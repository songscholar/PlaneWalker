#!/usr/bin/env python3
"""Reproduce original CC0 enemy wall, link and portal raster atlases."""

from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/enemy_spatial"
INK = (22, 30, 40, 255)
PALETTES = {
    "bramble_wall": (97, 190, 115, 255),
    "web_wall": (159, 119, 218, 255),
    "web_link": (236, 149, 214, 255),
    "portal_both": (129, 226, 245, 255),
    "portal_enemy": (242, 99, 119, 255),
}


def frame(kind: str, phase: int) -> Image.Image:
    portal = kind.startswith("portal_")
    size = (32, 32) if portal else (64, 16)
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    color = (246, 225, 120, 255) if phase == 0 else PALETTES[kind]
    if portal:
        draw.ellipse((2, 2, 29, 29), fill=INK)
        draw.ellipse((4, 4, 27, 27), outline=color, width=3)
        draw.ellipse((9, 8, 22, 23), outline=(221, 249, 255, 255), width=2)
        if kind == "portal_enemy":
            draw.polygon(((12, 11), (20, 16), (12, 21)), fill=color)
        else:
            draw.line(((10, 15), (21, 15)), fill=color, width=2)
            draw.polygon(((10, 12), (6, 16), (10, 20)), fill=color)
            draw.polygon(((21, 12), (25, 16), (21, 20)), fill=color)
        for x, y in [(15, 1), (29, 15), (15, 29), (1, 15)]:
            draw.rectangle((x, y, x + 1, y + 1), fill=color)
    else:
        draw.line(((0, 8), (63, 8)), fill=INK, width=7)
        draw.line(((0, 7), (63, 7)), fill=color, width=3)
        for x in range(4 + phase, 64, 8):
            draw.line(((x - 3, 3), (x, 8), (x + 3, 13)), fill=INK, width=3)
            draw.line(((x - 2, 3), (x, 7), (x + 2, 12)), fill=color, width=1)
        if kind == "web_link":
            draw.line(((0, 3), (63, 12)), fill=(233, 221, 244, 255), width=1)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for kind in PALETTES:
        first = frame(kind, 0)
        atlas = Image.new("RGBA", (first.width * 4, first.height))
        for phase in range(4):
            atlas.paste(frame(kind, phase), (phase * first.width, 0))
        path = OUTPUT / f"{kind}.png"
        atlas.save(path)
        rows.append({"id": kind, "path": path.name, "frame_size": list(first.size), "frames": ["warning", "active_1", "active_2", "active_3"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_enemy_spatial_atlases.py", "atlases": rows}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
