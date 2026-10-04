import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "assets/production/hostile_effects"
TYPES = ("physical", "time", "void", "fire", "ice", "lightning")


class HostileEffectArtTest(unittest.TestCase):
    def test_distinct_visible_four_frame_library(self):
        manifest = json.loads((ASSETS / "manifest.json").read_text())
        self.assertEqual(manifest["schema_id"], "plane_walker_hostile_effect_art_v1")
        self.assertEqual(manifest["license"], "CC0-1.0")
        expected = {f"{kind}_{shape}" for kind in TYPES for shape in ("projectile", "pool")}
        self.assertEqual({row["id"] for row in manifest["assets"]}, expected)
        atlas_hashes = set()
        for row in manifest["assets"]:
            path = ASSETS / row["path"]
            self.assertEqual(row["path"], row["id"] + ".png")
            self.assertEqual(row["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
            with Image.open(path) as image:
                self.assertEqual(image.size, (128, 32))
                self.assertEqual(image.mode, "RGBA")
                phases = set()
                for frame in range(4):
                    cell = image.crop((32 * frame, 0, 32 * (frame + 1), 32))
                    self.assertIsNotNone(cell.getbbox(), row["id"])
                    self.assertGreater(sum(alpha > 0 for alpha in cell.getchannel("A").get_flattened_data()), 48)
                    self.assertGreaterEqual(len(set(cell.get_flattened_data())), 4)
                    phases.add(hashlib.sha256(cell.tobytes()).hexdigest())
                self.assertEqual(len(phases), 4, row["id"])
                atlas_hashes.add(hashlib.sha256(image.tobytes()).hexdigest())
        self.assertEqual(len(atlas_hashes), 12)

    def test_generator_exactly_reproduces_assets(self):
        source = ROOT / "tools/production_art/generate_hostile_effect_atlases.py"
        spec = importlib.util.spec_from_file_location("plane_walker_effect_renderer", source)
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination)
            self.assertEqual({path.name for path in destination.iterdir()}, {path.name for path in ASSETS.iterdir() if path.suffix != ".import"})
            for path in destination.iterdir():
                self.assertEqual(path.read_bytes(), (ASSETS / path.name).read_bytes(), path.name)


if __name__ == "__main__":
    unittest.main()
