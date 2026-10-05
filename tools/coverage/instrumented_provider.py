#!/usr/bin/env python3
"""Measure original GDScript statement lines in an isolated instrumented runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from functools import lru_cache
from importlib.metadata import version
from pathlib import Path

from gdtoolkit.parser.parser import Parser
from lark import Token, Tree

from tools.coverage.collect_gdscript_coverage import collect, _write_json_atomic
from tools.validate_import_translations import classify


COUNTER_NAME = "_PWLineCoverageProbeV1"
COUNTER_RESOURCE = "res://tools/coverage/line_probe.gd"
PROVIDER_NAME = "planewalker-gdtoolkit-runtime-lines"
PROVIDER_VERSION = "1.0.0"
SOURCE_DIRECTORIES = ("autoload", "scripts")
COPY_EXCLUSIONS = {".git", ".godot", ".codex", "build", "__pycache__", ".DS_Store"}
SIMPLE_STATEMENTS = {
    "pass_stmt", "return_stmt", "func_var_stmt", "break_stmt",
    "breakpoint_stmt", "continue_stmt", "expr_stmt",
}
CALLABLES = {"func_def", "lambda", "property_custom_setter", "property_custom_getter"}
EXPRESSION_HEADERS = {
    "if_branch", "elif_branch", "while_stmt", "for_stmt", "for_stmt_typed",
    "match_stmt", "guarded_match_branch",
}


@lru_cache(maxsize=8)
def _parser(cache_dir: Path) -> Parser:
    parser = Parser()
    parser._cache_dirpath = str(cache_dir.resolve())
    return parser


def instrument_source(source: str, relative_path: str, cache_dir: Path) -> dict[str, object]:
    path = Path(relative_path)
    if path.is_absolute() or ".." in path.parts or path.suffix != ".gd":
        raise ValueError("instrumented source must have a project-relative GDScript path")
    parser = _parser(cache_dir)
    try:
        tree = parser.parse(source, gather_metadata=True)
    except Exception as error:
        raise ValueError(f"unsupported GDScript syntax in {relative_path}: {error}") from error
    if any(isinstance(value, Token) and str(value).startswith(COUNTER_NAME) for value in tree.scan_values(lambda value: isinstance(value, Token))):
        raise ValueError("source declares the reserved line-counter identity")

    additions: dict[int, list[str]] = {}
    executable: set[int] = set()
    quoted_path = json.dumps(path.as_posix(), ensure_ascii=True)
    counter_name = COUNTER_NAME + "_" + hashlib.sha256(path.as_posix().encode()).hexdigest()[:16]

    def add(position: int, text: str) -> None:
        additions.setdefault(position, []).append(text)

    def mark(line: int) -> str:
        executable.add(line)
        return f"{counter_name}.mark({quoted_path}, {line})"

    def wrap(expression: Tree, line: int, declared_type: str = "") -> None:
        original = source[expression.meta.start_pos:expression.meta.end_pos]
        # Both branches keep the original inferred type; only the true arm executes.
        cast = f" as {declared_type}" if declared_type.startswith(("Array[", "Dictionary[")) else ""
        add(expression.meta.start_pos, "(((" if cast else "((")
        add(expression.meta.end_pos, f"){cast}) if {mark(line)} else (({original}){cast}))" if cast else f") if {mark(line)} else ({original}))")

    def visit(node: Tree, in_callable: bool = False) -> None:
        kind = str(node.data)
        active = in_callable or kind in CALLABLES
        children = [child for child in node.children if isinstance(child, Tree)]
        if active and kind in SIMPLE_STATEMENTS:
            add(node.meta.start_pos, mark(node.meta.line) + "; ")
        elif active and kind in EXPRESSION_HEADERS:
            expression = next((child for child in children if str(child.data) == "expr"), None)
            if expression is None:
                raise ValueError(f"unrecognized executable header: {kind}")
            wrap(expression, node.meta.line)
        elif kind in {"class_var_stmt", "static_class_var_stmt"}:
            declaration = children[0]
            expression = next((child for child in declaration.children if isinstance(child, Tree) and str(child.data) == "expr"), None)
            if expression is not None:
                declared_type = next((str(child) for child in declaration.children if isinstance(child, Token) and child.type == "TYPE_HINT"), "")
                wrap(expression, node.meta.line, declared_type)
        for child in children:
            visit(child, active)

    visit(tree)
    transformed = source
    for position in sorted(additions, reverse=True):
        transformed = transformed[:position] + "".join(additions[position]) + transformed[position:]
    if executable:
        transformed += f'\n\nconst {counter_name} = preload("{COUNTER_RESOURCE}")\n'
    try:
        parser.parse(transformed, gather_metadata=True)
    except Exception as error:
        raise ValueError(f"instrumented syntax is invalid in {relative_path}: {error}") from error
    return {
        "source": transformed,
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "executable_lines": sorted(executable),
    }


def manifest_digest(manifest: dict[str, dict[str, object]]) -> str:
    identity = {
        path: {"source_sha256": row["source_sha256"], "executable_lines": row["executable_lines"]}
        for path, row in sorted(manifest.items())
    }
    return hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def aggregate_reports(manifest: dict[str, dict[str, object]], hits_dir: Path) -> dict[str, object]:
    reports = sorted(hits_dir.glob("*.json"))
    if not reports:
        raise ValueError("runtime did not retain any physical line-hit reports")
    expected_digest = manifest_digest(manifest)
    covered: dict[str, set[int]] = {path: set() for path in manifest}
    for path in reports:
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict) or set(value) != {"schema_version", "manifest_sha256", "hits"} or type(value["schema_version"]) is not int or value["schema_version"] != 1 or value["manifest_sha256"] != expected_digest or not isinstance(value["hits"], dict):
            raise ValueError(f"runtime line-hit report has invalid identity: {path}")
        for source, lines in value["hits"].items():
            if source not in manifest or not isinstance(lines, list) or any(type(line) is not int for line in lines):
                raise ValueError("runtime reported unknown sources or invalid line numbers")
            known = set(manifest[source]["executable_lines"])
            if len(lines) != len(set(lines)) or not set(lines) <= known:
                raise ValueError("runtime reported unknown or repeated executable lines")
            covered[source].update(lines)
    return {
        "schema_version": "1.0.0", "status": "collected", "language": "GDScript", "metric": "line",
        "provider": {"name": PROVIDER_NAME, "version": PROVIDER_VERSION, "mode": "instrumented_runtime"},
        "files": [{
            "path": path, "source_sha256": row["source_sha256"],
            "executable_lines": row["executable_lines"], "covered_lines": sorted(covered[path]),
        } for path, row in sorted(manifest.items()) if row["executable_lines"]],
    }


def _sources(root: Path) -> list[Path]:
    return sorted(path for directory in SOURCE_DIRECTORIES for path in (root / directory).rglob("*.gd"))


def _copy_project(root: Path, destination: Path) -> None:
    def ignore(directory: str, names: list[str]) -> set[str]:
        omitted = {name for name in names if name in COPY_EXCLUSIONS or name.endswith((".pyc", ".translation"))}
        for name in set(names) - omitted:
            if (Path(directory) / name).is_symlink():
                raise ValueError(f"isolated coverage copy refuses symbolic links: {Path(directory) / name}")
        return omitted

    shutil.copytree(root, destination, ignore=ignore)


def _run_logged(command: list[str], root: Path, output: Path, label: str, environment: dict[str, str], timeout: int, import_phase: str = "") -> None:
    stdout_log = output / f"{label}.stdout.log"
    engine_log = output / f"{label}.godot.log"
    print(f"Runtime line coverage: {label}", flush=True)
    with stdout_log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command + ["--log-file", str(engine_log)], cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False)
    logs = stdout_log.read_text(encoding="utf-8", errors="replace")
    if engine_log.is_file():
        logs += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    if result.returncode != 0 or re.search(r"SCRIPT ERROR:|Error calling deferred method:|Parse Error:|Failed to load script|ObjectDB instances leaked|RID allocations leaked", logs):
        raise ValueError(f"{label} failed; inspect {stdout_log}")
    errors = sorted(set(line for line in logs.splitlines() if line.startswith("ERROR:")))
    if import_phase:
        errors, _ = classify(root, import_phase, errors)
    if errors:
        raise ValueError(f"{label} contains engine errors: {'; '.join(errors)}")


def run_coverage(project_root: Path, godot_bin: str, output_dir: Path, *, filter_text: str = "", timeout_seconds: int = 90) -> dict[str, object]:
    root = project_root.resolve()
    output = output_dir.resolve()
    if not (root / "project.godot").is_file() or timeout_seconds <= 0:
        raise ValueError("coverage requires a Godot project and a positive scene timeout")
    if output == root or (output.is_relative_to(root) and output.relative_to(root).parts[0] != "build"):
        raise ValueError("coverage output inside its source project must use the excluded build directory")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("coverage evidence directory must be empty or absent")
    if version("gdtoolkit") != "4.5.0":
        raise ValueError("runtime instrumentation requires pinned gdtoolkit 4.5.0")
    editor = shutil.which(godot_bin)
    if editor is None:
        raise ValueError("coverage requires a runnable real Godot executable")
    output.mkdir(parents=True, exist_ok=True)
    isolated = output / "project-copy"
    report: dict[str, object] = {"schema_version": 1, "status": "failed", "project_root": str(root), "isolated_project": str(isolated), "filter": filter_text}
    try:
        _copy_project(root, isolated)
        helper_root = Path(__file__).resolve().parent
        (isolated / "tools/coverage").mkdir(parents=True, exist_ok=True)
        for filename in ["line_probe.gd", "install_probe.gd"]:
            shutil.copy2(helper_root / filename, isolated / "tools/coverage" / filename)
        environment = dict(os.environ)
        for key in ["GDSCRIPT_COVERAGE_PROVIDER_REPORT", "PLANEWALKER_COVERAGE_HITS_DIR", "PLANEWALKER_COVERAGE_MANIFEST_SHA256"]:
            environment.pop(key, None)
        environment["GODOT_BIN"] = editor
        environment["XDG_CACHE_HOME"] = str(output / "environment/cache")
        environment["XDG_CONFIG_HOME"] = str(output / "environment/config")
        environment["PLANEWALKER_TEST_DATA_DIR"] = str(output / "environment/files")
        engine_command = [editor, "--headless", "--path", str(isolated)]
        for phase in ["bootstrap", "clean"]:
            _run_logged(engine_command + ["--editor", "--import"], isolated, output, phase + "-import", environment, 300, phase)
        _run_logged(engine_command + ["--script", "res://tools/coverage/install_probe.gd"], isolated, output, "install-probe", environment, 60)
        manifest: dict[str, dict[str, object]] = {}
        for source_path in _sources(isolated):
            path = source_path.relative_to(isolated).as_posix()
            transformed = instrument_source(source_path.read_text(encoding="utf-8"), path, output / "parser-cache")
            source_path.write_text(transformed["source"], encoding="utf-8")
            manifest[path] = {key: transformed[key] for key in ["source_sha256", "executable_lines"]}
        if not manifest or not any(row["executable_lines"] for row in manifest.values()):
            raise ValueError("coverage source scope has no executable runtime statements")
        _write_json_atomic(output / "manifest.json", {"schema_version": 1, "manifest_sha256": manifest_digest(manifest), "files": manifest})
        _run_logged(engine_command + ["--editor", "--import"], isolated, output, "instrumented-import", environment, 300, "clean")
        hits_dir = output / "runtime-hits"
        environment["PLANEWALKER_COVERAGE_HITS_DIR"] = str(hits_dir)
        environment["PLANEWALKER_COVERAGE_MANIFEST_SHA256"] = manifest_digest(manifest)
        environment["TEST_LOG_DIR"] = str(output / "scene-tests")
        command = ["bash", str(isolated / "tools/run_tests.sh"), "--timeout", str(timeout_seconds)]
        if filter_text:
            command.extend(["--filter", filter_text])
        discovery = subprocess.run(command + ["--list"], cwd=isolated, env=environment, text=True, capture_output=True, timeout=30, check=False)
        scenes = discovery.stdout.splitlines()
        if discovery.returncode != 0 or not scenes or any(not scene.startswith("tests/") or not scene.endswith(".tscn") for scene in scenes):
            raise ValueError("instrumented runtime scene discovery failed")
        print(f"Runtime line coverage: {len(manifest)} original scripts instrumented; executing scene suite", flush=True)
        suite_log = output / "scene-suite.stdout.log"
        with suite_log.open("w", encoding="utf-8") as stream:
            suite = subprocess.run(command, cwd=isolated, env=environment, stdout=stream, stderr=subprocess.STDOUT, check=False)
        if suite.returncode != 0:
            raise ValueError(f"instrumented scene suite failed; inspect {suite_log}")
        for scene in scenes:
            if not list(hits_dir.glob("scene-" + scene.replace("/", "__") + "-pid-*.json")):
                raise ValueError(f"runtime did not retain a physical line report for tested scene: {scene}")
        if {path.relative_to(root).as_posix() for path in _sources(root)} != set(manifest):
            raise ValueError("original runtime source inventory changed during coverage measurement")
        for path, row in manifest.items():
            if hashlib.sha256((root / path).read_bytes()).hexdigest() != row["source_sha256"]:
                raise ValueError(f"original runtime source changed during coverage measurement: {path}")
        raw = aggregate_reports(manifest, hits_dir)
        provider_report = output / "provider-report.json"
        _write_json_atomic(provider_report, raw)
        normalized, status = collect(root, editor, output / "gdscript-coverage.json", provider_report)
        if status != 0:
            raise ValueError(f"original-source coverage collector refused runtime evidence: {normalized['issues']}")
        report.update({"status": "pass", "provider": raw["provider"], "summary": normalized["summary"], "runtime_reports": len(list(hits_dir.glob("*.json"))), "tested_scenes": scenes})
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["failure"] = str(error)
    _write_json_atomic(output / "run.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--filter", default="")
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args()
    try:
        report = run_coverage(args.project_root, args.godot_bin, args.output_dir, filter_text=args.filter, timeout_seconds=args.timeout)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
