from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tests.contract.performance.test_native_performance_probe import api, report


def measured_report():
    value = report()
    value["measurement_schema_version"] = 2
    value["native_process_id"] = 421
    value["wall_duration_usec"] = 2000
    for name, duration in [("frame_work", 4), ("frame_wall", 12)]:
        value["metrics"][name] = {
            "count": 120, "total_usec": duration * 120, "mean_usec": duration,
            "p50_usec": duration, "p95_usec": duration, "maximum_usec": duration,
        }
    value["process_rss"] = {
        "platform": "darwin", "source": "ps.rss_kib",
        "scope": "godot_process_after_pid_announcement", "process_id": 421,
        "sample_interval_ms": 100, "valid_sample_count": 3,
        "failed_sample_count": 1, "peak_bytes": 4 * 1024 * 1024,
    }
    return value


class NativeMeasurementContract(unittest.TestCase):
    def test_current_report_requires_same_frame_work_and_wall_measurements(self):
        api.validate_report(measured_report())
        for name in ["frame_work", "frame_wall"]:
            candidate = measured_report()
            del candidate["metrics"][name]
            with self.subTest(missing=name), self.assertRaises(ValueError):
                api.validate_report(candidate)
            candidate = measured_report()
            candidate["metrics"][name]["count"] -= 1
            with self.subTest(count=name), self.assertRaises(ValueError):
                api.validate_report(candidate)

    def test_combined_intervals_cannot_exclude_the_work_they_enclose(self):
        for name, duration in [("frame_work", 3), ("frame_wall", 7)]:
            candidate = measured_report()
            candidate["metrics"][name] = {
                "count": 120, "total_usec": duration * 120, "mean_usec": duration,
                "p50_usec": duration, "p95_usec": duration, "maximum_usec": duration,
            }
            with self.subTest(interval=name), self.assertRaises(ValueError):
                api.validate_report(candidate)
        candidate = measured_report()
        candidate["wall_duration_usec"] = 1000
        with self.assertRaises(ValueError):
            api.validate_report(candidate)

    def test_legacy_measurements_remain_explicitly_distinct(self):
        api.validate_report(report())
        explicit = report()
        explicit["measurement_schema_version"] = 1
        api.validate_report(explicit)
        for version in [True, 0, 3, "2"]:
            candidate = report()
            candidate["measurement_schema_version"] = version
            with self.subTest(version=version), self.assertRaises(ValueError):
                api.validate_report(candidate)

    def test_process_rss_requires_observed_samples_and_exact_native_pid(self):
        mutations = [
            ("valid_sample_count", 0), ("valid_sample_count", True),
            ("failed_sample_count", -1), ("peak_bytes", 0), ("peak_bytes", True),
            ("process_id", 422), ("process_id", True), ("sample_interval_ms", 0),
            ("platform", "invented"), ("source", "Performance.MEMORY_STATIC"),
            ("scope", "total_memory_certified"),
        ]
        for key, replacement in mutations:
            candidate = measured_report()
            candidate["process_rss"][key] = replacement
            with self.subTest(field=key), self.assertRaises(ValueError):
                api.validate_report(candidate)
        candidate = measured_report()
        del candidate["process_rss"]
        with self.assertRaises(ValueError):
            api.validate_report(candidate)

    def test_platform_rss_source_cannot_be_relabelled(self):
        for platform, source in [
            ("linux", "proc.status.VmRSS_kib"),
            ("win32", "GetProcessMemoryInfo.WorkingSetSize"),
        ]:
            candidate = measured_report()
            candidate["process_rss"].update(platform=platform, source=source)
            api.validate_report(candidate)
            candidate["process_rss"]["source"] = "ps.rss_kib"
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                api.validate_report(candidate)

    def test_linux_reads_current_target_process_resident_bytes(self):
        text = "Name:\tGodot\nVmSize:\t999999 kB\nVmRSS:\t4096 kB\n"
        with patch.object(Path, "read_text", autospec=True, return_value=text) as read:
            self.assertEqual(api._read_process_rss(421, "linux"), 4096 * 1024)
        self.assertEqual(read.call_args.args, (Path("/proc/421/status"),))
        for text in ["VmSize:\t4096 kB\n", "VmRSS:\t0 kB\n", "VmRSS:\tNaN kB\n"]:
            with self.subTest(text=text), patch.object(Path, "read_text", return_value=text):
                with self.assertRaises((OSError, ValueError)):
                    api._read_process_rss(421, "linux")

    def test_darwin_ps_is_bound_to_native_pid_and_kib_units(self):
        process = subprocess.CompletedProcess([], 0, stdout=" 4096\n", stderr="")
        with patch.object(api.subprocess, "run", return_value=process) as run:
            self.assertEqual(api._read_process_rss(421, "darwin"), 4096 * 1024)
        self.assertEqual(run.call_args.args[0], ["/bin/ps", "-o", "rss=", "-p", "421"])
        for output in ["", "0", "NaN", "4096 8192"]:
            process = subprocess.CompletedProcess([], 0, stdout=output, stderr="")
            with self.subTest(output=output), patch.object(api.subprocess, "run", return_value=process):
                with self.assertRaises((OSError, ValueError)):
                    api._read_process_rss(421, "darwin")

    def test_sampler_retains_real_peak_valid_counts_and_failed_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            stdout = Path(directory) / "stdout.log"
            stdout.write_text("Godot Engine\nNATIVE_PERFORMANCE_PROCESS_PID 421\n", encoding="utf-8")
            sampler = api._ProcessRssSampler(stdout, "linux")
            with patch.object(api, "_read_process_rss", side_effect=[1024, 4096, OSError("process unavailable")]) as read:
                sampler._sample()
                sampler._sample()
                sampler._sample()
            captured = sampler.snapshot()
            self.assertEqual(captured["process_id"], 421)
            self.assertEqual(captured["valid_sample_count"], 2)
            self.assertEqual(captured["failed_sample_count"], 1)
            self.assertEqual(captured["peak_bytes"], 4096)
            self.assertEqual(captured["source"], "proc.status.VmRSS_kib")
            self.assertEqual(read.call_args.args, (421, "linux"))
            json.dumps(captured, allow_nan=False)

    def test_missing_or_conflicting_pid_cannot_invent_memory_samples(self):
        for log in ["no native PID\n", "NATIVE_PERFORMANCE_PROCESS_PID 0\n", "NATIVE_PERFORMANCE_PROCESS_PID 421\nNATIVE_PERFORMANCE_PROCESS_PID 422\n"]:
            with self.subTest(log=log), tempfile.TemporaryDirectory() as directory:
                stdout = Path(directory) / "stdout.log"
                stdout.write_text(log, encoding="utf-8")
                sampler = api._ProcessRssSampler(stdout, "linux")
                with patch.object(api, "_read_process_rss") as read:
                    sampler._sample()
                read.assert_not_called()
                self.assertEqual(sampler.snapshot()["valid_sample_count"], 0)

    def test_invalid_process_identity_never_reaches_a_platform_reader(self):
        for process_id in [True, 0, -1, 4294967296]:
            with self.subTest(process_id=process_id), patch.object(api.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    api._read_process_rss(process_id, "darwin")
                run.assert_not_called()

    def test_current_cli_retains_memory_evidence_or_refuses_missing_samples(self):
        for missing_samples in [False, True]:
            with self.subTest(missing_samples=missing_samples), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                (root / "scripts").mkdir()
                (root / "scripts/runtime.gd").write_text("extends Node\n", encoding="utf-8")
                output = root / "build/measurement/report.json"
                native_report = measured_report()
                rss = native_report.pop("process_rss")
                if missing_samples:
                    rss["valid_sample_count"] = 0
                    rss["peak_bytes"] = 0

                def run(command, **kwargs):
                    if command[0] != "/fixture/godot":
                        return subprocess.CompletedProcess(command, 1, stdout="", stderr="")
                    output.write_text(json.dumps(native_report), encoding="utf-8")
                    return subprocess.CompletedProcess(command, 0)

                with patch.object(api, "ROOT", root), patch.object(api.shutil, "which", return_value="/fixture/godot"), patch.object(api.subprocess, "run", side_effect=run), patch.object(api, "_ProcessRssSampler") as sampler, patch.object(sys, "argv", ["probe", "--output", str(output), "--frames", "120", "--hub-frames", "12"]), patch("builtins.print"):
                    sampler.return_value.snapshot.return_value = rss
                    if missing_samples:
                        with self.assertRaises(ValueError):
                            api.main()
                    else:
                        api.main()
                    sampler.return_value.start.assert_called_once()
                    sampler.return_value.stop.assert_called_once()
                retained = json.loads(output.read_text())
                self.assertEqual(retained["native_status"], "pass")
                self.assertEqual(retained["status"], "failed" if missing_samples else "pass")
                self.assertEqual(retained["process_rss"], rss)
                self.assertEqual(retained["source"]["process_exit_code"], 0)
                self.assertTrue(retained["source"]["runtime_source_stable"])


if __name__ == "__main__":
    unittest.main()
