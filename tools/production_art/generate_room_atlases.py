#!/usr/bin/env python3
"""Reproduce Plane Walker's original five-floor room pixel artwork."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from random import Random

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/rooms"
PALETTES = {
    "ruins": ((45, 53, 55), (70, 80, 78), (126, 139, 116), (189, 162, 96)),
    "forest": ((29, 47, 43), (49, 75, 57), (100, 140, 99), (202, 126, 173)),
    "rift": ((35, 47, 62), (62, 78, 97), (108, 138, 153), (135, 217, 215)),
    "forge": ((49, 44, 42), (80, 76, 71), (139, 142, 126), (224, 145, 79)),
    "void": ((42, 38, 49), (67, 62, 78), (130, 127, 142), (200, 211, 202)),
}
INK = (20, 24, 28)
GOLD = (207, 170, 85)
PALE = (215, 221, 207)
CYAN = (108, 210, 194)


def tile(kind: str, variant: int) -> Image.Image:
    base, middle, light, accent = PALETTES[kind]
    image = Image.new("RGB", (32, 32), base)
    draw = ImageDraw.Draw(image)
    draw.rectangle((1, 1, 30, 30), outline=middle)
    draw.line(((2, 2), (29, 2)), fill=tuple((a + b) // 2 for a, b in zip(base, middle)))
    rng = Random(variant + list(PALETTES).index(kind) * 31)
    for _ in range(16):
        x, y = rng.randrange(3, 29), rng.randrange(4, 29)
        color = middle if rng.randrange(4) == 0 else tuple(max(0, c - 3) for c in base)
        draw.line(((x, y), (min(x + rng.randrange(1, 4), 29), y)), fill=color)
    if kind == "ruins":
        draw.line(((3, 22), (13, 22), (13, 30)), fill=INK)
        if variant == 1:
            draw.line(((19, 5), (17, 13), (23, 19), (20, 28)), fill=INK)
        if variant == 3:
            draw.rectangle((4, 4, 7, 5), fill=light)
            draw.rectangle((6, 6, 10, 7), fill=middle)
    elif kind == "forest":
        draw.line(((0, 19), (8, 23), (18, 19), (31, 24)), fill=middle)
        draw.line(((8, 23), (10, 31)), fill=middle)
        if variant in (1, 3):
            draw.polygon(((20, 6), (25, 7), (22, 11), (18, 10)), fill=light)
            draw.rectangle((22, 7, 23, 8), fill=middle)
        if variant == 2:
            draw.rectangle((7, 11, 8, 12), fill=accent)
    elif kind == "rift":
        draw.line(((0, 16), (9, 16), (15, 10), (31, 10)), fill=middle)
        if variant == 2:
            draw.line(((4, 17), (10, 17), (16, 11), (23, 11)), fill=light)
            draw.rectangle((23, 10, 24, 11), fill=accent)
    elif kind == "forge":
        draw.rectangle((3, 3, 28, 28), outline=middle)
        for x, y in ((5, 5), (26, 5), (5, 26), (26, 26)):
            draw.rectangle((x, y, x + 1, y + 1), fill=middle)
        if variant == 3:
            draw.line(((13, 0), (13, 5), (17, 9)), fill=accent)
            draw.line(((14, 0), (14, 4)), fill=light)
    else:
        draw.line(((4, 4), (13, 4), (13, 13)), fill=middle)
        draw.line(((19, 19), (19, 27), (27, 27)), fill=middle)
        if variant == 2:
            draw.line(((9, 24), (16, 17), (21, 19), (28, 12)), fill=light)
        if variant == 3:
            draw.rectangle((14, 14, 17, 17), outline=accent)
    return image


def wall(kind: str) -> Image.Image:
    base, middle, light, accent = PALETTES[kind]
    image = Image.new("RGB", (64, 32), INK)
    draw = ImageDraw.Draw(image)
    for y in (3, 17):
        for x in range(-16 if y == 17 else 0, 64, 32):
            draw.rectangle((x + 1, y, x + 30, y + 12), fill=middle)
            draw.line(((x + 2, y), (x + 28, y)), fill=light)
            draw.rectangle((x + 3, y + 10, x + 28, y + 11), fill=base)
    if kind == "forest":
        draw.line(((4, 0), (8, 9), (16, 13), (11, 26)), fill=light, width=2)
    elif kind in ("rift", "void"):
        draw.line(((48, 3), (44, 9), (48, 14), (43, 22)), fill=accent)
    elif kind == "forge":
        draw.rectangle((28, 7, 35, 22), fill=INK)
        draw.rectangle((30, 9, 33, 19), fill=accent)
    return image


def doorway(kind: str) -> Image.Image:
    base, middle, light, accent = PALETTES[kind]
    image = Image.new("RGBA", (48, 80))
    draw = ImageDraw.Draw(image)
    draw.rectangle((4, 9, 43, 74), fill=INK)
    draw.polygon(((5, 10), (13, 2), (34, 2), (42, 10), (42, 74), (5, 74)), fill=middle)
    draw.polygon(((12, 17), (18, 11), (29, 11), (35, 17), (35, 69), (12, 69)), fill=INK)
    draw.line(((7, 12), (15, 4), (32, 4), (40, 12)), fill=light, width=2)
    for y in (20, 37, 54):
        draw.line(((5, y), (11, y)), fill=base)
        draw.line(((36, y), (42, y)), fill=base)
    draw.rectangle((20, 5, 27, 8), fill=accent)
    for y in range(23, 63, 9):
        draw.line(((18, y), (24, y - 3), (29, y)), fill=base)
    draw.rectangle((10, 70, 37, 75), fill=light)
    draw.rectangle((13, 72, 34, 77), fill=middle)
    return image


def landmark(kind: str) -> Image.Image:
    image = Image.new("RGBA", (64, 64))
    draw = ImageDraw.Draw(image)
    stone, shadow = (105, 124, 119), (56, 74, 78)
    # Keep the landmark shadow as an opaque palette step; partial alpha reads as
    # a blur once the 64px atlas is scaled with nearest filtering.
    draw.ellipse((8, 49, 55, 58), fill=INK)
    if kind in ("combat", "elite", "boss"):
        draw.polygon(((9, 45), (18, 39), (45, 39), (55, 45), (47, 56), (16, 56)), fill=INK)
        draw.polygon(((13, 45), (20, 42), (43, 42), (50, 45), (44, 52), (19, 52)), fill=stone)
        draw.line(((18, 46), (44, 46)), fill=GOLD, width=2)
        if kind == "combat":
            draw.rectangle((25, 13, 38, 43), fill=INK)
            draw.rectangle((27, 14, 35, 41), fill=stone)
            draw.rectangle((21, 9, 42, 15), fill=INK)
            draw.rectangle((23, 10, 40, 13), fill=PALE)
            draw.line(((30, 19), (34, 24), (30, 30), (33, 36)), fill=CYAN, width=2)
        elif kind == "elite":
            draw.polygon(((32, 6), (43, 24), (32, 40), (21, 24)), fill=INK)
            draw.polygon(((32, 10), (39, 24), (32, 35), (25, 24)), fill=GOLD)
            draw.polygon(((32, 14), (33, 24), (30, 30), (27, 24)), fill=PALE)
        else:
            draw.rectangle((20, 8, 43, 35), fill=INK)
            draw.rectangle((23, 10, 40, 33), fill=shadow)
            draw.rectangle((25, 12, 38, 30), outline=GOLD)
            draw.rectangle((19, 30, 44, 44), fill=INK)
            draw.rectangle((22, 32, 41, 41), fill=stone)
            draw.rectangle((14, 26, 21, 42), fill=GOLD)
            draw.rectangle((42, 26, 49, 42), fill=GOLD)
    elif kind == "treasure":
        draw.rectangle((12, 23, 51, 51), fill=INK)
        draw.rectangle((14, 25, 49, 48), fill=(121, 91, 71))
        draw.rectangle((17, 21, 46, 32), fill=GOLD, outline=INK, width=2)
        draw.rectangle((17, 34, 46, 46), outline=GOLD, width=2)
        draw.rectangle((28, 29, 35, 38), fill=INK)
        draw.rectangle((30, 30, 33, 35), fill=PALE)
    elif kind == "shop":
        draw.rectangle((10, 13, 53, 50), fill=INK)
        draw.rectangle((13, 15, 50, 45), fill=shadow)
        draw.rectangle((7, 12, 56, 23), fill=GOLD, outline=INK, width=2)
        for x in (13, 25, 37, 49):
            draw.rectangle((x, 14, x + 4, 21), fill=(133, 64, 77))
        draw.rectangle((9, 39, 54, 49), fill=(121, 91, 71), outline=INK, width=2)
        draw.rectangle((19, 31, 25, 38), fill=CYAN)
        draw.ellipse((36, 32, 43, 38), fill=GOLD)
    elif kind == "rest":
        for box in ((10, 41, 20, 49), (24, 47, 36, 53), (44, 41, 54, 49)):
            draw.rectangle(box, fill=stone, outline=INK, width=2)
        draw.line(((19, 42), (42, 50)), fill=(121, 91, 71), width=5)
        draw.line(((20, 50), (43, 41)), fill=(121, 91, 71), width=5)
        draw.polygon(((18, 39), (22, 26), (26, 29), (32, 12), (38, 31), (43, 25), (46, 40), (32, 47)), fill=(215, 106, 77))
        draw.polygon(((25, 39), (32, 24), (40, 41), (32, 45)), fill=GOLD)
        draw.polygon(((29, 41), (32, 34), (36, 41)), fill=PALE)
    else:
        draw.rectangle((13, 43, 50, 52), fill=INK)
        draw.rectangle((16, 44, 47, 48), fill=stone)
        draw.rectangle((21, 29, 42, 44), fill=shadow, outline=INK, width=2)
        draw.polygon(((32, 8), (45, 22), (32, 35), (19, 22)), fill=INK)
        draw.polygon(((32, 12), (40, 22), (32, 30), (24, 22)), fill=CYAN)
        draw.line(((32, 14), (30, 22), (32, 27)), fill=PALE, width=2)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for kind in PALETTES:
        atlas = Image.new("RGB", (128, 32))
        for variant in range(4):
            atlas.paste(tile(kind, variant), (variant * 32, 0))
        for suffix, image in (("tiles", atlas), ("wall", wall(kind)), ("door", doorway(kind))):
            path = OUTPUT / f"{kind}_{suffix}.png"
            image.save(path)
            entries.append({"path": path.name, "size": list(image.size), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    kinds = ["combat", "elite", "boss", "treasure", "shop", "rest", "event"]
    atlas = Image.new("RGBA", (64 * len(kinds), 64))
    for index, kind in enumerate(kinds):
        atlas.paste(landmark(kind), (index * 64, 0))
    atlas.save(OUTPUT / "landmarks.png")
    entries.append({"path": "landmarks.png", "size": list(atlas.size), "frames": kinds, "sha256": hashlib.sha256((OUTPUT / "landmarks.png").read_bytes()).hexdigest()})
    manifest = {"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_room_atlases.py", "atlases": entries}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (OUTPUT / "LICENSE.txt").write_text(
        "Plane Walker Original Room Pixel Artwork\n\n"
        "Original pixel geometry authored locally for Plane Walker.\n"
        "Dedicated under CC0 1.0 Universal.\n"
        "https://creativecommons.org/publicdomain/zero/1.0/\n"
        "Source: tools/production_art/generate_room_atlases.py\n", encoding="utf-8",
    )


if __name__ == "__main__":
    main()
