import copy
import hashlib
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
CONTENT = ROOT / "data/content_packs/base/content"


class LaunchEncounterExtensionsTest(unittest.TestCase):
    def setUp(self):
        self.rows = json.loads((CONTENT / "launch_encounter_extensions.json").read_text())
        schema = json.loads((ROOT / "data/schemas/launch_encounter_extension_v1.schema.json").read_text())
        historic = json.loads((ROOT / "data/schemas/launch_encounter_profile_v1.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        registry = Registry().with_resource(historic["$id"], Resource.from_contents(historic))
        self.validator = Draft202012Validator(schema, registry=registry)

    def test_preserved_historical_authority_and_registered_additions(self):
        self.assertEqual(hashlib.sha256((CONTENT / "launch_encounters.json").read_bytes()).hexdigest(), "7a6399afe43c21a8e221dfd9c8fd1daafb2a7c7a559b3da0b6c60281cea53e40")
        self.assertEqual(len(self.rows), 2)
        pack = json.loads((CONTENT.parent / "pack.json").read_text())
        path = "content/launch_encounter_extensions.json"
        self.assertIn(path, pack["content_manifest"])
        self.assertEqual(pack["integrity_hashes"][path], hashlib.sha256((CONTENT / "launch_encounter_extensions.json").read_bytes()).hexdigest())
        for row, species in zip(self.rows, ["ruins_wraith", "void_spore"]):
            self.assertEqual(list(self.validator.iter_errors(row)), [])
            self.assertEqual(row["selection_revision"], 2)
            spawns = [spawn for wave in row["recipes"][0]["waves"] for spawn in wave["spawns"]]
            self.assertEqual([spawn["enemy_id"] for spawn in spawns if spawn["elite"]], [species])
            self.assertEqual(set(row["references"]), {row["profile_id"], *(spawn["enemy_id"] for spawn in spawns)})

    def test_closed_schema_refuses_missing_and_injected_fields(self):
        for row in self.rows:
            for field in row:
                forged = copy.deepcopy(row)
                del forged[field]
                self.assertTrue(list(self.validator.iter_errors(forged)), field)
            for path in [(), ("recipes", 0), ("recipes", 0, "waves", 0), ("recipes", 0, "waves", 0, "spawns", 0)]:
                forged = copy.deepcopy(row)
                target = forged
                for key in path:
                    target = target[key]
                target["runtime_script"] = "res://untrusted.gd"
                self.assertTrue(list(self.validator.iter_errors(forged)), path)
            for value in [0, 1, 3, True, "2"]:
                forged = copy.deepcopy(row)
                forged["selection_revision"] = value
                self.assertTrue(list(self.validator.iter_errors(forged)), value)
            forged = copy.deepcopy(row)
            forged["floor_id"] = "floor_plane_forge"
            self.assertTrue(list(self.validator.iter_errors(forged)))

    def test_native_geometry_budgets_and_complete_warnings(self):
        enemies = {row["id"]: row for row in json.loads((CONTENT / "enemies.json").read_text())}
        templates = {row["id"]: row for row in json.loads((CONTENT / "room_templates.json").read_text())}
        for index, row in enumerate(self.rows):
            recipe = row["recipes"][0]
            for wave in recipe["waves"]:
                self.assertGreaterEqual(wave["warning_frames"], 30 if index == 0 else 23)
                self.assertLessEqual(sum(enemies[spawn["enemy_id"]]["threat_cost"] + (3 if spawn["elite"] else 0) for spawn in wave["spawns"]), recipe["threat_budget"])
                for template_id in recipe["template_ids"]:
                    room = templates[template_id]
                    self.assertIn(row["floor_id"], room["floor_ids"])
                    anchor = next(anchor["position"] for anchor in room["spawn_anchors"] if anchor["id"] == "elite_primary")
                    entry = next(anchor["position"] for anchor in room["spawn_anchors"] if anchor["kind"] == "player")
                    points = [(anchor["x"] + spawn["spawn_offset"]["x"], anchor["y"] + spawn["spawn_offset"]["y"]) for spawn in wave["spawns"]]
                    bounds = room["camera_bounds"]
                    for point_index, (x, y) in enumerate(points):
                        self.assertGreaterEqual(x, bounds["x"] + 16)
                        self.assertLessEqual(x, bounds["x"] + bounds["width"] - 16)
                        self.assertGreaterEqual(y, bounds["y"] + 16)
                        self.assertLessEqual(y, bounds["y"] + bounds["height"] - 16)
                        self.assertGreaterEqual((x - entry["x"]) ** 2 + (y - entry["y"]) ** 2, 64 ** 2)
                        for previous_x, previous_y in points[:point_index]:
                            self.assertGreaterEqual((x - previous_x) ** 2 + (y - previous_y) ** 2, 32 ** 2)


if __name__ == "__main__":
    unittest.main()
