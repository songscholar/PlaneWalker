#!/usr/bin/env python3
"""Rebuild the authored CC0 data-only Expansion pack from fixed inputs."""

import csv
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "data/content_packs/temporal_frontiers"
IDS = ["echo_lancer", "mire_cantor", "parallax_guard", "cinder_drake", "prism_seer"]
FLOORS = ["ruins_of_remnant", "void_forest", "time_rift", "plane_forge", "throne_of_void"]
PROFILES = ["ruins", "forest", "rift", "forge", "throne"]
NAMES = ["Echo Lancer", "Mire Cantor", "Parallax Guard", "Cinder Drake", "Prism Seer"]
ZH_NAMES = ["回响枪卫", "泥潭咏者", "视差守卫", "余烬龙兽", "棱镜先知"]
DESCRIPTIONS = ["Two thrusts follow one locked warning.", "A mire blooms where its verse was aimed.", "Two rays leave a narrow passage between them.", "A charging drake follows with a fan of embers.", "Three prism rays launch in a fixed sequence."]
ZH_DESCRIPTIONS = ["锁定警告后连续刺击两次。", "咏唱锁定的位置将生出泥潭。", "双束射线之间留有狭窄通道。", "龙兽冲锋后散射余烬。", "三束棱镜射线按固定次序发射。"]
MASKS = [
    [".......aa.......", "......aaaa......", "......aeea......", ".....aaaaaa...w.", "......bbbb....w.", "....abbbbaa...w.", "...aabbbbbba..w.", "...a.bbbbbbaaaw.", ".....bbbbbb...w.", ".....bbbbbb...w.", ".....cccccc...w.", "....cc....cc..w.", "....cc....cc..w.", "...aaa....aaa.w.", "................", "................"],
    ["......aaaa......", "....aaaaaaaa....", "...aaabbbbaaa...", "....aeeeebba....", ".....bbbbbb.....", "....bbbbbbbb....", "...abbbbbbbba...", "..aaabbbbbbaaa..", "....bbbbbbbb....", "...bbbbbbbbbb...", "...bbbbbbbbbb...", "..bbbbbbbbbbbb..", "..aaccccccccaa..", "..aaa......aaa..", "................", "................"],
    [".....aaaaaa.....", "....aabbbbaa....", "....abeeebba....", ".....bbbbbb.....", "..aaabbbbbbaaa..", ".aabbabbbbabbaa.", ".abbbabbbbabbbba", ".abbbabbbbabbbba", "..aabbbbbbbbaa..", "....bbbbbbbb....", ".....cccccc.....", "....cc....cc....", "....cc....cc....", "...aaa....aaa...", "................", "................"],
    ["...a.......a....", "..aa..aaaa.aa...", "...aabeeeebba...", "....bbbbbbbb....", "a...bbbbbbbba...", "aa..bbbbbbbbaa..", "aba.bbbbbbbbbaa.", "abbbbbbbbbbbbaa.", ".abbbbbbbbbbbb..", "..abbbbbbbbbba..", "...bbbbbbbbba...", "...cccccccc.....", "..cc..cc..cc....", "..aa..aa..aa....", "................", "................"],
    [".......w........", "......www.......", ".....wwwww......", "....wwwewww.....", ".....wwwww......", "......www.......", "......bbb.......", ".....bbbbb......", "...aabbbbbaa....", "..aaabbbbbaaa...", "....bbbbbbb.....", "...bbbbbbbbb....", "..ccccccccccc...", "...aa.....aa....", "................", "................"],
]
PALETTES = [
    {"a": "#182f39", "b": "#a9c6cf", "c": "#5e8999", "e": "#f3c74c", "w": "#d9eef0"},
    {"a": "#243932", "b": "#6bbd86", "c": "#376b59", "e": "#fee07b", "w": "#b5ead0"},
    {"a": "#263044", "b": "#85b6dc", "c": "#b98cca", "e": "#fff4bc", "w": "#cceef7"},
    {"a": "#3c273b", "b": "#de775b", "c": "#925e76", "e": "#ffed87", "w": "#ffd5aa"},
    {"a": "#293942", "b": "#86aeb6", "c": "#506271", "e": "#ffffff", "w": "#e7b477"},
]


def write_json(relative, value):
    path = PACK / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def geometry(shape="line", radius=7, length=72, angle=0):
    return {"shape": shape, "origin_offset": {"x": 0, "y": 0}, "aim_offset_degrees": angle, "radius": radius, "length": length}


def action(enemy, suffix, handler, primitives, offsets, damage, damage_type="physical", parameters=None, warning=40, active=None, max_distance=220):
    return {"id": enemy + "." + suffix, "handler_id": handler, "warning_frames": warning, "active_frames": active or max(offsets) + 1, "recovery_frames": 30, "idle_frames": 30, "cooldown_frames": 150, "weight": 1, "max_consecutive": 1, "distance_min_px": 0, "distance_max_px": max_distance, "geometry": primitives, "hit_schedule": [{"offset_frame": offset, "hit_index": index, "damage": damage, "damage_type": damage_type} for index, offset in enumerate(offsets)], "parameters": parameters or {"knockback_px": 12}, "cue_id": enemy + "_" + suffix}


def build():
    patterns = [
        [action(IDS[0], "echo_thrust", "melee", [geometry()], [0, 30], 12, max_distance=84)],
        [action(IDS[1], "mire_verse", "zone", [geometry("target_circle", 28, 0)], [0], 5, "void", {"lifetime_frames": 180, "tick_interval_frames": 60, "slow_multiplier": 0.7, "slow_duration_frames": 60}, warning=50)],
        [action(IDS[2], "split_ray", "melee", [geometry(radius=6, length=180, angle=-18), geometry(radius=6, length=180, angle=18)], [0], 17, "time", warning=45)],
        [action(IDS[3], "cinder_charge", "charge", [geometry(radius=12, length=96)], [0], 20, "fire", {"travel_px": 96, "speed_px_per_second": 160, "knockback_px": 16}, active=36, max_distance=140), action(IDS[3], "cinder_fan", "projectile_volley", [geometry(radius=4, angle=angle) for angle in [-28, 0, 28]], [0, 0, 0], 9, "fire", {"speed_px_per_second": 150, "lifetime_frames": 90, "pierce_count": 0})],
        [action(IDS[4], "prism_sequence", "projectile_volley", [geometry(radius=4, angle=angle) for angle in [-20, 0, 20]], [0, 25, 50], 12, "void", {"speed_px_per_second": 170, "lifetime_frames": 84, "pierce_count": 0}, warning=50)],
    ]
    enemies, encounters = [], []
    for index, enemy_id in enumerate(IDS):
        floor_id = "floor_" + FLOORS[index]
        profile_id = "encounter_profile_" + PROFILES[index] + "_adapter_v1"
        recipe_id = enemy_id + "_frontiers_v3"
        enemies.append({"category": "expansion_enemy_definition", "id": enemy_id, "schema_version": 1, "name_key": "EXPANSION_" + enemy_id.upper() + "_NAME", "description_key": "EXPANSION_" + enemy_id.upper() + "_DESC", "availability": ["EXPANSION"], "tags": ["temporal_frontiers", "expansion"], "compatibility": {"floor_ids": [floor_id], "actor_kinds": ["enemy"]}, "references": [floor_id], "floor_id": floor_id, "runtime_kind": enemy_id, "max_hp": [90, 100, 130, 160, 180][index], "defense": index * 2, "move_speed": [52, 28, 32, 55, 24][index], "threat_cost": [2, 2, 3, 4, 4][index], "collision_radius_px": 12, "sprite_asset": "assets/" + enemy_id + ".png", "actions": patterns[index], "mechanisms": {"first_attack_stagger_frames": 30, "kite_min_px": [0, 80, 72, 0, 96][index], "kite_max_px": [36, 144, 144, 72, 160][index]}})
        encounters.append({"category": "expansion_encounter_profile", "id": "expansion_profile_" + enemy_id, "schema_version": 1, "name_key": "EXPANSION_" + enemy_id.upper() + "_NAME", "description_key": "EXPANSION_" + enemy_id.upper() + "_DESC", "availability": ["EXPANSION"], "tags": ["temporal_frontiers"], "compatibility": {}, "references": sorted([enemy_id, floor_id, profile_id, "room_combat_open_field"]), "floor_id": floor_id, "profile_id": profile_id, "selection_revision": 3, "recipes": [{"id": recipe_id, "room_type": "combat", "template_ids": ["room_combat_open_field"], "threat_budget": enemies[-1]["threat_cost"], "waves": [{"id": enemy_id + "_wave", "delay_frames": 0, "warning_frames": 40, "spawns": [{"id": enemy_id + "_spawn", "enemy_id": enemy_id, "spawn_slot_id": "enemy_wave_primary", "spawn_offset": {"x": 0, "y": 0}, "elite": False, "affix_ids": [], "mechanism_ids": []}]}]}]})
        atlas = Image.new("RGBA", (128, 32))
        for frame in range(4):
            sprite = Image.new("RGBA", (16, 16))
            palette = dict(PALETTES[index])
            if frame == 1:
                palette["e"] = "#ffffff"
            if frame == 2:
                palette["e"] = "#ff705c"
            for y, row in enumerate(MASKS[index]):
                for x, pixel in enumerate(row):
                    if pixel in palette:
                        sprite.putpixel((x, y), tuple(bytes.fromhex(palette[pixel][1:])) + (255,))
            atlas.paste(sprite.resize((32, 32), Image.Resampling.NEAREST), (frame * 32, 0))
        (PACK / "assets").mkdir(parents=True, exist_ok=True)
        atlas.save(PACK / "assets" / (enemy_id + ".png"))
    write_json("content/enemies.json", enemies)
    write_json("content/encounters.json", encounters)
    write_json("assets/provenance.json", {"schema_version": 1, "license": "CC0-1.0", "author": "Plane Walker project", "source": "Authored pixel masks in tools/generate_temporal_frontiers.py", "assets": [enemy_id + ".png" for enemy_id in IDS]})
    locale_path = PACK / "localization/strings.csv"
    locale_path.parent.mkdir(parents=True, exist_ok=True)
    with locale_path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["keys", "en", "zh_CN"])
        for index, enemy_id in enumerate(IDS):
            writer.writerow(["EXPANSION_" + enemy_id.upper() + "_NAME", NAMES[index], ZH_NAMES[index]])
            writer.writerow(["EXPANSION_" + enemy_id.upper() + "_DESC", DESCRIPTIONS[index], ZH_DESCRIPTIONS[index]])
    content = ["content/enemies.json", "content/encounters.json"]
    localization = ["localization/strings.csv"]
    assets = ["assets/" + enemy_id + ".png" for enemy_id in IDS] + ["assets/provenance.json"]
    write_json("pack.json", {"pack_id": "temporal_frontiers", "pack_version": "1.0.0", "schema_version": 2, "game_version_range": ">=0.4.0 <1.0.0", "dependencies": [{"pack_id": "base", "version_range": ">=0.4.0 <1.0.0", "required": True}], "load_order": 100, "content_manifest": content, "localization_sources": localization, "asset_manifest": assets, "integrity_hashes": {relative: hashlib.sha256((PACK / relative).read_bytes()).hexdigest() for relative in content + localization + assets}, "entitlement_tag": ""})


if __name__ == "__main__":
    build()
