#!/usr/bin/env python3
"""Run honest, uninstrumented production Main timing and recording evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
METRICS = {"player_advance", "host_process", "physics_wait", "observer"}
COUNTS = {"actors", "summons", "projectiles", "zones", "constructs", "threats"}


def _number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def _metric(value, count):
    if not isinstance(value, dict) or value.get("count") != count or type(value.get("count")) is not int:
        raise ValueError("timing sample count differs from actual accepted frames")
    for key in ["total_usec", "mean_usec", "p50_usec", "p95_usec", "maximum_usec"]:
        if not _number(value.get(key)):
            raise ValueError("timings must be finite nonnegative numbers")
    if not value["p50_usec"] <= value["p95_usec"] <= value["maximum_usec"] or not math.isclose(value["mean_usec"] * count, value["total_usec"], rel_tol=1e-6, abs_tol=0.01):
        raise ValueError("timing distribution is internally inconsistent")


def validate_report(value):
    if not isinstance(value, dict) or type(value.get("schema_version")) is not int or value.get("schema_version") != 1 or value.get("report_kind") != "actual_native_main_performance" or value.get("status") != "pass":
        raise ValueError("actual native Main performance report did not pass")
    if value.get("human_playtests") != 0 or value.get("unassisted_victory") is not False or value.get("fps_certified") is not False or value.get("survival_fixture") != "native_performance_survival_fixture":
        raise ValueError("performance samples cannot claim human, unassisted or FPS certification")
    count = value.get("accepted_frames")
    if type(count) is not int or not 1 <= count <= 162000 or count != value.get("requested_frames") or value.get("failures") != []:
        raise ValueError("every requested actual native frame must pass")
    scheduler = value.get("scheduler", {})
    if scheduler.get("physics_ticks_per_second") != 60 or type(scheduler.get("physics_ticks_per_second")) is not int or scheduler.get("native_hz") != 60 or type(scheduler.get("native_hz")) is not int or type(scheduler.get("time_scale")) not in (int, float) or scheduler.get("time_scale") != 1.0 or type(scheduler.get("wall_accelerated")) is not bool:
        raise ValueError("production 60Hz native scheduling with unit time scale must be explicit")
    snapshot = value.get("content_snapshot", {})
    packs = snapshot.get("packs", [])
    if not re.fullmatch(r"[0-9a-f]{64}", str(snapshot.get("aggregate_sha256", ""))) or not isinstance(packs, list) or not packs:
        raise ValueError("actual authoritative content fingerprint is required")
    for pack in packs:
        if not isinstance(pack, dict) or not isinstance(pack.get("pack_id"), str) or not pack["pack_id"] or not isinstance(pack.get("pack_version"), str) or not pack["pack_version"] or not re.fullmatch(r"[0-9a-f]{64}", str(pack.get("fingerprint_sha256", ""))):
            raise ValueError("every actual content pack must retain its identity and fingerprint")
    encounter = value.get("encounter", {})
    if type(value.get("prerequisite_route_fixture")) is not bool or type(encounter.get("floor_index")) is not int or not 0 <= encounter["floor_index"] <= 4 or encounter.get("room_type") not in {"combat", "elite", "boss"} or not isinstance(encounter.get("node_id"), str) or not encounter["node_id"]:
        raise ValueError("actual native encounter and prerequisite fixture classification are required")
    if not _number(value.get("native_duration_ms")) or not math.isclose(value["native_duration_ms"], count * 1000 / 60, abs_tol=0.01) or not _number(value.get("wall_duration_usec")):
        raise ValueError("native and elapsed wall durations must be separate and consistent")
    frames = value.get("sample_frames", {})
    if any(type(frames.get(key)) is not int for key in ["first", "last", "unique_count"]) or frames["first"] < 0 or frames["last"] - frames["first"] + 1 != count or frames["unique_count"] != count:
        raise ValueError("measured samples must be unique consecutive actual Player frames")
    metrics = value.get("metrics", {})
    if not isinstance(metrics, dict) or set(metrics) != METRICS:
        raise ValueError("independent Player, Host, physics and observer metrics are required")
    for metric in metrics.values():
        _metric(metric, count)
    if type(value.get("rendered")) is not bool:
        raise ValueError("render availability must be explicit")
    if value["rendered"]:
        _metric(value.get("render_wait"), count)
    elif value.get("render_wait") != {"count": 0}:
        raise ValueError("headless runs cannot invent render timings")
    peaks = value.get("observed_peak_counts", {})
    if not isinstance(peaks, dict) or set(peaks) != COUNTS or any(type(count) is not int or count < 0 for count in peaks.values()) or peaks["actors"] < 1:
        raise ValueError("actual nonnegative observed native concurrency is required")
    recording = value.get("recording", {})
    if recording.get("status") != "INTERRUPTED" or type(recording.get("actual_sample_count")) is not int or recording.get("actual_sample_count") != count or type(recording.get("total_tape_observations")) is not int or recording.get("total_tape_observations") != count + 1 or recording.get("failure") != "" or recording.get("physical_first_exact") is not True or recording.get("physical_last_exact") is not True:
        raise ValueError("physical recording readback and honest incomplete classification are required")
    for key in ["first_sha256", "last_sha256"]:
        if not re.fullmatch(r"[0-9a-f]{64}", str(recording.get(key, ""))):
            raise ValueError("exact retained sample hashes are required")
    hub = value.get("hub", {})
    if type(hub.get("frames")) is not int or hub["frames"] < 1 or type(hub.get("visited_functions")) is not int or hub["visited_functions"] < 9:
        raise ValueError("actual three-district nine-function Hub measurement is required")
    _metric(hub.get("scheduler_and_render_wait"), hub["frames"])
    if not _number(hub.get("wall_duration_usec")) or type(value.get("peak_native_static_bytes")) is not int or value["peak_native_static_bytes"] <= 0:
        raise ValueError("actual Hub duration and native memory observation are required")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--hub-frames", type=int, default=120)
    parser.add_argument("--boss-floor", type=int, default=-1, choices=[-1, 0, 1, 2, 3, 4])
    parser.add_argument("--phase", type=int, default=0, choices=[0, 1, 2])
    parser.add_argument("--real-time", action="store_true", help="keep wall-clock pacing; otherwise use Godot fixed-fps scheduling")
    parser.add_argument("--rendered", action="store_true")
    parser.add_argument("--timeout", type=int, default=28800)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "build") or output.exists():
        parser.error("output must be a new path under this project's build directory")
    if not 1 <= args.frames <= 162000 or not 9 <= args.hub_frames <= 162000 or args.phase > 0 and args.boss_floor < 0 or args.timeout <= 0:
        parser.error("invalid bounded native duration, scheduler or Boss phase")
    godot = shutil.which(os.environ.get("GODOT_BIN", "godot"))
    if not godot:
        parser.error("GODOT_BIN must identify a real Godot executable")
    output.parent.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    environment.update({"PLANEWALKER_PERFORMANCE_OUTPUT": str(output), "PLANEWALKER_PERFORMANCE_FRAMES": str(args.frames), "PLANEWALKER_PERFORMANCE_HUB_FRAMES": str(args.hub_frames), "PLANEWALKER_PERFORMANCE_BOSS_FLOOR": str(args.boss_floor), "PLANEWALKER_PERFORMANCE_PHASE": str(args.phase), "PLANEWALKER_PERFORMANCE_WALL_ACCELERATED": str(not args.real_time).lower(), "PLANEWALKER_PERFORMANCE_RENDERED": str(args.rendered).lower(), "PLANEWALKER_TEST_DATA_DIR": str(output.parent / "isolated-files"), "PLANEWALKER_USER_DATA_DIR": str(output.parent / "isolated-files"), "XDG_DATA_HOME": str(output.parent / "isolated-data")})
    for key in ["PLANEWALKER_COVERAGE_HITS_DIR", "PLANEWALKER_COVERAGE_MANIFEST_SHA256", "GDSCRIPT_COVERAGE_PROVIDER_REPORT"]:
        environment.pop(key, None)
    stdout_path = output.parent / "stdout.log"
    engine_path = output.parent / "godot.log"
    command = [godot, "--path", str(ROOT), "--log-file", str(engine_path)]
    if not args.real_time:
        command.extend(["--fixed-fps", "60"])
    if not args.rendered:
        command.append("--headless")
    command.append("res://tools/p15/native_performance_probe.tscn")
    sources = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for directory in ["scripts", "autoload"] for path in sorted((ROOT / directory).rglob("*.gd"))}
    with stdout_path.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
    logs = stdout_path.read_text(errors="replace") + (engine_path.read_text(errors="replace") if engine_path.is_file() else "")
    if result.returncode or re.search(r"SCRIPT ERROR:|Parse Error:|ERROR:|ObjectDB instances leaked|RID allocations leaked", logs):
        raise SystemExit(f"actual native performance run failed; inspect {stdout_path}")
    report = validate_report(json.loads(output.read_text()))
    git_root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, text=True, capture_output=True, check=False)
    own_checkout = git_root.returncode == 0 and Path(git_root.stdout.strip()).resolve() == ROOT
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, capture_output=True, check=False) if own_checkout else None
    after_sources = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for directory in ["scripts", "autoload"] for path in sorted((ROOT / directory).rglob("*.gd"))}
    if after_sources != sources:
        raise SystemExit("runtime sources changed during native performance measurement")
    report["source"] = {"revision": revision.stdout.strip() if revision is not None and revision.returncode == 0 else "", "runtime_source_sha256": hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(), "instrumented": False}
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"report": str(output), "accepted_frames": report["accepted_frames"], "native_duration_ms": report["native_duration_ms"], "wall_duration_usec": report["wall_duration_usec"], "player_advance": report["metrics"]["player_advance"], "observed_peak_counts": report["observed_peak_counts"]}, indent=2))


if __name__ == "__main__":
    main()
