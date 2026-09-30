import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = ROOT / "data/schemas/character_runtime_profile_v1.schema.json"
ENTRY_SCHEMA_PATH = ROOT / "data/schemas/content_entry_v2.schema.json"
CATALOG_PATH = ROOT / "data/content_packs/base/content/character_runtime_profiles.json"
ITEM_CATALOG_PATH = ROOT / "data/content_packs/base/content/items.json"
WEAPON_PROFILE_CATALOG_PATH = (
    ROOT / "data/content_packs/base/content/weapon_runtime_profiles.json"
)


class CharacterRuntimeProfileSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.entry_schema = json.loads(ENTRY_SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        cls.items = json.loads(ITEM_CATALOG_PATH.read_text(encoding="utf-8"))
        cls.weapon_profiles = json.loads(
            WEAPON_PROFILE_CATALOG_PATH.read_text(encoding="utf-8")
        )
        cls.validator = Draft202012Validator(cls.schema)
        cls.entry_validator = Draft202012Validator(cls.entry_schema)

    def test_schema_is_valid_draft_2020_12(self) -> None:
        Draft202012Validator.check_schema(self.schema)

    def test_all_authoritative_profiles_validate(self) -> None:
        self.assertEqual(len(self.catalog), 6)
        for profile in self.catalog:
            with self.subTest(profile=profile["id"]):
                self.assertEqual(list(self.validator.iter_errors(profile)), [])

    def test_parameter_value_one_of_is_non_overlapping(self) -> None:
        parameter_validator = Draft202012Validator(
            {
                "$schema": "https://json-schema.org/draft/2020-12/schema",
                "$defs": self.schema["$defs"],
                "$ref": "#/$defs/parameter_value",
            }
        )
        for value in [1, 1.5, True, "value"]:
            with self.subTest(value=value):
                self.assertEqual(list(parameter_validator.iter_errors(value)), [])

        for value in [[1, False], {"nested": 2}]:
            with self.subTest(value=value):
                self.assertTrue(list(parameter_validator.iter_errors(value)))

        branch_types = [
            branch.get("type")
            for branch in self.schema["$defs"]["parameter_value"]["oneOf"]
        ]
        self.assertIn("number", branch_types)
        self.assertNotIn("integer", branch_types)

    def test_closed_root_and_sixty_four_character_ids_fail_closed(self) -> None:
        hostile = copy.deepcopy(self.catalog[0])
        hostile["script_path"] = "res://hostile.gd"
        self.assertTrue(list(self.validator.iter_errors(hostile)))

        overlong = copy.deepcopy(self.catalog[0])
        overlong["id"] = "a" * 65
        self.assertTrue(list(self.validator.iter_errors(overlong)))

    def test_v1_version_and_handler_parameters_fail_closed(self) -> None:
        version_two = copy.deepcopy(self.catalog[0])
        version_two["profile_version"] = 2
        self.assertTrue(list(self.validator.iter_errors(version_two)))

        missing_parameter = copy.deepcopy(self.catalog[2])
        missing_parameter["passive"]["parameters"].pop("damage_reduction")
        self.assertTrue(list(self.validator.iter_errors(missing_parameter)))

        extra_parameter = copy.deepcopy(self.catalog[4])
        extra_parameter["character_skill"]["parameters"]["hidden_payload"] = 1
        self.assertTrue(list(self.validator.iter_errors(extra_parameter)))

        wrong_exact_value = copy.deepcopy(self.catalog[5])
        wrong_exact_value["time_interactions"]["stop"]["parameters"][
            "rewind_zone_radius"
        ] = 97
        self.assertTrue(list(self.validator.iter_errors(wrong_exact_value)))

    def test_unsupported_compatibility_constraints_fail_closed(self) -> None:
        for field in ["archetype_ids", "modes"]:
            with self.subTest(field=field):
                hostile = copy.deepcopy(self.catalog[0])
                hostile["compatibility"][field] = ["normal"]
                self.assertTrue(list(self.validator.iter_errors(hostile)))
                self.assertEqual(list(self.entry_validator.iter_errors(hostile)), [])

        empty_character_scope = copy.deepcopy(self.catalog[0])
        empty_character_scope["compatibility"]["character_ids"] = []
        self.assertTrue(list(self.validator.iter_errors(empty_character_scope)))
        self.assertEqual(
            list(self.entry_validator.iter_errors(empty_character_scope)), []
        )

    def test_frozen_v2_entry_schema_preserves_legacy_compatibility_and_versions(self) -> None:
        for compatibility in [
            {"character_ids": []},
            {"weapon_ids": []},
            {"time_ability_ids": []},
            {"archetype_ids": ["legacy_archetype"]},
            {"modes": ["normal"]},
        ]:
            with self.subTest(compatibility=compatibility):
                entry = copy.deepcopy(self.items[0])
                entry["compatibility"] = compatibility
                self.assertEqual(list(self.entry_validator.iter_errors(entry)), [])

        weapon_v2 = copy.deepcopy(self.weapon_profiles[0])
        weapon_v2["profile_version"] = 2
        self.assertEqual(list(self.entry_validator.iter_errors(weapon_v2)), [])

        character_v2 = copy.deepcopy(self.catalog[0])
        character_v2["profile_version"] = 2
        self.assertTrue(list(self.entry_validator.iter_errors(character_v2)))

    def test_generic_entry_schema_rejects_character_only_fields(self) -> None:
        for field, value in [
            ("character_id", "wanderer"),
            ("base_stats", {}),
            ("mobility", {}),
            ("resource", {}),
            ("passive", {}),
            ("character_skill", {}),
            ("weapon_mastery", {}),
            ("presentation", {}),
            ("talent_ids", []),
        ]:
            with self.subTest(field=field):
                hostile = copy.deepcopy(self.items[0])
                hostile[field] = value
                self.assertTrue(list(self.entry_validator.iter_errors(hostile)))

    def test_character_profiles_validate_as_generic_v2_entries(self) -> None:
        for profile in self.catalog:
            with self.subTest(profile=profile["id"]):
                self.assertEqual(list(self.entry_validator.iter_errors(profile)), [])


if __name__ == "__main__":
    unittest.main()
