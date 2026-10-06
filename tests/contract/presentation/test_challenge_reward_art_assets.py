import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "assets/production/ui"


class ChallengeRewardArtAssetsTest(unittest.TestCase):
    def test_authoritative_rewards_have_distinct_pixel_art(self):
        source = json.loads((ROOT / "assets/production/modes/challenge_rewards.json").read_text())
        inventory = json.loads((ART / "pixel_asset_inventory.json").read_text())
        batch = next((row for row in inventory["batches"] if row["id"] == "challenge_rewards"), None)
        self.assertIsNotNone(batch)
        self.assertEqual({row["id"] for row in batch["assets"]}, {row["id"] for row in source["rewards"]})
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
                first_frames.add(frames[0].tobytes())
        self.assertEqual(len(first_frames), len(source["rewards"]))

    def test_reward_art_regenerates_from_local_source(self):
        spec = importlib.util.spec_from_file_location("reward_art_renderer", ROOT / "tools/production_art/generate_ui_asset_slice.py")
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            renderer.generate(destination)
            paths = list((destination / "challenge_rewards").glob("*.png"))
            self.assertEqual(len(paths), 11)
            for path in paths:
                self.assertEqual(path.read_bytes(), (ART / "challenge_rewards" / path.name).read_bytes())


if __name__ == "__main__":
    unittest.main()
