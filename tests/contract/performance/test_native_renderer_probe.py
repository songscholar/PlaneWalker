from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tests.contract.performance.test_native_performance_probe import (
    api, fixture_executable, fixture_pid_announcement, framed_report, rss_fixture,
)


def renderer_report(method="gl_compatibility", requested="gl_compatibility"):
    value = framed_report(3)
    value["measurement_schema_version"] = 4
    value["rendered"] = True
    value["render_wait"] = copy.deepcopy(value["metrics"]["physics_wait"])
    value["metrics"]["frame_wall"].update(total_usec=1200, mean_usec=10.0, p50_usec=10, p95_usec=10, maximum_usec=10)
    value["wall_duration_usec"] = 1500
    value["rendering"] = {
        "requested_method": requested, "actual_method": method,
        "driver": "opengl3" if method == "gl_compatibility" else "metal",
        "adapter_name": "Apple M4 Pro", "adapter_vendor": "Apple",
        "api_version": "4.1" if method == "gl_compatibility" else "4.0",
        "display_server": "macos",
    }
    return value


class NativeRendererProbeContract(unittest.TestCase):
    def test_v4_requires_actual_structured_renderer_metadata(self):
        for method in ["gl_compatibility", "forward_plus"]:
            api.validate_report(renderer_report(method, method))
        legacy = framed_report(3)
        api.validate_report(legacy)
        candidate = renderer_report()
        del candidate["rendering"]
        with self.assertRaises(ValueError):
            api.validate_report(candidate)

    def test_explicit_backend_cannot_silently_fall_back_or_invent_hardware(self):
        mutations = [
            ("actual_method", "forward_plus"), ("actual_method", "unknown"),
            ("requested_method", "unknown"), ("driver", ""),
            ("adapter_name", ""), ("adapter_vendor", ""), ("api_version", ""),
            ("display_server", "headless"), ("driver", True),
        ]
        for field, replacement in mutations:
            candidate = renderer_report()
            candidate["rendering"][field] = replacement
            with self.subTest(field=field, replacement=replacement), self.assertRaises(ValueError):
                api.validate_report(candidate)
        candidate = renderer_report()
        candidate["rendering"]["extra"] = "unbound"
        with self.assertRaises(ValueError):
            api.validate_report(candidate)

    def test_cli_binds_explicit_backend_to_command_environment_and_native_report(self):
        for fallback in [False, True]:
            with self.subTest(fallback=fallback), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                (root / "scripts").mkdir()
                (root / "scripts/runtime.gd").write_text("extends Node\n", encoding="utf-8")
                binary = fixture_executable(root)
                output = root / "build/backend/report.json"
                native = renderer_report("forward_plus" if fallback else "gl_compatibility")
                commands = []

                def run(command, **kwargs):
                    if command[0] != str(binary):
                        return subprocess.CompletedProcess(command, 1, stdout="", stderr="")
                    commands.append(command)
                    self.assertEqual(kwargs["env"]["PLANEWALKER_PERFORMANCE_RENDERING_METHOD"], "gl_compatibility")
                    output.write_text(json.dumps(native), encoding="utf-8")
                    fixture_pid_announcement(output, native, kwargs["stdout"])
                    return subprocess.CompletedProcess(command, 0)

                argv = ["probe", "--output", str(output), "--frames", "120", "--hub-frames", "12", "--real-time", "--rendered", "--rendering-method", "gl_compatibility"]
                with patch.object(api, "ROOT", root), patch.object(api.shutil, "which", return_value=str(binary)), patch.object(api.subprocess, "run", side_effect=run), patch.object(api, "_ProcessRssSampler") as sampler, patch.object(sys, "argv", argv), patch("builtins.print"):
                    sampler.return_value.snapshot.return_value = rss_fixture()
                    if fallback:
                        with self.assertRaises(ValueError):
                            api.main()
                    else:
                        api.main()
                self.assertEqual(len(commands), 1)
                index = commands[0].index("--rendering-method")
                self.assertEqual(commands[0][index + 1], "gl_compatibility")
                retained = json.loads(output.read_text())
                manifest = json.loads(output.with_name("source-manifest.json").read_text())
                self.assertEqual(retained["source"]["requested_rendering_method"], "gl_compatibility")
                self.assertEqual(retained["status"], "failed" if fallback else "pass")
                self.assertEqual(manifest["execution_status"], "pass")
                if fallback:
                    self.assertIn("report_validation_failure", manifest)


if __name__ == "__main__":
    unittest.main()
