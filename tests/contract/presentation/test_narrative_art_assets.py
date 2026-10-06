import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "assets/production/ui"
SOURCE = ROOT / "data/content_packs/base/content/narrative_definitions.json"
FAMILIES = {"npc_portraits": ("npc", "npc_id", (64, 64)), "ending_art": ("ending", "ending_id", (128, 72))}
COMMANDS = {"settings", "bindings", "restart", "quit", "build", "import", "refresh", "next", "screenshot", "account", "storage", "community", "content", "sharing"}


class NarrativeArtAssetsTest(unittest.TestCase):
    def test_narrative_identity_frames_and_source_authentication(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        source = json.loads(SOURCE.read_text())
        palette = json.loads((ROOT / "assets/production/palettes/plane_walker_modern.json").read_text())
        allowed = {tuple(bytes.fromhex(color[1:])) + (255,) for color in palette["colors"]} | {(0, 0, 0, 0)}
        for family, (kind, identity, size) in FAMILIES.items():
            batch = next((row for row in inventory["batches"] if row["id"] == family), None)
            self.assertIsNotNone(batch, family + " batch")
            expected = {row[identity] for row in source if row["definition_kind"] == kind}
            self.assertEqual({row["id"] for row in batch["assets"]}, expected)
            first_frames = set()
            for row in batch["assets"]:
                path = ART / row["path"]
                with self.subTest(asset=row["id"]), Image.open(path) as image:
                    self.assertEqual(image.size, (size[0] * 4, size[1]))
                    self.assertEqual((row["frame_width"], row["frame_height"], row["frame_count"]), (*size, 4))
                    self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
                    self.assertTrue(set(image.get_flattened_data()) <= allowed)
                    frames = [image.crop((x * size[0], 0, (x + 1) * size[0], size[1])) for x in range(4)]
                    self.assertEqual(len({frame.tobytes() for frame in frames}), 4)
                    self.assertIsNotNone(frames[0].getchannel("A").getbbox())
                    first_frames.add(frames[0].tobytes())
            self.assertEqual(len(first_frames), len(expected), family + " independent static identities")

    def test_pause_and_settings_commands_have_independent_symbols(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        batch = next(row for row in inventory["batches"] if row["id"] == "controls")
        rows = [row for row in batch["assets"] if row["id"] in COMMANDS]
        self.assertEqual({row["id"] for row in rows}, COMMANDS)
        first_frames = set()
        for row in rows:
            with Image.open(ART / row["path"]) as image:
                self.assertEqual(image.size, (128, 32))
                first_frames.add(image.crop((0, 0, 32, 32)).tobytes())
        self.assertEqual(len(first_frames), len(COMMANDS))

    def test_narrative_assets_are_byte_reproducible(self):
        spec = importlib.util.spec_from_file_location("narrative_art_renderer", ROOT / "tools/production_art/generate_ui_asset_slice.py")
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination)
            for family in FAMILIES:
                self.assertGreater(len(list((destination / family).glob("*.png"))), 0)
                for path in (destination / family).glob("*.png"):
                    self.assertEqual(path.read_bytes(), (ART / family / path.name).read_bytes(), path.name)


if __name__ == "__main__":
    unittest.main()
