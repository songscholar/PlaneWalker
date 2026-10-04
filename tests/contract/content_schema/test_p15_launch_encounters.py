import copy
import csv
import hashlib
import json
import math
import unittest
from collections import Counter
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
CONTENT = ROOT / "data/content_packs/base/content"
SCHEMA = ROOT / "data/schemas/launch_encounter_profile_v1.schema.json"
FLOORS = ["floor_ruins_of_remnant", "floor_void_forest", "floor_time_rift", "floor_plane_forge", "floor_throne_of_void"]
BOSSES = ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
PROFILE_SUFFIXES = ["ruins", "forest", "rift", "forge", "throne"]
COMBAT_ROSTERS = [
    [("sentinel_line", ["shattered_sentinel"] * 3), ("watcher_guard", ["shattered_sentinel"] * 2 + ["rift_watcher"]), ("moth_crossfire", ["corrosive_moth"] * 2 + ["shattered_sentinel"]), ("wraith_shell", ["ruins_wraith", "stone_shell_strider"]), ("ruin_full", ["shattered_sentinel"] * 2 + ["corrosive_moth", "rift_watcher"])],
    [("hunter_archer", ["void_hunter"] * 2 + ["void_archer"]), ("bramble_spores", ["bramble_mage"] + ["void_spore"] * 3), ("caller_archer", ["forest_caller", "void_archer"]), ("lurker_hunter", ["shadow_lurker", "void_hunter"]), ("forest_full", ["void_hunter", "void_archer", "bramble_mage", "void_spore", "void_spore"])],
    [("guard_priest", ["chrono_guard", "rewind_priest"]), ("weaver_blink", ["rift_weaver", "blink_striker"]), ("hound_pack", ["eternal_hound"] * 3), ("storm_archer", ["chrono_storm_elemental", "void_archer", "void_archer"]), ("rift_full", ["chrono_guard", "rift_weaver", "blink_striker"])],
    [("titan_ranger", ["forge_titan", "phase_ranger"]), ("web_titan", ["void_web_weaver", "forge_titan"]), ("chaos_crossfire", ["chaos_amalgam", "void_archer"]), ("ripper_pack", ["plane_ripper", "void_hunter", "void_hunter"]), ("forge_full", ["forge_titan", "phase_ranger", "void_web_weaver"])],
    [("throne_front", ["chrono_guard", "forge_titan"]), ("throne_lanes", ["phase_ranger", "void_archer", "void_archer"]), ("throne_mirror", ["chaos_amalgam", "blink_striker"]), ("throne_space", ["plane_ripper", "rift_weaver"]), ("throne_guard", ["chrono_guard", "void_web_weaver", "rewind_priest"])],
]
ELITE_PARENTS = [
    [("sentinel_trial", 0, "shattered_sentinel"), ("shell_trial", 3, "stone_shell_strider"), ("watcher_trial", 1, "rift_watcher")],
    [("hunter_trial", 0, "void_hunter"), ("bramble_trial", 1, "bramble_mage"), ("caller_trial", 2, "forest_caller")],
    [("guard_trial", 0, "chrono_guard"), ("blink_trial", 1, "blink_striker"), ("storm_trial", 3, "chrono_storm_elemental")],
    [("titan_trial", 0, "forge_titan"), ("chaos_trial", 2, "chaos_amalgam"), ("ripper_trial", 3, "plane_ripper")],
    [("throne_titan_trial", 0, "forge_titan"), ("throne_chaos_trial", 2, "chaos_amalgam"), ("throne_blink_trial", 2, "blink_striker")],
]


class LaunchEncounterContentTest(unittest.TestCase):
    def rows(self):
        path = CONTENT / "launch_encounters.json"
        self.assertTrue(path.is_file(), "forty Launch recipes require an authoritative authored catalog")
        return json.loads(path.read_text(encoding="utf-8"))

    def validator(self):
        self.assertTrue(SCHEMA.is_file(), "Launch encounter profiles require a closed schema")
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        return Draft202012Validator(schema)

    def test_exact_profiles_rosters_and_elite_composition(self):
        rows = self.rows()
        self.assertEqual(len(rows), 5)
        self.assertEqual([row["id"] for row in rows], [f"encounter_profile_{suffix}_adapter_v1" for suffix in PROFILE_SUFFIXES])
        self.assertEqual(sum(len(row["recipes"]) for row in rows), 40)
        for floor, profile in enumerate(rows):
            self.assertEqual((profile["floor_id"], profile["boss_id"]), (FLOORS[floor], BOSSES[floor]))
            self.assertEqual(profile["boss_encounter_id"], f"boss_encounter_{BOSSES[floor]}_adapter_v1")
            self.assertEqual([recipe["id"] for recipe in profile["recipes"][:5]], [recipe_id for recipe_id, _ in COMBAT_ROSTERS[floor]])
            for recipe, (_, expected) in zip(profile["recipes"][:5], COMBAT_ROSTERS[floor]):
                spawns = [spawn for wave in recipe["waves"] for spawn in wave["spawns"]]
                self.assertEqual(Counter(spawn["enemy_id"] for spawn in spawns), Counter(expected))
                self.assertTrue(all(not spawn["elite"] for spawn in spawns))
            for recipe, (recipe_id, parent_index, elite_id) in zip(profile["recipes"][5:], ELITE_PARENTS[floor]):
                self.assertEqual(recipe["id"], recipe_id)
                spawns = [spawn for wave in recipe["waves"] for spawn in wave["spawns"]]
                self.assertEqual([spawn["enemy_id"] for spawn in spawns if spawn["elite"]], [elite_id])
                actual = Counter(spawn["enemy_id"] for spawn in spawns)
                parent = Counter(COMBAT_ROSTERS[floor][parent_index][1])
                self.assertTrue(all(actual[enemy_id] >= count for enemy_id, count in parent.items()))
                self.assertEqual(sum(actual.values()), sum(parent.values()) + 1, "elite replaces one base actor and adds exactly one escort")

    def test_closed_schema_and_nested_refusal(self):
        validator = self.validator()
        for row in self.rows():
            self.assertEqual(list(validator.iter_errors(row)), [])
            for key in row:
                bad = copy.deepcopy(row)
                del bad[key]
                self.assertTrue(list(validator.iter_errors(bad)), key)
            for path in [(), ("recipes", 0), ("recipes", 0, "waves", 0), ("recipes", 0, "waves", 0, "spawns", 0), ("recipes", 0, "waves", 0, "spawns", 0, "spawn_offset")]:
                bad = copy.deepcopy(row)
                target = bad
                for key in path:
                    target = target[key]
                target["runtime_script"] = "res://untrusted.gd"
                self.assertTrue(list(validator.iter_errors(bad)), path)
                original = row
                for key in path:
                    original = original[key]
                for field in original:
                    bad = copy.deepcopy(row)
                    target = bad
                    for key in path:
                        target = target[key]
                    del target[field]
                    self.assertTrue(list(validator.iter_errors(bad)), (path, field))
            for field, value in [("threat_budget", True), ("threat_budget", 1), ("threat_budget", 4.5)]:
                bad = copy.deepcopy(row)
                bad["recipes"][0][field] = value
                self.assertTrue(list(validator.iter_errors(bad)))
            for value in [True, 1, 16.5]:
                bad = copy.deepcopy(row)
                bad["recipes"][0]["waves"][0]["spawns"][0]["spawn_offset"]["x"] = value
                self.assertTrue(list(validator.iter_errors(bad)))
            bad = copy.deepcopy(row)
            bad["recipes"][1]["id"] = bad["recipes"][0]["id"]
            self.assertTrue(list(validator.iter_errors(bad)), "missing and repeated recipe identities reject")

    def test_actual_references_wave_budgets_and_spawn_margins(self):
        enemies = {row["id"]: row for row in json.loads((CONTENT / "enemies.json").read_text(encoding="utf-8"))}
        templates = {row["id"]: row for row in json.loads((CONTENT / "room_templates.json").read_text(encoding="utf-8"))}
        for floor, profile in enumerate(self.rows()):
            references = {profile["boss_id"]}
            combat_templates = set()
            elite_templates = set()
            for recipe in profile["recipes"]:
                self.assertLessEqual(len(recipe["waves"]), 3)
                for wave in recipe["waves"]:
                    threat = sum(enemies[spawn["enemy_id"]]["threat_cost"] + (3 if spawn["elite"] else 0) for spawn in wave["spawns"])
                    self.assertLessEqual(threat, recipe["threat_budget"])
                    self.assertGreaterEqual(wave["warning_frames"], 30 if floor == 0 else 23)
                    self.assertLessEqual(len(wave["spawns"]), 8)
                    for spawn in wave["spawns"]:
                        references.add(spawn["enemy_id"])
                        self.assertEqual(spawn["spawn_slot_id"], "elite_primary" if recipe["room_type"] == "elite" else "enemy_wave_primary")
                        self.assertEqual(len(spawn["affix_ids"]), (1 if floor < 2 else 2) if spawn["elite"] else 0)
                        self.assertEqual(spawn["mechanism_ids"], [])
                        self.assertEqual(spawn["spawn_offset"]["x"] % 16, 0)
                        self.assertEqual(spawn["spawn_offset"]["y"] % 16, 0)
                    for template_id in recipe["template_ids"]:
                        template = templates[template_id]
                        self.assertEqual(template["room_type"], recipe["room_type"])
                        self.assertIn(profile["floor_id"], template["floor_ids"])
                        anchor_id = "elite_primary" if recipe["room_type"] == "elite" else "enemy_wave_primary"
                        anchor = next(anchor["position"] for anchor in template["spawn_anchors"] if anchor["id"] == anchor_id)
                        entry = next(anchor["position"] for anchor in template["spawn_anchors"] if anchor["kind"] == "player")
                        bounds = template["camera_bounds"]
                        points = [(anchor["x"] + spawn["spawn_offset"]["x"], anchor["y"] + spawn["spawn_offset"]["y"]) for spawn in wave["spawns"]]
                        for index, (x, y) in enumerate(points):
                            self.assertGreaterEqual(x, bounds["x"] + 16)
                            self.assertLessEqual(x, bounds["x"] + bounds["width"] - 16)
                            self.assertGreaterEqual(y, bounds["y"] + 16)
                            self.assertLessEqual(y, bounds["y"] + bounds["height"] - 16)
                            self.assertGreaterEqual(math.dist((x, y), (entry["x"], entry["y"])), 64)
                            for other in points[index + 1:]:
                                self.assertGreaterEqual(math.dist((x, y), other), 32)
                (combat_templates if recipe["room_type"] == "combat" else elite_templates).update(recipe["template_ids"])
            self.assertEqual(set(profile["references"]), references)
            for room_type, actual in [("combat", combat_templates), ("elite", elite_templates)]:
                compatible = {row["id"] for row in templates.values() if row["room_type"] == room_type and profile["floor_id"] in row["floor_ids"]}
                self.assertEqual(actual, compatible, "every floor-compatible authored template has a recipe")

    def test_bilingual_profile_keys_and_integrity_bound_activation(self):
        for path in [ROOT / "data/localization/translations.csv", ROOT / "data/content_packs/base/localization/translations.csv"]:
            with path.open(encoding="utf-8", newline="") as handle:
                rows = {row["keys"]: row for row in csv.DictReader(handle)}
            for profile in self.rows():
                for field in ["name_key", "description_key"]:
                    self.assertTrue(rows[profile[field]]["en"].strip())
                    self.assertTrue(rows[profile[field]]["zh_CN"].strip())
        pack = json.loads((ROOT / "data/content_packs/base/pack.json").read_text(encoding="utf-8"))
        self.assertIn("content/launch_encounters.json", pack["content_manifest"])
        self.assertEqual(
            pack["integrity_hashes"]["content/launch_encounters.json"],
            hashlib.sha256((CONTENT / "launch_encounters.json").read_bytes()).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
