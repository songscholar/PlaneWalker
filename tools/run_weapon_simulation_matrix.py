#!/usr/bin/env python3
"""Run the deterministic P11H synthetic weapon/loadout simulation matrix.

This model consumes authored weapon profiles and produces reproducible balance
observations. It is not gameplay telemetry and never counts as human playtest
evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import fmean
from typing import Any, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = PROJECT_ROOT / "data" / "content_packs" / "base" / "content" / "weapon_runtime_profiles.json"
SCHEMA_VERSION = "1.0.0"
MODEL_VERSION = "p11h-profile-model-v1"
CANONICAL_WEAPONS = ("sword", "bow", "gun", "staff", "gauntlets")
PROFILE_IDS = {
    "sword": "sword_launch_v1",
    "bow": "bow_launch_v1",
    "gun": "gun_launch_v1",
    "staff": "staff_launch_v1",
    "gauntlets": "gauntlets_launch_v1",
}
TIME_PAIRS = (
    ("stop", "rewind"),
    ("stop", "rift"),
    ("stop", "accelerate"),
    ("rewind", "rift"),
    ("rewind", "accelerate"),
    ("rift", "accelerate"),
)
CANONICAL_SEEDS = tuple(range(20260901, 20260931))
EXPECTED_SEED_COUNT = len(CANONICAL_SEEDS)
EXPECTED_LOADOUT_COUNT = len(CANONICAL_WEAPONS) * len(TIME_PAIRS)
EXPECTED_SAMPLE_COUNT = EXPECTED_LOADOUT_COUNT * EXPECTED_SEED_COUNT
METRIC_FIELDS = (
    "dps",
    "risk_uptime",
    "starvation_rate",
    "burst_damage",
    "area_coverage",
    "status_uptime",
    "perfect_reload_value",
    "staff_combination_frequency",
    "gauntlets_combo_retention",
)
RATIO_METRICS = {
    "risk_uptime",
    "starvation_rate",
    "area_coverage",
    "status_uptime",
    "staff_combination_frequency",
    "gauntlets_combo_retention",
}


def build_report(seed_count: int = 30) -> dict[str, Any]:
    if seed_count != EXPECTED_SEED_COUNT:
        raise ValueError(f"seed_count must be exactly {EXPECTED_SEED_COUNT}")
    profiles = _load_profiles()
    seeds = CANONICAL_SEEDS
    samples: list[dict[str, Any]] = []
    loadouts: list[dict[str, Any]] = []
    samples_by_weapon: dict[str, list[dict[str, float]]] = {
        weapon_id: [] for weapon_id in CANONICAL_WEAPONS
    }

    for weapon_id in CANONICAL_WEAPONS:
        model = _profile_model(profiles[PROFILE_IDS[weapon_id]])
        for time_pair in TIME_PAIRS:
            loadout_samples: list[dict[str, float]] = []
            for seed in seeds:
                metrics = _simulate_sample(model, weapon_id, time_pair, seed)
                loadout_samples.append(metrics)
                samples.append(
                    {
                        "weapon_id": weapon_id,
                        "time_pair": list(time_pair),
                        "seed": seed,
                        "metrics": metrics,
                    }
                )
            samples_by_weapon[weapon_id].extend(loadout_samples)
            loadouts.append(
                {
                    "weapon_id": weapon_id,
                    "time_pair": list(time_pair),
                    "sample_count": len(loadout_samples),
                    "metrics": _average_metrics(loadout_samples),
                }
            )

    weapon_summaries = [
        {
            "weapon_id": weapon_id,
            "sample_count": len(samples_by_weapon[weapon_id]),
            "metrics": _average_metrics(samples_by_weapon[weapon_id]),
        }
        for weapon_id in CANONICAL_WEAPONS
    ]
    profile_bytes = PROFILE_PATH.read_bytes()
    report: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "report_type": "weapon_simulation_matrix",
        "evidence": {
            "source": "synthetic",
            "synthetic": True,
            "human_playtests": 0,
            "claim_boundary": "deterministic_model_observation_only",
        },
        "methodology": {
            "model_version": MODEL_VERSION,
            "frames_per_second": 60,
            "seed_policy": "canonical_20260901_through_20260930_exact",
            "samples_per_loadout": EXPECTED_SEED_COUNT,
            "total_samples": EXPECTED_SAMPLE_COUNT,
            "profile_source": str(PROFILE_PATH.relative_to(PROJECT_ROOT)),
            "profile_sha256": hashlib.sha256(profile_bytes).hexdigest(),
            "disclaimer": (
                "Synthetic deterministic profile simulation; this does not represent human playtest evidence."
            ),
        },
        "weapons": list(CANONICAL_WEAPONS),
        "time_pairs": [list(pair) for pair in TIME_PAIRS],
        "seeds": list(seeds),
        "samples": samples,
        "loadouts": loadouts,
        "weapon_summaries": weapon_summaries,
    }
    report["content_digest"] = report_digest(report)
    violations = validate_report(report)
    if violations:
        raise ValueError("generated report violates its contract: " + "; ".join(violations))
    return report


def report_digest(report: dict[str, Any]) -> str:
    payload = {key: value for key, value in report.items() if key != "content_digest"}
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_report(report: Any) -> list[str]:
    violations: list[str] = []
    if type(report) is not dict:
        return ["root: expected object"]
    expected_root = {
        "schema_version",
        "report_type",
        "evidence",
        "methodology",
        "weapons",
        "time_pairs",
        "seeds",
        "samples",
        "loadouts",
        "weapon_summaries",
        "content_digest",
    }
    _check_exact_fields(report, expected_root, "root", violations)
    if report.get("schema_version") != SCHEMA_VERSION:
        violations.append("schema_version: unsupported value")
    if report.get("report_type") != "weapon_simulation_matrix":
        violations.append("report_type: unsupported value")

    expected_evidence = {
        "source": "synthetic",
        "synthetic": True,
        "human_playtests": 0,
        "claim_boundary": "deterministic_model_observation_only",
    }
    if report.get("evidence") != expected_evidence:
        violations.append("evidence: report must remain synthetic with zero human playtests")

    methodology = report.get("methodology")
    expected_methodology = {
        "model_version",
        "frames_per_second",
        "seed_policy",
        "samples_per_loadout",
        "total_samples",
        "profile_source",
        "profile_sha256",
        "disclaimer",
    }
    if type(methodology) is not dict:
        violations.append("methodology: expected object")
    else:
        _check_exact_fields(methodology, expected_methodology, "methodology", violations)
        if methodology.get("model_version") != MODEL_VERSION:
            violations.append("methodology.model_version: unsupported value")
        if methodology.get("frames_per_second") != 60:
            violations.append("methodology.frames_per_second: expected 60")
        if methodology.get("seed_policy") != "canonical_20260901_through_20260930_exact":
            violations.append("methodology.seed_policy: expected the exact canonical 30-seed set")
        disclaimer = methodology.get("disclaimer")
        if type(disclaimer) is not str or "does not represent human playtest evidence" not in disclaimer:
            violations.append("methodology.disclaimer: missing synthetic evidence boundary")

    if report.get("weapons") != list(CANONICAL_WEAPONS):
        violations.append("weapons: expected canonical five-weapon order")
    if report.get("time_pairs") != [list(pair) for pair in TIME_PAIRS]:
        violations.append("time_pairs: expected six canonical unordered pairs")

    seeds = report.get("seeds")
    if type(seeds) is not list or seeds != list(CANONICAL_SEEDS):
        violations.append("seeds: expected exactly 30 canonical seeds")
    if type(methodology) is dict:
        if methodology.get("samples_per_loadout") != EXPECTED_SEED_COUNT:
            violations.append("methodology.samples_per_loadout: expected exactly 30")
        if methodology.get("total_samples") != EXPECTED_SAMPLE_COUNT:
            violations.append("methodology.total_samples: expected exactly 900")

    expected_sample_keys = [
        (weapon_id, time_pair, seed)
        for weapon_id in CANONICAL_WEAPONS
        for time_pair in TIME_PAIRS
        for seed in CANONICAL_SEEDS
    ]
    samples = report.get("samples")
    actual_sample_keys: list[tuple[str, tuple[str, ...], int]] = []
    samples_by_loadout: dict[tuple[str, tuple[str, ...]], list[dict[str, float]]] = {}
    samples_by_weapon: dict[str, list[dict[str, float]]] = {
        weapon_id: [] for weapon_id in CANONICAL_WEAPONS
    }
    if type(samples) is not list or len(samples) != EXPECTED_SAMPLE_COUNT:
        violations.append("samples: expected exactly 900 entries")
    if type(samples) is list:
        for index, sample in enumerate(samples):
            path = f"samples[{index}]"
            if type(sample) is not dict:
                violations.append(f"{path}: expected object")
                continue
            _check_exact_fields(sample, {"weapon_id", "time_pair", "seed", "metrics"}, path, violations)
            weapon_id = sample.get("weapon_id")
            time_pair = sample.get("time_pair")
            seed = sample.get("seed")
            valid_identity = (
                type(weapon_id) is str
                and weapon_id in CANONICAL_WEAPONS
                and type(time_pair) is list
                and tuple(time_pair) in TIME_PAIRS
                and all(type(value) is str for value in time_pair)
                and type(seed) is int
                and seed in CANONICAL_SEEDS
            )
            if not valid_identity:
                violations.append(f"{path}: invalid canonical weapon, time pair, or seed")
            else:
                sample_key = (weapon_id, tuple(time_pair), seed)
                actual_sample_keys.append(sample_key)
            metrics_violation_count = len(violations)
            _validate_metrics(sample.get("metrics"), f"{path}.metrics", violations)
            if valid_identity and len(violations) == metrics_violation_count:
                metrics = sample["metrics"]
                loadout_key = (weapon_id, tuple(time_pair))
                samples_by_loadout.setdefault(loadout_key, []).append(metrics)
                samples_by_weapon[weapon_id].append(metrics)
    if actual_sample_keys != expected_sample_keys:
        violations.append("samples: expected canonical weapon × time pair × seed order exactly once")

    loadouts = report.get("loadouts")
    expected_combinations = {
        (weapon_id, time_pair)
        for weapon_id in CANONICAL_WEAPONS
        for time_pair in TIME_PAIRS
    }
    actual_combinations: set[tuple[str, tuple[str, ...]]] = set()
    if type(loadouts) is not list or len(loadouts) != EXPECTED_LOADOUT_COUNT:
        violations.append("loadouts: expected exactly 30 entries")
    else:
        loadout_order: list[tuple[str, tuple[str, ...]]] = []
        for index, loadout in enumerate(loadouts):
            path = f"loadouts[{index}]"
            if type(loadout) is not dict:
                violations.append(f"{path}: expected object")
                continue
            _check_exact_fields(loadout, {"weapon_id", "time_pair", "sample_count", "metrics"}, path, violations)
            weapon_id = loadout.get("weapon_id")
            time_pair = loadout.get("time_pair")
            if type(weapon_id) is str and type(time_pair) is list and all(type(value) is str for value in time_pair):
                loadout_key = (weapon_id, tuple(time_pair))
                actual_combinations.add(loadout_key)
                loadout_order.append(loadout_key)
            else:
                violations.append(f"{path}: invalid weapon or time pair")
                loadout_key = None
            if loadout.get("sample_count") != EXPECTED_SEED_COUNT:
                violations.append(f"{path}.sample_count: expected exactly 30")
            _validate_metrics(loadout.get("metrics"), f"{path}.metrics", violations)
            detail_metrics = samples_by_loadout.get(loadout_key, []) if loadout_key is not None else []
            if len(detail_metrics) == EXPECTED_SEED_COUNT:
                if loadout.get("metrics") != _average_metrics(detail_metrics):
                    violations.append(f"{path}.metrics: must be recomputed from samples")
        expected_loadout_order = [
            (weapon_id, time_pair)
            for weapon_id in CANONICAL_WEAPONS
            for time_pair in TIME_PAIRS
        ]
        if loadout_order != expected_loadout_order:
            violations.append("loadouts: expected canonical order")
    if actual_combinations != expected_combinations:
        violations.append("loadouts: combinations must cover five weapons by six pairs exactly once")

    summaries = report.get("weapon_summaries")
    if type(summaries) is not list or len(summaries) != len(CANONICAL_WEAPONS):
        violations.append("weapon_summaries: expected exactly five entries")
    else:
        summary_ids: list[str] = []
        for index, summary in enumerate(summaries):
            path = f"weapon_summaries[{index}]"
            if type(summary) is not dict:
                violations.append(f"{path}: expected object")
                continue
            _check_exact_fields(summary, {"weapon_id", "sample_count", "metrics"}, path, violations)
            summary_ids.append(summary.get("weapon_id"))
            if summary.get("sample_count") != len(TIME_PAIRS) * EXPECTED_SEED_COUNT:
                violations.append(f"{path}.sample_count: expected exactly 180")
            _validate_metrics(summary.get("metrics"), f"{path}.metrics", violations)
            weapon_id = summary.get("weapon_id")
            detail_metrics = samples_by_weapon.get(weapon_id, []) if type(weapon_id) is str else []
            if len(detail_metrics) == len(TIME_PAIRS) * EXPECTED_SEED_COUNT:
                if summary.get("metrics") != _average_metrics(detail_metrics):
                    violations.append(f"{path}.metrics: must be recomputed from samples")
        if summary_ids != list(CANONICAL_WEAPONS):
            violations.append("weapon_summaries: expected canonical weapon order")

    digest = report.get("content_digest")
    if type(digest) is not str or len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        violations.append("content_digest: expected lowercase SHA-256")
    elif not _contains_non_finite(report) and digest != report_digest(report):
        violations.append("content_digest: report content mismatch")
    return violations


def _load_profiles() -> dict[str, dict[str, Any]]:
    parsed = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    if type(parsed) is not list:
        raise ValueError("weapon runtime profile catalog must be an array")
    profiles = {
        profile.get("id"): profile
        for profile in parsed
        if type(profile) is dict and type(profile.get("id")) is str
    }
    missing = sorted(set(PROFILE_IDS.values()) - set(profiles))
    if missing:
        raise ValueError("missing launch profiles: " + ", ".join(missing))
    return profiles


def _profile_model(profile: dict[str, Any]) -> dict[str, float]:
    payloads = {
        payload.get("payload_id"): payload
        for payload in profile.get("payloads", [])
        if type(payload) is dict
    }
    action_dps: list[float] = []
    burst_values: list[float] = []
    risks: list[float] = []
    starvation_values: list[float] = []
    area_values: list[float] = []
    status_values: list[float] = []
    resource_maximums = {
        resource.get("resource_id"): float(resource.get("maximum", 0.0))
        for resource in profile.get("resources", [])
        if type(resource) is dict
    }

    perfect_reload_value = 0.0
    staff_combination_frequency = 0.0
    gauntlets_combo_retention = 0.0
    for action in profile.get("actions", []):
        if type(action) is not dict:
            continue
        payload = payloads.get(action.get("payload_id"), {})
        parameters = payload.get("parameters", {}) if type(payload) is dict else {}
        if type(parameters) is not dict:
            parameters = {}
        damage = _damage_value(parameters)
        cycle_frames = _action_cycle_frames(action)
        cooldown_frames = max(0.0, float(action.get("cooldown_frames", 0) or 0))
        resource_pressure = _resource_pressure(action.get("resource_costs", {}), resource_maximums)
        if damage > 0.0:
            cadence_penalty = 1.0 + cooldown_frames / 600.0 + resource_pressure * 0.5
            action_dps.append((damage * 100.0) / (cycle_frames / 60.0) / cadence_penalty)
            burst_values.append(damage * 100.0)
        locked_frames = max(0.0, cycle_frames - float(action.get("cancel_from_frame", cycle_frames) or cycle_frames))
        risks.append(_clamp((float(action.get("windup_frames", 0)) + locked_frames) / cycle_frames))
        starvation_values.append(_clamp(resource_pressure))
        area_values.append(_area_value(parameters))
        status_values.append(_status_value(parameters, cycle_frames))

        if payload.get("kind") == "resource_action" and "perfect_fill" in parameters:
            normal_fill = max(1.0, float(parameters.get("normal_fill", 1.0)))
            fill_gain = (float(parameters.get("perfect_fill", normal_fill)) - normal_fill) / normal_fill
            recovery_gain = (
                float(parameters.get("total_frames", 0.0))
                - float(parameters.get("perfect_recovery_frames", 0.0))
            ) / max(1.0, float(parameters.get("total_frames", 1.0)))
            perfect_reload_value = max(0.0, (fill_gain + recovery_gain) * 100.0)
        combinations = parameters.get("combinations", [])
        if type(combinations) is list and combinations:
            staff_combination_frequency = _clamp(len(combinations) / 6.0)
        combo_gains = [
            float(item.get("combo_gain", 0.0))
            for item in [parameters]
            if type(item.get("combo_gain")) in (int, float)
        ]
        if combo_gains:
            gauntlets_combo_retention = max(
                gauntlets_combo_retention,
                _clamp((combo_gains[0] + 2.0) / (cycle_frames / 6.0 + 2.0)),
            )

    return {
        "dps": fmean(action_dps) if action_dps else 0.0,
        "risk_uptime": fmean(risks) if risks else 0.0,
        "starvation_rate": fmean(starvation_values) if starvation_values else 0.0,
        "burst_damage": max(burst_values, default=0.0),
        "area_coverage": max(area_values, default=0.0),
        "status_uptime": max(status_values, default=0.0),
        "perfect_reload_value": perfect_reload_value,
        "staff_combination_frequency": staff_combination_frequency,
        "gauntlets_combo_retention": gauntlets_combo_retention,
    }


def _simulate_sample(
    model: dict[str, float],
    weapon_id: str,
    time_pair: tuple[str, str],
    seed: int,
) -> dict[str, float]:
    factors = {metric: 1.0 for metric in METRIC_FIELDS}
    if "stop" in time_pair:
        factors.update({"dps": 1.05, "risk_uptime": 0.85, "burst_damage": 1.15, "status_uptime": 1.10})
    if "rewind" in time_pair:
        factors["risk_uptime"] *= 0.78
        factors["starvation_rate"] *= 0.90
        factors["gauntlets_combo_retention"] *= 1.10
    if "rift" in time_pair:
        factors["area_coverage"] *= 1.25
        factors["status_uptime"] *= 1.25
        factors["staff_combination_frequency"] *= 1.05
    if "accelerate" in time_pair:
        factors["dps"] *= 1.18
        factors["risk_uptime"] *= 1.12
        factors["starvation_rate"] *= 1.08
        factors["perfect_reload_value"] *= 1.12

    result: dict[str, float] = {}
    for metric in METRIC_FIELDS:
        base = model[metric]
        if base == 0.0:
            result[metric] = 0.0
            continue
        jitter = 0.96 + _stable_unit(seed, weapon_id, time_pair, metric) * 0.08
        value = base * factors[metric] * jitter
        if metric in RATIO_METRICS:
            value = _clamp(value)
        result[metric] = round(max(0.0, value), 6)
    return result


def _damage_value(parameters: dict[str, Any]) -> float:
    direct = _number(parameters.get("damage_multiplier"))
    tier_values = [
        _number(tier.get("damage_multiplier"))
        for tier in parameters.get("charge_tiers", [])
        if type(tier) is dict
    ]
    element_values = [
        _number(element.get("damage_multiplier"))
        for element in parameters.get("element_definitions", [])
        if type(element) is dict
    ]
    values = [value for value in [direct, *tier_values, *element_values] if value > 0.0]
    if not values:
        return 0.0
    base = fmean(values)
    count = max(
        1.0,
        _number(parameters.get("count")),
        _number(parameters.get("wave_count")) * max(1.0, _number(parameters.get("arrows_per_wave"))),
    )
    return base * math.sqrt(count)


def _action_cycle_frames(action: dict[str, Any]) -> float:
    frames = sum(
        max(0.0, _number(action.get(field)))
        for field in ("windup_frames", "active_frames", "recovery_frames")
    )
    hold = max(
        0.0,
        _number(action.get("hold_threshold_frames")),
        min(48.0, _number(action.get("maximum_hold_frames"))),
    )
    return max(1.0, frames + hold * 0.5)


def _resource_pressure(costs: Any, maximums: dict[str, float]) -> float:
    if type(costs) is not dict:
        return 0.0
    pressures = []
    for resource_id, raw_cost in costs.items():
        maximum = maximums.get(resource_id, 100.0 if resource_id == "time_energy" else 0.0)
        if maximum > 0.0:
            pressures.append(max(0.0, _number(raw_cost)) / maximum)
    return fmean(pressures) if pressures else 0.0


def _area_value(parameters: dict[str, Any]) -> float:
    candidates = [
        _number(parameters.get("radius_tiles")) / 5.0,
        _number(parameters.get("zone_radius_tiles")) / 5.0,
        _number(parameters.get("explosion_radius_tiles")) / 5.0,
        _number(parameters.get("radius_pixels")) / 320.0,
        _number(parameters.get("width_pixels")) / 160.0,
        _number(parameters.get("spread_degrees")) / 90.0,
        math.sqrt(max(0.0, _number(parameters.get("count")))) / 5.0,
    ]
    return _clamp(max(candidates, default=0.0))


def _status_value(parameters: dict[str, Any], cycle_frames: float) -> float:
    durations = [
        _number(value)
        for key, value in parameters.items()
        if key.endswith("duration_frames") and type(value) in (int, float)
    ]
    return _clamp(max(durations, default=0.0) / max(60.0, cycle_frames * 6.0))


def _average_metrics(samples: Iterable[dict[str, float]]) -> dict[str, float]:
    collected = list(samples)
    if not collected:
        return {metric: 0.0 for metric in METRIC_FIELDS}
    return {
        metric: round(fmean(sample[metric] for sample in collected), 6)
        for metric in METRIC_FIELDS
    }


def _stable_unit(seed: int, weapon_id: str, time_pair: tuple[str, str], metric: str) -> float:
    material = f"{MODEL_VERSION}|{seed}|{weapon_id}|{time_pair[0]}+{time_pair[1]}|{metric}".encode("utf-8")
    value = int.from_bytes(hashlib.sha256(material).digest()[:8], "big")
    return value / float((1 << 64) - 1)


def _validate_metrics(value: Any, path: str, violations: list[str]) -> None:
    if type(value) is not dict:
        violations.append(f"{path}: expected object")
        return
    _check_exact_fields(value, set(METRIC_FIELDS), path, violations)
    for metric in METRIC_FIELDS:
        raw_value = value.get(metric)
        if type(raw_value) is not float:
            violations.append(f"{path}.{metric}: expected float")
            continue
        if not math.isfinite(raw_value):
            violations.append(f"{path}.{metric}: expected finite value")
            continue
        if raw_value < 0.0:
            violations.append(f"{path}.{metric}: expected non-negative value")
        if metric in RATIO_METRICS and raw_value > 1.0:
            violations.append(f"{path}.{metric}: ratio exceeds one")


def _check_exact_fields(
    value: dict[str, Any],
    expected: set[str],
    path: str,
    violations: list[str],
) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing:
        violations.append(f"{path}: missing fields: {', '.join(missing)}")
    if unexpected:
        violations.append(f"{path}: unexpected fields: {', '.join(unexpected)}")


def _contains_non_finite(value: Any) -> bool:
    if type(value) is float:
        return not math.isfinite(value)
    if type(value) is dict:
        return any(_contains_non_finite(item) for item in value.values())
    if type(value) is list:
        return any(_contains_non_finite(item) for item in value)
    return False


def _number(value: Any) -> float:
    if type(value) not in (int, float):
        return 0.0
    result = float(value)
    return result if math.isfinite(result) else 0.0


def _clamp(value: float) -> float:
    return min(1.0, max(0.0, value))


def _exact_seed_count(raw_value: str) -> int:
    try:
        value = int(raw_value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("seeds must be an integer") from error
    if value != EXPECTED_SEED_COUNT:
        raise argparse.ArgumentTypeError(f"seeds must be exactly {EXPECTED_SEED_COUNT}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=_exact_seed_count, default=EXPECTED_SEED_COUNT)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    report = build_report(args.seeds)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, allow_nan=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "Wrote synthetic deterministic weapon simulation report "
        f"({report['methodology']['total_samples']} samples, digest {report['content_digest']}) to {args.output}"
    )
    print("This output is synthetic and is not human playtest evidence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
