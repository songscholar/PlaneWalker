#!/usr/bin/env python3
"""Strip known identifiers and re-key playtest sessions into anonymous JSONL."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from playtest_data import deidentify_session, validate_session


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="source JSONL, including legacy records")
    parser.add_argument("output", help="destination JSONL")
    parser.add_argument("--salt", required=True, help="local non-identifying re-key salt")
    args = parser.parse_args()

    source = Path(args.input)
    destination = Path(args.output)
    output: list[str] = []
    errors: list[str] = []
    for line_number, raw_line in enumerate(source.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw_line.strip():
            continue
        try:
            session = json.loads(raw_line)
        except json.JSONDecodeError as error:
            errors.append(f"line {line_number}: invalid-json: {error.msg}")
            continue
        if not isinstance(session, dict):
            errors.append(f"line {line_number}: expected JSON object")
            continue
        cleaned = deidentify_session(session, salt=args.salt)
        violations = validate_session(cleaned)
        if violations:
            errors.append(
                f"line {line_number}: deidentified record is invalid: "
                + "; ".join(f"{item.code} {item.path}" for item in violations)
            )
            continue
        output.append(json.dumps(cleaned, ensure_ascii=False, separators=(",", ":"), sort_keys=True))

    if errors:
        for error in errors:
            print(error)
        return 1
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(output) + ("\n" if output else ""), encoding="utf-8")
    print(f"Wrote {len(output)} deidentified sessions to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
