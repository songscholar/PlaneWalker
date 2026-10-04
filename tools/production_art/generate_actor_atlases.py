#!/usr/bin/env python3
"""Author and verify original deterministic pixel animation atlases."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "production" / "actors"
STATES = ("idle", "move", "attack", "cast", "hurt", "death")
CHARACTERS = ("wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord")
BOSSES = ("ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne")
OUTLINE = (19, 22, 29, 255)
INK = (37, 43, 52, 255)
IVORY = (232, 236, 222, 255)
GOLD = (225, 183, 77, 255)
PALETTES = {
    "wanderer": ((63, 159, 174, 255), (33, 77, 94, 255), (136, 233, 218, 255)),
    "time_guardian": ((91, 135, 183, 255), (38, 63, 99, 255), GOLD),
    "void_walker": ((171, 74, 144, 255), (71, 37, 83, 255), (229, 137, 192, 255)),
    "primordial_knight": ((147, 154, 156, 255), (64, 73, 83, 255), (241, 133, 70, 255)),
    "time_lord": ((142, 119, 188, 255), (51, 52, 86, 255), (133, 216, 205, 255)),
    "ruin_king": ((137, 153, 146, 255), (63, 79, 81, 255), GOLD),
    "forest_heart": ((100, 139, 78, 255), (56, 72, 51, 255), (175, 224, 112, 255)),
    "time_sovereign": ((207, 182, 108, 255), (99, 92, 77, 255), (128, 224, 216, 255)),
    "forge_colossus": ((153, 112, 103, 255), (65, 56, 62, 255), (248, 155, 63, 255)),
    "void_throne": ((122, 82, 139, 255), (53, 34, 67, 255), (229, 107, 155, 255)),
}
LICENSE = """Plane Walker Original Actor Atlas Artwork

These ten actor animation atlases, their generated contact sheet and the
original raster source were created locally for the Plane Walker project.
No downloaded artwork, copyrighted character references, external stock assets
or remote image services are used.

The original raster artwork in this directory is dedicated to the public domain
under CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/
This dedication applies to the artwork only; it does not relicense game code,
project names, third-party dependencies or other assets.

Source: tools/production_art/generate_actor_atlases.py
Reproduction: python3 tools/production_art/generate_actor_atlases.py
"""


class Canvas:
    def __init__(self, size: int):
        self.image = Image.new("RGBA", (size, size))
        self.draw = ImageDraw.Draw(self.image)

    def box(self, x: int, y: int, w: int, h: int, color: tuple, edge: bool = False):
        if edge:
            self.draw.rectangle((x - 1, y - 1, x + w, y + h), fill=OUTLINE)
        self.draw.rectangle((x, y, x + w - 1, y + h - 1), fill=color)

    def poly(self, points: list[tuple[int, int]], color: tuple, edge: bool = True):
        self.draw.polygon(points, fill=color)
        if edge:
            self.draw.line(points + [points[0]], fill=OUTLINE, width=1)

    def line(self, points: list[tuple[int, int]], color: tuple, width: int = 2):
        self.draw.line(points, fill=OUTLINE, width=width + 2)
        self.draw.line(points, fill=color, width=width)

    def diamond(self, x: int, y: int, radius: int, color: tuple):
        self.poly([(x, y - radius), (x + radius, y), (x, y + radius), (x - radius, y)], color)


def character(actor: str, state: str, frame: int) -> Image.Image:
    c = Canvas(48)
    primary, dark, accent = PALETTES[actor]
    bob = (0, -1, 0, 1)[frame]
    step = (-2, 0, 2, 0)[frame] if state == "move" else 0
    lean = (0, 1, 2, 1)[frame] if state == "attack" else (-1, -2, 0, 1)[frame] if state == "hurt" else 0
    x, y = 22 + lean, 21 + bob
    c.poly([(x - 8, y - 8), (x + 7, y - 8), (x + 11, y + 16), (x - 11, y + 15)], dark)
    c.box(x - 5 - step, y + 13, 5, 6, INK, True)
    c.box(x + 2 + step, y + 13, 5, 6, INK, True)
    c.box(x - 4 - step, y + 13, 3, 2, accent)
    c.box(x + 3 + step, y + 13, 3, 2, accent)
    c.box(x - 6, y - 2, 13, 13, primary, True)
    c.box(x - 4, y + 8, 10, 3, INK)
    c.box(x, y + 9, 3, 2, GOLD)
    c.box(x - 8, y + 1, 4, 8, dark, True)
    c.box(x + 7, y + 1, 4, 8, primary, True)
    if actor == "wanderer":
        c.poly([(x - 7, y - 8), (x - 3, y - 13), (x + 5, y - 12), (x + 8, y - 4), (x - 7, y - 3)], primary)
        c.box(x - 3, y - 8, 8, 5, INK)
        c.box(x - 1, y - 7, 6, 1 if frame == 3 and state == "idle" else 2, IVORY)
        c.line([(x - 5, y + 1), (x + 6, y + 7)], accent, 2)
        c.poly([(x - 6, y), (x - 15, y + 5), (x - 12 - frame, y + 10)], accent)
    elif actor == "time_guardian":
        c.box(x - 6, y - 11, 13, 9, primary, True)
        c.box(x - 7, y - 7, 15, 3, INK)
        c.box(x - 4, y - 6, 9, 1, accent)
        c.box(x - 1, y - 14, 3, 5, GOLD, True)
        c.box(x - 8, y - 1, 17, 3, GOLD, True)
        c.poly([(x - 16, y + 2), (x - 7, y), (x - 6, y + 13), (x - 11, y + 18), (x - 17, y + 12)], primary)
        c.box(x - 13, y + 4, 3, 10, GOLD)
        c.box(x - 16, y + 7, 9, 2, GOLD)
    elif actor == "void_walker":
        c.poly([(x - 7, y - 9), (x, y - 15), (x + 8, y - 8), (x + 6, y - 2), (x - 6, y - 2)], primary)
        c.box(x - 4, y - 8, 9, 5, OUTLINE)
        c.box(x - 2, y - 6, 6, 1, accent)
        c.poly([(x - 8, y + 4), (x - 12, y + 19), (x - 4, y + 16), (x, y + 20), (x + 5, y + 16), (x + 10, y + 19), (x + 8, y + 3)], primary)
        c.line([(x - 6, y + 6), (x - 14, y + 9 + frame), (x - 16, y + 3)], accent, 2)
        c.line([(x + 6, y + 6), (x + 15, y + 10 - frame), (x + 18, y + 3)], accent, 2)
        c.diamond(x + 15, y - 4, 3, accent)
    elif actor == "primordial_knight":
        c.box(x - 6, y - 11, 13, 9, primary, True)
        c.box(x - 5, y - 5, 11, 2, OUTLINE)
        c.box(x - 1, y - 5, 6, 1, accent)
        for sx in (-10, 7):
            c.box(x + sx, y - 2, 6, 6, primary, True)
            c.poly([(x + sx, y - 2), (x + sx + 2, y - 7), (x + sx + 5, y - 2)], accent)
        c.box(x - 2, y, 5, 7, INK)
        c.diamond(x, y + 3, 2, accent)
    else:
        c.poly([(x - 8, y - 10), (x + 8, y - 10), (x + 5, y - 3), (x - 5, y - 3)], primary)
        c.poly([(x - 6, y - 10), (x - 4, y - 15), (x + 2, y - 13), (x + 5, y - 15), (x + 7, y - 10)], GOLD)
        c.box(x - 4, y - 7, 9, 3, INK)
        c.box(x + 1, y - 6, 4, 1, accent)
        c.poly([(x - 8, y + 3), (x - 13, y + 18), (x - 3, y + 15), (x + 2, y + 18), (x + 11, y + 16), (x + 8, y + 2)], primary)
        c.line([(x - 5, y + 1), (x - 1, y + 13)], GOLD, 1)
        c.line([(x + 5, y + 1), (x + 2, y + 13)], GOLD, 1)
        c.box(x + 11, y + 3, 9, 9, dark, True)
        c.box(x + 12, y + 4, 7, 6, IVORY)
        c.box(x + 15, y + 3, 1, 8, GOLD)
    _effects(c, state, frame, accent, 48)
    return _death(c.image, frame) if state == "death" else c.image


def boss(actor: str, state: str, frame: int) -> Image.Image:
    c = Canvas(80)
    primary, dark, accent = PALETTES[actor]
    x, y = 39 + ((0, 1, 2, 1)[frame] if state == "attack" else 0), 38 + (0, -1, 0, 1)[frame]
    stride = (-2, 0, 2, 0)[frame] if state == "move" else 0
    if actor == "ruin_king":
        c.poly([(x - 18, y - 15), (x + 16, y - 15), (x + 23, y + 28), (x - 25, y + 28)], dark)
        c.box(x - 12, y - 17, 25, 35, primary, True)
        for offset in (-10, 2):
            c.box(x + offset + stride, y + 17, 10, 13, dark, True)
            c.box(x + offset + stride, y + 26, 10, 3, primary)
        c.poly([(x - 11, y - 18), (x - 13, y - 27), (x - 5, y - 22), (x, y - 30), (x + 5, y - 22), (x + 13, y - 27), (x + 11, y - 18)], GOLD)
        c.box(x - 9, y - 13, 18, 9, INK)
        c.box(x - 7, y - 10, 5, 2, accent)
        c.box(x + 3, y - 10, 5, 2, accent)
        c.box(x - 4, y - 1, 9, 14, dark)
        c.diamond(x, y + 5, 4, GOLD)
        c.poly([(x - 30, y - 8), (x - 13, y - 12), (x - 13, y + 15), (x - 23, y + 26), (x - 32, y + 12)], primary)
        c.poly([(x - 27, y - 5), (x - 17, y - 7), (x - 17, y + 13), (x - 23, y + 20), (x - 28, y + 10)], dark)
        c.line([(x - 23, y - 3), (x - 23, y + 15)], GOLD, 2)
        c.box(x + 23, y - 13, 3, 39, GOLD, True)
        c.box(x + 18, y - 17, 13, 13, primary, True)
        c.box(x + 20, y - 15, 9, 3, IVORY)
    elif actor == "forest_heart":
        for direction in (-1, 1):
            c.line([(x + direction * 11, y + 14), (x + direction * 24, y + 25), (x + direction * (31 + stride), y + 26)], dark, 5)
            c.line([(x + direction * 9, y - 10), (x + direction * 22, y - 19), (x + direction * 31, y - 11)], primary, 5)
            c.poly([(x + direction * 12, y - 16), (x + direction * 21, y - 28), (x + direction * 30, y - 23), (x + direction * 28, y - 12)], primary)
        c.poly([(x - 12, y - 21), (x + 11, y - 22), (x + 20, y + 22), (x + 8, y + 31), (x - 18, y + 27), (x - 17, y + 4)], dark)
        for offset in (-11, -3, 7):
            c.line([(x + offset, y - 14), (x + offset - 2, y + 12), (x + offset + 2, y + 24)], primary, 3)
        c.poly([(x - 9, y - 9), (x - 2, y - 16), (x + 8, y - 11), (x + 11, y + 2), (x + 1, y + 13), (x - 10, y + 4)], accent)
        c.diamond(x, y, 5, IVORY)
        c.box(x - 2, y - 3, 4, 6, dark)
        for dx, dy in ((-23, -19), (20, -17), (-15, 14), (13, 18)):
            c.diamond(x + dx, y + dy, 4, accent)
    elif actor == "time_sovereign":
        c.poly([(x - 18, y - 15), (x - 25, y + 25), (x - 8, y + 19), (x, y + 30), (x + 12, y + 21), (x + 26, y + 26), (x + 17, y - 15)], dark)
        for dx in (-20, 20):
            c.box(x + dx - 5, y - 7, 10, 28, primary, True)
            c.box(x + dx - 3, y - 5, 6, 3, IVORY)
        c.draw.ellipse((x - 19, y - 25, x + 19, y + 13), fill=OUTLINE)
        c.draw.ellipse((x - 17, y - 23, x + 17, y + 11), fill=primary)
        c.draw.ellipse((x - 13, y - 19, x + 13, y + 7), fill=dark)
        for angle in range(0, 360, 45):
            px = x + round(math.cos(math.radians(angle)) * 15)
            py = y - 6 + round(math.sin(math.radians(angle)) * 15)
            c.box(px - 1, py - 1, 3, 3, GOLD)
        c.line([(x, y - 6), (x + (3, 9, 3, -8)[frame], y - 6 + (-10, -4, 8, 3)[frame])], accent, 2)
        c.line([(x, y - 6), (x - 7, y - 12)], IVORY, 2)
        c.diamond(x, y - 6, 3, GOLD)
        c.poly([(x - 11, y - 26), (x - 10, y - 31), (x - 3, y - 27), (x, y - 33), (x + 5, y - 27), (x + 12, y - 31), (x + 11, y - 26)], accent)
        c.diamond(x, y + 20, 7, accent)
    elif actor == "forge_colossus":
        c.box(x - 16, y - 17, 33, 34, primary, True)
        for direction in (-1, 1):
            c.box(x + direction * 22 - 6, y - 14, 13, 28, dark, True)
            c.box(x + direction * 22 - 7, y - 18, 15, 7, primary, True)
            c.box(x + direction * 10 - 5 + stride, y + 18, 11, 14, dark, True)
            c.box(x + direction * 10 - 6 + stride, y + 28, 13, 4, primary, True)
        c.box(x - 9, y - 27, 19, 13, dark, True)
        c.box(x - 7, y - 23, 15, 3, accent)
        c.box(x - 8, y - 9, 17, 19, INK, True)
        c.box(x - 6, y - 7, 13, 15, accent)
        for dx in (-4, 1, 5):
            c.box(x + dx, y - 6, 2, 13, dark)
        for dx in (-12, 9):
            c.box(x + dx, y - 13, 3, 3, GOLD)
            c.box(x + dx, y + 12, 3, 3, GOLD)
        c.box(x - 15, y - 29, 4, 14, dark, True)
        c.box(x + 12, y - 30, 4, 15, dark, True)
        c.box(x + 25, y + 4, 3, 25, GOLD, True)
        c.box(x + 20, y - 2, 13, 10, primary, True)
    else:
        for direction in (-1, 1):
            c.poly([(x + direction * 8, y - 14), (x + direction * 19, y - 27), (x + direction * 32, y - 23), (x + direction * 25, y - 11), (x + direction * 31, y), (x + direction * 13, y - 1)], dark)
            c.line([(x + direction * 13, y - 12), (x + direction * 25, y - 20)], primary, 3)
            c.line([(x + direction * 10, y + 7), (x + direction * (24 + stride), y + 24), (x + direction * 32, y + 17)], primary, 4)
            c.line([(x + direction * 5, y + 13), (x + direction * 12, y + 29), (x + direction * 20, y + 26)], accent, 3)
        c.poly([(x - 12, y - 22), (x + 11, y - 22), (x + 19, y - 7), (x + 14, y + 13), (x, y + 27), (x - 16, y + 11), (x - 18, y - 7)], primary)
        c.poly([(x - 11, y - 4), (x, y - 13), (x + 12, y - 4), (x, y + 5)], IVORY)
        c.diamond(x + (frame % 2), y - 4, 4, accent)
        c.box(x, y - 7, 2, 7, OUTLINE)
        c.poly([(x - 11, y - 22), (x - 10, y - 31), (x - 4, y - 27), (x, y - 33), (x + 5, y - 27), (x + 12, y - 31), (x + 11, y - 22)], accent)
        c.line([(x - 8, y + 10), (x, y + 16), (x + 8, y + 9)], dark, 2)
    _effects(c, state, frame, accent, 80)
    return _death(c.image, frame) if state == "death" else c.image


def _effects(c: Canvas, state: str, frame: int, accent: tuple, size: int):
    if state == "attack" and size == 80:
        extent = 12 if size == 48 else 21
        cx, cy = size // 2, size // 2
        c.line([(cx + 3, cy - extent + frame * 3), (size - 5, cy - extent // 2 + frame * 4), (size - 7, cy + extent - frame)], IVORY, 2)
        c.diamond(size - 8, cy + frame * 3 - 5, 2, accent)
    elif state == "cast":
        radius = size // 2 - 5
        for index in range(3):
            angle = math.radians(index * 120 + frame * 24)
            c.diamond(size // 2 + round(math.cos(angle) * radius), size // 2 + round(math.sin(angle) * radius), 2, accent)
    elif state == "hurt":
        for dx, dy in ((-4, -6), (6, -3), (2, 5)):
            c.line([(size // 2 + dx, size // 2 + dy), (size // 2 + dx + frame + 2, size // 2 + dy - 3)], IVORY, 1)


def _death(image: Image.Image, frame: int) -> Image.Image:
    size = image.width
    height = (size - 6, size * 3 // 4, size // 2, size // 3)[frame]
    compressed = image.resize((size, height), Image.Resampling.NEAREST)
    result = Image.new("RGBA", image.size)
    result.alpha_composite(compressed, (0, size - height - 2))
    return result


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(output: Path = OUTPUT) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    previews = []
    for actor in sorted(CHARACTERS + BOSSES):
        kind = "character" if actor in CHARACTERS else "boss"
        size = 48 if kind == "character" else 80
        atlas = Image.new("RGBA", (size * 4, size * len(STATES)))
        for row, state in enumerate(STATES):
            for frame in range(4):
                image = character(actor, state, frame) if kind == "character" else boss(actor, state, frame)
                atlas.alpha_composite(image, (frame * size, row * size))
                if row == 0 and frame == 0:
                    previews.append((actor, image))
        path = output / (actor + ".png")
        atlas.save(path, optimize=False, compress_level=9)
        assets.append({"id": actor, "kind": kind, "path": path.name, "sha256": _sha(path), "width": atlas.width, "height": atlas.height, "frame_width": size, "frame_height": size, "columns": 4, "rows": 6, "frames_per_state": 4, "fps": {"idle": 5, "move": 8, "attack": 12, "cast": 10, "hurt": 12, "death": 8}, "facing": "right", "filter": "nearest"})
    sheet = Image.new("RGBA", (960, 448), (31, 35, 42, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (actor, preview) in enumerate(previews):
        x, y = index % 5 * 192, index // 5 * 224
        scale = 3 if preview.width == 48 else 2
        enlarged = preview.resize((preview.width * scale, preview.height * scale), Image.Resampling.NEAREST)
        sheet.alpha_composite(enlarged, (x + (192 - enlarged.width) // 2, y + 12))
        draw.text((x + 8, y + 188), actor.replace("_", " "), fill=IVORY)
        draw.text((x + 8, y + 206), "6 actions / 24 frames", fill=(150, 162, 172, 255))
    sheet.save(output / "contact_sheet.png", optimize=False, compress_level=9)
    (output / "LICENSE.txt").write_text(LICENSE, encoding="ascii")
    manifest = {"schema_id": "plane_walker_actor_atlas_v1", "schema_version": 1, "states": list(STATES), "provenance": {"kind": "original_project_art", "license": "CC0-1.0", "license_path": "LICENSE.txt", "generator": "tools/production_art/generate_actor_atlases.py", "third_party_art": False}, "assets": assets, "auxiliary_files": [{"path": name, "sha256": _sha(output / name)} for name in ("LICENSE.txt", "contact_sheet.png")]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="ascii")
    return manifest


def validate(output: Path = OUTPUT) -> dict:
    errors = []
    try:
        manifest = json.loads((output / "manifest.json").read_text(encoding="ascii"))
        if manifest["schema_id"] != "plane_walker_actor_atlas_v1" or manifest["schema_version"] != 1 or manifest["states"] != list(STATES) or manifest["provenance"]["kind"] != "original_project_art" or manifest["provenance"]["license"] != "CC0-1.0" or manifest["provenance"]["third_party_art"] is not False:
            raise ValueError("manifest contract")
        if [row["id"] for row in manifest["assets"]] != sorted(CHARACTERS + BOSSES):
            raise ValueError("actor identities")
        declared = {"manifest.json"}
        silhouettes = set()
        for row in manifest["assets"] + manifest["auxiliary_files"]:
            name = row["path"]
            if not isinstance(name, str) or Path(name).name != name or name in declared:
                raise ValueError("unsafe or duplicate asset path")
            declared.add(name)
            path = output / name
            if path.is_symlink() or not path.is_file() or _sha(path) != row["sha256"]:
                errors.append(name + ": missing or SHA-256 mismatch")
                continue
            if "id" not in row:
                continue
            size = 48 if row["id"] in CHARACTERS else 80
            if row["kind"] != ("character" if size == 48 else "boss") or row["frame_width"] != size or row["frame_height"] != size or row["width"] != size * 4 or row["height"] != size * 6 or row["columns"] != 4 or row["rows"] != 6 or row["frames_per_state"] != 4 or row["facing"] != "right" or row["filter"] != "nearest":
                errors.append(name + ": frame contract")
                continue
            with Image.open(path) as atlas:
                atlas.load()
                if atlas.size != (size * 4, size * 6) or atlas.mode != "RGBA":
                    errors.append(name + ": PNG format")
                    continue
                silhouettes.add(atlas.crop((0, 0, size, size)).getchannel("A").tobytes())
                for state in range(6):
                    frames = set()
                    for frame in range(4):
                        crop = atlas.crop((frame * size, state * size, (frame + 1) * size, (state + 1) * size))
                        alpha = crop.getchannel("A")
                        bounds = alpha.getbbox()
                        if not bounds or sum(value != 0 for value in alpha.get_flattened_data()) <= size * 2 or bounds[0] < 1 or bounds[1] < 1 or bounds[2] > size - 1 or bounds[3] > size - 1:
                            errors.append("%s: %s/%d blank or unpadded" % (name, STATES[state], frame))
                        frames.add(crop.tobytes())
                    if len(frames) < 3:
                        errors.append(name + ": insufficient " + STATES[state] + " animation")
        if len(silhouettes) != 10:
            errors.append("actor silhouettes are missing or duplicated")
        if {path.name for path in output.iterdir() if path.is_file() and not path.name.endswith(".import")} != declared:
            errors.append("undeclared or missing files")
    except (OSError, ValueError, KeyError, TypeError) as error:
        errors.append(str(error))
    return {"ok": not errors, "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="read-only validation of checked-in atlases")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    if not args.check:
        generate(args.output)
    result = validate(args.output)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
