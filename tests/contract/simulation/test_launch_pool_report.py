from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
TOOLS_DIR = PROJECT_ROOT / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import run_launch_pool_simulation as simulation  # noqa: E402


EXPECTED_ARCHETYPES = [
    "freeze_burst",
    "rewind_echo",
    "rift_trap",
    "accelerated_combo",
    "low_hp_void",
    "perfect_guard",
    "piercing_barrage",
    "echo_legion",
]
EXPECTED_COUNTS = {
    "items": 50,
    "passive_items": 42,
    "active_items": 8,
    "blessings": 28,
    "curses": 18,
    "talents": 15,
}


class LaunchPoolReportContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = simulation.build_report(seed_count=30)

    def test_report_is_strict_synthetic_evidence(self) -> None:
        self.assertEqual(
            set(self.report),
            {
                "schema_version",
                "report_type",
                "evidence",
                "methodology",
                "content_counts",
                "content_digests",
                "archetypes",
                "seeds",
                "samples",
                "route_summaries",
                "content_digest",
            },
        )
        self.assertEqual(self.report["schema_version"], "1.0.0")
        self.assertEqual(self.report["report_type"], "launch_pool_formation")
        self.assertEqual(
            self.report["evidence"],
            {
                "source": "synthetic",
                "synthetic": True,
                "human_playtests": 0,
                "claim_boundary": "deterministic_content_formation_only",
            },
        )
        self.assertEqual(simulation.validate_report(self.report), [])

    def test_report_covers_exact_counts_routes_and_canonical_seeds(self) -> None:
        self.assertEqual(self.report["content_counts"], EXPECTED_COUNTS)
        self.assertEqual(self.report["archetypes"], EXPECTED_ARCHETYPES)
        self.assertEqual(self.report["seeds"], list(range(20260901, 20260931)))
        self.assertEqual(len(self.report["samples"]), 240)
        self.assertEqual(len(self.report["route_summaries"]), 8)

        expected_order = [
            (archetype_id, seed)
            for archetype_id in EXPECTED_ARCHETYPES
            for seed in range(20260901, 20260931)
        ]
        actual_order = [
            (sample["archetype_id"], sample["seed"])
            for sample in self.report["samples"]
        ]
        self.assertEqual(actual_order, expected_order)

    def test_every_route_forms_and_exposes_complete_content(self) -> None:
        exposed_talents: set[str] = set()
        for sample in self.report["samples"]:
            self.assertTrue(sample["formation_success"], sample)
            self.assertEqual(sample["failure_reasons"], [])
            self.assertEqual(len(sample["selected"]["starters"]), 3)
            self.assertEqual(len(sample["selected"]["payoffs"]), 2)
            self.assertEqual(len(sample["selected"]["risks"]), 1)
            self.assertEqual(len(sample["selected"]["utility"]), 1)
            self.assertEqual(len(sample["selected"]["talent"]), 1)
            exposed_talents.update(sample["selected"]["talent"])
            self.assertGreater(sample["effect_execution_count"], 0)

        self.assertEqual(len(exposed_talents), 15)
        for summary in self.report["route_summaries"]:
            self.assertEqual(summary["sample_count"], 30)
            self.assertEqual(summary["formation_success_count"], 30)
            self.assertEqual(summary["failure_reasons"], {})
            self.assertGreaterEqual(summary["starter_pool_count"], 3)
            self.assertGreaterEqual(summary["payoff_pool_count"], 2)
            self.assertGreaterEqual(summary["risk_pool_count"], 3)
            self.assertGreater(summary["effect_execution_count"], 0)
            self.assertGreater(summary["active_usage_count"], 0)
            self.assertGreater(summary["curse_tradeoff_count"], 0)
            for category in ("item", "blessing", "curse", "talent", "active"):
                self.assertGreater(summary["option_exposure"][category], 0)

    def test_source_hashes_and_report_digest_are_stable(self) -> None:
        self.assertEqual(
            set(self.report["content_digests"]),
            {"catalog", "items", "blessings", "curses", "talents", "archetypes", "combined"},
        )
        for digest in self.report["content_digests"].values():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
        repeated = simulation.build_report(seed_count=30)
        self.assertEqual(repeated, self.report)
        self.assertEqual(self.report["content_digest"], simulation.report_digest(self.report))

    def test_validator_rejects_drift_unknown_fields_and_human_claims(self) -> None:
        unknown = copy.deepcopy(self.report)
        unknown["unexpected"] = True
        self.assertTrue(any("unexpected" in item for item in simulation.validate_report(unknown)))

        drifted = copy.deepcopy(self.report)
        drifted["route_summaries"][0]["formation_success_count"] -= 1
        drifted["content_digest"] = simulation.report_digest(drifted)
        self.assertTrue(any("recomputed" in item for item in simulation.validate_report(drifted)))

        human = copy.deepcopy(self.report)
        human["evidence"]["source"] = "human"
        human["evidence"]["synthetic"] = False
        human["evidence"]["human_playtests"] = 20
        self.assertTrue(any("evidence" in item for item in simulation.validate_report(human)))

    def test_cli_requires_thirty_seeds_and_is_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            first = Path(temp_dir) / "first.json"
            second = Path(temp_dir) / "second.json"
            for output in (first, second):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(TOOLS_DIR / "run_launch_pool_simulation.py"),
                        "--seeds",
                        "30",
                        "--output",
                        str(output),
                    ],
                    cwd=PROJECT_ROOT,
                    capture_output=True,
                    check=False,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("synthetic", result.stdout.lower())
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(simulation.validate_report(json.loads(first.read_text())), [])

            rejected = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS_DIR / "run_launch_pool_simulation.py"),
                    "--seeds",
                    "29",
                    "--output",
                    str(Path(temp_dir) / "rejected.json"),
                ],
                cwd=PROJECT_ROOT,
                capture_output=True,
                check=False,
                text=True,
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("exactly 30", (rejected.stdout + rejected.stderr).lower())


if __name__ == "__main__":
    unittest.main()
