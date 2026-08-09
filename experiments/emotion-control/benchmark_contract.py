#!/usr/bin/env python3
"""Validation and safe-path helpers for the isolated emotion benchmark."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from emotion_prompts import PROMPT_VERSION, SUPPORTED_INTENSITIES, build_emotion_prompt


class ContractError(ValueError):
    """Raised when a benchmark input would make results unsafe or incomparable."""


REQUIRED_EMOTIONS = ("natural", "happy", "excited", "sad", "angry")


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"cannot read benchmark manifest: {error}") from error
    validate_manifest(manifest)
    return manifest


def validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("schemaVersion") != 1:
        raise ContractError("schemaVersion must be 1")
    if manifest.get("language") != "zh-CN":
        raise ContractError("language must be zh-CN")
    if manifest.get("promptVersion") != PROMPT_VERSION:
        raise ContractError(f"promptVersion must be {PROMPT_VERSION}")
    intensity = manifest.get("intensity")
    if intensity not in SUPPORTED_INTENSITIES:
        raise ContractError(f"unsupported manifest intensity: {intensity}")

    entries = manifest.get("emotions")
    if not isinstance(entries, list):
        raise ContractError("emotions must be a list")
    ids = [entry.get("id") for entry in entries if isinstance(entry, dict)]
    if tuple(ids) != REQUIRED_EMOTIONS:
        raise ContractError("emotions must contain the fixed five entries in benchmark order")

    for entry in entries:
        emotion = entry["id"]
        texts = entry.get("texts")
        if not isinstance(texts, list) or len(texts) != 3:
            raise ContractError(f"{emotion} must contain exactly three texts")
        for text in texts:
            if not isinstance(text, str) or not text.strip():
                raise ContractError(f"{emotion} contains blank text")
            if len(text.strip()) > 120:
                raise ContractError(f"{emotion} text exceeds 120 characters")
        build_emotion_prompt(emotion, intensity)


def safe_output_path(output_root: Path, relative_name: str, reference_audio: Path) -> Path:
    if not relative_name or Path(relative_name).is_absolute():
        raise ContractError("output name must be a relative WAV path")
    output_root = output_root.resolve()
    candidate = (output_root / relative_name).resolve()
    try:
        candidate.relative_to(output_root)
    except ValueError as error:
        raise ContractError("output escapes the benchmark result directory") from error
    if candidate.suffix.lower() != ".wav":
        raise ContractError("output must use the .wav extension")
    if candidate == reference_audio.resolve():
        raise ContractError("output must not overwrite reference audio")
    return candidate
