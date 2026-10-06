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


def _portal_frame(kind: str, phase: int) -> Image.Image:
    """Render a readable portal with four deterministic charge stages."""
    image = Image.new("RGBA", (32, 32))
    draw = ImageDraw.Draw(image)
    color = PALETTES[kind]
    # The outer ring stays stable while the inner aperture and runes charge.
    draw.ellipse((2, 2, 29, 29), fill=INK)
    draw.ellipse((4, 4, 27, 27), outline=color, width=2)
    draw.arc((6, 6, 25, 25), 15 + phase * 20, 205 + phase * 20, fill=(221, 249, 255, 255), width=1)
    draw.arc((7, 7, 24, 24), 195 + phase * 20, 355 + phase * 20, fill=color, width=2)
    if kind == "portal_enemy":
        aperture = ((15, 9 + phase), (23, 16), (15, 23 - phase), (10, 16))
        draw.polygon(aperture, fill=color)
        draw.polygon(((15, 12 + phase), (20, 16), (15, 20 - phase), (13, 16)), fill=INK)
    else:
        draw.line(((10, 16), (22, 16)), fill=color, width=2)
        draw.polygon(((10, 12), (6, 16), (10, 20)), fill=color)
        draw.polygon(((22, 12), (26, 16), (22, 20)), fill=color)
        draw.rectangle((14, 13 + phase % 2, 17, 18 - phase % 2), fill=(221, 249, 255, 255))
    for x, y in ((15, 1), (29, 15), (15, 29), (1, 15)):
        if (phase + x + y) % 2 == 0:
            draw.rectangle((x, y, x + 1, y + 1), fill=color)
    return image


def _wall_frame(kind: str, phase: int) -> Image.Image:
    """Render irregular wall/link silhouettes instead of repeated zigzags."""
    image = Image.new("RGBA", (64, 16))
    draw = ImageDraw.Draw(image)
    color = PALETTES[kind]
    if kind == "web_link":
        anchors = [(0, 10), (9, 6 + phase % 2), (20, 11), (32, 5), (44, 9 + (phase + 1) % 2), (55, 4), (63, 8)]
        lower = [(0, 5), (12, 12), (25, 6), (38, 13), (50, 7), (63, 12)]
        draw.line(anchors, fill=INK, width=5)
        draw.line(anchors, fill=color, width=2)
        draw.line(lower, fill=INK, width=2)
        draw.line(lower, fill=(233, 221, 244, 255), width=1)
        for x, y in anchors[1:-1]:
            draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill=INK)
            draw.point((x, y), fill=(233, 221, 244, 255))
        glint_x = (5, 19, 37, 53)[phase]
        draw.rectangle((glint_x, 1 + phase % 3, glint_x + 1, 2 + phase % 3), fill=color)
        return image

    # Bramble and web walls share a grounded spine but use different motifs.
    if kind == "bramble_wall":
        spine = [(0, 9), (7, 7), (14, 10), (22, 6 + phase % 2), (31, 9), (40, 5), (49, 10), (57, 7), (63, 9)]
        draw.line(spine, fill=INK, width=7)
        draw.line(spine, fill=color, width=3)
        thorn_rows = [(5, 4, 2), (16, 12, -2), (28, 3, 2), (39, 13, -2), (52, 3, 2), (60, 12, -2)]
        for x, tip, direction in thorn_rows:
            draw.line(((x, 8), (x + direction * 2, tip)), fill=INK, width=3)
            draw.point((x + direction * 2, tip), fill=color)
    else:
        spine = [(0, 8), (8, 6), (16, 9), (25, 5 + phase % 2), (34, 10), (43, 6), (53, 9), (63, 7)]
        draw.line(spine, fill=INK, width=7)
        draw.line(spine, fill=color, width=2)
        for points in (
            [(3, 4), (8, 8), (13, 4)],
            [(19, 12), (25, 7), (31, 12)],
            [(37, 4), (43, 8), (49, 4)],
            [(52, 12), (57, 8), (62, 11)],
        ):
            draw.line(points, fill=INK, width=2)
            draw.line(points, fill=(222, 199, 238, 255), width=1)
    glint_x = (5, 19, 37, 53)[phase]
    draw.rectangle((glint_x, 1 + phase % 3, glint_x + 1, 2 + phase % 3), fill=color)
    return image


def frame(kind: str, phase: int) -> Image.Image:
    portal = kind.startswith("portal_")
    if portal:
        return _portal_frame(kind, phase)
    return _wall_frame(kind, phase)


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
