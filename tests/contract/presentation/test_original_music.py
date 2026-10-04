import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
import wave


ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "assets/production/music"
CUES = {"music_hub", "music_training", "music_credits", "music_victory", "music_defeat"}
CUES.update("music_" + name for name in (
    "ruins_of_remnant", "void_forest", "time_rift", "plane_forge", "throne_of_void"))
CUES.update("music_boss_" + name for name in (
    "ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"))


class OriginalMusicTest(unittest.TestCase):
    def test_asset_format_loop_headroom_and_provenance(self):
        manifest = json.loads((ASSETS / "manifest.json").read_text())
        self.assertEqual(manifest["schema_id"], "plane_walker_original_music_v1")
        self.assertEqual({row["id"] for row in manifest["cues"]}, CUES)
        self.assertEqual(len(manifest["cues"]), 15)
        self.assertEqual(manifest["license"], "CC0-1.0")
        self.assertIn("original", (ASSETS / "LICENSE.txt").read_text().lower())
        digests = set()
        for row in manifest["cues"]:
            path = ASSETS / (row["id"] + ".wav")
            self.assertEqual(row["path"], path.name)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(row["sha256"], digest)
            digests.add(digest)
            with wave.open(str(path)) as audio:
                self.assertEqual((audio.getnchannels(), audio.getsampwidth(), audio.getframerate()), (2, 2, 22050))
                self.assertEqual(audio.getnframes(), row["frames"])
                self.assertGreater(audio.getnframes() / 22050, 15)
                samples = struct.unpack("<%dh" % (audio.getnframes() * 2), audio.readframes(audio.getnframes()))
            peak = max(abs(sample) for sample in samples) / 32768
            rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples)) / 32768
            self.assertGreater(rms, 0.025, row["id"])
            self.assertLess(peak, 0.80, row["id"])
            self.assertLess(max(abs(sample) for sample in samples[:4] + samples[-4:]), 64, row["id"])
            self.assertEqual(row["loop_begin"], 0)
            self.assertEqual(row["loop_end"], row["frames"])
        self.assertEqual(len(digests), 15)

    def test_generator_reproduces_checked_in_bytes(self):
        source = ROOT / "tools/production_audio/generate_music.py"
        spec = importlib.util.spec_from_file_location("plane_walker_music_renderer", source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            module.generate(Path(directory))
            produced = Path(directory)
            self.assertEqual({path.name for path in produced.iterdir()}, {path.name for path in ASSETS.iterdir() if path.suffix != ".import"})
            for path in produced.iterdir():
                self.assertEqual(path.read_bytes(), (ASSETS / path.name).read_bytes(), path.name)


if __name__ == "__main__":
    unittest.main()
