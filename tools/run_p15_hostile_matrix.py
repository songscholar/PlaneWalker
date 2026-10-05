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


def positive_number(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def bounded_integer(value: object, minimum: int, maximum: int) -> bool:
    return type(value) is int and minimum <= value <= maximum


def source_snapshot() -> dict[str, str]:
    paths = [path for directory in ("scripts", "autoload", "tests/support") for path in (ROOT / directory).rglob("*.gd")]
    paths.extend((ROOT / "tools/run_p15_hostile_matrix.py", ROOT / "tests/smoke/p15_hostile_loadout_matrix_test.gd", ROOT / "project.godot"))
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


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


def run_shard(godot: str, start: int, count: int, logs: Path, timeout: int) -> dict[str, object]:
    directory = logs / f"native-{start:03d}-{count:03d}"
    directory.mkdir(parents=True, exist_ok=True)
    report_path = directory / "report.json"
    environment = os.environ.copy()
    environment.update({"PLANEWALKER_MATRIX_START": str(start), "PLANEWALKER_MATRIX_COUNT": str(count), "PLANEWALKER_MATRIX_OUTPUT": str(report_path), "PLANEWALKER_TEST_DATA_DIR": str(directory / "user-data"), "XDG_DATA_HOME": str(directory / "user-data"), "XDG_CACHE_HOME": str(directory / "cache")})
    command = [godot, "--headless", "--fixed-fps", "60", "--path", str(ROOT), "--log-file", str(directory / "godot.log"), SCENE]
    started = time.monotonic()
    try:
        completed = subprocess.run(command, cwd=ROOT, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        output = completed.stdout
        code = completed.returncode
    except subprocess.TimeoutExpired as error:
        output = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout or ""
        code = 124
    (directory / "stdout.log").write_text(output, encoding="utf-8")
    try:
        report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
    except (OSError, ValueError):
        report = {}
    if not isinstance(report, dict):
        report = {}
    errors = validate_cases(report.get("cases"), start, count)
    if code:
        errors.insert(0, f"Godot exited{code}")
    engine_log = directory / "godot.log"
    engine_output = engine_log.read_text(encoding="utf-8", errors="replace") if engine_log.exists() else ""
    if ERROR.search(output) or ERROR.search(engine_output):
        errors.insert(0, "Godot contains an error, orphan or leak diagnostic")
    if report.get("schema_version") != REPORT_VERSION or report.get("report_kind") != "actual_native_boss_loadout_matrix" or report.get("synthetic") is not False:
        errors.append("native shard provenance is missing")
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
    if not output.is_relative_to(ROOT) or not logs.is_relative_to(ROOT):
        parser.error("output and evidence logs must remain inside the workspace")
    chunk = (args.count + args.jobs - 1) // args.jobs
    ranges = [(start, min(chunk, args.start + args.count - start)) for start in range(args.start, args.start + args.count, chunk)]
    sources = source_snapshot()
    started = time.monotonic()
    shards = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_shard, godot, start, count, logs, args.timeout) for start, count in ranges]
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
    source = {"runtime_source_sha256": hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(), "instrumented": False}
    result = {"schema_version": REPORT_VERSION, "report_kind": "actual_native_boss_loadout_matrix", "synthetic": False, "human_playtests": 0, "difficulty": "normal", "unassisted_victory": False, "survival_fixture": "p15_matrix_survival_fixture", "clock": shards[0]["report"].get("clock", {}) if shards else {}, "content_snapshot": snapshots[0] if snapshots else {}, "range_start": args.start, "requested_case_count": args.count, "expected_production_case_count": CASE_COUNT, "production_case_count": len(rows), "native_complete": args.start == 0 and args.count == CASE_COUNT and not errors, "p15_complete": False, "synthetic_case_count": 0, "expected_synthetic_case_count": 22500, "errors": errors, "shards": [{key: value for key, value in shard.items() if key != "report"} for shard in shards], "cases": rows}
    result.update(source=source, duration_seconds=time.monotonic() - started)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"actual native cases{len(rows)}/{args.count}; errors{len(errors)}; report{output}", flush=True)
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
