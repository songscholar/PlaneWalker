#!/usr/bin/env python3
"""Instrument actual snapshot deep-copy inputs without changing production code."""
from __future__ import annotations

import argparse
import hashlib
from importlib.metadata import version
import json
from pathlib import Path

from gdtoolkit.parser.parser import Parser
from lark import Token, Tree


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path("scripts/enemies/launch/launch_hostile_effect_authority.gd")
PROBE_NAME = "_pw_snapshot_deep_copy_probe"
PROBE_SOURCE = '''

var _pw_snapshot_copy_inputs: Array[String] = []


func _pw_snapshot_deep_copy_probe(value: Dictionary) -> Dictionary:
\tfor key: String in ["payloads", "semantics", "summons"]:
\t\tif value.get(key) is Dictionary and not value[key].is_empty():
\t\t\t_pw_snapshot_copy_inputs.append(key)
\treturn value.duplicate(true)


func _pw_reset_snapshot_copy_probe() -> void:
\t_pw_snapshot_copy_inputs.clear()


func _pw_snapshot_copy_probe_inputs() -> Array[String]:
\treturn _pw_snapshot_copy_inputs.duplicate()
'''


def instrument_source(source: str, cache_directory: Path) -> dict:
    if version("gdtoolkit") != "4.5.0":
        raise ValueError("snapshot copy instrumentation requires pinned gdtoolkit 4.5.0")
    parser = Parser()
    parser._cache_dirpath = str(cache_directory.resolve())
    tree = parser.parse(source, gather_metadata=True)
    if any(str(token).startswith("_pw_snapshot_") for token in tree.scan_values(lambda value: isinstance(value, Token))):
        raise ValueError("source uses reserved snapshot probe identifiers")
    functions = [node for node in tree.find_data("func_def") if str(node.children[0].children[0]) == "snapshot"]
    if len(functions) != 1:
        raise ValueError("expected exactly one actual snapshot method")
    changes = []
    copy_calls = []
    for call in functions[0].find_data("getattr_call"):
        member = call.children[0]
        if not isinstance(member, Tree) or str(member.data) != "getattr" or str(member.children[-1]) != "duplicate":
            continue
        arguments = call.children[1:]
        if not arguments:
            continue
        if len(arguments) != 1 or str(arguments[0]) != "true":
            raise ValueError("snapshot duplicate must use a literal deep-copy argument")
        receiver = member.children[0]
        if not isinstance(receiver, Token) or receiver.type != "NAME":
            raise ValueError("snapshot copy receiver must be an explicit local dictionary")
        replacement = f"{PROBE_NAME}({receiver})"
        changes.append((call.meta.start_pos, call.meta.end_pos, replacement))
        copy_calls.append({"line": call.meta.line, "receiver": str(receiver), "expression": source[call.meta.start_pos:call.meta.end_pos]})
    if not copy_calls:
        raise ValueError("snapshot contains no observed deep dictionary copy")
    for declaration in tree.find_data("classname_stmt"):
        changes.append((declaration.meta.start_pos, declaration.meta.end_pos, ""))
    transformed = source
    for start, end, replacement in sorted(changes, reverse=True):
        transformed = transformed[:start] + replacement + transformed[end:]
    transformed += PROBE_SOURCE
    parser.parse(transformed, gather_metadata=True)
    return {"source": transformed, "source_sha256": hashlib.sha256(source.encode()).hexdigest(), "transformed_sha256": hashlib.sha256(transformed.encode()).hexdigest(), "copy_calls": copy_calls}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "build"):
        parser.error("instrumentation output must remain inside the workspace build directory")
    output.mkdir(parents=True, exist_ok=True)
    result = instrument_source((ROOT / SOURCE).read_text(encoding="utf-8"), output / "parser-cache")
    script = output / "launch_hostile_effect_authority_instrumented.gd"
    script.write_text(result.pop("source"), encoding="utf-8")
    manifest = {"schema_version": 1, "kind": "actual_effect_snapshot_deep_copy_inputs", "instrumented": True, "parser": {"name": "gdtoolkit", "version": "4.5.0"}, "source": SOURCE.as_posix(), "script": script.relative_to(ROOT).as_posix(), **result}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
