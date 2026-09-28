#!/usr/bin/env python3
"""Validate anonymous structured M1 playtest observations."""

from __future__ import annotations

import argparse
import json

from m1_gate import count_invalid_records, load_observations_jsonl


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    imported = load_observations_jsonl(args.path)
    report = {
        "path": args.path,
        "valid_observations": len(imported.observations),
        "invalid_observations": count_invalid_records(imported.violations),
        "violation_count": len(imported.violations),
        "violations": [item.to_dict() for item in imported.violations],
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print(f"Valid observations: {len(imported.observations)}")
        print(f"Invalid observation records: {report['invalid_observations']}")
        print(f"Field violations: {report['violation_count']}")
        for item in imported.violations:
            print(f"line {item.line or '-'} {item.code} {item.path}: {item.message}")
        if not imported.violations:
            print("Validation: PASS")
    return 1 if imported.violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
