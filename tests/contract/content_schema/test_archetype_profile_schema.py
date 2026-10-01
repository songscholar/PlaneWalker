import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = ROOT / "data/schemas/archetype_profile_v1.schema.json"
ENTRY_SCHEMA_PATH = ROOT / "data/schemas/content_entry_v2.schema.json"
CATALOG_PATH = ROOT / "data/content_packs/base/content/archetype_profiles.json"

EXPECTED_IDS = [
    "freeze_burst",
    "rewind_echo",
    "rift_trap",
    "accelerated_combo",
    "low_hp_void",
    "perfect_guard",
    "piercing_barrage",
    "echo_legion",
]

EXPECTED_BOSS_CONVERSIONS = {
    "freeze_burst": "boss_weakpoint_exposure",
    "rewind_echo": "boss_rewind_path_strike",
    "rift_trap": "boss_projectile_window",
    "accelerated_combo": "boss_combo_break",
    "low_hp_void": "boss_execute_warning",
    "perfect_guard": "boss_counter_window",
    "piercing_barrage": "boss_weakpoint_ammo_refund",
    "echo_legion": "boss_facing_lure",
}


class ArchetypeProfileSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.entry_schema = json.loads(ENTRY_SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        cls.validator = Draft202012Validator(cls.schema)
        cls.entry_validator = Draft202012Validator(cls.entry_schema)

    def test_schema_is_valid_draft_2020_12(self) -> None:
        Draft202012Validator.check_schema(self.schema)
        Draft202012Validator.check_schema(self.entry_schema)
        self.assertEqual(
            self.schema["$id"],
            "planewalker://schemas/archetype-profile/1.0.0",
        )
        self.assertFalse(self.schema["additionalProperties"])

    def test_generic_content_entry_schema_accepts_the_catalog(self) -> None:
        self.assertIn(
            "archetype_profile",
            self.entry_schema["properties"]["category"]["enum"],
        )
        for row in self.catalog:
            with self.subTest(archetype=row["archetype_id"]):
                self.assertEqual(list(self.entry_validator.iter_errors(row)), [])

    def test_generic_content_entry_schema_scopes_profile_only_fields(self) -> None:
        leaked_item = {
            "id": "profile_field_leak",
            "category": "item",
            "availability": ["LAUNCH"],
            "name_key": "PROFILE_FIELD_LEAK_NAME",
            "description_key": "PROFILE_FIELD_LEAK_DESC",
            "tags": ["test"],
            "compatibility": {},
            "effects": {},
            "kind": "utility",
            "archetype": "freeze_burst",
            "role": "starter",
            "rarity": "common",
            "icon_id": "content_profile_field_leak",
            "archetype_id": "freeze_burst",
        }
        self.assertTrue(list(self.entry_validator.iter_errors(leaked_item)))

    def test_exact_catalog_and_closed_values(self) -> None:
        self.assertEqual(
            [row["archetype_id"] for row in self.catalog],
            EXPECTED_IDS,
        )
        self.assertEqual(len({row["id"] for row in self.catalog}), 8)
        for row in self.catalog:
            with self.subTest(archetype=row["archetype_id"]):
                self.assertEqual(row["category"], "archetype_profile")
                self.assertEqual(row["profile_version"], 1)
                self.assertEqual(row["availability"], ["LAUNCH", "EXPANSION"])
                self.assertEqual(row["starter_min"], 3)
                self.assertEqual(row["payoff_min"], 2)
                self.assertEqual(row["risk_min"], 1)
                self.assertEqual(row["effects"], {})
                self.assertEqual(
                    row["boss_conversion_id"],
                    EXPECTED_BOSS_CONVERSIONS[row["archetype_id"]],
                )
                self.assertGreaterEqual(len(row["mechanic_tags"]), 4)
                self.assertEqual(
                    len(row["mechanic_tags"]),
                    len(set(row["mechanic_tags"])),
                )
                self.assertEqual(list(self.validator.iter_errors(row)), [])

    def test_root_is_closed_and_effects_are_empty(self) -> None:
        hostile = copy.deepcopy(self.catalog[0])
        hostile["script_path"] = "res://hostile.gd"
        self.assertTrue(list(self.validator.iter_errors(hostile)))

        executable = copy.deepcopy(self.catalog[0])
        executable["effects"] = {"attack_multiplier": 2.0}
        self.assertTrue(list(self.validator.iter_errors(executable)))

    def test_identity_and_version_fail_closed(self) -> None:
        version_two = copy.deepcopy(self.catalog[0])
        version_two["profile_version"] = 2
        self.assertTrue(list(self.validator.iter_errors(version_two)))

        unknown_id = copy.deepcopy(self.catalog[0])
        unknown_id["archetype_id"] = "heavy_cleave"
        self.assertTrue(list(self.validator.iter_errors(unknown_id)))

        overlong = copy.deepcopy(self.catalog[0])
        overlong["id"] = "a" * 65
        self.assertTrue(list(self.validator.iter_errors(overlong)))

        m1 = copy.deepcopy(self.catalog[0])
        m1["availability"] = ["M1"]
        self.assertTrue(list(self.validator.iter_errors(m1)))

    def test_coverage_minimums_are_exact(self) -> None:
        for field, value in [
            ("starter_min", 2),
            ("payoff_min", 1),
            ("risk_min", 0),
            ("starter_min", 3.5),
        ]:
            with self.subTest(field=field, value=value):
                hostile = copy.deepcopy(self.catalog[0])
                hostile[field] = value
                self.assertTrue(list(self.validator.iter_errors(hostile)))

        missing = copy.deepcopy(self.catalog[0])
        missing.pop("risk_min")
        self.assertTrue(list(self.validator.iter_errors(missing)))

    def test_mechanic_tags_are_nonempty_unique_and_closed(self) -> None:
        duplicate = copy.deepcopy(self.catalog[0])
        duplicate["mechanic_tags"].append(duplicate["mechanic_tags"][0])
        self.assertTrue(list(self.validator.iter_errors(duplicate)))

        empty = copy.deepcopy(self.catalog[0])
        empty["mechanic_tags"] = []
        self.assertTrue(list(self.validator.iter_errors(empty)))

        invalid = copy.deepcopy(self.catalog[0])
        invalid["mechanic_tags"][0] = "Invalid Tag"
        self.assertTrue(list(self.validator.iter_errors(invalid)))

    def test_boss_response_is_required_and_conversion_is_closed(self) -> None:
        missing = copy.deepcopy(self.catalog[0])
        missing.pop("boss_response_key")
        self.assertTrue(list(self.validator.iter_errors(missing)))

        unknown = copy.deepcopy(self.catalog[0])
        unknown["boss_conversion_id"] = "boss_hard_freeze"
        self.assertTrue(list(self.validator.iter_errors(unknown)))

        wrong_pair = copy.deepcopy(self.catalog[0])
        wrong_pair["boss_conversion_id"] = EXPECTED_BOSS_CONVERSIONS["rewind_echo"]
        self.assertTrue(list(self.validator.iter_errors(wrong_pair)))


if __name__ == "__main__":
    unittest.main()
