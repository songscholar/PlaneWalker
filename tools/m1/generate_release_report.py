#!/usr/bin/env python3
"""Generate the formal M1 decision from seed and validated playtest evidence."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = TOOLS_ROOT.parent
M1_TOOLS = TOOLS_ROOT / "m1"
sys.path.insert(0, str(TOOLS_ROOT / "playtest"))

from m1_gate import (  # noqa: E402
    M1_GO,
    compare_seed_matrices,
    evaluate_m1,
    load_observations_jsonl,
    render_release_report,
)
from playtest_data import ImportResult, load_jsonl  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-report", required=True)
    parser.add_argument("--sessions", help="validated playtest session JSONL; omit while external evidence is pending")
    parser.add_argument("--observations", help="structured M1 observation JSONL joined by anonymous session_id")
    parser.add_argument("--attestation", help="independent external approval manifest for the joined human cohort")
    parser.add_argument("--output", required=True, help="Markdown decision report")
    parser.add_argument("--json-output", help="machine-readable decision output")
    parser.add_argument("--tuning-output", help="machine-readable tuning input contract")
    parser.add_argument(
        "--require-go",
        action="store_true",
        help="exit non-zero unless the generated decision is exactly M1 Go",
    )
    args = parser.parse_args()

    seed_report = _load_json(Path(args.seed_report))
    sessions = load_jsonl(args.sessions) if args.sessions else ImportResult([], [])
    observations = load_observations_jsonl(args.observations) if args.observations else None
    attestation = _load_json(Path(args.attestation)) if args.attestation else None
    trusted_runtime_matrix_digest = _run_trusted_live_seed_verification(seed_report)
    decision = evaluate_m1(
        seed_report,
        sessions.sessions,
        session_violations=sessions.violations,
        observations=observations.observations if observations else [],
        observation_violations=observations.violations if observations else [],
        attestation=attestation,
        trusted_runtime_matrix_digest=trusted_runtime_matrix_digest,
    )
    _write_text_atomic(Path(args.output), render_release_report(decision))
    if args.json_output:
        _write_json_atomic(Path(args.json_output), decision.to_dict())
    if args.tuning_output:
        _write_json_atomic(Path(args.tuning_output), decision.tuning_input)
    print(
        json.dumps(
            {
                "state": decision.state,
                "seed_gate": decision.repository_gate["passed"],
                "human_sessions": decision.external_gate["human_sessions"],
                "joined_observations": decision.external_gate["joined_observations"],
                "attestation_approved": decision.external_gate["attestation"]["approved"],
                "release_ready": decision.state == M1_GO,
                "output": args.output,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0 if not args.require_go or decision.state == M1_GO else 2


def _load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"expected a JSON object in {path}")
    return value


def _run_trusted_live_seed_verification(seed_report: dict) -> str | None:
    evidence = seed_report.get("evidence")
    if not isinstance(evidence, dict):
        return None
    if (
        evidence.get("evidence_origin") != "godot_authoritative_probe"
        or evidence.get("classification") != "release"
    ):
        return None
    cohort = seed_report.get("cohort")
    if not isinstance(cohort, dict):
        return None
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    if head.returncode != 0 or cohort.get("commit") != head.stdout.strip().lower():
        return None
    build_version = cohort.get("build_version")
    if not isinstance(build_version, str) or not build_version.strip():
        return None
    with tempfile.TemporaryDirectory(prefix="planewalker-m1-live-verify-") as temp_dir:
        live_path = Path(temp_dir) / "seed-matrix.json"
        completed = subprocess.run(
            [
                sys.executable,
                str(M1_TOOLS / "run_seed_matrix.py"),
                "--seed-start",
                "0",
                "--seed-count",
                "30",
                "--build-version",
                build_version,
                "--output",
                str(live_path),
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            check=False,
            text=True,
        )
        if completed.returncode != 0 or not live_path.is_file():
            diagnostic = (completed.stderr or completed.stdout).strip()
            if diagnostic:
                print(f"trusted live seed verification failed: {diagnostic}", file=sys.stderr)
            return None
        live_report = _load_json(live_path)
    comparison = compare_seed_matrices(seed_report, live_report)
    if not comparison.matched:
        print(
            "trusted live seed verification mismatch: " + "; ".join(comparison.reasons),
            file=sys.stderr,
        )
        return None
    matrix_digest = live_report.get("matrix_digest")
    return matrix_digest if isinstance(matrix_digest, str) else None


def _write_text_atomic(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(value.rstrip() + "\n", encoding="utf-8")
    temporary.replace(path)


def _write_json_atomic(path: Path, value: object) -> None:
    _write_text_atomic(path, json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    raise SystemExit(main())
