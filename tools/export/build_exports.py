#!/usr/bin/env python3
"""Run validated Godot exports and record fail-closed artifact evidence."""

from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence

from artifact_evidence import describe_artifact, scan_export_logs
from preflight import (
    validate_contract,
    validate_local_environment,
    write_json_atomic,
)


EXIT_PASS = 0
EXIT_INVALID_CONTRACT = 2
EXIT_ENVIRONMENT_BLOCKED = 3
EXIT_EXPORT_FAILED = 4


def run_exports(
    project_root: Path,
    target_ids: Sequence[str],
    godot_bin: str,
    templates_dir: Path | None,
    evidence_output: Path,
    log_dir: Path,
    timeout_seconds: int,
    allow_dirty_candidate: bool,
) -> tuple[dict[str, object], int]:
    """Export selected targets after contract, Git, and toolchain gates pass."""

    root = project_root.expanduser().resolve()
    evidence_path = _project_path(root, evidence_output)
    logs_root = _project_path(root, log_dir)
    contract_report = validate_contract(root)
    available_targets = {
        str(target.get("id")): target
        for target in contract_report.get("targets", [])
        if isinstance(target, dict)
    }
    selected_ids = list(target_ids) if target_ids else list(available_targets)
    issues: list[dict[str, object]] = []

    report: dict[str, object] = {
        "schema_version": "1.0.0",
        "generated_at_utc": utc_now(),
        "status": "error",
        "classification": "invalid_contract",
        "project_root": str(root),
        "repository": collect_git_state(root),
        "preflight": contract_report,
        "targets": [],
        "issues": issues,
    }

    if contract_report.get("status") != "pass":
        issues.extend(_copy_issues(contract_report.get("issues")))
        return _finish(report, evidence_path, EXIT_INVALID_CONTRACT)

    unknown_targets = [target_id for target_id in selected_ids if target_id not in available_targets]
    if unknown_targets:
        for target_id in unknown_targets:
            issues.append({
                "code": "target_unknown",
                "category": "error",
                "message": f"unknown export target: {target_id}",
                "target": target_id,
            })
        return _finish(report, evidence_path, EXIT_INVALID_CONTRACT)
    if len(selected_ids) != len(set(selected_ids)):
        issues.append({
            "code": "target_duplicate",
            "category": "error",
            "message": "each export target may be selected only once",
        })
        return _finish(report, evidence_path, EXIT_INVALID_CONTRACT)
    if timeout_seconds <= 0:
        issues.append({
            "code": "timeout_invalid",
            "category": "error",
            "message": "timeout_seconds must be a positive integer",
        })
        return _finish(report, evidence_path, EXIT_INVALID_CONTRACT)

    target_records = [
        _new_target_record(available_targets[target_id])
        for target_id in selected_ids
    ]
    selected_set = set(selected_ids)
    report["targets"] = target_records

    repository = report["repository"]
    if not isinstance(repository, dict):
        raise ValueError("repository report has invalid shape")
    worktree_clean = bool(repository.get("worktree_clean"))
    if not worktree_clean and not allow_dirty_candidate:
        issues.append({
            "code": "worktree_dirty",
            "category": "blocked",
            "message": "exports require a clean tracked and untracked worktree",
        })

    local_report = _select_preflight_targets(
        validate_local_environment(contract_report, godot_bin, templates_dir),
        selected_set,
    )
    report["preflight"] = local_report
    for issue in _copy_issues(local_report.get("issues")):
        issues.append(issue)

    if issues:
        for target in target_records:
            target["status"] = "blocked"
        report["status"] = "blocked"
        report["classification"] = "blocked"
        return _finish(report, evidence_path, EXIT_ENVIRONMENT_BLOCKED)

    godot_details = local_report.get("godot")
    if not isinstance(godot_details, dict) or not godot_details.get("binary"):
        issues.append({
            "code": "godot_not_found",
            "category": "blocked",
            "message": "local preflight did not resolve a Godot executable",
        })
        for target in target_records:
            target["status"] = "blocked"
        report["status"] = "blocked"
        report["classification"] = "blocked"
        return _finish(report, evidence_path, EXIT_ENVIRONMENT_BLOCKED)
    resolved_godot = str(godot_details["binary"])

    any_failed = False
    for target in target_records:
        target_failed = _run_target(
            root,
            target,
            resolved_godot,
            logs_root,
            timeout_seconds,
            issues,
        )
        any_failed = target_failed or any_failed

    if any_failed:
        report["status"] = "failed"
        report["classification"] = "failed"
        return _finish(report, evidence_path, EXIT_EXPORT_FAILED)

    report["status"] = "pass"
    report["classification"] = (
        "local_export_candidate"
        if worktree_clean
        else "non_release_dirty_candidate"
    )
    return _finish(report, evidence_path, EXIT_PASS)


def _run_target(
    root: Path,
    target: dict[str, object],
    godot_binary: str,
    logs_root: Path,
    timeout_seconds: int,
    issues: list[dict[str, object]],
) -> bool:
    target_id = str(target["id"])
    artifact = root / str(target["artifact"])
    target_log_dir = logs_root / target_id
    stdout_log = target_log_dir / "stdout.log"
    engine_log = target_log_dir / "engine.log"
    _remove_previous_artifact(artifact)
    artifact.parent.mkdir(parents=True, exist_ok=True)
    target_log_dir.mkdir(parents=True, exist_ok=True)
    for path in (stdout_log, engine_log):
        if path.exists() or path.is_symlink():
            path.unlink()

    command = [
        godot_binary,
        "--headless",
        "--path",
        str(root),
        "--log-file",
        str(engine_log),
        "--export-release",
        str(target["preset"]),
        str(artifact),
    ]
    target["command"] = command
    target["logs"] = {
        "stdout": _display_path(stdout_log, root),
        "engine": _display_path(engine_log, root),
        "failures": [],
    }

    try:
        with stdout_log.open("w", encoding="utf-8") as output:
            completed = subprocess.run(
                command,
                cwd=root,
                stdout=output,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=timeout_seconds,
                text=True,
            )
    except subprocess.TimeoutExpired:
        target["exit_code"] = None
        target["status"] = "failed"
        issues.append({
            "code": "export_timeout",
            "category": "failed",
            "message": f"export target {target_id} exceeded {timeout_seconds}s",
            "target": target_id,
        })
        return True
    except OSError as error:
        target["exit_code"] = None
        target["status"] = "failed"
        issues.append({
            "code": "export_process_error",
            "category": "failed",
            "message": f"export target {target_id} could not start: {error}",
            "target": target_id,
        })
        return True

    target["exit_code"] = completed.returncode
    failures = scan_export_logs([stdout_log, engine_log])
    logs = target.get("logs")
    if isinstance(logs, dict):
        logs["failures"] = failures

    failed = False
    if completed.returncode != 0:
        failed = True
        issues.append({
            "code": "export_process_failed",
            "category": "failed",
            "message": f"export target {target_id} exited {completed.returncode}",
            "target": target_id,
        })
    if failures:
        failed = True
        issues.append({
            "code": "export_log_failure",
            "category": "failed",
            "message": f"export target {target_id} produced fatal log signatures",
            "target": target_id,
        })
    if failed:
        target["status"] = "failed"
        return True

    try:
        target["artifact_evidence"] = describe_artifact(
            artifact,
            root,
            str(target["artifact_kind"]),
        )
    except ValueError as error:
        issue_code = "artifact_missing" if not artifact.exists() else "artifact_invalid"
        issues.append({
            "code": issue_code,
            "category": "failed",
            "message": str(error),
            "target": target_id,
        })
        target["status"] = "failed"
        return True

    target["status"] = "pass"
    return False


def _new_target_record(target: dict[str, object]) -> dict[str, object]:
    return {
        "id": str(target["id"]),
        "status": "pending",
        "preset": str(target["preset"]),
        "platform": str(target["platform"]),
        "artifact": str(target["artifact"]),
        "artifact_kind": str(target["artifact_kind"]),
        "command": None,
        "exit_code": None,
        "logs": None,
        "artifact_evidence": None,
    }


def collect_git_state(root: Path) -> dict[str, object]:
    head = git_output(root, "rev-parse", "HEAD")
    status = git_output(root, "status", "--porcelain", "--untracked-files=all")
    available = head is not None and status is not None
    dirty_paths = status.splitlines() if status else []
    return {
        "available": available,
        "head_commit": head.strip() if head else None,
        "worktree_clean": available and not dirty_paths,
        "dirty_paths": dirty_paths,
    }


def git_output(root: Path, *arguments: str) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def _remove_previous_artifact(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def _finish(
    report: dict[str, object],
    evidence_output: Path,
    exit_code: int,
) -> tuple[dict[str, object], int]:
    rendered = json.dumps(
        report,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"
    write_json_atomic(evidence_output, rendered)
    return report, exit_code


def _copy_issues(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        return []
    return [dict(issue) for issue in value if isinstance(issue, dict)]


def _select_preflight_targets(
    report: dict[str, object],
    selected_ids: set[str],
) -> dict[str, object]:
    selected = copy.deepcopy(report)
    selected["targets"] = [
        target
        for target in selected.get("targets", [])
        if isinstance(target, dict) and target.get("id") in selected_ids
    ]
    selected["issues"] = [
        issue
        for issue in selected.get("issues", [])
        if isinstance(issue, dict)
        and (not issue.get("target") or issue.get("target") in selected_ids)
    ]
    if selected.get("status") != "error":
        selected["status"] = "blocked" if selected["issues"] else "pass"
    return selected


def _project_path(root: Path, path: Path) -> Path:
    expanded = path.expanduser()
    return expanded.resolve() if expanded.is_absolute() else (root / expanded).resolve()


def _display_path(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return str(path.resolve())


def utc_now() -> str:
    source_date_epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if source_date_epoch and source_date_epoch.isdigit():
        moment = datetime.fromtimestamp(int(source_date_epoch), tz=timezone.utc)
    else:
        moment = datetime.now(timezone.utc)
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Export Plane Walker targets and record artifact evidence.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument(
        "--godot-bin",
        default=os.environ.get("GODOT_BIN", "godot"),
    )
    parser.add_argument("--templates-dir", type=Path)
    parser.add_argument(
        "--evidence-output",
        type=Path,
        default=Path("build/export-evidence/export-report.json"),
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=Path("build/export-evidence/logs"),
    )
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--allow-dirty-candidate", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    report, exit_code = run_exports(
        args.project_root,
        args.target,
        args.godot_bin,
        args.templates_dir,
        args.evidence_output,
        args.log_dir,
        args.timeout_seconds,
        args.allow_dirty_candidate,
    )
    sys.stdout.write(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
