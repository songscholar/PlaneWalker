#!/usr/bin/env python3
"""Reproduce original Void arena pillar and plane core rasters."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/constructs"
INK = (24, 28, 35, 255)
STONE = (106, 133, 145, 255)
LIGHT = (183, 219, 220, 255)
GOLD = (230, 195, 94, 255)
CYAN = (78, 213, 197, 255)
RED = (228, 91, 111, 255)


def frame(kind: str, phase: int) -> Image.Image:
    image = Image.new("RGBA", (48, 48))
    draw = ImageDraw.Draw(image)
    if phase == 2:
        draw.polygon(((10, 33), (17, 28), (25, 33), (33, 29), (39, 35), (32, 40), (13, 40)), fill=INK)
        draw.polygon(((13, 34), (19, 31), (22, 35), (18, 38)), fill=STONE)
        draw.polygon(((28, 34), (33, 32), (36, 35), (32, 38)), fill=LIGHT)
        draw.line(((22, 37), (26, 34), (30, 37)), fill=CYAN if kind == "core" else GOLD, width=2)
        return image
    if kind == "pillar":
        draw.rectangle((12, 35, 36, 41), fill=INK)
        draw.rectangle((14, 36, 34, 39), fill=STONE)
        draw.polygon(((15, 9), (24, 4), (33, 9), (31, 35), (17, 35)), fill=INK)
        draw.rectangle((18, 12, 30, 34), fill=STONE)
        draw.line(((19, 12), (19, 32)), fill=LIGHT, width=2)
        draw.line(((29, 12), (28, 33)), fill=(62, 85, 101, 255), width=2)
        draw.polygon(((17, 10), (24, 6), (31, 10), (24, 14)), fill=GOLD)
        draw.line(((23, 18), (26, 22), (23, 27), (25, 31)), fill=CYAN, width=2)
        if phase == 1:
            draw.line(((17, 16), (24, 22), (21, 28), (29, 34)), fill=INK, width=2)
            draw.rectangle((22, 23, 25, 25), fill=RED)
    else:
        draw.polygon(((8, 31), (14, 26), (34, 26), (40, 31), (34, 39), (14, 39)), fill=INK)
        draw.polygon(((12, 32), (17, 29), (31, 29), (36, 32), (32, 36), (16, 36)), fill=STONE)
        draw.line(((15, 34), (33, 34)), fill=GOLD, width=2)
        draw.polygon(((24, 4), (34, 16), (24, 29), (14, 16)), fill=INK)
        draw.polygon(((24, 7), (31, 16), (24, 26), (17, 16)), fill=CYAN)
        draw.polygon(((24, 9), (26, 16), (24, 23), (20, 16)), fill=LIGHT)
        draw.line(((11, 13), (8, 17), (11, 21)), fill=GOLD)
        draw.line(((37, 13), (40, 17), (37, 21)), fill=GOLD)
        if phase == 1:
            draw.line(((24, 8), (21, 14), (27, 19), (23, 25)), fill=INK, width=2)
            draw.rectangle((24, 16, 27, 18), fill=RED)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for kind in ("pillar", "core"):
        atlas = Image.new("RGBA", (144, 48))
        for phase in range(3):
            atlas.paste(frame(kind, phase), (phase * 48, 0))
        path = OUTPUT / f"void_{kind}.png"
        atlas.save(path)
        entries.append({"id": f"void_{kind}", "path": path.name, "frame_size": [48, 48], "frames": ["intact", "damaged", "debris"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_void_arena_atlases.py", "atlases": entries}
    (OUTPUT / "void_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (OUTPUT / "VOID_LICENSE.txt").write_text(
        "Plane Walker Original Void Arena Artwork\n\n"
        "Original raster pixel geometry authored locally for Plane Walker.\n"
        "The artwork is dedicated under CC0 1.0 Universal.\n"
        "https://creativecommons.org/publicdomain/zero/1.0/\n"
        "Source: tools/production_art/generate_void_arena_atlases.py\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
