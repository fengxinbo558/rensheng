#!/usr/bin/env python3
"""Local Qwen3-TTS runner with one-shot and persistent JSON-lines contracts."""

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
MIN_AUTOMATIC_OUTPUT_SECONDS = 15.0
MAX_AUTOMATIC_OUTPUT_SECONDS = 180.0
CURRENT_REQUEST_ID: str | None = None


class RunnerError(RuntimeError):
    """A user-facing runner failure."""


def emit(event: str, **payload: Any) -> None:
    if CURRENT_REQUEST_ID is not None and "requestId" not in payload:
        payload["requestId"] = CURRENT_REQUEST_ID
    print(
        json.dumps({"event": event, **payload}, ensure_ascii=False, separators=(",", ":")),
        flush=True,
    )


def build_parser(worker_mode: bool = False) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate local Mandarin WAV files")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--reference-audio", required=not worker_mode)
    parser.add_argument("--reference-text", required=not worker_mode)
    parser.add_argument("--text", required=not worker_mode)
    parser.add_argument("--output", required=not worker_mode)
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
    parser.add_argument("--max-output-seconds", type=float)
    parser.add_argument(
        "--voice-conditioning",
        choices=("speaker_embedding", "icl"),
        default="speaker_embedding",
        help=(
            "speaker_embedding avoids ICL reference-tail echoes; "
            "icl preserves the legacy full-reference continuation"
        ),
    )
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
    if (
        arguments.max_output_seconds is not None
        and not 1.0 <= arguments.max_output_seconds <= 600.0
    ):
        raise RunnerError("maximum output duration must be between 1 and 600 seconds")


def output_duration_limit(arguments: argparse.Namespace) -> float:
    if arguments.max_output_seconds is not None:
        return float(arguments.max_output_seconds)
    estimated = len(arguments.text.strip()) * 0.75 + 6.0
    return float(
        min(
            MAX_AUTOMATIC_OUTPUT_SECONDS,
            max(MIN_AUTOMATIC_OUTPUT_SECONDS, estimated),
        )
    )


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


def load_qwen_model(arguments: argparse.Namespace) -> tuple[Any, float]:
    from mlx_audio.tts.utils import load_model

    emit("loading")
    load_started = time.monotonic()
    with contextlib.redirect_stdout(sys.stderr):
        model = load_model(str(Path(arguments.model_dir).expanduser()))
    return model, time.monotonic() - load_started


def reference_text_for_model(arguments: argparse.Namespace) -> str | None:
    """Keep the transcript for profile validation, but not for clean x-vector cloning.

    Qwen ICL conditioning can repeat the last words of the reference transcript at
    the beginning of every generated segment. The 0.6B MLX model has a dedicated
    speaker encoder, so the default path uses that embedding without feeding the
    reference words into the generation context.
    """
    if arguments.voice_conditioning == "speaker_embedding":
        return None
    return arguments.reference_text.strip()


def generate_audio_with_model(
    arguments: argparse.Namespace,
    model: Any,
    reference: Any,
    reference_duration: float,
    model_load_seconds: float,
) -> tuple[Any, int, dict[str, Any]]:
    import mlx.core as mx
    import numpy as np

    sample_rate = int(model.sample_rate)

    mx.clear_cache()
    mx.reset_peak_memory()
    mx.random.seed(arguments.seed)
    generation_started = time.monotonic()
    first_audio_seconds: float | None = None
    chunks = []
    total_samples = 0
    safety_limit_seconds = output_duration_limit(arguments)
    maximum_samples = int(math.ceil(safety_limit_seconds * sample_rate))

    with contextlib.redirect_stdout(sys.stderr):
        results = iter(model.generate(
            text=arguments.text.strip(),
            voice=None,
            ref_audio=reference,
            ref_text=reference_text_for_model(arguments),
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
        total_samples += int(audio.size)
        if total_samples > maximum_samples:
            raise RunnerError("生成结果异常过长，已自动停止；请重试或缩短文字")
        chunks.append(audio)
        emit("progress", chunks=len(chunks), samples=total_samples)

    generation_seconds = time.monotonic() - generation_started
    if not chunks:
        raise RunnerError("Qwen returned no audio")
    audio = np.concatenate(chunks)
    if not np.all(np.isfinite(audio)):
        raise RunnerError("Qwen output contains invalid samples")
    peak_memory_gb = float(mx.get_peak_memory() / 1e9)
    metrics = {
        "modelLoadSeconds": model_load_seconds,
        "firstAudioSeconds": first_audio_seconds,
        "generationSeconds": generation_seconds,
        "chunkCount": len(chunks),
        "qwenPeakMemoryGB": peak_memory_gb,
        "rawDuration": float(audio.size / sample_rate),
        "safetyLimitSeconds": safety_limit_seconds,
        "voiceConditioning": arguments.voice_conditioning,
    }

    del results
    gc.collect()
    mx.clear_cache()
    return audio, sample_rate, metrics


def generate_audio(arguments: argparse.Namespace) -> tuple[Any, int, dict[str, Any]]:
    import mlx.core as mx

    model, load_seconds = load_qwen_model(arguments)
    sample_rate = int(model.sample_rate)
    reference, reference_duration = prepare_reference(arguments, sample_rate)
    emit(
        "model_loaded",
        seconds=load_seconds,
        sampleRate=sample_rate,
        referenceDuration=reference_duration,
    )
    try:
        return generate_audio_with_model(
            arguments,
            model,
            reference,
            reference_duration,
            load_seconds,
        )
    finally:
        del model
        del reference
        gc.collect()
        mx.clear_cache()


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


def required_worker_string(message: dict[str, Any], key: str) -> str:
    value = message.get(key)
    if not isinstance(value, str) or not value.strip():
        raise RunnerError(f"worker request requires {key}")
    return value


def worker_arguments(
    base: argparse.Namespace,
    message: dict[str, Any],
) -> argparse.Namespace:
    values = vars(base).copy()
    values.update(
        worker=False,
        reference_audio=required_worker_string(message, "referenceAudio"),
        reference_text=required_worker_string(message, "referenceText"),
        text=required_worker_string(message, "text"),
        output=required_worker_string(message, "output"),
        seed=int(message.get("seed", base.seed)),
        reference_start_seconds=float(
            message.get("referenceStartSeconds", base.reference_start_seconds)
        ),
        reference_duration_seconds=message.get(
            "referenceDurationSeconds", base.reference_duration_seconds
        ),
        reference_peak_dbfs=float(
            message.get("referencePeakDBFS", base.reference_peak_dbfs)
        ),
        max_output_seconds=message.get(
            "maxOutputSeconds", base.max_output_seconds
        ),
    )
    if values["reference_duration_seconds"] is not None:
        values["reference_duration_seconds"] = float(
            values["reference_duration_seconds"]
        )
    if values["max_output_seconds"] is not None:
        values["max_output_seconds"] = float(values["max_output_seconds"])
    return argparse.Namespace(**values)


def reference_cache_key(arguments: argparse.Namespace) -> tuple[Any, ...]:
    path = Path(arguments.reference_audio).expanduser().resolve()
    stat = path.stat()
    return (
        str(path),
        stat.st_size,
        stat.st_mtime_ns,
        arguments.reference_text.strip(),
        arguments.voice_conditioning,
        arguments.reference_start_seconds,
        arguments.reference_duration_seconds,
        arguments.reference_peak_dbfs,
    )


def emit_worker_failure(error: Exception) -> None:
    if isinstance(error, (RunnerError, FileNotFoundError, ValueError, TypeError)):
        detail = str(error)
    else:
        detail = f"local generation failed: {error}"
    emit("failed", error=detail)


def run_worker(arguments: argparse.Namespace) -> None:
    global CURRENT_REQUEST_ID

    model = None
    reference = None
    cached_reference_key: tuple[Any, ...] | None = None
    cached_reference_duration = 0.0
    load_seconds = 0.0
    sample_rate = DEFAULT_FINAL_SAMPLE_RATE

    if arguments.validate_only:
        model_dir = Path(arguments.model_dir).expanduser()
        if not model_dir.is_dir():
            raise RunnerError(f"model directory does not exist: {model_dir}")
        emit("worker_ready", validatedOnly=True)
    else:
        model, load_seconds = load_qwen_model(arguments)
        sample_rate = int(model.sample_rate)
        emit(
            "worker_ready",
            seconds=load_seconds,
            sampleRate=sample_rate,
            validatedOnly=False,
        )

    try:
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue
            request_id: str | None = None
            try:
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise RunnerError("worker request must be a JSON object")
                raw_request_id = message.get("requestId")
                if not isinstance(raw_request_id, str) or not raw_request_id.strip():
                    raise RunnerError("worker request requires requestId")
                request_id = raw_request_id.strip()
                CURRENT_REQUEST_ID = request_id
                command = message.get("command")
                if command == "shutdown":
                    emit("worker_stopped")
                    return
                if command != "synthesize":
                    raise RunnerError(f"unsupported worker command: {command}")

                request_arguments = worker_arguments(arguments, message)
                validate_arguments(request_arguments)
                if arguments.validate_only:
                    emit("validated")
                    continue

                requested_reference_key = reference_cache_key(request_arguments)
                if requested_reference_key != cached_reference_key:
                    reference, cached_reference_duration = prepare_reference(
                        request_arguments, sample_rate
                    )
                    cached_reference_key = requested_reference_key
                    emit(
                        "voice_prepared",
                        referenceDuration=cached_reference_duration,
                    )
                else:
                    emit(
                        "voice_reused",
                        referenceDuration=cached_reference_duration,
                    )

                audio, source_rate, generation_metrics = generate_audio_with_model(
                    request_arguments,
                    model,
                    reference,
                    cached_reference_duration,
                    0.0,
                )
                final_audio, final_rate, postprocess_metrics = postprocess_audio(
                    audio, source_rate, request_arguments
                )
                output_metrics = write_output(
                    final_audio,
                    final_rate,
                    Path(request_arguments.output).expanduser(),
                )
                emit(
                    "completed",
                    output=output_metrics,
                    generation=generation_metrics,
                    postprocess=postprocess_metrics,
                    workerModelLoadSeconds=load_seconds,
                    processMaxRSSBytes=int(
                        resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
                    ),
                )
            except Exception as error:
                CURRENT_REQUEST_ID = request_id
                emit_worker_failure(error)
            finally:
                CURRENT_REQUEST_ID = None
    finally:
        if model is not None:
            del model
        if reference is not None:
            del reference
        gc.collect()
        if not arguments.validate_only:
            import mlx.core as mx

            mx.clear_cache()


def main(argv: Sequence[str] | None = None) -> int:
    raw_arguments = list(argv) if argv is not None else sys.argv[1:]
    parser = build_parser(worker_mode="--worker" in raw_arguments)
    arguments = parser.parse_args(raw_arguments)
    try:
        if arguments.worker:
            run_worker(arguments)
        else:
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
