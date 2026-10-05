from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

import run_dungeon_simulation as simulation  # noqa: E402


class DungeonSimulationLogContractTest(unittest.TestCase):
    def test_tool_adapter_is_bound_into_runtime_source_digests(self) -> None:
        sources = simulation._runtime_digests()
        self.assertIn("tools/dungeon/domain_encounter_runner.gd", sources)

    def test_bootstrap_failure_can_report_zero_entered_floors(self) -> None:
        summary = simulation._run_failure_summaries([
            {"seed": 20261001, "victory": False, "floor_summaries": [], "failures": ["merchant_effect_authority"]},
        ])
        self.assertEqual(summary, [{"seed": 20261001, "last_floor": None,
                                    "failures": ["merchant_effect_authority"]}])

    def test_only_registered_macos_ca_error_with_callsite_is_allowed(self) -> None:
        known_error = 'ERROR: Condition "ret != noErr" is true. Returning: ""'
        callsite = "at: get_system_ca_certificates (platform/macos/os_macos.mm:1014)"
        self.assertEqual(simulation._unapproved_error_lines(known_error + "\n" + callsite), [])
        self.assertTrue(simulation._unapproved_error_lines(known_error))
        self.assertEqual(simulation._unapproved_error_lines(
            known_error + "\n" + callsite + "\nERROR: Selection authority rollback failed"),
            ["ERROR: Selection authority rollback failed"])


class DungeonSimulationReportContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = simulation.build_report(seed_count=30)

    def test_report_is_authoritative_synthetic_evidence(self) -> None:
        self.assertEqual(self.report["schema_version"], "1.0.0")
        self.assertEqual(self.report["report_type"], "five_floor_dungeon")
        self.assertIs(self.report["synthetic"], True)
        self.assertEqual(self.report["human_playtests"], 0)
        self.assertEqual(self.report["generator_version"], "floor_plan_v1")
        self.assertEqual(self.report["methodology"]["runtime"], "godot_domain_probe")
        self.assertEqual(self.report["methodology"]["combat"], "domain_completion_commands")
        self.assertEqual(self.report["methodology"]["floor_rule_authority"],
                         "production_player_effects_in_fixture_zone")
        self.assertEqual(simulation.validate_report(self.report), [])

    def test_thirty_seeds_complete_all_five_floors(self) -> None:
        self.assertEqual(self.report["seeds"], list(range(20261001, 20261031)))
        floors = self.report["floor_summaries"]
        self.assertEqual(len(floors), 150)
        self.assertEqual(
            [(row["seed"], row["floor_index"]) for row in floors],
            [(seed, index) for seed in range(20261001, 20261031) for index in range(5)],
        )
        for floor in floors:
            self.assertEqual(floor["failures"], [])
            self.assertTrue(floor["completed"])
            self.assertGreater(len(floor["route_edge_ids"]), 0)
            self.assertEqual(floor["room_types"][-1], "boss")
            self.assertGreaterEqual(floor["gold_remainder"], 0)
            self.assertGreaterEqual(floor["minimum_gold_balance"], 0)
            self.assertEqual(
                floor["gold_start"] + sum(entry["amount"] for entry in floor["gold_ledger"]),
                floor["gold_remainder"],
            )
            self.assertEqual(
                floor["gold_start"] + floor["gold_earned"] - floor["gold_spent"] + floor["gold_settled"],
                floor["gold_remainder"],
            )
            self.assertEqual(
                [entry["revision"] for entry in floor["gold_ledger"]],
                list(range(floor["economy_start_revision"] + 1,
                           floor["economy_start_revision"] + len(floor["gold_ledger"]) + 1)),
            )
            self.assertRegex(floor["plan_digest"], r"^[0-9a-f]{64}$")
            self.assertGreater(floor["rule_effect_count"], 0)
            self.assertGreaterEqual(floor["rule_health_loss"], 0)
            if floor["rule_id"] == "rule_temporal_distortion":
                self.assertGreater(floor["rule_modifier_observation_count"], 0)
        summary = self.report["summary"]
        self.assertEqual(summary["invalid_plan_count"], 0)
        self.assertEqual(summary["negative_balance_count"], 0)
        self.assertEqual(summary["completed_run_count"], 30)
        self.assertEqual(set(summary["floor_rule_exposure"]), {
            "rule_crumbling_ground", "rule_void_spores", "rule_temporal_distortion",
            "rule_forge_vents", "rule_collapsing_plane",
        })
        self.assertEqual(set(summary["room_type_distribution"]), {
            "combat", "elite", "treasure", "shop", "event", "rest", "boss",
        })
        self.assertGreater(sum(summary["merchant_exposure"].values()), 0)
        self.assertGreater(sum(summary["event_exposure"].values()), 0)
        self.assertGreater(summary["merchant_purchase_count"], 0)
        self.assertGreater(summary["event_consequence_count"], 0)

    def test_economy_budget_drift_preserves_actual_measurements(self) -> None:
        profiles = json.loads((PROJECT_ROOT / "data/content_packs/base/content/economy_profiles.json").read_text())
        budgets = next(value["floor_income_budgets"] for value in profiles
                       if value["id"] == "launch_economy_v1")
        for budget in budgets:
            rows = [row for row in self.report["floor_summaries"]
                    if row["floor_index"] == budget["floor_index"] - 1]
            for metric, target in (("gold_earned", "earned"), ("gold_spent", "spend"),
                                   ("gold_remainder", "remainder")):
                comparison = self.report["summary"]["economy_budget_comparison"][str(budget["floor_index"])][metric]
                lower, upper = budget[f"{target}_min"], budget[f"{target}_max"]
                self.assertEqual((comparison["target_min"], comparison["target_max"]), (lower, upper))
                self.assertEqual(comparison["below_target_count"], sum(row[metric] < lower for row in rows))
                self.assertEqual(comparison["above_target_count"], sum(row[metric] > upper for row in rows))
                self.assertEqual(sum(comparison[key] for key in (
                    "below_target_count", "within_target_count", "above_target_count")), 30)
                self.assertEqual(comparison["distance_from_target_band"]["min"], min(
                    min(row[metric] - lower, 0) + max(row[metric] - upper, 0) for row in rows))

    def test_validator_rejects_forged_receipts_totals_and_human_claims(self) -> None:
        cases = []
        unknown = copy.deepcopy(self.report)
        unknown["unknown"] = 1
        cases.append(unknown)
        human = copy.deepcopy(self.report)
        human["synthetic"] = False
        human["human_playtests"] = 20
        cases.append(human)
        forged = copy.deepcopy(self.report)
        forged["floor_summaries"][0]["plan_digest"] = "0" * 64
        cases.append(forged)
        total = copy.deepcopy(self.report)
        total["summary"]["merchant_purchase_count"] += 1
        cases.append(total)
        drift = copy.deepcopy(self.report)
        drift["summary"]["economy_budget_comparison"]["1"]["gold_spent"]["below_target_count"] += 1
        cases.append(drift)
        negative = copy.deepcopy(self.report)
        negative["floor_summaries"][0]["gold_remainder"] = -1
        cases.append(negative)
        for report in cases:
            report["report_digest"] = simulation.report_digest(report)
            self.assertTrue(simulation.validate_report(report), report)

    def test_noncanonical_seed_requests_fail_before_engine_execution(self) -> None:
        for count in (0, 29, 31):
            with self.assertRaisesRegex(ValueError, "exactly 30"):
                simulation.build_report(seed_count=count)

    def test_serialized_cli_output_is_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory(prefix="planewalker-dungeon-contract-") as directory:
            paths = [Path(directory) / "first.json", Path(directory) / "second.json"]
            for path in paths:
                completed = subprocess.run(
                    [sys.executable, str(PROJECT_ROOT / "tools/run_dungeon_simulation.py"),
                     "--seeds", "30", "--output", str(path)],
                    cwd=PROJECT_ROOT, capture_output=True, text=True, timeout=180,
                )
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(paths[0].read_bytes(), paths[1].read_bytes())
            self.assertEqual(json.loads(paths[0].read_text()), self.report)


if __name__ == "__main__":
    unittest.main()
