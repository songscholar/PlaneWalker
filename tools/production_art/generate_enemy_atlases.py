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
INK = (17, 22, 25, 255)
PALE = (237, 240, 220, 255)
GOLD = (229, 189, 105, 255)
PALETTES = {
    "floor_ruins_of_remnant": ((105, 119, 113, 255), (55, 67, 66, 255), (97, 213, 231, 255)),
    "floor_void_forest": ((121, 186, 161, 255), (79, 146, 126, 255), (211, 106, 155, 255)),
    "floor_time_rift": ((201, 215, 210, 255), (62, 79, 104, 255), (97, 213, 231, 255)),
    "floor_plane_forge": ((193, 125, 84, 255), (155, 94, 72, 255), (229, 189, 105, 255)),
}
LIGHTS = {
    PALETTES["floor_ruins_of_remnant"][0]: (171, 184, 172, 255),
    PALETTES["floor_void_forest"][0]: (143, 174, 117, 255),
    PALETTES["floor_time_rift"][0]: PALE,
    PALETTES["floor_plane_forge"][0]: (223, 155, 101, 255),
    GOLD: (232, 213, 165, 255),
    (184, 151, 215, 255): (201, 215, 210, 255),
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
        if color in LIGHTS and w >= 4 and h >= 4:
            self.draw.polygon([(x + w // 2, y), (x + w - 1, y), (x + w - 1, y + max(1, h // 3)), (x + w - 3, y + 1)], fill=LIGHTS[color])

    def poly(self, points, color):
        self.draw.polygon(points, fill=color)
        self.draw.line(points + [points[0]], fill=INK, width=1)

    def line(self, points, color, width=2):
        self.draw.line(points, fill=INK, width=width + 2)
        self.draw.line(points, fill=color, width=width)

    def oval(self, box, color):
        self.draw.ellipse(box, fill=color, outline=INK, width=1)
        if color in LIGHTS and box[2] - box[0] >= 6:
            x0, y0, x1, y1 = box
            self.draw.ellipse((x0 + (x1 - x0) // 2, y0 + 2, x1 - 2, y0 + (y1 - y0) // 2), fill=LIGHTS[color])

    def gem(self, x, y, radius, color):
        self.poly([(x, y - radius), (x + radius, y), (x, y + radius), (x - radius, y)], color)
        if radius >= 3:
            self.draw.polygon([(x, y - radius + 1), (x + radius - 1, y), (x, y)], fill=LIGHTS.get(color, PALE))

    def marks(self, points, color, width=1):
        self.draw.line(points, fill=color, width=width)

    def facet(self, points, color):
        self.draw.polygon(points, fill=color)


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
        c.line([(33 + x, 23), (35 + x, 28)], body, 3)
        tip = ((42, 15), (35, 5), (44, 32), (40, 38))[phase]
        c.line([(35 + x, 28), tip], PALE, 2)
        c.line([(32 + x, 25), (38 + x, 29)], GOLD, 1)
        c.line([(26, 11 + y), (23, 14 + y), (26, 16 + y)], shadow, 1)
    elif species == "corrosive_moth":
        for side in (-1, 1):
            wing = 2 if phase in (0, 2) else 6
            c.poly([(24, 22), (24 + side * 17, 8 + wing), (24 + side * 20, 23), (24 + side * 11, 32)], body)
            c.gem(24 + side * 12, 22, 4, (143, 174, 117, 255))
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
        c.poly([(14 + x, 12 + y), (24 + x, 6 + y), (33 + x, 13 + y), (36 + x, 38), (29, 34), (25, 41), (20, 34), (12, 39)], (184, 151, 215, 255))
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
        hand_y = (0, -5, 5, 2)[phase]
        c.line([(13, 23), (7, 32 + hand_y), (4, 29 + hand_y)], glow, 2)
        c.line([(30, 23), (40, 28 + hand_y), (43, 22 + hand_y)], glow, 2)
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
        draw_x = (35, 29, 36, 33)[phase]
        c.line([(35, 10), (draw_x, 23), (35, 36)], PALE, 1)
        c.line([(draw_x - 6, 23), (43, 23)], glow, 1)
    elif species == "bramble_mage":
        c.poly([(16, 19), (30, 19), (35, 40), (11, 40)], shadow)
        c.poly([(9, 15 + y), (18, 12 + y), (23, 4 + y), (28, 12 + y), (37, 15 + y)], body)
        c.box(18, 16 + y, 10, 8, body)
        c.box(20, 19 + y, 7, 2, glow, False)
        c.line([(10, 30), (5, 20), (7, 8)], body, 2)
        c.poly([(5, 23), (2, 19), (8, 18)], glow)
        c.line([(37, 37), (39, 13)], GOLD, 2)
        c.gem(39, 10, (3, 4, 6, 2)[phase], glow)
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
        orb = (0, 1, 2, -1)[phase]
        c.oval((34 - orb, 6 - orb, 44 + orb, 16 + orb), glow)
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
        arm_y = (0, -5, 4, 2)[phase]
        c.box(5, 15 + arm_y, 8, 20, shadow)
        c.box(36, 14 + arm_y, 8, 23, shadow)
        c.box(4, 13 + arm_y, 10, 5, body)
        c.box(35, 12 + arm_y, 10, 6, body)
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

    light = LIGHTS[body]
    if species == "shattered_sentinel":
        c.facet([(28 + x, 12 + y), (31 + x, 13 + y), (30 + x, 29 + y), (26 + x, 29 + y)], light)
        c.marks([(19 + x, 24 + y), (23 + x, 26 + y), (21 + x, 31 + y)], INK)
        c.marks([(8, 23), (13, 21), (15, 31), (12, 35)], PALE)
        c.box(19 + x, 32 + y, 11, 2, GOLD, False)
        c.box(28 + x, 39 + y, 4, 2, light, False)
        c.gem(12, 29, 2, glow)
    elif species == "corrosive_moth":
        for side in (-1, 1):
            wing_y = 8 + (2 if phase in (0, 2) else 6)
            c.marks([(24 + side * 3, 23), (24 + side * 14, wing_y + 5), (24 + side * 17, 23)], shadow)
            c.marks([(24 + side * 5, 25), (24 + side * 11, 29)], light)
            c.box(24 + side * 12, 21, 2, 2, PALE, False)
        for segment in (24, 28, 32):
            c.marks([(22, segment + y), (26, segment + y)], INK)
        c.line([(22, 34 + y), (19, 38 + y)], shadow, 1)
        c.line([(26, 34 + y), (30, 38 + y)], shadow, 1)
    elif species == "stone_shell_strider":
        for px in (13, 21, 29):
            c.facet([(px + 1, 14 + y), (px + 5, 16 + y), (px + 4, 25 + y), (px + 1, 24 + y)], light)
            c.marks([(px - 3, 18 + y), (px - 4, 22 + y), (px - 2, 25 + y)], shadow)
        c.box(38, 30, 4, 2, PALE, False)
        for lx in (9, 19, 32):
            c.box(lx - 1 + x, 37, 3, 2, body, False)
    elif species == "ruins_wraith":
        c.facet([(29 + x, 10 + y), (32 + x, 16 + y), (31 + x, 31), (28 + x, 35)], light)
        c.marks([(18 + x, 15 + y), (22 + x, 14 + y), (25 + x, 16 + y)], shadow)
        c.box(23 + x, 21 + y, 2, 3, INK, False)
        c.marks([(19, 28), (20, 33), (18, 36)], (118, 87, 154, 255))
        c.marks([(26, 29), (25, 36)], PALE)
        c.box(7, 25 + y, 3, 2, PALE, False)
        c.box(38, 25 - y, 3, 2, PALE, False)
    elif species == "rift_watcher":
        c.facet([(28, 9), (32, 10), (35, 17), (30, 16)], light)
        c.marks([(17, 10), (20, 13), (18, 17)], shadow)
        c.marks([(14, 32), (19, 30), (22, 33), (20, 37)], shadow)
        c.marks([(31, 31), (33, 36)], light, 2)
        c.box(26 + x, 20 + y, 2, 2, PALE, False)
    elif species in ("void_hunter", "plane_ripper"):
        c.facet([(27 + x, 18 + y), (31, 24), (29, 31), (26, 28)], body)
        c.facet([(20 + x, 22 + y), (24 + x, 20 + y), (25, 31), (21, 32)], light)
        c.marks([(19 + x, 17 + y), (22 + x, 18 + y), (26 + x, 17 + y)], PALE)
        c.box(18 + x, 34, 5, 2, GOLD, False)
        c.box(28 + x, 33, 4, 2, body, False)
        claw_y = (0, -5, 5, 2)[phase] if species == "void_hunter" else 0
        for hand_x in (7, 39):
            c.marks([(hand_x, 27 + claw_y), (hand_x - 2, 31 + claw_y)], PALE)
            c.marks([(hand_x + 2, 27 + claw_y), (hand_x, 32 + claw_y)], light)
    elif species == "void_archer":
        c.facet([(24, 23), (29, 25), (30, 33), (24, 31)], body)
        c.marks([(18, 24), (17, 33), (21, 30)], body)
        c.box(19, 25, 10, 2, GOLD, False)
        c.line([(24, 23), (30 - phase, 24 + phase)], body, 2)
        c.box(29 - phase, 22 + phase, 3, 3, light, False)
        c.marks([(35, 12), (39, 20)], PALE)
        c.marks([(35, 32), (38, 28)], light)
    elif species == "bramble_mage":
        c.facet([(25, 23), (28, 23), (32, 37), (27, 34)], body)
        c.marks([(18, 24), (17, 32), (19, 37)], body, 2)
        c.box(15, 35, 15, 2, GOLD, False)
        c.marks([(23, 8 + y), (28, 13 + y), (34, 14 + y)], light)
        c.marks([(39, 15), (41, 19), (38, 23), (39, 30)], shadow)
        c.gem(24, 27, 3, glow)
    elif species == "void_spore":
        c.marks([(18 + x, 27 + y), (21 + x, 29 + y), (24 + x, 30 + y)], shadow, 2)
        c.box(26 + x, 17 + y, 3, 3, PALE, False)
        c.marks([(20 + x, 21 + y), (22 + x, 18 + y)], light)
        for dx, dy in ((-13, 1), (10, -10), (9, 11), (-5, -13), (-10, 12)):
            c.box(24 + dx, 21 + dy + y, 2, 2, PALE, False)
    elif species == "forest_caller":
        c.facet([(27, 25), (30, 28), (30, 34), (27, 32)], light)
        c.marks([(19, 26), (22, 29), (20, 35)], shadow)
        c.marks([(24, 14 + y), (24, 19 + y), (28, 22 + y)], GOLD)
        c.box(19, 33, 9, 3, shadow, False)
        c.marks([(31, 7), (35, 4)], PALE)
        c.marks([(33, 37), (31, 40)], light, 2)
    elif species == "shadow_lurker":
        c.facet([(17, 12 + y), (20, 17 + y), (16, 21 + y)], light)
        c.facet([(29, 13 + y), (32, 21 + y), (28, 20 + y)], light)
        c.facet([(23, 26), (29, 28), (33, 34), (27, 32)], body)
        c.marks([(20, 25 + y), (24, 27 + y), (29, 25 + y)], PALE)
        c.marks([(11 + x, 36), (8 + x, 38), (12 + x, 39)], PALE)
        c.marks([(38 + x, 36), (40 + x, 39)], light)
    elif species == "chrono_guard":
        c.facet([(26, 9 + y), (30, 10 + y), (29, 12 + y), (25, 11 + y)], light)
        c.box(16, 18 + y, 15, 2, GOLD, False)
        c.marks([(20, 24 + y), (25, 23 + y), (29, 27 + y)], PALE)
        c.marks([(21, 34 + y), (24, 35 + y), (28, 33 + y)], GOLD)
        c.box(12, 27, 4, 3, body, False)
        c.box(33, 27, 4, 3, light, False)
        c.box(17 + x, 40, 4, 2, light, False)
    elif species == "rift_weaver":
        c.facet([(26, 17), (29, 20), (33, 33), (28, 30)], body)
        c.marks([(19, 25), (17, 35), (21, 32)], light)
        for side in (-1, 1):
            c.gem(24 + side * 13, 18 + y, 2, GOLD)
            c.marks([(24 + side * 14, 22), (24 + side * 14, 27)], light)
        c.box(24, 8 + y, 2, 2, PALE, False)
    elif species == "blink_striker":
        c.facet([(26 + x, 18 + y), (30 + x, 22 + y), (30, 30), (25, 26)], light)
        c.marks([(19, 22), (23, 24), (21, 29)], shadow)
        c.box(19, 31, 11, 2, GOLD, False)
        c.marks([(18 + x, 13 + y), (24 + x, 9 + y)], body)
        c.gem(11, 22, 2, PALE)
        c.gem(37, 19, 2, PALE)
    elif species == "rewind_priest":
        c.facet([(27, 21), (29, 25), (32, 37), (27, 34)], light)
        c.marks([(18, 28), (16, 37), (19, 35)], shadow, 2)
        c.box(18, 24, 11, 2, GOLD, False)
        c.marks([(8, 25), (10, 25)], shadow)
        c.marks([(13, 25), (15, 25)], shadow)
        c.box(28, 9 + y, 2, 4, PALE, False)
        c.box(39, 8, 2, 2, PALE, False)
    elif species == "chrono_storm_elemental":
        c.facet([(27, 8), (30, 10), (26, 17), (24, 16)], light)
        c.facet([(31, 22), (35, 22), (28, 27)], PALE)
        c.facet([(27, 33), (29, 36), (25, 40), (24, 37)], light)
        c.marks([(21, 17 + y), (20, 22 + y), (23, 29 + y)], glow)
    elif species == "eternal_hound":
        c.facet([(23 + x, 22 + y), (29 + x, 24 + y), (27 + x, 30 + y), (23 + x, 28 + y)], light)
        c.marks([(16 + x, 28 + y), (20 + x, 30 + y), (22 + x, 33 + y)], shadow)
        c.marks([(35, 25 + y), (41, 24 + y)], PALE)
        c.line([(20, 33), (21 - x, 40)], shadow, 2)
        c.line([(28, 32), (27 - x, 40)], shadow, 2)
        c.box(13 + x, 39, 4, 2, light, False)
        c.box(31 + x, 38, 4, 2, light, False)
    elif species == "forge_titan":
        c.facet([(31, 17 + y), (34, 18 + y), (34, 34), (31, 32)], light)
        c.marks([(15, 20 + y), (17, 22 + y), (16, 28 + y)], shadow)
        c.box(14, 35, 20, 2, GOLD, False)
        c.box(6, 22 + arm_y, 5, 4, body, False)
        c.box(37, 21 + arm_y, 5, 4, light, False)
        c.marks([(19, 8 + y), (23, 8 + y)], PALE)
        c.box(30 + x, 39, 5, 3, body, False)
    elif species == "void_web_weaver":
        c.marks([(28, 13 + y), (30, 19 + y), (27, 23 + y)], body, 2)
        for eye_x in (19, 22, 26, 29):
            c.box(eye_x, 23 + y, 1, 2, PALE, False)
        c.marks([(22 + x, 31 + y), (27 + x, 34 + y)], GOLD)
        for side in (-1, 1):
            for offset in (-8, 0, 8):
                c.box(23 + side * 16, 20 + offset + y, 2, 2, light, False)
    elif species == "phase_ranger":
        c.facet([(27 + x, 9 + y), (29 + x, 9 + y), (29 + x, 12 + y), (26 + x, 11 + y)], light)
        c.facet([(25, 20), (28, 22), (29, 29), (25, 28)], body)
        c.box(17, 30, 13, 2, GOLD, False)
        c.box(34, 17, 5, 2, light, False)
        c.box(36, 21, 3, 3, body, False)
        c.marks([(9, 24), (10, 30)], PALE)
    elif species == "chaos_amalgam":
        c.facet([(32, 8 + y), (36, 15), (33, 20), (29, 17)], light)
        c.facet([(29, 34), (36, 36), (33, 38)], PALE)
        c.marks([(9, 15), (15, 16), (17, 13 + y)], shadow, 2)
        c.marks([(16, 23 + y), (19, 20 + y), (22, 21 + y)], GOLD)
        c.box(15, 30, 5, 2, PALE, False)

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
    palette_path = ROOT / "assets/production/palettes/plane_walker_modern.json"
    manifest = {"schema_id": "plane_walker_launch_enemy_art_v1", "schema_version": 1, "license": "CC0-1.0", "generator": "tools/production_art/generate_enemy_atlases.py", "source": "data/content_packs/base/content/enemies.json", "phases": list(PHASES), "assets": assets,
                "art_direction": {"light_direction": "top_right", "palette": str(palette_path.relative_to(ROOT)), "palette_sha256": hashlib.sha256(palette_path.read_bytes()).hexdigest()}}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (destination / "LICENSE.txt").write_text(LICENSE, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--scenes", type=Path, default=SCENES)
    args = parser.parse_args()
    generate(args.output, args.scenes)
