#!/usr/bin/env python3
"""Evaluate the Wave 4D minimum-human-session evidence gate."""

from __future__ import annotations

import argparse
import json

from playtest_data import EvidenceGate, load_jsonl


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="validated JSONL playtest session file")
    parser.add_argument("--minimum-human", type=int, default=20)
    parser.add_argument("--build-version")
    parser.add_argument("--commit")
    parser.add_argument("--content-version")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args()
    imported = load_jsonl(args.path)
    gate = EvidenceGate(
        minimum_human_sessions=args.minimum_human,
        required_build_version=args.build_version,
        required_commit=args.commit,
        required_content_version=args.content_version,
    ).evaluate(imported.sessions)
    report = gate.to_dict()
    report["import_violations"] = [item.to_dict() for item in imported.violations]
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        state = "PASS" if gate.passed else "FAIL"
        print(f"20-session evidence gate: {state}")
        print(f"Human: {gate.human_sessions}/{gate.required_human_sessions}")
        print(f"Synthetic (never counted as human): {gate.synthetic_sessions}")
        for reason in gate.reasons:
            print(f"- {reason}")
        if imported.violations:
            print(f"- {len(imported.violations)} import violations")
    return 0 if gate.passed and not imported.violations else 1


if __name__ == "__main__":
    raise SystemExit(main())
