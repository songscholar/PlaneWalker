#!/usr/bin/env python3
"""Classify only configured, valid CSV derivatives during the first import."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from tools.validate_localization import CATALOG_COLUMNS, _configured_runtime_resources, _read_catalog


MISSING_RESOURCE = re.compile(
    r"^ERROR: (?:Cannot open file '(?P<open>res://[^']+\.translation)'|"
    r"Failed loading resource: (?P<load>res://.+\.translation))\.$"
)


def classify(root: Path, phase: str, errors: list[str]) -> tuple[list[str], list[str]]:
    if phase not in {"bootstrap", "clean"}:
        raise ValueError("unknown import phase")
    if phase == "clean":
        return errors, []
    root = root.resolve()
    resources, violations = _configured_runtime_resources(root)
    if violations:
        raise ValueError("; ".join(row.render() for row in violations))
    configured = set(resources)
    observed: dict[str, set[str]] = {}
    remaining: list[str] = []
    for line in errors:
        match = MISSING_RESOURCE.fullmatch(line)
        resource = (match.group("open") or match.group("load")) if match else ""
        locale = next((locale for locale in CATALOG_COLUMNS[1:] if resource.endswith(f".{locale}.translation")), "")
        if resource not in configured or not locale:
            remaining.append(line)
            continue
        stem = resource[:-len(f".{locale}.translation")]
        source = root / (stem[len("res://"):] + ".csv")
        if not source.resolve().is_relative_to(root):
            raise ValueError("translation CSV source escapes the repository")
        _, source_violations = _read_catalog(root, source)
        if source_violations:
            raise ValueError("; ".join(row.render() for row in source_violations))
        observed.setdefault(stem, set()).add(locale)
    for stem, locales in observed.items():
        expected = {f"{stem}.{locale}.translation" for locale in CATALOG_COLUMNS[1:]}
        if locales != set(CATALOG_COLUMNS[1:]) or not expected <= configured:
            raise ValueError(f"bootstrap import must miss either both generated translations or neither: {stem}")
    return remaining, sorted(observed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--phase", choices=["bootstrap", "clean"], required=True)
    parser.add_argument("--errors-file", type=Path, required=True)
    parser.add_argument("--remaining-errors-file", type=Path, required=True)
    args = parser.parse_args()
    try:
        remaining, regenerated = classify(args.project_root, args.phase, args.errors_file.read_text(encoding="utf-8").splitlines())
        args.remaining_errors_file.write_text("".join(line + "\n" for line in remaining), encoding="utf-8")
        for stem in regenerated:
            print(f"WARNING: bootstrap import generated translation resources were absent before bootstrap; both expected CSV derivatives were regenerated: {stem}", file=sys.stderr)
        return 0
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
