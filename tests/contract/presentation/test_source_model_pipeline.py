from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "production_art"))
import source_model_pipeline as pipeline


def fixture_manifest():
    return {
        "schema_id": "plane_walker_source_model_v1", "schema_version": 1,
        "palette": ["#111619", "#61d5e7", "#edf0dc"],
        "assets": [{
            "id": "wanderer", "kind": "character", "status": "ready",
            "source": {"provider": "local_fixture", "file": "model.glb",
                       "license": "CC0-1.0", "rights_status": "approved"},
            "render": {"frame_size": 48, "pivot": [24, 40],
                       "world_anchor": [0, 0, 0], "camera_direction": [1, -4, 1],
                       "ortho_scale": 3, "resolution": 96, "alpha_threshold": 128},
            "animations": {state: {"frames": [1, 2, 3, 4], "fps": 8}
                           for state in pipeline.STATES},
        }],
    }


class SourceModelPipelineTest(unittest.TestCase):
    def test_catalog_covers_runtime_content_with_explicit_pending_sources(self):
        manifest = pipeline.catalog("all")
        definitions = json.loads((ROOT / "data/content_packs/base/content/enemies.json").read_text())
        enemies = {row["id"] for row in manifest["assets"] if row["kind"] == "enemy"}
        self.assertEqual(enemies, {row["id"] for row in definitions})
        self.assertEqual(len(manifest["assets"]), 32)
        with tempfile.TemporaryDirectory() as directory:
            report = pipeline.inspect_manifest(manifest, Path(directory))
        self.assertFalse(report["ready"])
        self.assertTrue(all(row["status"] == "awaiting_model" for row in report["assets"]))
        self.assertEqual(len(pipeline.catalog("enemy")["assets"]), 22)

    def test_selection_allows_ready_family_without_pending_assets(self):
        manifest = pipeline.catalog("all")
        ready = fixture_manifest()["assets"][0]
        manifest["assets"][0] = ready
        selected = pipeline.select_assets(manifest, ["wanderer"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model.glb").write_bytes(b"fixture")
            self.assertTrue(pipeline.require_ready(selected, root)["ready"])
        selected["assets"][0]["source"]["license"] = "changed"
        self.assertEqual(manifest["assets"][0]["source"]["license"], "CC0-1.0")
        for identities in (["not_an_actor"], ["wanderer", "wanderer"]):
            with self.assertRaises(pipeline.PipelineError):
                pipeline.select_assets(manifest, identities)

    def test_enemy_contract_requires_one_sample_for_each_runtime_phase(self):
        manifest = pipeline.catalog("enemy")
        self.assertEqual(pipeline.states_for(manifest["assets"][0]), pipeline.ENEMY_PHASES)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pipeline.inspect_manifest(manifest, root)
            for mutation in ("states", "count", "kind", "size"):
                candidate = copy.deepcopy(manifest)
                row = candidate["assets"][0]
                if mutation == "states":
                    row["animations"]["attack"] = row["animations"].pop("active")
                elif mutation == "count":
                    row["animations"]["idle"]["frames"] = [1, 2, 3, 4]
                elif mutation == "kind":
                    row["kind"] = "character"
                else:
                    row["render"]["frame_size"] = 32
                with self.subTest(mutation=mutation), self.assertRaises(pipeline.PipelineError):
                    pipeline.inspect_manifest(candidate, root)

    def test_enemy_packing_is_one_row_and_rejects_static_phase_output(self):
        row = pipeline.catalog("enemy")["assets"][0]
        frames = []
        for phase in range(4):
            image = Image.new("RGBA", (48, 48))
            ImageDraw.Draw(image).rectangle((21, 10, 26 + phase, 39), fill=(97, 213, 231, 255))
            frames.append(image)
        with tempfile.TemporaryDirectory() as directory:
            descriptor = pipeline.pack_asset(row, frames, Path(directory))
            self.assertEqual((descriptor["columns"], descriptor["rows"], descriptor["width"], descriptor["height"]), (4, 1, 192, 48))
            self.assertEqual(descriptor["phases"], list(pipeline.ENEMY_PHASES))
            self.assertEqual(descriptor["frame_width"], 48)
            self.assertEqual(len(descriptor["frame_bounds"]), 4)
            with self.assertRaises(pipeline.PipelineError):
                pipeline.pack_asset(row, [frames[0]] * 4, Path(directory))

    def test_build_rejects_mixed_atlas_families_before_rendering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model.glb").write_bytes(b"fixture")
            manifest = fixture_manifest()
            enemy = pipeline.catalog("enemy")["assets"][0]
            enemy["status"] = "ready"
            enemy["source"] = copy.deepcopy(manifest["assets"][0]["source"])
            manifest["assets"].append(enemy)
            path = root / "manifest.json"
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(pipeline.PipelineError, "atlas families"):
                pipeline.build(path, root / "atlas")
            self.assertFalse((root / "atlas").exists())

    def test_manifest_exposes_missing_models_without_claiming_success(self):
        manifest = fixture_manifest()
        manifest["assets"][0]["status"] = "awaiting_model"
        manifest["assets"][0]["source"] = {
            "provider": "tripo", "rights_status": "pending", "file": "missing.glb"}
        with tempfile.TemporaryDirectory() as directory:
            report = pipeline.inspect_manifest(manifest, Path(directory))
            self.assertFalse(report["ready"])
            self.assertEqual(report["assets"][0]["status"], "awaiting_model")
            with self.assertRaisesRegex(pipeline.PipelineError, "awaiting_model"):
                pipeline.require_ready(manifest, Path(directory))

    def test_ready_requires_rights_local_source_and_exact_runtime_states(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model.glb").write_bytes(b"fixture")
            for mutation in ("rights", "path", "states", "id", "size", "sha"):
                manifest = fixture_manifest()
                row = manifest["assets"][0]
                if mutation == "rights":
                    row["source"]["rights_status"] = "pending"
                elif mutation == "path":
                    row["source"]["file"] = "../outside.glb"
                elif mutation == "states":
                    del row["animations"]["death"]
                elif mutation == "id":
                    row["id"] = "../../outside"
                elif mutation == "size":
                    row["render"]["frame_size"] = 64
                else:
                    row["source"]["sha256"] = "0" * 64
                with self.subTest(mutation=mutation), self.assertRaises(pipeline.PipelineError):
                    pipeline.require_ready(manifest, root)

    def test_normalization_preserves_fixed_anchor_and_binary_palette(self):
        image = Image.new("RGBA", (96, 96))
        ImageDraw.Draw(image).rectangle((40, 30, 55, 74), fill=(30, 170, 200, 180))
        result = pipeline.normalize_frame(image, 48, [(97, 213, 231)], 128)
        self.assertEqual(result.size, (48, 48))
        self.assertEqual(result.getchannel("A").getbbox(), (20, 15, 28, 37))
        self.assertEqual(set(result.getchannel("A").get_flattened_data()), {0, 255})
        self.assertEqual(set(result.get_flattened_data()), {(0, 0, 0, 0), (97, 213, 231, 255)})

    def test_packing_matches_actor_contract_and_is_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = fixture_manifest()
            frames = []
            for _ in pipeline.STATES:
                for frame in range(4):
                    image = Image.new("RGBA", (48, 48))
                    ImageDraw.Draw(image).rectangle((21, 10, 26 + frame, 39), fill=(97, 213, 231, 255))
                    frames.append(image)
            one = pipeline.pack_asset(manifest["assets"][0], frames, root)
            before = (root / "wanderer.png").read_bytes()
            two = pipeline.pack_asset(copy.deepcopy(manifest["assets"][0]), frames, root)
            self.assertEqual(one, two)
            self.assertEqual(before, (root / "wanderer.png").read_bytes())
            self.assertEqual((one["columns"], one["rows"], one["width"], one["height"]), (4, 6, 192, 288))
            self.assertEqual(one["pivot"], [24, 40])
            self.assertEqual(one["provenance"]["provider"], "local_fixture")

    def test_blank_clipped_and_wrong_count_cannot_be_packed(self):
        row = fixture_manifest()["assets"][0]
        with tempfile.TemporaryDirectory() as directory:
            static = Image.new("RGBA", (48, 48))
            ImageDraw.Draw(static).rectangle((20, 10, 28, 39), fill=(97, 213, 231, 255))
            for frames in ([Image.new("RGBA", (48, 48))] * 24,
                           [Image.new("RGBA", (48, 48), "red")] * 24,
                           [Image.new("RGBA", (48, 48))] * 23,
                           [static] * 24):
                with self.assertRaises(pipeline.PipelineError):
                    pipeline.pack_asset(row, frames, Path(directory))


@unittest.skipUnless(os.environ.get("SOURCE_MODEL_BLENDER_SMOKE"), "opt-in local Blender smoke")
class SourceModelBlenderSmokeTest(unittest.TestCase):
    def test_actual_enemy_glb_and_fbx_build_with_other_assets_pending(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = pipeline.fixture(root)
            fixture = json.loads(path.read_text())
            manifest = pipeline.catalog("all")
            enemy = next(row for row in manifest["assets"] if row["kind"] == "enemy")
            enemy["status"] = "ready"
            enemy["source"] = fixture["assets"][0]["source"]
            enemy["render"] = fixture["assets"][0]["render"]
            enemy["animations"] = {phase: {"frames": [frame], "fps": 8}
                                   for phase, frame in zip(pipeline.ENEMY_PHASES, (1, 6, 12, 18))}
            for extension in ("glb", "fbx"):
                enemy["source"]["file"] = "local_fixture." + extension
                path.write_text(json.dumps(manifest))
                output = root / extension
                result = pipeline.build(path, output, asset_ids=[enemy["id"]])
                self.assertEqual(result["schema_id"], "plane_walker_launch_enemy_art_v1")
                self.assertEqual(result["phases"], list(pipeline.ENEMY_PHASES))
                self.assertEqual(result["assets"][0]["provenance"]["status"], "technical_preview")
                self.assertEqual(result["provenance"]["selected_assets"], [enemy["id"]])
                with Image.open(output / (enemy["id"] + ".png")) as atlas:
                    self.assertEqual(atlas.size, (192, 48))
                    self.assertEqual(set(atlas.getchannel("A").get_flattened_data()), {0, 255})

    def test_actual_glb_import_transparent_render_and_runtime_pack(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = pipeline.fixture(root)
            result = pipeline.build(manifest_path, root / "atlas")
            self.assertEqual(result["schema_id"], "plane_walker_actor_atlas_v1")
            self.assertEqual(result["assets"][0]["provenance"]["provider"], "local_fixture")
            self.assertEqual(result["assets"][0]["provenance"]["status"], "technical_preview")
            self.assertEqual(result["assets"][0]["pivot"], [24, 40])
            self.assertEqual(len(result["assets"][0]["provenance"]["sha256"]), 64)
            with Image.open(root / "atlas" / "wanderer.png") as atlas:
                self.assertEqual(atlas.size, (192, 288))
                self.assertEqual(set(atlas.getchannel("A").get_flattened_data()), {0, 255})
                for state in range(6):
                    frames = {atlas.crop((x * 48, state * 48, (x + 1) * 48, (state + 1) * 48)).tobytes() for x in range(4)}
                    self.assertGreaterEqual(len(frames), 3)
            fbx_manifest = json.loads(manifest_path.read_text())
            fbx_manifest["assets"][0]["source"]["file"] = "local_fixture.fbx"
            fbx_path = root / "fbx-manifest.json"
            fbx_path.write_text(json.dumps(fbx_manifest))
            fbx_result = pipeline.build(fbx_path, root / "fbx-atlas")
            self.assertEqual(fbx_result["assets"][0]["width"], 192)

    def test_blender_missing_action_fails_without_promoting_atlas(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_path = pipeline.fixture(root)
            manifest = json.loads(manifest_path.read_text())
            manifest["assets"][0]["animations"]["idle"]["action"] = "MissingAction"
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(pipeline.PipelineError, "Blender render failed"):
                pipeline.build(manifest_path, root / "atlas")
            self.assertFalse((root / "atlas" / "wanderer.png").exists())
            self.assertIn("animation action not found", (root / "atlas" / "blender.log").read_text())


if __name__ == "__main__":
    unittest.main()
