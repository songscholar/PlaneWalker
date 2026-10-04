#!/usr/bin/env python3
"""Collect deterministic synthetic dungeon evidence from the real Godot domain."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CANONICAL_SEEDS = tuple(range(20261001, 20261031))
GENERATOR_VERSION = "floor_plan_v1"
PROBE_VERSION = "1.0.0"
FAILURE_MARKERS = (
    "SCRIPT ERROR:", "Parse Error:", "Failed to load script", "Failed loading resource",
    "Cannot load resource",
    "ObjectDB instances leaked at exit", "RID allocations leaked at exit",
)
MACOS_CA_ERROR = 'ERROR: Condition "ret != noErr" is true. Returning: ""'
MACOS_CA_CALLSITE = "at: get_system_ca_certificates (platform/macos/os_macos.mm:"
ROOT_FIELDS = {
    "schema_version", "report_type", "synthetic", "human_playtests", "methodology",
    "content_digest", "content_digests", "generator_version", "seeds",
    "floor_summaries", "summary", "report_digest",
}
_CACHE: dict[tuple[Any, ...], dict[str, Any]] = {}


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode()


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def content_digests() -> dict[str, str]:
    paths = sorted((PROJECT_ROOT / "data/content_packs/base").rglob("*.json"))
    return {str(path.relative_to(PROJECT_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths}


def _runtime_digests() -> dict[str, str]:
    paths = [PROJECT_ROOT / "tools/dungeon/dungeon_simulation_runner.gd",
             PROJECT_ROOT / "tools/dungeon/dungeon_simulation_probe.gd"]
    paths.extend(sorted((PROJECT_ROOT / "scripts").rglob("*.gd")))
    paths.extend(sorted((PROJECT_ROOT / "scenes/player").rglob("*.tscn")))
    return {str(path.relative_to(PROJECT_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths)}


def _unapproved_error_lines(log_text: str) -> list[str]:
    errors = sorted({line.strip() for line in log_text.splitlines()
                     if line.strip().startswith("ERROR:")})
    unapproved = [line for line in errors if line != MACOS_CA_ERROR]
    if MACOS_CA_ERROR in errors and MACOS_CA_CALLSITE not in log_text:
        unapproved.append("macOS CA sandbox error missing expected call site")
    return unapproved


def _run_failure_summaries(runs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [{"seed": run.get("seed"), "failures": run.get("failures", []),
             "last_floor": (run.get("floor_summaries") or [{}])[-1].get("floor_index")}
            for run in runs if run.get("failures") or not run.get("victory")]


def _run_probe(godot_bin: str, timeout_seconds: int) -> dict[str, Any]:
    executable = shutil.which(godot_bin) if "/" not in godot_bin else godot_bin
    if not executable:
        raise ValueError(f"Godot executable unavailable: {godot_bin}")
    with tempfile.TemporaryDirectory(prefix="planewalker-dungeon-probe-") as directory:
        root = Path(directory)
        raw_path, log_path = root / "raw.json", root / "godot.log"
        environment = os.environ.copy()
        environment.update({
            "PLANEWALKER_DUNGEON_OUTPUT": str(raw_path),
            "PLANEWALKER_TEST_DATA_DIR": str(root / "files"),
            "XDG_DATA_HOME": str(root / "user"), "XDG_CACHE_HOME": str(root / "cache"),
        })
        command = [executable, "--headless", "--path", str(PROJECT_ROOT),
                   "--log-file", str(log_path), "res://tools/dungeon/dungeon_simulation_probe.tscn"]
        try:
            completed = subprocess.run(command, cwd=PROJECT_ROOT, env=environment,
                                       capture_output=True, text=True, timeout=timeout_seconds)
        except subprocess.TimeoutExpired as error:
            raise ValueError(f"Godot dungeon probe exceeded {timeout_seconds}s") from error
        engine_log = log_path.read_text(errors="replace") if log_path.exists() else ""
        combined = completed.stdout + completed.stderr + engine_log
        if completed.returncode or _unapproved_error_lines(combined) or any(
                marker in combined for marker in FAILURE_MARKERS):
            failures = []
            if raw_path.exists():
                raw = json.loads(raw_path.read_text())
                failures = _run_failure_summaries(raw.get("runs", []))
            raise ValueError(f"Godot dungeon probe failed ({completed.returncode}):\n"
                             f"{combined[-12000:]}\nRun failures: {failures}")
        if not raw_path.exists():
            raise ValueError("Godot dungeon probe produced no report")
        raw = json.loads(raw_path.read_text())
        if raw.get("probe_version") != PROBE_VERSION:
            raise ValueError("Godot dungeon probe version mismatch")
        return raw


def _bands(values: list[int]) -> dict[str, int]:
    ordered = sorted(values)
    return {"min": min(ordered), "median": ordered[len(ordered) // 2], "max": max(ordered)}


def _budget_comparison(rows: list[dict[str, Any]]) -> dict[str, Any]:
    profiles = json.loads((PROJECT_ROOT / "data/content_packs/base/content/economy_profiles.json").read_text())
    profile = next(value for value in profiles if value["id"] == "launch_economy_v1")
    comparisons = {}
    for budget in profile["floor_income_budgets"]:
        floor_number = budget["floor_index"]
        observed = [row for row in rows if row["floor_index"] == floor_number - 1]
        comparison = {}
        for metric, target in (("gold_earned", "earned"), ("gold_spent", "spend"),
                               ("gold_remainder", "remainder")):
            minimum, maximum = budget[f"{target}_min"], budget[f"{target}_max"]
            values = [row[metric] for row in observed]
            deltas = [value - minimum if value < minimum else value - maximum
                      if value > maximum else 0 for value in values]
            comparison[metric] = {
                "target_min": minimum, "target_max": maximum,
                "below_target_count": sum(value < minimum for value in values),
                "within_target_count": sum(minimum <= value <= maximum for value in values),
                "above_target_count": sum(value > maximum for value in values),
                "distance_from_target_band": _bands(deltas),
            }
        comparisons[str(floor_number)] = comparison
    return comparisons


def _summarize(rows: list[dict[str, Any]], runs: list[dict[str, Any]]) -> dict[str, Any]:
    paths, room_types, rules, merchants, events = Counter(), Counter(), Counter(), Counter(), Counter()
    bands = {}
    for row in rows:
        paths[str(len(row["route_edge_ids"]))] += 1
        room_types.update(row["room_types"])
        rules[row["rule_id"]] += 1
        merchants.update(row["merchant_ids"])
        events.update(row["event_ids"])
    for index in range(5):
        floor_rows = [row for row in rows if row["floor_index"] == index]
        bands[str(index + 1)] = {
            key: _bands([row[key] for row in floor_rows])
            for key in ("gold_earned", "gold_spent", "gold_remainder")
        }
    return {
        "completed_run_count": sum(run["victory"] and not run["failures"] for run in runs),
        "invalid_plan_count": sum(bool(row["failures"]) or not row["completed"] for row in rows),
        "negative_balance_count": sum(row["minimum_gold_balance"] < 0 for row in rows),
        "all_buy_count": sum(row["all_buy_count"] for row in rows),
        "merchant_purchase_count": sum(len(row["merchant_purchases"]) for row in rows),
        "event_consequence_count": sum(row["event_consequence_count"] for row in rows),
        "route_path_distribution": dict(sorted(paths.items())),
        "room_type_distribution": dict(sorted(room_types.items())),
        "floor_rule_exposure": dict(sorted(rules.items())),
        "merchant_exposure": dict(sorted(merchants.items())),
        "event_exposure": dict(sorted(events.items())),
        "gold_bands": bands,
        "economy_budget_comparison": _budget_comparison(rows),
    }


def build_report(seed_count: int = 30, *, godot_bin: str | None = None,
                 timeout_seconds: int = 180) -> dict[str, Any]:
    if seed_count != 30:
        raise ValueError("dungeon evidence requires exactly 30 canonical seeds")
    sources, runtime_sources = content_digests(), _runtime_digests()
    executable = godot_bin or os.environ.get("GODOT_BIN", "godot")
    cache_key = (_digest(sources), _digest(runtime_sources), executable)
    if cache_key in _CACHE:
        return copy.deepcopy(_CACHE[cache_key])
    raw = _run_probe(executable, timeout_seconds)
    runs = raw.get("runs", [])
    if [run.get("seed") for run in runs] != list(CANONICAL_SEEDS):
        raise ValueError("Godot probe did not execute all canonical seeds in order")
    failed_runs = [run for run in runs if run.get("failures") or not run.get("victory")]
    if failed_runs:
        raise ValueError(f"Godot dungeon runs failed: {_run_failure_summaries(failed_runs)}")
    rows = [row for run in runs for row in run.get("floor_summaries", [])]
    if [(row.get("seed"), row.get("floor_index")) for row in rows] != [
            (seed, index) for seed in CANONICAL_SEEDS for index in range(5)]:
        raise ValueError("Godot probe did not produce the complete 150-floor matrix")
    runtime_content = {run.get("runtime_content_digest") for run in runs}
    if len(runtime_content) != 1:
        raise ValueError("runtime content changed during the probe")
    if any(row.get("generator_version") != GENERATOR_VERSION for row in rows):
        raise ValueError("runtime generator version differs from the report contract")
    if content_digests() != sources or _runtime_digests() != runtime_sources:
        raise ValueError("dungeon sources changed during the probe; rerun after concurrent edits finish")
    report = {
        "schema_version": "1.0.0", "report_type": "five_floor_dungeon",
        "synthetic": True, "human_playtests": 0,
        "methodology": {
            "runtime": "godot_domain_probe", "probe_version": PROBE_VERSION,
            "combat": "domain_completion_commands",
            "floor_rule_authority": "production_player_effects_in_fixture_zone",
            "income": "production_room_completion_and_authored_event_receipts",
            "merchant_policy": "price_then_id_unowned_compatible_offers_until_floor_spend_min_or_unaffordable",
            "all_buy_metric": "entire_inventory_affordable_before_purchase",
            "route_policy": "seed_plus_step_modulo_available_choices",
            "claim_boundary": "automated_domain_evidence_without_combat_or_human_balance_claims",
            "runtime_content_digest": next(iter(runtime_content)),
            "runtime_source_digests": runtime_sources,
        },
        "content_digests": sources, "content_digest": _digest(sources),
        "generator_version": GENERATOR_VERSION, "seeds": list(CANONICAL_SEEDS),
        "floor_summaries": rows, "summary": _summarize(rows, runs),
    }
    report["report_digest"] = report_digest(report)
    _CACHE.clear()
    _CACHE[cache_key] = copy.deepcopy(report)
    return report


def report_digest(report: dict[str, Any]) -> str:
    return _digest({key: value for key, value in report.items() if key != "report_digest"})


def validate_report(report: Any, *, godot_bin: str | None = None) -> list[str]:
    if not isinstance(report, dict):
        return ["report must be an object"]
    reasons = []
    if set(report) != ROOT_FIELDS:
        reasons.append("unknown or missing report fields")
    if report.get("synthetic") is not True or report.get("human_playtests") != 0:
        reasons.append("evidence must remain synthetic with zero human playtests")
    if report.get("report_digest") != report_digest(report):
        reasons.append("report digest mismatch")
    if report.get("content_digests") != content_digests():
        reasons.append("source content digest mismatch")
    # Reuse a fresh engine observation within this invocation; there is no Python
    # generator or economy implementation that could certify its own predictions.
    expected = build_report(godot_bin=godot_bin)
    if report != expected:
        reasons.append("report differs from authoritative Godot receipts and recomputed totals")
    return reasons


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=30)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args()
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    try:
        report = build_report(args.seeds, godot_bin=args.godot_bin, timeout_seconds=args.timeout_seconds)
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=True) + "\n")
    print(json.dumps({"output": str(args.output), "report_digest": report["report_digest"],
                      "floor_summaries": len(report["floor_summaries"]),
                      "synthetic": True, "human_playtests": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
