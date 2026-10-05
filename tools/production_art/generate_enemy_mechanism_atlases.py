#!/usr/bin/env python3
"""Reproduce original Hound sigil and Phase Ranger arrival raster cues."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/enemy_mechanisms"


def generate() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name in ("hound_sigil", "phase_arrival"):
        atlas = Image.new("RGBA", (128, 32))
        for frame in range(4):
            image = Image.new("RGBA", (32, 32))
            draw = ImageDraw.Draw(image)
            ink = (24, 28, 35, 255)
            glow = (118, 234, 228, 255) if name == "hound_sigil" else (248, 196, 78, 255)
            draw.ellipse((3, 9, 28, 25), fill=ink, outline=glow, width=2)
            draw.ellipse((7, 12, 24, 22), outline=(226, 238, 236, 255), width=1)
            if name == "hound_sigil":
                draw.polygon([(16, 2 + frame % 2), (23, 12), (16, 21), (9, 12)], fill=ink, outline=glow)
                draw.line([(16, 6), (16, 17)], fill=glow, width=2)
                draw.line([(12, 11), (20, 11)], fill=glow, width=2)
            else:
                for x, y in ((4, 5), (26, 5), (4, 27), (26, 27)):
                    draw.line([(x, y), (x + (3 if x < 16 else -3), y)], fill=glow, width=2)
                    draw.line([(x, y), (x, y + (3 if y < 16 else -3))], fill=glow, width=2)
                draw.line([(12 + frame, 16), (20 - frame, 16)], fill=glow, width=2)
            atlas.alpha_composite(image, (frame * 32, 0))
        target = OUTPUT / f"{name}.png"
        atlas.save(target)
        rows.append({"id": name, "path": target.name, "width": 128, "height": 32, "frame_width": 32, "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    (OUTPUT / "manifest.json").write_text(json.dumps({"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_enemy_mechanism_atlases.py", "atlases": rows}, indent=2) + "\n")
    (OUTPUT / "LICENSE.txt").write_text("Plane Walker original enemy mechanism artwork\n\nThese raster atlases were authored locally from original pixel geometry.\nDedicated to the public domain under CC0 1.0 Universal:\nhttps://creativecommons.org/publicdomain/zero/1.0/\n\nSource: tools/production_art/generate_enemy_mechanism_atlases.py\n")


if __name__ == "__main__":
    generate()
