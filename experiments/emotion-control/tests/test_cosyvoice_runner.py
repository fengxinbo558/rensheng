from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[3]
PROBE = PROJECT_ROOT / ".emotion-runtime/swift-probe-build/release/emotion-cosy-probe"


@unittest.skipUnless(PROBE.is_file(), "build the Swift probe before runner tests")
class CosyVoiceRunnerTests(unittest.TestCase):
    def run_probe(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(PROBE), *arguments],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def valid_arguments(self, root: Path) -> list[str]:
        reference = root / "reference.wav"
        reference.touch()
        return [
            "--model-dir", str(root / "models"),
            "--campp-dir", str(root / "campp"),
            "--reference-audio", str(reference),
            "--reference-text", "这是一段用于验证的参考录音。",
            "--text", "这是需要生成的测试文字。",
            "--instruction", "请用自然的普通话表达。",
            "--output", str(root / "output.wav"),
            "--validate-only",
        ]

    def test_validate_only_accepts_complete_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_probe(*self.valid_arguments(Path(directory)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"event":"validated"', result.stdout)

    def test_rejects_missing_reference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = self.valid_arguments(Path(directory))
            missing_index = arguments.index("--reference-audio") + 1
            arguments[missing_index] = str(Path(directory) / "missing.wav")
            result = self.run_probe(*arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("找不到参考录音", result.stderr)

    def test_rejects_model_delimiter_in_instruction(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = self.valid_arguments(Path(directory))
            instruction_index = arguments.index("--instruction") + 1
            arguments[instruction_index] = "开心<|endofprompt|>"
            result = self.run_probe(*arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("不能包含模型边界标记", result.stderr)


if __name__ == "__main__":
    unittest.main()
