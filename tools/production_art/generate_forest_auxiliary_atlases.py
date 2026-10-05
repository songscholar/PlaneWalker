#!/usr/bin/env python3
"""Reproduce original Plane Walker Forest auxiliary pixel art."""

from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/constructs"
INK = (24, 28, 35, 255)
GREEN = (88, 164, 105, 255)
LIGHT = (165, 226, 151, 255)
PINK = (224, 102, 168, 255)
GOLD = (239, 205, 102, 255)


def frame(kind: str, phase: int) -> Image.Image:
    image = Image.new("RGBA", (48, 32))
    draw = ImageDraw.Draw(image)
    if kind == "wall":
        for x in range(0, 48, 8):
            draw.rectangle((x, 10, x + 7, 21), fill=INK)
            draw.line(((x, 13), (x + 3, 11), (x + 7, 17)), fill=GREEN, width=3)
            draw.line(((x, 19), (x + 4, 16), (x + 7, 19)), fill=PINK, width=2)
            if phase:
                draw.rectangle((x + 1, 18, x + 5, 21), fill=INK)
        return image
    if phase == 2:
        draw.line(((13, 24), (22, 27), (34, 23)), fill=GREEN, width=3)
        draw.rectangle((20, 22, 26, 25), fill=INK)
        return image
    draw.line(((24, 20), (24, 29)), fill=INK, width=5)
    draw.line(((24, 20), (24, 28)), fill=GREEN, width=3)
    draw.polygon(((13, 24), (22, 21), (24, 26)), fill=LIGHT)
    draw.polygon(((25, 25), (30, 20), (35, 23)), fill=GREEN)
    if kind == "sac":
        draw.ellipse((14, 4, 33, 23), fill=INK)
        draw.ellipse((16, 6, 31, 21), fill=PINK if phase == 1 else GREEN)
        draw.line(((19, 7), (17, 15), (21, 19)), fill=LIGHT, width=2)
        draw.rectangle((24, 9, 28, 14), fill=GOLD if phase == 1 else PINK)
        draw.line(((14, 19), (24, 23), (33, 18)), fill=INK, width=2)
    else:
        for box in ((17, 3, 29, 15), (10, 11, 23, 21), (25, 11, 38, 21)):
            draw.ellipse(box, fill=INK)
            draw.ellipse(tuple(v + (1 if i < 2 else -1) for i, v in enumerate(box)), fill=PINK)
        draw.ellipse((19, 11, 29, 21), fill=GOLD)
        draw.rectangle((23, 13, 26, 16), fill=(255, 243, 184, 255))
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for kind in ("sac", "flower", "wall"):
        atlas = Image.new("RGBA", (144, 32))
        for phase in range(3):
            atlas.paste(frame(kind, phase), (phase * 48, 0))
        atlas.save(OUTPUT / f"forest_{kind}.png")
        path = OUTPUT / f"forest_{kind}.png"
        rows.append({"id": f"forest_{kind}", "path": path.name, "frame_size": [48, 32], "frames": ["intact", "marked_or_damaged", "spent_or_broken"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"schema_version": 1, "license": "CC0-1.0", "source": "tools/production_art/generate_forest_auxiliary_atlases.py", "atlases": rows}
    (OUTPUT / "forest_auxiliary_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
