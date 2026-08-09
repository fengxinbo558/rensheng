from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


EXPERIMENT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPERIMENT_ROOT))
SPEC = importlib.util.spec_from_file_location("run_benchmark", EXPERIMENT_ROOT / "run_benchmark.py")
assert SPEC and SPEC.loader
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class BenchmarkRunnerTests(unittest.TestCase):
    def test_build_jobs_can_select_one_utterance_for_smoke_test(self) -> None:
        manifest = RUNNER.load_manifest(EXPERIMENT_ROOT / "benchmark-manifest.json")
        jobs = RUNNER.build_jobs(manifest, 1, ("natural", "happy"))
        self.assertEqual([job[0] for job in jobs], ["natural", "happy"])
        self.assertTrue(all("同一个人的音色" in job[3] for job in jobs))

    def test_event_parser_ignores_model_logs(self) -> None:
        events = RUNNER._parse_events('model log\n{"event":"validated"}\n')
        self.assertEqual(events, [{"event": "validated"}])

    def test_failure_summary_removes_private_values(self) -> None:
        summary = RUNNER._failure_summary(
            "failed at /private/voice.wav while reading 私密原文",
            ("/private/voice.wav", "私密原文"),
        )
        self.assertNotIn("/private/voice.wav", summary)
        self.assertNotIn("私密原文", summary)

    def test_failure_summary_keeps_the_leading_error(self) -> None:
        summary = RUNNER._failure_summary("important error " + "x" * 800, ())
        self.assertTrue(summary.startswith("important error"))
        self.assertLessEqual(len(summary), 500)


if __name__ == "__main__":
    unittest.main()
