#!/usr/bin/env python3
"""Offline validation for Plane Walker documentation governance contracts."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path, PureWindowsPath
from typing import Iterable, Sequence
from urllib.parse import unquote, urlsplit


BASELINE_SCHEMA_VERSION = 1
REQUIRED_METADATA = (
    "Status",
    "Document Role",
    "Authority Level",
    "Applies To",
    "Owner",
    "Depends On",
    "Last Verified",
)
CURRENT_FORBIDDEN_STATUS_WORDS = (
    "completed",
    "historical",
    "archived",
    "superseded",
)
HISTORICAL_STATUS_WORDS = CURRENT_FORBIDDEN_STATUS_WORDS
ALLOWED_EXTERNAL_SCHEMES = {"http", "https", "mailto"}
METADATA_PATTERN = re.compile(r"^- ([A-Za-z][A-Za-z0-9 ]*):\s*(.*)$")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]\n]+\]\(([^)\n]+)\)")
INLINE_CODE_PATTERN = re.compile(r"(`+)(.*?)\1")
ISO_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ADR_FILENAME_PATTERN = re.compile(r"^\d{4}-[a-z0-9][a-z0-9-]*\.md$")
ADR_DECISION_STATUSES = {"Accepted", "Superseded"}


@dataclass(frozen=True, order=True)
class Violation:
    """One deterministic documentation contract violation."""

    code: str
    path: str
    line: int
    subject: str
    message: str

    @property
    def violation_id(self) -> str:
        return f"{self.path}::{self.code}::{self.subject}"


@dataclass(frozen=True)
class ValidationReport:
    """Repository validation result after applying an optional migration baseline."""

    violations: tuple[Violation, ...]
    allowed_violation_ids: tuple[str, ...]
    new_violation_ids: tuple[str, ...]
    stale_baseline_ids: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.new_violation_ids and not self.stale_baseline_ids

    def to_dict(self) -> dict[str, object]:
        return {
            "ok": self.ok,
            "violation_count": len(self.violations),
            "allowed_violation_ids": list(self.allowed_violation_ids),
            "new_violation_ids": list(self.new_violation_ids),
            "stale_baseline_ids": list(self.stale_baseline_ids),
            "violations": [
                {**asdict(violation), "violation_id": violation.violation_id}
                for violation in self.violations
            ],
        }


@dataclass(frozen=True)
class ParsedDocument:
    """Metadata and source lines extracted from one governed Markdown file."""

    relative_path: str
    lines: tuple[str, ...]
    title_line: int
    metadata: dict[str, str]
    metadata_lines: dict[str, int]
    metadata_end_index: int


def discover_governed_documents(project_root: Path) -> tuple[Path, ...]:
    """Return governed Markdown paths in stable repository-relative order."""

    docs_root = project_root / "docs"
    candidates: set[Path] = set()
    readme = docs_root / "README.md"
    if readme.is_file():
        candidates.add(readme)
    for relative_directory in (
        "current",
        "contracts",
        "adrs",
        "superpowers/specs",
        "superpowers/plans",
    ):
        directory = docs_root / relative_directory
        if directory.is_dir():
            candidates.update(path for path in directory.glob("*.md") if path.is_file())
    return tuple(sorted(candidates, key=lambda path: path.relative_to(project_root).as_posix()))


def validate_repository(
    project_root: Path,
    baseline_path: Path | None = None,
) -> ValidationReport:
    """Validate all governed documents below *project_root* without network access."""

    root = project_root.resolve()
    documents = discover_governed_documents(root)
    by_id: dict[str, Violation] = {}
    for path in documents:
        for violation in validate_document(root, path):
            by_id.setdefault(violation.violation_id, violation)
    for violation in _validate_adr_chain(root):
        by_id.setdefault(violation.violation_id, violation)
    violations = tuple(sorted(by_id.values()))
    allowed = load_baseline(baseline_path) if baseline_path is not None else ()
    actual_ids = set(by_id)
    allowed_ids = set(allowed)
    return ValidationReport(
        violations=violations,
        allowed_violation_ids=tuple(sorted(allowed_ids)),
        new_violation_ids=tuple(sorted(actual_ids - allowed_ids)),
        stale_baseline_ids=tuple(sorted(allowed_ids - actual_ids)),
    )


def validate_document(project_root: Path, path: Path) -> tuple[Violation, ...]:
    """Validate metadata, lifecycle, and local links for one Markdown document."""

    parsed, parse_violations = _parse_document(project_root, path)
    violations = list(parse_violations)
    if parsed is None:
        return tuple(violations)
    violations.extend(_validate_metadata(parsed))
    violations.extend(_validate_lifecycle(parsed))
    violations.extend(_validate_links(project_root, path, parsed))
    return tuple(violations)


def load_baseline(path: Path) -> tuple[str, ...]:
    """Load and validate the exact migration-baseline schema."""

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"baseline does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"baseline is not valid JSON: {path}: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError("baseline root must be an object")
    if payload.get("schema_version") != BASELINE_SCHEMA_VERSION:
        raise ValueError(
            f"baseline schema_version must be {BASELINE_SCHEMA_VERSION}"
        )
    allowed = payload.get("allowed_violation_ids")
    if not isinstance(allowed, list) or any(
        not isinstance(item, str) or not item for item in allowed
    ):
        raise ValueError("baseline allowed_violation_ids must be non-empty strings")
    if allowed != sorted(set(allowed)):
        raise ValueError("baseline allowed_violation_ids must be sorted and unique")
    if set(payload) != {"schema_version", "allowed_violation_ids"}:
        raise ValueError("baseline contains unsupported fields")
    return tuple(allowed)


def write_baseline(path: Path, violation_ids: Iterable[str]) -> None:
    """Write the exact sorted baseline schema."""

    payload = {
        "schema_version": BASELINE_SCHEMA_VERSION,
        "allowed_violation_ids": sorted(set(violation_ids)),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _parse_document(
    project_root: Path,
    path: Path,
) -> tuple[ParsedDocument | None, tuple[Violation, ...]]:
    relative_path = path.relative_to(project_root).as_posix()
    lines = tuple(path.read_text(encoding="utf-8").splitlines())
    first_content = next((index for index, line in enumerate(lines) if line.strip()), -1)
    if first_content < 0 or not lines[first_content].startswith("# "):
        return None, (
            Violation(
                "missing_title",
                relative_path,
                max(first_content + 1, 1),
                "H1",
                "governed documents must begin with a level-one Markdown title",
            ),
        )

    metadata: dict[str, str] = {}
    metadata_lines: dict[str, int] = {}
    violations: list[Violation] = []
    cursor = first_content + 1
    while cursor < len(lines) and not lines[cursor].strip():
        cursor += 1
    while cursor < len(lines):
        match = METADATA_PATTERN.match(lines[cursor])
        if match is None:
            break
        key, value = match.groups()
        if key in metadata:
            violations.append(
                Violation(
                    "duplicate_metadata",
                    relative_path,
                    cursor + 1,
                    key,
                    f"metadata field {key!r} appears more than once in the header",
                )
            )
        else:
            metadata[key] = value.strip()
            metadata_lines[key] = cursor + 1
        cursor += 1

    parsed = ParsedDocument(
        relative_path=relative_path,
        lines=lines,
        title_line=first_content + 1,
        metadata=metadata,
        metadata_lines=metadata_lines,
        metadata_end_index=cursor,
    )
    return parsed, tuple(violations)


def _validate_metadata(parsed: ParsedDocument) -> list[Violation]:
    violations: list[Violation] = []
    required = list(REQUIRED_METADATA)
    role = parsed.metadata.get("Document Role", "")
    if _is_plan(parsed.relative_path):
        if _role_lifecycle(role) == "current":
            required.append("Exit Gate")
        elif _role_lifecycle(role) == "historical":
            required.extend(("Implementation Status", "Completion Evidence"))

    for key in required:
        value = parsed.metadata.get(key)
        if value is None:
            violations.append(
                Violation(
                    "missing_metadata",
                    parsed.relative_path,
                    parsed.title_line,
                    key,
                    f"required metadata field {key!r} is missing from the header",
                )
            )
        elif not value:
            violations.append(
                Violation(
                    "empty_metadata",
                    parsed.relative_path,
                    parsed.metadata_lines[key],
                    key,
                    f"required metadata field {key!r} is empty",
                )
            )

    header_keys = set(parsed.metadata)
    for line_index, line in enumerate(
        parsed.lines[parsed.metadata_end_index :],
        parsed.metadata_end_index + 1,
    ):
        match = METADATA_PATTERN.match(line)
        if match is None:
            continue
        key = match.group(1)
        if key in REQUIRED_METADATA and key not in header_keys:
            violations.append(
                Violation(
                    "metadata_outside_header",
                    parsed.relative_path,
                    line_index,
                    key,
                    f"metadata field {key!r} must be in the block below the H1",
                )
            )

    verified = parsed.metadata.get("Last Verified")
    if verified and not _is_iso_date(verified):
        violations.append(
            Violation(
                "invalid_verified_date",
                parsed.relative_path,
                parsed.metadata_lines["Last Verified"],
                "Last Verified",
                "Last Verified must be a real ISO date in YYYY-MM-DD form",
            )
        )
    return violations


def _validate_lifecycle(parsed: ParsedDocument) -> list[Violation]:
    role = parsed.metadata.get("Document Role", "")
    status = parsed.metadata.get("Status", "")
    lifecycle = _role_lifecycle(role)
    if lifecycle is None:
        return [
            Violation(
                "ambiguous_lifecycle",
                parsed.relative_path,
                parsed.metadata_lines.get("Document Role", parsed.title_line),
                "Document Role",
                "Document Role must contain exactly one lifecycle word: Current or Historical",
            )
        ]
    lowered_status = status.casefold()
    if lifecycle == "current" and any(
        word in lowered_status for word in CURRENT_FORBIDDEN_STATUS_WORDS
    ):
        return [
            Violation(
                "lifecycle_status_mismatch",
                parsed.relative_path,
                parsed.metadata_lines.get("Status", parsed.title_line),
                "Status",
                "a Current document may not claim a Historical completion state",
            )
        ]
    if lifecycle == "historical" and not any(
        word in lowered_status for word in HISTORICAL_STATUS_WORDS
    ):
        return [
            Violation(
                "lifecycle_status_mismatch",
                parsed.relative_path,
                parsed.metadata_lines.get("Status", parsed.title_line),
                "Status",
                "a Historical document must declare Completed, Historical, Archived, or Superseded",
            )
        ]
    return []


def _validate_links(
    project_root: Path,
    path: Path,
    parsed: ParsedDocument,
) -> list[Violation]:
    violations: list[Violation] = []
    for line_number, destination in _markdown_destinations(parsed.lines):
        if not destination or destination.startswith("#"):
            continue
        parsed_url = urlsplit(destination)
        scheme = parsed_url.scheme.casefold()
        if scheme in ALLOWED_EXTERNAL_SCHEMES:
            continue
        if (
            scheme
            or destination.startswith("/")
            or PureWindowsPath(destination).is_absolute()
        ):
            violations.append(
                Violation(
                    "absolute_local_link",
                    parsed.relative_path,
                    line_number,
                    destination,
                    "repository-local Markdown links must be relative",
                )
            )
            continue
        raw_path = destination.split("#", 1)[0].split("?", 1)[0]
        decoded_path = unquote(raw_path)
        if not decoded_path:
            continue
        target = (path.parent / decoded_path).resolve(strict=False)
        if not _is_within(target, project_root):
            violations.append(
                Violation(
                    "link_outside_repository",
                    parsed.relative_path,
                    line_number,
                    destination,
                    "relative Markdown link resolves outside the repository",
                )
            )
            continue
        if not target.exists() or not _has_exact_case(project_root, target):
            violations.append(
                Violation(
                    "missing_link_target",
                    parsed.relative_path,
                    line_number,
                    destination,
                    "relative Markdown link target does not exist with exact case",
                )
            )
    return violations


def _validate_adr_chain(project_root: Path) -> list[Violation]:
    violations: list[Violation] = []
    adr_directory = project_root / "docs/adrs"
    index_path = adr_directory / "README.md"
    numbered_adrs = (
        tuple(
            sorted(
                (
                    path
                    for path in adr_directory.glob("*.md")
                    if ADR_FILENAME_PATTERN.fullmatch(path.name)
                ),
                key=lambda path: path.name,
            )
        )
        if adr_directory.is_dir()
        else ()
    )

    if not index_path.is_file():
        violations.append(
            Violation(
                "adr_index_missing",
                "docs/adrs/README.md",
                1,
                "README.md",
                "the governed ADR authority chain requires docs/adrs/README.md",
            )
        )

    for adr_path in numbered_adrs:
        parsed, _ = _parse_document(project_root, adr_path)
        if parsed is None:
            continue
        decision_status = parsed.metadata.get("Decision Status")
        if decision_status is None or not decision_status:
            violations.append(
                Violation(
                    "adr_decision_status_missing",
                    parsed.relative_path,
                    parsed.title_line,
                    "Decision Status",
                    "numbered ADRs require Decision Status in the metadata header",
                )
            )
        elif decision_status not in ADR_DECISION_STATUSES:
            violations.append(
                Violation(
                    "adr_decision_status_invalid",
                    parsed.relative_path,
                    parsed.metadata_lines["Decision Status"],
                    "Decision Status",
                    "Decision Status must be Accepted or Superseded",
                )
            )

    if not index_path.is_file():
        return violations

    index_parsed, _ = _parse_document(project_root, index_path)
    if index_parsed is None:
        return violations
    link_counts = {adr_path.resolve(): 0 for adr_path in numbered_adrs}
    for _line_number, destination in _markdown_destinations(index_parsed.lines):
        if not destination or destination.startswith("#"):
            continue
        if urlsplit(destination).scheme:
            continue
        raw_path = destination.split("#", 1)[0].split("?", 1)[0]
        if not raw_path:
            continue
        target = (index_path.parent / unquote(raw_path)).resolve(strict=False)
        if target in link_counts:
            link_counts[target] += 1

    for adr_path in numbered_adrs:
        count = link_counts[adr_path.resolve()]
        if count == 0:
            violations.append(
                Violation(
                    "adr_unindexed",
                    "docs/adrs/README.md",
                    index_parsed.title_line,
                    adr_path.name,
                    "every numbered ADR must be linked exactly once from the ADR index",
                )
            )
        elif count > 1:
            violations.append(
                Violation(
                    "adr_duplicate_index_link",
                    "docs/adrs/README.md",
                    index_parsed.title_line,
                    adr_path.name,
                    "a numbered ADR may appear only once in the ADR index",
                )
            )
    return violations


def _markdown_destinations(lines: Iterable[str]) -> Iterable[tuple[int, str]]:
    in_fence = False
    fence_marker = ""
    for line_number, source_line in enumerate(lines, 1):
        stripped = source_line.lstrip()
        marker_match = re.match(r"(```+|~~~+)", stripped)
        if marker_match:
            marker = marker_match.group(1)
            marker_char = marker[0]
            if not in_fence:
                in_fence = True
                fence_marker = marker_char
            elif marker_char == fence_marker:
                in_fence = False
                fence_marker = ""
            continue
        if in_fence:
            continue
        line = INLINE_CODE_PATTERN.sub("", source_line)
        for match in MARKDOWN_LINK_PATTERN.finditer(line):
            yield line_number, _normalize_markdown_destination(match.group(1))


def _normalize_markdown_destination(destination: str) -> str:
    value = destination.strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1].strip()
    if " " in value and not value.startswith(("http://", "https://", "mailto:")):
        value = value.split(maxsplit=1)[0]
    return value


def _role_lifecycle(role: str) -> str | None:
    has_current = re.search(r"\bcurrent\b", role, re.IGNORECASE) is not None
    has_historical = re.search(r"\bhistorical\b", role, re.IGNORECASE) is not None
    if has_current == has_historical:
        return None
    return "current" if has_current else "historical"


def _is_plan(relative_path: str) -> bool:
    return relative_path.startswith("docs/superpowers/plans/")


def _is_iso_date(value: str) -> bool:
    if ISO_DATE_PATTERN.fullmatch(value) is None:
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _has_exact_case(project_root: Path, target: Path) -> bool:
    try:
        relative = target.relative_to(project_root)
    except ValueError:
        return False
    cursor = project_root
    for part in relative.parts:
        if not cursor.is_dir():
            return False
        names = {child.name for child in cursor.iterdir()}
        if part not in names:
            return False
        cursor = cursor / part
    return True


def _resolve_cli_path(project_root: Path, path: Path | None) -> Path | None:
    if path is None:
        return None
    if path.is_absolute():
        return path
    return project_root / path


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate Plane Walker documentation governance offline.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--refresh-baseline", action="store_true")
    parser.add_argument("--json", action="store_true", dest="json_output")
    return parser


def _render_human(report: ValidationReport, baseline_path: Path | None) -> str:
    lines: list[str] = []
    for violation in report.violations:
        classification = (
            "BASELINED"
            if violation.violation_id in report.allowed_violation_ids
            else "ERROR"
        )
        lines.append(
            f"{classification}: {violation.path}:{violation.line}: "
            f"{violation.code}: {violation.message} [{violation.subject}]"
        )
    for violation_id in report.stale_baseline_ids:
        lines.append(f"ERROR: stale baseline entry: {violation_id}")
    lines.append(
        "Documentation governance: "
        f"violations={len(report.violations)} "
        f"baselined={len(report.allowed_violation_ids)} "
        f"new={len(report.new_violation_ids)} "
        f"stale={len(report.stale_baseline_ids)}"
    )
    if baseline_path is not None:
        lines.append(f"Baseline: {baseline_path}")
    lines.append("PASS" if report.ok else "FAIL")
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    project_root = args.project_root.resolve()
    baseline_path = _resolve_cli_path(project_root, args.baseline)
    try:
        if args.refresh_baseline:
            if baseline_path is None:
                raise ValueError("--refresh-baseline requires --baseline")
            unbaselined_report = validate_repository(project_root)
            write_baseline(
                baseline_path,
                (item.violation_id for item in unbaselined_report.violations),
            )
        report = validate_repository(project_root, baseline_path)
    except (OSError, UnicodeError, ValueError) as error:
        if args.json_output:
            print(json.dumps({"ok": False, "configuration_error": str(error)}))
        else:
            print(f"ERROR: {error}", file=sys.stderr)
        return 2

    if args.json_output:
        print(json.dumps(report.to_dict(), ensure_ascii=False, sort_keys=True))
    else:
        print(_render_human(report, baseline_path))
    return 0 if report.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
