#!/usr/bin/env python3
"""Generate the formal M1 decision from seed and validated playtest evidence."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_ROOT / "playtest"))

from m1_gate import (  # noqa: E402
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
    parser.add_argument("--output", required=True, help="Markdown decision report")
    parser.add_argument("--json-output", help="machine-readable decision output")
    parser.add_argument("--tuning-output", help="machine-readable tuning input contract")
    args = parser.parse_args()

    seed_report = _load_json(Path(args.seed_report))
    sessions = load_jsonl(args.sessions) if args.sessions else ImportResult([], [])
    observations = load_observations_jsonl(args.observations) if args.observations else None
    decision = evaluate_m1(
        seed_report,
        sessions.sessions,
        session_violations=sessions.violations,
        observations=observations.observations if observations else [],
        observation_violations=observations.violations if observations else [],
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
                "output": args.output,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def _load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"expected a JSON object in {path}")
    return value


def _write_text_atomic(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(value.rstrip() + "\n", encoding="utf-8")
    temporary.replace(path)


def _write_json_atomic(path: Path, value: object) -> None:
    _write_text_atomic(path, json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    raise SystemExit(main())
