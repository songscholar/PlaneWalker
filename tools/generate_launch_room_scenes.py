#!/usr/bin/env python3
"""Generate the thirty deterministic Launch room scene shells from room templates.

The content JSON remains the authority for ids, anchors, floor eligibility, and
safe zones. This tool only materializes native Godot scene structure and a
stable visual/layout signature for each template.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_PATH = ROOT / "data/content_packs/base/content/room_templates.json"
OUTPUT_DIR = ROOT / "data/content_packs/base/assets/rooms/launch"
PACK_PATH = ROOT / "data/content_packs/base/pack.json"
SCRIPT_PATH = "res://scripts/dungeon/launch_room_scene.gd"


PALETTE = {
    "combat": "Color(0.11, 0.16, 0.22, 1)",
    "elite": "Color(0.20, 0.13, 0.24, 1)",
    "treasure": "Color(0.22, 0.18, 0.08, 1)",
    "shop": "Color(0.12, 0.20, 0.18, 1)",
    "event": "Color(0.16, 0.14, 0.24, 1)",
    "boss": "Color(0.25, 0.10, 0.12, 1)",
    "rest": "Color(0.12, 0.20, 0.14, 1)",
}


def _vec(value: dict) -> str:
    return f"Vector2({int(value['x'])}, {int(value['y'])})"


def _rect(bounds: dict) -> str:
    return (
        f"Rect2({int(bounds['x'])}, {int(bounds['y'])}, "
        f"{int(bounds['width'])}, {int(bounds['height'])})"
    )


def _safe_zone_bounds(template: dict) -> dict:
    for zone in template.get("accessibility_safe_hazard_zones", []):
        if zone.get("id") == "safe_core":
            return zone["bounds"]
    return {"x": 224, "y": 96, "width": 192, "height": 168}


def _hazard_bounds(template: dict, index: int) -> dict:
    safe = _safe_zone_bounds(template)
    candidates = [
        {"x": 32, "y": 32, "width": 128, "height": 48},
        {"x": 480, "y": 32, "width": 128, "height": 48},
        {"x": 32, "y": 280, "width": 128, "height": 48},
        {"x": 480, "y": 280, "width": 128, "height": 48},
        {"x": 40, "y": 128, "width": 72, "height": 104},
        {"x": 528, "y": 128, "width": 72, "height": 104},
    ]
    candidate = candidates[index % len(candidates)]
    # Keep generated hazard cues outside the safe core even when a future
    # template changes the core bounds.
    if (
        candidate["x"] < safe["x"] + safe["width"]
        and candidate["x"] + candidate["width"] > safe["x"]
        and candidate["y"] < safe["y"] + safe["height"]
        and candidate["y"] + candidate["height"] > safe["y"]
    ):
        candidate = {"x": 32, "y": 32, "width": 128, "height": 48}
    return candidate


def render(template: dict, ordinal: int) -> str:
    room_id = template["id"]
    room_type = template["room_type"]
    variant = room_id.removeprefix("room_")
    signature = hashlib.sha256(f"{room_id}:{ordinal}".encode()).hexdigest()[:16]
    color = PALETTE[room_type]
    landmark_x = 208 + (ordinal * 37) % 224
    landmark_y = 96 + (ordinal * 23) % 112
    landmark_width = 32 + (ordinal % 5) * 8
    landmark_height = 40 + (ordinal % 4) * 12
    cue_x = 64 + (ordinal * 41) % 480
    camera = template["camera_bounds"]
    lines = [
        "[gd_scene load_steps=8 format=3]",
        "",
        f'[ext_resource type="Script" path="{SCRIPT_PATH}" id="1_scene"]',
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_camera"]',
        f"size = Vector2({camera['width']}, {camera['height']})",
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_hazard_1"]',
        "size = Vector2(128, 48)",
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_hazard_2"]',
        "size = Vector2(128, 48)",
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_hazard_3"]',
        "size = Vector2(128, 48)",
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_hazard_4"]',
        "size = Vector2(128, 48)",
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_hazard_5"]',
        "size = Vector2(128, 48)",
        "",
        '[sub_resource type="RectangleShape2D" id="RectangleShape2D_hazard_6"]',
        "size = Vector2(128, 48)",
        "",
        '[node name="LaunchRoomScene" type="Node2D"]',
        'script = ExtResource("1_scene")',
        f'content_id = &"{room_id}"',
        f'room_type = "{room_type}"',
        f'metadata/content_id = "{room_id}"',
        f'metadata/room_type = "{room_type}"',
        f'metadata/layout_variant = "{variant}"',
        f'metadata/visual_signature = "{signature}"',
        "",
        '[node name="PixelProxyLayer" type="Node2D" parent="."]',
        f'metadata/visual_signature = "{signature}"',
        "",
        '[node name="Background" type="Polygon2D" parent="PixelProxyLayer"]',
        "polygon = PackedVector2Array(0, 0, 640, 0, 640, 360, 0, 360)",
        f"color = {color}",
        "",
        '[node name="Ground" type="Polygon2D" parent="PixelProxyLayer"]',
        "polygon = PackedVector2Array(0, 264, 640, 264, 640, 360, 0, 360)",
        "color = Color(0.07, 0.09, 0.12, 1)",
        "",
        '[node name="LandmarkPrimary" type="Polygon2D" parent="PixelProxyLayer"]',
        (
            "polygon = PackedVector2Array("
            f"{landmark_x}, {landmark_y + landmark_height}, "
            f"{landmark_x + landmark_width // 2}, {landmark_y}, "
            f"{landmark_x + landmark_width}, {landmark_y + landmark_height})"
        ),
        "color = Color(0.78, 0.72, 0.52, 1)",
        "",
        '[node name="DoorVisualWest" type="Polygon2D" parent="PixelProxyLayer"]',
        "polygon = PackedVector2Array(0, 144, 32, 144, 32, 216, 0, 216)",
        "color = Color(0.68, 0.72, 0.78, 1)",
        "",
        '[node name="DoorVisualEast" type="Polygon2D" parent="PixelProxyLayer"]',
        "polygon = PackedVector2Array(608, 144, 640, 144, 640, 216, 608, 216)",
        "color = Color(0.68, 0.72, 0.78, 1)",
        "",
        '[node name="HazardCue" type="Polygon2D" parent="PixelProxyLayer"]',
        f"polygon = PackedVector2Array({cue_x}, 320, {cue_x + 16}, 296, {cue_x + 32}, 320)",
        "color = Color(0.92, 0.32, 0.28, 1)",
        "",
        '[node name="PlayerEntry" type="Marker2D" parent="."]',
        f"position = {_vec(template['spawn_anchors'][0]['position'])}",
        'metadata/anchor_id = "player_entry"',
        "",
        '[node name="PlayerExit" type="Marker2D" parent="."]',
        f"position = {_vec(next(a for a in template['interaction_anchors'] if a['kind'] == 'exit')['position'])}",
        'metadata/anchor_id = "room_exit"',
        "",
        '[node name="CameraBounds" type="Area2D" parent="."]',
        "position = Vector2(320, 180)",
        'metadata/anchor_id = "camera_bounds"',
        "",
        '[node name="CollisionShape2D" type="CollisionShape2D" parent="CameraBounds"]',
        'shape = SubResource("RectangleShape2D_camera")',
        "",
        '[node name="DoorAnchors" type="Node2D" parent="."]',
    ]
    for door in template.get("door_anchors", []):
        lines.extend(
            [
                f'[node name="{door["id"]}" type="Marker2D" parent="DoorAnchors"]',
                f"position = {_vec(door['position'])}",
                f'metadata/anchor_id = "{door["id"]}"',
                f'metadata/direction = "{door["direction"]}"',
                'metadata/clear_width = 48',
                'metadata/clear_width_pixels = 48',
                "",
            ]
        )
    lines.append('[node name="EncounterAnchors" type="Node2D" parent="."]')
    for spawn in template.get("spawn_anchors", []):
        if spawn["kind"] not in {"enemy", "elite", "boss"}:
            continue
        lines.extend(
            [
                f'[node name="{spawn["id"]}" type="Marker2D" parent="EncounterAnchors"]',
                f"position = {_vec(spawn['position'])}",
                f'metadata/anchor_id = "{spawn["id"]}"',
                f'metadata/kind = "{spawn["kind"]}"',
                "",
            ]
        )
    lines.append('[node name="InteractionAnchors" type="Node2D" parent="."]')
    for anchor in template.get("interaction_anchors", []):
        lines.extend(
            [
                f'[node name="{anchor["id"]}" type="Marker2D" parent="InteractionAnchors"]',
                f"position = {_vec(anchor['position'])}",
                f'metadata/anchor_id = "{anchor["id"]}"',
                f'metadata/kind = "{anchor["kind"]}"',
                "",
            ]
        )
    lines.append('[node name="FloorRuleAnchors" type="Node2D" parent="."]')
    for zone in template.get("accessibility_safe_hazard_zones", []):
        bounds = zone["bounds"]
        lines.extend(
            [
                f'[node name="{zone["id"]}" type="Marker2D" parent="FloorRuleAnchors"]',
                f"position = Vector2({bounds['x'] + bounds['width'] // 2}, {bounds['y'] + bounds['height'] // 2})",
                f'metadata/anchor_id = "{zone["id"]}"',
                f'metadata/bounds = {_rect(bounds)}',
                "",
            ]
        )
    for index in range(6):
        bounds = _hazard_bounds(template, index)
        lines.extend(
            [
                f'[node name="HazardZone{index + 1}" type="Area2D" parent="FloorRuleAnchors"]',
                f"position = Vector2({bounds['x'] + bounds['width'] // 2}, {bounds['y'] + bounds['height'] // 2})",
                f'metadata/zone_id = "{room_id}_hazard_{index + 1}"',
                "",
                f'[node name="CollisionShape2D" type="CollisionShape2D" parent="FloorRuleAnchors/HazardZone{index + 1}"]',
                f'shape = SubResource("RectangleShape2D_hazard_{index + 1}")',
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    templates = json.loads(TEMPLATE_PATH.read_text())
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    asset_paths = ["assets/rooms/launch/launch_room_base.tscn"]
    for ordinal, template in enumerate(templates, start=1):
        path = ROOT / Path(template["scene_path"].removeprefix("res://"))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render(template, ordinal), encoding="utf-8")
        asset_paths.append(path.relative_to(PACK_PATH.parent).as_posix())

    pack = json.loads(PACK_PATH.read_text())
    pack["asset_manifest"] = sorted(asset_paths)
    integrity = pack["integrity_hashes"]
    for asset_path in pack["asset_manifest"]:
        integrity[asset_path] = hashlib.sha256(
            (PACK_PATH.parent / asset_path).read_bytes()
        ).hexdigest()
    declared = set(pack["content_manifest"])
    declared.update(pack["localization_sources"])
    declared.update(pack["asset_manifest"])
    pack["integrity_hashes"] = {
        path: integrity[path] for path in sorted(declared)
    }
    PACK_PATH.write_text(
        json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"generated {len(templates)} Launch room scenes and sealed "
        f"{len(asset_paths)} pack assets"
    )


if __name__ == "__main__":
    main()
