#!/usr/bin/env python3
"""Generate original, deterministic Hub district and NPC pixel artwork."""

from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/content_packs/base/assets/hub"
NPCS = ["odysseus", "elara", "sibyl", "hermes", "phia", "morpheus", "nemesis", "vera"]


class Raster:
    def __init__(self, width: int, height: int, color=(0, 0, 0, 0)):
        self.width, self.height = width, height
        self.pixels = bytearray(bytes(color) * width * height)

    def rect(self, x: int, y: int, w: int, h: int, color) -> None:
        row = bytes(color) * max(0, min(self.width, x + w) - max(0, x))
        for yy in range(max(0, y), min(self.height, y + h)):
            offset = (yy * self.width + max(0, x)) * 4
            self.pixels[offset : offset + len(row)] = row

    def png(self) -> bytes:
        stride = self.width * 4
        raw = b"".join(b"\0" + self.pixels[y * stride : (y + 1) * stride] for y in range(self.height))

        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def district(kind: str) -> Raster:
    image = Raster(640, 360, (24, 29, 31, 255))
    stone, edge, light = (76, 86, 84, 255), (47, 55, 56, 255), (129, 142, 137, 255)
    gold, ivory, teal = (213, 172, 78, 255), (214, 224, 209, 255), (86, 181, 161, 255)
    image.rect(24, 48, 592, 286, edge)
    for y in range(56, 328, 16):
        for x in range(32, 608, 32):
            color = stone if (x // 32 + y // 16) % 4 else (68, 79, 76, 255)
            image.rect(x + (16 if y % 32 else 0), y, 30, 14, color)
            image.rect(x + (16 if y % 32 else 0), y, 29, 1, light)
    image.rect(32, 54, 576, 6, light)
    image.rect(48, 318, 544, 4, light)
    image.rect(288, 192, 64, 126, (102, 108, 92, 255))
    image.rect(292, 196, 56, 118, (88, 101, 95, 255))
    for x in (40, 584):
        for y in (88, 242):
            image.rect(x, y, 16, 40, edge)
            image.rect(x + 4, y + 4, 8, 24, gold)
            image.rect(x + 5, y + 5, 6, 12, ivory)
            image.rect(x - 4, y + 37, 24, 5, light)
    for index, x in enumerate((160, 320, 480)):
        image.rect(x - 58, 98, 116, 96, edge)
        image.rect(x - 54, 102, 108, 82, stone)
        image.rect(x - 60, 190, 120, 8, light)
        image.rect(x - 64, 200, 128, 6, stone)
        if kind == "hub_council":
            image.rect(x - 44, 68, 88, 28, (126, 56, 67, 255))
            image.rect(x - 40, 72, 80, 3, gold)
            for pillar_x in (x - 48, x + 36):
                image.rect(pillar_x, 96, 12, 86, light)
                image.rect(pillar_x + 4, 99, 3, 76, ivory)
            if index == 0:
                image.rect(x - 24, 112, 48, 34, (51, 95, 92, 255))
                image.rect(x - 4, 116, 8, 24, gold)
                image.rect(x - 14, 125, 28, 6, gold)
            elif index == 1:
                for book_y in (112, 132, 152):
                    image.rect(x - 24, book_y, 48, 5, edge)
                    for book_x in range(x - 22, x + 20, 8):
                        image.rect(book_x, book_y - 14, 6, 14, gold if book_x % 3 else teal)
            else:
                image.rect(x - 20, 104, 40, 56, edge)
                image.rect(x - 16, 108, 32, 48, teal)
                image.rect(x - 10, 114, 20, 42, (32, 60, 58, 255))
                image.rect(x - 2, 112, 4, 40, ivory)
        elif kind == "hub_craft":
            image.rect(x - 42, 74, 84, 24, (76, 113, 87, 255))
            image.rect(x - 40, 76, 80, 4, teal)
            if index == 0:
                image.rect(x - 4, 106, 8, 48, gold)
                image.rect(x - 24, 114, 48, 8, ivory)
                image.rect(x - 18, 105, 36, 28, (161, 72, 68, 255))
                image.rect(x - 11, 110, 22, 18, ivory)
                image.rect(x - 4, 114, 8, 10, gold)
            elif index == 1:
                image.rect(x - 26, 104, 52, 52, edge)
                image.rect(x - 16, 112, 32, 28, (212, 104, 63, 255))
                image.rect(x - 10, 124, 20, 16, gold)
                image.rect(x - 22, 156, 44, 8, light)
                image.rect(x - 6, 150, 12, 18, light)
            else:
                image.rect(x - 22, 110, 44, 10, ivory)
                image.rect(x - 4, 106, 8, 45, teal)
                image.rect(x - 26, 150, 52, 8, teal)
        else:
            roof = (75, 126, 151, 255) if index % 2 else (156, 103, 137, 255)
            image.rect(x - 62, 78, 124, 24, roof)
            for stripe in range(x - 58, x + 54, 16):
                image.rect(stripe, 80, 8, 20, ivory)
            if index == 0:
                for crate_x in (x - 26, x + 2):
                    image.rect(crate_x, 125, 24, 32, gold)
                    image.rect(crate_x + 3, 129, 18, 3, ivory)
                    image.rect(crate_x + 3, 150, 18, 3, edge)
            elif index == 1:
                image.rect(x - 26, 108, 52, 48, gold)
                image.rect(x - 22, 112, 44, 40, edge)
                image.rect(x - 12, 122, 24, 20, teal)
                image.rect(x - 4, 114, 8, 32, ivory)
            else:
                image.rect(x - 26, 104, 52, 54, ivory)
                image.rect(x - 22, 108, 44, 46, (77, 127, 147, 255))
                image.rect(x - 10, 112, 4, 38, (180, 214, 208, 255))
                image.rect(x + 8, 112, 4, 38, teal)
    return image


def portraits() -> Raster:
    image = Raster(32 * 9, 32)
    coats = [(124, 63, 72, 255), (51, 130, 120, 255), (123, 87, 160, 255), (165, 130, 61, 255), (91, 135, 167, 255), (94, 111, 99, 255), (158, 76, 69, 255), (188, 126, 75, 255), (103, 166, 151, 255)]
    for index, coat in enumerate(coats):
        x = index * 32
        image.rect(x + 8, 26, 17, 3, (19, 26, 25, 160))
        image.rect(x + 11, 5, 11, 22, (24, 28, 31, 255))
        image.rect(x + 12, 6, 9, 8, (208, 192, 165, 255))
        image.rect(x + 10, 14, 14, 12, coat)
        image.rect(x + 13, 14, 2, 10, (212, 221, 207, 255))
        image.rect(x + 15, 9, 1, 1, (24, 28, 31, 255))
        image.rect(x + 19, 9, 1, 1, (24, 28, 31, 255))
        image.rect(x + 11, 26, 5, 3, (24, 28, 31, 255))
        image.rect(x + 19, 26, 5, 3, (24, 28, 31, 255))
        if index in (0, 6):
            image.rect(x + 10, 4, 13, 4, (148, 160, 151, 255))
            image.rect(x + 24, 13, 3, 14, (213, 172, 78, 255))
        elif index in (2, 4):
            image.rect(x + 7, 5, 18, 3, coat)
            image.rect(x + 11, 2, 10, 3, coat)
            image.rect(x + 25, 9, 2, 18, (213, 172, 78, 255))
        elif index == 3:
            image.rect(x + 6, 5, 20, 3, coat)
            image.rect(x + 12, 2, 9, 3, coat)
        elif index == 7:
            image.rect(x + 22, 14, 7, 4, (148, 160, 151, 255))
            image.rect(x + 24, 18, 2, 10, (213, 172, 78, 255))
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    assets = []
    for name, image in [(name, district(name)) for name in ("hub_council", "hub_craft", "hub_rift")] + [("hub_portraits", portraits())]:
        data = image.png()
        (OUTPUT / f"{name}.png").write_bytes(data)
        assets.append({"path": f"{name}.png", "sha256": hashlib.sha256(data).hexdigest(), "width": image.width, "height": image.height})
    (OUTPUT / "generated_assets.json").write_text(json.dumps({"schema_version": 1, "status": "native_hub_work", "generator": "tools/generate_hub_assets.py", "provenance": "Original project-authored procedural pixel artwork; no third-party sources.", "license": "CC0-1.0", "npc_frame_order": NPCS + ["walker"], "assets": assets}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
