#!/usr/bin/env python3
"""Fail closed on runtime errors; scene tests may declare exact refusal scopes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


PREFIX = "PLANEWALKER_EXPECTED_ENGINE_ERROR_"
BEGIN = PREFIX + "BEGIN "
END = PREFIX + "END "
FATAL = re.compile(r"SCRIPT ERROR:|Parse Error:|Error calling deferred method:|Failed to load script|Failed loading resource|Cannot open file .*\.gd|Cannot load resource|Invalid (?:call|get|set)(?:\.| )|String formatting error:|ObjectDB instances leaked|RID allocations leaked|resources still in use at exit|Pages in use exist at exit")
ERROR = re.compile(r"(?:^|\s)ERROR:")


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate scope field")
        result[key] = value
    return result


def _scope(text, beginning):
    try:
        value = json.loads(text, object_pairs_hook=_object)
    except (json.JSONDecodeError, ValueError) as error:
        raise ValueError("malformed expected-error scope JSON") from error
    keys = {"schema_version", "scope_id", "operation", "expected" if beginning else "result"}
    if not isinstance(value, dict) or set(value) != keys or type(value["schema_version"]) is not int or value["schema_version"] != 1 or not isinstance(value["scope_id"], str) or not re.fullmatch(r"-?[1-9][0-9]*:[1-9][0-9]*", value["scope_id"]):
        raise ValueError("invalid expected-error scope identity/schema")
    if not isinstance(value["operation"], str) or not value["operation"].strip() or any(ord(character) < 32 for character in value["operation"]):
        raise ValueError("scope must declare one explicit synchronous operation")
    if not beginning:
        if value["result"] is not False:
            raise ValueError("expected-error operation must finish with a false refusal result")
        return value
    expected = value["expected"]
    if not isinstance(expected, list) or not 1 <= len(expected) <= 16:
        raise ValueError("scope must declare bounded exact expected messages")
    seen = set()
    for item in expected:
        if not isinstance(item, dict) or set(item) != {"message", "count"} or not isinstance(item["message"], str) or not item["message"].strip() or any(ord(character) < 32 for character in item["message"]) or FATAL.search(item["message"]) or PREFIX in item["message"] or type(item["count"]) is not int or not 1 <= item["count"] <= 1000 or item["message"] in seen:
            raise ValueError("invalid exact expected-error message/count")
        seen.add(item["message"])
    return value


def validate_log(text, *, allow_expected_test_errors=False):
    active = None
    seen = set()
    completed = []
    counts = {}
    for number, line in enumerate(text.splitlines(), start=1):
        if FATAL.search(line):
            raise ValueError(f"runtime script failure or leak on line {number}: {line}")
        if PREFIX in line:
            if not allow_expected_test_errors:
                raise ValueError("expected-error scopes are enabled only for explicit scene-test validation")
            if line.startswith(BEGIN):
                if active is not None:
                    raise ValueError("nested expected-error scope")
                active = _scope(line[len(BEGIN):], True)
                if active["scope_id"] in seen:
                    raise ValueError("reused expected-error scope identity")
                seen.add(active["scope_id"])
                counts = {item["message"]: item["count"] for item in active["expected"]}
            elif line.startswith(END):
                ending = _scope(line[len(END):], False)
                if active is None or ending["scope_id"] != active["scope_id"] or ending["operation"] != active["operation"] or any(counts.values()):
                    raise ValueError("unmatched scope completion or missing expected errors")
                completed.append(active)
                active = None
                counts = {}
            else:
                raise ValueError("malformed expected-error marker")
            continue
        if ERROR.search(line):
            match = re.fullmatch(r"\s*ERROR: (.+)", line)
            message = match.group(1) if match else ""
            if active is None or message not in counts or counts[message] < 1:
                raise ValueError(f"unexpected engine error on line {number}: {line}")
            counts[message] -= 1
    if active is not None:
        raise ValueError("unclosed expected-error scope")
    return completed


def validate_logs(paths, *, allow_expected_test_errors=False):
    if not paths:
        raise ValueError("at least one actual runtime log is required")
    scopes = []
    for path in paths:
        path = Path(path)
        if not path.is_file():
            raise ValueError(f"required runtime log is missing: {path}")
        try:
            scopes.append(validate_log(path.read_text(encoding="utf-8", errors="strict"), allow_expected_test_errors=allow_expected_test_errors))
        except (UnicodeError, ValueError) as error:
            raise ValueError(f"{path}: {error}") from error
    if any(value != scopes[0] for value in scopes[1:]):
        raise ValueError("stdout and engine logs disagree about exact expected-error operations")
    return scopes[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-suite-scopes", action="store_true", help="permit only exact completed TestSuite refusal scopes")
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        validate_logs(args.logs, allow_expected_test_errors=args.test_suite_scopes)
    except ValueError as error:
        parser.exit(1, f"Runtime log validation failed: {error}\n")


if __name__ == "__main__":
    main()
