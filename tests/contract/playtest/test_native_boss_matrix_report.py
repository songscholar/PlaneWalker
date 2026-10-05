from __future__ import annotations

import copy
import hashlib
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import run_p15_hostile_matrix as matrix  # noqa: E402


def valid_row(index: int) -> dict:
    identity = matrix.identity(index)
    run_id = f"p15-native-matrix-{index}"
    source = "matrix-" + hashlib.sha256(run_id.encode()).hexdigest()[:40]
    death = "hostile_defeat:" + hashlib.sha256(f"{run_id}|{source}".encode()).hexdigest()[:40]
    return {
        "identity": identity,
        "failures": [],
        "frames": 500,
        "final_hp": 0,
        "checkpoint_digest": "a" * 64,
        "phase_damage": {str(phase): 10 for phase in range(3 if index % 5 in (3, 4) else 2)},
        "damage_trace": [{"run_id": run_id, "target_id": source, "raw_run_id": run_id, "raw_target_id": source, "native_authenticated": True, "source_id": "player_sword_v2" if identity["weapon_id"] == "sword" else f"player:{identity['weapon_id']}:1:0", "frame": 100 + phase, "phase_index": phase, "hit_index": phase, "amount": 10, "actual_loss": 10, "attack_generation": 1, "accelerated": False, "tags": [f"weapon:{identity['weapon_id']}"]} for phase in range(3 if index % 5 in (3, 4) else 2)],
        "time_casts": [{"ability_id": ability, "run_id": run_id, "owner_generation": 2, "action_generation": 3, "action_token": offset + 1, "runtime_frame": 20 + offset, "endpoint": {"x": 10, "y": 20}, "facing": {"x": 1, "y": 0}, "id": hashlib.sha256(f'["{run_id}",2,3,{offset + 1}]'.encode()).hexdigest()} for offset, ability in enumerate(identity["time_abilities"])],
        "positive_time": ["boss_stop_conversion"],
        "weapon_actions": [{"sword": "charged_slash", "bow": "precision_draw", "gun": "aimed_fire", "staff": "arcane_bolt", "gauntlets": "punch_1"}[identity["weapon_id"]]],
        "boss_actions": {{"ruin_king": "guardian_fist_slam", "forest_heart": "matriarch_call", "time_sovereign": "traitor_chrono_bolt", "forge_colossus": "forge_hammer_slam", "void_throne": "voidking_void_bolt"}[identity["boss_id"]]: 1},
        "death_receipts": [{"source_id": source, "receipt": death}],
    }


class NativeBossMatrixReportTest(unittest.TestCase):
    def test_all_canonical_identities_are_distinct(self) -> None:
        identities = [matrix.identity(index) for index in range(750)]
        self.assertEqual(len({identity["key"] for identity in identities}), 750)
        self.assertEqual(identities[-1]["key"], "time_lord|gauntlets|rift+accelerate|void_throne")

    def test_forge_and_void_require_three_real_hp_phases(self) -> None:
        for index in (3, 4):
            row = valid_row(index)
            self.assertEqual(matrix.validate_cases([row], index, 1), [])
            row["phase_damage"].pop("2")
            self.assertTrue(matrix.validate_cases([row], index, 1))

    def test_missing_or_duplicate_identity_cannot_certify_range(self) -> None:
        self.assertTrue(matrix.validate_cases([valid_row(0)], 0, 2))
        self.assertTrue(matrix.validate_cases([valid_row(0), valid_row(0)], 0, 2))

    def test_authentic_damage_checkpoint_casts_and_final_receipt_are_required(self) -> None:
        row = valid_row(32)
        for field in ("damage_trace", "checkpoint_digest", "time_casts", "positive_time", "weapon_actions", "boss_actions", "death_receipts"):
            changed = copy.deepcopy(row)
            changed[field] = "" if field == "checkpoint_digest" else []
            with self.subTest(field=field):
                self.assertTrue(matrix.validate_cases([changed], 32, 1))

    def test_malformed_or_nonfinite_observations_fail_closed(self) -> None:
        row = valid_row(0)
        for changes in ({"phase_damage": []}, {"time_casts": [None]}, {"damage_trace": [{}]}, {"damage_trace": [{"actual_loss": float("nan")}]}, {"frames": True}):
            changed = copy.deepcopy(row)
            changed.update(changes)
            with self.subTest(changes=changes):
                self.assertTrue(matrix.validate_cases([changed], 0, 1))

    def test_content_binding_cannot_be_missing_or_substituted(self) -> None:
        binding = {"aggregate_sha256": "a" * 64, "packs": [{"pack_id": "base", "pack_version": "0.4.0-dev", "schema_version": 2, "fingerprint_sha256": "b" * 64}]}
        self.assertEqual(matrix.validate_content_snapshot(binding), [])
        for changed in ({}, [], {**binding, "packs": []}, {**binding, "aggregate_sha256": "invalid"}, {**binding, "packs": [{**binding["packs"][0], "pack_id": "fixture"}]}, {**binding, "packs": [{**binding["packs"][0], "schema_version": True}]}):
            with self.subTest(binding=changed):
                self.assertTrue(matrix.validate_content_snapshot(changed))

    def test_damage_provenance_and_phase_totals_fail_closed(self) -> None:
        row = valid_row(0)
        self.assertEqual(matrix.validate_cases([row], 0, 1), [])
        for field in ("run_id", "target_id", "raw_run_id", "raw_target_id", "native_authenticated", "source_id", "frame", "hit_index", "phase_index", "accelerated"):
            changed = copy.deepcopy(row)
            changed["damage_trace"][0].pop(field)
            with self.subTest(missing=field):
                self.assertTrue(matrix.validate_cases([changed], 0, 1))
        for field, value in (("run_id", "other-run"), ("target_id", "other-body"), ("raw_run_id", "other-run"), ("raw_target_id", "other-body"), ("native_authenticated", False), ("source_id", "forged-source"), ("frame", 501), ("hit_index", -1), ("phase_index", True), ("accelerated", 1)):
            changed = copy.deepcopy(row)
            changed["damage_trace"][0][field] = value
            with self.subTest(field=field):
                self.assertTrue(matrix.validate_cases([changed], 0, 1))
        changed = copy.deepcopy(row)
        changed["phase_damage"]["0"] += 1
        self.assertTrue(matrix.validate_cases([changed], 0, 1))
        changed = copy.deepcopy(row)
        changed["damage_trace"].append(copy.deepcopy(changed["damage_trace"][0]))
        changed["phase_damage"]["0"] += 10
        self.assertTrue(matrix.validate_cases([changed], 0, 1))

    def test_observed_actions_and_positive_time_are_canonical(self) -> None:
        row = valid_row(0)
        for fields in ({"weapon_actions": ["junk"]}, {"weapon_actions": "charged_slash"}, {"boss_actions": {"traitor_blink": 1}}, {"boss_actions": {"guardian_fist_slam": True}}, {"positive_time": ["junk"]}, {"positive_time": "boss_stop_conversion"}, {"positive_time": ["accelerated_physical_hit"]}):
            changed = copy.deepcopy(row)
            changed.update(fields)
            with self.subTest(fields=fields):
                self.assertTrue(matrix.validate_cases([changed], 0, 1))

    def test_engine_log_errors_are_not_hidden_by_clean_stdout(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            logs = Path(directory)
            shard = logs / "native-000-001"
            shard.mkdir()
            (shard / "godot.log").write_text("ERROR: isolated engine diagnostic\n", encoding="utf-8")
            with patch.object(matrix.subprocess, "run", return_value=SimpleNamespace(stdout="PASS\n", returncode=0)):
                result = matrix.run_shard("unused-godot", 0, 1, logs, 10)
            self.assertIn("Godot contains an error, orphan or leak diagnostic", result["errors"])

    def test_authenticated_legacy_aliases_are_explicit(self) -> None:
        row = valid_row(0)
        row["damage_trace"][0].update(raw_run_id="legacy_run", raw_target_id="pending_target")
        self.assertEqual(matrix.validate_cases([row], 0, 1), [])
        row["damage_trace"][0]["native_authenticated"] = False
        self.assertTrue(matrix.validate_cases([row], 0, 1))
        row = valid_row(92)
        row["damage_trace"][0].update(raw_run_id="runtime", raw_target_id="target:12345")
        self.assertEqual(matrix.validate_cases([row], 92, 1), [])
        row["damage_trace"][0]["raw_target_id"] = "target:forged"
        self.assertTrue(matrix.validate_cases([row], 92, 1))

    def test_staff_burn_provenance_requires_its_exact_source_generation(self) -> None:
        row = valid_row(92)
        owner = "staff:1:staff_element_cast:0"
        burn = row["damage_trace"][0]
        burn.update(source_id="status:" + hashlib.sha256(f"{owner}|1|burn".encode()).hexdigest()[:40], attack_generation=2, tags=["weapon:staff", "element:fire", "status:burn", f"status_source:{owner}", "status_generation:1"])
        self.assertEqual(matrix.validate_cases([row], 92, 1), [])
        burn["source_id"] = "status:" + "0" * 40
        self.assertTrue(matrix.validate_cases([row], 92, 1))

    def test_time_receipts_require_their_exact_identity_and_physical_frame(self) -> None:
        row = valid_row(0)
        for field, value in (("runtime_frame", 20.5), ("runtime_frame", 501), ("owner_generation", True), ("action_generation", 0), ("action_token", -1), ("id", "0" * 64), ("endpoint", {"x": float("nan"), "y": 1}), ("facing", {"x": 0, "y": 0})):
            changed = copy.deepcopy(row)
            changed["time_casts"][0][field] = value
            with self.subTest(field=field, value=value):
                self.assertTrue(matrix.validate_cases([changed], 0, 1))


if __name__ == "__main__":
    unittest.main()
