from __future__ import annotations

import copy
import hashlib
from pathlib import Path
import sys
import unittest


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
        "damage_trace": [{"amount": 10, "actual_loss": 10, "attack_generation": 1, "tags": [f"weapon:{identity['weapon_id']}"]}],
        "time_casts": [{"ability_id": ability, "run_id": run_id, "runtime_frame": 20 + offset, "id": str(offset) * 64} for offset, ability in enumerate(identity["time_abilities"])],
        "positive_time": ["boss_stop_conversion"],
        "weapon_actions": ["primary"],
        "boss_actions": {"authored": 1},
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


if __name__ == "__main__":
    unittest.main()
