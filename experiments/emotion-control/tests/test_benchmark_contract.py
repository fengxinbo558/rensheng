from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest
import wave


EXPERIMENT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPERIMENT_ROOT))

from audio_metrics import AudioValidationError, finalize_wav, inspect_pcm_wav
from benchmark_contract import ContractError, load_manifest, safe_output_path
from emotion_prompts import PROMPT_VERSION, build_emotion_prompt


class BenchmarkContractTests(unittest.TestCase):
    def test_fixed_manifest_is_valid(self) -> None:
        manifest = load_manifest(EXPERIMENT_ROOT / "benchmark-manifest.json")
        self.assertEqual(manifest["promptVersion"], PROMPT_VERSION)
        self.assertEqual(len(manifest["emotions"]), 5)

    def test_manifest_rejects_missing_emotion(self) -> None:
        source = json.loads(
            (EXPERIMENT_ROOT / "benchmark-manifest.json").read_text(encoding="utf-8")
        )
        source["emotions"] = source["emotions"][:-1]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(ContractError, "fixed five"):
                load_manifest(path)

    def test_prompt_rejects_unknown_emotion_and_intensity(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported emotion"):
            build_emotion_prompt("surprised")
        with self.assertRaisesRegex(ValueError, "unsupported intensity"):
            build_emotion_prompt("happy", "maximum")

    def test_prompt_preserves_identity_without_exposing_model_delimiter(self) -> None:
        prompt = build_emotion_prompt("angry", "clear")
        self.assertIn("保持参考录音中同一个人的音色与身份", prompt.instruction)
        self.assertNotIn("<|endofprompt|>", prompt.instruction)
        self.assertNotIn("You are a helpful assistant", prompt.instruction)

    def test_natural_prompt_never_asks_for_emotion_intensity(self) -> None:
        prompt = build_emotion_prompt("natural", "strong")
        self.assertNotIn("只带一点情绪", prompt.instruction)
        self.assertNotIn("情绪清楚", prompt.instruction)
        self.assertNotIn("情绪更强", prompt.instruction)
        self.assertIn("不要播音、朗诵或表演", prompt.instruction)

    def test_subtle_emotions_are_bounded_as_daily_conversation(self) -> None:
        angry = build_emotion_prompt("angry", "subtle").instruction
        excited = build_emotion_prompt("excited", "subtle").instruction
        self.assertIn("只带一点情绪", angry)
        self.assertIn("不要吼叫", angry)
        self.assertIn("保持日常对话", excited)
        self.assertIn("不要喊叫", excited)

    def test_output_must_stay_inside_results_and_not_replace_reference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reference = root / "reference.wav"
            reference.touch()
            results = root / "results"
            valid = safe_output_path(results, "blind/001.wav", reference)
            self.assertEqual(valid, (results / "blind" / "001.wav").resolve())
            with self.assertRaisesRegex(ContractError, "escapes"):
                safe_output_path(results, "../reference.wav", reference)
            with self.assertRaisesRegex(ContractError, "wav"):
                safe_output_path(results, "001.mp3", reference)

    def test_pcm_wav_is_measured_then_atomically_finalized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            temporary = root / "candidate.tmp.wav"
            output = root / "results" / "candidate.wav"
            samples = [0, 4000, -4000, 2000, -2000] * 4800
            with wave.open(str(temporary), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(24_000)
                for sample in samples:
                    wav_file.writeframesraw(sample.to_bytes(2, "little", signed=True))
            metrics = finalize_wav(temporary, output)
            self.assertFalse(temporary.exists())
            self.assertTrue(output.exists())
            self.assertEqual(metrics.sample_rate, 24_000)
            self.assertGreater(metrics.rms, 0)
            self.assertEqual(inspect_pcm_wav(output).sha256, metrics.sha256)

    def test_silent_wav_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "silent.wav"
            with wave.open(str(path), "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(24_000)
                wav_file.writeframes(bytes(24_000 * 2))
            with self.assertRaisesRegex(AudioValidationError, "silent"):
                inspect_pcm_wav(path)


if __name__ == "__main__":
    unittest.main()
