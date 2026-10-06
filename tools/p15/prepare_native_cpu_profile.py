#!/usr/bin/env python3
"""Install explicit inclusive CPU timers into a clean retained diagnostic clone."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    "scripts/player/player_controller.gd": [
        ("advance_action_frame", "frame_intents: Dictionary = {}", "frame_intents", "bool"),
        ("_fixed_frame_preflight", "", "", "bool"),
        ("_fixed_frame_transaction_snapshot", "", "", "Dictionary"),
        ("_rewind_frame_transaction_snapshot", "", "", "Dictionary"),
        ("_full_player_replay_snapshot", "for_native_recording: bool", "for_native_recording", "Dictionary"),
        ("validate_native_replay_recording_snapshot", "snapshot: Dictionary, expected_identity: Dictionary", "snapshot, expected_identity", "Dictionary"),
        ("_commit_fixed_frame_event_buffers", "", "", "bool"),
        ("_refresh_weapon_replay_fact_baseline", "", "", "void"),
    ],
    "scripts/time_system/time_manager.gd": [(name, "", "", "Dictionary") for name in ["replay_snapshot", "fixed_frame_transaction_snapshot"]],
    "scripts/combat/health_component.gd": [(name, "", "", "Dictionary") for name in ["runtime_state_snapshot", "reward_effect_snapshot", "invulnerability_replay_snapshot"]],
    "scripts/player/characters/character_action_coordinator.gd": [(name, "", "", "Dictionary") for name in ["snapshot", "action_snapshot"]],
    "scripts/combat/weapons/weapon_action_coordinator.gd": [("snapshot", "", "", "Dictionary")],
    "scripts/combat/world_payload_authority.gd": [("replay_snapshot", "", "", "Dictionary")],
    "scripts/input/weapon_intent_router.gd": [("runtime_snapshot", "", "", "Dictionary")],
    "scripts/items/active_item_runtime.gd": [("snapshot", "", "", "Dictionary")],
    "scripts/replay/native_run_replay_recorder.gd": [("_observe", "kind: String, frame: int = -1", "kind, frame", "Dictionary")],
}


def instrument(source: str, path: str, methods: list[tuple[str, str, str, str]]) -> str:
    marker = 'const _NativeCpuProfile := preload("res://tools/p15/native_cpu_profile_trace.gd")\n'
    if "_NativeCpuProfile" in source:
        raise ValueError("CPU profile source must be uninstrumented")
    source, count = re.subn(r"^(extends .+\n)", lambda match: match.group() + marker, source, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("exact source inheritance declaration required")
    for name, parameters, arguments, result_type in methods:
        declaration = re.compile(r"^func " + re.escape(name) + r"\([\s\S]*?\) -> " + result_type + r":$", re.MULTILINE)
        matches = list(declaration.finditer(source))
        if len(matches) != 1:
            raise ValueError(f"exact method/type required: {path}:{name}")
        implementation = "_native_cpu_impl_" + name
        source = source[:matches[0].start()] + matches[0].group().replace("func " + name + "(", "func " + implementation + "(", 1) + source[matches[0].end():]
        label = path.removeprefix("scripts/").removesuffix(".gd") + ":" + name
        call = implementation + "(" + arguments + ")"
        if result_type == "void":
            fast = "\t\t" + call + "\n\t\treturn\n"
            measured = "\t" + call + "\n\t_NativeCpuProfile.leave(started)\n"
        else:
            fast = "\t\treturn " + call + "\n"
            measured = "\tvar value: " + result_type + " = " + call + "\n\t_NativeCpuProfile.leave(started)\n\treturn value\n"
        source += "\n\nfunc " + name + "(" + parameters + ") -> " + result_type + ":\n\tif not _NativeCpuProfile.active:\n" + fast + '\tvar started := _NativeCpuProfile.enter("' + label + '")\n' + measured
    return source


def prepare(checkout: Path) -> None:
    checkout = checkout.resolve(strict=True)
    checkout.relative_to(ROOT / "build/retained-checkout")
    status = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=checkout, check=True, capture_output=True, text=True)
    if status.stdout:
        raise ValueError("diagnostic clone must have a clean tracked worktree")
    replacements = {path: instrument((checkout / path).read_text(), path, methods) for path, methods in TARGETS.items()}
    probe_path = "tools/p15/native_performance_probe.gd"
    probe = (checkout / probe_path).read_text()
    before = "func _measure() -> void:\n"
    after = before + '\tvar cpu_trace := preload("res://tools/p15/native_cpu_profile_trace.gd")\n\tcpu_trace.start()\n'
    if probe.count(before) != 1 or probe.count("\treport.wall_duration_usec = Time.get_ticks_usec() - started") != 1:
        raise ValueError("exact native measurement boundary required")
    probe = probe.replace(before, after).replace("\treport.wall_duration_usec = Time.get_ticks_usec() - started", '\treport["cpu_profile"] = cpu_trace.finish(int(report.accepted_frames))\n\treport.wall_duration_usec = Time.get_ticks_usec() - started')
    replacements[probe_path] = probe
    launcher_path = "tools/p15/native_performance_probe.py"
    launcher = (checkout / launcher_path).read_text()
    if launcher.count('"instrumented": False') != 1:
        raise ValueError("exact source instrumentation marker required")
    replacements[launcher_path] = launcher.replace('"instrumented": False', '"instrumented": True')
    for path, source in replacements.items():
        (checkout / path).write_text(source)
    (checkout / "tools/p15/native_cpu_profile_trace.gd").write_bytes((ROOT / "tools/p15/native_cpu_profile_trace.gd").read_bytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.checkout)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"CPU diagnostic preparation refused: {error}\n")


if __name__ == "__main__":
    main()
