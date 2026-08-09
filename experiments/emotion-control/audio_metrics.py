#!/usr/bin/env python3
"""Dependency-free PCM WAV integrity checks for benchmark outputs."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import math
from pathlib import Path
import struct
import wave


class AudioValidationError(ValueError):
    """Raised when a candidate cannot be treated as a valid benchmark result."""


@dataclass(frozen=True)
class AudioMetrics:
    sha256: str
    duration_seconds: float
    sample_rate: int
    channels: int
    sample_width_bits: int
    peak: float
    rms: float

    def as_json(self) -> dict[str, object]:
        return asdict(self)


def _decode_pcm(raw: bytes, sample_width: int) -> list[int]:
    if sample_width == 1:
        return [value - 128 for value in raw]
    if sample_width == 2:
        return list(struct.unpack(f"<{len(raw) // 2}h", raw))
    if sample_width == 3:
        values: list[int] = []
        for offset in range(0, len(raw), 3):
            packed = raw[offset : offset + 3]
            value = int.from_bytes(packed, "little", signed=False)
            if value & 0x800000:
                value -= 1 << 24
            values.append(value)
        return values
    if sample_width == 4:
        return list(struct.unpack(f"<{len(raw) // 4}i", raw))
    raise AudioValidationError(f"unsupported PCM sample width: {sample_width}")


def inspect_pcm_wav(path: Path) -> AudioMetrics:
    try:
        with wave.open(str(path), "rb") as wav_file:
            if wav_file.getcomptype() != "NONE":
                raise AudioValidationError("WAV must contain uncompressed PCM")
            channels = wav_file.getnchannels()
            sample_rate = wav_file.getframerate()
            sample_width = wav_file.getsampwidth()
            frame_count = wav_file.getnframes()
            raw = wav_file.readframes(frame_count)
    except (OSError, EOFError, wave.Error) as error:
        raise AudioValidationError(f"cannot read WAV: {error}") from error

    if channels != 1:
        raise AudioValidationError("benchmark WAV must be mono")
    if sample_rate < 16_000 or sample_rate > 96_000:
        raise AudioValidationError("sample rate is outside benchmark range")
    if frame_count <= 0:
        raise AudioValidationError("WAV contains no audio frames")
    samples = _decode_pcm(raw, sample_width)
    if not samples:
        raise AudioValidationError("WAV contains no samples")

    scale = float(1 << (sample_width * 8 - 1))
    normalized = [sample / scale for sample in samples]
    peak = max(abs(sample) for sample in normalized)
    rms = math.sqrt(sum(sample * sample for sample in normalized) / len(normalized))
    duration = frame_count / float(sample_rate)
    if duration < 0.2:
        raise AudioValidationError("WAV is too short to be a generated utterance")
    if rms < 1e-5:
        raise AudioValidationError("WAV is effectively silent")

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return AudioMetrics(
        sha256=digest,
        duration_seconds=round(duration, 6),
        sample_rate=sample_rate,
        channels=channels,
        sample_width_bits=sample_width * 8,
        peak=round(peak, 8),
        rms=round(rms, 8),
    )


def finalize_wav(temporary_path: Path, output_path: Path) -> AudioMetrics:
    metrics = inspect_pcm_wav(temporary_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path.replace(output_path)
    return metrics
