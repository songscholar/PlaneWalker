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


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (128, 32))
    for phase in range(4):
        atlas.paste(watch_frame(phase), (32 * phase, 0))
    path = OUTPUT / "time_watch.png"
    atlas.save(path)
    manifest = {
        "schema_version": 1,
        "license": "CC0-1.0",
        "source": "tools/production_art/generate_boss_construct_atlases.py",
        "atlases": [{"id": "time_watch", "path": path.name, "frame_size": [32, 32], "frames": ["idle", "warning_a", "warning_b", "broken"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}],
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
