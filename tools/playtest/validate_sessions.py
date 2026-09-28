#!/usr/bin/env python3
"""Validate a Plane Walker playtest JSONL file."""

from __future__ import annotations

import argparse
import json

from playtest_data import load_jsonl


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="JSONL playtest session file")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args()
    result = load_jsonl(args.path)
    report = {
        "path": args.path,
        "valid_sessions": len(result.sessions),
        "violations": [item.to_dict() for item in result.violations],
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print(f"Valid sessions: {report['valid_sessions']}")
        if result.violations:
            for violation in result.violations:
                print(f"line {violation.line or '-'} {violation.code} {violation.path}: {violation.message}")
        else:
            print("Validation: PASS")
    return 1 if result.violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
