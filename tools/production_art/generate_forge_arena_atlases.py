#!/usr/bin/env python3
"""Reproduce original Forge anvil, fixed vent and cooling pool pixel rasters."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/constructs"
INK = (25, 29, 35, 255)
STEEL = (113, 137, 147, 255)
LIGHT = (198, 222, 216, 255)
FIRE = (247, 123, 56, 255)
WATER = (66, 179, 204, 255)


def frame(kind: str, phase: int) -> Image.Image:
    image = Image.new("RGBA", (48, 48))
    draw = ImageDraw.Draw(image)
    if kind == "anvil":
        # A hard-edged ground shadow keeps the atlas valid at nearest filtering.
        draw.ellipse((6, 29, 42, 43), fill=INK)
        if phase == 2:
            draw.polygon(((9, 30), (20, 25), (25, 30), (36, 28), (41, 35), (32, 40), (12, 39)), fill=INK)
            draw.polygon(((12, 31), (18, 28), (22, 32), (18, 35)), fill=STEEL)
            draw.polygon(((29, 32), (35, 30), (37, 35), (31, 37)), fill=LIGHT)
            return image
        draw.polygon(((8, 9), (36, 9), (44, 13), (35, 20), (29, 20), (28, 29), (36, 34), (36, 39), (12, 39), (12, 34), (20, 29), (19, 20), (12, 19), (4, 14)), fill=INK)
        draw.polygon(((9, 11), (35, 11), (40, 13), (33, 17), (12, 17), (7, 14)), fill=LIGHT)
        draw.rectangle((21, 20, 27, 30), fill=STEEL)
        draw.polygon(((15, 35), (22, 31), (27, 31), (33, 35), (33, 37), (15, 37)), fill=STEEL)
        draw.line(((22, 21), (22, 29)), fill=LIGHT, width=2)
        if phase == 1:
            draw.line(((25, 11), (21, 16), (26, 19), (23, 27)), fill=INK, width=2)
            draw.rectangle((22, 24, 25, 26), fill=FIRE)
    elif kind == "vent":
        draw.ellipse((7, 11, 41, 38), fill=INK)
        draw.ellipse((10, 13, 38, 35), fill=STEEL)
        draw.ellipse((14, 16, 34, 32), fill=(126, 60, 49, 255))
        for x in range(16, 34, 5):
            draw.line(((x, 17), (x, 31)), fill=INK, width=2)
            draw.rectangle((x + 1, 21, x + 2, 26), fill=FIRE)
        draw.line(((11, 20), (15, 15), (29, 14)), fill=LIGHT, width=2)
    else:
        draw.ellipse((0, 3, 47, 44), fill=INK)
        draw.ellipse((3, 6, 44, 41), fill=STEEL)
        draw.ellipse((6, 9, 41, 38), fill=(28, 87, 119, 255))
        draw.ellipse((8, 11, 39, 36), fill=WATER)
        draw.arc((12, 15, 35, 31), 180, 340, fill=LIGHT, width=2)
        draw.line(((12, 17), (18, 13), (28, 13)), fill=LIGHT, width=2)
        draw.line(((18, 30), (26, 32), (34, 28)), fill=(25, 128, 167, 255), width=2)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for kind in ("anvil", "vent", "cooling"):
        count = 3 if kind == "anvil" else 1
        atlas = Image.new("RGBA", (48 * count, 48))
        for phase in range(count):
            atlas.paste(frame(kind, phase), (48 * phase, 0))
        path = OUTPUT / f"forge_{kind}.png"
        atlas.save(path)
        entries.append({"id": f"forge_{kind}", "path": path.name, "frame_size": [48, 48], "frames": ["intact", "damaged", "debris"] if count == 3 else ["permanent"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUTPUT / "forge_manifest.json").write_text(json.dumps({"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_forge_arena_atlases.py", "atlases": entries}, indent=2) + "\n", encoding="utf-8")
    (OUTPUT / "FORGE_LICENSE.txt").write_text("Plane Walker Original Forge Arena Artwork\n\nOriginal raster pixel geometry authored locally for Plane Walker.\nThe artwork is dedicated under CC0 1.0 Universal.\nhttps://creativecommons.org/publicdomain/zero/1.0/\nSource: tools/production_art/generate_forge_arena_atlases.py\n", encoding="utf-8")


if __name__ == "__main__":
    main()
