#!/usr/bin/env python3
"""Generate original deterministic pixel rasters for inactive P15 actor scenes."""

from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/content_packs/base/assets/enemies/launch"
COLORS = {
    "outline": (28, 32, 39, 255),
    "shadow": (64, 75, 80, 255),
    "stone": (114, 134, 137, 255),
    "light": (173, 194, 192, 255),
    "gold": (218, 174, 67, 255),
    "eye": (84, 233, 220, 255),
    "acid": (165, 222, 77, 255),
    "wing": (96, 153, 177, 230),
    "violet": (163, 133, 215, 255),
    "spirit": (213, 239, 237, 240),
}


def raster(species: str = "shattered_sentinel") -> bytes:
    pixels = bytearray(128 * 32 * 4)

    def rect(frame: int, x: int, y: int, w: int, h: int, color: str) -> None:
        rgba = bytes(COLORS[color])
        for row in range(y, y + h):
            for col in range(x, x + w):
                offset = (row * 128 + frame * 32 + col) * 4
                pixels[offset : offset + 4] = rgba

    for frame in range(4):
        shift = -1 if frame == 2 else 1 if frame == 3 else 0
        if species == "acid_projectile":
            rect(frame, 9, 12, 14, 8, "outline")
            rect(frame, 12, 10, 8, 12, "outline")
            rect(frame, 11, 13, 10, 6, "acid")
            rect(frame, 14, 12, 6, 8, "acid")
            rect(frame, 17, 13, 3, 3, "spirit")
            rect(frame, 3 + frame, 15, 6, 2, "gold")
            continue
        if species == "acid_pool":
            rect(frame, 4, 9, 24, 14, "outline")
            rect(frame, 8, 4, 16, 24, "outline")
            rect(frame, 5, 10, 22, 12, "shadow")
            rect(frame, 9, 5, 14, 22, "acid")
            rect(frame, 6, 11, 20, 10, "acid")
            rect(frame, 10, 9, 3, 3, "spirit")
            rect(frame, 19, 19 - frame, 4, 3, "gold")
            rect(frame, 13, 18, 4, 4, "shadow")
            continue
        if species == "stone_shell_strider":
            for leg in (5, 12, 21):
                rect(frame, leg + shift, 21, 5, 6, "outline")
                rect(frame, leg + shift, 22, 3, 4, "shadow")
            rect(frame, 3 + shift, 12, 25, 11, "outline")
            rect(frame, 6 + shift, 7, 19, 15, "outline")
            rect(frame, 7 + shift, 8, 17, 13, "stone")
            rect(frame, 9 + shift, 6, 13, 3, "outline")
            rect(frame, 10 + shift, 7, 11, 2, "light")
            for plate in (9, 15, 21):
                rect(frame, plate + shift, 10, 2, 10, "shadow")
                rect(frame, plate + shift, 10, 1, 6, "gold")
            rect(frame, 23 + shift, 15, 6, 7, "outline")
            rect(frame, 24 + shift, 16, 4, 4, "shadow")
            rect(frame, 27 + shift, 16, 1, 2, "eye")
            if frame == 1:
                rect(frame, 4, 10, 2, 5, "gold")
            if frame == 3:
                rect(frame, 11, 17, 9, 4, "eye")
            continue
        if species == "ruins_wraith":
            rect(frame, 10 + shift, 4, 12, 18, "outline")
            rect(frame, 8 + shift, 9, 16, 12, "outline")
            rect(frame, 11 + shift, 5, 10, 16, "violet")
            rect(frame, 12 + shift, 8, 8, 8, "spirit")
            rect(frame, 13 + shift, 11, 2, 2, "outline")
            rect(frame, 17 + shift, 11, 2, 2, "outline")
            for trail in (9, 14, 19):
                rect(frame, trail + shift, 20, 3, 8 - frame, "violet")
                rect(frame, trail + shift + 1, 21, 1, 5 - frame, "spirit")
            if frame in (1, 2):
                rect(frame, 5, 13, 3, 8, "eye")
                rect(frame, 24, 13, 3, 8, "eye")
            continue
        if species == "corrosive_moth":
            wing_y = 8 if frame in (0, 2) else 11
            rect(frame, 3, wing_y, 11, 13, "outline")
            rect(frame, 18, wing_y, 11, 13, "outline")
            rect(frame, 4, wing_y + 1, 9, 10, "wing")
            rect(frame, 19, wing_y + 1, 9, 10, "wing")
            rect(frame, 7, wing_y + 3, 4, 5, "acid")
            rect(frame, 21, wing_y + 3, 4, 5, "acid")
            rect(frame, 13, 8, 6, 18, "outline")
            rect(frame, 14, 9, 4, 15, "gold")
            rect(frame, 14, 10, 4, 4, "shadow")
            rect(frame, 14, 11, 1, 1, "eye")
            rect(frame, 17, 11, 1, 1, "eye")
            if frame == 2:
                rect(frame, 14, 25, 4, 4, "acid")
            continue
        if species == "rift_watcher":
            rect(frame, 9, 3 + shift, 14, 25, "outline")
            rect(frame, 6, 8 + shift, 20, 17, "outline")
            rect(frame, 10, 4 + shift, 12, 21, "stone")
            rect(frame, 7, 10 + shift, 18, 9, "gold")
            rect(frame, 8, 11 + shift, 16, 7, "outline")
            rect(frame, 10, 12 + shift, 12, 5, "spirit")
            rect(frame, 15, 11 + shift, 3, 7, "eye")
            rect(frame, 16, 12 + shift, 1, 5, "outline")
            rect(frame, 13, 21 + shift, 6, 3, "violet")
            if frame in (1, 2):
                rect(frame, 3, 13, 2, 9, "eye")
                rect(frame, 27, 13, 2, 9, "eye")
            continue
        # A fractured stone guardian with a large edged shield and luminous eyes.
        rect(frame, 10 + shift, 6, 13, 19, "outline")
        rect(frame, 11 + shift, 7, 11, 17, "shadow")
        rect(frame, 12 + shift, 7, 9, 9, "stone")
        rect(frame, 13 + shift, 7, 7, 2, "light")
        rect(frame, 12 + shift, 11, 9, 3, "outline")
        rect(frame, 13 + shift, 11, 3, 1, "eye")
        rect(frame, 18 + shift, 11, 2, 1, "eye")
        rect(frame, 15 + shift, 8, 1, 3, "shadow")
        rect(frame, 12 + shift, 17, 8, 6, "stone")
        rect(frame, 14 + shift, 17, 2, 2, "gold")
        rect(frame, 9 + shift, 24, 5, 4, "outline")
        rect(frame, 18 + shift, 24, 5, 4, "outline")
        rect(frame, 10 + shift, 24, 3, 3, "shadow")
        rect(frame, 19 + shift, 24, 3, 3, "shadow")
        shield_x = 3 if frame == 1 else 1 if frame == 2 else 4
        rect(frame, shield_x + 2, 12, 9, 14, "outline")
        rect(frame, shield_x, 14, 13, 9, "outline")
        rect(frame, shield_x + 2, 13, 9, 12, "gold")
        rect(frame, shield_x + 1, 15, 11, 7, "gold")
        rect(frame, shield_x + 3, 15, 7, 7, "shadow")
        rect(frame, shield_x + 4, 14, 5, 10, "stone")
        rect(frame, shield_x + 5, 16, 3, 5, "light")
        rect(frame, shield_x + 6, 17, 1, 3, "eye")
        rect(frame, 24 + shift, 17, 3, 7, "outline")
        rect(frame, 24 + shift, 18, 2, 5, "stone")
    raw = b"".join(b"\0" + pixels[row * 512 : (row + 1) * 512] for row in range(32))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 128, 32, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    assets = []
    for species in ("shattered_sentinel", "corrosive_moth", "stone_shell_strider", "ruins_wraith", "rift_watcher", "acid_projectile", "acid_pool"):
        data = raster(species)
        filename = f"{species}.png"
        (OUTPUT / filename).write_bytes(data)
        assets.append({"path": filename, "sha256": hashlib.sha256(data).hexdigest(), "width": 128, "height": 32, "frame_width": 32, "frames": ["idle", "warning", "active", "recovery"]})
    manifest = {
        "schema_version": 1,
        "status": "inactive_p15_work",
        "generator": "tools/generate_launch_enemy_assets.py",
        "provenance": "Original project-authored procedural pixel artwork; no third-party source assets.",
        "license": "CC0-1.0",
        "assets": assets,
    }
    (OUTPUT / "generated_assets.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
