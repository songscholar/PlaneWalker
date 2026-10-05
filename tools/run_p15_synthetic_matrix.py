#!/usr/bin/env python3
"""Execute and validate synthetic P15 domain traces, independently of native fights."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


CHARACTERS = ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
WEAPONS = ["sword", "bow", "gun", "staff", "gauntlets"]
TIME_PAIRS = [["stop", "rewind"], ["stop", "rift"], ["stop", "accelerate"], ["rewind", "rift"], ["rewind", "accelerate"], ["rift", "accelerate"]]
BOSSES = ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
SEEDS = [2026100500 + index for index in range(30)]
CASE_COUNT = 22500
LOG_FAILURE = re.compile(r"(?:SCRIPT ERROR:|ERROR:|Parse Error:|ObjectDB instances leaked|resources still in use|RID.+leaked)")
SHA = re.compile(r"[a-f0-9]{64}\Z")


def source_binding(root: Path) -> dict:
    paths = sorted(set(root.glob("scripts/**/*.gd")) | set(root.glob("data/content_packs/base/**/*.json")) |
                   {root / "tools/run_p15_synthetic_matrix.py", root / "tools/p15/hostile_synthetic_probe.gd", root / "tools/p15/hostile_synthetic_probe.tscn"})
    hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    encoded = json.dumps(hashes, sort_keys=True, separators=(",", ":")).encode()
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=False)
    return {"git_commit": revision.stdout.strip(), "domain_files_sha256": hashlib.sha256(encoded).hexdigest(), "files": hashes}


def canonical_profiles(root: Path) -> tuple[dict, dict]:
    rows = json.loads((root / "data/content_packs/base/content/character_runtime_profiles.json").read_text(encoding="utf-8"))
    characters = {row["character_id"]: row for row in rows if "LAUNCH" in row["availability"]}
    rows = json.loads((root / "data/content_packs/base/content/weapon_runtime_profiles.json").read_text(encoding="utf-8"))
    weapons = {row["weapon_id"]: row for row in rows if "LAUNCH" in row["availability"]}
    return characters, weapons


def profile_errors(row: dict, characters: dict, weapons: dict) -> list[str]:
    identity = row["identity"]
    character, weapon = characters[identity["character_id"]], weapons[identity["weapon_id"]]
    primary = next(action for action in weapon["actions"] if action["semantic_action"] == "weapon_primary")
    payload = next(value for value in weapon["payloads"] if value["payload_id"] == primary["payload_id"])
    inputs = row.get("profile_inputs")
    if not isinstance(inputs, dict):
        return [f"case:{identity['index']}:profile_inputs"]
    expected = {"character_profile": character["id"], "weapon_profile": weapon["id"],
                "attack": character["base_stats"]["attack"], "attack_speed": character["base_stats"]["attack_speed"],
                "move_speed": character["base_stats"]["move_speed"], "synthetic_damage_amount": character["base_stats"]["attack"] * payload["parameters"].get("damage_multiplier", 1.0),
                "payload": payload, "time_interactions": {ability: {"character": character["time_interactions"][ability], "weapon": weapon["time_interactions"][ability]} for ability in identity["time_abilities"]}}
    # The profile parser fills optional action defaults; authored fields must survive exactly.
    if any(inputs.get(field) != value for field, value in expected.items()) or not isinstance(inputs.get("weapon_action"), dict) or any(inputs["weapon_action"].get(field) != value for field, value in primary.items()):
        return [f"case:{identity['index']}:canonical_profile_divergence"]
    observations = row.get("time_observations")
    if not isinstance(observations, list) or len(observations) != 2:
        return [f"case:{identity['index']}:time_observations"]
    for ability, observation in zip(identity["time_abilities"], observations):
        if not isinstance(observation, dict) or observation.get("ability") != ability:
            return [f"case:{identity['index']}:time_observation_identity"]
        if ability in ["stop", "rift"]:
            if observation.get("kind") != "actual_boss_control" or observation.get("accepted") is not True:
                return [f"case:{identity['index']}:time_control"]
            if ability == "stop" and (observation.get("duration") != 180 + character["time_interactions"]["stop"]["parameters"].get("window_bonus_frames", 0) or observation.get("conversion", 0) <= 0):
                return [f"case:{identity['index']}:stop_conversion"]
            if ability == "rift" and observation.get("actual_multiplier") != 0.7:
                return [f"case:{identity['index']}:rift_floor"]
        elif observation.get("kind") != "synthetic_profile_damage" or observation.get("synthetic_profile_observation") != expected["time_interactions"][ability]:
            return [f"case:{identity['index']}:time_profile_observation"]
    return []


def case_identity(index: int) -> dict:
    if type(index) is not int or not 0 <= index < CASE_COUNT:
        raise ValueError("case index must be an integer in [0,22500)")
    seed_index, local = divmod(index, 750)
    loadout, boss_index = divmod(local, 5)
    character_index, tail = divmod(loadout, 30)
    weapon_index, pair_index = divmod(tail, 6)
    abilities = TIME_PAIRS[pair_index]
    return {"index": index, "seed_index": seed_index, "seed": SEEDS[seed_index], "loadout_index": loadout,
            "character_id": CHARACTERS[character_index], "weapon_id": WEAPONS[weapon_index],
            "time_abilities": abilities, "boss_id": BOSSES[boss_index], "boss_index": boss_index,
            "key": f"{SEEDS[seed_index]}|{CHARACTERS[character_index]}|{WEAPONS[weapon_index]}|{'+'.join(abilities)}|{BOSSES[boss_index]}"}


def authored_action_ids(root: Path) -> list[str]:
    rows = json.loads((root / "data/content_packs/base/content/bosses.json").read_text(encoding="utf-8"))
    return sorted(action["id"] for boss in rows for action in boss["actions"] + boss["time_responses"])


def case_errors(row: object, expected_index: int, action_ids: list[str]) -> list[str]:
    prefix = f"case:{expected_index}"
    if not isinstance(row, dict) or row.get("identity") != case_identity(expected_index):
        return [prefix + ":identity"]
    errors = []
    for field in ["trace_sha256", "repeat_sha256", "checkpoint_sha256", "profile_inputs_sha256", "recipe_affix_sha256"]:
        if not isinstance(row.get(field), str) or SHA.fullmatch(row[field]) is None:
            errors.append(prefix + ":" + field)
    if row.get("trace_sha256") != row.get("repeat_sha256"):
        errors.append(prefix + ":repeat_divergence")
    if row.get("action_id") not in action_ids or type(row.get("frames")) is not int or not 1 <= row["frames"] <= 19000:
        errors.append(prefix + ":action_or_frames")
    if row.get("time_inputs") != row["identity"]["time_abilities"] or row.get("time_input_count") != 2:
        errors.append(prefix + ":equipped_time_inputs")
    if not isinstance(row.get("accepted_damage"), (int, float)) or isinstance(row.get("accepted_damage"), bool) or not math.isfinite(row["accepted_damage"]) or row["accepted_damage"] <= 0:
        errors.append(prefix + ":accepted_damage")
    for field in ["typed_cold_next_frame_equal", "malformed_snapshot_refused", "phase_monotonic", "terminal_cleanup", "profile_inputs_consumed"]:
        if row.get(field) is not True:
            errors.append(prefix + ":" + field)
    if row.get("unwarned_hits") != 0 or row.get("errors") != []:
        errors.append(prefix + ":runtime_failure")
    if not isinstance(row.get("recipe_id"), str) or not row["recipe_id"] or not isinstance(row.get("affix_ids"), list) or not row["affix_ids"] or row["affix_ids"] != sorted(set(row["affix_ids"])):
        errors.append(prefix + ":seeded_recipe_affixes")
    if type(row.get("hit_count")) is not int or row["hit_count"] < 0 or type(row.get("effect_count")) is not int or row["effect_count"] < 1:
        errors.append(prefix + ":unexecuted_action")
    return errors


def budget_errors(value: object) -> list[str]:
    expected = {"projectile_peak": 32, "zone_peak": 12, "zone_pulse_peak": 12, "reservation_count": 256,
                "projectile_overflow_pending": True, "zone_overflow_pending": True,
                "reservation_overflow_refused": True, "typed_cold_equal": True,
                "finite_lifetime_cleanup": True, "response_pending_peak": 4,
                "response_overflow_bounded": True, "terminal_response_cleanup": True,
                "errors": []}
    return [] if isinstance(value, dict) and value == expected and all(type(value[key]) is type(expected_value) for key, expected_value in expected.items()) else ["adversarial_budgets"]


def counterplay_errors(value: object) -> list[str]:
    if not isinstance(value, dict) or value.get("case_count") != 8 or not isinstance(value.get("cases"), list) or len(value["cases"]) != 8:
        return ["positive_response_count"]
    for row, (phase, ability) in zip(value["cases"], [(phase, ability) for phase in [0, 1] for ability in ["stop", "rewind", "accelerate", "rift"]]):
        if not isinstance(row, dict) or row.get("phase") != phase or row.get("ability") != ability or row.get("errors") != [] or any(row.get(field) is not True for field in ["positive_response", "typed_cold_equal", "duplicate_refused", "terminal_cleanup", "repeat_equal"]) or SHA.fullmatch(str(row.get("trace_sha256", ""))) is None or row.get("trace_sha256") != row.get("repeat_sha256"):
            return ["positive_response_invariant"]
    return []


def validate_report(value: object, root: Path, require_complete: bool = True) -> list[str]:
    if not isinstance(value, dict):
        return ["report_shape"]
    errors = []
    if any(value.get(key) != expected or type(value.get(key)) is not type(expected) for key, expected in {
        "schema_version": 1, "report_kind": "synthetic_hostile_domain_matrix", "synthetic": True,
        "production_case_count": 0, "human_playtests": 0, "unassisted_victory": False,
        "expected_synthetic_case_count": CASE_COUNT,
    }.items()):
        errors.append("report_classification")
    start, count = value.get("range_start"), value.get("requested_case_count")
    if type(start) is not int or type(count) is not int or start < 0 or count < 1 or start + count > CASE_COUNT:
        return errors + ["report_range"]
    rows = value.get("cases")
    if not isinstance(rows, list) or value.get("synthetic_case_count") != len(rows) or len(rows) != count:
        return errors + ["case_count"]
    actions = authored_action_ids(root)
    if len(actions) != 52:
        errors.append("authored_action_count")
    coverage = {action: 0 for action in actions}
    characters, weapons = canonical_profiles(root)
    boss_rows = json.loads((root / "data/content_packs/base/content/bosses.json").read_text(encoding="utf-8"))
    boss_actions = {boss["id"]: {action["id"] for action in boss["actions"] + boss["time_responses"]} for boss in boss_rows}
    for offset, row in enumerate(rows):
        errors.extend(case_errors(row, start + offset, actions))
        if isinstance(row, dict) and row.get("identity") == case_identity(start + offset):
            errors.extend(profile_errors(row, characters, weapons))
            if row.get("action_id") not in boss_actions[row["identity"]["boss_id"]]:
                errors.append(f"case:{start + offset}:boss_action_identity")
            if row.get("enrage_threshold_observed") is not (row["identity"]["loadout_index"] == 149):
                errors.append(f"case:{start + offset}:enrage_threshold")
        if isinstance(row, dict) and row.get("action_id") in coverage:
            coverage[row["action_id"]] += 1
    if value.get("action_coverage") != coverage:
        errors.append("action_coverage_mismatch")
    binding = value.get("source_binding")
    current = source_binding(root)
    if not isinstance(binding, dict) or binding.get("domain_files_sha256") != current["domain_files_sha256"] or binding.get("files") != current["files"] or re.fullmatch(r"[a-f0-9]{40}", str(binding.get("git_commit", ""))) is None:
        errors.append("source_binding")
    content = value.get("content_snapshot")
    if not isinstance(content, dict) or SHA.fullmatch(str(content.get("aggregate_sha256", ""))) is None or not isinstance(content.get("packs"), list) or len(content["packs"]) != 1 or content["packs"][0].get("pack_id") != "base" or SHA.fullmatch(str(content["packs"][0].get("fingerprint_sha256", ""))) is None:
        errors.append("content_binding")
    budgets = value.get("budgets")
    if not isinstance(budgets, list) or not budgets:
        errors.append("budget_evidence_missing")
    else:
        for budget in budgets:
            errors.extend(budget_errors(budget))
    counterplay = value.get("counterplay")
    if not isinstance(counterplay, list) or not counterplay:
        errors.append("positive_response_evidence_missing")
    else:
        for sample in counterplay:
            errors.extend(counterplay_errors(sample))
    complete = start == 0 and count == CASE_COUNT and not errors and all(coverage.values())
    if value.get("complete") != complete or value.get("status") != ("pass" if not errors else "failed"):
        errors.append("completion_claim")
    if require_complete and not complete:
        errors.append("full_matrix_incomplete")
    if value.get("errors") != []:
        errors.append("reported_errors")
    return errors


def _run_shard(root: Path, binary: str, start: int, count: int, logs: Path, timeout: int) -> dict:
    shard = logs / f"{start:05d}"
    shard.mkdir(parents=True, exist_ok=True)
    output, engine, stdout = shard / "domain.json", shard / "engine.log", shard / "stdout.log"
    for path in [output, engine]:
        path.unlink(missing_ok=True)
    environment = dict(os.environ)
    environment.update(PLANEWALKER_SYNTHETIC_START=str(start), PLANEWALKER_SYNTHETIC_COUNT=str(count),
                       PLANEWALKER_SYNTHETIC_OUTPUT=str(output), PLANEWALKER_TEST_DATA_DIR=str(shard / "data"))
    command = [binary, "--headless", "--path", str(root), "--log-file", str(engine), "res://tools/p15/hostile_synthetic_probe.tscn"]
    failures = []
    exit_code = None
    try:
        with stdout.open("w", encoding="utf-8") as handle:
            completed = subprocess.run(command, cwd=root, env=environment, stdout=handle,
                                       stderr=subprocess.STDOUT, timeout=timeout, check=False)
        exit_code = completed.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        failures.append(type(error).__name__)
    for path in [stdout, engine]:
        if path.exists():
            failures.extend(line for line in path.read_text(encoding="utf-8", errors="replace").splitlines() if LOG_FAILURE.search(line))
    try:
        report = json.loads(output.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        report = {}
        failures.append("missing_or_invalid_domain_report")
    if exit_code != 0:
        failures.append("domain_process_failed")
    return {"start": start, "count": count, "exit_code": exit_code, "logs": str(shard),
            "errors": failures, "report": report}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--seed-count", type=int, default=30)
    parser.add_argument("--loadout-count", type=int, default=150)
    parser.add_argument("--boss-count", type=int, default=5)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--count", type=int, default=CASE_COUNT)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--shard-size", type=int, default=750)
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--output", type=Path, default=Path("build/p15-synthetic-matrix.json"))
    args = parser.parse_args()
    if (args.seed_count, args.loadout_count, args.boss_count) != (30, 150, 5) or args.start < 0 or args.count < 1 or args.start + args.count > CASE_COUNT or not 1 <= args.workers <= 8 or args.shard_size < 1 or args.timeout_seconds < 1:
        parser.error("canonical matrix is30x150x5; ranges, workers and timeouts must be bounded")
    binary = shutil.which(args.godot_bin)
    if binary is None:
        parser.error("Godot executable unavailable")
    root = args.project_root.resolve()
    binding = source_binding(root)
    started = time.monotonic()
    output = (root / args.output).resolve()
    output.relative_to(root)
    logs = output.parent / (output.stem + "-shards")
    intervals = [(start, min(args.shard_size, args.start + args.count - start)) for start in range(args.start, args.start + args.count, args.shard_size)]
    shards = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(_run_shard, root, binary, start, count, logs, args.timeout_seconds) for start, count in intervals]
        for future in concurrent.futures.as_completed(futures):
            shard = future.result()
            shards.append(shard)
            print(f"synthetic shard {shard['start']}+{shard['count']}: exit={shard['exit_code']} errors={len(shard['errors'])}", flush=True)
    shards.sort(key=lambda value: value["start"])
    rows, errors, budgets, bindings, counterplay = [], [], [], [], []
    for shard in shards:
        errors.extend(shard["errors"])
        report = shard["report"]
        if report.get("schema_version") != 1 or report.get("range_start") != shard["start"] or report.get("requested_case_count") != shard["count"] or report.get("synthetic") is not True or report.get("production_case_count") != 0 or report.get("human_playtests") != 0 or not isinstance(report.get("cases"), list) or len(report["cases"]) != shard["count"]:
            errors.append(f"shard:{shard['start']}:invalid_header")
        rows.extend(report.get("cases", []))
        if report.get("errors") != []:
            errors.append(f"shard:{shard['start']}:reported_errors")
        budgets.append(report.get("budgets", {}))
        counterplay.append(report.get("counterplay", {}))
        bindings.append(report.get("content_snapshot", {}))
    coverage = {action: 0 for action in authored_action_ids(root)}
    for row in rows:
        if row.get("action_id") in coverage:
            coverage[row["action_id"]] += 1
    if not bindings or not bindings[0] or any(value != bindings[0] for value in bindings):
        errors.append("content_binding_divergence")
    if source_binding(root)["domain_files_sha256"] != binding["domain_files_sha256"]:
        errors.append("source_changed_during_execution")
    result = {"schema_version": 1, "report_kind": "synthetic_hostile_domain_matrix", "synthetic": True,
              "production_case_count": 0, "human_playtests": 0, "unassisted_victory": False,
              "expected_synthetic_case_count": CASE_COUNT, "synthetic_case_count": len(rows),
              "range_start": args.start, "requested_case_count": args.count, "content_snapshot": bindings[0] if bindings else {},
              "source_binding": binding, "elapsed_seconds": round(time.monotonic() - started, 3),
              "action_coverage": coverage, "budgets": budgets, "counterplay": counterplay, "cases": rows, "errors": [],
              "complete": False, "status": "pass", "shards": [{key: value for key, value in shard.items() if key != "report"} for shard in shards]}
    result["complete"] = args.start == 0 and args.count == CASE_COUNT and not errors and all(coverage.values())
    errors.extend(validate_report(result, root, require_complete=False))
    result["errors"] = errors
    result["status"] = "failed" if errors else "pass"
    result["complete"] = result["complete"] and not errors
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "complete": result["complete"], "synthetic_case_count": len(rows),
                      "action_count": sum(count > 0 for count in coverage.values()), "errors": errors[:10], "output": str(output)}, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
