#!/usr/bin/env python3
"""Reproduce original Hound sigil and Phase Ranger arrival raster cues."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/enemy_mechanisms"


def _hound_frame(phase: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    ink = (24, 28, 35, 255)
    glow = (118, 234, 228, 255)
    # A compact rune silhouette reads as a targetable dormant sigil at 1x.
    draw.ellipse((3, 8, 28, 26), fill=ink)
    draw.arc((4, 9, 27, 25), 200 + phase * 18, 530 + phase * 18, fill=glow, width=2)
    draw.arc((6, 11, 25, 23), 20 + phase * 18, 160 + phase * 18, fill=(226, 238, 236, 255), width=1)
    ear_shift = phase % 2
    draw.polygon(((10, 14), (10 - ear_shift, 8), (14, 12), (18, 12), (22 + ear_shift, 8), (22, 14), (20, 21), (16, 24), (12, 21)), fill=ink)
    draw.line(((16, 13), (16, 20)), fill=glow, width=2)
    draw.line(((12, 16), (20, 16)), fill=glow, width=2)
    draw.rectangle((13, 18, 14, 19), fill=(226, 238, 236, 255))
    draw.rectangle((18, 18, 19, 19), fill=(226, 238, 236, 255))
    # Four moving charge ticks make the frame changes intentional.
    ticks = (((16, 2), (16, 6)), ((27, 10), (24, 12)), ((16, 30), (16, 26)), ((5, 10), (8, 12)))
    for index, (start, end) in enumerate(ticks):
        if index == phase or index == (phase + 1) % 4:
            draw.line((start, end), fill=glow, width=2)
    return image


def _arrival_frame(phase: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    ink = (24, 28, 35, 255)
    glow = (248, 196, 78, 255)
    pale = (255, 236, 158, 255)
    # Phase travel is represented by a four-corner gate and a scanning beam.
    corners = ((4, 4), (27, 5), (26, 27), (5, 26))
    for x, y in corners:
        draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill=ink)
    draw.line(((5, 5), (11, 11), (5, 26), (11, 20)), fill=ink, width=2)
    draw.line(((27, 5), (21, 11), (27, 26), (21, 20)), fill=ink, width=2)
    draw.line(((5, 5), (11, 11)), fill=glow, width=1)
    draw.line(((27, 5), (21, 11)), fill=glow, width=1)
    draw.line(((5, 26), (11, 20)), fill=glow, width=1)
    draw.line(((27, 26), (21, 20)), fill=glow, width=1)
    aperture = ((16, 7), (23, 16), (16, 25), (9, 16))
    draw.polygon(aperture, fill=ink)
    inner = ((16, 10 + phase % 2), (20, 16), (16, 22 - phase % 2), (12, 16))
    draw.polygon(inner, fill=glow)
    scan_y = (10, 13, 16, 19)[phase]
    draw.line(((10, scan_y), (22, scan_y)), fill=pale, width=2)
    if phase in (1, 3):
        draw.rectangle((2, 14, 5, 17), fill=glow)
        draw.rectangle((26, 14, 29, 17), fill=glow)
    return image


def generate() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name in ("hound_sigil", "phase_arrival"):
        atlas = Image.new("RGBA", (128, 32))
        for frame in range(4):
            image = _hound_frame(frame) if name == "hound_sigil" else _arrival_frame(frame)
            atlas.alpha_composite(image, (frame * 32, 0))
        target = OUTPUT / f"{name}.png"
        atlas.save(target)
        rows.append({"id": name, "path": target.name, "width": 128, "height": 32, "frame_width": 32, "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    (OUTPUT / "manifest.json").write_text(json.dumps({"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_enemy_mechanism_atlases.py", "atlases": rows}, indent=2) + "\n")
    (OUTPUT / "LICENSE.txt").write_text("Plane Walker original enemy mechanism artwork\n\nThese raster atlases were authored locally from original pixel geometry.\nDedicated to the public domain under CC0 1.0 Universal:\nhttps://creativecommons.org/publicdomain/zero/1.0/\n\nSource: tools/production_art/generate_enemy_mechanism_atlases.py\n")


if __name__ == "__main__":
    generate()
