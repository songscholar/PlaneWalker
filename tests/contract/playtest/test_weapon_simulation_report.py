from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from statistics import fmean


PROJECT_ROOT = Path(__file__).resolve().parents[3]
TOOLS_DIR = PROJECT_ROOT / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import run_weapon_simulation_matrix as simulation  # noqa: E402


EXPECTED_WEAPONS = ["sword", "bow", "gun", "staff", "gauntlets"]
EXPECTED_TIME_PAIRS = [
    ["stop", "rewind"],
    ["stop", "rift"],
    ["stop", "accelerate"],
    ["rewind", "rift"],
    ["rewind", "accelerate"],
    ["rift", "accelerate"],
]
EXPECTED_METRICS = {
    "dps",
    "risk_uptime",
    "starvation_rate",
    "burst_damage",
    "area_coverage",
    "status_uptime",
    "perfect_reload_value",
    "staff_combination_frequency",
    "gauntlets_combo_retention",
}


class WeaponSimulationReportContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = simulation.build_report(seed_count=30)

    def test_report_has_strict_top_level_contract_and_synthetic_disclosure(self) -> None:
        self.assertEqual(
            set(self.report),
            {
                "schema_version",
                "report_type",
                "evidence",
                "methodology",
                "weapons",
                "time_pairs",
                "seeds",
                "samples",
                "loadouts",
                "weapon_summaries",
                "content_digest",
            },
        )
        self.assertEqual(self.report["schema_version"], "1.0.0")
        self.assertEqual(self.report["report_type"], "weapon_simulation_matrix")
        self.assertEqual(
            self.report["evidence"],
            {
                "source": "synthetic",
                "synthetic": True,
                "human_playtests": 0,
                "claim_boundary": "deterministic_model_observation_only",
            },
        )
        self.assertIn("does not represent human playtest evidence", self.report["methodology"]["disclaimer"])
        self.assertEqual(simulation.validate_report(self.report), [])

    def test_report_covers_five_weapons_six_pairs_and_thirty_canonical_seeds(self) -> None:
        self.assertEqual(self.report["weapons"], EXPECTED_WEAPONS)
        self.assertEqual(self.report["time_pairs"], EXPECTED_TIME_PAIRS)
        self.assertEqual(self.report["seeds"], list(range(20260901, 20260931)))
        self.assertEqual(self.report["methodology"]["samples_per_loadout"], 30)
        self.assertEqual(self.report["methodology"]["total_samples"], 900)
        self.assertEqual(len(self.report["samples"]), 900)
        self.assertEqual(len(self.report["loadouts"]), 30)
        self.assertEqual(
            {
                (entry["weapon_id"], tuple(entry["time_pair"]))
                for entry in self.report["loadouts"]
            },
            {
                (weapon_id, tuple(time_pair))
                for weapon_id in EXPECTED_WEAPONS
                for time_pair in EXPECTED_TIME_PAIRS
            },
        )
        self.assertEqual(
            [
                (sample["weapon_id"], sample["time_pair"], sample["seed"])
                for sample in self.report["samples"]
            ],
            [
                (weapon_id, time_pair, seed)
                for weapon_id in EXPECTED_WEAPONS
                for time_pair in EXPECTED_TIME_PAIRS
                for seed in range(20260901, 20260931)
            ],
        )

    def test_each_seed_sample_is_auditable_and_recomputes_every_summary(self) -> None:
        samples_by_loadout: dict[tuple[str, tuple[str, str]], list[dict[str, float]]] = {}
        samples_by_weapon: dict[str, list[dict[str, float]]] = {}
        for sample in self.report["samples"]:
            self.assertEqual(set(sample), {"weapon_id", "time_pair", "seed", "metrics"})
            self.assertIn(sample["weapon_id"], EXPECTED_WEAPONS)
            self.assertIn(sample["time_pair"], EXPECTED_TIME_PAIRS)
            self.assertIn(sample["seed"], range(20260901, 20260931))
            self._assert_metric_contract(sample["metrics"])
            loadout_key = (sample["weapon_id"], tuple(sample["time_pair"]))
            samples_by_loadout.setdefault(loadout_key, []).append(sample["metrics"])
            samples_by_weapon.setdefault(sample["weapon_id"], []).append(sample["metrics"])

        for loadout in self.report["loadouts"]:
            key = (loadout["weapon_id"], tuple(loadout["time_pair"]))
            self.assertEqual(loadout["sample_count"], len(samples_by_loadout[key]))
            self.assertEqual(loadout["metrics"], self._average_metrics(samples_by_loadout[key]))
        for summary in self.report["weapon_summaries"]:
            metrics = samples_by_weapon[summary["weapon_id"]]
            self.assertEqual(summary["sample_count"], len(metrics))
            self.assertEqual(summary["metrics"], self._average_metrics(metrics))

    def test_each_loadout_and_weapon_summary_exposes_all_required_metrics(self) -> None:
        for entry in self.report["loadouts"]:
            self.assertEqual(set(entry), {"weapon_id", "time_pair", "sample_count", "metrics"})
            self.assertEqual(entry["sample_count"], 30)
            self._assert_metric_contract(entry["metrics"])

        self.assertEqual(len(self.report["weapon_summaries"]), 5)
        for summary in self.report["weapon_summaries"]:
            self.assertEqual(set(summary), {"weapon_id", "sample_count", "metrics"})
            self.assertEqual(summary["sample_count"], 180)
            self._assert_metric_contract(summary["metrics"])

        by_weapon = {entry["weapon_id"]: entry["metrics"] for entry in self.report["weapon_summaries"]}
        self.assertGreater(by_weapon["gun"]["perfect_reload_value"], 0.0)
        self.assertGreater(by_weapon["staff"]["staff_combination_frequency"], 0.0)
        self.assertGreater(by_weapon["gauntlets"]["gauntlets_combo_retention"], 0.0)
        for weapon_id in ["sword", "bow", "staff", "gauntlets"]:
            self.assertEqual(by_weapon[weapon_id]["perfect_reload_value"], 0.0)
        for weapon_id in ["sword", "bow", "gun", "gauntlets"]:
            self.assertEqual(by_weapon[weapon_id]["staff_combination_frequency"], 0.0)
        for weapon_id in ["sword", "bow", "gun", "staff"]:
            self.assertEqual(by_weapon[weapon_id]["gauntlets_combo_retention"], 0.0)

    def test_same_inputs_produce_identical_report_and_digest(self) -> None:
        repeated = simulation.build_report(seed_count=30)
        self.assertEqual(repeated, self.report)
        self.assertEqual(self.report["content_digest"], simulation.report_digest(self.report))

    def test_generator_and_validator_reject_any_noncanonical_seed_count(self) -> None:
        with self.assertRaisesRegex(ValueError, "exactly 30"):
            simulation.build_report(seed_count=1)

        shortened = copy.deepcopy(self.report)
        shortened["seeds"] = shortened["seeds"][:-1]
        shortened["samples"] = [
            sample for sample in shortened["samples"] if sample["seed"] != 20260930
        ]
        shortened["methodology"]["samples_per_loadout"] = 29
        shortened["methodology"]["total_samples"] = 870
        shortened["content_digest"] = simulation.report_digest(shortened)
        violations = simulation.validate_report(shortened)
        self.assertTrue(any("exactly 30" in violation for violation in violations))
        self.assertTrue(any("exactly 900" in violation for violation in violations))

    def test_validator_rejects_unknown_fields_metric_drift_and_human_claims(self) -> None:
        unknown = copy.deepcopy(self.report)
        unknown["unexpected"] = True
        self.assertIn("root: unexpected fields: unexpected", simulation.validate_report(unknown))

        missing_metric = copy.deepcopy(self.report)
        del missing_metric["loadouts"][0]["metrics"]["dps"]
        self.assertTrue(
            any("loadouts[0].metrics" in violation for violation in simulation.validate_report(missing_metric))
        )

        false_evidence = copy.deepcopy(self.report)
        false_evidence["evidence"]["source"] = "human"
        false_evidence["evidence"]["synthetic"] = False
        false_evidence["evidence"]["human_playtests"] = 20
        violations = simulation.validate_report(false_evidence)
        self.assertTrue(any("evidence" in violation for violation in violations))

        non_finite = copy.deepcopy(self.report)
        non_finite["weapon_summaries"][0]["metrics"]["dps"] = float("nan")
        self.assertTrue(any("finite" in violation for violation in simulation.validate_report(non_finite)))

        tampered_sample = copy.deepcopy(self.report)
        tampered_sample["samples"][0]["metrics"]["dps"] += 1.0
        tampered_sample["content_digest"] = simulation.report_digest(tampered_sample)
        tampered_violations = simulation.validate_report(tampered_sample)
        self.assertTrue(
            any("recomputed from samples" in violation for violation in tampered_violations),
            tampered_violations,
        )

    def test_cli_writes_byte_identical_valid_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            first = Path(temp_dir) / "first.json"
            second = Path(temp_dir) / "second.json"
            for output in (first, second):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(TOOLS_DIR / "run_weapon_simulation_matrix.py"),
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
            parsed = json.loads(first.read_text(encoding="utf-8"))
            self.assertEqual(simulation.validate_report(parsed), [])
            self.assertEqual(parsed["content_digest"], simulation.report_digest(parsed))

            rejected = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS_DIR / "run_weapon_simulation_matrix.py"),
                    "--seeds",
                    "1",
                    "--output",
                    str(Path(temp_dir) / "invalid.json"),
                ],
                cwd=PROJECT_ROOT,
                capture_output=True,
                check=False,
                text=True,
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("exactly 30", rejected.stderr)

    def _assert_metric_contract(self, metrics: dict) -> None:
        self.assertEqual(set(metrics), EXPECTED_METRICS)
        for metric_name, value in metrics.items():
            self.assertIs(type(value), float, metric_name)
            self.assertGreaterEqual(value, 0.0, metric_name)
        for ratio_name in {
            "risk_uptime",
            "starvation_rate",
            "area_coverage",
            "status_uptime",
            "staff_combination_frequency",
            "gauntlets_combo_retention",
        }:
            self.assertLessEqual(metrics[ratio_name], 1.0, ratio_name)

    def _average_metrics(self, samples: list[dict[str, float]]) -> dict[str, float]:
        return {
            metric: round(fmean(sample[metric] for sample in samples), 6)
            for metric in EXPECTED_METRICS
        }


if __name__ == "__main__":
    unittest.main()
