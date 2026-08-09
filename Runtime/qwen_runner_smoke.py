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


if __name__ == "__main__":
    unittest.main()
