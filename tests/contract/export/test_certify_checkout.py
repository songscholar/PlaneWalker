from __future__ import annotations

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
        (self.root / ".gitattributes").write_text("* text=auto eol=lf\n", encoding="utf-8")
        (self.root / ".gitignore").write_text("build/\n", encoding="utf-8")
        validation = self.root / "tools" / "validate_project.sh"
        validation.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "if [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"fail\" ]]; then\n"
            "  printf '%s\\n' 'synthetic validation failure'\n"
            "  exit 9\n"
            "fi\n"
            "if [[ \"${FIXTURE_VALIDATION_MODE:-pass}\" == \"no_coverage\" ]]; then\n"
            "  printf '%s\\n' 'Code coverage: not collected'\n"
            "else\n"
            "  printf '%s\\n' 'Code coverage: collected (fixture)'\n"
            "fi\n"
            "printf '%s\\n' 'PASS: synthetic validation'\n",
            encoding="utf-8",
        )
        validation.chmod(0o755)
        exporter = tools / "build_exports.py"
        exporter.write_text(FAKE_EXPORTER, encoding="utf-8")
        exporter.chmod(0o755)

        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "core.autocrlf", "false"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "fixture@example.invalid"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.name", "Fixture"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=self.root, check=True)
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self._temporary.cleanup()

    def certify(self, *, allow_source_dirty_candidate: bool = False):
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
output = Path(args.evidence_output)
output.parent.mkdir(parents=True, exist_ok=True)
rendered = json.dumps(report, indent=2, sort_keys=True) + "\\n"
output.write_text(rendered, encoding="utf-8")
print(rendered, end="")
raise SystemExit(0 if status == "pass" else (3 if status == "blocked" else 4))
"""


if __name__ == "__main__":
    unittest.main()
