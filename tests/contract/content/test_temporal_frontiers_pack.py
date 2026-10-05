import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PACK = ROOT / "data/content_packs/temporal_frontiers"
IDS = ["echo_lancer", "mire_cantor", "parallax_guard", "cinder_drake", "prism_seer"]


class TemporalFrontiersPackTests(unittest.TestCase):
    def test_five_distinct_safe_authored_enemies_and_encounters(self):
        self.assertTrue((PACK / "pack.json").is_file(), "five Expansion enemies need a shipped pack")
        descriptor = json.loads((PACK / "pack.json").read_text())
        self.assertEqual(descriptor["pack_id"], "temporal_frontiers")
        files = descriptor["content_manifest"] + descriptor["localization_sources"] + descriptor["asset_manifest"]
        self.assertEqual(set(files), set(descriptor["integrity_hashes"]))
        for relative in files:
            self.assertNotIn("..", Path(relative).parts)
            self.assertIn(Path(relative).suffix, [".json", ".csv", ".png"])
            if Path(relative).suffix == ".csv":
                self.assertNotIn(b"\r", (PACK / relative).read_bytes(), "authenticated CSV bytes must survive Git LF normalization")
            self.assertEqual(hashlib.sha256((PACK / relative).read_bytes()).hexdigest(), descriptor["integrity_hashes"][relative])
        enemies = json.loads((PACK / "content/enemies.json").read_text())
        profiles = json.loads((PACK / "content/encounters.json").read_text())
        self.assertEqual([enemy["id"] for enemy in enemies], IDS)
        self.assertEqual(len(profiles), 5)
        fingerprints = set()
        for enemy, profile in zip(enemies, profiles):
            self.assertEqual(enemy["category"], "expansion_enemy_definition")
            self.assertEqual(enemy["availability"], ["EXPANSION"])
            self.assertEqual(profile["floor_id"], enemy["floor_id"])
            self.assertEqual(profile["selection_revision"], 3)
            spawns = [spawn for wave in profile["recipes"][0]["waves"] for spawn in wave["spawns"]]
            self.assertEqual([spawn["enemy_id"] for spawn in spawns], [enemy["id"]])
            patterns = []
            for action in enemy["actions"]:
                self.assertGreaterEqual(action["warning_frames"], 30)
                self.assertGreaterEqual(action["recovery_frames"], 15)
                self.assertTrue(all(hit["offset_frame"] < action["active_frames"] for hit in action["hit_schedule"]))
                patterns.append((action["handler_id"], len(action["geometry"]), tuple(hit["offset_frame"] for hit in action["hit_schedule"])))
            fingerprints.add(tuple(patterns))
            self.assertTrue((PACK / enemy["sprite_asset"]).is_file())
        self.assertEqual(len(fingerprints), 5, "Expansion enemies must have five distinct attack patterns")
        fan = enemies[3]["actions"][1]
        self.assertEqual([hit["hit_index"] for hit in fan["hit_schedule"]], [0, 1, 2], "every visible Cinder fan lane must emit a projectile")
        self.assertEqual([hit["offset_frame"] for hit in fan["hit_schedule"]], [0, 0, 0])
        license_data = json.loads((PACK / "assets/provenance.json").read_text())
        self.assertEqual(license_data["license"], "CC0-1.0")


if __name__ == "__main__":
    unittest.main()
