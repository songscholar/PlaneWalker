import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
SCHEMAS = ROOT / "data/schemas"
CONTENT = ROOT / "data/content_packs/base/content"
MAX_VALUE = 2147483647
WEAPONS = ["bow", "gauntlets", "gun", "staff", "sword"]
CHARACTERS = ["primordial_knight", "time_guardian", "time_lord", "void_walker", "wanderer"]
NPCS = ["elara", "hermes", "morpheus", "nemesis", "odysseus", "phia", "sibyl", "vera"]
FACTIONS = ["council", "merchants", "shardborn", "void_cult"]
HIDDEN = ["primordial_whispers", "voice_of_void", "walkers_song"]


def catalog(name):
    return json.loads((CONTENT / f"{name}.json").read_text())


def references():
    refs = {
        "item_id": sorted(row["id"] for row in catalog("items")),
        "meta_node_id": sorted(row["node_id"] for row in catalog("meta_nodes")),
        "enchantment_id": sorted(row["enchantment_id"] for row in catalog("forge_definitions") if row["definition_kind"] == "enchantment"),
    }
    flags = set()

    def collect(value):
        if isinstance(value, list):
            for child in value:
                collect(child)
        elif isinstance(value, dict):
            for key, child in value.items():
                if key in ("resolution_flag", "completion_flag"):
                    flags.add(child)
                elif key == "flags" and isinstance(child, list):
                    flags.update(child)
                else:
                    collect(child)

    narrative = catalog("narrative_definitions")
    collect(narrative)
    refs["narrative_flag_id"] = sorted(flags)
    for kind, field in [("artifact", "artifact_id"), ("environment_record", "record_id"), ("ending", "ending_id")]:
        refs[kind + "_id"] = sorted(row[field] for row in narrative if row["definition_kind"] == kind)
    tutorial = catalog("tutorial_definitions")
    for kind, field in [("lesson", "lesson_id"), ("hint", "hint_id")]:
        refs["tutorial_" + kind + "_id"] = sorted(row[field] for row in tutorial if row["definition_kind"] == kind)
    legacy = json.loads((ROOT / "data/content/meta_legacy_references.json").read_text())
    for category in ("achievement", "cosmetic"):
        refs[category + "_id"] = sorted(legacy[category])
    return refs


def fresh_profile():
    return {
        "schema_id": "planewalker.meta_profile_state", "schema_version": 1,
        "catalog_fingerprint": "a" * 64, "revision": 0,
        "chronos_shards": 0, "existential_imprints": 0,
        "unlocked_nodes": [], "discovered_items": [],
        "unlocked_characters": ["wanderer"], "unlocked_weapons": ["bow", "sword"],
        "weapon_proficiency": dict.fromkeys(WEAPONS, 0),
        "forge_state": {weapon: {"level": 0, "enchant_preferences": [], "void_tempered": False} for weapon in WEAPONS},
        "npc_affinity": dict.fromkeys(NPCS, 0), "faction_standing": dict.fromkeys(FACTIONS, 0),
        "narrative_state": {
            "flags": [], "artifacts": [], "environment_records": [], "hidden_steps": dict.fromkeys(HIDDEN, 0),
            "nemesis_choices": [], "vera_conversations": 0, "heart_fragments": [], "endings": [],
            "credits_completed": [], "void_exposure_frames": 0, "consumed_sources": [], "balance_choice_sources": [],
        },
        "tutorial_state": {"completed_lessons": [], "skipped_lessons": [], "seen_hints": [], "suppressed": False, "guided_runs_completed": 0},
        "build_library": [], "repair_stage": 0, "launch_sequence": 0,
        "active_launch_receipt": {}, "last_settlement_receipt": {}, "completed_command_ids": [],
        "completed_boss_ids": [], "unlocked_achievements": [], "cosmetics": [], "soul_reserve": 0,
        "statistics": {"finished_runs": 0, "victories": 0, "deaths": 0, "abandons": 0},
    }


def rich_profile():
    profile = fresh_profile()
    refs = references()
    profile.update({"unlocked_nodes": refs["meta_node_id"], "unlocked_characters": CHARACTERS,
                    "unlocked_weapons": WEAPONS, "discovered_items": refs["item_id"], "launch_sequence": 2})
    for state in profile["forge_state"].values():
        state.update({"level": 5, "enchant_preferences": ["EN-01", "EN-04"], "void_tempered": True})
    profile["narrative_state"].update({"flags": refs["narrative_flag_id"], "artifacts": refs["artifact_id"],
        "environment_records": refs["environment_record_id"], "endings": refs["ending_id"],
        "credits_completed": refs["ending_id"], "nemesis_choices": ["spare", "spare", "attack"],
        "consumed_sources": ["source:1"], "balance_choice_sources": ["source:1"]})
    profile["tutorial_state"].update({"completed_lessons": refs["tutorial_lesson_id"], "seen_hints": refs["tutorial_hint_id"]})
    profile["build_library"] = [{"id": "build:1", "name": "Bow time", "character_id": "wanderer", "weapon_id": "bow", "time_abilities": ["stop", "rewind"]}]
    profile["active_launch_receipt"] = {"schema_id": "meta_launch_receipt_v1", "sequence": 2, "run_id": "run:2", "difficulty": "hard", "seed": 12,
        "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rift"], "projection_digest": "b" * 64}
    profile["last_settlement_receipt"] = {"schema_id": "meta_settlement_receipt_v1", "sequence": 1, "run_id": "run:1", "terminal_reason": "victory",
        "shards": 12, "imprints": 1, "soul_reserve": 3, "digest": "c" * 64}
    return profile


def object_paths(value, prefix=()):
    paths = []
    if isinstance(value, dict):
        paths.append(prefix)
        for key, child in value.items():
            paths.extend(object_paths(child, prefix + (key,)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            paths.extend(object_paths(child, prefix + (index,)))
    return paths


class P16ProfileSchemasTest(unittest.TestCase):
    def validator(self, filename):
        path = SCHEMAS / filename
        self.assertTrue(path.is_file(), f"Missing closed P16 save schema: {path}")
        registry = Registry()
        for resource_path in SCHEMAS.glob("*.schema.json"):
            value = json.loads(resource_path.read_text())
            Draft202012Validator.check_schema(value)
            resource = Resource.from_contents(value)
            registry = registry.with_resource(resource_path.as_uri(), resource)
            if "$id" in value:
                registry = registry.with_resource(value["$id"], resource)
        return Draft202012Validator(json.loads(path.read_text()), registry=registry, format_checker=FormatChecker())

    def test_fresh_and_rich_profiles_and_integral_json_floats_are_accepted(self):
        validator = self.validator("meta_profile_state_v1.schema.json")
        for profile in (fresh_profile(), rich_profile()):
            self.assertEqual(list(validator.iter_errors(profile)), [])
        integral = fresh_profile()
        integral["revision"] = 0.0
        integral["schema_version"] = 1.0
        integral["weapon_proficiency"]["sword"] = 100.0
        self.assertTrue(validator.is_valid(integral))

    def test_real_native_profile_and_migrated_envelope_fixtures_are_accepted(self):
        profile = json.loads((ROOT / "tests/fixtures/save/meta_profile_v1.json").read_text())
        envelope = json.loads((ROOT / "tests/fixtures/save/profile_v4.json").read_text())
        self.assertEqual(list(self.validator("meta_profile_state_v1.schema.json").iter_errors(profile)), [])
        self.assertEqual(list(self.validator("save_profile_v4.schema.json").iter_errors(envelope)), [])
        self.assertEqual(envelope["payload"]["meta_profile_state"]["catalog_fingerprint"], profile["catalog_fingerprint"])
        self.assertEqual(envelope["payload"]["unlocked_weapons"], ["bow", "sword"])
        self.assertEqual(envelope["payload"]["runs_completed"], 6)

    def test_real_native_in_flight_v4_envelope_accepts_event_state_slot(self):
        envelope = json.loads((ROOT / "tests/fixtures/save/profile_active_v4.json").read_text())
        validator = self.validator("save_profile_v4.schema.json")
        run = envelope["payload"]["active_run_state"]
        self.assertIn("dungeon_event_runtime", run)
        self.assertIn("meta_run_projection", run["resources"])
        self.assertEqual(list(validator.iter_errors(envelope)), [])
        run["unexpected_field"] = True
        self.assertFalse(validator.is_valid(envelope))

    def test_every_meta_object_is_closed_and_requires_all_fields(self):
        validator = self.validator("meta_profile_state_v1.schema.json")
        profile = rich_profile()
        for path in object_paths(profile):
            mutated = copy.deepcopy(profile)
            cursor = mutated
            for part in path:
                cursor = cursor[part]
            cursor["unexpected_field"] = True
            with self.subTest(path=path, mutation="unknown"):
                self.assertFalse(validator.is_valid(mutated))
            for key in list(cursor):
                if key == "unexpected_field":
                    continue
                missing = copy.deepcopy(profile)
                target = missing
                for part in path:
                    target = target[part]
                del target[key]
                with self.subTest(path=path, mutation="missing", key=key):
                    self.assertFalse(validator.is_valid(missing))

    def test_schema_reference_enums_match_authoritative_base_catalogs(self):
        self.validator("meta_profile_state_v1.schema.json")
        schema = json.loads((SCHEMAS / "meta_profile_state_v1.schema.json").read_text())
        for name, values in references().items():
            self.assertEqual(schema["$defs"][name]["enum"], values)

    def test_integer_bounds_and_id_sets_reject_corrupt_profiles(self):
        validator = self.validator("meta_profile_state_v1.schema.json")
        for value in (True, -1, 0.25, MAX_VALUE + 1):
            for field in ("revision", "chronos_shards", "existential_imprints", "launch_sequence", "soul_reserve"):
                profile = fresh_profile()
                profile[field] = value
                self.assertFalse(validator.is_valid(profile), (field, value))
        for field in ("unlocked_nodes", "discovered_items", "unlocked_characters", "unlocked_weapons", "completed_boss_ids", "unlocked_achievements", "cosmetics"):
            profile = fresh_profile()
            profile[field].append("forged_id")
            self.assertFalse(validator.is_valid(profile), field)
        for field in ("unlocked_characters", "unlocked_weapons"):
            profile = fresh_profile()
            profile[field] *= 2
            self.assertFalse(validator.is_valid(profile), field)
            profile[field] = []
            self.assertFalse(validator.is_valid(profile), field)
        for fingerprint in ("", "A" * 64, "a" * 63):
            profile = fresh_profile()
            profile["catalog_fingerprint"] = fingerprint
            self.assertFalse(validator.is_valid(profile))

    def test_prerequisite_closure_and_forge_unlocks_are_required(self):
        validator = self.validator("meta_profile_state_v1.schema.json")
        for row in catalog("meta_nodes"):
            if row["prerequisites"]:
                profile = fresh_profile()
                profile["unlocked_nodes"] = [row["node_id"]]
                self.assertFalse(validator.is_valid(profile), row["node_id"])
        for field, value in [("level", 1), ("enchant_preferences", ["EN-01"]), ("enchant_preferences", ["EN-01", "EN-04"]), ("void_tempered", True)]:
            profile = fresh_profile()
            profile["forge_state"]["sword"][field] = value
            self.assertFalse(validator.is_valid(profile), field)

    def test_nested_references_and_receipts_reject_corruption(self):
        validator = self.validator("meta_profile_state_v1.schema.json")
        for parent, field in [("narrative_state", "flags"), ("narrative_state", "artifacts"), ("narrative_state", "environment_records"),
                              ("narrative_state", "endings"), ("tutorial_state", "completed_lessons"), ("tutorial_state", "seen_hints")]:
            profile = fresh_profile()
            profile[parent][field] = ["forged_id"]
            self.assertFalse(validator.is_valid(profile), (parent, field))
        for location in ("active_launch_receipt", "build_library"):
            profile = rich_profile()
            record = profile[location] if location == "active_launch_receipt" else profile[location][0]
            record["time_abilities"] = ["stop", "stop"]
            self.assertFalse(validator.is_valid(profile), location)
        for location, key, value in [("active_launch_receipt", "sequence", 0), ("active_launch_receipt", "difficulty", "easy"),
                                     ("last_settlement_receipt", "terminal_reason", "ongoing"), ("last_settlement_receipt", "shards", True)]:
            profile = rich_profile()
            profile[location][key] = value
            self.assertFalse(validator.is_valid(profile), (location, key))
        for name in ("", "n" * 65, "nul\x00name"):
            profile = rich_profile()
            profile["build_library"][0]["name"] = name
            self.assertFalse(validator.is_valid(profile), name)

    def test_enchantment_exclusion_and_authored_legacy_references(self):
        validator = self.validator("meta_profile_state_v1.schema.json")
        for pair in [("EN-01", "EN-02"), ("EN-01", "EN-03"), ("EN-02", "EN-03"), ("EN-04", "EN-05")]:
            profile = rich_profile()
            profile["forge_state"]["sword"]["enchant_preferences"] = list(pair)
            self.assertFalse(validator.is_valid(profile), pair)
        profile = fresh_profile()
        refs = references()
        profile["unlocked_achievements"] = refs["achievement_id"]
        profile["cosmetics"] = refs["cosmetic_id"]
        self.assertTrue(validator.is_valid(profile))

    def test_v4_envelope_keeps_legacy_extensions_and_strict_meta_state(self):
        validator = self.validator("save_profile_v4.schema.json")
        envelope = json.loads((ROOT / "tests/fixtures/save/profile_v3.json").read_text())
        self.assertFalse(validator.is_valid(envelope))
        envelope["schema_version"] = 4
        profile = fresh_profile()
        profile["chronos_shards"] = envelope["payload"]["chronos_shards"]
        profile["existential_imprints"] = envelope["payload"]["existential_imprints"]
        envelope["payload"].update({"meta_profile_state": profile, "unlocked_weapons": ["bow", "sword"], "legacy_extension": {"future": True}})
        self.assertEqual(list(validator.iter_errors(envelope)), [])
        for field in ("active_item_state", "reward_effect_state", "active_run_state", "meta_profile_state"):
            invalid = copy.deepcopy(envelope)
            del invalid["payload"][field]
            self.assertFalse(validator.is_valid(invalid), field)
        for field, value in [("chronos_shards", True), ("existential_imprints", -1), ("weapon_proficiency", {"sword": 0}),
                             ("unlocked_nodes", ["node_guard_1"]), ("cosmetics", ["forged_id"])]:
            invalid = copy.deepcopy(envelope)
            invalid["payload"][field] = value
            self.assertFalse(validator.is_valid(invalid), field)
        for path in ((), ("content_snapshot",), ("content_snapshot", "packs", 0), ("integrity",), ("payload", "meta_profile_state")):
            invalid = copy.deepcopy(envelope)
            cursor = invalid
            for part in path:
                cursor = cursor[part]
            cursor["unexpected_field"] = True
            self.assertFalse(validator.is_valid(invalid), path)

    def test_v3_settings_and_profile_contracts_remain_accepted(self):
        for kind in ("profile", "settings"):
            fixture = json.loads((ROOT / f"tests/fixtures/save/{kind}_v3.json").read_text())
            self.assertEqual(list(self.validator(f"save_{kind}_v3.schema.json").iter_errors(fixture)), [])


if __name__ == "__main__":
    unittest.main()
