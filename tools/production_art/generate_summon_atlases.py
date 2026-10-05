#!/usr/bin/env python3
"""Reproduce original CC0 Plane Walker support-unit pixel atlases."""

from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/summons"
INK = (23, 29, 37, 255)
LIGHT = (220, 247, 230, 255)
PALETTES = {
    "mini_wraith": (116, 216, 192, 255),
    "small_void_spore": (226, 116, 191, 255),
    "void_firefly": (241, 209, 94, 255),
    "void_beetle": (106, 163, 220, 255),
    "hunter_echo": (163, 133, 226, 255),
    "ranger_echo": (121, 221, 153, 255),
    "timeline_echo": (234, 164, 102, 255),
    "void_sapling": (87, 177, 117, 255),
    "elite_mirror": (194, 222, 244, 255),
}


def frame(kind: str, phase: int) -> Image.Image:
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    color = PALETTES[kind]
    accent = (245, 216, 90, 255) if phase == 1 else LIGHT
    rise = -2 if phase == 2 else 1 if phase == 3 else 0
    if kind == "void_firefly":
        draw.ellipse((3, 7 + rise, 14, 17 + rise), fill=INK)
        draw.ellipse((18, 7 + rise, 29, 17 + rise), fill=INK)
        draw.ellipse((5, 9 + rise, 13, 15 + rise), fill=LIGHT)
        draw.ellipse((19, 9 + rise, 27, 15 + rise), fill=LIGHT)
        draw.ellipse((11, 12 + rise, 21, 25 + rise), fill=INK)
        draw.ellipse((13, 14 + rise, 19, 23 + rise), fill=color)
    elif kind == "small_void_spore":
        draw.ellipse((5, 5 + rise, 27, 22 + rise), fill=INK)
        draw.ellipse((7, 7 + rise, 25, 20 + rise), fill=color)
        draw.rectangle((11, 20 + rise, 21, 28), fill=INK)
        draw.rectangle((13, 21 + rise, 19, 26), fill=LIGHT)
        for x, y in [(11, 11), (20, 9), (22, 15)]:
            draw.rectangle((x, y + rise, x + 2, y + rise + 2), fill=accent)
    elif kind == "void_sapling":
        draw.line(((15, 13), (16, 27)), fill=INK, width=7)
        draw.line(((15, 13), (16, 26)), fill=color, width=3)
        for points in [((5, 7 + rise), (14, 5 + rise), (16, 15)), ((17, 10), (24, 3 + rise), (28, 10 + rise)), ((4, 18), (14, 13), (15, 22))]:
            draw.polygon(points, fill=INK)
        draw.polygon(((7, 8 + rise), (13, 7 + rise), (14, 13)), fill=color)
        draw.polygon(((20, 9), (24, 6 + rise), (25, 10)), fill=accent)
        draw.line(((8, 28), (16, 25), (25, 28)), fill=INK, width=3)
    elif kind == "void_beetle":
        for y in [12, 18, 24]:
            draw.line(((3, y), (10, y - 3), (22, y - 3), (29, y)), fill=INK, width=3)
        draw.ellipse((7, 7 + rise, 25, 27), fill=INK)
        draw.ellipse((9, 9 + rise, 23, 25), fill=color)
        draw.line(((16, 10 + rise), (16, 24)), fill=INK, width=2)
    else:
        draw.polygon(((16, 3 + rise), (25, 9 + rise), (24, 20), (28, 28), (18, 25), (13, 28), (5, 27), (8, 19), (7, 10 + rise)), fill=INK)
        draw.polygon(((16, 5 + rise), (22, 10 + rise), (21, 20), (24, 25), (17, 22), (12, 25), (8, 24), (11, 18), (10, 11 + rise)), fill=color)
        if kind == "ranger_echo":
            draw.arc((21, 9, 30, 25), 80, 280, fill=accent, width=2)
            draw.line(((26, 9), (26, 25)), fill=INK)
        elif kind == "hunter_echo":
            draw.line(((5, 18), (1, 22 + rise)), fill=accent, width=3)
            draw.line(((25, 18), (30, 22 + rise)), fill=accent, width=3)
        elif kind == "timeline_echo":
            draw.rectangle((12, 18, 20, 25), fill=INK)
            draw.line(((13, 19), (19, 24), (13, 24), (19, 19)), fill=accent)
        elif kind == "elite_mirror":
            draw.line(((6, 9), (3, 15), (5, 24)), fill=LIGHT)
            draw.line(((26, 9), (29, 15), (27, 24)), fill=LIGHT)
    draw.rectangle((12, 12 + rise, 14, 14 + rise), fill=INK)
    draw.rectangle((18, 12 + rise, 20, 14 + rise), fill=INK)
    draw.point((13, 12 + rise), fill=accent)
    draw.point((19, 12 + rise), fill=accent)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for kind in PALETTES:
        atlas = Image.new("RGBA", (128, 32))
        for phase in range(4):
            atlas.paste(frame(kind, phase), (phase * 32, 0))
        path = OUTPUT / f"{kind}.png"
        atlas.save(path)
        rows.append({"id": kind, "path": path.name, "frame_size": [32, 32], "frames": ["idle", "warning", "active", "recovery"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_summon_atlases.py", "atlases": rows}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
