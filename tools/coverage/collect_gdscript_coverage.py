#!/usr/bin/env python3
"""Validate and normalize real GDScript line-hit coverage evidence.

The stock Godot 4.6.1 command line can profile script timing, but it does not
emit per-line execution counts. This collector therefore fails closed unless a
runtime instrumentation provider supplies file-level executable and covered
line sets tied to exact source digests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence


EXIT_COLLECTED = 0
EXIT_UNAVAILABLE = 3
EXIT_INVALID = 4
SCHEMA_VERSION = "1.0.0"
COLLECTOR_NAME = "planewalker-gdscript-line-coverage"
COLLECTOR_VERSION = "1.0.0"


def collect(
    project_root: Path,
    godot_bin: str,
    output: Path,
    provider_report: Path | None,
) -> tuple[dict[str, object], int]:
    root = project_root.expanduser().resolve()
    output_path = _resolve_output(root, output)
    engine = _probe_engine(godot_bin)

    if provider_report is None:
        report = _unavailable_report(engine)
        _write_json_atomic(output_path, report)
        return report, EXIT_UNAVAILABLE

    provider_path = provider_report.expanduser().resolve()
    try:
        provider_value = json.loads(provider_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        report = _invalid_report(
            engine,
            [{
                "code": "provider_report_unreadable",
                "message": str(error),
            }],
            provider_path,
        )
        _write_json_atomic(output_path, report)
        return report, EXIT_INVALID

    normalized, issues = _normalize_provider_report(root, provider_value)
    if issues:
        report = _invalid_report(engine, issues, provider_path)
        _write_json_atomic(output_path, report)
        return report, EXIT_INVALID

    files = normalized["files"]
    executable_total = sum(int(file_value["executable_line_count"]) for file_value in files)
    covered_total = sum(int(file_value["covered_line_count"]) for file_value in files)
    line_rate = round(covered_total / executable_total, 6) if executable_total else 0.0
    report: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "status": "collected",
        "classification": "verified_instrumented_line_coverage",
        "language": "GDScript",
        "metric": "line",
        "collector": {
            "name": COLLECTOR_NAME,
            "version": COLLECTOR_VERSION,
        },
        "engine": engine,
        "provider": normalized["provider"],
        "provider_report": {
            "path": str(provider_path),
            "sha256": _sha256(provider_path),
        },
        "summary": {
            "files": len(files),
            "executable_lines": executable_total,
            "covered_lines": covered_total,
            "missing_lines": executable_total - covered_total,
            "line_rate": line_rate,
        },
        "files": files,
        "capabilities": {
            "godot_cli_line_coverage": bool(engine.get("cli_line_coverage")),
            "instrumented_line_hits": True,
            "source_digests_verified": True,
            "scene_counts_are_coverage": False,
        },
        "issues": [],
    }
    _write_json_atomic(output_path, report)
    return report, EXIT_COLLECTED


def _normalize_provider_report(
    root: Path,
    value: object,
) -> tuple[dict[str, object], list[dict[str, str]]]:
    if not isinstance(value, dict):
        return {}, [_issue("provider_report_root_invalid", "provider report root must be an object")]
    if value.get("schema_version") != SCHEMA_VERSION:
        return {}, [_issue("provider_schema_invalid", f"schema_version must be {SCHEMA_VERSION}")]
    if value.get("status") != "collected":
        return {}, [_issue("provider_status_invalid", "provider status must be collected")]
    if value.get("language") != "GDScript" or value.get("metric") != "line":
        return {}, [_issue("provider_metric_invalid", "provider must report GDScript line coverage")]

    provider = value.get("provider")
    if not isinstance(provider, dict):
        return {}, [_issue("provider_identity_invalid", "provider identity is required")]
    if provider.get("mode") != "instrumented_runtime":
        return {}, [_issue(
            "provider_mode_invalid",
            "provider mode must be instrumented_runtime; scene counts and timing profiles are not line coverage",
        )]
    if not _nonempty_string(provider.get("name")) or not _nonempty_string(provider.get("version")):
        return {}, [_issue("provider_identity_invalid", "provider name and version are required")]

    files_value = value.get("files")
    if not isinstance(files_value, list) or not files_value:
        return {}, [_issue(
            "provider_line_hits_missing",
            "provider must include non-empty per-file executable_lines and covered_lines",
        )]

    normalized_files: list[dict[str, object]] = []
    seen_paths: set[str] = set()
    issues: list[dict[str, str]] = []
    for index, file_value in enumerate(files_value):
        normalized, file_issues = _normalize_file(root, file_value, index, seen_paths)
        issues.extend(file_issues)
        if normalized:
            normalized_files.append(normalized)
    if issues:
        return {}, issues
    return {
        "provider": {
            "name": str(provider["name"]),
            "version": str(provider["version"]),
            "mode": "instrumented_runtime",
        },
        "files": sorted(normalized_files, key=lambda item: str(item["path"])),
    }, []


def _normalize_file(
    root: Path,
    value: object,
    index: int,
    seen_paths: set[str],
) -> tuple[dict[str, object], list[dict[str, str]]]:
    label = f"files[{index}]"
    if not isinstance(value, dict):
        return {}, [_issue("coverage_file_invalid", f"{label} must be an object")]
    relative_value = value.get("path")
    if not _nonempty_string(relative_value):
        return {}, [_issue("coverage_path_invalid", f"{label}.path is required")]
    relative = Path(str(relative_value))
    if relative.is_absolute() or ".." in relative.parts or relative.suffix != ".gd":
        return {}, [_issue("coverage_path_invalid", f"{label}.path must be a project-relative .gd file")]
    normalized_path = relative.as_posix()
    if normalized_path in seen_paths:
        return {}, [_issue("coverage_path_duplicate", f"duplicate coverage path: {normalized_path}")]
    seen_paths.add(normalized_path)

    source = (root / relative).resolve()
    try:
        source.relative_to(root)
    except ValueError:
        return {}, [_issue("coverage_path_invalid", f"coverage path escapes project root: {normalized_path}")]
    if not source.is_file():
        return {}, [_issue("coverage_source_missing", f"coverage source does not exist: {normalized_path}")]
    expected_digest = value.get("source_sha256")
    actual_digest = _sha256(source)
    if expected_digest != actual_digest:
        return {}, [_issue("source_digest_mismatch", f"source digest changed: {normalized_path}")]

    executable, executable_error = _line_set(value.get("executable_lines"), f"{label}.executable_lines")
    if executable_error:
        return {}, [executable_error]
    covered, covered_error = _line_set(value.get("covered_lines"), f"{label}.covered_lines", allow_empty=True)
    if covered_error:
        return {}, [covered_error]
    if not set(covered).issubset(executable):
        return {}, [_issue("covered_line_not_executable", f"{label}.covered_lines must be a subset of executable_lines")]
    try:
        source_text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        return {}, [_issue(
            "coverage_source_unreadable",
            f"cannot read {normalized_path} as UTF-8 source: {error}",
        )]
    source_line_count = len(source_text.splitlines())
    if max(executable) > source_line_count:
        return {}, [_issue("coverage_line_out_of_range", f"{label} references a line past end of source")]
    missing = sorted(set(executable) - set(covered))
    return {
        "path": normalized_path,
        "source_sha256": actual_digest,
        "executable_lines": executable,
        "covered_lines": covered,
        "missing_lines": missing,
        "executable_line_count": len(executable),
        "covered_line_count": len(covered),
        "line_rate": round(len(covered) / len(executable), 6),
    }, []


def _line_set(
    value: object,
    label: str,
    *,
    allow_empty: bool = False,
) -> tuple[list[int], dict[str, str] | None]:
    if not isinstance(value, list) or (not value and not allow_empty):
        return [], _issue("coverage_lines_invalid", f"{label} must be a {'possibly empty' if allow_empty else 'non-empty'} list")
    if any(not isinstance(line, int) or isinstance(line, bool) or line <= 0 for line in value):
        return [], _issue("coverage_lines_invalid", f"{label} must contain positive integer line numbers")
    normalized = sorted(set(value))
    if len(normalized) != len(value):
        return [], _issue("coverage_lines_invalid", f"{label} must not contain duplicate line numbers")
    return normalized, None


def _unavailable_report(engine: dict[str, object]) -> dict[str, object]:
    cli_support = bool(engine.get("cli_line_coverage"))
    classification = "provider_not_configured" if cli_support else "godot_line_coverage_unsupported"
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "unavailable",
        "classification": classification,
        "language": "GDScript",
        "metric": "line",
        "collector": {"name": COLLECTOR_NAME, "version": COLLECTOR_VERSION},
        "engine": engine,
        "provider": None,
        "summary": {
            "files": 0,
            "executable_lines": 0,
            "covered_lines": 0,
            "missing_lines": 0,
            "line_rate": None,
        },
        "files": [],
        "capabilities": {
            "godot_cli_line_coverage": cli_support,
            "instrumented_line_hits": False,
            "source_digests_verified": False,
            "scene_counts_are_coverage": False,
        },
        "issues": [{
            "code": classification,
            "message": (
                "No trusted instrumented GDScript line-hit report was supplied. "
                "Godot --profiling timing and passed-scene counts are deliberately rejected as code coverage."
            ),
        }],
    }


def _invalid_report(
    engine: dict[str, object],
    issues: list[dict[str, str]],
    provider_path: Path,
) -> dict[str, object]:
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "invalid",
        "classification": "provider_report_invalid",
        "language": "GDScript",
        "metric": "line",
        "collector": {"name": COLLECTOR_NAME, "version": COLLECTOR_VERSION},
        "engine": engine,
        "provider": None,
        "provider_report": {"path": str(provider_path)},
        "summary": {
            "files": 0,
            "executable_lines": 0,
            "covered_lines": 0,
            "missing_lines": 0,
            "line_rate": None,
        },
        "files": [],
        "capabilities": {
            "godot_cli_line_coverage": bool(engine.get("cli_line_coverage")),
            "instrumented_line_hits": False,
            "source_digests_verified": False,
            "scene_counts_are_coverage": False,
        },
        "issues": issues,
    }


def _probe_engine(godot_bin: str) -> dict[str, object]:
    version = _run_probe([godot_bin, "--version"])
    help_text = _run_probe([godot_bin, "--help"])
    return {
        "command": godot_bin,
        "version": version.strip(),
        "help_sha256": hashlib.sha256(help_text.encode("utf-8")).hexdigest(),
        "cli_line_coverage": "--coverage" in help_text,
        "profiling_is_line_coverage": False,
    }


def _run_probe(command: list[str]) -> str:
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"unavailable: {error}"
    return completed.stdout + completed.stderr


def _resolve_output(root: Path, output: Path) -> Path:
    expanded = output.expanduser()
    return expanded.resolve() if expanded.is_absolute() else (root / expanded).resolve()


def _write_json_atomic(path: Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _issue(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


def _nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Normalize trusted runtime-instrumented GDScript line coverage evidence.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/coverage/gdscript-coverage.json"),
    )
    parser.add_argument("--provider-report", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    report, exit_code = collect(
        args.project_root,
        args.godot_bin,
        args.output,
        args.provider_report,
    )
    summary = report.get("summary", {})
    if report["status"] == "collected":
        covered = int(summary.get("covered_lines", 0))
        executable = int(summary.get("executable_lines", 0))
        rate = float(summary.get("line_rate", 0.0)) * 100.0
        print(f"Code coverage: collected (GDScript line {covered}/{executable}, {rate:.2f}%)")
    elif report["status"] == "unavailable":
        print(f"Code coverage: not collected ({report['classification']})")
    else:
        print(f"Code coverage: invalid ({report['classification']})", file=sys.stderr)
    print(f"Coverage report: {args.output}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
