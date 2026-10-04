from __future__ import annotations

import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
EXPORT_TOOLS = PROJECT_ROOT / "tools" / "export"
sys.path.insert(0, str(EXPORT_TOOLS))

from artifact_evidence import describe_artifact, scan_export_logs  # noqa: E402
from build_exports import (  # noqa: E402
    EXIT_ENVIRONMENT_BLOCKED,
    EXIT_EXPORT_FAILED,
    EXIT_INVALID_CONTRACT,
    EXIT_PASS,
    run_exports,
)


TEMPLATE_FILES = (
    "windows_release_x86_64.exe",
    "linux_release.x86_64",
    "macos.zip",
)


class ArtifactEvidenceContractTest(unittest.TestCase):
    def test_file_evidence_contains_digest_size_and_relative_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifact = root / "build" / "windows" / "PlaneWalker.exe"
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b"plane-walker")

            evidence = describe_artifact(artifact, root, "file")

        self.assertEqual(
            evidence["sha256"],
            hashlib.sha256(b"plane-walker").hexdigest(),
        )
        self.assertEqual(evidence["size_bytes"], 12)
        self.assertEqual(evidence["path"], "build/windows/PlaneWalker.exe")
        self.assertEqual(evidence["digest_algorithm"], "sha256")
        self.assertEqual(evidence["file_count"], 1)

    def test_directory_digest_ignores_creation_order_and_mtime(self) -> None:
        with tempfile.TemporaryDirectory() as first_temp, tempfile.TemporaryDirectory() as second_temp:
            first_root = Path(first_temp)
            second_root = Path(second_temp)
            first_app = make_app_bundle(first_root, reverse=False)
            second_app = make_app_bundle(second_root, reverse=True)
            os.utime(first_app / "Contents" / "MacOS" / "PlaneWalker", (100, 100))
            os.utime(second_app / "Contents" / "MacOS" / "PlaneWalker", (900, 900))

            first = describe_artifact(first_app, first_root, "directory")
            second = describe_artifact(second_app, second_root, "directory")

        self.assertEqual(first["sha256"], second["sha256"])
        self.assertEqual(first["digest_algorithm"], "sha256-tree-v1")
        self.assertEqual(first["file_count"], 2)
        self.assertEqual(first["size_bytes"], second["size_bytes"])

    def test_directory_digest_changes_when_content_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = make_app_bundle(root, reverse=False)
            before = describe_artifact(app, root, "directory")
            (app / "Contents" / "Resources" / "game.pck").write_bytes(b"changed")
            after = describe_artifact(app, root, "directory")

        self.assertNotEqual(before["sha256"], after["sha256"])

    def test_artifact_kind_mismatch_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifact = root / "build" / "PlaneWalker.exe"
            artifact.parent.mkdir()
            artifact.write_bytes(b"fixture")

            with self.assertRaisesRegex(ValueError, "expected directory"):
                describe_artifact(artifact, root, "directory")

    def test_log_scanner_reports_runtime_failures_once(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            log = Path(temp) / "export.log"
            log.write_text(
                "SCRIPT ERROR: broken\n"
                "SCRIPT ERROR: broken\n"
                "ERROR: generic export failure\n"
                "WARNING: ObjectDB instances leaked at exit\n",
                encoding="utf-8",
            )

            failures = scan_export_logs([log])

        self.assertEqual(
            {entry["code"] for entry in failures},
            {"script_error", "engine_error", "object_leak"},
        )
        self.assertEqual(len(failures), 3)


class ExportExecutorContractTest(unittest.TestCase):
    def test_missing_templates_block_before_any_export_command(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            empty_templates = fixture.external_root / "empty-templates"

            report, exit_code = run_exports(
                fixture.root,
                (),
                str(fake_godot),
                empty_templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

            self.assertEqual(exit_code, EXIT_ENVIRONMENT_BLOCKED)
            self.assertEqual(report["status"], "blocked")
            self.assertEqual(
                {issue["code"] for issue in report["issues"]},
                {"template_missing"},
            )
            self.assertFalse(fixture.export_call_log.exists())
            self.assertTrue(all(target["command"] is None for target in report["targets"]))
            self.assertEqual(read_json(fixture.evidence_output), report)

    def test_successful_fake_exports_record_three_artifact_hashes(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            report, exit_code = run_exports(
                fixture.root,
                (),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

            self.assertEqual(exit_code, EXIT_PASS, report["issues"])
            self.assertEqual(report["status"], "pass")
            self.assertEqual(report["classification"], "local_export_candidate")
            self.assertEqual([target["status"] for target in report["targets"]], ["pass"] * 3)
            self.assertEqual(
                [target["artifact_evidence"]["kind"] for target in report["targets"]],
                ["file", "file", "directory"],
            )
            for target in report["targets"]:
                self.assertRegex(target["artifact_evidence"]["sha256"], r"^[0-9a-f]{64}$")
                editor = Path(target["command"][0])
                self.assertTrue(editor.is_relative_to(fixture.root.resolve() / "build"))
                self.assertEqual(editor.read_bytes(), fake_godot.read_bytes())
                self.assertTrue((editor.parent / "_sc_").is_file())
                template_link = editor.parent / "editor_data" / "export_templates" / "4.6.1.stable"
                self.assertEqual(template_link.resolve(), templates.resolve())
            self.assertEqual(len(fixture.export_call_log.read_text().splitlines()), 3)
            self.assertEqual(read_json(fixture.evidence_output), report)

    def test_single_target_requires_only_its_template(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            templates = fixture.external_root / "templates"
            templates.mkdir()
            (templates / "windows_release_x86_64.exe").write_bytes(b"fixture")

            report, exit_code = run_exports(
                fixture.root,
                ("windows-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

        self.assertEqual(exit_code, EXIT_PASS, report["issues"])
        self.assertEqual(report["preflight"]["status"], "pass")
        self.assertEqual(
            [target["id"] for target in report["preflight"]["targets"]],
            ["windows-x86_64"],
        )

    def test_script_error_log_fails_even_with_zero_exit(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "log_failure", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            report, exit_code = run_exports(
                fixture.root,
                ("windows-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

        self.assertEqual(exit_code, EXIT_EXPORT_FAILED)
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["targets"][0]["status"], "failed")
        self.assertIsNone(report["targets"][0]["artifact_evidence"])
        self.assertIn(
            "script_error",
            {failure["code"] for failure in report["targets"][0]["logs"]["failures"]},
        )

    def test_nonzero_export_exit_fails_even_when_artifact_exists(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "exit_failure", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            report, exit_code = run_exports(
                fixture.root,
                ("linux-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

        self.assertEqual(exit_code, EXIT_EXPORT_FAILED)
        self.assertEqual(report["targets"][0]["exit_code"], 7)
        self.assertIsNone(report["targets"][0]["artifact_evidence"])

    def test_stale_artifact_is_removed_before_missing_artifact_check(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "no_artifact", fixture.export_call_log)
            templates = make_templates(fixture.external_root)
            stale = fixture.root / "build" / "windows" / "PlaneWalker.exe"
            stale.parent.mkdir(parents=True)
            stale.write_bytes(b"stale")

            report, exit_code = run_exports(
                fixture.root,
                ("windows-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

            self.assertFalse(stale.exists())

        self.assertEqual(exit_code, EXIT_EXPORT_FAILED)
        self.assertIn("artifact_missing", {issue["code"] for issue in report["issues"]})

    def test_unknown_target_is_contract_error_without_export(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            report, exit_code = run_exports(
                fixture.root,
                ("not-a-target",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

            self.assertFalse(fixture.export_call_log.exists())

        self.assertEqual(exit_code, EXIT_INVALID_CONTRACT)
        self.assertEqual(report["status"], "error")
        self.assertIn("target_unknown", {issue["code"] for issue in report["issues"]})

    def test_duplicate_target_is_contract_error_without_export(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            report, exit_code = run_exports(
                fixture.root,
                ("windows-x86_64", "windows-x86_64"),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )

            self.assertFalse(fixture.export_call_log.exists())

        self.assertEqual(exit_code, EXIT_INVALID_CONTRACT)
        self.assertIn("target_duplicate", {issue["code"] for issue in report["issues"]})

    def test_export_timeout_fails_without_artifact_evidence(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "hang", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            report, exit_code = run_exports(
                fixture.root,
                ("windows-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                1,
                False,
            )

        self.assertEqual(exit_code, EXIT_EXPORT_FAILED)
        self.assertIn("export_timeout", {issue["code"] for issue in report["issues"]})
        self.assertIsNone(report["targets"][0]["artifact_evidence"])

    def test_dirty_repository_requires_explicit_candidate_flag(self) -> None:
        with export_fixture() as fixture:
            (fixture.root / "dirty.txt").write_text("dirty", encoding="utf-8")
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            templates = make_templates(fixture.external_root)

            blocked, blocked_exit = run_exports(
                fixture.root,
                ("windows-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                False,
            )
            candidate, candidate_exit = run_exports(
                fixture.root,
                ("windows-x86_64",),
                str(fake_godot),
                templates,
                fixture.evidence_output,
                fixture.log_dir,
                10,
                True,
            )

        self.assertEqual(blocked_exit, EXIT_ENVIRONMENT_BLOCKED)
        self.assertIn("worktree_dirty", {issue["code"] for issue in blocked["issues"]})
        self.assertEqual(candidate_exit, EXIT_PASS)
        self.assertEqual(candidate["classification"], "non_release_dirty_candidate")


class ExportExecutorCliContractTest(unittest.TestCase):
    def test_blocked_cli_stdout_matches_atomic_report(self) -> None:
        with export_fixture() as fixture:
            fake_godot = make_fake_godot(fixture.external_root, "success", fixture.export_call_log)
            result = subprocess.run(
                [
                    sys.executable,
                    str(EXPORT_TOOLS / "build_exports.py"),
                    "--project-root",
                    str(fixture.root),
                    "--godot-bin",
                    str(fake_godot),
                    "--templates-dir",
                    str(fixture.external_root / "empty-templates"),
                    "--evidence-output",
                    str(fixture.evidence_output),
                    "--log-dir",
                    str(fixture.log_dir),
                ],
                cwd=fixture.root,
                capture_output=True,
                text=True,
                check=False,
            )

            stdout_report = json.loads(result.stdout)
            file_report = read_json(fixture.evidence_output)

        self.assertEqual(result.returncode, EXIT_ENVIRONMENT_BLOCKED, result.stderr)
        self.assertEqual(stdout_report, file_report)
        self.assertEqual(stdout_report["status"], "blocked")


class ExportFixture:
    def __init__(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self._external_temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name)
        self.external_root = Path(self._external_temporary.name)
        self.evidence_output = self.root / "build" / "export-evidence" / "report.json"
        self.log_dir = self.root / "build" / "export-evidence" / "logs"
        self.export_call_log = self.root / "export-calls.log"

    def __enter__(self) -> "ExportFixture":
        (self.root / "data" / "toolchain").mkdir(parents=True)
        (self.root / "scenes").mkdir()
        for relative in (
            Path(".gitignore"),
            Path("project.godot"),
            Path("export_presets.cfg"),
            Path("data/toolchain/export_targets.json"),
        ):
            shutil.copy2(PROJECT_ROOT / relative, self.root / relative)
        (self.root / "scenes" / "main.tscn").write_text(
            "[gd_scene format=3]\n",
            encoding="utf-8",
        )
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "core.autocrlf", "false"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "fixture@example.invalid"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.name", "Fixture"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=self.root, check=True)
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self._temporary.cleanup()
        self._external_temporary.cleanup()


def export_fixture() -> ExportFixture:
    return ExportFixture()


def make_templates(root: Path) -> Path:
    templates = root / "templates"
    templates.mkdir(exist_ok=True)
    for name in TEMPLATE_FILES:
        (templates / name).write_bytes(b"fixture")
    return templates


def make_fake_godot(directory: Path, mode: str, export_call_log: Path) -> Path:
    executable = directory / f"godot-{mode}"
    call_log = shlex.quote(str(export_call_log))
    script = f"""#!/usr/bin/env bash
set -eu
if [[ "${{1:-}}" == "--version" ]]; then
  printf '%s\\n' '4.6.1.stable.official.fixture'
  exit 0
fi
engine_log=''
preset=''
artifact=''
while (( $# > 0 )); do
  case "$1" in
    --log-file) engine_log="$2"; shift 2 ;;
    --export-release) preset="$2"; artifact="$3"; shift 3 ;;
    *) shift ;;
  esac
done
printf '%s\\n' "${{preset}}" >> {call_log}
if [[ '{mode}' == 'hang' ]]; then sleep 2; fi
mkdir -p "$(dirname "${{engine_log}}")"
case '{mode}' in
  log_failure) printf '%s\\n' 'SCRIPT ERROR: synthetic export failure' >"${{engine_log}}" ;;
  *) printf '%s\\n' "exported ${{preset}}" >"${{engine_log}}" ;;
esac
case '{mode}' in
  no_artifact) ;;
  *)
    case "${{artifact}}" in
      *.app)
        mkdir -p "${{artifact}}/Contents/MacOS" "${{artifact}}/Contents/Resources"
        printf '%s' 'fixture-binary' >"${{artifact}}/Contents/MacOS/PlaneWalker"
        printf '%s' 'fixture-pack' >"${{artifact}}/Contents/Resources/game.pck"
        ;;
      *)
        mkdir -p "$(dirname "${{artifact}}")"
        printf '%s' 'fixture-binary' >"${{artifact}}"
        ;;
    esac
    ;;
esac
if [[ '{mode}' == 'exit_failure' ]]; then exit 7; fi
exit 0
"""
    executable.write_text(script, encoding="utf-8")
    executable.chmod(0o755)
    return executable


def make_app_bundle(root: Path, *, reverse: bool) -> Path:
    app = root / "build" / "macos" / "PlaneWalker.app"
    entries = [
        (app / "Contents" / "MacOS" / "PlaneWalker", b"binary"),
        (app / "Contents" / "Resources" / "game.pck", b"pack"),
    ]
    if reverse:
        entries.reverse()
    for path, content in entries:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    return app


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
