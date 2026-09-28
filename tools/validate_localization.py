#!/usr/bin/env python3
"""Validate Plane Walker's source localization catalog and its references."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator


CATALOG_COLUMNS = ("keys", "en", "zh_CN")
RUNTIME_SOURCE_DIRS = ("autoload", "scripts")
LOCALIZED_CONTENT_FIELDS = frozenset(("name", "description"))
DERIVED_CONTENT_KEY_PREFIXES = {
    "archetype": "ARCHETYPE_",
    "risk": "RISK_",
}
REQUIRED_DOMAIN_KEYS = frozenset(
    (
        "ROOM_TYPE_COMBAT",
        "ROOM_TYPE_ELITE",
        "ROOM_TYPE_BOSS",
        "ROOM_TYPE_EVENT",
        "RESULT_DEATH",
        "RESULT_FLOOR_CLEARED",
    )
)
PERCENT_PLACEHOLDER_RE = re.compile(
    r"%(?!%)(?:[-+0#]*)(?:\d+|\*)?(?:\.(?:\d+|\*))?[diouxXfFeEgGcs]"
)
BRACE_PLACEHOLDER_RE = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")
TR_LITERAL_RE = re.compile(
    r"\btr\s*\(\s*(?P<quote>['\"])(?P<key>(?:\\.|(?!\1).)*)\1\s*\)",
    re.DOTALL,
)


@dataclass(frozen=True, order=True)
class Violation:
    code: str
    key: str
    path: str
    line: int
    message: str

    def render(self) -> str:
        location = self.path if self.line <= 0 else f"{self.path}:{self.line}"
        key_suffix = f" [{self.key}]" if self.key else ""
        return f"{location}: {self.code}{key_suffix}: {self.message}"


def validate_localization(project_root: Path | str) -> list[Violation]:
    root = Path(project_root).resolve()
    catalog_path = root / "data" / "localization" / "translations.csv"
    catalog, violations = _read_catalog(root, catalog_path)
    catalog_keys = set(catalog)

    violations.extend(_validate_required_domain_keys(root, catalog_path, catalog_keys))
    violations.extend(_validate_code_references(root, catalog_keys))
    violations.extend(_validate_content_references(root, catalog_keys))
    return sorted(violations)


def _validate_required_domain_keys(
    root: Path, catalog_path: Path, catalog_keys: set[str]
) -> list[Violation]:
    return [
        Violation(
            "missing-required-key",
            key,
            _relative_path(root, catalog_path),
            0,
            "fixed room/result domain key is absent from translations.csv",
        )
        for key in sorted(REQUIRED_DOMAIN_KEYS - catalog_keys)
    ]


def _read_catalog(
    root: Path, catalog_path: Path
) -> tuple[dict[str, tuple[str, str]], list[Violation]]:
    relative_path = _relative_path(root, catalog_path)
    if not catalog_path.is_file():
        return {}, [
            Violation(
                "missing-catalog",
                "",
                relative_path,
                0,
                "expected the authoritative localization CSV",
            )
        ]

    catalog: dict[str, tuple[str, str]] = {}
    violations: list[Violation] = []
    try:
        with catalog_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != list(CATALOG_COLUMNS):
                return {}, [
                    Violation(
                        "invalid-header",
                        "",
                        relative_path,
                        1,
                        f"expected columns {', '.join(CATALOG_COLUMNS)} in that order",
                    )
                ]

            for line_number, row in enumerate(reader, start=2):
                key = (row.get("keys") or "").strip()
                english = row.get("en") or ""
                chinese = row.get("zh_CN") or ""
                if not key:
                    violations.append(
                        Violation(
                            "empty-key",
                            "",
                            relative_path,
                            line_number,
                            "localization key must not be blank",
                        )
                    )
                    continue
                if key in catalog:
                    violations.append(
                        Violation(
                            "duplicate-key",
                            key,
                            relative_path,
                            line_number,
                            "localization key is already defined",
                        )
                    )
                else:
                    catalog[key] = (english, chinese)

                if not english.strip():
                    violations.append(
                        Violation(
                            "empty-en",
                            key,
                            relative_path,
                            line_number,
                            "English translation must not be blank",
                        )
                    )
                if not chinese.strip():
                    violations.append(
                        Violation(
                            "empty-zh_CN",
                            key,
                            relative_path,
                            line_number,
                            "Simplified Chinese translation must not be blank",
                        )
                    )

                english_placeholders = _extract_placeholders(english)
                chinese_placeholders = _extract_placeholders(chinese)
                if english_placeholders != chinese_placeholders:
                    violations.append(
                        Violation(
                            "placeholder-mismatch",
                            key,
                            relative_path,
                            line_number,
                            "placeholder sequence differs: "
                            f"en={english_placeholders}, zh_CN={chinese_placeholders}",
                        )
                    )
    except (OSError, csv.Error) as error:
        violations.append(
            Violation("invalid-catalog", "", relative_path, 0, str(error))
        )
    return catalog, violations


def _extract_placeholders(value: str) -> tuple[str, ...]:
    matches = [
        (match.start(), match.group(0))
        for pattern in (PERCENT_PLACEHOLDER_RE, BRACE_PLACEHOLDER_RE)
        for match in pattern.finditer(value)
    ]
    return tuple(token for _, token in sorted(matches))


def _validate_code_references(root: Path, catalog_keys: set[str]) -> list[Violation]:
    violations: list[Violation] = []
    for source_path in _runtime_gdscript_files(root):
        try:
            source = source_path.read_text(encoding="utf-8")
        except OSError as error:
            violations.append(
                Violation(
                    "unreadable-source",
                    "",
                    _relative_path(root, source_path),
                    0,
                    str(error),
                )
            )
            continue
        for match in TR_LITERAL_RE.finditer(source):
            key = _decode_literal(match.group("key"), match.group("quote"))
            if key in catalog_keys:
                continue
            violations.append(
                Violation(
                    "missing-code-key",
                    key,
                    _relative_path(root, source_path),
                    source.count("\n", 0, match.start()) + 1,
                    "literal tr() key is absent from translations.csv",
                )
            )
    return violations


def _runtime_gdscript_files(root: Path) -> Iterator[Path]:
    for directory_name in RUNTIME_SOURCE_DIRS:
        directory = root / directory_name
        if directory.is_dir():
            yield from sorted(directory.rglob("*.gd"))


def _decode_literal(value: str, quote: str) -> str:
    if quote == '"':
        try:
            return str(json.loads(f'"{value}"'))
        except json.JSONDecodeError:
            pass
    return value.replace(f"\\{quote}", quote).replace("\\\\", "\\")


def _validate_content_references(root: Path, catalog_keys: set[str]) -> list[Violation]:
    violations: list[Violation] = []
    reported_derived_keys: set[str] = set()
    data_root = root / "data"
    if not data_root.is_dir():
        return violations

    for content_path in sorted(data_root.rglob("*.json")):
        try:
            content = json.loads(content_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            violations.append(
                Violation(
                    "invalid-content-json",
                    "",
                    _relative_path(root, content_path),
                    getattr(error, "lineno", 0),
                    str(error),
                )
            )
            continue

        for field, key in _content_localization_references(content):
            if key in catalog_keys:
                continue
            violations.append(
                Violation(
                    "missing-content-key",
                    key,
                    _relative_path(root, content_path),
                    0,
                    f"localization value referenced by '{field}' is absent from translations.csv",
                )
            )
        for field, key in _content_derived_key_references(content):
            if key in catalog_keys or key in reported_derived_keys:
                continue
            reported_derived_keys.add(key)
            violations.append(
                Violation(
                    "missing-derived-key",
                    key,
                    _relative_path(root, content_path),
                    0,
                    f"localization key derived from '{field}' is absent from translations.csv",
                )
            )
    return violations


def _content_localization_references(value: object) -> Iterable[tuple[str, str]]:
    if isinstance(value, dict):
        for field, child in value.items():
            if isinstance(child, str) and (
                field in LOCALIZED_CONTENT_FIELDS or field.endswith("_key")
            ):
                if child.strip():
                    yield field, child.strip()
            elif isinstance(child, list) and field.endswith("_keys"):
                for key in child:
                    if isinstance(key, str) and key.strip():
                        yield field, key.strip()
            else:
                yield from _content_localization_references(child)
    elif isinstance(value, list):
        for child in value:
            yield from _content_localization_references(child)


def _content_derived_key_references(value: object) -> Iterable[tuple[str, str]]:
    if isinstance(value, dict):
        for field, child in value.items():
            prefix = DERIVED_CONTENT_KEY_PREFIXES.get(field)
            if prefix is not None and isinstance(child, str) and child.strip():
                yield field, prefix + child.strip().upper()
            else:
                yield from _content_derived_key_references(child)
    elif isinstance(value, list):
        for child in value:
            yield from _content_derived_key_references(child)


def _relative_path(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "project_root",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Plane Walker project root (defaults to the tool's parent project)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    violations = validate_localization(args.project_root)
    if violations:
        for violation in violations:
            print(violation.render(), file=sys.stderr)
        print(
            f"FAIL: localization contract found {len(violations)} violation(s)",
            file=sys.stderr,
        )
        return 1
    print("PASS: localization contract is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
