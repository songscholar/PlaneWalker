from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "production_art"))
import generate_actor_atlases as art


class ProductionActorAtlasesTest(unittest.TestCase):
    def test_runtime_pixels_use_locked_palette_and_binary_alpha(self):
        palette = json.loads((ROOT / "assets/production/palettes/plane_walker_modern.json").read_text())
        colors = {tuple(bytes.fromhex(color[1:])) for color in palette["colors"]}
        with tempfile.TemporaryDirectory() as directory:
            manifest = art.generate(Path(directory))
            self.assertEqual(manifest["art_direction"]["light_direction"], "top_right")
            for row in manifest["assets"]:
                with self.subTest(actor=row["id"]), Image.open(Path(directory) / row["path"]) as atlas:
                    pixels = list(atlas.get_flattened_data())
                    self.assertTrue(all(pixel[3] in (0, 255) for pixel in pixels))
                    self.assertTrue({pixel[:3] for pixel in pixels if pixel[3]} <= colors)

    def test_player_attack_moves_articulated_limbs_beyond_body_lean(self):
        for actor in art.CHARACTERS:
            with self.subTest(actor=actor):
                idle = art.character(actor, "idle", 0)
                attack = art.character(actor, "attack", 2)
                idle_hand = idle.crop((33, 18, 43, 31)).getchannel("A")
                attack_hand = attack.crop((33, 18, 43, 31)).getchannel("A")
                self.assertGreater(sum(attack_hand.get_flattened_data()), sum(idle_hand.get_flattened_data()))

    def test_library_covers_actual_launch_identities_and_frame_states(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = art.generate(root)
            expected = {"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord", "ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"}
            self.assertEqual({row["id"] for row in manifest["assets"]}, expected)
            self.assertEqual(manifest["states"], ["idle", "move", "attack", "cast", "hurt", "death"])
            self.assertEqual(manifest["provenance"]["kind"], "original_project_art")
            silhouettes = set()
            for row in manifest["assets"]:
                with self.subTest(actor=row["id"]), Image.open(root / row["path"]) as atlas:
                    size = row["frame_width"]
                    self.assertEqual(atlas.size, (size * 4, size * 6))
                    self.assertEqual(atlas.mode, "RGBA")
                    self.assertEqual(row["sha256"], hashlib.sha256((root / row["path"]).read_bytes()).hexdigest())
                    for state in range(6):
                        distinct = set()
                        for frame in range(4):
                            crop = atlas.crop((frame * size, state * size, (frame + 1) * size, (state + 1) * size))
                            alpha = crop.getchannel("A")
                            bounds = alpha.getbbox()
                            self.assertIsNotNone(bounds)
                            self.assertGreater(sum(value != 0 for value in alpha.get_flattened_data()), size * 2)
                            self.assertGreaterEqual(bounds[0], 1)
                            self.assertGreaterEqual(bounds[1], 1)
                            self.assertLessEqual(bounds[2], size - 1)
                            self.assertLessEqual(bounds[3], size - 1)
                            distinct.add(crop.tobytes())
                        self.assertGreaterEqual(len(distinct), 3, "each action has meaningful animation")
                    silhouettes.add(atlas.crop((0, 0, size, size)).getchannel("A").tobytes())
            self.assertEqual(len(silhouettes), 10, "silhouettes cannot be palette swaps")
            self.assertTrue(art.validate(root)["ok"])

    def test_fresh_generation_matches_checked_in_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory)
            art.generate(generated)
            committed = ROOT / "assets" / "production" / "actors"
            for filename in ("manifest.json", "contact_sheet.png", "LICENSE.txt"):
                self.assertEqual((generated / filename).read_bytes(), (committed / filename).read_bytes())
            for row in json.loads((generated / "manifest.json").read_text())["assets"]:
                self.assertEqual((generated / row["path"]).read_bytes(), (committed / row["path"]).read_bytes())

    def test_read_only_validator_rejects_missing_corrupt_blank_or_undeclared_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = art.generate(root)
            path = root / manifest["assets"][0]["path"]
            original = path.read_bytes()
            path.unlink()
            self.assertFalse(art.validate(root)["ok"])
            path.write_bytes(b"invalid PNG")
            self.assertFalse(art.validate(root)["ok"])
            original_manifest = (root / "manifest.json").read_bytes()
            row = manifest["assets"][0]
            Image.new("RGBA", (row["width"], row["height"])).save(path)
            row["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            (root / "manifest.json").write_text(json.dumps(manifest))
            self.assertFalse(art.validate(root)["ok"])
            path.write_bytes(original)
            (root / "manifest.json").write_bytes(original_manifest)
            (root / "undeclared.png").write_bytes(original)
            self.assertFalse(art.validate(root)["ok"])

    def test_manifest_cannot_escape_the_asset_root_or_hide_a_bad_frame_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = art.generate(root)
            manifest["assets"][0]["path"] = "../outside.png"
            (root / "manifest.json").write_text(json.dumps(manifest))
            self.assertFalse(art.validate(root)["ok"])


if __name__ == "__main__":
    unittest.main()
