import copy
import csv
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
CONTENT = ROOT / "data/content_packs/base/content"
SCHEMAS = ROOT / "data/schemas"
FILES = {
    "enemy_definition": ("enemies.json", "enemy_definition_v1.schema.json", 22),
    "boss_definition": ("bosses.json", "boss_definition_v1.schema.json", 5),
    "elite_affix_definition": ("elite_affixes.json", "elite_affix_v1.schema.json", 10),
    "summon_definition": ("summons.json", "summon_definition_v1.schema.json", 9),
}
ENEMIES = [
    "shattered_sentinel", "corrosive_moth", "stone_shell_strider", "ruins_wraith", "rift_watcher",
    "void_hunter", "void_archer", "bramble_mage", "void_spore", "forest_caller", "shadow_lurker",
    "chrono_guard", "rift_weaver", "blink_striker", "rewind_priest", "chrono_storm_elemental", "eternal_hound",
    "forge_titan", "void_web_weaver", "phase_ranger", "chaos_amalgam", "plane_ripper",
]
BOSSES = ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
FLOORS = ["floor_ruins_of_remnant", "floor_void_forest", "floor_time_rift", "floor_plane_forge", "floor_throne_of_void"]


class P15HostileSchemaTest(unittest.TestCase):
    def catalog(self, category):
        path = CONTENT / FILES[category][0]
        self.assertTrue(path.is_file(), f"real authored {category} catalog must exist")
        return json.loads(path.read_text(encoding="utf-8"))

    def validator(self, category):
        registry = Registry()
        for name in ["hostile_action_v1.schema.json", *[row[1] for row in FILES.values()]]:
            path = SCHEMAS / name
            self.assertTrue(path.is_file(), f"closed {name} must exist")
            schema = json.loads(path.read_text(encoding="utf-8"))
            Draft202012Validator.check_schema(schema)
            registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
        schema = json.loads((SCHEMAS / FILES[category][1]).read_text(encoding="utf-8"))
        return Draft202012Validator(schema, registry=registry)

    def test_exact_catalog_counts_and_identity_closure(self):
        for category, (_, _, count) in FILES.items():
            rows = self.catalog(category)
            self.assertEqual(len(rows), count)
            self.assertEqual(len({row["id"] for row in rows}), count)
            self.assertTrue(all(row["category"] == category for row in rows))
        self.assertEqual([row["id"] for row in self.catalog("enemy_definition")], ENEMIES)
        self.assertEqual([row["id"] for row in self.catalog("boss_definition")], BOSSES)

    def test_all_authored_definitions_pass_closed_schemas(self):
        for category in FILES:
            validator = self.validator(category)
            for row in self.catalog(category):
                with self.subTest(category=category, id=row["id"]):
                    self.assertEqual(list(validator.iter_errors(row)), [])

    def test_exact_boss_move_and_response_counts(self):
        rows = self.catalog("boss_definition")
        self.assertEqual([len(row["actions"]) for row in rows], [8, 8, 8, 11, 13])
        self.assertEqual(sum(len(row["time_responses"]) for row in rows), 4)
        self.assertEqual(len(rows[2]["time_responses"]), 4)
        for row in rows:
            ids = {action["id"] for action in row["actions"]}
            self.assertEqual(len(ids), len(row["actions"]))
            previous = 2.0
            for phase in row["phases"]:
                self.assertLess(phase["hp_threshold"], previous)
                previous = phase["hp_threshold"]
                self.assertTrue(set(phase["action_ids"]) <= ids)

    def test_actual_warning_recovery_and_hit_boundaries(self):
        for category in ["enemy_definition", "boss_definition"]:
            for row in self.catalog(category):
                floor_index = FLOORS.index(row["floor_id"])
                warning = (40 if floor_index == 0 else 25 if floor_index == 4 else 30) if category == "boss_definition" else (30 if floor_index == 0 else 23)
                actions = row["actions"] + row.get("elite_actions", []) + row.get("time_responses", [])
                for action in actions:
                    self.assertGreaterEqual(action["warning_frames"], warning, action["id"])
                    if any(hit["damage"] > 0 for hit in action["hit_schedule"]):
                        self.assertGreaterEqual(action["recovery_frames"], 20 if category == "boss_definition" else 15)
                    self.assertEqual(len({hit["hit_index"] for hit in action["hit_schedule"]}), len(action["hit_schedule"]))
                    for hit in action["hit_schedule"]:
                        self.assertLess(hit["offset_frame"], action["active_frames"], action["id"])
        blink = next(row for row in self.catalog("enemy_definition") if row["id"] == "blink_striker")
        self.assertEqual(blink["elite_actions"][0]["active_frames"], 58)
        self.assertEqual([hit["offset_frame"] for hit in blink["elite_actions"][0]["hit_schedule"]], [0, 27, 54])

    def test_root_and_nested_unknown_fields_fail_closed(self):
        for category in FILES:
            validator = self.validator(category)
            row = self.catalog(category)[0]
            for field in row:
                bad = copy.deepcopy(row)
                del bad[field]
                self.assertTrue(list(validator.iter_errors(bad)), f"{category}.{field} is required")
            bad = copy.deepcopy(row)
            bad["runtime_script"] = "res://untrusted.gd"
            self.assertTrue(list(validator.iter_errors(bad)))
            bad = copy.deepcopy(row)
            bad["compatibility"]["unknown"] = True
            self.assertTrue(list(validator.iter_errors(bad)))
        row = self.catalog("enemy_definition")[0]
        validator = self.validator("enemy_definition")
        for target in ["action", "geometry", "hit", "parameters", "mechanisms"]:
            bad = copy.deepcopy(row)
            action = bad["actions"][0]
            container = {
                "action": action, "geometry": action["geometry"][0],
                "hit": action["hit_schedule"][0], "parameters": action["parameters"],
                "mechanisms": bad["mechanisms"],
            }[target]
            container["untrusted"] = True
            self.assertTrue(list(validator.iter_errors(bad)), target)
        bad = copy.deepcopy(row)
        bad["max_hp"] = True
        self.assertTrue(list(validator.iter_errors(bad)))
        bad = copy.deepcopy(row)
        bad["actions"][0]["handler_id"] = "runtime_script"
        self.assertTrue(list(validator.iter_errors(bad)))

    def test_nonrecursive_summons_and_symmetric_affix_exclusions(self):
        summons = self.catalog("summon_definition")
        for row in summons:
            self.assertGreaterEqual(row["spawn_warning_frames"], 30)
            self.assertFalse(row["reward_eligible"])
            self.assertEqual(row["capabilities"], [])
        affixes = {row["id"]: row for row in self.catalog("elite_affix_definition")}
        for id_, row in affixes.items():
            for exclusion in row["excluded_affix_ids"]:
                self.assertIn(id_, affixes[exclusion]["excluded_affix_ids"])

    def test_all_names_descriptions_and_cues_have_draft_localization(self):
        path = ROOT / "data/localization/drafts/p15_hostiles.csv"
        self.assertTrue(path.is_file(), "P15 localized draft must accompany authoring")
        with path.open(encoding="utf-8", newline="") as stream:
            translations = {row["keys"]: row for row in csv.DictReader(stream)}
        for category in FILES:
            for row in self.catalog(category):
                keys = [row["name_key"], row["description_key"]]
                for action in row.get("actions", []) + row.get("elite_actions", []) + row.get("time_responses", []):
                    keys.append("CUE_" + action["cue_id"].upper().replace(".", "_"))
                for key in keys:
                    self.assertIn(key, translations)
                    self.assertTrue(translations[key]["en"].strip())
                    self.assertTrue(translations[key]["zh_CN"].strip())


if __name__ == "__main__":
    unittest.main()
