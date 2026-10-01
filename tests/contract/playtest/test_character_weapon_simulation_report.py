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

import run_character_weapon_simulation_matrix as simulation  # noqa: E402


EXPECTED_CHARACTERS = [
    "wanderer",
    "time_guardian",
    "void_walker",
    "primordial_knight",
    "time_lord",
]
EXPECTED_WEAPONS = ["sword", "bow", "gun", "staff", "gauntlets"]
EXPECTED_TIME_PAIRS = [
    ["stop", "rewind"],
    ["stop", "rift"],
    ["stop", "accelerate"],
    ["rewind", "rift"],
    ["rewind", "accelerate"],
    ["rift", "accelerate"],
]
P11_METRICS = {
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
P12_METRICS = {
    "signature_resource_efficiency",
    "mastery_conversion_rate",
    "damage_prevention_value",
    "void_debt_generated",
    "void_debt_converted",
    "planar_echo_value",
    "codex_pair_completion_frequency",
    "character_skill_use_rate",
    "character_skill_rejection_rate",
}
EXPECTED_METRICS = P11_METRICS | P12_METRICS


class CharacterWeaponSimulationReportContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = simulation.build_report(seed_count=30)

    def test_report_has_strict_v2_contract_and_synthetic_disclosure(self) -> None:
        self.assertEqual(
            set(self.report),
            {
                "schema_version",
                "report_type",
                "evidence",
                "methodology",
                "characters",
                "weapons",
                "time_pairs",
                "seeds",
                "talent_subset_cases",
                "samples",
                "loadouts",
                "character_summaries",
                "weapon_summaries",
                "character_weapon_summaries",
                "content_digest",
            },
        )
        self.assertEqual(self.report["schema_version"], "2.0.0")
        self.assertEqual(self.report["report_type"], "character_weapon_simulation_matrix")
        self.assertEqual(
            self.report["evidence"],
            {
                "source": "synthetic",
                "synthetic": True,
                "human_playtests": 0,
                "claim_boundary": "deterministic_model_observation_only",
            },
        )
        self.assertEqual(simulation.validate_report(self.report), [])

    def test_report_covers_exact_150_loadouts_and_4500_samples(self) -> None:
        self.assertEqual(self.report["characters"], EXPECTED_CHARACTERS)
        self.assertEqual(self.report["weapons"], EXPECTED_WEAPONS)
        self.assertEqual(self.report["time_pairs"], EXPECTED_TIME_PAIRS)
        self.assertEqual(self.report["seeds"], list(range(20260901, 20260931)))
        self.assertEqual(self.report["talent_subset_cases"], 40)
        self.assertEqual(self.report["methodology"]["samples_per_loadout"], 30)
        self.assertEqual(self.report["methodology"]["total_samples"], 4500)
        self.assertEqual(len(self.report["samples"]), 4500)
        self.assertEqual(len(self.report["loadouts"]), 150)
        self.assertEqual(len(self.report["character_summaries"]), 5)
        self.assertEqual(len(self.report["weapon_summaries"]), 5)
        self.assertEqual(len(self.report["character_weapon_summaries"]), 25)

        expected = [
            (character_id, weapon_id, time_pair, seed)
            for character_id in EXPECTED_CHARACTERS
            for weapon_id in EXPECTED_WEAPONS
            for time_pair in EXPECTED_TIME_PAIRS
            for seed in range(20260901, 20260931)
        ]
        actual = [
            (
                sample["character_id"],
                sample["weapon_id"],
                sample["time_pair"],
                sample["seed"],
            )
            for sample in self.report["samples"]
        ]
        self.assertEqual(actual, expected)

    def test_profiles_and_active_pack_are_bound_by_exact_hashes(self) -> None:
        methodology = self.report["methodology"]
        self.assertEqual(
            set(methodology),
            {
                "model_version",
                "frames_per_second",
                "seed_policy",
                "samples_per_loadout",
                "total_samples",
                "character_profile_source",
                "character_profile_sha256",
                "weapon_profile_source",
                "weapon_profile_sha256",
                "active_pack_source",
                "active_pack_sha256",
                "disclaimer",
            },
        )
        for key in (
            "character_profile_sha256",
            "weapon_profile_sha256",
            "active_pack_sha256",
        ):
            self.assertRegex(methodology[key], r"^[0-9a-f]{64}$")

    def test_every_sample_and_summary_exposes_p11_and_p12_metrics(self) -> None:
        for sample in self.report["samples"]:
            self.assertEqual(
                set(sample),
                {"character_id", "weapon_id", "time_pair", "seed", "metrics"},
            )
            self._assert_metrics(sample["metrics"])

        for collection in (
            self.report["loadouts"],
            self.report["character_summaries"],
            self.report["weapon_summaries"],
            self.report["character_weapon_summaries"],
        ):
            for entry in collection:
                self._assert_metrics(entry["metrics"])

    def test_character_metrics_remain_bounded_and_character_specific(self) -> None:
        summaries = {
            entry["character_id"]: entry["metrics"]
            for entry in self.report["character_summaries"]
        }
        self.assertGreater(summaries["time_guardian"]["damage_prevention_value"], 0.0)
        self.assertGreater(summaries["void_walker"]["void_debt_generated"], 0.0)
        self.assertGreater(summaries["void_walker"]["void_debt_converted"], 0.0)
        self.assertGreater(summaries["primordial_knight"]["planar_echo_value"], 0.0)
        self.assertGreater(summaries["time_lord"]["codex_pair_completion_frequency"], 0.0)
        self.assertEqual(summaries["wanderer"]["void_debt_generated"], 0.0)
        self.assertEqual(summaries["time_guardian"]["planar_echo_value"], 0.0)

    def test_same_inputs_produce_byte_identical_report_and_digest(self) -> None:
        repeated = simulation.build_report(seed_count=30)
        self.assertEqual(repeated, self.report)
        self.assertEqual(self.report["content_digest"], simulation.report_digest(self.report))

    def test_validator_rejects_unknown_fields_drift_nonfinite_and_human_claims(self) -> None:
        unknown = copy.deepcopy(self.report)
        unknown["unexpected"] = True
        self.assertTrue(any("unexpected" in item for item in simulation.validate_report(unknown)))

        drifted = copy.deepcopy(self.report)
        drifted["character_summaries"][0]["metrics"]["dps"] += 1.0
        drifted["content_digest"] = simulation.report_digest(drifted)
        self.assertTrue(any("recomputed" in item for item in simulation.validate_report(drifted)))

        nonfinite = copy.deepcopy(self.report)
        nonfinite["samples"][0]["metrics"]["risk_uptime"] = float("nan")
        self.assertTrue(any("finite" in item for item in simulation.validate_report(nonfinite)))

        human = copy.deepcopy(self.report)
        human["evidence"]["source"] = "human"
        human["evidence"]["synthetic"] = False
        human["evidence"]["human_playtests"] = 20
        self.assertTrue(any("evidence" in item for item in simulation.validate_report(human)))

    def test_cli_accepts_only_thirty_seeds_and_writes_identical_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            outputs = [Path(temp_dir) / "a.json", Path(temp_dir) / "b.json"]
            for output in outputs:
                result = subprocess.run(
                    [
                        sys.executable,
                        str(TOOLS_DIR / "run_character_weapon_simulation_matrix.py"),
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
            self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes())
            parsed = json.loads(outputs[0].read_text(encoding="utf-8"))
            self.assertEqual(simulation.validate_report(parsed), [])

            rejected = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS_DIR / "run_character_weapon_simulation_matrix.py"),
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

    def _assert_metrics(self, metrics: dict) -> None:
        self.assertEqual(set(metrics), EXPECTED_METRICS)
        for name, value in metrics.items():
            self.assertIs(type(value), float, name)
            self.assertGreaterEqual(value, 0.0, name)
            if name in simulation.RATIO_METRICS:
                self.assertLessEqual(value, 1.0, name)


if __name__ == "__main__":
    unittest.main()
