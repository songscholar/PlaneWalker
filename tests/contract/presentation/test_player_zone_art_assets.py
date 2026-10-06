import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "assets/production/ui"
IDS = {
    "ice_zone", "planar_collapse", "seeded_sequence", "steam_burst",
    "crystal_thunder", "reverse_steam", "thunder_flare", "thunder_crystal",
    "blazing_storm", "space_time_shatter", "primordial_collapse",
    "charged_heavy_shockwave", "rewind_counter_shockwave",
}


class PlayerZoneArtAssetsTest(unittest.TestCase):
    def test_zones_have_cohesive_distinct_native_atlases(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        batch = next((row for row in inventory["batches"] if row["id"] == "player_zones"), None)
        self.assertIsNotNone(batch)
        self.assertEqual({row["id"] for row in batch["assets"]}, IDS)
        palette = json.loads((ROOT / "assets/production/palettes/plane_walker_modern.json").read_text())
        allowed = {tuple(bytes.fromhex(color[1:])) + (255,) for color in palette["colors"]} | {(0, 0, 0, 0)}
        identities = set()
        for row in batch["assets"]:
            path = ART / row["path"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
            with Image.open(path) as image:
                self.assertEqual(image.size, (256, 64))
                self.assertTrue(set(image.get_flattened_data()) <= allowed)
                poses = [image.crop((x * 64, 0, (x + 1) * 64, 64)) for x in range(4)]
                self.assertEqual(len({pose.tobytes() for pose in poses}), 4)
                self.assertTrue(all(pose.getchannel("A").getbbox() for pose in poses))
                self.assertTrue(all(pose.getchannel("A").histogram()[255] < 1300 for pose in poses))
                identities.add(poses[0].tobytes())
        self.assertEqual(len(identities), len(IDS))

    def test_zone_source_regenerates_exact_bytes(self):
        spec = importlib.util.spec_from_file_location("zone_renderer", ROOT / "tools/production_art/generate_ui_asset_slice.py")
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination)
            paths = list((destination / "player_zones").glob("*.png"))
            self.assertEqual(len(paths), len(IDS))
            for path in paths:
                self.assertEqual(path.read_bytes(), (ART / "player_zones" / path.name).read_bytes())


if __name__ == "__main__":
    unittest.main()
