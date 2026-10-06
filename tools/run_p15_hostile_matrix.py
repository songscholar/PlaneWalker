#!/usr/bin/env python3
"""Execute and validate actual native P15 Boss/loadout cases in isolated Godot shards."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import lru_cache
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from runtime_log_validation import validate_logs


ROOT = Path(__file__).resolve().parents[1]
SCENE = "res://tests/smoke/p15_hostile_loadout_matrix_test.tscn"
CHARACTERS = ("wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord")
WEAPONS = ("sword", "bow", "gun", "staff", "gauntlets")
PAIRS = (("stop", "rewind"), ("stop", "rift"), ("stop", "accelerate"), ("rewind", "rift"), ("rewind", "accelerate"), ("rift", "accelerate"))
BOSSES = ("ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne")
CASE_COUNT = 750
REPORT_VERSION = 3
TRACE_FIELDS = {"run_id", "target_id", "raw_run_id", "raw_target_id", "native_authenticated", "source_id", "frame", "phase_index", "hit_index", "amount", "actual_loss", "attack_generation", "damage_type", "accelerated", "tags"}
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|(?:^|\n)ERROR:|ObjectDB instances leaked|RID.*leaked|Orphan (?:Node|StringName)", re.I)
SOURCE_EXPLICIT_PATHS = {
    "tools/run_p15_hostile_matrix.py",
    "tools/runtime_log_validation.py",
    "tests/smoke/p15_hostile_loadout_matrix_test.gd",
    "tests/smoke/p15_hostile_loadout_matrix_test.tscn",
    "project.godot",
}


def positive_number(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def bounded_integer(value: object, minimum: int, maximum: int) -> bool:
    return type(value) is int and minimum <= value <= maximum


def source_snapshot() -> dict[str, str]:
    paths = [path for directory in ("scripts", "autoload", "tests/support") for path in (ROOT / directory).rglob("*.gd")]
    paths.extend(path for path in (ROOT / "scenes").rglob("*.tscn"))
    paths.extend(path for path in (ROOT / "data/content_packs/base").rglob("*") if path.is_file() and not path.name.endswith((".uid", ".import", ".translation")))
    paths.extend((ROOT / "tools/run_p15_hostile_matrix.py", ROOT / "tools/runtime_log_validation.py", ROOT / "tests/smoke/p15_hostile_loadout_matrix_test.gd", ROOT / "tests/smoke/p15_hostile_loadout_matrix_test.tscn", ROOT / "project.godot"))
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


def _in_source_scope(path: str) -> bool:
    if path in SOURCE_EXPLICIT_PATHS:
        return True
    if (path.startswith("scripts/") or path.startswith("autoload/") or path.startswith("tests/support/")) and path.endswith(".gd"):
        return True
    if path.startswith("scenes/") and path.endswith(".tscn"):
        return True
    return path.startswith("data/content_packs/base/") and not path.endswith((".uid", ".import", ".translation"))


def source_identity(sources: dict[str, str], revision_override: str | None = None) -> dict[str, object]:
    revision = subprocess.run(
        ["git", "rev-parse", revision_override or "HEAD"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    return {
        "runtime_source_sha256": hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "revision": revision.stdout.strip() if revision.returncode == 0 else "",
        "instrumented": False,
    }


def validate_committed_source(sources: dict[str, str], revision: str) -> list[str]:
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        return ["native certification requires a resolved Git source commit"]
    tree = subprocess.run(["git", "ls-tree", "-rz", revision], cwd=ROOT, capture_output=True, check=False)
    if tree.returncode:
        return ["native certification source commit is unavailable"]
    blobs = {}
    committed_scope = set()
    for entry in tree.stdout.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, digest = metadata.split(b" ", 2)
        if kind == b"blob" and mode != b"120000":
            path = name.decode()
            blobs[path] = digest.decode()
            if _in_source_scope(path):
                committed_scope.add(path)
    errors = []
    source_scope = set(sources)
    for path in sorted(committed_scope - source_scope):
        errors.append(f"native certification source is missing from the working tree: {path}")
    for path in sorted(source_scope - committed_scope):
        errors.append(f"native certification source is outside the selected commit scope: {path}")
    for path in sources:
        if path not in blobs:
            continue
        payload = (ROOT / path).read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(payload)).encode() + b"\0" + payload).hexdigest()
        if blobs.get(path) != actual:
            errors.append(f"native certification source differs from commit: {path}")
    return errors


def validate_source_identity(value: object, expected: dict[str, object]) -> list[str]:
    if not isinstance(value, dict) or set(value) != {"runtime_source_sha256", "revision", "instrumented"} or value.get("instrumented") is not False or not re.fullmatch(r"[0-9a-f]{64}", str(value.get("runtime_source_sha256", ""))) or not re.fullmatch(r"[0-9a-f]{40}", str(value.get("revision", ""))) or value != expected:
        return ["native shard source identity does not match the current executable source"]
    return []


@lru_cache(maxsize=1)
def canonical_actions() -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    content = ROOT / "data/content_packs/base/content"
    weapons = json.loads((content / "weapon_runtime_profiles.json").read_text(encoding="utf-8"))
    bosses = json.loads((content / "bosses.json").read_text(encoding="utf-8"))
    weapon_actions = {row["weapon_id"]: {action["action_id"] for action in row["actions"]} for row in weapons if row["id"] == f"{row['weapon_id']}_launch_v1"}
    boss_actions = {row["id"]: {action["id"] for field in ("actions", "time_responses") for action in row.get(field, [])} for row in bosses}
    return weapon_actions, boss_actions


def valid_damage_source(hit: dict, weapon: str) -> bool:
    source = hit["source_id"]
    if not isinstance(source, str):
        return False
    if weapon == "sword":
        return source == "player_sword_v2"
    if re.fullmatch(rf"player:{weapon}:[1-9][0-9]{{0,9}}:[0-9]{{1,10}}", source):
        return int(source.split(":")[3 if weapon == "gauntlets" else 2]) == hit["attack_generation"]
    if weapon != "staff" or not re.fullmatch(r"status:[0-9a-f]{40}", source) or "status:burn" not in hit["tags"]:
        return False
    owners = [tag.removeprefix("status_source:") for tag in hit["tags"] if tag.startswith("status_source:")]
    generations = [tag.removeprefix("status_generation:") for tag in hit["tags"] if tag.startswith("status_generation:")]
    if len(owners) != 1 or len(generations) != 1 or not re.fullmatch(r"[0-9]{1,10}", generations[0]) or not re.fullmatch(r"staff:[1-9][0-9]{0,9}:staff_element_cast:[0-9]{1,10}", owners[0]):
        return False
    generation = int(generations[0])
    expected = "status:" + hashlib.sha256(f"{owners[0]}|{generation}|burn".encode()).hexdigest()[:40]
    return source == expected and hit["attack_generation"] == generation + 1


def validate_damage_trace(row: dict, run_id: str, source: str, required: int) -> tuple[bool, dict[str, float]]:
    traces = row.get("damage_trace")
    sums = {str(phase): 0.0 for phase in range(required)}
    if not isinstance(traces, list) or not traces or not bounded_integer(row.get("frames"), 1, 16001):
        return False, sums
    claims = set()
    last_frame = 1
    weapon = row["identity"]["weapon_id"]
    for hit in traces:
        if not isinstance(hit, dict) or set(hit) != TRACE_FIELDS or hit["run_id"] != run_id or hit["target_id"] != source:
            return False, sums
        raw_target = hit["raw_target_id"]
        if hit["native_authenticated"] is not True or hit["raw_run_id"] not in (run_id, "legacy_run", "runtime") or (raw_target not in (source, "pending_target") and (not isinstance(raw_target, str) or not re.fullmatch(r"target:[1-9][0-9]*", raw_target))):
            return False, sums
        if not positive_number(hit["actual_loss"]) or not positive_number(hit["amount"]) or not bounded_integer(hit["attack_generation"], 1, 2147483646) or not bounded_integer(hit["frame"], last_frame, row["frames"]) or not bounded_integer(hit["hit_index"], 0, 2147483646) or not bounded_integer(hit["phase_index"], 0, required - 1) or not bounded_integer(hit["damage_type"], 0, 5) or type(hit["accelerated"]) is not bool:
            return False, sums
        if not isinstance(hit["tags"], list) or any(not isinstance(tag, str) for tag in hit["tags"]) or f"weapon:{weapon}" not in hit["tags"] or not valid_damage_source(hit, weapon):
            return False, sums
        claim = (hit["source_id"], hit["attack_generation"], hit["hit_index"], hit["damage_type"])
        if claim in claims:
            return False, sums
        claims.add(claim)
        last_frame = hit["frame"]
        sums[str(hit["phase_index"])] += hit["actual_loss"]
    return True, sums


def valid_observed_actions(row: dict) -> bool:
    weapon_actions, boss_actions = canonical_actions()
    positive = row.get("positive_time")
    weapons = row.get("weapon_actions")
    bosses = row.get("boss_actions")
    if not bounded_integer(row.get("frames"), 1, 16001):
        return False
    if not isinstance(positive, list) or not positive or any(value not in ("boss_stop_conversion", "boss_rift_slow", "accelerated_physical_hit") for value in positive):
        return False
    if not isinstance(weapons, list) or not weapons or any(not isinstance(value, str) or value not in weapon_actions[row["identity"]["weapon_id"]] for value in weapons):
        return False
    if not isinstance(bosses, dict) or not bosses or any(value not in boss_actions[row["identity"]["boss_id"]] or not bounded_integer(frames, 1, row["frames"]) for value, frames in bosses.items()):
        return False
    if "accelerated_physical_hit" in positive:
        traces = row.get("damage_trace")
        return isinstance(traces, list) and any(isinstance(hit, dict) and hit.get("accelerated") is True for hit in traces)
    return True


def valid_time_receipts(row: dict, run_id: str) -> bool:
    receipts = row.get("time_casts")
    fields = {"id", "run_id", "owner_generation", "action_generation", "action_token", "ability_id", "runtime_frame", "endpoint", "facing"}
    if not isinstance(receipts, list) or len(receipts) != 2 or not bounded_integer(row.get("frames"), 1, 16001):
        return False
    seen = set()
    last_frame = 0
    for ability, receipt in zip(row["identity"]["time_abilities"], receipts):
        if not isinstance(receipt, dict) or set(receipt) != fields or receipt["run_id"] != run_id or receipt["ability_id"] != ability or not bounded_integer(receipt["runtime_frame"], max(1, last_frame + 1), row["frames"]):
            return False
        if any(not bounded_integer(receipt[field], 1, 2147483646) for field in ("owner_generation", "action_generation", "action_token")):
            return False
        for field in ("endpoint", "facing"):
            point = receipt[field]
            if not isinstance(point, dict) or set(point) != {"x", "y"} or any(type(value) not in (int, float) or not math.isfinite(value) for value in point.values()):
                return False
        if not math.isclose(math.hypot(receipt["facing"]["x"], receipt["facing"]["y"]), 1.0, rel_tol=0.0, abs_tol=1e-5):
            return False
        encoded = json.dumps([run_id, receipt["owner_generation"], receipt["action_generation"], receipt["action_token"]], separators=(",", ":"))
        expected = hashlib.sha256(encoded.encode()).hexdigest()
        if receipt["id"] != expected or expected in seen:
            return False
        seen.add(expected)
        last_frame = receipt["runtime_frame"]
    return True


def validate_content_snapshot(value: object) -> list[str]:
    if not isinstance(value, dict) or set(value) != {"aggregate_sha256", "packs"} or not re.fullmatch(r"[0-9a-f]{64}", str(value.get("aggregate_sha256", ""))):
        return ["native content snapshot is missing its canonical aggregate fingerprint"]
    packs = value["packs"]
    if not isinstance(packs, list) or len(packs) != 1:
        return ["native matrix must retain its one authoritative Base Pack binding"]
    pack = packs[0]
    if not isinstance(pack, dict) or set(pack) != {"pack_id", "pack_version", "schema_version", "fingerprint_sha256"} or pack.get("pack_id") != "base" or not isinstance(pack.get("pack_version"), str) or not pack["pack_version"] or type(pack.get("schema_version")) not in (int, float) or pack["schema_version"] != 2 or not re.fullmatch(r"[0-9a-f]{64}", str(pack.get("fingerprint_sha256", ""))):
        return ["native Base Pack content binding is malformed or substituted"]
    return []


def identity(index: int) -> dict[str, object]:
    character = CHARACTERS[index // 150]
    weapon = WEAPONS[(index // 30) % 5]
    pair = PAIRS[(index // 5) % 6]
    boss = BOSSES[index % 5]
    return {"index": index, "key": f"{character}|{weapon}|{pair[0]}+{pair[1]}|{boss}", "character_id": character, "weapon_id": weapon, "time_abilities": list(pair), "boss_id": boss, "boss_index": index % 5, "seed": 20261005 + index}


def validate_cases(rows: object, start: int, count: int) -> list[str]:
    errors: list[str] = []
    if not isinstance(rows, list) or len(rows) != count:
        return [f"actual native case count must be{count}"]
    for offset, row in enumerate(rows):
        index = start + offset
        label = f"case{index}"
        if not isinstance(row, dict) or row.get("identity") != identity(index):
            errors.append(f"{label}: missing, substituted or duplicate canonical identity")
            continue
        if row.get("failures") != [] or row.get("final_hp") != 0 or type(row.get("frames")) is not int or row["frames"] < 1:
            errors.append(f"{label}: native terminal criteria failed: {row.get('failures')}")
        if not re.fullmatch(r"[0-9a-f]{64}", str(row.get("checkpoint_digest", ""))):
            errors.append(f"{label}: no physical native checkpoint and exact continuation")
        phases = row.get("phase_damage", {})
        required = 3 if index % 5 in (3, 4) else 2
        if not isinstance(phases, dict) or set(phases) != {str(n) for n in range(required)} or any(not positive_number(v) for v in phases.values()):
            errors.append(f"{label}: actual weapon damage did not cover every authored HP phase")
        run_id = f"p15-native-matrix-{index}"
        source = "matrix-" + hashlib.sha256(run_id.encode()).hexdigest()[:40]
        valid_trace, sums = validate_damage_trace(row, run_id, source, required)
        if not valid_trace:
            errors.append(f"{label}: missing authentic production weapon damage trace")
        elif not isinstance(phases, dict) or any(not positive_number(phases.get(phase)) or not math.isclose(phases[phase], amount, rel_tol=1e-12, abs_tol=1e-9) for phase, amount in sums.items()):
            errors.append(f"{label}: phase damage does not equal its actual accepted trace")
        if not valid_time_receipts(row, run_id):
            errors.append(f"{label}: both actual equipped time receipts are required")
        if not valid_observed_actions(row):
            errors.append(f"{label}: missing actual action or positive time interaction")
        receipt = "hostile_defeat:" + hashlib.sha256(f"p15-native-matrix-{index}|{source}".encode()).hexdigest()[:40]
        if row.get("death_receipts") != [{"source_id": source, "receipt": receipt}]:
            errors.append(f"{label}: missing exactly one authenticated final physical weapon death")
    return errors


def _read_json(path: Path) -> dict[str, object] | None:
    def unique_fields(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON field")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_fields)
    except (OSError, UnicodeError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def _path_has_symlink(path: Path) -> bool:
    current = path.absolute()
    while True:
        if current.is_symlink():
            return True
        if current == ROOT or current.parent == current:
            return False
        current = current.parent


def _write_json_atomic(path: Path, value: dict[str, object]) -> None:
    if _path_has_symlink(path) or _path_has_symlink(path.with_suffix(path.suffix + ".tmp")):
        raise ValueError("native evidence write must not redirect through a symlink")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as destination:
        destination.write(json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n")
        destination.flush()
        os.fsync(destination.fileno())
    temporary.replace(path)


def _validate_attempt_logs(
    directory: Path,
    expected_source: dict[str, object],
    expected_start: int | None = None,
    expected_count: int | None = None,
) -> list[str]:
    errors = []
    if _path_has_symlink(directory / "attempts"):
        return ["native attempt evidence path must not redirect through a symlink"]
    attempts = sorted(path for path in (directory / "attempts").glob("*") if path.is_dir())
    if (directory / "godot.log").exists() or (directory / "stdout.log").exists():
        attempts.append(directory)
    if not attempts:
        errors.append("native resume has no retained execution logs")
    for attempt in attempts:
        if _path_has_symlink(attempt) or any(_path_has_symlink(attempt / name) for name in ("execution.json", "stdout.log", "godot.log")):
            errors.append("native attempt evidence path must not redirect through a symlink")
            continue
        execution = _read_json(attempt / "execution.json")
        status = execution.get("status") if execution else None
        valid_status = status in ("running", "finished", "timed_out")
        valid_range = (
            bounded_integer(execution.get("range_start"), 0, CASE_COUNT - 1)
            and bounded_integer(execution.get("requested_case_count"), 1, CASE_COUNT)
            and execution["range_start"] + execution["requested_case_count"] <= CASE_COUNT
            and (expected_start is None or execution["range_start"] == expected_start)
            and (expected_count is None or execution["requested_case_count"] == expected_count)
        ) if execution else False
        valid_exit = (
            status == "running" and "exit_code" not in execution
            or status == "timed_out" and type(execution.get("exit_code")) is int and execution["exit_code"] == 124
            or status == "finished" and type(execution.get("exit_code")) is int and execution["exit_code"] == 0
        ) if execution else False
        if not execution or execution.get("source") != expected_source or not valid_status or not valid_range or not valid_exit:
            errors.append("native attempt execution source identity is missing or substituted")
        try:
            validate_logs([attempt / "stdout.log", attempt / "godot.log"])
        except ValueError as error:
            errors.append(f"native attempt strict paired logs refused: {error}")
    return errors


def _validate_partial_report(
    report: object,
    start: int,
    count: int,
    expected_source: dict[str, object],
) -> tuple[list[dict[str, object]], list[str]]:
    if not isinstance(report, dict):
        return [], ["native resume partial report is missing or malformed"]
    errors: list[str] = []
    if report.get("schema_version") != REPORT_VERSION or report.get("report_kind") != "actual_native_boss_loadout_matrix" or report.get("synthetic") is not False:
        errors.append("native resume partial provenance is missing")
    if report.get("partial") is not True or report.get("complete") is not False:
        errors.append("native resume requires an explicitly incomplete partial report")
    if type(report.get("range_start")) is not int or type(report.get("requested_case_count")) is not int or report.get("range_start") != start or report.get("requested_case_count") != count:
        errors.append("native resume partial range does not match the requested shard")
    errors.extend(validate_source_identity(report.get("source"), expected_source))
    errors.extend(validate_content_snapshot(report.get("content_snapshot")))
    clock = report.get("clock")
    if not isinstance(clock, dict) or set(clock) != {"physics_ticks_per_second", "time_scale"} or type(clock.get("physics_ticks_per_second")) is not int or clock["physics_ticks_per_second"] != 60 or type(clock.get("time_scale")) not in (int, float) or clock["time_scale"] != 1.0:
        errors.append("native resume partial clock differs from production60Hz")
    rows = report.get("cases")
    if not isinstance(rows, list) or len(rows) > count:
        errors.append("native resume partial case count is outside the requested range")
        return [], errors
    if not errors:
        errors.extend(validate_cases(rows, start, len(rows)))
    return rows if not errors else [], errors


def read_partial_report(
    path: Path,
    start: int,
    count: int,
    expected_source: dict[str, object],
) -> tuple[dict[str, object], list[str]]:
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
        return {}, ["native partial path must not redirect outside its retained shard"]
    manifest = _read_json(path)
    if manifest is None:
        return {}, ["native partial manifest is missing or malformed"]
    errors: list[str] = []
    descriptors = manifest.get("case_receipts")
    rows: list[dict[str, object]] = []
    if not isinstance(descriptors, list) or len(descriptors) > count:
        return {}, ["native partial receipt count is outside the requested range"]
    for offset, descriptor in enumerate(descriptors):
        index = start + offset
        expected_path = f"cases/case-{index:06d}.json"
        if not isinstance(descriptor, dict) or set(descriptor) != {"index", "path", "sha256"} or type(descriptor.get("index")) is not int or descriptor["index"] != index or descriptor.get("path") != expected_path or not re.fullmatch(r"[0-9a-f]{64}", str(descriptor.get("sha256", ""))):
            errors.append(f"native partial case{index} has a duplicate, foreign or reordered descriptor")
            continue
        receipt_path = path.parent / expected_path
        if any(candidate.is_symlink() for candidate in (receipt_path, *receipt_path.parents)) or not receipt_path.is_file() or not receipt_path.resolve().is_relative_to(path.parent.resolve()) or hashlib.sha256(receipt_path.read_bytes()).hexdigest() != descriptor["sha256"]:
            errors.append(f"native partial case{index} receipt is missing, redirected or changed")
            continue
        receipt = _read_json(receipt_path)
        if receipt is None or receipt.get("schema_version") != 1 or receipt.get("report_kind") != "actual_native_boss_loadout_case" or receipt.get("source") != expected_source or receipt.get("content_snapshot") != manifest.get("content_snapshot") or not isinstance(receipt.get("typed_row"), str) or not receipt["typed_row"] or not isinstance(receipt.get("row"), dict):
            errors.append(f"native partial case{index} receipt provenance is missing or substituted")
            continue
        rows.append(receipt["row"])
    if type(manifest.get("production_case_count")) is not int or manifest.get("production_case_count") != len(descriptors):
        errors.append("native partial manifest count does not match its receipt descriptors")
    result = {**manifest, "cases": rows}
    if not errors:
        _, errors = _validate_partial_report(result, start, count, expected_source)
    return result, errors


def run_shard(
    godot: str,
    start: int,
    count: int,
    logs: Path,
    timeout: int,
    *,
    expected_source: dict[str, object] | None = None,
    resume: bool = False,
) -> dict[str, object]:
    directory = logs / f"native-{start:03d}-{count:03d}"
    if _path_has_symlink(logs) or _path_has_symlink(directory):
        return {
            "range_start": start,
            "requested_case_count": count,
            "duration_seconds": 0.0,
            "logs": str(directory.relative_to(ROOT)),
            "errors": ["native shard evidence path must not redirect through a symlink"],
            "report": {},
        }
    directory.mkdir(parents=True, exist_ok=True)
    report_path = directory / "report.json"
    partial_path = directory / "partial.json"
    expected_source = expected_source or source_identity(source_snapshot())
    resume_rows: list[dict[str, object]] = []
    resume_errors: list[str] = []
    if resume:
        if not partial_path.is_file():
            resume_errors.append("native resume requested but its source-bound partial report is missing")
        else:
            partial, resume_errors = read_partial_report(partial_path, start, count, expected_source)
            resume_rows = partial.get("cases", []) if not resume_errors else []
            committed = {str(descriptor["path"]) for descriptor in partial.get("case_receipts", [])} if not resume_errors else set()
            for receipt_path in (directory / "cases").glob("case-*.json"):
                relative = receipt_path.relative_to(directory).as_posix()
                if relative in committed:
                    continue
                next_index = start + len(resume_rows)
                receipt = _read_json(receipt_path)
                if relative != f"cases/case-{next_index:06d}.json" or any(candidate.is_symlink() for candidate in (receipt_path, *receipt_path.parents)) or not receipt or receipt.get("source") != expected_source or validate_cases([receipt.get("row")], next_index, 1):
                    resume_errors.append("native resume has an uncommitted foreign or failed case receipt")
                # A valid uncommitted receipt is preserved by the producer and rerun.
    elif partial_path.exists() or report_path.exists():
        resume_errors.append("native shard output already exists; use --resume to avoid mixing prior evidence")
    if resume:
        resume_errors.extend(_validate_attempt_logs(directory, expected_source, start, count))
    if any(candidate.is_symlink() for candidate in (directory, *directory.parents)):
        resume_errors.append("native shard directory must not redirect its evidence")
    if resume_errors:
        return {
            "range_start": start,
            "requested_case_count": count,
            "duration_seconds": 0.0,
            "logs": str(directory.relative_to(ROOT)),
            "errors": resume_errors,
            "report": {},
        }
    resumed_count = len(resume_rows)
    effective_start = start + resumed_count
    effective_count = count - resumed_count
    environment = os.environ.copy()
    environment.update({
        "PLANEWALKER_MATRIX_START": str(effective_start),
        "PLANEWALKER_MATRIX_COUNT": str(effective_count),
        "PLANEWALKER_MATRIX_REQUESTED_START": str(start),
        "PLANEWALKER_MATRIX_REQUESTED_COUNT": str(count),
        "PLANEWALKER_MATRIX_OUTPUT": str(report_path),
        "PLANEWALKER_MATRIX_PARTIAL_OUTPUT": str(partial_path),
        "PLANEWALKER_MATRIX_RESUME_INPUT": str(partial_path) if resume_rows else "",
        "PLANEWALKER_MATRIX_SOURCE_SHA256": str(expected_source["runtime_source_sha256"]),
        "PLANEWALKER_MATRIX_SOURCE_REVISION": str(expected_source["revision"]),
        "PLANEWALKER_TEST_DATA_DIR": str(directory / "user-data"),
        "XDG_DATA_HOME": str(directory / "user-data"),
        "XDG_CACHE_HOME": str(directory / "user-data"),
    })
    attempts = directory / "attempts"
    retained_attempt_paths = [path for path in attempts.glob("*")]
    if _path_has_symlink(attempts) or any(_path_has_symlink(path) or any(_path_has_symlink(path / name) for name in ("execution.json", "stdout.log", "godot.log")) for path in retained_attempt_paths):
        return {
            "range_start": start,
            "requested_case_count": count,
            "duration_seconds": 0.0,
            "logs": str(directory.relative_to(ROOT)),
            "errors": ["native attempt evidence path must not redirect through a symlink"],
            "report": {},
        }
    attempts.mkdir(exist_ok=True)
    attempt_number = 0
    while (attempts / f"{attempt_number:03d}").exists():
        attempt_number += 1
    attempt = attempts / f"{attempt_number:03d}"
    if _path_has_symlink(attempt):
        return {
            "range_start": start,
            "requested_case_count": count,
            "duration_seconds": 0.0,
            "logs": str(directory.relative_to(ROOT)),
            "errors": ["native attempt evidence path must not redirect through a symlink"],
            "report": {},
        }
    attempt.mkdir()
    if report_path.exists():
        report_path.replace(attempt / "prior-report.json")
    command = [godot, "--headless", "--fixed-fps", "60", "--path", str(ROOT), "--log-file", str(attempt / "godot.log"), SCENE]
    started = time.monotonic()
    timed_out = False
    execution = {"source": expected_source, "range_start": start, "requested_case_count": count, "resumed_case_count": resumed_count, "timeout_seconds": timeout, "command": command, "status": "running"}
    _write_json_atomic(attempt / "execution.json", execution)
    with (attempt / "stdout.log").open("w", encoding="utf-8") as stdout_file:
        try:
            completed_process = subprocess.run(command, cwd=ROOT, env=environment, text=True, stdout=stdout_file, stderr=subprocess.STDOUT, timeout=timeout, check=False)
            code = completed_process.returncode
        except subprocess.TimeoutExpired:
            code = 124
            timed_out = True
        stdout_file.flush()
        os.fsync(stdout_file.fileno())
    output = (attempt / "stdout.log").read_text(encoding="utf-8", errors="replace")
    execution.update(status="timed_out" if timed_out else "finished", exit_code=code, duration_seconds=time.monotonic() - started)
    _write_json_atomic(attempt / "execution.json", execution)
    report = _read_json(report_path)
    partial_errors: list[str] = []
    if report is None:
        report, partial_errors = read_partial_report(partial_path, start, count, expected_source) if partial_path.exists() else ({}, [])
    report_rows = report.get("cases")
    actual_count = len(report_rows) if isinstance(report_rows, list) else count
    errors = validate_cases(report_rows, start, count if report.get("partial") is not True else actual_count)
    if resume_rows and (not isinstance(report_rows, list) or report_rows[:resumed_count] != resume_rows):
        errors.insert(0, "native resumed shard discarded or reordered previously persisted cases")
    if code:
        errors.insert(0, f"Godot exited{code}")
    if timed_out:
        errors.insert(0, f"native shard timed out after{timeout}s")
    errors.extend(partial_errors)
    errors.extend(_validate_attempt_logs(directory, expected_source, start, count))
    engine_output = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in directory.rglob("*.log"))
    if ERROR.search(output) or ERROR.search(engine_output):
        errors.insert(0, "Godot contains an error, orphan or leak diagnostic")
    if report.get("schema_version") != REPORT_VERSION or report.get("report_kind") != "actual_native_boss_loadout_matrix" or report.get("synthetic") is not False:
        errors.append("native shard provenance is missing")
    if report.get("partial") is True:
        errors.append("native shard emitted only a partial report; process completion is unverified")
    if report.get("range_start") != start or report.get("requested_case_count") != count:
        errors.append("native shard report range does not match the requested shard")
    errors.extend(validate_source_identity(report.get("source"), expected_source))
    clock = report.get("clock")
    if not isinstance(clock, dict) or set(clock) != {"physics_ticks_per_second", "time_scale"} or type(clock["physics_ticks_per_second"]) is not int or clock["physics_ticks_per_second"] != 60 or type(clock["time_scale"]) not in (int, float) or clock["time_scale"] != 1.0:
        errors.append("native matrix must retain the production60Hz clock and time scale")
    errors.extend(validate_content_snapshot(report.get("content_snapshot")))
    return {"range_start": start, "requested_case_count": count, "duration_seconds": time.monotonic() - started, "logs": str(directory.relative_to(ROOT)), "errors": errors, "report": report}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-count", type=int, default=30)
    parser.add_argument("--loadout-count", type=int, default=150)
    parser.add_argument("--boss-count", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--logs", type=Path, default=Path("build/test-evidence/p15-native-matrix"))
    parser.add_argument("--jobs", type=int, choices=range(1, 6), default=5)
    parser.add_argument("--timeout", type=int, default=7200)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--count", type=int, default=CASE_COUNT)
    parser.add_argument("--resume", action="store_true", help="resume only canonical passed case receipts from the same exact committed source")
    parser.add_argument("--source-revision", help="explicit Git source commit for a frozen checkout without its own .git directory")
    args = parser.parse_args(argv)
    if (args.seed_count, args.loadout_count, args.boss_count) != (30, 150, 5):
        parser.error("canonical counts are30 seeds,150 loadouts and5 Bosses")
    if not 0 <= args.start < CASE_COUNT or not 1 <= args.count <= CASE_COUNT - args.start or args.timeout < 1:
        parser.error("requested native range or timeout is invalid")
    godot = shutil.which(os.environ.get("GODOT_BIN", "godot"))
    if godot is None:
        parser.error("Godot executable is unavailable")
    output = args.output.resolve()
    logs = args.logs.resolve()
    if _path_has_symlink(args.output) or _path_has_symlink(args.logs):
        parser.error("output and evidence logs must not redirect through a symlink")
    if not output.is_relative_to(ROOT) or not logs.is_relative_to(ROOT):
        parser.error("output and evidence logs must remain inside the workspace")
    chunk = (args.count + args.jobs - 1) // args.jobs
    ranges = [(start, min(chunk, args.start + args.count - start)) for start in range(args.start, args.start + args.count, chunk)]
    sources = source_snapshot()
    source = source_identity(sources, args.source_revision)
    source_errors = validate_committed_source(sources, str(source["revision"]))
    if source_errors:
        parser.error("; ".join(source_errors[:5]))
    manifest_path = logs / "source-manifest.json"
    if _path_has_symlink(manifest_path):
        parser.error("source manifest must not redirect through a symlink")
    if args.resume:
        retained_sources = _read_json(manifest_path)
        if retained_sources != {"source": source, "runtime_files_sha256": sources}:
            parser.error("resume source manifest is missing or differs from the exact current committed source")
    else:
        if manifest_path.exists():
            parser.error("matrix logs already retain a source manifest; use --resume or a fresh evidence directory")
        _write_json_atomic(manifest_path, {"source": source, "runtime_files_sha256": sources})
    started = time.monotonic()
    shards = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_shard, godot, start, count, logs, args.timeout, expected_source=source, resume=args.resume) for start, count in ranges]
        for future in as_completed(futures):
            shard = future.result()
            shards.append(shard)
            print(f"native shard{shard['range_start']}:{shard['requested_case_count']} {'PASS' if not shard['errors'] else 'FAIL'}", flush=True)
    shards.sort(key=lambda shard: shard["range_start"])
    rows = [row for shard in shards for row in shard["report"].get("cases", [])]
    errors = [error for shard in shards for error in shard["errors"]]
    errors.extend(validate_cases(rows, args.start, args.count))
    snapshots = [shard["report"].get("content_snapshot", {}) for shard in shards]
    if any(snapshot != snapshots[0] for snapshot in snapshots):
        errors.append("native shards ran different content fingerprints")
    if source_snapshot() != sources:
        errors.append("native runtime or runner sources changed during certification")
    result = {"schema_version": REPORT_VERSION, "report_kind": "actual_native_boss_loadout_matrix", "synthetic": False, "human_playtests": 0, "difficulty": "normal", "unassisted_victory": False, "survival_fixture": "p15_matrix_survival_fixture", "clock": shards[0]["report"].get("clock", {}) if shards else {}, "content_snapshot": snapshots[0] if snapshots else {}, "range_start": args.start, "requested_case_count": args.count, "expected_production_case_count": CASE_COUNT, "production_case_count": len(rows), "native_complete": args.start == 0 and args.count == CASE_COUNT and not errors, "p15_complete": False, "synthetic_case_count": 0, "expected_synthetic_case_count": 22500, "errors": errors, "shards": [{key: value for key, value in shard.items() if key != "report"} for shard in shards], "cases": rows}
    result.update(source=source, duration_seconds=time.monotonic() - started)
    output.parent.mkdir(parents=True, exist_ok=True)
    _write_json_atomic(output, result)
    print(f"actual native cases{len(rows)}/{args.count}; errors{len(errors)}; report{output}", flush=True)
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
