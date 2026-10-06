#!/usr/bin/env python3
"""Reproduce the original elemental hostile projectile and area pixel atlases."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/hostile_effects"
INK = (25, 28, 34, 255)
PALETTES = {
    "physical": ((144, 162, 174, 255), (223, 192, 95, 255), (237, 243, 238, 255)),
    "time": ((77, 169, 177, 255), (110, 224, 221, 255), (228, 251, 241, 255)),
    "void": ((99, 72, 147, 255), (209, 112, 189, 255), (240, 203, 238, 255)),
    "fire": ((169, 53, 48, 255), (241, 129, 58, 255), (255, 231, 133, 255)),
    "ice": ((97, 140, 197, 255), (146, 211, 243, 255), (243, 249, 255, 255)),
    "lightning": ((149, 138, 68, 255), (246, 213, 65, 255), (254, 254, 220, 255)),
}
LICENSE = """Plane Walker Original Hostile Effect Artwork

The twelve four-frame projectile and area atlases and contact sheet were authored
locally from original pixel geometry for Plane Walker. No external images,
downloaded samples, remote generation services or third-party artwork were used.

The artwork is dedicated to the public domain under CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/
The dedication applies to the artwork, not game code or project identity.

Source: tools/production_art/generate_hostile_effect_atlases.py
Reproduction: python3 tools/production_art/generate_hostile_effect_atlases.py
The existing certified corrosive Moth acid atlases are preserved independently.
"""


def projectile(kind: str, phase: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    dark, mid, light = PALETTES[kind]
    shift = (0, -1, 0, 1)[phase]
    if kind == "physical":
        draw.polygon([(5, 13), (20, 13), (20, 8), (28, 16), (20, 24), (20, 19), (5, 19)], fill=INK)
        draw.polygon([(7, 14), (22, 14), (22, 11), (26, 16), (22, 21), (22, 18), (7, 18)], fill=dark)
        draw.line([(9, 16), (23, 16)], fill=light, width=2)
        draw.rectangle((4 + phase, 11, 9 + phase, 12), fill=mid)
    elif kind == "time":
        draw.ellipse((8, 7, 26, 25), fill=INK)
        draw.ellipse((10, 9, 24, 23), fill=dark)
        draw.ellipse((12, 11, 22, 21), outline=mid, width=2)
        draw.line([(17, 16), (17 + (phase % 2) * 4, 11 + phase)], fill=light, width=2)
        for y in (9, 16, 23):
            draw.rectangle((3 + phase, y, 7 + phase, y + 1), fill=mid)
        draw.rectangle((16, 5, 18, 8), fill=mid)
        draw.rectangle((25, 15, 28, 17), fill=light)
    elif kind in ("void", "ice"):
        points = [(4, 16 + shift), (16, 9), (28, 16), (16, 23)]
        draw.polygon(points, fill=INK)
        draw.polygon([(6, 16 + shift), (17, 11), (26, 16), (17, 21)], fill=dark)
        draw.polygon([(10, 16), (18, 12), (25, 16), (17, 18)], fill=mid)
        draw.line([(17, 13), (23, 16)], fill=light, width=2)
        draw.rectangle((3 + phase, 8, 5 + phase, 10), fill=light)
        draw.rectangle((6, 23 - phase, 8, 24 - phase), fill=mid)
    elif kind == "fire":
        draw.polygon([(3, 8 + shift), (15, 12), (21, 7), (29, 16), (22, 25), (16, 21), (4, 24 - shift), (9, 16)], fill=INK)
        draw.polygon([(5, 10 + shift), (16, 13), (21, 9), (27, 16), (21, 23), (17, 19), (7, 22 - shift), (12, 16)], fill=dark)
        draw.ellipse((15, 11 + shift, 26, 22 + shift), fill=mid)
        draw.polygon([(18, 15), (23, 13 + phase % 2), (25, 17), (21, 20)], fill=light)
        draw.rectangle((4 + phase, 5 + phase, 5 + phase, 6 + phase), fill=mid)
    else:
        draw.polygon([(2, 17), (12, 6 + shift), (18, 11), (24, 9), (30, 16), (19, 26), (14, 20), (7, 24)], fill=INK)
        draw.polygon([(5, 17), (13, 9 + shift), (16, 14), (24, 12), (27, 16), (19, 23), (16, 17), (9, 21)], fill=mid)
        draw.line([(10, 17), (17, 14), (23, 16)], fill=light, width=2)
        draw.rectangle((4 + phase, 8, 6 + phase, 9), fill=dark)
    return image


def pool(kind: str, phase: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    dark, mid, light = PALETTES[kind]
    inset = phase % 2
    draw.ellipse((3, 6, 29, 27), fill=INK)
    # Pixel art uses binary alpha. Keep the pool's depth in the palette instead
    # of introducing a translucent antialiased shadow.
    draw.ellipse((5, 8, 27, 25), fill=dark)
    draw.ellipse((6 + inset, 9 + inset, 26 - inset, 24 - inset), outline=mid, width=2)
    draw.ellipse((10, 12, 22, 21), outline=mid, width=1)
    draw.polygon([(16, 10 + phase), (21, 16), (16, 22 - phase), (11, 16)], outline=light)
    for x, y in ((7 + phase, 15), (22 - phase, 20), (16, 7 + phase)):
        draw.rectangle((x, y, x + 1, y + 1), fill=light)
    if kind == "physical":
        draw.line([(10, 11), (15 + phase, 17), (12, 24)], fill=light, width=1)
    elif kind == "lightning":
        draw.line([(9, 19), (14, 13 + phase), (17, 17), (23, 11)], fill=light, width=2)
    return image


def generate(destination: Path = OUTPUT) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    manifest = {"schema_id": "plane_walker_hostile_effect_art_v1", "license": "CC0-1.0", "frame_size": 32, "frame_count": 4, "assets": []}
    contact = Image.new("RGBA", (256, 6 * 40), (28, 31, 37, 255))
    for row, kind in enumerate(PALETTES):
        for column, shape in enumerate(("projectile", "pool")):
            atlas = Image.new("RGBA", (128, 32))
            renderer = projectile if shape == "projectile" else pool
            for phase in range(4):
                atlas.paste(renderer(kind, phase), (phase * 32, 0))
            name = f"{kind}_{shape}.png"
            path = destination / name
            atlas.save(path)
            manifest["assets"].append({"id": f"{kind}_{shape}", "path": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
            contact.alpha_composite(atlas, (column * 128, row * 40 + 4))
    contact.save(destination / "contact-sheet.png")
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (destination / "LICENSE.txt").write_text(LICENSE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    generate(parser.parse_args().output)
