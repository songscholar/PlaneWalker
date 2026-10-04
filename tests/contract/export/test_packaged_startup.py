from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

from tests.contract.export.test_export_preflight import fixture_project

PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "export"))

from artifact_evidence import describe_artifact  # noqa: E402
from verify_packaged_startup import EXPECTED_CHECKS, verify_packaged_startup  # noqa: E402


class PackagedStartupContractTest(unittest.TestCase):
    def run_fixture(self, mode: str = "pass", changed: bool = False, host_system: str = "Linux"):
        with fixture_project() as root:
            executable = root / "build/linux/PlaneWalker.x86_64"
            executable.parent.mkdir(parents=True)
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
            if mode == "malformed":
                result["schema_version"] = True
            executable.write_text(
                f"#!{sys.executable}\n"
                "import json, os, pathlib, sys\n"
                "pathlib.Path(sys.argv[sys.argv.index('--log-file') + 1]).write_text('Godot startup\\n')\n"
                f"result = json.loads({json.dumps(json.dumps(result))})\n"
                + ("\n" if mode == "no_report" else
                   "pathlib.Path(os.environ['PLANEWALKER_STARTUP_REPORT']).write_text(json.dumps(result))\n")
                + ("print('ERROR: fixture zero-exit runtime failure')\n" if mode == "zero_error" else "")
                + ("print('WARNING: ObjectDB instances leaked at exit')\n" if mode == "leak" else "")
                + ("pathlib.Path(__file__).write_text('mutated')\n" if mode == "mutation" else "")
                + "sys.exit(9 if os.environ.get('STARTUP_FIXTURE_FAIL') == 'yes' else 0)\n",
                encoding="utf-8",
            )
            executable.chmod(0o755)
            target = {
                "id": "linux-x86_64", "artifact": "build/linux/PlaneWalker.x86_64",
                "artifact_kind": "file", "status": "pass",
                "artifact_evidence": describe_artifact(executable, root, "file"),
            }
            source = root / "build/export.json"
            source.write_text(json.dumps({"status": "pass", "targets": [target]}), encoding="utf-8")
            if changed:
                executable.write_text(executable.read_text() + "\n# changed\n")
            with mock.patch("verify_packaged_startup.platform.system", return_value=host_system):
                report, code = verify_packaged_startup(
                    root, source, root / "build/startup.json", root / "build/startup-logs", 10
                )
            self.assertEqual(json.loads((root / "build/startup.json").read_text()), report)
            return report, code

    def test_real_process_result_records_host_startup_only(self):
        report, code = self.run_fixture()
        self.assertEqual(code, 0, report)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["classification"], "host_packaged_startup_verified")
        self.assertFalse(report["full_product_certified"])
        self.assertEqual(report["startup"]["checks"], EXPECTED_CHECKS)

    def test_changed_artifact_is_refused_before_launch(self):
        report, code = self.run_fixture(changed=True)
        self.assertEqual(code, 4)
        self.assertEqual(report["failure"], "artifact_changed")
        self.assertIsNone(report["command"])

    def test_changed_artifact_during_execution_is_refused(self):
        report, code = self.run_fixture("mutation")
        self.assertEqual(code, 4)
        self.assertEqual(report["failure"], "artifact_changed_during_startup")

    def test_zero_exit_error_is_refused(self):
        for mode in ["zero_error", "leak"]:
            with self.subTest(mode=mode):
                report, code = self.run_fixture(mode)
                self.assertEqual(code, 4)
                self.assertEqual(report["failure"], "runtime_log_failure")

    def test_nonhost_artifact_is_recorded_without_execution(self):
        report, code = self.run_fixture(host_system="Darwin")
        self.assertEqual(code, 3)
        self.assertEqual(report["unexecuted_target_ids"], ["linux-x86_64"])
        self.assertIsNone(report["command"])

    def test_missing_report_or_checks_are_refused(self):
        for mode in ["no_report", "missing_check", "malformed"]:
            with self.subTest(mode=mode):
                report, code = self.run_fixture(mode)
                self.assertEqual(code, 4)
                self.assertEqual(report["failure"], "startup_result_invalid")

    def test_nonzero_process_is_refused(self):
        with mock.patch.dict(os.environ, {"STARTUP_FIXTURE_FAIL": "yes"}):
            report, code = self.run_fixture()
        self.assertEqual(code, 4)
        self.assertEqual(report["failure"], "startup_process_failed")
