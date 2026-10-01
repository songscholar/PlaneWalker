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
EXPECTED_CHARACTERS = {
    "wanderer",
    "time_guardian",
    "void_walker",
    "primordial_knight",
    "time_lord",
}
EXPECTED_WEAPONS = {"sword", "bow", "gun", "staff", "gauntlets"}
EXPECTED_TIME_PAIRS = {
    ("stop", "rewind"),
    ("stop", "rift"),
    ("stop", "accelerate"),
    ("rewind", "rift"),
    ("rewind", "accelerate"),
    ("rift", "accelerate"),
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
        self.assertEqual(self.report["schema_version"], "2.0.0")
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
        self.assertEqual(
            self.report["methodology"]["loadout_policy"],
            "canonical_5x5x6_launch_loadouts_with_definition_compatibility",
        )
        self.assertEqual(
            self.report["methodology"]["effect_execution_model"],
            "bounded_effect_catalog_dry_run_with_active_handler_receipts",
        )

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
            self.assertIn(sample["character_id"], EXPECTED_CHARACTERS)
            self.assertIn(sample["weapon_id"], EXPECTED_WEAPONS)
            self.assertIn(tuple(sample["time_ability_ids"]), EXPECTED_TIME_PAIRS)
            self.assertGreater(sample["effect_execution_count"], 0)
            self.assertEqual(
                sample["effect_execution_count"],
                sum(sample["effect_runtime_domains"].values()),
            )
            self.assertRegex(sample["effect_execution_digest"], r"^[0-9a-f]{64}$")

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
            {
                "catalog",
                "items",
                "blessings",
                "curses",
                "talents",
                "archetypes",
                "effect_catalog",
                "characters",
                "character_profiles",
                "weapons",
                "weapon_profiles",
                "time_abilities",
                "combined",
            },
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

        forged_sources = copy.deepcopy(self.report)
        forged_sources["content_digests"]["items"] = "0" * 64
        forged_sources["content_digests"]["combined"] = simulation._canonical_digest(
            {
                key: value
                for key, value in forged_sources["content_digests"].items()
                if key != "combined"
            }
        )
        forged_sources["content_digest"] = simulation.report_digest(forged_sources)
        self.assertTrue(
            any(
                "source digest mismatch" in item
                for item in simulation.validate_report(forged_sources)
            )
        )

    def test_validator_rejects_incompatible_loadouts_and_fake_execution(self) -> None:
        incompatible = copy.deepcopy(self.report)
        accelerated = next(
            sample
            for sample in incompatible["samples"]
            if sample["archetype_id"] == "accelerated_combo"
        )
        self.assertEqual(accelerated["weapon_id"], "sword")
        accelerated["weapon_id"] = "bow"
        incompatible["content_digest"] = simulation.report_digest(incompatible)
        self.assertTrue(
            any(
                "compatibility" in item
                for item in simulation.validate_report(incompatible)
            )
        )

        fake_execution = copy.deepcopy(self.report)
        fake_execution["samples"][0]["effect_execution_count"] += 1
        fake_execution["content_digest"] = simulation.report_digest(fake_execution)
        self.assertTrue(
            any(
                "effect_execution" in item
                for item in simulation.validate_report(fake_execution)
            )
        )

    def test_dry_run_rejects_invalid_active_payload_and_weapon_capability(self) -> None:
        context = simulation._load_simulation_context()
        active = copy.deepcopy(context["rows_by_id"]["absolute_zero_device"][1])
        active["active_parameters"]["radius"] = True
        with self.assertRaisesRegex(ValueError, "active_parameters"):
            simulation._execute_definition_dry_run(
                "item",
                active,
                {
                    "character_id": "wanderer",
                    "weapon_id": "sword",
                    "time_ability_ids": ("stop", "rewind"),
                },
                context["effect_catalog"],
                {},
            )

        sword_only = context["rows_by_id"]["accelerated_combo"][1]
        with self.assertRaisesRegex(ValueError, "weapon"):
            simulation._execute_definition_dry_run(
                "item",
                sword_only,
                {
                    "character_id": "wanderer",
                    "weapon_id": "bow",
                    "time_ability_ids": ("stop", "accelerate"),
                },
                context["effect_catalog"],
                {},
            )

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
