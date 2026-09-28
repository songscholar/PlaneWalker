#!/usr/bin/env python3
"""Compare two canonical M1 seed reports for deterministic drift."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from m1_gate import compare_seed_matrices


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first")
    parser.add_argument("second")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    first = _load(Path(args.first))
    second = _load(Path(args.second))
    result = compare_seed_matrices(first, second)
    report = result.to_dict()
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print("Deterministic seed comparison: " + ("PASS" if result.matched else "FAIL"))
        print("Changed seeds: " + (", ".join(map(str, result.changed_seeds)) or "none"))
        for reason in result.reasons:
            print(f"- {reason}")
    return 0 if result.matched else 1


def _load(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"expected a JSON object in {path}")
    return value


if __name__ == "__main__":
    raise SystemExit(main())
