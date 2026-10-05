#!/usr/bin/env python3
"""Generate the original free appearance catalog and its exact raster assets."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw

import generate_actor_atlases as actors


ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "data/content_packs/base"
OUTPUT = PACK / "assets/cosmetics"
ROUTES = ("default", "return", "victory")
PALETTES = {
    "return": {
        "wanderer": ((86, 174, 111, 255), (34, 78, 57, 255), (177, 236, 150, 255)),
        "time_guardian": ((174, 91, 108, 255), (86, 39, 61, 255), (246, 161, 144, 255)),
        "void_walker": ((73, 160, 165, 255), (29, 61, 84, 255), (139, 238, 219, 255)),
        "primordial_knight": ((102, 130, 178, 255), (44, 59, 92, 255), (158, 207, 242, 255)),
        "time_lord": ((187, 126, 74, 255), (82, 56, 37, 255), (246, 207, 135, 255)),
    },
    "victory": {
        "wanderer": ((195, 114, 74, 255), (89, 46, 36, 255), (251, 202, 91, 255)),
        "time_guardian": ((128, 169, 117, 255), (46, 80, 60, 255), (230, 244, 154, 255)),
        "void_walker": ((154, 161, 181, 255), (64, 70, 98, 255), (251, 194, 228, 255)),
        "primordial_knight": ((182, 103, 150, 255), (78, 43, 74, 255), (248, 208, 133, 255)),
        "time_lord": ((75, 163, 158, 255), (31, 72, 75, 255), (220, 234, 148, 255)),
    },
}
NAMES = {
    "wanderer": ("Wanderer", "浪人"),
    "time_guardian": ("Time Guardian", "时空守卫"),
    "void_walker": ("Void Walker", "虚空行者"),
    "primordial_knight": ("Primordial Knight", "始源骑士"),
    "time_lord": ("Time Lord", "时间领主"),
}
LICENSE = """Plane Walker Original Free Appearance Artwork

These fifteen raster animation atlases and their contact sheet are original
project artwork generated locally from the original Plane Walker actor source.
No third-party artwork or external image service is used.

The artwork is dedicated to the public domain under CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/

Source: tools/production_art/generate_cosmetic_atlases.py
Base source: tools/production_art/generate_actor_atlases.py
Reproduce: python3 tools/production_art/generate_cosmetic_atlases.py
"""


def png(image: Image.Image) -> bytes:
    stream = io.BytesIO()
    image.save(stream, format="PNG", optimize=False, compress_level=9)
    return stream.getvalue()


def expected() -> dict[Path, bytes]:
    files: dict[Path, bytes] = {OUTPUT / "LICENSE.txt": LICENSE.encode("ascii")}
    definitions = []
    descriptors = []
    translations = [["keys", "en", "zh_CN"]]
    sheet = Image.new("RGBA", (288, 5 * 80), (23, 28, 32, 255))
    draw = ImageDraw.Draw(sheet)
    for character_index, character in enumerate(actors.CHARACTERS):
        original = actors.PALETTES[character]
        for route_index, route in enumerate(ROUTES):
            actors.PALETTES[character] = original if route == "default" else PALETTES[route][character]
            atlas = Image.new("RGBA", (192, 288))
            for state_index, state in enumerate(actors.STATES):
                for frame in range(4):
                    atlas.alpha_composite(actors.character(character, state, frame), (frame * 48, state_index * 48))
            filename = f"{character}_{route}.png"
            data = png(atlas)
            files[OUTPUT / filename] = data
            digest = hashlib.sha256(data).hexdigest()
            identity = f"{character}.{route}"
            key = "COSMETIC_" + identity.replace(".", "_").upper()
            definitions.append({"category": "cosmetic_definition", "id": "cosmetic_" + identity.replace(".", "_"), "schema_version": 1,
                "name_key": key + "_NAME", "description_key": "COSMETIC_ROUTE_" + route.upper(),
                "availability": ["LAUNCH", "EXPANSION"], "tags": ["free", "appearance"], "compatibility": {}, "effects": {},
                "cosmetic_id": identity, "character_id": character, "unlock_route": route,
                "atlas_path": "res://data/content_packs/base/assets/cosmetics/" + filename, "atlas_sha256": digest})
            descriptors.append({"id": identity, "character_id": character, "path": filename, "sha256": digest,
                "width": 192, "height": 288, "frame_width": 48, "frame_height": 48, "columns": 4, "rows": 6, "filter": "nearest"})
            suffix = {"default": ("Original", "原初"), "return": ("Homecoming", "归途"), "victory": ("Triumph", "凯旋")}[route]
            translations.append([key + "_NAME", NAMES[character][0] + " · " + suffix[0], NAMES[character][1] + "·" + suffix[1]])
            tile = atlas.crop((0, 0, 48, 48))
            sheet.alpha_composite(tile, (route_index * 96 + 24, character_index * 80 + 6))
            draw.text((route_index * 96 + 4, character_index * 80 + 56), character[:12], fill=(236, 239, 231, 255))
            draw.text((route_index * 96 + 4, character_index * 80 + 67), route, fill=(162, 180, 181, 255))
        actors.PALETTES[character] = original
    files[OUTPUT / "contact_sheet.png"] = png(sheet)
    manifest = {"schema_id": "plane_walker_cosmetic_atlas_v1", "schema_version": 1, "states": list(actors.STATES),
        "provenance": {"kind": "original_project_art", "license": "CC0-1.0", "license_path": "LICENSE.txt",
            "generator": "tools/production_art/generate_cosmetic_atlases.py", "base_generator": "tools/production_art/generate_actor_atlases.py", "third_party_art": False},
        "assets": descriptors,
        "auxiliary_files": [{"path": name, "sha256": hashlib.sha256(files[OUTPUT / name]).hexdigest()} for name in ("LICENSE.txt", "contact_sheet.png")]}
    files[OUTPUT / "manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("ascii")
    files[PACK / "content/cosmetics.json"] = (json.dumps(definitions, indent=2, sort_keys=True) + "\n").encode("ascii")
    translations.extend([
        ["COSMETIC_ROUTE_DEFAULT", "Original appearance", "原初外观"],
        ["COSMETIC_ROUTE_RETURN", "Return from one expedition", "完成一次远征返回据点"],
        ["COSMETIC_ROUTE_VICTORY", "Win one expedition", "完成一次胜利远征"],
        ["UI_COSMETIC_COLLECTION", "Character appearances", "角色外观"],
        ["UI_COSMETIC_CLAIM", "Claim", "领取"], ["UI_COSMETIC_EQUIP", "Equip", "装备"],
        ["UI_COSMETIC_EQUIPPED", "Equipped", "已装备"],
        ["HUB_COSMETIC_EQUIPPED", "This appearance is equipped", "已装备此外观"],
        ["HUB_COSMETIC_CHARACTER_LOCKED", "Unlock this character first", "先解锁此角色"],
        ["HUB_COSMETIC_RETURN_REQUIRED", "Return from one expedition", "完成一次远征返回据点"],
        ["HUB_COSMETIC_VICTORY_REQUIRED", "Win one expedition", "完成一次胜利远征"],
    ])
    buffer = io.StringIO(newline="")
    csv.writer(buffer, lineterminator="\n").writerows(translations)
    localizations = buffer.getvalue().encode("utf-8")
    files[PACK / "localization/cosmetics.csv"] = localizations
    files[ROOT / "assets/production/localization/cosmetics.csv"] = localizations
    return files


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    files = expected()
    if args.check:
        wrong = [str(path.relative_to(ROOT)) for path, data in files.items() if not path.is_file() or path.read_bytes() != data]
        if wrong:
            raise SystemExit("Cosmetic outputs differ: " + ", ".join(wrong))
        print("Original cosmetic atlases, catalog, license and localization: PASS")
        return
    for path, data in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    pack_path = PACK / "pack.json"
    pack = json.loads(pack_path.read_text())
    pack["content_manifest"] = sorted(set(pack["content_manifest"]) | {"content/cosmetics.json"})
    pack["localization_sources"] = sorted(set(pack["localization_sources"]) | {"localization/cosmetics.csv"})
    pack["asset_manifest"] = sorted(set(pack["asset_manifest"]) | {str(path.relative_to(PACK)) for path in files if path.is_relative_to(OUTPUT)})
    declared = set(pack["content_manifest"] + pack["localization_sources"] + pack["asset_manifest"])
    pack["integrity_hashes"] = {name: hashlib.sha256((PACK / name).read_bytes()).hexdigest() for name in sorted(declared)}
    pack_path.write_text(json.dumps(pack, indent=2) + "\n", encoding="ascii")
    print("Generated fifteen original free appearance atlases and sealed the Base pack")


if __name__ == "__main__":
    main()
