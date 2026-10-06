import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "assets/production/ui"
CATEGORIES = ("items", "blessings", "curses", "talents")


class ContentIconAssetsTest(unittest.TestCase):
    def test_every_authoritative_content_entry_has_a_distinct_icon(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        for category in CATEGORIES:
            source = json.loads((ROOT / f"data/content_packs/base/content/{category}.json").read_text())
            batch = next(row for row in inventory["batches"] if row["id"] == category)
            self.assertEqual({row["id"] for row in batch["assets"]}, {row["id"] for row in source})
            self.assertEqual(len({row["sha256"] for row in batch["assets"]}), len(source), category)
            first_frames = set()
            for row in batch["assets"]:
                path = ART / row["path"]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
                with Image.open(path) as atlas:
                    self.assertEqual(atlas.size, (128, 32))
                    frames = [atlas.crop((index * 32, 0, (index + 1) * 32, 32)) for index in range(4)]
                    self.assertEqual(len({frame.tobytes() for frame in frames}), 4)
                    first_frames.add(frames[0].tobytes())
            self.assertEqual(len(first_frames), len(source), category + " static icons")

    def test_icons_and_effects_stay_on_the_shared_palette_without_alpha_noise(self):
        palette = json.loads((ROOT / "assets/production/palettes/plane_walker_modern.json").read_text())
        allowed = {tuple(bytes.fromhex(color[1:])) + (255,) for color in palette["colors"]}
        for category in (*CATEGORIES, "weapons", "time_abilities", "player_effects", "mode_art", "room_types", "event_art", "controls"):
            for path in (ART / category).glob("*.png"):
                with self.subTest(asset=path.name), Image.open(path) as atlas:
                    self.assertTrue(set(atlas.get_flattened_data()) <= allowed | {(0, 0, 0, 0)})

    def test_room_type_art_has_a_separate_unknown_glyph(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        batch = next(row for row in inventory["batches"] if row["id"] == "room_types")
        expected = {"entry", "unknown", "combat", "elite", "treasure", "shop", "event", "boss", "rest"}
        self.assertEqual({row["id"] for row in batch["assets"]}, expected)
        self.assertEqual(len({row["sha256"] for row in batch["assets"]}), 9)
        unknown = next(row for row in batch["assets"] if row["id"] == "unknown")
        with Image.open(ART / unknown["path"]) as atlas:
            self.assertEqual(atlas.size, (128, 32))
            self.assertIsNotNone(atlas.getchannel("A").getbbox())

    def test_all_events_have_specific_vignettes_and_commands_have_symbols(self):
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        events = json.loads((ROOT / "data/content_packs/base/content/dungeon_events.json").read_text())
        batch = next(row for row in inventory["batches"] if row["id"] == "event_art")
        self.assertEqual({row["id"] for row in batch["assets"]}, {row["id"] for row in events})
        self.assertEqual(len({row["sha256"] for row in batch["assets"]}), len(events))
        for row in batch["assets"]:
            with Image.open(ART / row["path"]) as image:
                self.assertEqual(image.size, (384, 64))
        controls = next(row for row in inventory["batches"] if row["id"] == "controls")
        self.assertEqual({row["id"] for row in controls["assets"]}, {"decline_contract", "play", "pause", "copy", "paste", "export", "delete", "back"})

    def test_exact_regeneration_authenticates_each_declared_resource(self):
        spec = importlib.util.spec_from_file_location("ui_asset_renderer", ROOT / "tools/production_art/generate_ui_asset_slice.py")
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination)
            for category in (*CATEGORIES, "weapons", "time_abilities", "player_effects", "mode_art", "room_types", "event_art", "controls"):
                for path in (destination / category).glob("*.png"):
                    self.assertEqual(path.read_bytes(), (ART / category / path.name).read_bytes(), path.name)


if __name__ == "__main__":
    unittest.main()
