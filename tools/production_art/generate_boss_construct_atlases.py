#!/usr/bin/env python3
"""Reproduce Plane Walker's original native Boss construct pixel atlases."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/constructs"
INK = (24, 28, 35, 255)
GOLD = (227, 187, 79, 255)
PALE = (236, 242, 234, 255)
CYAN = (92, 222, 216, 255)
RED = (228, 91, 111, 255)


def watch_frame(phase: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    draw.rectangle((13, 1, 18, 4), fill=GOLD, outline=INK)
    draw.ellipse((4, 4, 27, 27), fill=INK)
    draw.ellipse((6, 6, 25, 25), fill=GOLD)
    draw.ellipse((8, 8, 23, 23), fill=INK)
    draw.ellipse((9, 9, 22, 22), fill=PALE)
    if phase == 3:
        draw.line(((11, 10), (15, 14), (13, 18), (20, 22)), fill=INK, width=2)
        draw.line(((20, 10), (17, 15), (21, 17)), fill=RED, width=2)
        draw.rectangle((5, 24, 9, 26), fill=RED)
    else:
        for x, y in ((15, 10), (21, 15), (15, 21), (10, 15)):
            draw.rectangle((x, y, x + 1, y + 1), fill=INK)
        hand = ((16, 11), (20, 13), (19, 20))[phase]
        draw.line(((16, 16), hand), fill=INK, width=2)
        draw.line(((16, 16), (12, 18)), fill=INK, width=1)
        draw.rectangle((14, 14, 17, 17), fill=CYAN if phase else GOLD)
        if phase:
            draw.line(((3, 8), (1, 12), (2, 19)), fill=CYAN, width=1)
            draw.line(((29, 8), (31, 12), (30, 19)), fill=CYAN, width=1)
    return image


def cover_frame(phase: int) -> Image.Image:
    image = Image.new("RGBA", (48, 48))
    draw = ImageDraw.Draw(image)
    stone = (114, 131, 128, 255)
    light = (172, 185, 170, 255)
    moss = (92, 154, 110, 255)
    if phase == 2:
        draw.polygon(((7, 37), (14, 30), (27, 32), (38, 38), (31, 43), (12, 43)), fill=INK)
        draw.polygon(((11, 37), (17, 33), (25, 36), (20, 40)), fill=stone)
        draw.polygon(((25, 37), (31, 35), (35, 39), (29, 41)), fill=light)
        draw.rectangle((12, 41, 21, 42), fill=moss)
        return image
    draw.rectangle((9, 37, 38, 43), fill=INK)
    draw.rectangle((11, 38, 36, 41), fill=stone)
    draw.rectangle((14, 9, 33, 38), fill=INK)
    draw.rectangle((16, 11, 31, 37), fill=stone)
    draw.rectangle((17, 12, 20, 36), fill=light)
    draw.rectangle((28, 12, 30, 36), fill=(73, 88, 96, 255))
    draw.rectangle((10, 5, 37, 12), fill=INK)
    draw.rectangle((12, 6, 35, 10), fill=light)
    draw.rectangle((14, 5, 19, 7), fill=moss)
    draw.line(((22, 16), (25, 20), (23, 27), (27, 31)), fill=CYAN, width=2)
    draw.rectangle((11, 37, 15, 40), fill=moss)
    if phase == 1:
        draw.line(((15, 13), (24, 22), (18, 29), (29, 37)), fill=INK, width=2)
        draw.line(((30, 16), (24, 22), (31, 28)), fill=RED, width=1)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (128, 32))
    for phase in range(4):
        atlas.paste(watch_frame(phase), (32 * phase, 0))
    path = OUTPUT / "time_watch.png"
    atlas.save(path)
    cover_atlas = Image.new("RGBA", (144, 48))
    for phase in range(3):
        cover_atlas.paste(cover_frame(phase), (48 * phase, 0))
    cover_path = OUTPUT / "ruins_cover.png"
    cover_atlas.save(cover_path)
    manifest = {
        "schema_version": 1,
        "license": "CC0-1.0",
        "source": "tools/production_art/generate_boss_construct_atlases.py",
        "atlases": [
            {"id": "time_watch", "path": path.name, "frame_size": [32, 32], "frames": ["idle", "warning_a", "warning_b", "broken"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()},
            {"id": "ruins_cover", "path": cover_path.name, "frame_size": [48, 48], "frames": ["intact", "damaged", "debris"], "sha256": hashlib.sha256(cover_path.read_bytes()).hexdigest()},
        ],
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (OUTPUT / "LICENSE.txt").write_text(
        "Plane Walker Original Boss Construct Artwork\n\n"
        "This raster atlas was authored locally from original pixel geometry for Plane Walker.\n"
        "No downloaded imagery or third-party artwork is used.\n\n"
        "The artwork is dedicated to the public domain under CC0 1.0 Universal:\n"
        "https://creativecommons.org/publicdomain/zero/1.0/\n"
        "The dedication applies to the artwork, not game code or project identity.\n\n"
        "Source: tools/production_art/generate_boss_construct_atlases.py\n"
        "Reproduction: python3 tools/production_art/generate_boss_construct_atlases.py\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
