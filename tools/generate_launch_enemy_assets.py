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
}


def raster() -> bytes:
    pixels = bytearray(128 * 32 * 4)

    def rect(frame: int, x: int, y: int, w: int, h: int, color: str) -> None:
        rgba = bytes(COLORS[color])
        for row in range(y, y + h):
            for col in range(x, x + w):
                offset = (row * 128 + frame * 32 + col) * 4
                pixels[offset : offset + 4] = rgba

    for frame in range(4):
        shift = -1 if frame == 2 else 1 if frame == 3 else 0
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
    data = raster()
    filename = "shattered_sentinel.png"
    (OUTPUT / filename).write_bytes(data)
    manifest = {
        "schema_version": 1,
        "status": "inactive_p15_work",
        "generator": "tools/generate_launch_enemy_assets.py",
        "provenance": "Original project-authored procedural pixel artwork; no third-party source assets.",
        "license": "CC0-1.0",
        "assets": [{"path": filename, "sha256": hashlib.sha256(data).hexdigest(), "width": 128, "height": 32, "frame_width": 32, "frames": ["idle", "warning", "active", "recovery"]}],
    }
    (OUTPUT / "generated_assets.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
