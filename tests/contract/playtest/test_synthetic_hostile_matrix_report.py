from __future__ import annotations

import importlib.util
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DRIVER = ROOT / "tools/run_p15_synthetic_matrix.py"
SPEC = importlib.util.spec_from_file_location("p15_synthetic", DRIVER)
MATRIX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATRIX)


def report_fixture(count: int = 5, start: int = 0) -> dict:
    characters, weapons = MATRIX.canonical_profiles(ROOT)
    bosses = {row["id"]: row for row in json.loads((ROOT / "data/content_packs/base/content/bosses.json").read_text())}
    actions = MATRIX.authored_action_ids(ROOT)
    coverage = dict.fromkeys(actions, 0)
    rows = []
    for index in range(start, start + count):
        identity = MATRIX.case_identity(index)
        character, weapon = characters[identity["character_id"]], weapons[identity["weapon_id"]]
        primary = next(action for action in weapon["actions"] if action["semantic_action"] == "weapon_primary")
        payload = next(value for value in weapon["payloads"] if value["payload_id"] == primary["payload_id"])
        interactions = {ability: {"character": character["time_interactions"][ability], "weapon": weapon["time_interactions"][ability]} for ability in identity["time_abilities"]}
        observations = []
        for ability in identity["time_abilities"]:
            if ability == "stop":
                observations.append({"ability": ability, "kind": "actual_boss_control", "accepted": True, "duration": 180 + character["time_interactions"]["stop"]["parameters"].get("window_bonus_frames", 0), "conversion": 30})
            elif ability == "rift":
                observations.append({"ability": ability, "kind": "actual_boss_control", "accepted": True, "actual_multiplier": 0.7})
            else:
                observations.append({"ability": ability, "kind": "synthetic_profile_damage", "synthetic_profile_observation": interactions[ability]})
        boss = bosses[identity["boss_id"]]
        action_id = boss["enrage"]["action_id"] if identity["loadout_index"] == 149 else boss["actions"][0]["id"]
        coverage[action_id] += 1
        rows.append({"identity": identity, "action_id": action_id, "frames": 100, "time_inputs": identity["time_abilities"], "time_input_count": 2,
                     "profile_inputs_consumed": True, "accepted_damage": 30.0, "typed_cold_next_frame_equal": True,
                     "malformed_snapshot_refused": True, "phase_monotonic": True, "terminal_cleanup": True,
                     "hit_count": 1, "effect_count": 1, "unwarned_hits": 0, "errors": [],
                     "trace_sha256": "a" * 64, "repeat_sha256": "a" * 64, "checkpoint_sha256": "b" * 64,
                     "profile_inputs_sha256": "c" * 64, "recipe_affix_sha256": "d" * 64,
                     "recipe_id": "fixture_recipe", "affix_ids": ["shielded"],
                     "enrage_threshold_observed": identity["loadout_index"] == 149, "time_observations": observations,
                     "profile_inputs": {"character_profile": character["id"], "weapon_profile": weapon["id"],
                                        "attack": character["base_stats"]["attack"], "attack_speed": character["base_stats"]["attack_speed"],
                                        "move_speed": character["base_stats"]["move_speed"], "weapon_action": primary, "payload": payload,
                                        "time_interactions": interactions, "synthetic_damage_amount": character["base_stats"]["attack"] * payload["parameters"].get("damage_multiplier", 1.0)}})
    budgets = {"projectile_peak": 32, "zone_peak": 12, "zone_pulse_peak": 12, "reservation_count": 256,
               "projectile_overflow_pending": True, "zone_overflow_pending": True, "reservation_overflow_refused": True,
               "typed_cold_equal": True, "finite_lifetime_cleanup": True, "response_pending_peak": 4,
               "response_overflow_bounded": True, "terminal_response_cleanup": True, "errors": []}
    counterplay = {"case_count": 8, "cases": [{"phase": phase, "ability": ability, "positive_response": True,
                   "typed_cold_equal": True, "duplicate_refused": True, "terminal_cleanup": True, "repeat_equal": True,
                   "trace_sha256": "e" * 64, "repeat_sha256": "e" * 64, "errors": []}
                  for phase in [0, 1] for ability in ["stop", "rewind", "accelerate", "rift"]]}
    return {"schema_version": 1, "report_kind": "synthetic_hostile_domain_matrix", "synthetic": True,
            "production_case_count": 0, "human_playtests": 0, "unassisted_victory": False,
            "expected_synthetic_case_count": 22500, "synthetic_case_count": count, "range_start": start,
            "requested_case_count": count, "source_binding": MATRIX.source_binding(ROOT),
            "content_snapshot": {"aggregate_sha256": "f" * 64, "packs": [{"pack_id": "base", "fingerprint_sha256": "f" * 64}]},
            "action_coverage": coverage, "cases": rows, "budgets": [budgets], "counterplay": [counterplay],
            "errors": [], "status": "pass", "complete": False}


class SyntheticHostileMatrixReportTests(unittest.TestCase):
    def test_driver_and_domain_probe_exist_as_separate_certification(self):
        self.assertTrue(DRIVER.is_file(), "22500 synthetic domain traces need an independent fail-closed driver")
        self.assertTrue((ROOT / "tools/p15/hostile_synthetic_probe.gd").is_file())
        self.assertTrue((ROOT / "tools/p15/hostile_synthetic_probe.tscn").is_file())

    def test_canonical_identity_is_exact_and_cannot_alias_loadouts(self):
        identities = [MATRIX.case_identity(index) for index in range(22500)]
        self.assertEqual(len({row["key"] for row in identities}), 22500)
        self.assertEqual(len({row["seed"] for row in identities}), 30)
        self.assertEqual(len({(row["character_id"], row["weapon_id"], tuple(row["time_abilities"])) for row in identities}), 150)
        self.assertEqual(len({row["boss_id"] for row in identities}), 5)
        for invalid in [-1, 22500, True, 1.0]:
            with self.assertRaises(ValueError):
                MATRIX.case_identity(invalid)

    def test_partial_evidence_cannot_claim_full_certification(self):
        report = report_fixture()
        self.assertEqual(MATRIX.validate_report(report, ROOT, require_complete=False), [])
        self.assertIn("full_matrix_incomplete", MATRIX.validate_report(report, ROOT))
        report["complete"] = True
        self.assertIn("completion_claim", MATRIX.validate_report(report, ROOT, require_complete=False))

    def test_report_refuses_semantic_tampering(self):
        baseline = report_fixture()
        mutations = {
            "actual_player_claim": lambda report: report.update(production_case_count=750),
            "numeric_synthetic_alias": lambda report: report.update(synthetic=1),
            "human_claim": lambda report: report.update(human_playtests=1),
            "duplicate_identity": lambda report: report["cases"][1].update(identity=report["cases"][0]["identity"]),
            "repeat_divergence": lambda report: report["cases"][0].update(repeat_sha256="b" * 64),
            "wrong_character_attack": lambda report: report["cases"][0]["profile_inputs"].update(attack=999),
            "inert_time_input": lambda report: report["cases"][0]["time_observations"][0].update(accepted=False),
            "wrong_boss_move": lambda report: report["cases"][0].update(action_id="forge_hammer_slam"),
            "unwarned_hit": lambda report: report["cases"][0].update(unwarned_hits=1),
            "cold_divergence": lambda report: report["cases"][0].update(typed_cold_next_frame_equal=False),
            "false_enrage": lambda report: report["cases"][0].update(enrage_threshold_observed=True),
            "budget_overflow": lambda report: report["budgets"][0].update(projectile_peak=33),
            "lost_positive_response": lambda report: report["counterplay"][0]["cases"][0].update(positive_response=False),
            "wrong_source": lambda report: report["source_binding"].update(domain_files_sha256="0" * 64),
            "missing_content": lambda report: report.update(content_snapshot={}),
            "forged_coverage": lambda report: report["action_coverage"].update(guardian_charge=50),
            "empty_seed_recipe": lambda report: report["cases"][0].update(recipe_id=""),
            "reported_failure": lambda report: report.update(errors=["failure"]),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                report = copy.deepcopy(baseline)
                mutation(report)
                self.assertTrue(MATRIX.validate_report(report, ROOT, require_complete=False))

    def test_missing_cases_and_nonfinite_damage_refuse(self):
        report = report_fixture()
        report["cases"].pop()
        self.assertIn("case_count", MATRIX.validate_report(report, ROOT, require_complete=False))
        report = report_fixture()
        report["cases"][0]["accepted_damage"] = float("nan")
        self.assertIn("case:0:accepted_damage", MATRIX.validate_report(report, ROOT, require_complete=False))

    def test_failed_process_cannot_reuse_stale_domain_report(self):
        (ROOT / "build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            logs = Path(directory)
            stale = logs / "00000"
            stale.mkdir()
            (stale / "domain.json").write_text('{"cases":[{"stale":true}]}')
            shard = MATRIX._run_shard(ROOT, sys.executable, 0, 1, logs, 10)
            self.assertEqual(shard["report"], {})
            self.assertIn("missing_or_invalid_domain_report", shard["errors"])
            self.assertIn("domain_process_failed", shard["errors"])


if __name__ == "__main__":
    unittest.main()
