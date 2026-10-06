import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "assets/production/enemies"
SOURCE = ROOT / "data/content_packs/base/content/enemies.json"


class LaunchEnemyArtTest(unittest.TestCase):
    def test_phase_library_uses_the_shared_binary_pixel_palette(self):
        palette = json.loads((ROOT / "assets/production/palettes/plane_walker_modern.json").read_text())
        allowed = {tuple(bytes.fromhex(color[1:])) + (255,) for color in palette["colors"]}
        for row in json.loads(SOURCE.read_text()):
            with self.subTest(enemy=row["id"]), Image.open(ASSETS / (row["id"] + ".png")) as image:
                colors = set(image.get_flattened_data())
                self.assertTrue(colors <= allowed | {(0, 0, 0, 0)})

    def test_complete_unique_visible_phase_library(self):
        definitions = json.loads(SOURCE.read_text())
        manifest = json.loads((ASSETS / "manifest.json").read_text())
        self.assertEqual(manifest["schema_id"], "plane_walker_launch_enemy_art_v1")
        self.assertEqual(manifest["license"], "CC0-1.0")
        self.assertEqual(manifest["phases"], ["idle", "warning", "active", "recovery"])
        self.assertEqual({row["id"] for row in manifest["assets"]}, {row["id"] for row in definitions})
        self.assertEqual(len(manifest["assets"]), 22)
        silhouettes = set()
        for row in manifest["assets"]:
            path = ASSETS / (row["id"] + ".png")
            self.assertEqual(row["path"], path.name)
            self.assertEqual(row["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
            with Image.open(path) as image:
                self.assertEqual(image.size, (192, 48))
                self.assertEqual(image.mode, "RGBA")
                phases = set()
                for frame in range(4):
                    cell = image.crop((frame * 48, 0, (frame + 1) * 48, 48))
                    bbox = cell.getbbox()
                    self.assertIsNotNone(bbox)
                    self.assertTrue(1 <= bbox[0] < bbox[2] <= 47 and 1 <= bbox[1] < bbox[3] <= 47, row["id"])
                    self.assertGreater(sum(alpha > 0 for alpha in cell.getchannel("A").get_flattened_data()), 80)
                    phases.add(hashlib.sha256(cell.tobytes()).hexdigest())
                    if frame == 0:
                        silhouettes.add(hashlib.sha256(cell.getchannel("A").tobytes()).hexdigest())
                self.assertEqual(len(phases), 4, row["id"])
        self.assertEqual(len(silhouettes), 22)

    def test_exact_generated_assets_and_only_missing_scenes(self):
        source = ROOT / "tools/production_art/generate_enemy_atlases.py"
        spec = importlib.util.spec_from_file_location("plane_walker_enemy_renderer", source)
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination / "assets", destination / "scenes")
            for path in (destination / "assets").iterdir():
                self.assertEqual(path.read_bytes(), (ASSETS / path.name).read_bytes(), path.name)
            self.assertEqual(len(list((destination / "scenes").glob("*.tscn"))), 18)
            native = ROOT / "data/content_packs/base/assets/enemies/launch"
            for path in (destination / "scenes").iterdir():
                self.assertEqual(path.read_bytes(), (native / path.name).read_bytes(), path.name)


if __name__ == "__main__":
    unittest.main()
