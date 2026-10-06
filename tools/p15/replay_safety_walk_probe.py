#!/usr/bin/env python3
"""Count Replay safety walk roots in an AST-instrumented build-only copy."""
from __future__ import annotations

import argparse
import hashlib
from importlib.metadata import version
import json
from pathlib import Path

from gdtoolkit.parser.parser import Parser
from lark import Token


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path("scripts/replay/replay_recorder.gd")
PROBE_NAME = "_pw_counted_replay_value_is_safe"
PROBE_SOURCE = '''

static var _pw_replay_safety_walk_roots: int = 0


static func _pw_counted_replay_value_is_safe(value: Variant) -> bool:
\t_pw_replay_safety_walk_roots += 1
\treturn replay_value_is_safe(value)


static func _pw_reset_replay_safety_walk_probe() -> void:
\t_pw_replay_safety_walk_roots = 0


static func _pw_replay_safety_walk_probe_count() -> int:
\treturn _pw_replay_safety_walk_roots
'''


def instrument_source(source: str, cache_directory: Path) -> dict:
    if version("gdtoolkit") != "4.5.0":
        raise ValueError("Replay safety instrumentation requires pinned gdtoolkit 4.5.0")
    parser = Parser()
    parser._cache_dirpath = str(cache_directory.resolve())
    tree = parser.parse(source, gather_metadata=True)
    if any("pw_" in str(token) for token in tree.scan_values(lambda value: isinstance(value, Token))):
        raise ValueError("source uses reserved probe identifiers")
    functions = list(tree.find_data("func_def"))
    if sum(str(function.children[0].children[0]) == "replay_value_is_safe" for function in functions) != 1:
        raise ValueError("expected one actual Replay safety function")
    changes = []
    calls = []
    for function in functions:
        name = str(function.children[0].children[0])
        if name == "replay_value_is_safe":
            continue
        for call in function.find_data("standalone_call"):
            token = call.children[0]
            if str(token) != "replay_value_is_safe":
                continue
            changes.append((token.start_pos, token.end_pos, PROBE_NAME))
            calls.append({"function": name, "line": call.meta.line})
    if not calls:
        raise ValueError("source contains no rooted safety calls")
    for declaration in tree.find_data("classname_stmt"):
        changes.append((declaration.meta.start_pos, declaration.meta.end_pos, ""))
    transformed = source
    for start, end, replacement in sorted(changes, reverse=True):
        transformed = transformed[:start] + replacement + transformed[end:]
    transformed += PROBE_SOURCE
    parser.parse(transformed, gather_metadata=True)
    return {"source": transformed, "source_sha256": hashlib.sha256(source.encode()).hexdigest(), "transformed_sha256": hashlib.sha256(transformed.encode()).hexdigest(), "rooted_calls": calls}


def prepare_output(output: Path, workspace: Path = ROOT) -> Path:
    root = workspace.resolve()
    unresolved = output.absolute()
    resolved = output.resolve()
    if not resolved.is_relative_to(root / "build") or resolved == root / "build":
        raise ValueError("instrumentation output must be a new directory inside workspace build")
    for candidate in [unresolved, *unresolved.parents]:
        if candidate.is_symlink():
            raise ValueError("instrumentation output cannot use a symlink")
        if candidate == root:
            break
    if output.exists():
        raise ValueError("instrumentation output already exists; retained evidence cannot be overwritten")
    resolved.mkdir(parents=True, exist_ok=False)
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / SOURCE)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    if not source.is_relative_to(ROOT):
        parser.error("source must remain inside the workspace")
    try:
        output = prepare_output(args.output)
    except ValueError as error:
        parser.error(str(error))
    result = instrument_source(source.read_text(encoding="utf-8"), output / "parser-cache")
    script = output / "replay_recorder_instrumented.gd"
    with script.open("x", encoding="utf-8") as handle:
        handle.write(result.pop("source"))
    manifest = {"schema_version": 1, "kind": "actual_replay_safety_walk_roots", "instrumented": True, "parser": {"name": "gdtoolkit", "version": "4.5.0"}, "source": source.relative_to(ROOT).as_posix(), "script": script.relative_to(ROOT).as_posix(), **result}
    with (output / "manifest.json").open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
