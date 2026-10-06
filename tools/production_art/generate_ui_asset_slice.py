#!/usr/bin/env python3
"""Generate the first deterministic Plane Walker UI/gameplay art slice.

The source is intentionally small and offline.  It produces pixel-aligned
weapon, time-ability and player-effect atlases, then records those assets and
the already certified actor/enemy/room batches in one inventory manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "production" / "ui"
FRAME_SIZE = 32
FRAME_COUNT = 4
PALETTE = {
    "ink": (17, 22, 25, 255),
    "stone": (36, 45, 45, 255),
    "edge": (105, 119, 113, 255),
    "bone": (237, 240, 220, 255),
    "muted": (171, 184, 172, 255),
    "patina": (121, 186, 161, 255),
    "time": (97, 213, 231, 255),
    "brass": (229, 189, 105, 255),
    "danger": (240, 112, 101, 255),
    "ember": (223, 155, 101, 255),
    "void": (184, 151, 215, 255),
}

WEAPONS = ("sword", "bow", "gun", "staff", "gauntlets")
ABILITIES = ("stop", "rewind", "accelerate", "rift")
EFFECTS = ("weapon_arc", "arrow_trail", "muzzle_flash", "spell_burst", "time_ring", "rift_bloom")
CONTENT_SOURCES = {
    "items": ROOT / "data" / "content_packs" / "base" / "content" / "items.json",
    "blessings": ROOT / "data" / "content_packs" / "base" / "content" / "blessings.json",
    "curses": ROOT / "data" / "content_packs" / "base" / "content" / "curses.json",
    "talents": ROOT / "data" / "content_packs" / "base" / "content" / "talents.json",
}
MODE_ART = ("boss_rush", "daily_boss", "authored_challenges", "training", "endless")
UI_FRAMES = ("panel", "panel_active", "panel_danger", "divider", "badge", "cursor")

LICENSE = """Plane Walker Original UI Art Slice

The weapon, time-ability and player-effect raster atlases in this directory are
generated locally from deterministic pixel geometry.  No downloaded artwork,
remote image generation, or third-party image is used.

The artwork is dedicated to the public domain under CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/
The dedication applies to artwork only; it does not relicense game code,
project names, fonts, or third-party dependencies.

Source: tools/production_art/generate_ui_asset_slice.py
Reproduction: python3 tools/production_art/generate_ui_asset_slice.py
"""


def _rgba(value: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    return value


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def _outline(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], fill: tuple[int, int, int, int]) -> None:
    draw.polygon(points, fill=PALETTE["ink"])
    inset = [(x + (1 if x < 16 else -1), y + (1 if y < 16 else -1)) for x, y in points]
    draw.polygon(inset, fill=fill)


def weapon_frame(weapon: str, frame: int) -> Image.Image:
    image, draw = _canvas()
    ink, stone, bone = PALETTE["ink"], PALETTE["stone"], PALETTE["bone"]
    patina, brass, ember = PALETTE["patina"], PALETTE["brass"], PALETTE["ember"]
    pulse = (0, 1, 0, -1)[frame]
    if weapon == "sword":
        _outline(draw, [(5, 25), (9, 21), (22, 8), (26, 10), (13, 24), (10, 28)], bone)
        draw.line([(8, 24), (23, 9)], fill=brass, width=2)
        draw.rectangle((4, 24, 12, 27), fill=patina)
        draw.rectangle((7, 27, 10, 30), fill=brass)
        draw.rectangle((12 + pulse, 6, 16 + pulse, 10), fill=PALETTE["time"])
    elif weapon == "bow":
        draw.arc((5, 3, 25, 29), 72, 288, fill=ink, width=4)
        draw.arc((7, 5, 23, 27), 72, 288, fill=brass, width=2)
        draw.line([(10, 5), (10 + pulse, 27)], fill=bone, width=1)
        draw.line([(10, 16), (26, 16)], fill=patina, width=2)
        draw.polygon([(29, 16), (24, 13), (24, 19)], fill=PALETTE["time"])
        draw.rectangle((7, 14, 10, 18), fill=ember)
    elif weapon == "gun":
        draw.rectangle((5, 9, 24, 19), fill=ink)
        draw.rectangle((7, 11, 23, 17), fill=stone)
        draw.rectangle((20, 12, 29, 15), fill=bone)
        draw.rectangle((10, 18, 16, 26), fill=ink)
        draw.rectangle((12, 19, 15, 24), fill=patina)
        draw.rectangle((7, 12 + pulse, 10, 14 + pulse), fill=brass)
        draw.rectangle((27, 12, 30, 14), fill=ember)
    elif weapon == "staff":
        draw.line([(8, 28), (16, 7)], fill=ink, width=5)
        draw.line([(8, 28), (16, 7)], fill=brass, width=2)
        draw.ellipse((10, 3 + pulse, 22, 15 + pulse), fill=ink)
        draw.ellipse((12, 5 + pulse, 20, 13 + pulse), fill=PALETTE["time"])
        draw.rectangle((14, 8 + pulse, 17, 11 + pulse), fill=bone)
    else:
        draw.rectangle((7, 11, 14, 23), fill=ink)
        draw.rectangle((18, 9, 25, 21), fill=ink)
        draw.rectangle((9, 12, 13, 20), fill=patina)
        draw.rectangle((19, 11, 23, 18), fill=brass)
        draw.line([(13, 17), (19, 15)], fill=bone, width=2)
        draw.rectangle((5, 8 + pulse, 10, 12 + pulse), fill=PALETTE["time"])
        draw.rectangle((22, 19 - pulse, 27, 23 - pulse), fill=ember)
    return image


def ability_frame(ability: str, frame: int) -> Image.Image:
    image, draw = _canvas()
    ink, stone, bone = PALETTE["ink"], PALETTE["stone"], PALETTE["bone"]
    time, brass, void = PALETTE["time"], PALETTE["brass"], PALETTE["void"]
    pulse = (0, 1, 0, -1)[frame]
    draw.rectangle((3, 3, 28, 28), fill=ink)
    draw.rectangle((5, 5, 26, 26), fill=stone)
    if ability == "stop":
        draw.ellipse((8, 8, 23, 23), outline=time, width=2)
        draw.rectangle((12, 11, 14, 20), fill=bone)
        draw.rectangle((18, 11, 20, 20), fill=bone)
        draw.rectangle((5, 14 + pulse, 8, 17 + pulse), fill=brass)
    elif ability == "rewind":
        draw.arc((8, 8, 24, 24), 35, 330, fill=time, width=3)
        draw.polygon([(7, 10), (14, 10), (10, 16)], fill=brass)
        draw.rectangle((14, 14, 18, 18), fill=bone)
        draw.rectangle((18, 18, 21, 21), fill=void)
    elif ability == "accelerate":
        draw.polygon([(7, 18), (15, 8), (14, 15), (24, 14), (15, 25), (16, 18)], fill=time)
        draw.line([(7, 24), (11, 20)], fill=bone, width=1)
        draw.line([(22, 9), (25, 6)], fill=brass, width=2)
    else:
        draw.polygon([(8, 8), (24, 8), (20, 14), (24, 23), (8, 23), (12, 16)], fill=void)
        draw.line([(8, 16), (24, 16)], fill=time, width=2)
        draw.rectangle((13, 13 + pulse, 18, 18 + pulse), fill=bone)
        draw.rectangle((5, 6, 9, 9), fill=brass)
    return image


def effect_frame(effect: str, frame: int) -> Image.Image:
    image, draw = _canvas()
    ink, bone = PALETTE["ink"], PALETTE["bone"]
    patina, time, brass = PALETTE["patina"], PALETTE["time"], PALETTE["brass"]
    pulse = (0, 1, 0, -1)[frame]
    if effect == "weapon_arc":
        draw.arc((4, 4, 28, 28), 205, 330, fill=ink, width=5)
        draw.arc((5, 5, 27, 27), 205, 330, fill=brass, width=2)
        draw.rectangle((9 + frame, 8, 12 + frame, 11), fill=bone)
    elif effect == "arrow_trail":
        draw.line([(4, 25), (17, 16), (28, 8)], fill=ink, width=5)
        draw.line([(5, 24), (17, 16), (27, 9)], fill=patina, width=2)
        draw.polygon([(28, 8), (22, 8), (26, 13)], fill=time)
    elif effect == "muzzle_flash":
        draw.polygon([(5, 16), (13, 12), (16, 4 + pulse), (19, 13), (28, 16), (19, 19), (16, 28 - pulse), (13, 20)], fill=ink)
        draw.polygon([(8, 16), (15, 14), (16, 8 + pulse), (18, 14), (25, 16), (18, 18), (16, 24 - pulse), (14, 18)], fill=brass)
        draw.rectangle((14, 14, 17, 18), fill=bone)
    elif effect == "spell_burst":
        draw.ellipse((7, 7, 25, 25), outline=ink, width=4)
        draw.ellipse((10, 10, 22, 22), outline=time, width=2)
        for x, y in ((6 + frame, 6), (24 - frame, 23), (23, 7 + frame)):
            draw.rectangle((x, y, x + 2, y + 2), fill=bone)
    elif effect == "time_ring":
        draw.ellipse((4, 4, 27, 27), outline=ink, width=4)
        draw.arc((6, 6, 25, 25), 35 + frame * 15, 160 + frame * 15, fill=time, width=2)
        draw.line([(16, 16), (16 + pulse * 4, 8)], fill=bone, width=2)
        draw.rectangle((14, 14, 18, 18), fill=brass)
    else:
        draw.polygon([(3, 18), (12, 12), (18, 3), (20, 13), (29, 18), (20, 21), (14, 29), (12, 21)], fill=ink)
        draw.polygon([(7, 18), (13, 14), (17, 7), (18, 15), (25, 18), (18, 20), (14, 25), (13, 20)], fill=PALETTE["void"])
        draw.rectangle((14, 15, 18, 20), fill=time)
    return image


def _content_colors(category: str) -> tuple[tuple[int, int, int, int], tuple[int, int, int, int], tuple[int, int, int, int]]:
    if category == "items":
        return PALETTE["patina"], PALETTE["time"], PALETTE["bone"]
    if category == "blessings":
        return PALETTE["brass"], PALETTE["bone"], PALETTE["patina"]
    if category == "curses":
        return PALETTE["danger"], PALETTE["ember"], PALETTE["void"]
    if category == "talents":
        return PALETTE["void"], PALETTE["time"], PALETTE["bone"]
    if category == "mode_art":
        return PALETTE["brass"], PALETTE["time"], PALETTE["bone"]
    return PALETTE["stone"], PALETTE["patina"], PALETTE["bone"]


def content_frame(category: str, asset_id: str, frame: int) -> Image.Image:
    """Render a stable semantic glyph; the id hash chooses a distinct silhouette."""
    import hashlib as _hashlib

    image, draw = _canvas()
    primary, accent, highlight = _content_colors(category)
    digest = _hashlib.sha256(asset_id.encode("utf-8")).digest()
    shape = digest[0] % 5
    wobble = (0, 1, 0, -1)[frame]
    draw.rectangle((3, 3, 28, 28), fill=PALETTE["ink"])
    draw.rectangle((5, 5, 26, 26), fill=PALETTE["stone"])
    if shape == 0:
        draw.polygon([(16, 7 + wobble), (24, 15), (16, 25 - wobble), (8, 15)], fill=primary)
        draw.polygon([(16, 10 + wobble), (20, 15), (16, 21 - wobble), (12, 15)], fill=accent)
    elif shape == 1:
        draw.ellipse((8, 8, 24, 24), fill=primary)
        draw.rectangle((13, 12 + wobble, 19, 20 + wobble), fill=accent)
        draw.rectangle((15, 14 + wobble, 17, 18 + wobble), fill=highlight)
    elif shape == 2:
        draw.rectangle((8, 10, 24, 22), fill=primary)
        for x in (11, 15, 19):
            draw.rectangle((x, 12 + wobble, x + 1, 20 + wobble), fill=accent)
        draw.rectangle((12, 9, 20, 11), fill=highlight)
    elif shape == 3:
        draw.polygon([(7, 12), (11, 8), (14, 11), (18, 7), (21, 11), (25, 9), (24, 22), (8, 22)], fill=primary)
        draw.rectangle((12, 14 + wobble, 20, 18 + wobble), fill=accent)
    else:
        draw.arc((7, 7, 25, 25), 20 + frame * 12, 320 + frame * 12, fill=primary, width=3)
        draw.rectangle((13, 13 + wobble, 19, 19 + wobble), fill=accent)
    draw.rectangle((6, 6, 8, 8), fill=highlight)
    return image


def ui_frame(asset_id: str, frame: int) -> Image.Image:
    image, draw = _canvas()
    ink, stone, edge = PALETTE["ink"], PALETTE["stone"], PALETTE["edge"]
    time, brass = PALETTE["time"], PALETTE["brass"]
    if asset_id == "divider":
        draw.rectangle((4, 14, 27, 17), fill=ink)
        draw.rectangle((6, 15, 25, 16), fill=time)
        draw.rectangle((8 + frame, 12, 10 + frame, 19), fill=brass)
    elif asset_id == "badge":
        draw.polygon([(7, 7), (25, 7), (23, 24), (16, 28), (9, 24)], fill=ink)
        draw.polygon([(9, 9), (23, 9), (21, 22), (16, 25), (11, 22)], fill=brass)
        draw.rectangle((14, 13, 18, 19), fill=time)
    elif asset_id == "cursor":
        draw.polygon([(8, 5), (8, 27), (14, 21), (19, 27), (22, 24), (17, 18), (25, 18)], fill=ink)
        draw.polygon([(10, 8), (10, 22), (14, 18), (19, 24), (20, 23), (15, 17), (22, 17)], fill=time)
    else:
        draw.rectangle((4, 4, 27, 27), fill=ink)
        draw.rectangle((6, 6, 25, 25), fill=stone)
        border = time if asset_id == "panel_active" else PALETTE["danger"] if asset_id == "panel_danger" else edge
        draw.rectangle((7, 7, 24, 24), outline=border, width=2)
        draw.rectangle((10, 10, 21, 11), fill=brass if frame % 2 == 0 else border)
    return image


def _atlas(frames: Iterable[Image.Image]) -> Image.Image:
    atlas = Image.new("RGBA", (FRAME_SIZE * FRAME_COUNT, FRAME_SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (index * FRAME_SIZE, 0))
    return atlas


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_atlases(destination: Path, family: str, ids: tuple[str, ...], renderer) -> list[dict]:
    family_dir = destination / family
    family_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for asset_id in ids:
        path = family_dir / f"{asset_id}.png"
        _atlas(renderer(asset_id, frame) for frame in range(FRAME_COUNT)).save(path)
        rows.append({
            "id": asset_id,
            "path": str(path.relative_to(destination)),
            "kind": family,
            "width": FRAME_SIZE * FRAME_COUNT,
            "height": FRAME_SIZE,
            "frame_width": FRAME_SIZE,
            "frame_height": FRAME_SIZE,
            "frame_count": FRAME_COUNT,
            "filter": "nearest",
            "sha256": _sha(path),
        })
    return rows


def _existing_inventory(root: Path, family: str, ids: tuple[str, ...], manifest_name: str, path_key: str = "path") -> list[dict]:
    manifest_path = root / family / manifest_name
    if not manifest_path.exists():
        return []
    source = json.loads(manifest_path.read_text())
    source_rows = source.get("assets", source.get("atlases", []))
    output: list[dict] = []
    for row in source_rows:
        asset_id = str(row.get("id", Path(str(row.get(path_key, ""))).stem))
        if ids and asset_id not in ids:
            continue
        relative = str(row[path_key])
        file_path = root / family / relative
        if not file_path.exists():
            continue
        output.append({
            "id": asset_id,
            "path": str(file_path.relative_to(root)),
            "kind": family,
            "source_manifest": str(manifest_path.relative_to(root)),
            "filter": row.get("filter", "nearest"),
            "sha256": _sha(file_path),
        })
    return output


def _content_ids() -> dict[str, tuple[str, ...]]:
    result: dict[str, tuple[str, ...]] = {}
    for category, path in CONTENT_SOURCES.items():
        source = json.loads(path.read_text())
        result[category] = tuple(str(row["id"]) for row in source if isinstance(row, dict) and str(row.get("id", "")))
    return result


def _contact_sheet(destination: Path, generated: list[dict], existing: list[dict]) -> None:
    rows = generated + existing
    thumb_w, thumb_h = 128, 72
    columns = 4
    sheet = Image.new("RGBA", (columns * thumb_w, ((len(rows) + columns - 1) // columns) * (thumb_h + 18)), (17, 22, 25, 255))
    draw = ImageDraw.Draw(sheet)
    for index, row in enumerate(rows):
        x = (index % columns) * thumb_w
        y = (index // columns) * (thumb_h + 18)
        source = destination / row["path"] if "source_manifest" not in row else ROOT / "assets" / "production" / row["path"]
        image = Image.open(source).convert("RGBA")
        image.thumbnail((thumb_w - 8, thumb_h - 8), Image.Resampling.NEAREST)
        sheet.alpha_composite(image, (x + (thumb_w - image.width) // 2, y + 2))
        draw.text((x + 4, y + thumb_h), row["id"][:19], fill=PALETTE["bone"])
    sheet.save(destination / "pixel_asset_contact_sheet.png")


def generate(destination: Path = OUTPUT) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    generated: list[dict] = []
    generated += _write_atlases(destination, "weapons", WEAPONS, weapon_frame)
    generated += _write_atlases(destination, "time_abilities", ABILITIES, ability_frame)
    generated += _write_atlases(destination, "player_effects", EFFECTS, effect_frame)
    content_ids = _content_ids()
    for category, ids in content_ids.items():
        generated += _write_atlases(destination, category, ids, lambda asset_id, frame, family=category: content_frame(family, asset_id, frame))
    generated += _write_atlases(destination, "mode_art", MODE_ART, lambda asset_id, frame: content_frame("mode_art", asset_id, frame))
    generated += _write_atlases(destination, "final_ui_frames", UI_FRAMES, ui_frame)

    production_root = ROOT / "assets" / "production"
    existing: list[dict] = []
    existing += _existing_inventory(production_root, "actors", tuple(), "manifest.json")
    existing += _existing_inventory(production_root, "enemies", tuple(row["id"] for row in json.loads((production_root / "enemies" / "manifest.json").read_text()).get("assets", [])[:5]), "manifest.json")
    existing += _existing_inventory(production_root, "rooms", tuple(), "manifest.json", "path")
    _contact_sheet(destination, generated, existing)

    inventory = {
        "schema_id": "plane_walker_pixel_asset_inventory_v1",
        "schema_version": 1,
        "generated_by": "tools/production_art/generate_ui_asset_slice.py",
        "nearest_filter": True,
        "palette": {key: "#%02x%02x%02x" % value[:3] for key, value in PALETTE.items()},
        "batches": [
            {"id": "actors", "status": "generated", "scope": "five players and five bosses", "assets": [row for row in existing if row["kind"] == "actors"]},
            {"id": "enemies", "status": "generated", "scope": "five basic enemies", "assets": [row for row in existing if row["kind"] == "enemies"]},
            {"id": "rooms", "status": "generated", "scope": "room tiles, walls, doors and landmarks", "assets": [row for row in existing if row["kind"] == "rooms"]},
            {"id": "weapons", "status": "generated", "scope": "five weapon icons", "assets": [row for row in generated if row["kind"] == "weapons"]},
            {"id": "time_abilities", "status": "generated", "scope": "four time ability icons", "assets": [row for row in generated if row["kind"] == "time_abilities"]},
            {"id": "player_effects", "status": "generated", "scope": "weapon and time projectile/effect strips", "assets": [row for row in generated if row["kind"] == "player_effects"]},
            {"id": "items", "status": "generated", "scope": "authoritative item icon atlas", "assets": [row for row in generated if row["kind"] == "items"]},
            {"id": "blessings", "status": "generated", "scope": "authoritative blessing icon atlas", "assets": [row for row in generated if row["kind"] == "blessings"]},
            {"id": "curses", "status": "generated", "scope": "authoritative curse icon atlas", "assets": [row for row in generated if row["kind"] == "curses"]},
            {"id": "talents", "status": "generated", "scope": "authoritative talent icon atlas", "assets": [row for row in generated if row["kind"] == "talents"]},
            {"id": "mode_art", "status": "generated", "scope": "mode entry icon atlas", "assets": [row for row in generated if row["kind"] == "mode_art"]},
            {"id": "final_ui_frames", "status": "generated", "scope": "panel, divider, badge and cursor frame atlas", "assets": [row for row in generated if row["kind"] == "final_ui_frames"]},
            {"id": "font", "status": "fallback", "scope": "Godot theme/system font remains the authoritative fallback", "assets": [], "fallback": "system_font"},
        ],
        "contact_sheet": "pixel_asset_contact_sheet.png",
        "uncompleted_batches": ["font"],
        "fallbacks": [{"batch": "font", "source": "Godot theme/system font", "reason": "No bundled font file is required for the current offline slice."}],
    }
    (destination / "pixel_asset_inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    (destination / "LICENSE.txt").write_text(LICENSE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    generate(parser.parse_args().output)
