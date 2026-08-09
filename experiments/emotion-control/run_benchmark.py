#!/usr/bin/env python3
"""Run the isolated CosyVoice emotion benchmark without persisting private inputs."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
from typing import Any

from audio_metrics import inspect_pcm_wav
from benchmark_contract import REQUIRED_EMOTIONS, load_manifest, safe_output_path
from emotion_prompts import build_emotion_prompt


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = Path(__file__).with_name("benchmark-manifest.json")
DEFAULT_PROBE = PROJECT_ROOT / ".emotion-runtime/swift-probe-build/release/emotion-cosy-probe"
DEFAULT_MODEL = PROJECT_ROOT / ".emotion-models/CosyVoice3-0.5B-MLX-8bit-full"
DEFAULT_CAMPP = PROJECT_ROOT / ".emotion-models/CamPlusPlus-Speaker-CoreML"
DEFAULT_RESULTS = Path(__file__).with_name("results")
MODEL_ID = "aufklarer/CosyVoice3-0.5B-MLX-8bit-full"
MODEL_REVISION = "b52fc1c3bf5f3b947d40c250639e5ebe347ece11"
_MEMORY_PATTERN = re.compile(r"^\s*(\d+)\s+maximum resident set size\s*$", re.MULTILINE)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _parse_events(stdout: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and isinstance(value.get("event"), str):
            events.append(value)
    return events


def _peak_memory(stderr: str) -> int | None:
    matches = _MEMORY_PATTERN.findall(stderr)
    return int(matches[-1]) if matches else None


def _failure_summary(stderr: str, private_values: tuple[str, ...]) -> str:
    summary = " ".join(stderr.strip().split())[-500:]
    for value in private_values:
        if value:
            summary = summary.replace(value, "[已隐藏]")
    return summary


def build_jobs(
    manifest: dict[str, Any],
    utterances_per_emotion: int,
    emotions: tuple[str, ...],
) -> list[tuple[str, int, str, str]]:
    selected = set(emotions)
    jobs: list[tuple[str, int, str, str]] = []
    for entry in manifest["emotions"]:
        emotion = entry["id"]
        if emotion not in selected:
            continue
        instruction = build_emotion_prompt(emotion, manifest["intensity"]).instruction
        for index, text in enumerate(entry["texts"][:utterances_per_emotion], start=1):
            jobs.append((emotion, index, text, instruction))
    return jobs


def run_benchmark(arguments: argparse.Namespace) -> Path:
    manifest = load_manifest(arguments.manifest)
    if not 1 <= arguments.utterances_per_emotion <= 3:
        raise ValueError("utterances-per-emotion must be between 1 and 3")
    unknown = set(arguments.emotions) - set(REQUIRED_EMOTIONS)
    if unknown:
        raise ValueError(f"unsupported emotions: {', '.join(sorted(unknown))}")
    if not arguments.probe.is_file():
        raise FileNotFoundError(f"probe not found: {arguments.probe}")
    if not arguments.reference_audio.is_file():
        raise FileNotFoundError("reference audio not found")
    if not arguments.reference_text.strip():
        raise ValueError("reference text must not be blank")

    session_name = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    session_root = arguments.results_root / session_name
    audio_root = session_root / "audio"
    audio_root.mkdir(parents=True, exist_ok=False)

    reference_hash = _sha256(arguments.reference_audio)
    answer_key: list[dict[str, Any]] = []
    results: list[dict[str, Any]] = []
    jobs = build_jobs(manifest, arguments.utterances_per_emotion, arguments.emotions)
    for job_index, (emotion, text_index, text, instruction) in enumerate(jobs, start=1):
        anonymous_name = f"sample-{secrets.token_hex(6)}.wav"
        output = safe_output_path(audio_root, anonymous_name, arguments.reference_audio)
        command = [
            "/usr/bin/time", "-l", str(arguments.probe),
            "--model-id", MODEL_ID,
            "--model-dir", str(arguments.model_directory),
            "--campp-dir", str(arguments.campp_directory),
            "--reference-audio", str(arguments.reference_audio),
            "--reference-text", arguments.reference_text,
            "--text", text,
            "--instruction", instruction,
            "--output", str(output),
            "--seed", str(arguments.seed + job_index - 1),
        ]
        started = time.monotonic()
        completed = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        elapsed = time.monotonic() - started
        events = _parse_events(completed.stdout)
        item: dict[str, Any] = {
            "sample": anonymous_name,
            "exitCode": completed.returncode,
            "wallSeconds": round(elapsed, 6),
            "peakMemoryBytes": _peak_memory(completed.stderr),
            "events": events,
        }
        if completed.returncode == 0:
            item["audio"] = inspect_pcm_wav(output).as_json()
        else:
            item["failure"] = _failure_summary(
                completed.stderr,
                (str(arguments.reference_audio), arguments.reference_text, text),
            )
        results.append(item)
        answer_key.append({
            "sample": anonymous_name,
            "emotion": emotion,
            "textIndex": text_index,
        })
        print(
            json.dumps(
                {
                    "event": "sample_completed" if completed.returncode == 0 else "sample_failed",
                    "current": job_index,
                    "total": len(jobs),
                    "sample": anonymous_name,
                },
                ensure_ascii=False,
            ),
            flush=True,
        )

    report = {
        "schemaVersion": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "modelID": MODEL_ID,
        "modelRevision": MODEL_REVISION,
        "promptVersion": manifest["promptVersion"],
        "intensity": manifest["intensity"],
        "seed": arguments.seed,
        "referenceSHA256": reference_hash,
        "referenceAudioPersisted": False,
        "results": results,
    }
    (session_root / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (session_root / "answer-key.json").write_text(
        json.dumps(answer_key, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"event": "benchmark_completed", "directory": str(session_root)}, ensure_ascii=False))
    return session_root


def parse_arguments(values: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-audio", type=Path, required=True)
    parser.add_argument("--reference-text", required=True)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--probe", type=Path, default=DEFAULT_PROBE)
    parser.add_argument("--model-directory", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--campp-directory", type=Path, default=DEFAULT_CAMPP)
    parser.add_argument("--results-root", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--utterances-per-emotion", type=int, default=3)
    parser.add_argument("--emotions", nargs="+", default=list(REQUIRED_EMOTIONS))
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args(values)


def main() -> int:
    try:
        run_benchmark(parse_arguments())
    except Exception as error:
        print(json.dumps({"event": "benchmark_failed", "message": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
