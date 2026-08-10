#!/usr/bin/env python3
"""Run two real requests through one Qwen worker and save a metrics manifest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from typing import Any


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", required=True)
    parser.add_argument("--runner", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--deepfilter-model", required=True)
    parser.add_argument("--reference-audio", required=True)
    parser.add_argument("--reference-text", required=True)
    parser.add_argument("--output-dir", required=True)
    return parser


def read_event(process: subprocess.Popen[str]) -> dict[str, Any]:
    if process.stdout is None:
        raise RuntimeError("worker stdout is unavailable")
    line = process.stdout.readline()
    if not line:
        detail = process.stderr.read() if process.stderr is not None else ""
        raise RuntimeError(f"worker stopped before an event: {detail[-1000:]}")
    value = json.loads(line)
    if not isinstance(value, dict):
        raise RuntimeError("worker event is not an object")
    return value


def send(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    if process.stdin is None:
        raise RuntimeError("worker stdin is unavailable")
    process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
    process.stdin.flush()


def run_request(
    process: subprocess.Popen[str],
    request_id: str,
    text: str,
    output: Path,
    reference_audio: Path,
    reference_text: str,
    seed: int,
) -> dict[str, Any]:
    started = time.monotonic()
    send(
        process,
        {
            "command": "synthesize",
            "requestId": request_id,
            "referenceAudio": str(reference_audio),
            "referenceText": reference_text,
            "text": text,
            "output": str(output),
            "seed": seed,
        },
    )
    events: list[dict[str, Any]] = []
    while True:
        event = read_event(process)
        if event.get("requestId") != request_id:
            continue
        events.append(event)
        if event.get("event") == "failed":
            raise RuntimeError(str(event.get("error", "worker request failed")))
        if event.get("event") == "completed":
            return {
                "requestId": request_id,
                "text": text,
                "elapsedSeconds": time.monotonic() - started,
                "events": events,
                "output": str(output),
            }


def main() -> int:
    arguments = build_parser().parse_args()
    output_dir = Path(arguments.output_dir).expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(
        [
            arguments.python,
            arguments.runner,
            "--worker",
            "--model-dir",
            arguments.model_dir,
            "--deepfilter-model",
            arguments.deepfilter_model,
            "--deepfilter-wet",
            "0.0",
            "--streaming-interval",
            "2",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    ready_started = time.monotonic()
    try:
        startup_events: list[dict[str, Any]] = []
        while True:
            ready = read_event(process)
            startup_events.append(ready)
            if ready.get("event") == "worker_ready":
                break
            if ready.get("event") != "loading":
                raise RuntimeError(f"unexpected startup event: {ready}")
        ready_elapsed = time.monotonic() - ready_started
        reference_audio = Path(arguments.reference_audio).expanduser()
        requests = [
            run_request(
                process,
                "continuous-1",
                "今天我们先讲一个简单的概念。人声听起来是否自然，不只取决于音色，还取决于气息、重音、节奏和上下文是否连续。如果每说一个短句就重新开始，听众很快就会感到不自然。",
                output_dir / "01-连续人声.wav",
                reference_audio,
                arguments.reference_text,
                42,
            ),
            run_request(
                process,
                "continuous-2",
                "因此，这一版把相邻的完整句子放在同一个语义段里，并让模型在一次任务中保持常驻。这样既可以减少重复加载，也能让一整段话共享更完整的表达节奏。下一步，我们再通过真实试听判断它是否真的更像人说话。",
                output_dir / "02-连续人声.wav",
                reference_audio,
                arguments.reference_text,
                43,
            ),
        ]
        send(process, {"command": "shutdown", "requestId": "shutdown"})
        stopped = read_event(process)
        if stopped.get("event") != "worker_stopped":
            raise RuntimeError(f"unexpected shutdown event: {stopped}")
        return_code = process.wait(timeout=30)
        manifest = {
            "workerReady": ready,
            "startupEvents": startup_events,
            "workerReadyElapsedSeconds": ready_elapsed,
            "workerReadyCount": 1,
            "requests": requests,
            "returnCode": return_code,
        }
        manifest_path = output_dir / "metrics.json"
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
        return 0
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        if process.stdin is not None:
            process.stdin.close()
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()


if __name__ == "__main__":
    raise SystemExit(main())
