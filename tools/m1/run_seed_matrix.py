#!/usr/bin/env python3
"""Run the canonical Godot M1 seed matrix and write deterministic evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from m1_gate import PROBE_VERSION, make_seed_matrix, validate_seed_matrix


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUILD_VERSION = "0.4.0-dev"
FAILURE_MARKERS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed to load script",
    "ObjectDB instances leaked at exit",
    "RID allocations leaked at exit",
)
MACOS_CA_ERROR = 'ERROR: Condition "ret != noErr" is true. Returning: ""'
MACOS_CA_CALLSITE = "at: get_system_ca_certificates (platform/macos/os_macos.mm:"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-start", type=int, default=0)
    parser.add_argument("--seed-count", type=int, default=30)
    parser.add_argument("--output", required=True)
    parser.add_argument("--build-version", default=os.environ.get("PLANEWALKER_BUILD_VERSION", DEFAULT_BUILD_VERSION))
    parser.add_argument("--commit", default=None)
    parser.add_argument("--content-version", default=None)
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument(
        "--allow-dirty-candidate",
        action="store_true",
        help="allow a real Godot probe on a dirty tree, always classified non-release",
    )
    parser.add_argument(
        "--raw-results",
        help="validated offline adapter input; skips Godot but remains synthetic repository evidence",
    )
    args = parser.parse_args()
    if args.seed_start != 0 or args.seed_count != 30:
        parser.error("official M1 evidence requires the canonical seed range 0 through 29")
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")

    head_commit = _git_value("rev-parse", "HEAD", label="current Git commit")
    tree_digest = _git_value("rev-parse", "HEAD^{tree}", label="HEAD tree digest")
    worktree_clean = _git_worktree_clean()
    catalog_path = PROJECT_ROOT / "data" / "encounters" / "m1_encounters.json"
    catalog = _load_json(catalog_path)
    catalog_content_version = catalog.get("plan_id") if isinstance(catalog, dict) else None
    if not isinstance(catalog_content_version, str) or not catalog_content_version:
        raise SystemExit("encounter catalog does not declare a non-blank plan_id")
    if args.commit is not None and args.commit != head_commit:
        raise SystemExit("--commit must equal the current HEAD commit")
    if args.content_version is not None and args.content_version != catalog_content_version:
        raise SystemExit("--content-version must equal the encounter catalog plan_id")
    cohort = {
        "build_version": args.build_version,
        "commit": head_commit,
        "content_version": catalog_content_version,
    }
    if args.raw_results:
        raw = _load_json(Path(args.raw_results))
        evidence_origin = "raw_results_adapter"
        classification = "non_release_synthetic"
        godot_version = "not_executed"
    else:
        if not worktree_clean and not args.allow_dirty_candidate:
            raise SystemExit(
                "official Godot seed evidence requires a clean worktree; "
                "use --allow-dirty-candidate only for non-release diagnostics"
            )
        executable = _resolve_executable(args.godot_bin)
        godot_version = _godot_version(executable)
        raw = _run_godot_probe(
            executable,
            seed_start=args.seed_start,
            seed_count=args.seed_count,
            timeout_seconds=args.timeout_seconds,
        )
        if raw.get("probe_version") != PROBE_VERSION:
            raise SystemExit(
                f"Godot probe version mismatch: expected {PROBE_VERSION}, got {raw.get('probe_version')!r}"
            )
        evidence_origin = "godot_authoritative_probe"
        classification = "release" if worktree_clean else "non_release_candidate"
    runs = raw.get("runs") if isinstance(raw, dict) else None
    if not isinstance(runs, list):
        raise SystemExit("raw seed probe did not produce a runs array")
    report = make_seed_matrix(
        runs,
        cohort=cohort,
        seed_start=args.seed_start,
        seed_count=args.seed_count,
        evidence={
            "evidence_origin": evidence_origin,
            "classification": classification,
            "probe_version": PROBE_VERSION,
            "worktree_clean": worktree_clean,
            "head_commit": head_commit,
            "tree_digest": tree_digest,
            "probe_digest": _sha256_file(PROJECT_ROOT / "tools" / "m1" / "seed_matrix_probe.gd"),
            "godot_version": godot_version,
            "content_digest": _sha256_file(catalog_path),
            "catalog_content_version": catalog_content_version,
        },
    )
    validation = validate_seed_matrix(report)
    _write_json_atomic(Path(args.output), report)
    failed_runs = [
        run
        for run in report["runs"]
        if run.get("terminal_state") != "victory" or run.get("failure_codes")
    ]
    summary = {
        "output": str(Path(args.output)),
        "matrix_digest": report["matrix_digest"],
        "seed_count": len(report["runs"]),
        "failed_runs": len(failed_runs),
        "valid": validation.passed,
        "release_eligible": validation.release_eligible,
        "reasons": list(validation.reasons),
        "release_reasons": list(validation.release_reasons),
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0 if validation.passed and not failed_runs else 1


def _run_godot_probe(
    godot_command: str,
    *,
    seed_start: int,
    seed_count: int,
    timeout_seconds: int,
) -> dict:
    executable = godot_command
    with tempfile.TemporaryDirectory(prefix="planewalker-m1-seeds-") as temp_dir:
        temp = Path(temp_dir)
        raw_path = temp / "raw.json"
        engine_log = temp / "godot.log"
        environment = os.environ.copy()
        environment.update(
            {
                "PLANEWALKER_M1_SEED_START": str(seed_start),
                "PLANEWALKER_M1_SEED_COUNT": str(seed_count),
                "PLANEWALKER_M1_RAW_OUTPUT": str(raw_path),
            }
        )
        command = [
            executable,
            "--headless",
            "--path",
            str(PROJECT_ROOT),
            "--log-file",
            str(engine_log),
            "res://tools/m1/seed_matrix_probe.tscn",
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=PROJECT_ROOT,
                env=environment,
                capture_output=True,
                check=False,
                text=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired as error:
            raise SystemExit(f"Godot seed probe timed out after {timeout_seconds}s") from error
        engine_text = engine_log.read_text(encoding="utf-8", errors="replace") if engine_log.exists() else ""
        combined = completed.stdout + "\n" + completed.stderr + "\n" + engine_text
        failures = [marker for marker in FAILURE_MARKERS if marker in combined]
        unapproved_errors = _unapproved_error_lines(combined)
        if unapproved_errors:
            failures.append("unapproved ERROR lines: " + " | ".join(unapproved_errors))
        if completed.returncode != 0 or failures or not raw_path.exists():
            tail = "\n".join(combined.splitlines()[-120:])
            raise SystemExit(
                "Godot seed probe failed "
                f"(exit={completed.returncode}, markers={failures}, raw_output={raw_path.exists()})\n{tail}"
            )
        return _load_json(raw_path)


def _resolve_executable(command: str) -> str:
    if "/" in command:
        path = Path(command)
        if not path.is_file() or not os.access(path, os.X_OK):
            raise SystemExit(f"Godot executable is not runnable: {command}")
        return str(path)
    resolved = shutil.which(command)
    if resolved is None:
        raise SystemExit(f"Godot executable not found: {command}")
    return resolved


def _git_value(*arguments: str, label: str) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    value = completed.stdout.strip().lower()
    if completed.returncode != 0 or not value:
        raise SystemExit(f"could not resolve {label}")
    return value


def _git_worktree_clean() -> bool:
    completed = subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        raise SystemExit("could not inspect Git worktree status")
    return not completed.stdout.strip()


def _godot_version(executable: str) -> str:
    completed = subprocess.run(
        [executable, "--version"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    version = (completed.stdout or completed.stderr).strip().splitlines()
    if completed.returncode != 0 or not version:
        raise SystemExit("could not resolve the Godot runtime version")
    return version[0].strip()


def _sha256_file(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise SystemExit(f"could not hash {path}: {error}") from error


def _unapproved_error_lines(log_text: str) -> list[str]:
    errors = sorted({line.strip() for line in log_text.splitlines() if line.strip().startswith("ERROR:")})
    unapproved = [line for line in errors if line != MACOS_CA_ERROR]
    if MACOS_CA_ERROR in errors and MACOS_CA_CALLSITE not in log_text:
        unapproved.append("macOS CA sandbox error missing expected call site")
    return unapproved


def _load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"could not read JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"expected a JSON object in {path}")
    return value


def _write_json_atomic(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


if __name__ == "__main__":
    raise SystemExit(main())
