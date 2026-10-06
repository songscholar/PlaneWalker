from __future__ import annotations

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]


def _load_renderer(name: str):
    source = ROOT / "tools" / "production_art" / f"generate_{name}_atlases.py"
    spec = importlib.util.spec_from_file_location(f"plane_walker_{name}_renderer", source)
    renderer = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(renderer)
    return renderer


class SupportAssetAtlasesTest(unittest.TestCase):
    def test_production_support_assets_use_binary_alpha(self):
        roots = [
            ROOT / "assets/production/summons",
            ROOT / "assets/production/enemy_spatial",
            ROOT / "assets/production/enemy_mechanisms",
            ROOT / "assets/production/hostile_effects",
            ROOT / "assets/production/constructs",
        ]
        for root in roots:
            for path in sorted(root.glob("*.png")):
                with self.subTest(path=path.relative_to(ROOT)), Image.open(path) as image:
                    self.assertEqual(image.mode, "RGBA")
                    self.assertTrue(set(image.getchannel("A").get_flattened_data()) <= {0, 255})

    def test_support_generators_reproduce_checked_in_atlases(self):
        for name, directory in (
            ("summon", "summons"),
            ("enemy_spatial", "enemy_spatial"),
            ("enemy_mechanism", "enemy_mechanisms"),
        ):
            renderer = _load_renderer(name)
            with self.subTest(generator=name), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)
                if name == "summon":
                    renderer.main.__globals__["OUTPUT"] = output
                    renderer.main()
                elif name == "enemy_spatial":
                    renderer.main.__globals__["OUTPUT"] = output
                    renderer.main()
                else:
                    renderer.OUTPUT = output
                    renderer.generate()
                committed = ROOT / "assets/production" / directory
                generated = {path.name: path.read_bytes() for path in output.iterdir()}
                expected = {path.name: path.read_bytes() for path in committed.iterdir() if path.name in generated}
                self.assertEqual(generated, expected)

    def test_animation_frames_are_unique_and_echo_silhouettes_are_distinct(self):
        manifests = (
            (ROOT / "assets/production/summons", 32, 4),
            (ROOT / "assets/production/enemy_spatial", None, 4),
            (ROOT / "assets/production/enemy_mechanisms", 32, 4),
        )
        for root, fixed_frame_size, frame_count in manifests:
            manifest = next(root.glob("manifest.json"))
            payload = __import__("json").loads(manifest.read_text())
            rows = payload.get("atlases", payload.get("assets", []))
            for row in rows:
                path = root / row["path"]
                with self.subTest(path=path.relative_to(ROOT)), Image.open(path) as image:
                    frame_width = fixed_frame_size or int(row["frame_size"][0])
                    frame_height = fixed_frame_size or int(row["frame_size"][1])
                    self.assertEqual(image.width, frame_width * frame_count)
                    self.assertEqual(image.height, frame_height)
                    hashes = {
                        hashlib.sha256(image.crop((index * frame_width, 0, (index + 1) * frame_width, frame_height)).tobytes()).hexdigest()
                        for index in range(frame_count)
                    }
                    self.assertEqual(len(hashes), frame_count)

        summons = ROOT / "assets/production/summons"
        silhouettes = {
            hashlib.sha256(Image.open(summons / f"{name}.png").crop((0, 0, 32, 32)).getchannel("A").tobytes()).hexdigest()
            for name in ("hunter_echo", "ranger_echo", "timeline_echo", "elite_mirror")
        }
        self.assertEqual(len(silhouettes), 4)


if __name__ == "__main__":
    unittest.main()
