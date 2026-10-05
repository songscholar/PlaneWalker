from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path

from tests.contract.export.test_export_preflight import fixture_project

PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "export"))

from artifact_evidence import describe_artifact  # noqa: E402
from verify_packaged_startup import EXPECTED_CHECKS  # noqa: E402
from verify_windows_wine_guest_startup import verify_windows_wine_guest_startup  # noqa: E402

IMAGE = "sha256:" + "c" * 64


class WindowsWineGuestStartupTest(unittest.TestCase):
    def run_fixture(self, mode="pass", *, image=IMAGE):
        with fixture_project() as root:
            artifacts = root / "build/retained"
            executable = artifacts / "build/windows/PlaneWalker.exe"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"fixture executable")
            target = {
                "id": "windows-x86_64", "artifact": "build/windows/PlaneWalker.exe",
                "artifact_kind": "file", "status": "pass",
                "artifact_evidence": describe_artifact(executable, artifacts, "file"),
            }
            result = {
                "schema_id": "planewalker.packaged_startup", "schema_version": 1,
                "status": "pass", "engine_version": "4.6.1-stable (official)",
                "checks": EXPECTED_CHECKS, "failure": "",
                "content_snapshot": {"aggregate_sha256": "a" * 64, "packs": [{
                    "pack_id": "base", "pack_version": "0.4.0-dev",
                    "schema_version": 2, "fingerprint_sha256": "b" * 64,
                }]},
            }
            if mode == "missing_check":
                result["checks"] = EXPECTED_CHECKS[:-1]
            source = root / "build/export.json"
            source.write_text(json.dumps({"status": "pass", "targets": [target]}))
            if mode == "changed":
                executable.write_bytes(b"changed")
            if mode == "duplicate":
                source.write_text(json.dumps({"status": "pass", "targets": [target, target]}))
            fake = root / "build/fake-docker"
            fake.write_text(
                f"#!{sys.executable}\n"
                "import json, pathlib, sys, time\n"
                f"mode = {mode!r}\n"
                "args = sys.argv[1:]\n"
                "if 'version' in args:\n"
                "    print('{}' if mode == 'daemon_missing' else '{\"Os\":\"linux\",\"Version\":\"27.5.1\"}')\n"
                "elif 'inspect' in args:\n"
                f"    value = {{'Id': {IMAGE!r}, 'Os': 'linux', 'Architecture': 'amd64'}}\n"
                "    if mode == 'wrong_arch': value['Architecture'] = 'arm64'\n"
                "    if mode == 'wrong_image': value['Id'] = 'sha256:' + 'e' * 64\n"
                "    print(json.dumps(value))\n"
                "    if mode == 'image_missing': sys.exit(1)\n"
                "elif 'run' in args:\n"
                "    mounts = [args[i+1] for i, value in enumerate(args) if value == '--mount']\n"
                "    parsed = [dict(part.split('=', 1) for part in value.split(',') if '=' in part) for value in mounts]\n"
                "    output = pathlib.Path(next(value['source'] for value in parsed if value['target'] == '/output'))\n"
                "    (output / 'command.json').write_text(json.dumps(args))\n"
                "    if mode == 'timeout': time.sleep(5)\n"
                "    (output / 'engine.log').write_text('Godot guest startup\\n')\n"
                f"    result = json.loads({json.dumps(json.dumps(result))})\n"
                "    if mode != 'missing_result': (output / 'native-startup.json').write_text(json.dumps(result))\n"
                "    if mode == 'zero_error': print('ERROR: guest fixture failure')\n"
                "    if mode == 'leak': print('WARNING: ObjectDB instances leaked at exit')\n"
                "    if mode == 'changed_during': pathlib.Path(next(value['source'] for value in parsed if value['target'].startswith('/artifact/'))).write_bytes(b'mutated')\n"
                "    if mode == 'nonzero': sys.exit(9)\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            logs = root / "build/guest-logs"
            report, code = verify_windows_wine_guest_startup(
                root, source, artifacts, root / "build/guest.json", logs,
                str(fake), "unix:///fixture.sock", image,
                1 if mode == "timeout" else 10,
            )
            self.assertEqual(json.loads((root / "build/guest.json").read_text()), report)
            command = json.loads((logs / "command.json").read_text()) if (logs / "command.json").exists() else None
            return report, code, command

    def test_success_is_windows_compatibility_evidence_and_isolated(self):
        report, code, command = self.run_fixture()
        self.assertEqual(code, 0, report)
        self.assertEqual(report["classification"], "windows_wine_guest_packaged_startup_verified")
        self.assertFalse(report["full_product_certified"])
        self.assertFalse(report["actual_windows_host_verified"])
        self.assertEqual(report["startup"]["checks"], EXPECTED_CHECKS)
        self.assertEqual(command[command.index("--network") + 1], "none")
        self.assertIn("--read-only", command)
        self.assertIn("--pull=never", command)
        self.assertIn("--init", command)
        self.assertEqual(command[command.index("--tmpfs") + 1],
                         f"/tmp:rw,nosuid,exec,size=1024m,uid={os.getuid()},gid={os.getgid()}")
        self.assertEqual(command[command.index("--memory") + 1], "2048m")
        self.assertIn("HOME=/tmp", command)
        self.assertEqual(command[command.index("--entrypoint") + 1], "/usr/bin/xvfb-run")
        self.assertIn("/usr/lib/wine/wine64", command)
        self.assertIn("/artifact/PlaneWalker.exe", command)
        self.assertEqual(command.count("--mount"), 2)
        self.assertNotIn("--path", command)

    def test_environment_and_mutable_image_refused(self):
        for mode in ["daemon_missing", "image_missing", "wrong_arch", "wrong_image"]:
            with self.subTest(mode=mode):
                report, code, command = self.run_fixture(mode)
                self.assertEqual(code, 3, report)
                self.assertIsNone(command)
        report, code, command = self.run_fixture(image="planewalker-wine-guest:local")
        self.assertEqual(code, 4)
        self.assertEqual(report["failure"], "invalid_guest_configuration")
        self.assertIsNone(command)

    def test_artifact_and_export_identity_refused(self):
        for mode, failure in [("changed", "artifact_changed"), ("duplicate", "export_report_invalid"),
                              ("changed_during", "artifact_changed_during_startup")]:
            with self.subTest(mode=mode):
                report, code, _ = self.run_fixture(mode)
                self.assertEqual(code, 4, report)
                self.assertEqual(report["failure"], failure)

    def test_runtime_errors_and_incomplete_results_refused(self):
        for mode in ["zero_error", "leak", "nonzero", "missing_result", "missing_check", "timeout"]:
            with self.subTest(mode=mode):
                report, code, _ = self.run_fixture(mode)
                self.assertEqual(code, 4, report)
                self.assertEqual(report["status"], "failed")


if __name__ == "__main__":
    unittest.main()
