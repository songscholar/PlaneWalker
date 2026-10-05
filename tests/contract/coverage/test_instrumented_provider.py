from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PROVIDER_PATH = ROOT / "tools/coverage/instrumented_provider.py"
provider = None
if PROVIDER_PATH.is_file():
    spec = importlib.util.spec_from_file_location("instrumented_provider", PROVIDER_PATH)
    provider = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(provider)


class InstrumentedProviderTest(unittest.TestCase):
    def require_provider(self):
        self.assertIsNotNone(provider, "runtime AST instrumentation provider must exist")
        return provider

    def test_parallel_runtime_hits_retain_every_worker_and_main_thread_line(self):
        editor = shutil.which(os.environ.get("GODOT_BIN", "godot"))
        self.assertIsNotNone(editor, "real Godot threads must exercise the coverage collector")
        temporary_parent = ROOT / "build/coverage-fixtures"
        temporary_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_parent) as temporary:
            root = Path(temporary)
            probe = root / "tools/coverage/line_probe.gd"
            probe.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "tools/coverage/line_probe.gd", probe)
            (root / "project.godot").write_text(
                'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n'
                '[autoload]\nPWLineCoverageProbe="*res://tools/coverage/line_probe.gd"\n',
                encoding="utf-8",
            )
            (root / "concurrent.gd").write_text(
                'extends Node\n'
                'const Probe = preload("res://tools/coverage/line_probe.gd")\n'
                'func _ready() -> void:\n\tcall_deferred("_run")\n'
                'func _run() -> void:\n'
                '\tvar threads: Array[Thread] = []\n'
                '\tfor worker: int in range(4):\n'
                '\t\tvar thread := Thread.new()\n'
                '\t\tthread.start(_mark.bind(worker))\n'
                '\t\tthreads.append(thread)\n'
                '\t_mark(4)\n'
                '\tfor thread: Thread in threads:\n\t\tthread.wait_to_finish()\n'
                '\tvar count: int = Probe._hits.get("scripts/parallel.gd", {}).size()\n'
                '\tprint("PARALLEL_HIT_COUNT ", count)\n'
                '\tget_tree().quit(0 if count == 20000 else 1)\n'
                'func _mark(worker: int) -> void:\n'
                '\tfor line: int in range(4000):\n'
                '\t\tProbe.mark("scripts/parallel.gd", worker * 4000 + line + 1)\n',
                encoding="utf-8",
            )
            (root / "main.tscn").write_text(
                '[gd_scene load_steps=2 format=3]\n'
                '[ext_resource type="Script" path="res://concurrent.gd" id="1"]\n'
                '[node name="ConcurrentCoverage" type="Node"]\nscript = ExtResource("1")\n',
                encoding="utf-8",
            )
            hits = root / "runtime-hits"
            environment = dict(os.environ)
            environment["PLANEWALKER_COVERAGE_HITS_DIR"] = str(hits)
            result = subprocess.run(
                [editor, "--headless", "--path", str(root), "--log-file", str(root / "engine.log")],
                cwd=root, env=environment, text=True, capture_output=True, timeout=30, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for failure in ["ERROR:", "ObjectDB instances leaked", "RID allocations leaked"]:
                self.assertNotIn(failure, result.stdout + result.stderr)
            reports = list(hits.glob("*.json"))
            self.assertEqual(len(reports), 1)
            recorded = json.loads(reports[0].read_text())["hits"]["scripts/parallel.gd"]
            self.assertEqual(recorded, list(range(1, 20001)))

    def test_real_runtime_covers_executed_lines_and_preserves_typed_initializers(self):
        api = self.require_provider()
        editor = shutil.which(os.environ.get("GODOT_BIN", "godot"))
        self.assertIsNotNone(editor, "a real Godot is required for runtime line-hit evidence")
        transformed = api.instrument_source(FIXTURE, "scripts/fixture.gd", ROOT / "build/toolchain/coverage-parser-cache")
        self.assertEqual(transformed["source_sha256"], hashlib.sha256(FIXTURE.encode()).hexdigest())
        self.assertNotEqual(transformed["source"], FIXTURE)
        temporary_parent = ROOT / "build/coverage-fixtures"
        temporary_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_parent) as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            (root / "scripts/fixture.gd").write_text(transformed["source"], encoding="utf-8")
            probe = root / "tools/coverage/line_probe.gd"
            probe.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "tools/coverage/line_probe.gd", probe)
            (root / "project.godot").write_text(
                'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n'
                '[autoload]\nPWLineCoverageProbe="*res://tools/coverage/line_probe.gd"\n',
                encoding="utf-8",
            )
            (root / "main.tscn").write_text(
                '[gd_scene load_steps=2 format=3]\n'
                '[ext_resource type="Script" path="res://scripts/fixture.gd" id="1"]\n'
                '[node name="CoverageFixture" type="Node"]\nscript = ExtResource("1")\n',
                encoding="utf-8",
            )
            hits = root / "runtime-hits"
            environment = dict(os.environ)
            environment["PLANEWALKER_COVERAGE_HITS_DIR"] = str(hits)
            environment["PLANEWALKER_COVERAGE_MANIFEST_SHA256"] = api.manifest_digest({"scripts/fixture.gd": transformed})
            result = subprocess.run(
                [editor, "--headless", "--path", str(root), "--log-file", str(root / "engine.log")],
                cwd=root, env=environment, text=True, capture_output=True, timeout=30, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("COVERAGE_FIXTURE_PRESERVED", result.stdout)
            for failure in ["SCRIPT ERROR:", "Parse Error:", "ObjectDB instances leaked", "RID allocations leaked"]:
                self.assertNotIn(failure, result.stdout + result.stderr)
            raw = api.aggregate_reports({"scripts/fixture.gd": transformed}, hits)
        row = raw["files"][0]
        expected_missing = [_line("return 9"), _line("return 99"), _line("return amount * 99")]
        for line in expected_missing:
            self.assertIn(line, row["executable_lines"])
            self.assertNotIn(line, row["covered_lines"])
        for source in ["var initial := 3", "var values := [1, 2]", "static var static_value := 4", "total += 2", "total += 1", "total += number", "return amount + 1", "return callback.call(total)"]:
            self.assertIn(_line(source), row["covered_lines"], source)
        self.assertEqual(row["source_sha256"], hashlib.sha256(FIXTURE.encode()).hexdigest())

    def test_invalid_syntax_and_reserved_counter_identity_fail_before_execution(self):
        api = self.require_provider()
        for source in ["func broken(\n", "extends Node\nconst _PWLineCoverageProbeV1 := 1\n"]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                api.instrument_source(source, "scripts/fixture.gd", ROOT / "build/toolchain/coverage-parser-cache")

    def test_forged_runtime_hits_cannot_claim_unknown_original_lines(self):
        api = self.require_provider()
        transformed = api.instrument_source(FIXTURE, "scripts/fixture.gd", ROOT / "build/toolchain/coverage-parser-cache")
        with tempfile.TemporaryDirectory() as temporary:
            hits = Path(temporary)
            manifest = {"scripts/fixture.gd": transformed}
            cases = [
                (api.manifest_digest(manifest), {"scripts/fixture.gd": [999999]}),
                (api.manifest_digest(manifest), {"scripts/fixture.gd": [_line("return 99")] * 2}),
                (api.manifest_digest(manifest), {"scripts/unknown.gd": [1]}),
                ("0" * 64, {}),
            ]
            for digest, recorded in cases:
                (hits / "forged.json").write_text(json.dumps({
                    "schema_version": 1, "manifest_sha256": digest, "hits": recorded,
                }), encoding="utf-8")
                with self.subTest(recorded=recorded), self.assertRaises(ValueError):
                    api.aggregate_reports(manifest, hits)

    def test_isolated_runner_retains_real_hits_without_changing_original_sources(self):
        api = self.require_provider()
        temporary_parent = ROOT / "build/coverage-fixtures"
        temporary_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_parent) as temporary:
            root = Path(temporary) / "project"
            (root / "scripts").mkdir(parents=True)
            (root / "tests").mkdir()
            (root / "tools/coverage").mkdir(parents=True)
            inherited_fixture = FIXTURE.replace("extends Node", 'extends "res://scripts/base.gd"', 1).replace("func _ready() -> void:\n", "func _ready() -> void:\n    super._ready()\n")
            (root / "scripts/fixture.gd").write_text(inherited_fixture, encoding="utf-8")
            (root / "scripts/base.gd").write_text('extends Node\nfunc _ready() -> void:\n    print("COVERAGE_BASE_READY")\n', encoding="utf-8")
            (root / "scripts/never_loaded.gd").write_text("extends RefCounted\nfunc unused() -> int:\n    return 101\n", encoding="utf-8")
            (root / "autoload").mkdir()
            (root / "autoload/cleanup.gd").write_text("extends Node\nfunc _exit_tree() -> void:\n    print(\"COVERAGE_AUTOLOAD_EXIT\")\n", encoding="utf-8")
            (root / "project.godot").write_text(
                'config_version=5\n[application]\nrun/main_scene="res://tests/fixture_test.tscn"\n'
                '[input]\nfixture_action={"deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":65)]}\n',
                encoding="utf-8",
            )
            (root / "project.godot").write_text((root / "project.godot").read_text() + '[autoload]\nCleanup="*res://autoload/cleanup.gd"\n')
            original_project = (root / "project.godot").read_bytes()
            (root / "tests/fixture_test.tscn").write_text(
                '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/fixture.gd" id="1"]\n'
                '[node name="Fixture" type="Node"]\nscript = ExtResource("1")\n', encoding="utf-8",
            )
            shutil.copy2(ROOT / "tools/run_tests.sh", root / "tools/run_tests.sh")
            shutil.copy2(ROOT / "tools/coverage/collect_gdscript_coverage.py", root / "tools/coverage/collect_gdscript_coverage.py")
            output = Path(temporary) / "evidence"
            result = api.run_coverage(root, shutil.which(os.environ.get("GODOT_BIN", "godot")), output, timeout_seconds=30)
            self.assertEqual(result["status"], "pass", result)
            self.assertEqual((root / "scripts/fixture.gd").read_text(), inherited_fixture)
            self.assertEqual((root / "project.godot").read_bytes(), original_project)
            report = json.loads((output / "gdscript-coverage.json").read_text())
            never_loaded = next(row for row in report["files"] if row["path"] == "scripts/never_loaded.gd")
            self.assertEqual(never_loaded["executable_lines"], [3])
            self.assertEqual(never_loaded["covered_lines"], [])
            self.assertGreater(report["summary"]["covered_lines"], 0)
            cleanup = next(row for row in report["files"] if row["path"] == "autoload/cleanup.gd")
            self.assertEqual(cleanup["covered_lines"], [3])
            base = next(row for row in report["files"] if row["path"] == "scripts/base.gd")
            self.assertEqual(base["covered_lines"], [3])
            self.assertTrue(list((output / "runtime-hits").glob("*.json")))
            installed = (output / "project-copy/project.godot").read_text()
            self.assertIn("InputEventKey", installed)
            self.assertIn("PWLineCoverageProbe", installed)

    def test_occupied_or_recursive_output_is_refused(self):
        api = self.require_provider()
        with tempfile.TemporaryDirectory(dir=ROOT / "build/coverage-fixtures") as temporary:
            root = Path(temporary)
            (root / "project.godot").write_text("config_version=5\n")
            output = root / "build/occupied"
            output.mkdir(parents=True)
            (output / "valuable.json").write_text("preserve")
            for destination in [root / "scripts/output", output]:
                with self.subTest(destination=destination), self.assertRaises(ValueError):
                    api.run_coverage(root, "godot", destination)
            self.assertEqual((output / "valuable.json").read_text(), "preserve")


def _line(text: str) -> int:
    return next(index for index, line in enumerate(FIXTURE.splitlines(), 1) if text in line)


FIXTURE = """extends Node
var initial := 3
var values := [1, 2]
static var static_value := 4
static var static_numbers: Array[int] = [4]
var typed_values: Array[String] = ["alpha"]
var typed_rows: Array[Dictionary] = []
@onready var ready_value := name
@onready var typed_nodes: Array[Node] = [self]

func choose(value: int) -> int:
    var total := value
    if value > 0:
        total += 2
    elif value < 0:
        return 9
    else:
        total += 1
    for number: int in range(2):
        total += number
    while total < 6:
        total += 1
    var callback := func(amount: int) -> int:
        return amount + 1
    var uncalled := func(amount: int) -> int:
        return amount * 99
    assert(uncalled is Callable)
    return callback.call(total)

func unused() -> int:
    return 99

func _ready() -> void:
    assert(choose(1) == 7)
    assert(choose(0) == 7)
    assert(initial == 3 and static_value == 4 and values == [1, 2])
    assert(static_numbers.is_typed() and static_numbers == [4])
    assert(typed_values.is_typed() and typed_values == ["alpha"])
    assert(typed_rows.is_typed() and typed_rows.is_empty())
    assert(typed_nodes.is_typed() and typed_nodes == [self])
    assert(ready_value == name)
    if InputMap.has_action("fixture_action"):
        assert(InputMap.action_get_events("fixture_action")[0].physical_keycode == 65)
    var expected := {"initial": TYPE_INT, "values": TYPE_ARRAY, "ready_value": TYPE_STRING_NAME}
    for property: Dictionary in get_property_list():
        if expected.has(property.name):
            assert(property.type == expected[property.name])
    print("COVERAGE_FIXTURE_PRESERVED")
    get_tree().quit()
"""


if __name__ == "__main__":
    unittest.main()
