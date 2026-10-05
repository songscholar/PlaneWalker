from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
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


class NativePerformanceProbeContract(unittest.TestCase):
    def require_api(self):
        self.assertIsNotNone(api, "actual Main performance executable must exist")
        for suffix in ["gd", "tscn"]:
            self.assertTrue(SOURCE.with_suffix("." + suffix).is_file(), "native performance scene and script must exist")
        return api

    def test_authentic_report_retains_independent_metrics_and_physical_samples(self):
        self.require_api().validate_report(report())

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
            output = root / "build" / "failed" / "report.json"

            def run(command, **kwargs):
                if command[0] == "/fixture/godot":
                    output.write_text(json.dumps({"status": "failed", "failures": ["recording capacity"]}), encoding="utf-8")
                return subprocess.CompletedProcess(command, 1, stdout="", stderr="")

            with patch.object(probe, "ROOT", root), patch.object(probe.shutil, "which", return_value="/fixture/godot"), patch.object(probe.subprocess, "run", side_effect=run), patch.object(sys, "argv", [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12"]):
                with self.assertRaises(SystemExit):
                    probe.main()
            retained = json.loads(output.read_text())
            expected = {"scripts/runtime.gd": hashlib.sha256(script.read_bytes()).hexdigest()}
            expected_digest = hashlib.sha256(json.dumps(expected, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            self.assertEqual(retained["status"], "failed")
            self.assertEqual(retained["source"]["runtime_source_sha256"], expected_digest)
            self.assertTrue(retained["source"]["runtime_source_stable"])
            self.assertEqual(retained["source"]["process_exit_code"], 1)
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
                output = root / "build" / "failed" / "report.json"

                def run(command, **kwargs):
                    if command[0] != "/fixture/godot":
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

                with patch.object(probe, "ROOT", root), patch.object(probe.shutil, "which", return_value="/fixture/godot"), patch.object(probe.subprocess, "run", side_effect=run), patch.object(sys, "argv", [str(SOURCE), "--output", str(output), "--frames", "120", "--hub-frames", "12"]):
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
