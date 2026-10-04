from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools/export"))

from portable_runtime import classified_log_failures, prepare_self_contained_editor  # noqa: E402


class ContentPackSourceExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        command = os.environ.get("GODOT_BIN", "godot")
        source = shutil.which(command)
        if source is None:
            raise unittest.SkipTest("Godot is unavailable for real export contracts")
        cls.editor = prepare_self_contained_editor(PROJECT_ROOT, Path(source))

    def fixture(self, root: Path) -> tuple[Path, dict]:
        shutil.copytree(PROJECT_ROOT / "addons/content_pack_source_export", root / "addons/content_pack_source_export")
        scripts = root / "scripts/content"
        scripts.mkdir(parents=True)
        shutil.copy2(PROJECT_ROOT / "scripts/content/content_pack_descriptor.gd", scripts)
        (root / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Plane Walker: Chronicles of Collapse"\n'
            'run/main_scene="res://main.tscn"\n[editor_plugins]\n'
            'enabled=PackedStringArray("res://addons/content_pack_source_export/plugin.cfg")\n',
            encoding="utf-8",
        )
        shutil.copy2(PROJECT_ROOT / "export_presets.cfg", root / "export_presets.cfg")
        pack = root / "data/content_packs/base"
        pack.mkdir(parents=True)
        shutil.copy2(PROJECT_ROOT / "data/content_packs/base/assets/enemies/launch/acid_pool.png", pack / "actor.png")
        (pack / "actor.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n'
            '[ext_resource type="Texture2D" path="res://data/content_packs/base/actor.png" id="1"]\n'
            '[node name="Actor" type="Sprite2D"]\ntexture = ExtResource("1")\n',
            encoding="utf-8",
        )
        (pack / "content.json").write_text('{}\n', encoding="utf-8")
        (pack / "translations.csv").write_text('key,en,zh_CN\nEXPORT_TEST,Test,Test\n', encoding="utf-8")
        descriptor = {
            "pack_id": "base", "pack_version": "0.4.0-dev", "schema_version": 2,
            "game_version_range": ">=0.4.0-dev <1.0.0", "dependencies": [], "load_order": 0,
            "content_manifest": ["content.json"], "localization_sources": ["translations.csv"],
            "asset_manifest": ["actor.png", "actor.tscn"], "entitlement_tag": "",
            "integrity_hashes": {
                name: hashlib.sha256((pack / name).read_bytes()).hexdigest()
                for name in ["content.json", "translations.csv", "actor.png", "actor.tscn"]
            },
        }
        self.write_descriptor(pack, descriptor)
        (root / "main.gd").write_text(
            'extends Node\nconst Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")\n'
            'func _ready() -> void:\n'
            '\tvar result := Descriptor.load_path("res://data/content_packs/base/pack.json", true)\n'
            '\tvar texture := load("res://data/content_packs/base/actor.png") as Texture2D\n'
            '\tvar scene := load("res://data/content_packs/base/actor.tscn") as PackedScene\n'
            '\tif not result.ok or texture == null or scene == null:\n'
            '\t\tpush_error("PACKED_AUTHENTICATION_FAILED: " + str(result))\n'
            '\t\tget_tree().quit(1)\n\t\treturn\n'
            '\tprint("PACKED_AUTHENTICATION_PASS")\n\tget_tree().quit()\n',
            encoding="utf-8",
        )
        (root / "main.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n'
            '[ext_resource type="Script" path="res://main.gd" id="1"]\n'
            '[node name="ExportProbe" type="Node"]\nscript = ExtResource("1")\n',
            encoding="utf-8",
        )
        return pack, descriptor

    @staticmethod
    def write_descriptor(pack: Path, descriptor: dict) -> None:
        (pack / "pack.json").write_text(json.dumps(descriptor, indent=2) + "\n", encoding="utf-8")

    def run_godot(self, root: Path, arguments: list[str], name: str) -> tuple[subprocess.CompletedProcess, list[dict]]:
        log = root / f"{name}.log"
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = str(root / "user-data")
        environment["PLANEWALKER_TEST_DATA_DIR"] = str(root / "user-data/files")
        result = subprocess.run(
            [str(self.editor), "--headless", *arguments, "--log-file", str(log)],
            cwd=root, env=environment, capture_output=True, text=True, timeout=90, check=False,
        )
        failures, _environmental = classified_log_failures([log])
        return result, failures

    def test_real_pck_preserves_authenticated_png_scene_and_csv_with_native_loaders(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            archive = root / "game.pck"
            exported, failures = self.run_godot(root, ["--path", str(root), "--export-pack", "macOS Debug", str(archive)], "export")
            self.assertEqual(exported.returncode, 0, exported.stdout + exported.stderr)
            self.assertEqual(failures, [], exported.stdout + exported.stderr)
            self.assertIn("CONTENT_PACK_SOURCE_EXPORT: authenticated source files=4", exported.stdout)
            runtime = root / "isolated-runtime"
            runtime.mkdir()
            started, failures = self.run_godot(runtime, ["--path", str(runtime), "--main-pack", str(archive)], "runtime")
            self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
            self.assertEqual(failures, [], started.stdout + started.stderr)
            self.assertIn("PACKED_AUTHENTICATION_PASS", started.stdout)

    def test_changed_declared_bytes_fail_export_log_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack, _descriptor = self.fixture(root)
            (pack / "content.json").write_text('{"changed": true}\n', encoding="utf-8")
            exported, failures = self.run_godot(root, ["--path", str(root), "--export-pack", "macOS Debug", str(root / "game.pck")], "export")
            self.assertTrue(any("Content pack integrity" in row["line"] for row in failures), exported.stdout + exported.stderr)
            self.assertIn("INTEGRITY_MISMATCH", exported.stdout + exported.stderr)
            self.assertNotIn("CONTENT_PACK_SOURCE_EXPORT: authenticated", exported.stdout)

    def test_escaping_declared_path_fails_export_log_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack, descriptor = self.fixture(root)
            descriptor["asset_manifest"].append("../outside.txt")
            descriptor["integrity_hashes"]["../outside.txt"] = "0" * 64
            self.write_descriptor(pack, descriptor)
            exported, failures = self.run_godot(root, ["--path", str(root), "--export-pack", "macOS Debug", str(root / "game.pck")], "export")
            self.assertTrue(any("Content pack integrity" in row["line"] for row in failures), exported.stdout + exported.stderr)
            self.assertIn("invalid_path", exported.stdout + exported.stderr)
            self.assertNotIn("CONTENT_PACK_SOURCE_EXPORT: authenticated", exported.stdout)


if __name__ == "__main__":
    unittest.main()
