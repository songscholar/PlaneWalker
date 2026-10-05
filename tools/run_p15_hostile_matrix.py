#!/usr/bin/env python3
"""Execute and validate actual native P15 Boss/loadout cases in isolated Godot shards."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SCENE = "res://tests/smoke/p15_hostile_loadout_matrix_test.tscn"
CHARACTERS = ("wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord")
WEAPONS = ("sword", "bow", "gun", "staff", "gauntlets")
PAIRS = (("stop", "rewind"), ("stop", "rift"), ("stop", "accelerate"), ("rewind", "rift"), ("rewind", "accelerate"), ("rift", "accelerate"))
BOSSES = ("ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne")
CASE_COUNT = 750
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|(?:^|\n)ERROR:|ObjectDB instances leaked|RID.*leaked|Orphan (?:Node|StringName)", re.I)


def positive_number(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value > 0


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
        traces = row.get("damage_trace", [])
        if not isinstance(traces, list) or not traces or any(not isinstance(hit, dict) or not positive_number(hit.get("actual_loss")) or not positive_number(hit.get("amount")) or type(hit.get("attack_generation")) is not int or hit["attack_generation"] < 1 or not isinstance(hit.get("tags"), list) or f"weapon:{row['identity']['weapon_id']}" not in hit["tags"] for hit in traces):
            errors.append(f"{label}: missing authentic production weapon damage trace")
        receipts = row.get("time_casts", [])
        if not isinstance(receipts, list) or any(not isinstance(receipt, dict) for receipt in receipts) or [r.get("ability_id") for r in receipts] != row["identity"]["time_abilities"] or any(r.get("run_id") != f"p15-native-matrix-{index}" or not positive_number(r.get("runtime_frame")) or not re.fullmatch(r"[0-9a-f]{64}", str(r.get("id", ""))) for r in receipts):
            errors.append(f"{label}: both actual equipped time receipts are required")
        if not row.get("positive_time") or not row.get("weapon_actions") or not row.get("boss_actions"):
            errors.append(f"{label}: missing actual action or positive time interaction")
        source = "matrix-" + hashlib.sha256(f"p15-native-matrix-{index}".encode()).hexdigest()[:40]
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
    command = [godot, "--headless", "--path", str(ROOT), "--log-file", str(directory / "godot.log"), SCENE]
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
    if ERROR.search(output):
        errors.insert(0, "Godot contains an error, orphan or leak diagnostic")
    if report.get("report_kind") != "actual_native_boss_loadout_matrix" or report.get("synthetic") is not False:
        errors.append("native shard provenance is missing")
    errors.extend(validate_content_snapshot(report.get("content_snapshot")))
    return {"range_start": start, "requested_case_count": count, "logs": str(directory.relative_to(ROOT)), "errors": errors, "report": report}


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
    result = {"schema_version": 1, "report_kind": "actual_native_boss_loadout_matrix", "synthetic": False, "human_playtests": 0, "difficulty": "normal", "unassisted_victory": False, "survival_fixture": "p15_matrix_survival_fixture", "content_snapshot": snapshots[0] if snapshots else {}, "range_start": args.start, "requested_case_count": args.count, "expected_production_case_count": CASE_COUNT, "production_case_count": len(rows), "native_complete": args.start == 0 and args.count == CASE_COUNT and not errors, "p15_complete": False, "synthetic_case_count": 0, "expected_synthetic_case_count": 22500, "errors": errors, "shards": [{key: value for key, value in shard.items() if key != "report"} for shard in shards], "cases": rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"actual native cases{len(rows)}/{args.count}; errors{len(errors)}; report{output}", flush=True)
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
