#!/usr/bin/env python3
"""Local model-to-pixel-atlas pipeline. No provider calls or account credentials."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

STATES = ("idle", "move", "attack", "cast", "hurt", "death")
CHARACTERS = ("wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord")
BOSSES = ("ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne")
STATUSES = ("ready", "awaiting_model", "awaiting_animation", "license_pending")


class PipelineError(ValueError):
    pass


def _check(condition, message):
    if not condition:
        raise PipelineError(message)


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _local_file(root, filename):
    _check(isinstance(filename, str) and filename, "source file must be a relative path")
    path = Path(filename)
    _check(not path.is_absolute() and ".." not in path.parts, "source path escapes manifest directory")
    resolved = (root / path).resolve()
    _check(resolved.is_relative_to(root.resolve()), "source symlink escapes manifest directory")
    _check(resolved.suffix.lower() in (".glb", ".gltf", ".fbx", ".blend"), "unsupported source format")
    return resolved


def _validate_source(source, root, ready):
    _check(isinstance(source, dict), "source descriptor is required")
    _check(source.get("provider") in ("tripo", "mixamo", "local_fixture", "local_authored"), "unknown provider")
    path = _local_file(root, source.get("file"))
    if ready:
        _check(source.get("rights_status") == "approved" and bool(source.get("license")), "ready source requires approved rights and license")
        if source["provider"] in ("tripo", "mixamo"):
            _check(bool(source.get("terms_url")) and bool(source.get("acquired_at")), "external source requires terms URL and acquisition date")
        _check(path.is_file() and path.stat().st_size > 0, f"source model missing: {path.name}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if "sha256" in source:
            _check(source["sha256"] == digest, f"source sha256 mismatch: {path.name}")
    return path


def inspect_manifest(manifest, root):
    _check(isinstance(manifest, dict), "manifest must be an object")
    _check(manifest.get("schema_id") == "plane_walker_source_model_v1" and manifest.get("schema_version") == 1, "unsupported source model schema")
    palette = manifest.get("palette")
    _check(isinstance(palette, list) and 1 <= len(palette) <= 64, "palette requires 1 to 64 hex colors")
    for value in palette:
        _check(isinstance(value, str) and len(value) == 7 and value[0] == "#", "invalid palette color")
        try:
            int(value[1:], 16)
        except ValueError as error:
            raise PipelineError("invalid palette color") from error
    _check(len(set(palette)) == len(palette), "palette colors must be unique")
    assets = manifest.get("assets")
    _check(isinstance(assets, list) and assets, "manifest requires assets")
    seen, report = set(), []
    for row in assets:
        _check(isinstance(row, dict), "asset must be an object")
        identity, kind = row.get("id"), row.get("kind")
        _check(identity in CHARACTERS + BOSSES and identity not in seen, "unknown or duplicate actor id")
        seen.add(identity)
        expected_size = 48 if identity in CHARACTERS else 80
        _check(kind == ("character" if expected_size == 48 else "boss"), "actor kind does not match runtime")
        status = row.get("status")
        _check(status in STATUSES, "unknown asset status")
        _validate_source(row.get("source"), root, status == "ready")
        render = row.get("render", {})
        _check(isinstance(render, dict), "render must be an object")
        _check(render.get("frame_size") == expected_size, "frame size must match runtime actor contract")
        resolution = render.get("resolution")
        _check(type(resolution) is int and expected_size <= resolution <= 2048 and resolution % expected_size == 0, "render resolution must be an integer multiple of frame size")
        _check(_number(render.get("ortho_scale")) and 0 < render["ortho_scale"] <= 1000, "ortho_scale must be positive")
        for key in ("world_anchor", "camera_direction"):
            vector = render.get(key)
            _check(isinstance(vector, list) and len(vector) == 3 and all(_number(n) for n in vector), f"invalid {key}")
        _check(sum(n * n for n in render["camera_direction"]) > 0, "camera direction must be nonzero")
        pivot = render.get("pivot")
        _check(isinstance(pivot, list) and len(pivot) == 2 and all(type(n) is int and 0 < n < expected_size for n in pivot), "pivot must lie inside frame")
        _check(type(render.get("alpha_threshold")) is int and 1 <= render["alpha_threshold"] <= 255, "alpha_threshold must be between 1 and 255")
        animations = row.get("animations")
        _check(isinstance(animations, dict) and set(animations) == set(STATES), "all six runtime states are required")
        for state in STATES:
            clip = animations[state]
            _check(isinstance(clip, dict), f"invalid {state} clip")
            frames = clip.get("frames")
            _check(isinstance(frames, list) and len(frames) == 4 and all(type(n) is int and 0 <= n <= 100000 for n in frames), f"{state} requires four frame samples")
            _check(type(clip.get("fps")) is int and 1 <= clip["fps"] <= 30, f"invalid {state} fps")
            if "action" in clip:
                _check(isinstance(clip["action"], str) and bool(clip["action"]), f"invalid {state} action")
            if "source" in clip:
                _validate_source(clip["source"], root, status == "ready")
                _check(bool(clip.get("action")), "separate animation source requires an exact action name")
        report.append({"id": identity, "status": status, "provider": row["source"]["provider"]})
    return {"ready": all(row["status"] == "ready" for row in report), "assets": report}


def require_ready(manifest, root):
    report = inspect_manifest(manifest, root)
    for row in report["assets"]:
        _check(row["status"] == "ready", f"{row['id']}: {row['status']}")
    return report


def normalize_frame(image, size, palette, alpha_threshold):
    from PIL import Image

    _check(image.width == image.height and image.width % size == 0, "unexpected rendered dimensions")
    resized = image.convert("RGBA").resize((size, size), Image.Resampling.NEAREST)
    cache = {}
    pixels = []
    for pixel in resized.get_flattened_data():
        if pixel[3] < alpha_threshold:
            pixels.append((0, 0, 0, 0))
            continue
        color = pixel[:3]
        if color not in cache:
            cache[color] = min(palette, key=lambda candidate: sum((a - b) ** 2 for a, b in zip(color, candidate)))
        pixels.append(tuple(cache[color]) + (255,))
    result = Image.new("RGBA", (size, size))
    result.putdata(pixels)
    return result


def pack_asset(row, frames, output):
    from PIL import Image

    size = row["render"]["frame_size"]
    _check(len(frames) == 24, "actor atlas requires exactly 24 frames")
    for index, state in enumerate(STATES):
        _check(len({frame.tobytes() for frame in frames[index * 4:index * 4 + 4]}) >= 3, f"{state} needs at least three distinct poses")
    atlas = Image.new("RGBA", (size * 4, size * 6))
    bounds = []
    for index, image in enumerate(frames):
        _check(image.mode == "RGBA" and image.size == (size, size), "unexpected normalized frame")
        bbox = image.getchannel("A").getbbox()
        _check(bbox is not None, f"blank frame: {index}")
        _check(set(image.getchannel("A").get_flattened_data()) <= {0, 255}, "frame alpha must be binary")
        _check(0 < bbox[0] and 0 < bbox[1] and bbox[2] < size and bbox[3] < size, f"clipped frame: {index}; enlarge ortho_scale")
        bounds.append(list(bbox))
        atlas.paste(image, ((index % 4) * size, (index // 4) * size))
    output.mkdir(parents=True, exist_ok=True)
    path = output / f"{row['id']}.png"
    atlas.save(path, optimize=False)
    return {
        "id": row["id"], "kind": row["kind"], "path": path.name,
        "columns": 4, "rows": 6, "frames_per_state": 4,
        "frame_width": size, "frame_height": size,
        "width": size * 4, "height": size * 6, "facing": "right", "filter": "nearest",
        "fps": {state: row["animations"][state]["fps"] for state in STATES},
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "pivot": row["render"]["pivot"], "frame_bounds": bounds,
        "provenance": {**row["source"], "kind": "model_rendered_pixel_art", "status": "technical_preview",
                       "animations": row["animations"]},
    }


def _import_model(path):
    import bpy

    before = set(bpy.data.objects)
    if path.suffix.lower() == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    elif path.suffix.lower() in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    else:
        with bpy.data.libraries.load(str(path), link=False) as (source, target):
            target.objects = source.objects
        for obj in target.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
    return list(set(bpy.data.objects) - before)


def _find_action(objects, name):
    candidates = []
    for obj in objects:
        if not obj.animation_data:
            continue
        actions = {obj.animation_data.action} if obj.animation_data.action else set()
        actions.update(strip.action for track in obj.animation_data.nla_tracks for strip in track.strips if strip.action)
        for action in actions:
            # Blender appends a numeric suffix when a later import reuses a name.
            base, separator, suffix = action.name.rpartition(".")
            if action.name == name or (separator and suffix.isdigit() and base == name):
                candidates.append((obj, action))
    _check(len(candidates) == 1, f"animation action not found or ambiguous: {name}")
    return candidates[0]


def _apply_action(obj, action):
    obj.animation_data_create()
    for track in obj.animation_data.nla_tracks:
        track.mute = True
    obj.animation_data.action = action
    if hasattr(action, "slots") and len(action.slots):
        obj.animation_data.action_slot = action.slots[0]


def _render_blender(manifest_path, output):
    import bpy
    from bpy_extras.object_utils import world_to_camera_view
    from mathutils import Vector

    manifest = json.loads(manifest_path.read_text())
    root = manifest_path.parent
    require_ready(manifest, root)
    for row in manifest["assets"]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        objects = _import_model(_local_file(root, row["source"]["file"]))
        _check(any(obj.type == "MESH" for obj in objects), "source has no mesh")
        for obj in objects:
            if obj.type in ("CAMERA", "LIGHT"):
                obj.hide_render = True
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 8
        scene.cycles.seed = 0
        scene.cycles.use_animated_seed = False
        scene.render.film_transparent = True
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA"
        config = row["render"]
        scene.render.resolution_x = scene.render.resolution_y = config["resolution"]
        scene.render.resolution_percentage = 100
        scene.view_settings.view_transform = "Standard"
        camera_data = bpy.data.cameras.new("PipelineCamera")
        camera_data.type, camera_data.ortho_scale = "ORTHO", config["ortho_scale"]
        camera = bpy.data.objects.new("PipelineCamera", camera_data)
        scene.collection.objects.link(camera)
        anchor = Vector(config["world_anchor"])
        direction = Vector(config["camera_direction"]).normalized()
        camera.location = anchor + direction * max(config["ortho_scale"] * 4, 10)
        camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        scene.camera = camera
        target = (config["pivot"][0] / config["frame_size"], 1 - config["pivot"][1] / config["frame_size"])
        # Project the shared world anchor once; never recenter individual poses.
        for _ in range(3):
            bpy.context.view_layer.update()
            projected = world_to_camera_view(scene, camera, anchor)
            camera_data.shift_x += projected.x - target[0]
            camera_data.shift_y += projected.y - target[1]
        bpy.context.view_layer.update()
        projected = world_to_camera_view(scene, camera, anchor)
        _check(abs(projected.x - target[0]) < 1e-4 and abs(projected.y - target[1]) < 1e-4, "camera pivot projection failed")
        for name, location, power, diameter in (
            ("Key", (3, -4, 7), 500, 4), ("Fill", (-4, -1, 3), 250, 5)):
            light_data = bpy.data.lights.new(name, "AREA")
            light_data.energy, light_data.size = power, diameter
            light = bpy.data.objects.new(name, light_data)
            scene.collection.objects.link(light)
            light.location = location
            light.rotation_euler = (anchor - light.location).to_track_quat("-Z", "Y").to_euler()
        destination = output / row["id"]
        destination.mkdir(parents=True, exist_ok=True)
        for state in STATES:
            clip = row["animations"][state]
            imported_animation = []
            if "source" in clip:
                _check(clip["source"]["file"] != row["source"]["file"], "use action only for animations embedded in the base model")
                imported_animation = _import_model(_local_file(root, clip["source"]["file"]))
                source_rigs = [obj for obj in imported_animation if obj.type == "ARMATURE"]
                target_rigs = [obj for obj in objects if obj.type == "ARMATURE"]
                _check(len(source_rigs) == len(target_rigs) == 1, "animation transfer needs exactly one source and target armature")
                _check(set(source_rigs[0].data.bones.keys()) == set(target_rigs[0].data.bones.keys()), "bone mismatch; full retargeting is not supported")
                _check(all(sum((a - c) ** 2 for source_row, target_row in zip(source_rigs[0].data.bones[b.name].matrix_local, b.matrix_local) for a, c in zip(source_row, target_row)) < 1e-10 for b in target_rigs[0].data.bones), "rest pose mismatch; full retargeting is not supported")
                owner, action = _find_action(imported_animation, clip["action"])
                _check(owner == source_rigs[0], "separate clip must animate the source armature")
                _apply_action(target_rigs[0], action)
                for obj in imported_animation:
                    obj.hide_render = True
            elif "action" in clip:
                owner, action = _find_action(objects, clip["action"])
                _apply_action(owner, action)
            for index, frame in enumerate(clip["frames"]):
                scene.frame_set(frame)
                scene.render.filepath = str(destination / f"{state}_{index}.png")
                bpy.ops.render.render(write_still=True)
            for obj in imported_animation:
                bpy.data.objects.remove(obj, do_unlink=True)


def build(manifest_path, output, blender="blender"):
    from PIL import Image

    manifest_path = manifest_path.resolve()
    manifest = json.loads(manifest_path.read_text())
    require_ready(manifest, manifest_path.parent)
    sources = [row["source"] for row in manifest["assets"]]
    sources.extend(clip["source"] for row in manifest["assets"] for clip in row["animations"].values() if "source" in clip)
    source_hashes = {source["file"]: hashlib.sha256(_local_file(manifest_path.parent, source["file"]).read_bytes()).hexdigest() for source in sources}
    binary = shutil.which(blender)
    _check(binary is not None, "Blender CLI unavailable")
    palette = [tuple(bytes.fromhex(color[1:])) for color in manifest["palette"]]
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="source-model-", dir=output) as directory:
        stage = Path(directory)
        command = [binary, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1",
                   "--python", str(Path(__file__).resolve()), "--", "_render", str(manifest_path), str(stage / "raw")]
        result = subprocess.run(command, capture_output=True, text=True, timeout=600)
        (output / "blender.log").write_text(result.stdout + result.stderr)
        _check(result.returncode == 0 and "Traceback (most recent call last)" not in result.stdout + result.stderr, "Blender render failed; see blender.log")
        for source in sources:
            digest = hashlib.sha256(_local_file(manifest_path.parent, source["file"]).read_bytes()).hexdigest()
            _check(digest == source_hashes[source["file"]], "source file changed during rendering")
            source["sha256"] = digest
        descriptors = []
        for row in manifest["assets"]:
            frames = []
            for state in STATES:
                for index in range(4):
                    with Image.open(stage / "raw" / row["id"] / f"{state}_{index}.png") as image:
                        frames.append(normalize_frame(image, row["render"]["frame_size"], palette, row["render"]["alpha_threshold"]))
            descriptors.append(pack_asset(row, frames, stage / "packed"))
        result_manifest = {"schema_id": "plane_walker_actor_atlas_v1", "schema_version": 1,
                           "states": list(STATES), "assets": descriptors,
                           "provenance": {"kind": "model_rendered_pixel_art", "status": "technical_preview",
                                          "source_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest()}}
        (stage / "packed" / "manifest.json").write_text(json.dumps(result_manifest, indent=2, sort_keys=True) + "\n")
        for path in (stage / "packed").iterdir():
            shutil.copy2(path, output / path.name)
    return result_manifest


def _fixture_blender(output):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    material = bpy.data.materials.new("LocalFixtureTeal")
    material.diffuse_color = (0.2, 0.7, 0.75, 1)
    pieces = []
    for name, position, scale in (
        ("Body", (0, 0, 0.95), (0.3, 0.18, 0.45)),
        ("Head", (0, 0, 1.65), (0.22, 0.18, 0.25)),
        ("LeftLeg", (-0.18, 0, 0.25), (0.1, 0.16, 0.25)),
        ("RightLeg", (0.18, 0, 0.25), (0.1, 0.16, 0.25))):
        bpy.ops.mesh.primitive_cube_add(size=2, location=position)
        obj = bpy.context.object
        obj.name, obj.scale = name, scale
        obj.data.materials.append(material)
        pieces.append(obj)
    head = pieces[1]
    for frame in range(1, 25):
        head.rotation_euler.y = ((frame - 1) % 4 - 1.5) * 0.15
        head.keyframe_insert(data_path="rotation_euler", frame=frame)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, 24
    bpy.ops.export_scene.fbx(filepath=str(output / "local_fixture.fbx"), bake_anim=True, bake_anim_use_all_actions=True)
    bpy.ops.export_scene.gltf(filepath=str(output / "local_fixture.glb"), export_format="GLB", export_animations=True)


def fixture(output, blender="blender"):
    output.mkdir(parents=True, exist_ok=True)
    command = [blender, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1",
               "--python", str(Path(__file__).resolve()), "--", "_fixture", str(output.resolve())]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    _check(result.returncode == 0, "fixture GLB creation failed: " + result.stderr[-1000:])
    manifest = {
        "schema_id": "plane_walker_source_model_v1", "schema_version": 1,
        "palette": ["#111619", "#1b2224", "#374342", "#697771", "#61d5e7", "#2c8da0", "#edf0dc"],
        "assets": [{
            "id": "wanderer", "kind": "character", "status": "ready",
            "source": {"provider": "local_fixture", "file": "local_fixture.glb", "license": "CC0-1.0", "rights_status": "approved",
                       "note": "Procedural cubes authored locally for pipeline testing; not a Tripo or Mixamo product."},
            "render": {"frame_size": 48, "resolution": 96, "pivot": [24, 40], "alpha_threshold": 128,
                       "world_anchor": [0, 0, 0], "camera_direction": [1, -4, 1], "ortho_scale": 3},
            "animations": {state: {"frames": list(range(i * 4 + 1, i * 4 + 5)), "fps": 8} for i, state in enumerate(STATES)},
        }],
    }
    path = output / "fixture-manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "build"):
        command = commands.add_parser(name)
        command.add_argument("manifest", type=Path)
        if name == "build":
            command.add_argument("--output", type=Path, required=True)
            command.add_argument("--blender", default="blender")
    command = commands.add_parser("fixture")
    command.add_argument("--output", type=Path, required=True)
    command.add_argument("--blender", default="blender")
    args = parser.parse_args(argv)
    if args.command == "inspect":
        result = inspect_manifest(json.loads(args.manifest.read_text()), args.manifest.resolve().parent)
    elif args.command == "fixture":
        result = {"manifest": str(fixture(args.output, args.blender))}
    else:
        result = build(args.manifest, args.output, args.blender)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        if "--" in sys.argv and sys.argv[sys.argv.index("--") + 1] == "_render":
            arguments = sys.argv[sys.argv.index("--") + 2:]
            _render_blender(Path(arguments[0]), Path(arguments[1]))
        elif "--" in sys.argv and sys.argv[sys.argv.index("--") + 1] == "_fixture":
            _fixture_blender(Path(sys.argv[-1]))
        else:
            main()
    except (PipelineError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        print(f"source-model pipeline: {error}", file=sys.stderr)
        raise SystemExit(1) from error
