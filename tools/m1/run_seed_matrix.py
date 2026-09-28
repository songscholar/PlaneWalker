#!/usr/bin/env python3
"""Run the canonical Godot M1 seed matrix and write deterministic evidence."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from m1_gate import make_seed_matrix, validate_seed_matrix


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUILD_VERSION = "0.4.0-dev"
FAILURE_MARKERS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed to load script",
    "ObjectDB instances leaked at exit",
    "RID allocations leaked at exit",
)


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
        "--raw-results",
        help="validated offline adapter input; skips Godot but remains synthetic repository evidence",
    )
    args = parser.parse_args()
    if args.seed_start != 0 or args.seed_count != 30:
        parser.error("official M1 evidence requires the canonical seed range 0 through 29")
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")

    cohort = {
        "build_version": args.build_version,
        "commit": args.commit or _git_commit(),
        "content_version": args.content_version or _content_version(),
    }
    if args.raw_results:
        raw = _load_json(Path(args.raw_results))
    else:
        raw = _run_godot_probe(
            args.godot_bin,
            seed_start=args.seed_start,
            seed_count=args.seed_count,
            timeout_seconds=args.timeout_seconds,
        )
    runs = raw.get("runs") if isinstance(raw, dict) else None
    if not isinstance(runs, list):
        raise SystemExit("raw seed probe did not produce a runs array")
    report = make_seed_matrix(
        runs,
        cohort=cohort,
        seed_start=args.seed_start,
        seed_count=args.seed_count,
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
        "reasons": list(validation.reasons),
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
    executable = _resolve_executable(godot_command)
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


def _git_commit() -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    commit = completed.stdout.strip().lower()
    if completed.returncode != 0 or not commit:
        raise SystemExit("could not resolve the current Git commit; pass --commit explicitly")
    return commit


def _content_version() -> str:
    catalog = _load_json(PROJECT_ROOT / "data" / "encounters" / "m1_encounters.json")
    value = catalog.get("plan_id") if isinstance(catalog, dict) else None
    if not isinstance(value, str) or not value:
        raise SystemExit("encounter catalog does not declare plan_id; pass --content-version explicitly")
    return value


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
