import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/production_art"))
import generate_ui_asset_slice as art


class PixelChromeTest(unittest.TestCase):
    def test_chrome_centers_are_uniform_for_nine_slice_stretching(self):
        for name in ("chrome_panel", "chrome_button", "chrome_focus"):
            self.assertIn(name, art.UI_FRAMES)
            for frame in range(4):
                with self.subTest(name=name, frame=frame):
                    image = art.ui_frame(name, frame)
                    center = image.crop((5, 5, 27, 27))
                    self.assertEqual(len(set(center.get_flattened_data())), 1)
                    self.assertEqual(set(image.getchannel("A").get_flattened_data()), {0, 255})
                    self.assertIsNotNone(image.getchannel("A").getbbox())


if __name__ == "__main__":
    unittest.main()
