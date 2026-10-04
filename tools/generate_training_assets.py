#!/usr/bin/env python3
"""Generate deterministic original training artwork and native tool symbols."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from generate_hub_assets import Raster

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/content_packs/base/assets/training"


def floor() -> Raster:
    image = Raster(640, 360, (26, 29, 30, 255))
    for y in range(72, 328, 16):
        for x in range(16, 624, 32):
            shade = 65 + ((x // 32 * 7 + y // 16 * 3) % 4) * 3
            image.rect(x, y, 30, 14, (shade, shade + 5, shade + 2, 255))
            image.rect(x + 1, y, 28, 1, (shade + 17, shade + 21, shade + 15, 255))
    for y in (70, 328):
        image.rect(12, y, 616, 4, (157, 169, 158, 255))
        image.rect(16, y + 4, 608, 2, (45, 49, 47, 255))
    for x in (10, 626):
        image.rect(x, 76, 4, 248, (121, 134, 127, 255))
    for x in (36, 600):
        for y in (102, 266):
            image.rect(x - 8, y - 6, 16, 30, (39, 44, 42, 255))
            image.rect(x - 4, y - 4, 8, 14, (222, 186, 93, 255))
            image.rect(x - 2, y - 3, 4, 8, (243, 232, 162, 255))
            image.rect(x - 9, y + 20, 18, 4, (139, 151, 140, 255))
    image.rect(144, 128, 352, 2, (125, 153, 143, 255))
    image.rect(144, 274, 352, 2, (125, 153, 143, 255))
    image.rect(144, 130, 2, 144, (125, 153, 143, 255))
    image.rect(494, 130, 2, 144, (125, 153, 143, 255))
    for x in (204, 424):
        image.rect(x - 22, 199, 44, 2, (183, 178, 142, 255))
        image.rect(x - 1, 178, 2, 44, (183, 178, 142, 255))
    for x in range(270, 376, 16):
        image.rect(x, 200, 7, 2, (154, 180, 164, 255))
    return image


def target() -> Raster:
    image = Raster(40, 48)
    image.rect(4, 44, 32, 3, (17, 24, 23, 190))
    image.rect(17, 15, 6, 28, (110, 101, 81, 255))
    image.rect(10, 40, 20, 4, (159, 146, 109, 255))
    image.rect(7, 4, 26, 28, (43, 51, 48, 255))
    image.rect(9, 6, 22, 24, (205, 201, 172, 255))
    image.rect(12, 9, 16, 18, (159, 69, 78, 255))
    image.rect(15, 12, 10, 12, (239, 219, 170, 255))
    image.rect(18, 15, 4, 6, (76, 133, 118, 255))
    image.rect(2, 15, 5, 5, (159, 146, 109, 255))
    image.rect(33, 15, 5, 5, (159, 146, 109, 255))
    return image


def warden() -> Raster:
    image = Raster(48, 52)
    image.rect(5, 47, 38, 4, (16, 24, 23, 190))
    image.rect(9, 13, 30, 30, (34, 51, 49, 255))
    image.rect(12, 17, 24, 23, (67, 130, 121, 255))
    image.rect(16, 4, 16, 18, (214, 187, 111, 255))
    image.rect(18, 7, 12, 12, (44, 52, 48, 255))
    image.rect(19, 10, 3, 3, (202, 238, 220, 255))
    image.rect(26, 10, 3, 3, (202, 238, 220, 255))
    image.rect(6, 13, 9, 9, (194, 178, 119, 255))
    image.rect(33, 13, 9, 9, (194, 178, 119, 255))
    image.rect(20, 23, 8, 12, (220, 204, 148, 255))
    image.rect(23, 25, 2, 7, (62, 120, 109, 255))
    image.rect(8, 40, 32, 5, (159, 64, 83, 255))
    image.rect(12, 44, 8, 4, (202, 188, 134, 255))
    image.rect(28, 44, 8, 4, (202, 188, 134, 255))
    image.rect(2, 24, 3, 22, (183, 201, 178, 255))
    image.rect(0, 22, 7, 4, (232, 219, 155, 255))
    return image


def icon(kind: str) -> Raster:
    image = Raster(16, 16)
    ink = (216, 235, 219, 255)
    if kind == "play":
        for y in range(3, 13):
            width = 6 - abs(y - 7)
            image.rect(5, y, max(1, width), 1, ink)
    elif kind == "pause":
        image.rect(4, 3, 3, 10, ink)
        image.rect(10, 3, 3, 10, ink)
    elif kind == "back":
        image.rect(4, 7, 10, 2, ink)
        for step in range(5):
            image.rect(2 + step, 7 - step, 2, 2, ink)
            image.rect(2 + step, 7 + step, 2, 2, ink)
    else:
        image.rect(5, 2, 7, 2, ink)
        image.rect(12, 4, 2, 7, ink)
        image.rect(5, 12, 7, 2, ink)
        image.rect(2, 6, 2, 5, ink)
        image.rect(1, 2, 2, 6, ink)
        image.rect(1, 6, 6, 2, ink)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    images = [("training_floor", floor()), ("training_target", target()), ("training_warden", warden())]
    images.extend((name, icon(name)) for name in ("play", "pause", "reset", "back"))
    assets = []
    for name, image in images:
        data = image.png()
        (OUTPUT / f"{name}.png").write_bytes(data)
        assets.append({"path": f"{name}.png", "sha256": hashlib.sha256(data).hexdigest(), "width": image.width, "height": image.height})
    (OUTPUT / "generated_assets.json").write_text(json.dumps({"schema_version": 1, "generator": "tools/generate_training_assets.py", "provenance": "Original project-authored deterministic pixel artwork; no third-party sources.", "license": "CC0-1.0", "assets": assets}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
