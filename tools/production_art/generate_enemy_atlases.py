#!/usr/bin/env python3
"""Reproduce the original four-phase launch enemy pixel library and new scenes."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/production/enemies"
SCENES = ROOT / "data/content_packs/base/assets/enemies/launch"
PHASES = ("idle", "warning", "active", "recovery")
PRESERVED = {"shattered_sentinel", "corrosive_moth", "stone_shell_strider", "ruins_wraith"}
INK = (24, 28, 35, 255)
PALE = (224, 237, 225, 255)
GOLD = (227, 187, 79, 255)
PALETTES = {
    "floor_ruins_of_remnant": ((123, 150, 150, 255), (57, 76, 84, 255), (111, 229, 213, 255)),
    "floor_void_forest": ((102, 161, 94, 255), (43, 66, 65, 255), (211, 108, 177, 255)),
    "floor_time_rift": ((176, 180, 192, 255), (72, 81, 101, 255), (105, 218, 230, 255)),
    "floor_plane_forge": ((183, 110, 103, 255), (70, 58, 75, 255), (248, 191, 77, 255)),
}
LICENSE = """Plane Walker Original Launch Enemy Artwork

All twenty-two phase atlases and the contact sheet were authored locally from
original pixel geometry for Plane Walker. No downloaded imagery, stock samples,
remote generation services or third-party character artwork are used.

The artwork is dedicated to the public domain under CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/
The dedication applies to the artwork, not game code or project identity.

Source: tools/production_art/generate_enemy_atlases.py
Reproduction: python3 tools/production_art/generate_enemy_atlases.py
Runtime content authority: data/content_packs/base/content/enemies.json
"""


class Pixel:
    def __init__(self):
        self.image = Image.new("RGBA", (48, 48))
        self.draw = ImageDraw.Draw(self.image)

    def box(self, x, y, w, h, color, outline=True):
        if outline:
            self.draw.rectangle((x - 1, y - 1, x + w, y + h), fill=INK)
        self.draw.rectangle((x, y, x + w - 1, y + h - 1), fill=color)

    def poly(self, points, color):
        self.draw.polygon(points, fill=color)
        self.draw.line(points + [points[0]], fill=INK, width=1)

    def line(self, points, color, width=2):
        self.draw.line(points, fill=INK, width=width + 2)
        self.draw.line(points, fill=color, width=width)

    def oval(self, box, color):
        self.draw.ellipse(box, fill=color, outline=INK, width=1)

    def gem(self, x, y, radius, color):
        self.poly([(x, y - radius), (x + radius, y), (x, y + radius), (x - radius, y)], color)


def frame(definition, phase):
    c = Pixel()
    species = definition["id"]
    body, shadow, glow = PALETTES[definition["floor_id"]]
    y = (0, -1, 0, 1)[phase]
    x = (0, 0, 1, -1)[phase]
    if species == "shattered_sentinel":
        c.box(17 + x, 11 + y, 15, 23, body)
        c.box(19 + x, 17 + y, 11, 4, shadow)
        c.box(20 + x, 18 + y, 3, 1, glow, False)
        c.box(27 + x, 18 + y, 2, 1, glow, False)
        c.box(18 + x, 35 + y, 5, 7, shadow)
        c.box(28 + x, 35 + y, 5, 7, shadow)
        c.poly([(6, 21), (16, 18), (18, 33), (12, 39), (5, 32)], GOLD)
        c.box(9, 24, 6, 9, shadow)
        c.line([(33 + x, 23), (40 + x, 18), (40 + x, 34)], body, 3)
        c.line([(26, 11 + y), (23, 14 + y), (26, 16 + y)], shadow, 1)
    elif species == "corrosive_moth":
        for side in (-1, 1):
            wing = 2 if phase in (0, 2) else 6
            c.poly([(24, 22), (24 + side * 17, 8 + wing), (24 + side * 20, 23), (24 + side * 11, 32)], body)
            c.gem(24 + side * 12, 22, 4, (168, 224, 85, 255))
            c.line([(24 + side * 2, 16), (24 + side * 7, 9)], GOLD, 1)
        c.oval((20, 15 + y, 28, 36 + y), shadow)
        c.box(22, 20 + y, 4, 10, GOLD, False)
        c.box(22, 16 + y, 1, 2, glow, False)
        c.box(26, 16 + y, 1, 2, glow, False)
    elif species == "stone_shell_strider":
        for lx in (9, 19, 32):
            c.line([(lx, 28), (lx - 3 + x, 38), (lx + 3 + x, 40)], shadow, 3)
        c.oval((5, 11 + y, 37, 33 + y), body)
        for px in (13, 21, 29):
            c.line([(px, 14 + y), (px - 2, 30 + y)], shadow, 2)
            c.box(px, 17 + y, 2, 4, GOLD, False)
        c.poly([(35, 23), (42, 22), (44, 31), (36, 34)], shadow)
        c.box(40, 25, 2, 2, glow, False)
    elif species == "ruins_wraith":
        c.poly([(14 + x, 12 + y), (24 + x, 6 + y), (33 + x, 13 + y), (36 + x, 38), (29, 34), (25, 41), (20, 34), (12, 39)], (162, 142, 194, 255))
        c.oval((16 + x, 12 + y, 31 + x, 27 + y), PALE)
        c.box(19 + x, 18 + y, 3, 3, INK, False)
        c.box(26 + x, 18 + y, 3, 3, INK, False)
        c.line([(14, 23), (7, 28 + y), (5, 22)], glow, 2)
        c.line([(33, 23), (40, 28 - y), (43, 21)], glow, 2)
    elif species == "rift_watcher":
        c.poly([(15, 8), (33, 8), (37, 38), (11, 38)], body)
        c.box(12, 38, 24, 4, shadow)
        c.oval((8, 17 + y, 40, 30 + y), GOLD)
        c.oval((11, 19 + y, 37, 28 + y), PALE)
        c.gem(24 + x, 23 + y, 5, glow)
        c.box(23 + x, 20 + y, 2, 7, INK, False)
        c.gem(24, 12, 3, GOLD)
        c.gem(24, 35, 3, glow)
    elif species == "void_hunter":
        c.poly([(15 + x, 13 + y), (29 + x, 12 + y), (36, 34), (20, 40), (9, 33)], shadow)
        c.poly([(16 + x, 12 + y), (15, 6), (22, 9), (29, 6), (30 + x, 14 + y), (25, 21), (18, 20)], body)
        c.box(18 + x, 14 + y, 10, 2, glow, False)
        c.line([(13, 23), (7, 32), (4, 29)], glow, 2)
        c.line([(30, 23), (40, 28), (43, 22)], glow, 2)
        c.line([(21, 34), (15 + x, 42)], body, 3)
        c.line([(29, 33), (35 + x, 40)], body, 3)
    elif species == "void_archer":
        c.poly([(16, 13 + y), (27, 10 + y), (32, 36), (15, 37)], shadow)
        c.poly([(15, 15 + y), (22, 6 + y), (29, 15 + y)], body)
        c.box(19, 15 + y, 8, 4, INK)
        c.box(22, 16 + y, 4, 1, glow, False)
        c.line([(17, 35), (14 + x, 42)], body, 3)
        c.line([(27, 35), (30 + x, 42)], body, 3)
        c.line([(35, 10), (41 + x, 23), (35, 36)], GOLD, 2)
        c.line([(35, 10), (35, 36)], PALE, 1)
        c.line([(25, 23), (43, 23)], glow, 1)
    elif species == "bramble_mage":
        c.poly([(16, 19), (30, 19), (35, 40), (11, 40)], shadow)
        c.poly([(9, 15 + y), (18, 12 + y), (23, 4 + y), (28, 12 + y), (37, 15 + y)], body)
        c.box(18, 16 + y, 10, 8, body)
        c.box(20, 19 + y, 7, 2, glow, False)
        c.line([(10, 30), (5, 20), (7, 8)], body, 2)
        c.poly([(5, 23), (2, 19), (8, 18)], glow)
        c.line([(37, 37), (39, 13)], GOLD, 2)
        c.gem(39, 10, 4, glow)
    elif species == "void_spore":
        for dx, dy in ((-13, 1), (10, -10), (9, 11), (-5, -13), (-10, 12)):
            c.line([(24, 23), (24 + dx, 23 + dy + y)], shadow, 2)
            c.oval((21 + dx, 20 + dy + y, 27 + dx, 26 + dy + y), glow)
        c.oval((15 + x, 15 + y, 32 + x, 32 + y), body)
        c.oval((19 + x, 18 + y, 28 + x, 28 + y), shadow)
        c.gem(24 + x, 22 + y, 3, PALE)
    elif species == "forest_caller":
        c.poly([(16, 15), (30, 15), (34, 37), (13, 39)], body)
        c.oval((16, 10 + y, 31, 24 + y), shadow)
        for side in (-1, 1):
            c.line([(24 + side * 4, 12), (24 + side * 11, 7), (24 + side * 16, 11)], GOLD, 2)
            c.line([(24 + side * 10, 7), (24 + side * 10, 3)], GOLD, 1)
        c.box(19, 15 + y, 3, 2, glow, False)
        c.box(27, 15 + y, 3, 2, glow, False)
        c.line([(17, 28), (7, 27 + y), (6, 21)], body, 3)
        c.gem(6, 18 + y, 3, glow)
        c.line([(30, 26), (39, 30), (40, 40)], GOLD, 2)
        c.gem(40, 27, 4, glow)
        c.line([(19, 36), (16 + x, 43)], shadow, 3)
        c.line([(29, 36), (31 + x, 43)], shadow, 3)
    elif species == "shadow_lurker":
        c.poly([(7, 32), (13, 20 + y), (24, 16 + y), (36, 23 + y), (43, 35), (31, 38), (23, 34), (12, 39)], shadow)
        c.poly([(14, 21 + y), (17, 10 + y), (23, 16 + y), (31, 10 + y), (34, 24 + y)], body)
        c.box(18, 21 + y, 4, 2, glow, False)
        c.box(28, 21 + y, 4, 2, glow, False)
        c.line([(13, 29), (6 + x, 38)], body, 3)
        c.line([(34, 29), (42 + x, 40)], body, 3)
        c.gem(24, 30, 3, glow)
    elif species == "chrono_guard":
        c.box(15, 15 + y, 18, 23, body)
        c.box(16, 8 + y, 16, 11, body)
        c.box(17, 12 + y, 14, 3, shadow)
        c.box(20, 13 + y, 9, 1, glow, False)
        c.box(11, 19, 6, 10, GOLD)
        c.box(32, 19, 6, 10, GOLD)
        c.box(16 + x, 38, 6, 5, shadow)
        c.box(27 + x, 38, 6, 5, shadow)
        c.oval((18, 23 + y, 30, 35 + y), shadow)
        c.line([(24, 29 + y), (24, 25 + y), (24, 29 + y), (28, 29 + y)], glow, 1)
        c.box(5, 14, 3, 24, GOLD)
        c.gem(6, 11, 5, body)
    elif species == "rift_weaver":
        c.poly([(20, 14 + y), (29, 14 + y), (37, 39), (26, 34), (14, 40), (17, 24)], shadow)
        c.gem(24, 10 + y, 6, body)
        c.gem(24, 10 + y, 2, glow)
        for side in (-1, 1):
            c.line([(24 + side * 6, 22), (24 + side * 15, 16 + y), (24 + side * 16, 31)], body, 2)
            c.gem(24 + side * 16, 31, 3, glow)
        c.line([(8, 31), (24, 25 + y), (40, 31)], glow, 1)
        c.gem(24, 27, 4, GOLD)
    elif species == "blink_striker":
        c.poly([(18 + x, 16 + y), (29 + x, 16 + y), (34, 34), (22, 38), (13, 30)], body)
        c.poly([(15 + x, 14 + y), (24 + x, 6 + y), (31 + x, 15 + y), (25, 20)], shadow)
        c.box(20 + x, 13 + y, 8, 2, glow, False)
        c.line([(17, 24), (7, 21), (4, 28)], GOLD, 2)
        c.line([(30, 24), (38, 18), (43, 23)], glow, 2)
        c.line([(21, 35), (12 + x, 42)], shadow, 3)
        c.line([(28, 35), (35 + x, 40)], shadow, 3)
        c.box(5, 10, 3, 2, glow)
        c.box(39, 36, 4, 2, glow)
    elif species == "rewind_priest":
        c.poly([(18, 17), (29, 17), (36, 42), (12, 42)], body)
        c.poly([(18, 16 + y), (17, 8 + y), (24, 5 + y), (32, 9 + y), (30, 16 + y)], GOLD)
        c.box(20, 15 + y, 9, 6, shadow)
        c.box(23, 17 + y, 5, 1, glow, False)
        c.line([(23, 24), (23, 39)], GOLD, 2)
        c.box(6, 23, 12, 9, shadow)
        c.box(7, 24, 10, 5, PALE, False)
        c.box(11, 24, 1, 6, GOLD, False)
        c.line([(38, 38), (39, 12)], GOLD, 2)
        c.oval((34, 6, 44, 16), glow)
        c.line([(38, 10), (41, 10), (38, 13)], shadow, 1)
    elif species == "chrono_storm_elemental":
        c.poly([(21, 5), (32, 8), (30, 18), (39, 22), (30, 29), (32, 36), (24, 44), (15, 36), (18, 28), (9, 23), (18, 18)], body)
        c.poly([(23, 13 + y), (30, 20 + y), (27, 31 + y), (20, 34 + y), (17, 22 + y)], shadow)
        c.gem(24 + x, 24 + y, 5, glow)
        c.line([(11, 12), (6, 22), (11, 21), (6, 34)], glow, 1)
        c.line([(38, 12), (43, 20), (38, 22), (43, 34)], GOLD, 1)
    elif species == "eternal_hound":
        c.oval((12 + x, 21 + y, 34 + x, 34 + y), body)
        c.poly([(31, 18 + y), (30, 9 + y), (36, 15 + y), (42, 17 + y), (43, 25 + y), (34, 27 + y)], shadow)
        c.box(37, 19 + y, 3, 2, glow, False)
        c.line([(16, 32), (13 + x, 41)], body, 3)
        c.line([(30, 32), (34 + x, 40)], body, 3)
        c.line([(13, 25), (6, 21), (4, 14)], glow, 2)
        c.box(18, 24 + y, 10, 3, GOLD, False)
    elif species == "forge_titan":
        c.box(13, 15 + y, 23, 23, body)
        c.box(17, 6 + y, 15, 11, shadow)
        c.box(18, 10 + y, 13, 3, glow, False)
        c.box(5, 15, 8, 20, shadow)
        c.box(36, 14, 8, 23, shadow)
        c.box(4, 13, 10, 5, body)
        c.box(35, 12, 10, 6, body)
        c.box(14 + x, 38, 8, 6, shadow)
        c.box(28 + x, 38, 8, 6, shadow)
        c.box(18, 21 + y, 14, 12, INK)
        for dx in (20, 24, 28):
            c.box(dx, 23 + y, 2, 8, glow, False)
        c.box(14, 5, 3, 9, body)
        c.box(34, 4, 3, 9, body)
    elif species == "void_web_weaver":
        for side in (-1, 1):
            for offset in (-8, 0, 8):
                c.line([(24 + side * 6, 24 + offset // 2), (24 + side * 16, 21 + offset + y), (24 + side * 20, 28 + offset)], body, 2)
        c.oval((15, 10 + y, 33, 29 + y), shadow)
        c.oval((19 + x, 25 + y, 29 + x, 38 + y), body)
        c.gem(24, 18 + y, 5, glow)
        c.box(21, 27 + y, 6, 2, GOLD, False)
    elif species == "phase_ranger":
        c.poly([(17, 17), (29, 17), (32, 34), (15, 34)], shadow)
        c.box(17 + x, 8 + y, 13, 11, body)
        c.box(18 + x, 12 + y, 11, 3, INK)
        c.box(20 + x, 13 + y, 8, 1, glow, False)
        c.line([(18, 33), (14 + x, 42)], body, 3)
        c.line([(28, 33), (33 + x, 41)], body, 3)
        c.line([(25, 23), (39, 20)], body, 3)
        c.box(34, 16, 10, 7, shadow)
        c.box(38, 18, 6, 2, glow, False)
        c.box(7, 13, 5, 20, GOLD)
        c.box(8, 15, 3, 7, glow, False)
    elif species == "chaos_amalgam":
        c.poly([(14, 9 + y), (23, 13 + y), (31, 5 + y), (39, 15), (35, 26), (42, 37), (28, 40), (24, 34), (15, 43), (7, 31), (12, 22), (6, 14)], body)
        c.poly([(13, 18 + y), (24, 16 + y), (32, 25), (25, 36), (15, 33)], shadow)
        c.oval((14, 18 + y, 25, 28 + y), PALE)
        c.gem(21 + x, 23 + y, 3, glow)
        c.gem(32, 16, 3, GOLD)
        c.line([(10, 31), (15, 35), (12, 39)], glow, 2)
        c.line([(30, 30), (36, 36)], GOLD, 3)
    elif species == "plane_ripper":
        c.poly([(17, 13 + y), (29, 12 + y), (33, 29), (28, 39), (19, 40), (14, 27)], shadow)
        c.poly([(17, 13 + y), (15, 6 + y), (22, 10 + y), (27, 5 + y), (30, 14 + y), (25, 20)], body)
        c.box(21, 14 + y, 7, 2, glow, False)
        c.line([(16, 23), (8, 18), (4, 28)], body, 3)
        c.line([(30, 23), (39, 18), (44, 27)], body, 3)
        c.line([(8, 18), (5, 10)], glow, 2)
        c.line([(39, 18), (43, 9)], glow, 2)
        c.gem(24 + x, 28, 5, GOLD)
        c.line([(19, 37), (14 + x, 44)], body, 2)
        c.line([(28, 37), (34 + x, 43)], body, 2)
    else:
        raise ValueError("No authored silhouette: " + species)

    if phase == 1:
        c.gem(24, 4, 2, GOLD)
    elif phase == 2:
        c.gem(5, 40, 2, glow)
        c.gem(43, 40, 2, PALE)
    elif phase == 3:
        c.box(5, 42, 4, 1, shadow, False)
        c.box(39, 42, 4, 1, shadow, False)
    return c.image


def scene(definition):
    name = "".join(part.title() for part in definition["id"].split("_"))
    radius = float(definition["collision_radius_px"])
    return f'''[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://scripts/enemies/launch/launch_hostile_actor.gd" id="1_actor"]
[ext_resource type="Script" path="res://scripts/combat/health_component.gd" id="2_health"]
[ext_resource type="Script" path="res://scripts/combat/hurtbox.gd" id="3_hurtbox"]
[ext_resource type="Texture2D" path="res://assets/production/enemies/{definition["id"]}.png" id="4_texture"]

[sub_resource type="CircleShape2D" id="BodyShape"]
radius = {radius:.1f}

[sub_resource type="CircleShape2D" id="HurtShape"]
radius = {radius + 3:.1f}

[node name="{name}" type="CharacterBody2D"]
collision_layer = 4
collision_mask = 1
script = ExtResource("1_actor")
max_hp = {float(definition["max_hp"]):.1f}
move_speed = {float(definition["move_speed"]):.1f}

[node name="Visual" type="Polygon2D" parent="."]
visible = false

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("4_texture")
hframes = 4

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("BodyShape")

[node name="HealthComponent" type="Node" parent="."]
script = ExtResource("2_health")
max_hp = {float(definition["max_hp"]):.1f}

[node name="Hurtbox" type="Area2D" parent="."]
collision_layer = 4
collision_mask = 0
script = ExtResource("3_hurtbox")
health_component_path = NodePath("../HealthComponent")

[node name="CollisionShape2D" type="CollisionShape2D" parent="Hurtbox"]
shape = SubResource("HurtShape")
'''


def generate(destination=OUTPUT, scene_destination=SCENES):
    definitions = json.loads((ROOT / "data/content_packs/base/content/enemies.json").read_text())
    destination.mkdir(parents=True, exist_ok=True)
    scene_destination.mkdir(parents=True, exist_ok=True)
    assets = []
    sheet = Image.new("RGB", (768, 480), (30, 35, 42))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=10)
    for index, definition in enumerate(definitions):
        atlas = Image.new("RGBA", (192, 48))
        for phase in range(4):
            atlas.paste(frame(definition, phase), (phase * 48, 0))
        filename = definition["id"] + ".png"
        path = destination / filename
        atlas.save(path, compress_level=9)
        assets.append({"id": definition["id"], "path": filename, "floor_id": definition["floor_id"], "width": 192, "height": 48, "frame_width": 48, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        sx, sy = (index % 4) * 192, (index // 4) * 80
        sheet.paste(atlas, (sx, sy + 2), atlas)
        draw.text((sx + 5, sy + 54), definition["id"], fill=(219, 230, 222), font=font)
        if definition["id"] not in PRESERVED:
            (scene_destination / ("enemy_" + definition["id"] + ".tscn")).write_text(scene(definition), encoding="utf-8")
    sheet.save(destination / "contact-sheet.png", compress_level=9)
    manifest = {"schema_id": "plane_walker_launch_enemy_art_v1", "schema_version": 1, "license": "CC0-1.0", "generator": "tools/production_art/generate_enemy_atlases.py", "source": "data/content_packs/base/content/enemies.json", "phases": list(PHASES), "assets": assets}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (destination / "LICENSE.txt").write_text(LICENSE, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--scenes", type=Path, default=SCENES)
    args = parser.parse_args()
    generate(args.output, args.scenes)
