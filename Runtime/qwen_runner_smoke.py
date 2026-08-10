#!/usr/bin/env python3
"""Fast contract tests for the local Qwen runner without loading MLX."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


RUNNER = Path(__file__).with_name("qwen_runner.py")


class QwenRunnerContractTests(unittest.TestCase):
    def run_runner(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(RUNNER), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_required_arguments_are_enforced(self) -> None:
        result = self.run_runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required", result.stderr.lower())

    def test_validate_only_accepts_project_relative_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model = root / "model"
            model.mkdir()
            reference = root / "reference.wav"
            reference.write_bytes(b"not-decoded-during-validation")
            output = root / "result.wav"

            result = self.run_runner(
                "--model-dir",
                str(model),
                "--reference-audio",
                str(reference),
                "--reference-text",
                "你好，这是参考原文。",
                "--text",
                "这是一段测试文字。",
                "--output",
                str(output),
                "--validate-only",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(events[-1]["event"], "validated")
            self.assertFalse(output.exists())

    def test_blank_text_is_rejected_before_model_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model = root / "model"
            model.mkdir()
            reference = root / "reference.wav"
            reference.write_bytes(b"placeholder")

            result = self.run_runner(
                "--model-dir",
                str(model),
                "--reference-audio",
                str(reference),
                "--reference-text",
                "参考原文",
                "--text",
                "   ",
                "--output",
                str(root / "result.wav"),
                "--validate-only",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("target text", result.stderr.lower())

    def test_invalid_processing_values_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model = root / "model"
            model.mkdir()
            reference = root / "reference.wav"
            reference.write_bytes(b"placeholder")

            result = self.run_runner(
                "--model-dir",
                str(model),
                "--reference-audio",
                str(reference),
                "--reference-text",
                "参考原文",
                "--text",
                "目标文字",
                "--output",
                str(root / "result.wav"),
                "--streaming-interval",
                "0",
                "--deepfilter-wet",
                "1.5",
                "--validate-only",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("streaming interval", result.stderr.lower())

    def test_invalid_output_duration_limit_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model = root / "model"
            model.mkdir()
            reference = root / "reference.wav"
            reference.write_bytes(b"placeholder")

            result = self.run_runner(
                "--model-dir",
                str(model),
                "--reference-audio",
                str(reference),
                "--reference-text",
                "参考原文",
                "--text",
                "目标文字",
                "--output",
                str(root / "result.wav"),
                "--max-output-seconds",
                "0",
                "--validate-only",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("maximum output duration", result.stderr.lower())

    def test_persistent_worker_validates_multiple_requests(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model = root / "model"
            model.mkdir()
            reference = root / "reference.wav"
            reference.write_bytes(b"placeholder")
            process = subprocess.Popen(
                [
                    sys.executable,
                    str(RUNNER),
                    "--worker",
                    "--validate-only",
                    "--model-dir",
                    str(model),
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertIsNotNone(process.stdin)
            self.assertIsNotNone(process.stdout)
            assert process.stdin is not None
            assert process.stdout is not None

            ready = json.loads(process.stdout.readline())
            self.assertEqual(ready["event"], "worker_ready")
            self.assertTrue(ready["validatedOnly"])

            for index in range(2):
                request_id = f"request-{index}"
                process.stdin.write(
                    json.dumps(
                        {
                            "command": "synthesize",
                            "requestId": request_id,
                            "referenceAudio": str(reference),
                            "referenceText": "参考原文",
                            "text": f"第{index + 1}段目标文字。",
                            "output": str(root / f"result-{index}.wav"),
                            "seed": 42 + index,
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                process.stdin.flush()
                validated = json.loads(process.stdout.readline())
                self.assertEqual(validated["event"], "validated")
                self.assertEqual(validated["requestId"], request_id)

            process.stdin.write(
                json.dumps(
                    {"command": "shutdown", "requestId": "shutdown-request"}
                )
                + "\n"
            )
            process.stdin.flush()
            stopped = json.loads(process.stdout.readline())
            self.assertEqual(stopped["event"], "worker_stopped")
            self.assertEqual(stopped["requestId"], "shutdown-request")
            self.assertEqual(process.wait(timeout=5), 0)
            process.stdin.close()
            process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()

    def test_persistent_worker_reports_request_error_and_stays_alive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model = root / "model"
            model.mkdir()
            reference = root / "reference.wav"
            reference.write_bytes(b"placeholder")
            process = subprocess.Popen(
                [
                    sys.executable,
                    str(RUNNER),
                    "--worker",
                    "--validate-only",
                    "--model-dir",
                    str(model),
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert process.stdin is not None
            assert process.stdout is not None
            json.loads(process.stdout.readline())
            process.stdin.write(
                json.dumps(
                    {
                        "command": "synthesize",
                        "requestId": "bad-request",
                        "referenceAudio": str(reference),
                        "referenceText": "参考原文",
                        "text": "   ",
                        "output": str(root / "invalid.wav"),
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
            process.stdin.flush()
            failed = json.loads(process.stdout.readline())
            self.assertEqual(failed["event"], "failed")
            self.assertEqual(failed["requestId"], "bad-request")
            self.assertIn("text", failed["error"].lower())

            process.stdin.write(
                json.dumps(
                    {"command": "shutdown", "requestId": "shutdown-request"}
                )
                + "\n"
            )
            process.stdin.flush()
            self.assertEqual(
                json.loads(process.stdout.readline())["event"], "worker_stopped"
            )
            self.assertEqual(process.wait(timeout=5), 0)
            process.stdin.close()
            process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()


if __name__ == "__main__":
    unittest.main()
