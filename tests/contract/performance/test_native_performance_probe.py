from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "tools/p15/native_performance_probe.py"
api = None
if SOURCE.is_file():
    spec = importlib.util.spec_from_file_location("native_performance_probe", SOURCE)
    api = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(api)


def report():
    metric = {"count": 120, "total_usec": 240, "mean_usec": 2.0, "p50_usec": 2, "p95_usec": 2, "maximum_usec": 2}
    return {"schema_version": 1, "report_kind": "actual_native_main_performance", "status": "pass", "human_playtests": 0, "unassisted_victory": False, "fps_certified": False, "survival_fixture": "native_performance_survival_fixture", "prerequisite_route_fixture": True, "rendered": False, "scheduler": {"physics_ticks_per_second": 60, "native_hz": 60, "time_scale": 1.0, "wall_accelerated": True}, "content_snapshot": {"aggregate_sha256": "a" * 64, "packs": [{"pack_id": "base", "pack_version": "0.4.0-dev", "fingerprint_sha256": "d" * 64}]}, "encounter": {"floor_index": 0, "node_id": "boss", "room_type": "boss"}, "peak_native_static_bytes": 1000, "requested_frames": 120, "accepted_frames": 120, "native_duration_ms": 2000.0, "wall_duration_usec": 900, "sample_frames": {"first": 10, "last": 129, "unique_count": 120}, "metrics": {name: copy.deepcopy(metric) for name in ["player_advance", "host_process", "physics_wait", "observer"]}, "render_wait": {"count": 0}, "observed_peak_counts": {name: 1 for name in ["actors", "summons", "projectiles", "zones", "constructs", "threats"]}, "recording": {"status": "INTERRUPTED", "actual_sample_count": 120, "total_tape_observations": 121, "first_sha256": "b" * 64, "last_sha256": "c" * 64, "physical_first_exact": True, "physical_last_exact": True, "failure": ""}, "hub": {"frames": 12, "visited_functions": 9, "wall_duration_usec": 30, "scheduler_and_render_wait": {"count": 12, "total_usec": 24, "mean_usec": 2.0, "p50_usec": 2, "p95_usec": 2, "maximum_usec": 2}}, "failures": []}


def rss_fixture():
    return {"platform": "darwin", "source": "ps.rss_kib", "scope": "godot_process_after_pid_announcement", "process_id": 321, "sample_interval_ms": 100, "valid_sample_count": 2, "failed_sample_count": 0, "peak_bytes": 65536}


def framed_report(version=2):
    value = report()
    value["measurement_schema_version"] = version
    value["native_process_id"] = 321
    value["process_rss"] = rss_fixture()
    value["wall_duration_usec"] = 1200
    for name, amount in [("frame_work", 4), ("frame_wall", 8)]:
        value["metrics"][name] = {"count": 120, "total_usec": amount * 120, "mean_usec": float(amount), "p50_usec": amount, "p95_usec": amount, "maximum_usec": amount}
    if version == 3:
        value["debug_build"] = False
        value["peak_native_static_bytes"] = 0
        value["native_static_monitor"] = {"source": "Performance.MEMORY_STATIC", "available": False, "reason": "release_build"}
    return value


def fixture_executable(root):
    binary = root / "fixture-godot"
    binary.write_bytes(b"fixture executable bytes\n")
    binary.chmod(0o755)
    return binary


def fixture_package(root):
    contents = root / "fixture.app/Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    binary = fixture_executable(macos)
    (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": binary.name}))
    resource = resources / (binary.name + ".pck")
    resource.write_bytes(b"authenticated pack bytes\n")
    return binary, resource


class NativePerformanceProbeContract(unittest.TestCase):
    def require_api(self):
        self.assertIsNotNone(api, "actual Main performance executable must exist")
        for suffix in ["gd", "tscn"]:
            self.assertTrue(SOURCE.with_suffix("." + suffix).is_file(), "native performance scene and script must exist")
        return api

    def test_authentic_report_retains_independent_metrics_and_physical_samples(self):
        self.require_api().validate_report(report())

    def test_release_zero_static_monitor_is_explicit_and_keeps_real_rss(self):
        validator = self.require_api().validate_report
        validator(report())
        validator(framed_report())
        validator(framed_report(3))
        for debug in [True, False]:
            candidate = framed_report(3)
            candidate["debug_build"] = debug
            candidate["peak_native_static_bytes"] = 1000
            candidate["native_static_monitor"] = {"source": "Performance.MEMORY_STATIC", "available": True, "reason": ""}
            validator(candidate)
        for version in [1, 2]:
            candidate = report() if version == 1 else framed_report()
            candidate["peak_native_static_bytes"] = 0
            with self.subTest(legacy_version=version), self.assertRaises(ValueError):
                validator(candidate)

    def test_runtime_monitor_and_rss_cannot_be_forged_or_silently_absent(self):
        validator = self.require_api().validate_report
        mutations = [
            ("debug_build", True), ("debug_build", 0),
            ("peak_native_static_bytes", -1), ("peak_native_static_bytes", False),
            ("peak_native_static_bytes", 1000),
            ("native_static_monitor", {"source": "Performance.MEMORY_STATIC", "available": True, "reason": ""}),
            ("native_static_monitor", {"source": "invented", "available": False, "reason": "release_build"}),
            ("native_static_monitor", {"source": "Performance.MEMORY_STATIC", "available": 0, "reason": "release_build"}),
            ("native_static_monitor", {"source": "Performance.MEMORY_STATIC", "available": False, "reason": ""}),
            ("native_static_monitor", {"source": "Performance.MEMORY_STATIC", "available": False, "reason": "release_build", "extra": True}),
        ]
        for key, value in mutations:
            candidate = framed_report(3)
            candidate[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validator(candidate)
        for key in ["debug_build", "native_static_monitor", "process_rss", "native_process_id"]:
            candidate = framed_report(3)
            del candidate[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                validator(candidate)
        for key, value in [("valid_sample_count", 0), ("peak_bytes", 0), ("process_id", 322)]:
            candidate = framed_report(3)
            candidate["process_rss"][key] = value
            with self.subTest(rss=key), self.assertRaises(ValueError):
                validator(candidate)

    def test_packaged_probe_runs_its_main_and_retains_executable_and_pack_identity(self):
        probe = self.require_api()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            binary, resource = fixture_package(root)
            output = root / "build" / "packaged" / "report.json"
            commands = []

            def run(command, **kwargs):
                if command[0] == str(binary):
                    commands.append(command)
                    output.write_text(json.dumps(framed_report(3)), encoding="utf-8")
                return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

            argv = [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12", "--packaged-binary", str(binary), "--packaged-resource", str(resource)]
            with patch.object(probe, "ROOT", root), patch.object(probe.subprocess, "run", side_effect=run), patch.object(probe._ProcessRssSampler, "snapshot", return_value=rss_fixture()), patch.object(sys, "argv", argv):
                probe.main()
            self.assertEqual(commands, [[str(binary), "--log-file", str(output.parent / "godot.log"), "--fixed-fps", "60", "--headless"]])
            retained = json.loads(output.read_text())
            source = retained["source"]
            self.assertEqual(retained["status"], "pass")
            self.assertEqual(source["runtime_kind"], "packaged_binary")
            self.assertEqual(source["source_checkout_role"], "harness_only")
            self.assertEqual(source["command"], commands[0])
            self.assertEqual(source["godot_binary"], str(binary))
            self.assertEqual(source["godot_binary_sha256"], hashlib.sha256(binary.read_bytes()).hexdigest())
            self.assertEqual(source["packaged_resource"], str(resource))
            self.assertEqual(source["packaged_resource_sha256"], hashlib.sha256(resource.read_bytes()).hexdigest())
            plist = binary.parent.parent / "Info.plist"
            self.assertEqual(source["packaged_resource_binding"], "macos_bundle_autoload")
            self.assertEqual(source["package_info_plist"], str(plist))
            self.assertEqual(source["package_info_plist_sha256"], hashlib.sha256(plist.read_bytes()).hexdigest())
            self.assertTrue(source["package_info_plist_stable"])
            self.assertTrue(source["godot_binary_stable"] and source["packaged_resource_stable"])
            manifest = json.loads(output.with_name("source-manifest.json").read_text())
            self.assertEqual(manifest["command"], commands[0])
            self.assertEqual(manifest["packaged_resource_sha256"], source["packaged_resource_sha256"])

    def test_packaged_mutation_and_late_failures_cannot_retain_pass(self):
        probe = self.require_api()
        for failure in ["binary", "resource", "resource_deleted", "plist", "source", "exit", "log", "legacy_report", "rss"]:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                (root / "scripts").mkdir()
                script = root / "scripts/runtime.gd"
                script.write_text("extends Node\n", encoding="utf-8")
                binary, resource = fixture_package(root)
                output = root / "build" / "failed" / "report.json"

                def run(command, **kwargs):
                    if command[0] == str(binary):
                        output.write_text(json.dumps(report() if failure == "legacy_report" else framed_report(3)), encoding="utf-8")
                        if failure == "binary":
                            binary.write_bytes(b"changed binary\n")
                        if failure == "resource":
                            resource.write_bytes(b"changed pack\n")
                        if failure == "resource_deleted":
                            resource.unlink()
                        if failure == "plist":
                            (binary.parent.parent / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "different"}))
                        if failure == "source":
                            script.write_text("extends Node\nvar changed = true\n", encoding="utf-8")
                        if failure == "log":
                            kwargs["stdout"].write("SCRIPT ERROR: packaged late failure\n")
                        return subprocess.CompletedProcess(command, 1 if failure == "exit" else 0)
                    return subprocess.CompletedProcess(command, 1, stdout="", stderr="")

                argv = [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12", "--packaged-binary", str(binary), "--packaged-resource", str(resource)]
                rss = rss_fixture()
                if failure == "rss":
                    rss["valid_sample_count"] = 0
                    rss["peak_bytes"] = 0
                with patch.object(probe, "ROOT", root), patch.object(probe.subprocess, "run", side_effect=run), patch.object(probe._ProcessRssSampler, "snapshot", return_value=rss), patch.object(sys, "argv", argv):
                    with self.assertRaises((SystemExit, ValueError)):
                        probe.main()
                retained = json.loads(output.read_text())
                self.assertEqual(retained["status"], "failed")
                self.assertEqual(retained["source"]["godot_binary_stable"], failure != "binary")
                self.assertEqual(retained["source"]["packaged_resource_stable"], failure not in ["resource", "resource_deleted"])
                self.assertEqual(retained["source"]["package_info_plist_stable"], failure != "plist")

    def test_unrelated_ambiguous_symlinked_or_misidentified_pack_refuses_before_launch(self):
        probe = self.require_api()
        for case in ["unrelated", "ambiguous", "adjacent_pack", "bundle_identity", "symlink_binary", "symlink_resource", "symlink_plist", "unsupported_layout"]:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                binary, resource = fixture_package(root)
                plist = binary.parent.parent / "Info.plist"
                if case == "unrelated":
                    unrelated = root / "unrelated.pck"
                    unrelated.write_bytes(resource.read_bytes())
                    resource = unrelated
                if case == "ambiguous":
                    resource.with_name("another.pck").write_bytes(b"second pack\n")
                if case == "adjacent_pack":
                    binary.with_suffix(".pck").write_bytes(b"adjacent pack\n")
                if case == "bundle_identity":
                    plist.write_bytes(plistlib.dumps({"CFBundleExecutable": "different"}))
                if case == "symlink_binary":
                    alias = root / "binary-alias"
                    alias.symlink_to(binary)
                    binary = alias
                if case == "symlink_resource":
                    alias = root / "pack-alias"
                    alias.symlink_to(resource)
                    resource = alias
                if case == "symlink_plist":
                    original = root / "original.plist"
                    plist.rename(original)
                    plist.symlink_to(original)
                if case == "unsupported_layout":
                    binary = fixture_executable(root)
                argv = [str(SOURCE), "--output", str(root / "build/report.json"), "--packaged-binary", str(binary), "--packaged-resource", str(resource)]
                with patch.object(probe, "ROOT", root), patch.object(probe.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, stdout="", stderr="")) as run, patch.object(sys, "argv", argv):
                    with self.assertRaises(SystemExit):
                        probe.main()
                    self.assertEqual(run.call_count, 0, "invalid package must refuse before any subprocess starts")

    def test_package_layout_changes_cannot_keep_stable_content_identity(self):
        probe = self.require_api()
        for case in ["binary_symlink", "resource_symlink", "extra_pack"]:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                binary, resource = fixture_package(root)
                output = root / "build/layout/report.json"

                def run(command, **kwargs):
                    if command[0] == str(binary):
                        output.write_text(json.dumps(framed_report(3)), encoding="utf-8")
                        if case == "extra_pack":
                            resource.with_name("new.pck").write_bytes(b"new ambiguous pack\n")
                        else:
                            target = binary if case == "binary_symlink" else resource
                            moved = root / "moved-content"
                            target.rename(moved)
                            target.symlink_to(moved)
                    return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

                argv = [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12", "--packaged-binary", str(binary), "--packaged-resource", str(resource)]
                with patch.object(probe, "ROOT", root), patch.object(probe.subprocess, "run", side_effect=run), patch.object(probe._ProcessRssSampler, "snapshot", return_value=rss_fixture()), patch.object(sys, "argv", argv), patch("builtins.print"):
                    with self.assertRaises((SystemExit, ValueError)):
                        probe.main()
                retained = json.loads(output.read_text())
                self.assertEqual(retained["status"], "failed")
                self.assertTrue(retained["source"]["godot_binary_stable"] and retained["source"]["packaged_resource_stable"])
                self.assertFalse(retained["source"]["packaged_layout_stable"])

    def test_packaged_arguments_are_bound_and_missing_paths_refuse_before_launch(self):
        probe = self.require_api()
        for case in ["resource_only", "binary_only", "missing_resource", "missing_binary", "not_executable"]:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                binary, resource = fixture_package(root)
                arguments = [str(SOURCE), "--output", str(root / "build/report.json")]
                if case != "resource_only":
                    arguments.extend(["--packaged-binary", str(root / "missing" if case == "missing_binary" else binary)])
                if case != "binary_only":
                    arguments.extend(["--packaged-resource", str(root / "missing" if case == "missing_resource" else resource)])
                if case == "not_executable":
                    binary.chmod(0o644)
                with patch.object(probe, "ROOT", root), patch.object(probe.subprocess, "run") as run, patch.object(sys, "argv", arguments):
                    with self.assertRaises(SystemExit):
                        probe.main()
                    run.assert_not_called()

    def test_claims_and_missing_recorded_samples_fail_closed(self):
        validator = self.require_api().validate_report
        mutations = [
            ("human_playtests", 20), ("unassisted_victory", True), ("fps_certified", True),
            ("accepted_frames", 119), ("native_duration_ms", 45000.0),
            ("sample_frames", {"first": 10, "last": 128, "unique_count": 120}),
        ]
        for key, value in mutations:
            candidate = report()
            candidate[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator(candidate)
        for key, value in [("physical_first_exact", False), ("physical_last_exact", False), ("failure", "CAPACITY"), ("status", "COMPLETE"), ("actual_sample_count", 119)]:
            candidate = report()
            candidate["recording"][key] = value
            with self.subTest(recording=key), self.assertRaises(ValueError):
                validator(candidate)

    def test_nonfinite_negative_inconsistent_or_missing_timings_refuse(self):
        validator = self.require_api().validate_report
        for value in [float("nan"), float("inf"), -1.0, True]:
            candidate = report()
            candidate["metrics"]["player_advance"]["mean_usec"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                validator(candidate)
        for key, value in [("count", 119), ("p95_usec", 3), ("total_usec", 1)]:
            candidate = report()
            candidate["metrics"]["player_advance"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator(candidate)
        candidate = report()
        del candidate["metrics"]["observer"]
        with self.assertRaises(ValueError):
            validator(candidate)

    def test_rendered_measurement_and_real_observed_load_are_explicit(self):
        validator = self.require_api().validate_report
        candidate = report()
        candidate["rendered"] = True
        with self.assertRaises(ValueError):
            validator(candidate)
        candidate["render_wait"] = copy.deepcopy(candidate["metrics"]["physics_wait"])
        validator(candidate)
        candidate["observed_peak_counts"]["projectiles"] = -1
        with self.assertRaises(ValueError):
            validator(candidate)

    def test_scheduler_encounter_and_authoritative_content_cannot_be_inferred(self):
        validator = self.require_api().validate_report
        for section, key, value in [("scheduler", "physics_ticks_per_second", 1000), ("scheduler", "time_scale", 16.667), ("scheduler", "wall_accelerated", "true"), ("content_snapshot", "packs", []), ("content_snapshot", "aggregate_sha256", ""), ("encounter", "floor_index", 5), ("encounter", "room_type", "invented"), ("hub", "scheduler_and_render_wait", {"count": 0}), ("recording", "total_tape_observations", 120)]:
            candidate = report()
            candidate[section][key] = value
            with self.subTest(section=section, key=key), self.assertRaises(ValueError):
                validator(candidate)

    def test_failed_native_process_retains_exact_source_identity(self):
        probe = self.require_api()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "scripts").mkdir()
            script = root / "scripts" / "runtime.gd"
            script.write_text("extends Node\n", encoding="utf-8")
            binary = fixture_executable(root)
            output = root / "build" / "failed" / "report.json"

            def run(command, **kwargs):
                if command[0] == str(binary):
                    output.write_text(json.dumps({"status": "failed", "failures": ["recording capacity"]}), encoding="utf-8")
                return subprocess.CompletedProcess(command, 1, stdout="", stderr="")

            with patch.object(probe, "ROOT", root), patch.object(probe.shutil, "which", return_value=str(binary)), patch.object(probe.subprocess, "run", side_effect=run), patch.object(sys, "argv", [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12"]):
                with self.assertRaises(SystemExit):
                    probe.main()
            retained = json.loads(output.read_text())
            expected = {"scripts/runtime.gd": hashlib.sha256(script.read_bytes()).hexdigest()}
            expected_digest = hashlib.sha256(json.dumps(expected, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            self.assertEqual(retained["status"], "failed")
            self.assertEqual(retained["source"]["runtime_source_sha256"], expected_digest)
            self.assertTrue(retained["source"]["runtime_source_stable"])
            self.assertEqual(retained["source"]["process_exit_code"], 1)
            self.assertEqual(retained["source"]["runtime_kind"], "source_project")
            self.assertEqual(retained["source"]["source_checkout_role"], "executed_project")
            self.assertEqual(retained["source"]["godot_binary_sha256"], hashlib.sha256(binary.read_bytes()).hexdigest())
            self.assertIn("--path", retained["source"]["command"])
            self.assertEqual(retained["source"]["command"][-1], "res://tools/p15/native_performance_probe.tscn")
            manifest = json.loads(output.with_name("source-manifest.json").read_text())
            self.assertEqual(manifest["runtime_files_sha256"], expected)

    def test_late_execution_failures_cannot_leave_a_passing_report(self):
        probe = self.require_api()
        for failure in ["exit", "log", "source", "timeout", "report"]:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                (root / "scripts").mkdir()
                script = root / "scripts" / "runtime.gd"
                script.write_text("extends Node\n", encoding="utf-8")
                binary = fixture_executable(root)
                output = root / "build" / "failed" / "report.json"

                def run(command, **kwargs):
                    if command[0] != str(binary):
                        return subprocess.CompletedProcess(command, 1, stdout="", stderr="")
                    if failure == "timeout":
                        raise subprocess.TimeoutExpired(command, 1)
                    native_report = report()
                    if failure == "report":
                        native_report["observed_peak_counts"]["actors"] = 0
                    output.write_text(json.dumps(native_report), encoding="utf-8")
                    if failure == "source":
                        script.write_text("extends Node\nvar changed = true\n", encoding="utf-8")
                    if failure == "log":
                        kwargs["stdout"].write("SCRIPT ERROR: late failure\n")
                    return subprocess.CompletedProcess(command, 1 if failure == "exit" else 0)

                with patch.object(probe, "ROOT", root), patch.object(probe.shutil, "which", return_value=str(binary)), patch.object(probe.subprocess, "run", side_effect=run), patch.object(sys, "argv", [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12"]):
                    with self.assertRaises((SystemExit, ValueError, subprocess.TimeoutExpired)):
                        probe.main()
                manifest = json.loads(output.with_name("source-manifest.json").read_text())
                self.assertEqual(manifest["execution_status"], "pass" if failure == "report" else "failed")
                self.assertEqual(manifest["timed_out"], failure == "timeout")
                self.assertEqual(manifest["runtime_source_stable"], failure != "source")
                if failure == "timeout":
                    self.assertFalse(output.exists(), "timeout metadata cannot invent native sample counts")
                else:
                    retained = json.loads(output.read_text())
                    self.assertEqual(retained["native_status"], "pass")
                    self.assertEqual(retained["status"], "failed")
                    with self.assertRaises(ValueError):
                        probe.validate_report(retained)


if __name__ == "__main__":
    unittest.main()
