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
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[3]
EXPORT_TOOLS = PROJECT_ROOT / "tools" / "export"
sys.path.insert(0, str(EXPORT_TOOLS))

from certify_checkout import (  # noqa: E402
    EXIT_BLOCKED,
    EXIT_FAILED,
    EXIT_PASS,
    certify_checkout,
)


class DetachedCheckoutCertificationContractTest(unittest.TestCase):
    def test_dirty_source_blocks_before_clone_without_candidate_flag(self) -> None:
        with certification_fixture() as fixture:
            (fixture.root / "dirty.txt").write_text("dirty", encoding="utf-8")

            report, exit_code = fixture.certify(allow_source_dirty_candidate=False)

        self.assertEqual(exit_code, EXIT_BLOCKED)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["classification"], "source_worktree_dirty")
        self.assertIsNone(report["checkout"])
        self.assertIsNone(report["validation"])
        self.assertIsNone(report["export"])

    def test_validation_failure_stops_before_export(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "fail", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            report, exit_code = fixture.certify()

        self.assertEqual(exit_code, EXIT_FAILED)
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["classification"], "validation_failed")
        self.assertEqual(report["validation"]["exit_code"], 9)
        self.assertIsNone(report["export"])

    def test_export_blocker_is_preserved_after_clean_validation(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "pass", "FIXTURE_EXPORT_MODE": "blocked"},
        ):
            source_commit = fixture.head_commit()
            report, exit_code = fixture.certify()
            file_report = read_json(fixture.evidence_output)

        self.assertEqual(exit_code, EXIT_BLOCKED)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["classification"], "export_templates_pending")
        self.assertEqual(report["checkout"]["head_commit"], source_commit)
        self.assertTrue(report["checkout"]["clean_before_validation"])
        self.assertTrue(report["checkout"]["clean_after_execution"])
        self.assertEqual(report["validation"]["exit_code"], 0)
        self.assertEqual(report["export"]["status"], "blocked")
        self.assertFalse(report["certified"])
        self.assertEqual(file_report, report)

    def test_export_pass_remains_candidate_until_packaged_startup(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "pass", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            report, exit_code = fixture.certify()

        self.assertEqual(exit_code, EXIT_PASS)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["classification"], "detached_checkout_export_candidate")
        self.assertFalse(report["certified"])
        self.assertEqual(report["remaining_gates"], ["packaged_startup"])

    def test_missing_coverage_blocks_even_when_export_passes(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "no_coverage", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            report, exit_code = fixture.certify()

        self.assertEqual(exit_code, EXIT_BLOCKED)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["classification"], "coverage_pending")
        self.assertEqual(report["validation"]["coverage_status"], "not_collected")
        self.assertEqual(report["remaining_gates"], ["coverage", "packaged_startup"])
        self.assertIn("coverage_not_collected", {issue["code"] for issue in report["issues"]})

    def test_stdout_marker_cannot_spoof_collected_coverage(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "spoof_coverage", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            report, exit_code = fixture.certify()

        self.assertEqual(exit_code, EXIT_BLOCKED)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["classification"], "coverage_pending")
        self.assertEqual(report["validation"]["coverage_status"], "not_collected")
        self.assertEqual(report["validation"]["coverage"]["classification"], "report_missing")

    def test_untrusted_collector_artifact_cannot_spoof_coverage(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "untrusted_collector", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            report, exit_code = fixture.certify()

        self.assertEqual(exit_code, EXIT_BLOCKED)
        self.assertEqual(report["classification"], "coverage_pending")
        self.assertEqual(report["validation"]["coverage_status"], "invalid")
        self.assertEqual(
            report["validation"]["coverage"]["classification"],
            "collector_identity_invalid",
        )
        self.assertIn("coverage_evidence_invalid", {issue["code"] for issue in report["issues"]})

    def test_inconsistent_line_summary_cannot_spoof_coverage(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "inconsistent_coverage", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            report, exit_code = fixture.certify()

        self.assertEqual(exit_code, EXIT_BLOCKED)
        self.assertEqual(report["classification"], "coverage_pending")
        self.assertEqual(report["validation"]["coverage_status"], "invalid")
        self.assertEqual(
            report["validation"]["coverage"]["classification"],
            "file_missing_lines_mismatch",
        )

    def test_dirty_source_candidate_never_becomes_release_evidence(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ,
            {"FIXTURE_VALIDATION_MODE": "pass", "FIXTURE_EXPORT_MODE": "pass"},
        ):
            (fixture.root / "dirty.txt").write_text("dirty", encoding="utf-8")

            report, exit_code = fixture.certify(allow_source_dirty_candidate=True)

        self.assertEqual(exit_code, EXIT_PASS)
        self.assertEqual(report["classification"], "non_release_dirty_source_candidate")
        self.assertFalse(report["source"]["worktree_clean"])
        self.assertFalse(report["certified"])

    def test_verified_files_and_bundle_survive_detached_checkout_cleanup(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ, {"FIXTURE_EXPORT_ARTIFACTS": "valid"},
        ):
            destination = fixture.root / "build" / "retained"
            report, code = fixture.certify(artifact_dir=destination)
            retained = report["retained_artifacts"]
            self.assertEqual(code, EXIT_PASS)
            self.assertEqual(retained["status"], "pass")
            self.assertEqual(len(retained["targets"]), 2)
            binary = destination / "build/linux/PlaneWalker.x86_64"
            bundle = destination / "build/macos/PlaneWalker.app"
            self.assertEqual(binary.read_bytes(), b"fixture executable\n")
            self.assertTrue(os.access(binary, os.X_OK))
            self.assertEqual((bundle / "Contents/current").read_bytes(), b"fixture resource\n")
            self.assertTrue((bundle / "Contents/current").is_symlink())
            for target in retained["targets"]:
                original = next(row for row in report["export"]["targets"] if row["id"] == target["id"])
                self.assertEqual(target["artifact_evidence"], original["artifact_evidence"])
                self.assertTrue((fixture.root / target["retained_path"]).exists())

    def test_retention_refuses_existing_packages_without_overwriting_them(self) -> None:
        with certification_fixture() as fixture:
            destination = fixture.root / "build" / "retained"
            destination.mkdir(parents=True)
            previous = destination / "previous.bin"
            previous.write_bytes(b"previous candidate")
            report, code = fixture.certify(artifact_dir=destination)
            self.assertEqual(previous.read_bytes(), b"previous candidate")
        self.assertEqual(code, EXIT_BLOCKED)
        self.assertEqual(report["classification"], "artifact_destination_unavailable")
        self.assertIsNone(report["checkout"])

    def test_unverified_or_escaping_exports_cannot_be_retained(self) -> None:
        for mode in ["changed", "escaping", "external_symlink"]:
            with self.subTest(mode=mode), certification_fixture() as fixture, mock.patch.dict(
                os.environ, {"FIXTURE_EXPORT_ARTIFACTS": mode},
            ):
                report, code = fixture.certify(artifact_dir=fixture.root / "build/retained")
                self.assertEqual(code, EXIT_FAILED)
                self.assertEqual(report["classification"], "artifact_retention_failed")
                self.assertFalse(report["certified"])

    def test_host_startup_pass_removes_only_its_gate_even_without_coverage(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ, {"FIXTURE_VALIDATION_MODE": "no_coverage"},
        ):
            report, code = fixture.certify(verify_startup=True)
            startup = report["packaged_startup"]
            self.assertEqual(startup["status"], "pass")
            self.assertTrue((fixture.root / startup["retained_evidence"]["path"]).is_file())
        self.assertEqual(code, EXIT_BLOCKED)
        self.assertEqual(report["classification"], "coverage_pending")
        self.assertEqual(report["remaining_gates"], ["coverage"])
        self.assertFalse(report["certified"])

    def test_failed_packaged_startup_keeps_verified_exports_for_diagnosis(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ, {"FIXTURE_STARTUP_MODE": "fail", "FIXTURE_EXPORT_ARTIFACTS": "valid"},
        ):
            report, code = fixture.certify(
                verify_startup=True, artifact_dir=fixture.root / "build/retained",
            )
            self.assertEqual(report["retained_artifacts"]["status"], "pass")
        self.assertEqual(code, EXIT_FAILED)
        self.assertEqual(report["classification"], "packaged_startup_failed")
        self.assertIn("packaged_startup", report["remaining_gates"])
        self.assertFalse(report["certified"])

    def test_explicit_godot_argument_reaches_clean_validation(self) -> None:
        with certification_fixture() as fixture, mock.patch.dict(
            os.environ, {"GODOT_BIN": "unrelated-editor", "FIXTURE_EXPECTED_GODOT": "fixture-godot"},
        ):
            report, code = fixture.certify()
        self.assertEqual(code, EXIT_PASS)
        self.assertEqual(report["validation"]["status"], "pass")


class DetachedCheckoutCertificationCliContractTest(unittest.TestCase):
    def test_cli_stdout_matches_atomic_evidence(self) -> None:
        with certification_fixture() as fixture:
            environment = dict(os.environ)
            environment.update({
                "FIXTURE_VALIDATION_MODE": "pass",
                "FIXTURE_EXPORT_MODE": "blocked",
            })
            result = subprocess.run(
                [
                    sys.executable,
                    str(EXPORT_TOOLS / "certify_checkout.py"),
                    "--source-root",
                    str(fixture.root),
                    "--evidence-output",
                    str(fixture.evidence_output),
                    "--log-dir",
                    str(fixture.log_dir),
                    "--godot-bin",
                    "fixture-godot",
                    "--templates-dir",
                    str(fixture.root / "templates"),
                    "--validation-timeout-seconds",
                    "10",
                    "--export-timeout-seconds",
                    "10",
                ],
                cwd=fixture.root,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            stdout_report = json.loads(result.stdout)
            file_report = read_json(fixture.evidence_output)

        self.assertEqual(result.returncode, EXIT_BLOCKED, result.stderr)
        self.assertEqual(stdout_report, file_report)


class CertificationFixture:
    def __init__(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name)
        self.evidence_output = self.root / "build" / "certification" / "report.json"
        self.log_dir = self.root / "build" / "certification" / "logs"

    def __enter__(self) -> "CertificationFixture":
        tools = self.root / "tools" / "export"
        tools.mkdir(parents=True)
        scripts = self.root / "scripts"
        scripts.mkdir(parents=True)
        source = scripts / "fixture.gd"
        source.write_text("extends RefCounted\nfunc value() -> int:\n\treturn 1\n", encoding="utf-8")
        coverage_fixture = self.root / "tools" / "fixture-coverage.json"
        coverage_value = {
            "schema_version": "1.0.0",
            "status": "collected",
            "classification": "verified_instrumented_line_coverage",
            "language": "GDScript",
            "metric": "line",
            "collector": {
                "name": "planewalker-gdscript-line-coverage",
                "version": "1.0.0",
            },
            "provider": {
                "name": "fixture-instrumenter",
                "version": "1.0.0",
                "mode": "instrumented_runtime",
            },
            "provider_report": {
                "path": "tools/fixture-provider.json",
                "sha256": "a" * 64,
            },
            "summary": {
                "files": 1,
                "executable_lines": 2,
                "covered_lines": 2,
                "missing_lines": 0,
                "line_rate": 1.0,
            },
            "files": [
                {
                    "path": "scripts/fixture.gd",
                    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "executable_lines": [2, 3],
                    "covered_lines": [2, 3],
                    "missing_lines": [],
                    "executable_line_count": 2,
                    "covered_line_count": 2,
                    "line_rate": 1.0,
                }
            ],
            "capabilities": {
                "instrumented_line_hits": True,
                "source_digests_verified": True,
                "scene_counts_are_coverage": False,
            },
            "issues": [],
        }
        coverage_fixture.write_text(
            json.dumps(coverage_value, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        untrusted_coverage = dict(coverage_value)
        untrusted_coverage["collector"] = {
            "name": "stdout-marker-adapter",
            "version": "1.0.0",
        }
        (self.root / "tools" / "fixture-untrusted-coverage.json").write_text(
            json.dumps(untrusted_coverage, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        inconsistent_coverage = json.loads(json.dumps(coverage_value))
        inconsistent_coverage["files"][0]["missing_lines"] = [1]
        (self.root / "tools" / "fixture-inconsistent-coverage.json").write_text(
            json.dumps(inconsistent_coverage, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (self.root / ".gitattributes").write_text("* text=auto eol=lf\n", encoding="utf-8")
        (self.root / ".gitignore").write_text("build/\n", encoding="utf-8")
        validation = self.root / "tools" / "validate_project.sh"
        validation.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "if [[ -n \"${FIXTURE_EXPECTED_GODOT:-}\" && \"${GODOT_BIN}\" != \"${FIXTURE_EXPECTED_GODOT}\" ]]; then exit 8; fi\n"
            "if [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"fail\" ]]; then\n"
            "  printf '%s\\n' 'synthetic validation failure'\n"
            "  exit 9\n"
            "fi\n"
            "mkdir -p \"${TEST_LOG_DIR}\"\n"
            "if [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"no_coverage\" ]]; then\n"
            "  printf '%s\\n' '{\"schema_version\":\"1.0.0\",\"status\":\"unavailable\",\"classification\":\"fixture_unavailable\",\"language\":\"GDScript\",\"metric\":\"line\"}' >\"${TEST_LOG_DIR}/gdscript-coverage.json\"\n"
            "  printf '%s\\n' 'Code coverage: not collected'\n"
            "elif [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"spoof_coverage\" ]]; then\n"
            "  printf '%s\\n' 'Code coverage: collected (spoof only)'\n"
            "elif [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"untrusted_collector\" ]]; then\n"
            "  cp tools/fixture-untrusted-coverage.json \"${TEST_LOG_DIR}/gdscript-coverage.json\"\n"
            "  printf '%s\\n' 'Code coverage: collected (untrusted fixture)'\n"
            "elif [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"inconsistent_coverage\" ]]; then\n"
            "  cp tools/fixture-inconsistent-coverage.json \"${TEST_LOG_DIR}/gdscript-coverage.json\"\n"
            "  printf '%s\\n' 'Code coverage: collected (inconsistent fixture)'\n"
            "else\n"
            "  cp tools/fixture-coverage.json \"${TEST_LOG_DIR}/gdscript-coverage.json\"\n"
            "  printf '%s\\n' 'Code coverage: collected (fixture)'\n"
            "fi\n"
            "printf '%s\\n' 'PASS: synthetic validation'\n",
            encoding="utf-8",
        )
        validation.chmod(0o755)
        exporter = tools / "build_exports.py"
        exporter.write_text(FAKE_EXPORTER, encoding="utf-8")
        exporter.chmod(0o755)
        shutil.copyfile(EXPORT_TOOLS / "artifact_evidence.py", tools / "artifact_evidence.py")
        (tools / "verify_packaged_startup.py").write_text(FAKE_STARTUP, encoding="utf-8")

        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "core.autocrlf", "false"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "fixture@example.invalid"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.name", "Fixture"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=self.root, check=True)
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self._temporary.cleanup()

    def certify(self, *, allow_source_dirty_candidate: bool = False,
                artifact_dir: Path | None = None, verify_startup: bool = False):
        return certify_checkout(
            self.root,
            "HEAD",
            self.evidence_output,
            self.log_dir,
            "fixture-godot",
            self.root / "templates",
            10,
            10,
            allow_source_dirty_candidate,
            artifact_dir=artifact_dir,
            verify_startup=verify_startup,
        )

    def head_commit(self) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=self.root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()


def certification_fixture() -> CertificationFixture:
    return CertificationFixture()


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


FAKE_EXPORTER = """#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from artifact_evidence import describe_artifact

parser = argparse.ArgumentParser()
parser.add_argument("--project-root")
parser.add_argument("--godot-bin")
parser.add_argument("--templates-dir")
parser.add_argument("--evidence-output", required=True)
parser.add_argument("--log-dir")
parser.add_argument("--timeout-seconds")
args = parser.parse_args()
mode = os.environ.get("FIXTURE_EXPORT_MODE", "pass")
status = "pass" if mode == "pass" else ("blocked" if mode == "blocked" else "failed")
report = {
    "schema_version": "1.0.0",
    "status": status,
    "classification": "fixture",
    "issues": ([{"code": "template_missing", "category": "blocked"}] if status == "blocked" else []),
    "targets": [],
}
artifact_mode = os.environ.get("FIXTURE_EXPORT_ARTIFACTS", "none")
if status == "pass" and artifact_mode != "none":
    root = Path(args.project_root)
    binary = root / "build/linux/PlaneWalker.x86_64"
    binary.parent.mkdir(parents=True)
    binary.write_bytes(b"fixture executable\\n")
    binary.chmod(0o755)
    bundle = root / "build/macos/PlaneWalker.app"
    (bundle / "Contents").mkdir(parents=True)
    (bundle / "Contents/resource").write_bytes(b"fixture resource\\n")
    (bundle / "Contents/current").symlink_to("resource")
    for id_, artifact, kind in [("linux-x86_64", binary, "file"), ("macos-universal", bundle, "directory")]:
        report["targets"].append({
            "id": id_, "artifact": artifact.relative_to(root).as_posix(),
            "artifact_kind": kind, "status": "pass",
            "artifact_evidence": describe_artifact(artifact, root, kind),
        })
    if artifact_mode == "changed":
        binary.write_bytes(b"tampered after export")
    elif artifact_mode == "escaping":
        report["targets"][0]["artifact"] = "../outside.bin"
    elif artifact_mode == "external_symlink":
        (bundle / "Contents/current").unlink()
        (bundle / "Contents/current").symlink_to("../../../../outside.bin")
        report["targets"][1]["artifact_evidence"] = describe_artifact(bundle, root, "directory")
output = Path(args.evidence_output)
output.parent.mkdir(parents=True, exist_ok=True)
rendered = json.dumps(report, indent=2, sort_keys=True) + "\\n"
output.write_text(rendered, encoding="utf-8")
print(rendered, end="")
raise SystemExit(0 if status == "pass" else (3 if status == "blocked" else 4))
"""

FAKE_STARTUP = """#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--project-root", required=True)
parser.add_argument("--export-report", required=True)
parser.add_argument("--evidence-output", required=True)
parser.add_argument("--log-dir", required=True)
parser.add_argument("--timeout-seconds")
args = parser.parse_args()
assert Path(args.project_root).resolve() == Path.cwd().resolve()
assert json.loads(Path(args.export_report).read_text())["status"] == "pass"
logs = Path(args.log_dir)
logs.mkdir(parents=True)
(logs / "stdout.log").write_text("fixture native startup\\n")
failed = os.environ.get("FIXTURE_STARTUP_MODE", "pass") == "fail"
report = {
    "status": "failed" if failed else "pass",
    "classification": "packaged_startup_failed" if failed else "host_packaged_startup_verified",
    "failure": "runtime_log_failure" if failed else "",
    "full_product_certified": False,
}
output = Path(args.evidence_output)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report) + "\\n")
raise SystemExit(4 if failed else 0)
"""


if __name__ == "__main__":
    unittest.main()
