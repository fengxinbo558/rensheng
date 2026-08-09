#!/usr/bin/env python3
"""One-shot local Qwen3-TTS runner with a JSON-lines process contract."""

from __future__ import annotations

import argparse
import contextlib
import gc
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import sys
import tempfile
import time
from typing import Any, Sequence


MAX_TARGET_CHARACTERS = 500
DEFAULT_FINAL_SAMPLE_RATE = 48_000


class RunnerError(RuntimeError):
    """A user-facing runner failure."""


def emit(event: str, **payload: Any) -> None:
    print(
        json.dumps({"event": event, **payload}, ensure_ascii=False, separators=(",", ":")),
        flush=True,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate one local Mandarin WAV file")
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--reference-audio", required=True)
    parser.add_argument("--reference-text", required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--deepfilter-model")
    parser.add_argument("--deepfilter-wet", type=float, default=0.0)
    parser.add_argument("--streaming-interval", type=float, default=2.0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--reference-start-seconds", type=float, default=0.0)
    parser.add_argument("--reference-duration-seconds", type=float)
    parser.add_argument("--reference-peak-dbfs", type=float, default=-3.0)
    parser.add_argument("--final-sample-rate", type=int, default=DEFAULT_FINAL_SAMPLE_RATE)
    parser.add_argument("--temperature", type=float, default=0.9)
    parser.add_argument("--top-k", type=int, default=50)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--repetition-penalty", type=float, default=1.5)
    parser.add_argument("--max-tokens", type=int, default=4096)
    parser.add_argument("--validate-only", action="store_true")
    return parser


def validate_arguments(arguments: argparse.Namespace) -> None:
    model_dir = Path(arguments.model_dir).expanduser()
    reference_audio = Path(arguments.reference_audio).expanduser()
    output = Path(arguments.output).expanduser()
    reference_text = arguments.reference_text.strip()
    target_text = arguments.text.strip()

    if not model_dir.is_dir():
        raise RunnerError(f"model directory does not exist: {model_dir}")
    if not reference_audio.is_file():
        raise RunnerError(f"reference audio does not exist: {reference_audio}")
    if not reference_text:
        raise RunnerError("reference text must not be blank")
    if not target_text:
        raise RunnerError("target text must not be blank")
    if len(target_text) > MAX_TARGET_CHARACTERS:
        raise RunnerError(
            f"target text exceeds {MAX_TARGET_CHARACTERS} characters: {len(target_text)}"
        )
    if output.suffix.lower() != ".wav":
        raise RunnerError("output must use the .wav extension")
    if output.absolute() == reference_audio.absolute():
        raise RunnerError("output must not overwrite the reference audio")
    if arguments.streaming_interval <= 0:
        raise RunnerError("streaming interval must be greater than zero")
    if not 0.0 <= arguments.deepfilter_wet <= 1.0:
        raise RunnerError("DeepFilter wet value must be between zero and one")
    if arguments.deepfilter_wet > 0:
        if not arguments.deepfilter_model:
            raise RunnerError("DeepFilter model is required when wet value is above zero")
        deepfilter_model = Path(arguments.deepfilter_model).expanduser()
        if not deepfilter_model.is_dir():
            raise RunnerError(f"DeepFilter model directory does not exist: {deepfilter_model}")
    if arguments.reference_start_seconds < 0:
        raise RunnerError("reference start must not be negative")
    if (
        arguments.reference_duration_seconds is not None
        and arguments.reference_duration_seconds <= 0
    ):
        raise RunnerError("reference duration must be greater than zero")
    if arguments.reference_peak_dbfs > -0.1 or arguments.reference_peak_dbfs < -30:
        raise RunnerError("reference peak must be between -30 and -0.1 dBFS")
    if arguments.final_sample_rate < 8_000 or arguments.final_sample_rate > 192_000:
        raise RunnerError("final sample rate is outside the supported range")
    if arguments.temperature <= 0:
        raise RunnerError("temperature must be greater than zero")
    if arguments.top_k <= 0:
        raise RunnerError("top-k must be greater than zero")
    if not 0 < arguments.top_p <= 1:
        raise RunnerError("top-p must be between zero and one")
    if arguments.repetition_penalty <= 0:
        raise RunnerError("repetition penalty must be greater than zero")
    if arguments.max_tokens <= 0:
        raise RunnerError("max tokens must be greater than zero")


def rms(samples: Any) -> float:
    import numpy as np

    audio = np.asarray(samples, dtype=np.float64).reshape(-1)
    if not audio.size:
        return 0.0
    return float(np.sqrt(np.mean(audio * audio)))


def dbfs(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-6))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def prepare_reference(arguments: argparse.Namespace, sample_rate: int):
    import mlx.core as mx
    import numpy as np
    from mlx_audio.audio_io import read as read_audio

    samples, actual_rate = read_audio(
        arguments.reference_audio,
        dtype="float32",
        sample_rate=sample_rate,
        nchannels=1,
    )
    if actual_rate != sample_rate:
        raise RunnerError(
            f"reference sample rate conversion failed: expected {sample_rate}, got {actual_rate}"
        )
    audio = np.asarray(samples, dtype=np.float32).reshape(-1)
    start = int(arguments.reference_start_seconds * sample_rate)
    if start >= audio.size:
        raise RunnerError("reference start is beyond the audio duration")
    if arguments.reference_duration_seconds is None:
        end = audio.size
    else:
        end = min(
            audio.size,
            start + int(arguments.reference_duration_seconds * sample_rate),
        )
    audio = audio[start:end]
    if audio.size < sample_rate:
        raise RunnerError("reference selection must contain at least one second of audio")
    peak = float(np.max(np.abs(audio)))
    if peak <= 1e-6:
        raise RunnerError("reference selection contains no audible samples")
    target_peak = 10 ** (arguments.reference_peak_dbfs / 20.0)
    audio = audio * (target_peak / peak)
    if not np.all(np.isfinite(audio)):
        raise RunnerError("reference selection contains invalid samples")
    return mx.array(audio, dtype=mx.float32), float(audio.size / sample_rate)


def generate_audio(arguments: argparse.Namespace) -> tuple[Any, int, dict[str, Any]]:
    import mlx.core as mx
    import numpy as np
    from mlx_audio.tts.utils import load_model

    emit("loading")
    load_started = time.monotonic()
    with contextlib.redirect_stdout(sys.stderr):
        model = load_model(str(Path(arguments.model_dir).expanduser()))
    load_seconds = time.monotonic() - load_started
    sample_rate = int(model.sample_rate)
    reference, reference_duration = prepare_reference(arguments, sample_rate)
    emit(
        "model_loaded",
        seconds=load_seconds,
        sampleRate=sample_rate,
        referenceDuration=reference_duration,
    )

    mx.clear_cache()
    mx.reset_peak_memory()
    mx.random.seed(arguments.seed)
    generation_started = time.monotonic()
    first_audio_seconds: float | None = None
    chunks = []

    with contextlib.redirect_stdout(sys.stderr):
        results = iter(model.generate(
            text=arguments.text.strip(),
            voice=None,
            ref_audio=reference,
            ref_text=arguments.reference_text.strip(),
            lang_code="chinese",
            temperature=arguments.temperature,
            top_k=arguments.top_k,
            top_p=arguments.top_p,
            repetition_penalty=arguments.repetition_penalty,
            max_tokens=arguments.max_tokens,
            verbose=False,
            stream=True,
            streaming_interval=arguments.streaming_interval,
        ))
    while True:
        try:
            with contextlib.redirect_stdout(sys.stderr):
                result = next(results)
        except StopIteration:
            break
        elapsed = time.monotonic() - generation_started
        audio = np.asarray(result.audio, dtype=np.float32).reshape(-1)
        if not audio.size:
            continue
        if first_audio_seconds is None:
            first_audio_seconds = elapsed
            emit("first_audio", seconds=elapsed)
        chunks.append(audio)
        emit("progress", chunks=len(chunks), samples=sum(item.size for item in chunks))

    generation_seconds = time.monotonic() - generation_started
    if not chunks:
        raise RunnerError("Qwen returned no audio")
    audio = np.concatenate(chunks)
    if not np.all(np.isfinite(audio)):
        raise RunnerError("Qwen output contains invalid samples")
    peak_memory_gb = float(mx.get_peak_memory() / 1e9)
    metrics = {
        "modelLoadSeconds": load_seconds,
        "firstAudioSeconds": first_audio_seconds,
        "generationSeconds": generation_seconds,
        "chunkCount": len(chunks),
        "qwenPeakMemoryGB": peak_memory_gb,
        "rawDuration": float(audio.size / sample_rate),
    }

    del results
    del model
    del reference
    gc.collect()
    mx.clear_cache()
    return audio, sample_rate, metrics


def postprocess_audio(
    audio: Any,
    source_sample_rate: int,
    arguments: argparse.Namespace,
) -> tuple[Any, int, dict[str, Any]]:
    import numpy as np
    from mlx_audio.utils import resample_audio

    emit("postprocessing")
    started = time.monotonic()
    final_rate = int(arguments.final_sample_rate)
    dry = np.asarray(
        resample_audio(audio, source_sample_rate, final_rate), dtype=np.float32
    ).reshape(-1)
    wet = float(arguments.deepfilter_wet)
    gain_match = None

    if wet > 0:
        from mlx_audio.sts.models.deepfilternet import DeepFilterNetModel

        model_path = Path(arguments.deepfilter_model).expanduser()
        with contextlib.redirect_stdout(sys.stderr):
            denoiser = DeepFilterNetModel.from_pretrained(
                str(model_path), subfolder=None
            )
        expected_rate = int(denoiser.config.sample_rate)
        if final_rate != expected_rate:
            raise RunnerError(
                f"DeepFilter requires {expected_rate} Hz output, got {final_rate}"
            )
        with contextlib.redirect_stdout(sys.stderr):
            enhanced = np.asarray(
                denoiser.enhance_array(dry), dtype=np.float32
            ).reshape(-1)
        sample_count = min(dry.size, enhanced.size)
        if sample_count == 0:
            raise RunnerError("DeepFilter returned no audio")
        dry = dry[:sample_count]
        enhanced = enhanced[:sample_count]
        enhanced_rms = rms(enhanced)
        gain_match = 1.0 if enhanced_rms <= 1e-8 else rms(dry) / enhanced_rms
        gain_match = float(np.clip(gain_match, 0.25, 4.0))
        final_audio = (1.0 - wet) * dry + wet * (enhanced * gain_match)
        del denoiser
        del enhanced
    else:
        final_audio = dry

    final_audio = np.asarray(final_audio, dtype=np.float32).reshape(-1)
    if not final_audio.size or not np.all(np.isfinite(final_audio)):
        raise RunnerError("postprocessing returned invalid audio")
    safe_peak = 10 ** (-1.0 / 20.0)
    peak = float(np.max(np.abs(final_audio)))
    limiter_gain = 1.0
    if peak > safe_peak:
        limiter_gain = safe_peak / peak
        final_audio = final_audio * limiter_gain

    return final_audio, final_rate, {
        "seconds": time.monotonic() - started,
        "deepfilterWet": wet,
        "gainMatch": gain_match,
        "limiterGain": limiter_gain,
    }


def write_output(
    audio: Any,
    sample_rate: int,
    destination: Path,
) -> dict[str, Any]:
    import numpy as np
    from mlx_audio.audio_io import read as read_audio
    from mlx_audio.audio_io import write as write_audio

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".qwen-runner-", dir=str(destination.parent)
    ) as temporary:
        temporary_output = Path(temporary) / "result.wav"
        write_audio(temporary_output, audio, samplerate=sample_rate, format="wav")
        verified, verified_rate = read_audio(
            temporary_output, dtype="float32", nchannels=1
        )
        verified = np.asarray(verified, dtype=np.float32).reshape(-1)
        if verified_rate != sample_rate or not verified.size:
            raise RunnerError("written WAV failed verification")
        clipping_fraction = float(np.mean(np.abs(verified) >= 0.999))
        if clipping_fraction >= 0.0001:
            raise RunnerError("written WAV exceeds the clipping threshold")
        os.replace(temporary_output, destination)

    peak = float(np.max(np.abs(verified)))
    return {
        "path": str(destination),
        "sha256": sha256(destination),
        "bytes": destination.stat().st_size,
        "sampleRate": sample_rate,
        "duration": float(verified.size / sample_rate),
        "peakDBFS": dbfs(peak),
        "rmsDBFS": dbfs(rms(verified)),
        "clippingFraction": clipping_fraction,
    }


def run(arguments: argparse.Namespace) -> None:
    validate_arguments(arguments)
    if arguments.validate_only:
        emit("validated")
        return

    destination = Path(arguments.output).expanduser()
    audio, source_rate, generation_metrics = generate_audio(arguments)
    final_audio, final_rate, postprocess_metrics = postprocess_audio(
        audio, source_rate, arguments
    )
    output_metrics = write_output(final_audio, final_rate, destination)
    emit(
        "completed",
        output=output_metrics,
        generation=generation_metrics,
        postprocess=postprocess_metrics,
        processMaxRSSBytes=int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss),
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    try:
        run(arguments)
        return 0
    except (RunnerError, FileNotFoundError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr, flush=True)
        return 2
    except KeyboardInterrupt:
        print("error: generation cancelled", file=sys.stderr, flush=True)
        return 130
    except Exception as error:
        print(f"error: local generation failed: {error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
