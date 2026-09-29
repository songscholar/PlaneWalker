#!/usr/bin/env python3
"""Certify validation and export evidence from a clean local detached clone."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Sequence

from build_exports import collect_git_state, git_output, utc_now
from preflight import write_json_atomic


EXIT_PASS = 0
EXIT_INVALID = 2
EXIT_BLOCKED = 3
EXIT_FAILED = 4


def certify_checkout(
    source_root: Path,
    commit: str,
    evidence_output: Path,
    log_dir: Path,
    godot_bin: str,
    templates_dir: Path | None,
    validation_timeout_seconds: int,
    export_timeout_seconds: int,
    allow_source_dirty_candidate: bool,
) -> tuple[dict[str, object], int]:
    """Clone a committed revision locally, validate it, then invoke export evidence."""

    source = source_root.expanduser().resolve()
    evidence_path = _source_path(source, evidence_output)
    logs_root = _source_path(source, log_dir)
    source_state = collect_git_state(source)
    resolved_commit = git_output(source, "rev-parse", f"{commit}^{{commit}}")
    issues: list[dict[str, object]] = []
    report: dict[str, object] = {
        "schema_version": "1.0.0",
        "generated_at_utc": utc_now(),
        "status": "error",
        "classification": "invalid_source",
        "certified": False,
        "remaining_gates": ["validation", "coverage", "exports", "packaged_startup"],
        "source": {
            "root": str(source),
            "requested_commit": commit,
            "resolved_commit": resolved_commit,
            "worktree_clean": bool(source_state.get("worktree_clean")),
            "dirty_paths": list(source_state.get("dirty_paths", [])),
            "dirty_candidate_allowed": allow_source_dirty_candidate,
        },
        "checkout": None,
        "validation": None,
        "export": None,
        "issues": issues,
    }

    if not source_state.get("available") or not resolved_commit:
        issues.append({
            "code": "source_revision_unavailable",
            "category": "error",
            "message": f"cannot resolve committed revision {commit} from {source}",
        })
        return _finish(report, evidence_path, EXIT_INVALID)
    if validation_timeout_seconds <= 0 or export_timeout_seconds <= 0:
        issues.append({
            "code": "timeout_invalid",
            "category": "error",
            "message": "validation and export timeouts must be positive integers",
        })
        return _finish(report, evidence_path, EXIT_INVALID)
    source_is_clean = bool(source_state.get("worktree_clean"))
    if not source_is_clean and not allow_source_dirty_candidate:
        report["status"] = "blocked"
        report["classification"] = "source_worktree_dirty"
        issues.append({
            "code": "source_worktree_dirty",
            "category": "blocked",
            "message": "detached certification requires a clean source worktree",
        })
        return _finish(report, evidence_path, EXIT_BLOCKED)

    logs_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="planewalker-certify-") as temp:
        checkout = Path(temp) / "checkout"
        clone_error = _clone_revision(source, checkout, resolved_commit)
        if clone_error is not None:
            issues.append({
                "code": "clone_failed",
                "category": "failed",
                "message": clone_error,
            })
            report["status"] = "failed"
            report["classification"] = "clone_failed"
            return _finish(report, evidence_path, EXIT_FAILED)

        checkout_before = collect_git_state(checkout)
        report["checkout"] = {
            "method": "git_clone_no_local_detached",
            "head_commit": checkout_before.get("head_commit"),
            "clean_before_validation": bool(checkout_before.get("worktree_clean")),
            "clean_after_execution": None,
        }
        if (
            checkout_before.get("head_commit") != resolved_commit
            or not checkout_before.get("worktree_clean")
        ):
            issues.append({
                "code": "checkout_not_clean",
                "category": "failed",
                "message": "local clone did not reproduce the requested clean revision",
            })
            report["status"] = "failed"
            report["classification"] = "checkout_not_clean"
            return _finish(report, evidence_path, EXIT_FAILED)

        validation = _run_validation(
            source,
            checkout,
            logs_root,
            validation_timeout_seconds,
        )
        report["validation"] = validation
        if validation["status"] != "pass":
            report["status"] = "failed"
            report["classification"] = "validation_failed"
            report["remaining_gates"] = ["validation", "coverage", "exports", "packaged_startup"]
            issues.append({
                "code": str(validation["failure_code"]),
                "category": "failed",
                "message": "clean detached validation did not pass",
            })
            checkout_after = collect_git_state(checkout)
            _set_checkout_after(report, checkout_after)
            return _finish(report, evidence_path, EXIT_FAILED)

        coverage_pending = validation.get("coverage_status") != "collected"
        if coverage_pending:
            issues.append({
                "code": "coverage_not_collected",
                "category": "blocked",
                "message": "clean detached validation did not produce a code coverage report",
            })
        report["remaining_gates"] = (
            ["coverage", "exports", "packaged_startup"]
            if coverage_pending
            else ["exports", "packaged_startup"]
        )
        export_report, export_exit = _run_export(
            source,
            checkout,
            logs_root,
            godot_bin,
            templates_dir,
            export_timeout_seconds,
        )
        report["export"] = export_report
        checkout_after = collect_git_state(checkout)
        _set_checkout_after(report, checkout_after)
        if not checkout_after.get("worktree_clean"):
            issues.append({
                "code": "checkout_dirty_after_execution",
                "category": "failed",
                "message": "validation or export modified tracked/untracked checkout state",
            })
            report["status"] = "failed"
            report["classification"] = "checkout_dirty_after_execution"
            return _finish(report, evidence_path, EXIT_FAILED)

        export_status = export_report.get("status") if isinstance(export_report, dict) else None
        if export_exit == EXIT_BLOCKED and export_status == "blocked":
            export_issue_codes = {
                str(issue.get("code"))
                for issue in export_report.get("issues", [])
                if isinstance(issue, dict)
            }
            report["status"] = "blocked"
            templates_only = export_issue_codes and export_issue_codes == {"template_missing"}
            if coverage_pending and templates_only:
                report["classification"] = "coverage_and_export_templates_pending"
            elif templates_only:
                report["classification"] = "export_templates_pending"
            elif coverage_pending:
                report["classification"] = "coverage_and_export_blocked"
            else:
                report["classification"] = "export_blocked"
            issues.extend(_copy_issues(export_report.get("issues")))
            return _finish(report, evidence_path, EXIT_BLOCKED)
        if export_exit != EXIT_PASS or export_status != "pass":
            report["status"] = "failed"
            report["classification"] = "export_failed"
            issues.append({
                "code": "export_failed",
                "category": "failed",
                "message": f"clean detached export exited {export_exit} with status {export_status}",
            })
            if isinstance(export_report, dict):
                issues.extend(_copy_issues(export_report.get("issues")))
            return _finish(report, evidence_path, EXIT_FAILED)

        if coverage_pending:
            report["status"] = "blocked"
            report["classification"] = "coverage_pending"
            report["remaining_gates"] = ["coverage", "packaged_startup"]
            return _finish(report, evidence_path, EXIT_BLOCKED)

        report["status"] = "pass"
        report["classification"] = (
            "detached_checkout_export_candidate"
            if source_is_clean
            else "non_release_dirty_source_candidate"
        )
        report["remaining_gates"] = ["packaged_startup"]
        return _finish(report, evidence_path, EXIT_PASS)


def _clone_revision(source: Path, checkout: Path, commit: str) -> str | None:
    try:
        clone = subprocess.run(
            [
                "git",
                "clone",
                "--no-local",
                "--no-checkout",
                "--quiet",
                str(source),
                str(checkout),
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if clone.returncode != 0:
            return clone.stderr.strip() or f"git clone exited {clone.returncode}"
        detached = subprocess.run(
            ["git", "-C", str(checkout), "checkout", "--detach", "--quiet", commit],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return str(error)
    if detached.returncode != 0:
        return detached.stderr.strip() or f"git checkout exited {detached.returncode}"
    return None


def _run_validation(
    source: Path,
    checkout: Path,
    logs_root: Path,
    timeout_seconds: int,
) -> dict[str, object]:
    stdout_log = logs_root / "validation.stdout.log"
    validation_log_dir = logs_root / "validation"
    validation_log_dir.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    environment["VALIDATION_LOG_DIR"] = str(validation_log_dir)
    environment["TEST_LOG_DIR"] = str(validation_log_dir / "scene-tests")
    command = [str(checkout / "tools" / "validate_project.sh")]
    started = time.monotonic()
    try:
        with stdout_log.open("w", encoding="utf-8") as output:
            completed = subprocess.run(
                command,
                cwd=checkout,
                env=environment,
                stdout=output,
                stderr=subprocess.STDOUT,
                check=False,
                text=True,
                timeout=timeout_seconds,
            )
        exit_code: int | None = completed.returncode
        failure_code = None if completed.returncode == 0 else "validation_process_failed"
    except subprocess.TimeoutExpired:
        exit_code = None
        failure_code = "validation_timeout"
    except OSError:
        exit_code = None
        failure_code = "validation_process_error"
    coverage_status = _coverage_status(stdout_log)
    return {
        "status": "pass" if failure_code is None else "failed",
        "failure_code": failure_code,
        "command": ["tools/validate_project.sh"],
        "exit_code": exit_code,
        "duration_ms": int((time.monotonic() - started) * 1000),
        "coverage_status": coverage_status,
        "stdout": _file_evidence(stdout_log, source),
    }


def _run_export(
    source: Path,
    checkout: Path,
    logs_root: Path,
    godot_bin: str,
    templates_dir: Path | None,
    timeout_seconds: int,
) -> tuple[dict[str, object], int]:
    export_report_path = logs_root / "export-report.json"
    export_stdout = logs_root / "export.stdout.log"
    command = [
        sys.executable,
        str(checkout / "tools" / "export" / "build_exports.py"),
        "--project-root",
        str(checkout),
        "--godot-bin",
        godot_bin,
        "--evidence-output",
        str(export_report_path),
        "--log-dir",
        str(logs_root / "export-logs"),
        "--timeout-seconds",
        str(timeout_seconds),
    ]
    if templates_dir is not None:
        command.extend(["--templates-dir", str(templates_dir.expanduser().resolve())])
    try:
        with export_stdout.open("w", encoding="utf-8") as output:
            completed = subprocess.run(
                command,
                cwd=checkout,
                env=dict(os.environ),
                stdout=output,
                stderr=subprocess.STDOUT,
                check=False,
                text=True,
                timeout=max(timeout_seconds * 3, timeout_seconds + 30),
            )
        exit_code = completed.returncode
    except subprocess.TimeoutExpired:
        return {
            "status": "failed",
            "issues": [{"code": "export_orchestrator_timeout", "category": "failed"}],
        }, EXIT_FAILED
    except OSError as error:
        return {
            "status": "failed",
            "issues": [{
                "code": "export_orchestrator_error",
                "category": "failed",
                "message": str(error),
            }],
        }, EXIT_FAILED

    try:
        value = json.loads(export_report_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "status": "failed",
            "issues": [{
                "code": "export_report_invalid",
                "category": "failed",
                "message": str(error),
            }],
        }, EXIT_FAILED
    if not isinstance(value, dict):
        return {
            "status": "failed",
            "issues": [{"code": "export_report_invalid", "category": "failed"}],
        }, EXIT_FAILED
    value["orchestrator_stdout"] = _file_evidence(export_stdout, source)
    return value, exit_code


def _set_checkout_after(report: dict[str, object], state: dict[str, object]) -> None:
    checkout = report.get("checkout")
    if isinstance(checkout, dict):
        checkout["clean_after_execution"] = bool(state.get("worktree_clean"))


def _file_evidence(path: Path, source: Path) -> dict[str, object]:
    digest = hashlib.sha256()
    size = 0
    if path.is_file():
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                size += len(chunk)
    return {
        "path": _display_path(path, source),
        "sha256": digest.hexdigest(),
        "size_bytes": size,
    }


def _coverage_status(stdout_log: Path) -> str:
    if not stdout_log.is_file():
        return "unknown"
    text = stdout_log.read_text(encoding="utf-8", errors="replace")
    if "Code coverage: not collected" in text:
        return "not_collected"
    if "Code coverage: collected" in text:
        return "collected"
    return "unknown"


def _copy_issues(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        return []
    return [dict(issue) for issue in value if isinstance(issue, dict)]


def _finish(
    report: dict[str, object],
    evidence_output: Path,
    exit_code: int,
) -> tuple[dict[str, object], int]:
    rendered = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    write_json_atomic(evidence_output, rendered)
    return report, exit_code


def _source_path(source: Path, path: Path) -> Path:
    expanded = path.expanduser()
    return expanded.resolve() if expanded.is_absolute() else (source / expanded).resolve()


def _display_path(path: Path, source: Path) -> str:
    try:
        return path.resolve().relative_to(source).as_posix()
    except ValueError:
        return str(path.resolve())


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate and export Plane Walker from a clean local detached clone.",
    )
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    parser.add_argument("--commit", default="HEAD")
    parser.add_argument(
        "--evidence-output",
        type=Path,
        default=Path("build/export-evidence/certification-report.json"),
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=Path("build/export-evidence/certification-logs"),
    )
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--templates-dir", type=Path)
    parser.add_argument("--validation-timeout-seconds", type=int, default=1800)
    parser.add_argument("--export-timeout-seconds", type=int, default=900)
    parser.add_argument("--allow-source-dirty-candidate", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    report, exit_code = certify_checkout(
        args.source_root,
        args.commit,
        args.evidence_output,
        args.log_dir,
        args.godot_bin,
        args.templates_dir,
        args.validation_timeout_seconds,
        args.export_timeout_seconds,
        args.allow_source_dirty_candidate,
    )
    sys.stdout.write(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
