#!/usr/bin/env python3
"""Summarize valid human playtest evidence while reporting synthetic count separately."""

from __future__ import annotations

import argparse
import json

from playtest_data import load_jsonl, summarize_sessions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="validated JSONL playtest session file")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args()
    imported = load_jsonl(args.path)
    report = summarize_sessions(imported.sessions)
    report["import_violations"] = [item.to_dict() for item in imported.violations]
    if args.json:
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        evidence = report["evidence"]
        metrics = report["human_metrics"]
        print(f"Human sessions: {evidence['human']}")
        print(f"Synthetic sessions (excluded from human metrics): {evidence['synthetic']}")
        print(f"Completion rate: {metrics['completion_rate']:.1%}")
        print(f"Average run duration: {metrics['average_duration_ms']:.0f} ms")
        print(f"Average damage taken: {metrics['average_damage_taken']:.1f}")
        if imported.violations:
            print(f"Import violations: {len(imported.violations)}")
    return 1 if imported.violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
