import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "assets/production/ui"
IDS = {"sword", "bow", "gun", "gauntlets", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"}


class HeldWeaponArtAssetsTest(unittest.TestCase):
    def test_held_weapons_have_distinct_ready_and_action_art(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        batch = next((row for row in inventory["batches"] if row["id"] == "held_weapons"), None)
        self.assertIsNotNone(batch)
        self.assertEqual({row["id"] for row in batch["assets"]}, IDS)
        palette = json.loads((ROOT / "assets/production/palettes/plane_walker_modern.json").read_text())
        allowed = {tuple(bytes.fromhex(color[1:])) + (255,) for color in palette["colors"]} | {(0, 0, 0, 0)}
        first_frames = set()
        for row in batch["assets"]:
            path = ART / row["path"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
            with Image.open(path) as image:
                self.assertEqual(image.size, (128, 32))
                self.assertTrue(set(image.get_flattened_data()) <= allowed)
                frames = [image.crop((x * 32, 0, (x + 1) * 32, 32)) for x in range(4)]
                self.assertEqual(len({frame.tobytes() for frame in frames}), 4)
                self.assertTrue(all(frame.getchannel("A").getbbox() for frame in frames))
                first_frames.add(frames[0].tobytes())
        self.assertEqual(len(first_frames), len(IDS))

    def test_held_weapon_source_regenerates_exact_bytes(self):
        spec = importlib.util.spec_from_file_location("held_weapon_renderer", ROOT / "tools/production_art/generate_ui_asset_slice.py")
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination)
            paths = list((destination / "held_weapons").glob("*.png"))
            self.assertEqual(len(paths), len(IDS))
            for path in paths:
                self.assertEqual(path.read_bytes(), (ART / "held_weapons" / path.name).read_bytes())


if __name__ == "__main__":
    unittest.main()
