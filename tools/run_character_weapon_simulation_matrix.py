#!/usr/bin/env python3
"""Build the deterministic P12 character, weapon, and time-pair report.

The report is synthetic model evidence. It is not gameplay telemetry and never
counts as human playtest evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import fmean
from typing import Any, Iterable

import run_weapon_simulation_matrix as weapon_simulation


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CHARACTER_PROFILE_PATH = (
    PROJECT_ROOT
    / "data"
    / "content_packs"
    / "base"
    / "content"
    / "character_runtime_profiles.json"
)
WEAPON_PROFILE_PATH = weapon_simulation.PROFILE_PATH
ACTIVE_PACK_PATH = PROJECT_ROOT / "data" / "content_packs" / "base" / "pack.json"

SCHEMA_VERSION = "2.0.0"
MODEL_VERSION = "p12g-character-weapon-profile-model-v2"
CANONICAL_CHARACTERS = (
    "wanderer",
    "time_guardian",
    "void_walker",
    "primordial_knight",
    "time_lord",
)
CHARACTER_PROFILE_IDS = {
    "wanderer": "wanderer_launch_v1",
    "time_guardian": "time_guardian_launch_v1",
    "void_walker": "void_walker_launch_v1",
    "primordial_knight": "primordial_knight_launch_v1",
    "time_lord": "time_lord_launch_v1",
}
CANONICAL_WEAPONS = weapon_simulation.CANONICAL_WEAPONS
TIME_PAIRS = weapon_simulation.TIME_PAIRS
CANONICAL_SEEDS = weapon_simulation.CANONICAL_SEEDS
EXPECTED_SEED_COUNT = len(CANONICAL_SEEDS)
EXPECTED_LOADOUT_COUNT = len(CANONICAL_CHARACTERS) * len(CANONICAL_WEAPONS) * len(TIME_PAIRS)
EXPECTED_SAMPLE_COUNT = EXPECTED_LOADOUT_COUNT * EXPECTED_SEED_COUNT
TALENT_SUBSET_CASES = len(CANONICAL_CHARACTERS) * 8

P11_METRIC_FIELDS = weapon_simulation.METRIC_FIELDS
P12_METRIC_FIELDS = (
    "signature_resource_efficiency",
    "mastery_conversion_rate",
    "damage_prevention_value",
    "void_debt_generated",
    "void_debt_converted",
    "planar_echo_value",
    "codex_pair_completion_frequency",
    "character_skill_use_rate",
    "character_skill_rejection_rate",
)
METRIC_FIELDS = P11_METRIC_FIELDS + P12_METRIC_FIELDS
RATIO_METRICS = set(weapon_simulation.RATIO_METRICS) | {
    "signature_resource_efficiency",
    "mastery_conversion_rate",
    "damage_prevention_value",
    "codex_pair_completion_frequency",
    "character_skill_use_rate",
    "character_skill_rejection_rate",
}


def build_report(seed_count: int = EXPECTED_SEED_COUNT) -> dict[str, Any]:
    if seed_count != EXPECTED_SEED_COUNT:
        raise ValueError(f"seed_count must be exactly {EXPECTED_SEED_COUNT}")

    profiles = _load_character_profiles()
    base_report = weapon_simulation.build_report(seed_count=seed_count)
    base_samples = {
        (sample["weapon_id"], tuple(sample["time_pair"]), sample["seed"]): sample["metrics"]
        for sample in base_report["samples"]
    }

    samples: list[dict[str, Any]] = []
    grouped_loadouts: dict[tuple[str, str, tuple[str, str]], list[dict[str, float]]] = {}
    grouped_characters: dict[str, list[dict[str, float]]] = {
        character_id: [] for character_id in CANONICAL_CHARACTERS
    }
    grouped_weapons: dict[str, list[dict[str, float]]] = {
        weapon_id: [] for weapon_id in CANONICAL_WEAPONS
    }
    grouped_character_weapons: dict[tuple[str, str], list[dict[str, float]]] = {}

    for character_id in CANONICAL_CHARACTERS:
        profile = profiles[CHARACTER_PROFILE_IDS[character_id]]
        for weapon_id in CANONICAL_WEAPONS:
            for time_pair in TIME_PAIRS:
                loadout_key = (character_id, weapon_id, time_pair)
                loadout_metrics: list[dict[str, float]] = []
                for seed in CANONICAL_SEEDS:
                    base_metrics = base_samples[(weapon_id, time_pair, seed)]
                    metrics = _simulate_character_sample(
                        base_metrics,
                        profile,
                        character_id,
                        weapon_id,
                        time_pair,
                        seed,
                    )
                    samples.append(
                        {
                            "character_id": character_id,
                            "weapon_id": weapon_id,
                            "time_pair": list(time_pair),
                            "seed": seed,
                            "metrics": metrics,
                        }
                    )
                    loadout_metrics.append(metrics)
                    grouped_characters[character_id].append(metrics)
                    grouped_weapons[weapon_id].append(metrics)
                    grouped_character_weapons.setdefault((character_id, weapon_id), []).append(metrics)
                grouped_loadouts[loadout_key] = loadout_metrics

    loadouts = [
        {
            "character_id": character_id,
            "weapon_id": weapon_id,
            "time_pair": list(time_pair),
            "sample_count": EXPECTED_SEED_COUNT,
            "metrics": _average_metrics(grouped_loadouts[(character_id, weapon_id, time_pair)]),
        }
        for character_id in CANONICAL_CHARACTERS
        for weapon_id in CANONICAL_WEAPONS
        for time_pair in TIME_PAIRS
    ]
    character_summaries = [
        {
            "character_id": character_id,
            "sample_count": len(grouped_characters[character_id]),
            "metrics": _average_metrics(grouped_characters[character_id]),
        }
        for character_id in CANONICAL_CHARACTERS
    ]
    weapon_summaries = [
        {
            "weapon_id": weapon_id,
            "sample_count": len(grouped_weapons[weapon_id]),
            "metrics": _average_metrics(grouped_weapons[weapon_id]),
        }
        for weapon_id in CANONICAL_WEAPONS
    ]
    character_weapon_summaries = [
        {
            "character_id": character_id,
            "weapon_id": weapon_id,
            "sample_count": len(grouped_character_weapons[(character_id, weapon_id)]),
            "metrics": _average_metrics(grouped_character_weapons[(character_id, weapon_id)]),
        }
        for character_id in CANONICAL_CHARACTERS
        for weapon_id in CANONICAL_WEAPONS
    ]

    report: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "report_type": "character_weapon_simulation_matrix",
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
            "character_profile_source": str(CHARACTER_PROFILE_PATH.relative_to(PROJECT_ROOT)),
            "character_profile_sha256": _file_digest(CHARACTER_PROFILE_PATH),
            "weapon_profile_source": str(WEAPON_PROFILE_PATH.relative_to(PROJECT_ROOT)),
            "weapon_profile_sha256": _file_digest(WEAPON_PROFILE_PATH),
            "active_pack_source": str(ACTIVE_PACK_PATH.relative_to(PROJECT_ROOT)),
            "active_pack_sha256": _file_digest(ACTIVE_PACK_PATH),
            "disclaimer": (
                "Synthetic deterministic profile simulation; this does not represent human playtest evidence."
            ),
        },
        "characters": list(CANONICAL_CHARACTERS),
        "weapons": list(CANONICAL_WEAPONS),
        "time_pairs": [list(pair) for pair in TIME_PAIRS],
        "seeds": list(CANONICAL_SEEDS),
        "talent_subset_cases": TALENT_SUBSET_CASES,
        "samples": samples,
        "loadouts": loadouts,
        "character_summaries": character_summaries,
        "weapon_summaries": weapon_summaries,
        "character_weapon_summaries": character_weapon_summaries,
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

    _check_exact_fields(
        report,
        {
            "schema_version",
            "report_type",
            "evidence",
            "methodology",
            "characters",
            "weapons",
            "time_pairs",
            "seeds",
            "talent_subset_cases",
            "samples",
            "loadouts",
            "character_summaries",
            "weapon_summaries",
            "character_weapon_summaries",
            "content_digest",
        },
        "root",
        violations,
    )
    if report.get("schema_version") != SCHEMA_VERSION:
        violations.append("schema_version: unsupported value")
    if report.get("report_type") != "character_weapon_simulation_matrix":
        violations.append("report_type: unsupported value")
    if report.get("evidence") != {
        "source": "synthetic",
        "synthetic": True,
        "human_playtests": 0,
        "claim_boundary": "deterministic_model_observation_only",
    }:
        violations.append("evidence: report must remain synthetic with zero human playtests")

    _validate_methodology(report.get("methodology"), violations)
    if report.get("characters") != list(CANONICAL_CHARACTERS):
        violations.append("characters: expected canonical five-character order")
    if report.get("weapons") != list(CANONICAL_WEAPONS):
        violations.append("weapons: expected canonical five-weapon order")
    if report.get("time_pairs") != [list(pair) for pair in TIME_PAIRS]:
        violations.append("time_pairs: expected six canonical unordered pairs")
    if report.get("seeds") != list(CANONICAL_SEEDS):
        violations.append("seeds: expected exactly 30 canonical seeds")
    if report.get("talent_subset_cases") != TALENT_SUBSET_CASES:
        violations.append("talent_subset_cases: expected exactly 40")

    grouped = _validate_samples(report.get("samples"), violations)
    _validate_loadouts(report.get("loadouts"), grouped["loadouts"], violations)
    _validate_summary_collection(
        report.get("character_summaries"),
        "character_summaries",
        ("character_id",),
        [(character_id,) for character_id in CANONICAL_CHARACTERS],
        grouped["characters"],
        violations,
    )
    _validate_summary_collection(
        report.get("weapon_summaries"),
        "weapon_summaries",
        ("weapon_id",),
        [(weapon_id,) for weapon_id in CANONICAL_WEAPONS],
        grouped["weapons"],
        violations,
    )
    _validate_summary_collection(
        report.get("character_weapon_summaries"),
        "character_weapon_summaries",
        ("character_id", "weapon_id"),
        [
            (character_id, weapon_id)
            for character_id in CANONICAL_CHARACTERS
            for weapon_id in CANONICAL_WEAPONS
        ],
        grouped["character_weapons"],
        violations,
    )

    digest = report.get("content_digest")
    if type(digest) is not str or len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
        violations.append("content_digest: expected lowercase SHA-256")
    elif not _contains_non_finite(report) and digest != report_digest(report):
        violations.append("content_digest: report content mismatch")
    return violations


def _validate_methodology(value: Any, violations: list[str]) -> None:
    if type(value) is not dict:
        violations.append("methodology: expected object")
        return
    _check_exact_fields(
        value,
        {
            "model_version",
            "frames_per_second",
            "seed_policy",
            "samples_per_loadout",
            "total_samples",
            "character_profile_source",
            "character_profile_sha256",
            "weapon_profile_source",
            "weapon_profile_sha256",
            "active_pack_source",
            "active_pack_sha256",
            "disclaimer",
        },
        "methodology",
        violations,
    )
    expected = {
        "model_version": MODEL_VERSION,
        "frames_per_second": 60,
        "seed_policy": "canonical_20260901_through_20260930_exact",
        "samples_per_loadout": EXPECTED_SEED_COUNT,
        "total_samples": EXPECTED_SAMPLE_COUNT,
        "character_profile_source": str(CHARACTER_PROFILE_PATH.relative_to(PROJECT_ROOT)),
        "character_profile_sha256": _file_digest(CHARACTER_PROFILE_PATH),
        "weapon_profile_source": str(WEAPON_PROFILE_PATH.relative_to(PROJECT_ROOT)),
        "weapon_profile_sha256": _file_digest(WEAPON_PROFILE_PATH),
        "active_pack_source": str(ACTIVE_PACK_PATH.relative_to(PROJECT_ROOT)),
        "active_pack_sha256": _file_digest(ACTIVE_PACK_PATH),
    }
    for key, expected_value in expected.items():
        if value.get(key) != expected_value:
            violations.append(f"methodology.{key}: does not match authoritative input")
    disclaimer = value.get("disclaimer")
    if type(disclaimer) is not str or "does not represent human playtest evidence" not in disclaimer:
        violations.append("methodology.disclaimer: missing synthetic evidence boundary")


def _validate_samples(value: Any, violations: list[str]) -> dict[str, dict[Any, list[dict[str, float]]]]:
    grouped: dict[str, dict[Any, list[dict[str, float]]]] = {
        "loadouts": {},
        "characters": {},
        "weapons": {},
        "character_weapons": {},
    }
    if type(value) is not list or len(value) != EXPECTED_SAMPLE_COUNT:
        violations.append("samples: expected exactly 4500 entries")
    if type(value) is not list:
        return grouped

    expected_identities = [
        (character_id, weapon_id, time_pair, seed)
        for character_id in CANONICAL_CHARACTERS
        for weapon_id in CANONICAL_WEAPONS
        for time_pair in TIME_PAIRS
        for seed in CANONICAL_SEEDS
    ]
    actual_identities: list[tuple[str, str, tuple[str, ...], int]] = []
    for index, sample in enumerate(value):
        path = f"samples[{index}]"
        if type(sample) is not dict:
            violations.append(f"{path}: expected object")
            continue
        _check_exact_fields(
            sample,
            {"character_id", "weapon_id", "time_pair", "seed", "metrics"},
            path,
            violations,
        )
        character_id = sample.get("character_id")
        weapon_id = sample.get("weapon_id")
        time_pair = sample.get("time_pair")
        seed = sample.get("seed")
        identity_valid = (
            type(character_id) is str
            and character_id in CANONICAL_CHARACTERS
            and type(weapon_id) is str
            and weapon_id in CANONICAL_WEAPONS
            and type(time_pair) is list
            and tuple(time_pair) in TIME_PAIRS
            and type(seed) is int
            and seed in CANONICAL_SEEDS
        )
        before = len(violations)
        _validate_metrics(sample.get("metrics"), f"{path}.metrics", violations)
        if not identity_valid:
            violations.append(f"{path}: invalid canonical identity")
            continue
        pair = tuple(time_pair)
        actual_identities.append((character_id, weapon_id, pair, seed))
        if len(violations) == before:
            metrics = sample["metrics"]
            grouped["loadouts"].setdefault((character_id, weapon_id, pair), []).append(metrics)
            grouped["characters"].setdefault((character_id,), []).append(metrics)
            grouped["weapons"].setdefault((weapon_id,), []).append(metrics)
            grouped["character_weapons"].setdefault((character_id, weapon_id), []).append(metrics)
    if actual_identities != expected_identities:
        violations.append("samples: expected canonical character × weapon × pair × seed order exactly once")
    return grouped


def _validate_loadouts(
    value: Any,
    grouped: dict[Any, list[dict[str, float]]],
    violations: list[str],
) -> None:
    if type(value) is not list or len(value) != EXPECTED_LOADOUT_COUNT:
        violations.append("loadouts: expected exactly 150 entries")
    if type(value) is not list:
        return
    expected_keys = [
        (character_id, weapon_id, time_pair)
        for character_id in CANONICAL_CHARACTERS
        for weapon_id in CANONICAL_WEAPONS
        for time_pair in TIME_PAIRS
    ]
    actual_keys: list[tuple[Any, Any, Any]] = []
    for index, entry in enumerate(value):
        path = f"loadouts[{index}]"
        if type(entry) is not dict:
            violations.append(f"{path}: expected object")
            continue
        _check_exact_fields(
            entry,
            {"character_id", "weapon_id", "time_pair", "sample_count", "metrics"},
            path,
            violations,
        )
        time_pair = entry.get("time_pair")
        key = (
            entry.get("character_id"),
            entry.get("weapon_id"),
            tuple(time_pair) if type(time_pair) is list else (),
        )
        actual_keys.append(key)
        if entry.get("sample_count") != EXPECTED_SEED_COUNT:
            violations.append(f"{path}.sample_count: expected exactly 30")
        _validate_metrics(entry.get("metrics"), f"{path}.metrics", violations)
        details = grouped.get(key, [])
        if len(details) == EXPECTED_SEED_COUNT and entry.get("metrics") != _average_metrics(details):
            violations.append(f"{path}.metrics: must be recomputed from samples")
    if actual_keys != expected_keys:
        violations.append("loadouts: expected canonical order")


def _validate_summary_collection(
    value: Any,
    collection_name: str,
    identity_fields: tuple[str, ...],
    expected_keys: list[tuple[Any, ...]],
    grouped: dict[Any, list[dict[str, float]]],
    violations: list[str],
) -> None:
    if type(value) is not list or len(value) != len(expected_keys):
        violations.append(f"{collection_name}: expected exactly {len(expected_keys)} entries")
    if type(value) is not list:
        return
    actual_keys: list[tuple[Any, ...]] = []
    for index, entry in enumerate(value):
        path = f"{collection_name}[{index}]"
        if type(entry) is not dict:
            violations.append(f"{path}: expected object")
            continue
        _check_exact_fields(entry, set(identity_fields) | {"sample_count", "metrics"}, path, violations)
        key = tuple(entry.get(field) for field in identity_fields)
        actual_keys.append(key)
        details = grouped.get(key, [])
        if entry.get("sample_count") != len(details):
            violations.append(f"{path}.sample_count: must match samples")
        _validate_metrics(entry.get("metrics"), f"{path}.metrics", violations)
        if details and entry.get("metrics") != _average_metrics(details):
            violations.append(f"{path}.metrics: must be recomputed from samples")
    if actual_keys != expected_keys:
        violations.append(f"{collection_name}: expected canonical order")


def _load_character_profiles() -> dict[str, dict[str, Any]]:
    parsed = json.loads(CHARACTER_PROFILE_PATH.read_text(encoding="utf-8"))
    if type(parsed) is not list:
        raise ValueError("character runtime profile catalog must be an array")
    profiles = {
        profile.get("id"): profile
        for profile in parsed
        if type(profile) is dict and type(profile.get("id")) is str
    }
    missing = sorted(set(CHARACTER_PROFILE_IDS.values()) - set(profiles))
    if missing:
        raise ValueError("missing launch character profiles: " + ", ".join(missing))
    for character_id, profile_id in CHARACTER_PROFILE_IDS.items():
        if profiles[profile_id].get("character_id") != character_id:
            raise ValueError(f"character profile {profile_id} has mismatched character_id")
        availability = profiles[profile_id].get("availability", [])
        if "LAUNCH" not in availability:
            raise ValueError(f"character profile {profile_id} is not available at LAUNCH")
    return profiles


def _simulate_character_sample(
    base_metrics: dict[str, float],
    profile: dict[str, Any],
    character_id: str,
    weapon_id: str,
    time_pair: tuple[str, str],
    seed: int,
) -> dict[str, float]:
    stats = profile["base_stats"]
    resource = profile["resource"]
    skill = profile["character_skill"]
    passive = profile["passive"]
    attack_scale = float(stats["attack"]) / 30.0
    speed_scale = float(stats["attack_speed"])
    defense_ratio = min(0.45, max(0.0, float(stats["defense"]) / 100.0))
    energy_capacity = max(1.0, float(stats["time_energy_max"]))
    energy_regen = max(0.0, float(stats["time_energy_regen"]))
    jitter = 0.97 + _stable_unit(seed, character_id, weapon_id, time_pair, "character") * 0.06

    result = dict(base_metrics)
    result["dps"] = round(result["dps"] * attack_scale * speed_scale * jitter, 6)
    result["burst_damage"] = round(result["burst_damage"] * attack_scale * jitter, 6)
    result["risk_uptime"] = round(_clamp(result["risk_uptime"] * (1.0 - defense_ratio)), 6)
    result["starvation_rate"] = round(
        _clamp(result["starvation_rate"] * (100.0 / energy_capacity) * (1.0 - min(0.3, energy_regen / 20.0))),
        6,
    )

    resource_maximum = max(0.0, float(resource.get("maximum", 0.0)))
    gain_cap = max(0.0, float(resource.get("gain_cap_per_action", 0.0)))
    signature_efficiency = 0.0 if resource_maximum == 0.0 else _clamp((gain_cap + 1.0) / max(2.0, resource_maximum))
    mastery_conversion = {
        "wanderer": 0.78,
        "time_guardian": 0.70,
        "void_walker": 0.74,
        "primordial_knight": 0.66,
        "time_lord": 0.72,
    }[character_id]
    mastery_conversion *= 0.96 + _stable_unit(seed, character_id, weapon_id, time_pair, "mastery") * 0.08

    damage_prevention = 0.0
    if character_id == "time_guardian":
        damage_prevention = float(passive["parameters"].get("damage_reduction", 0.0))
    elif character_id == "primordial_knight":
        damage_prevention = max(
            defense_ratio,
            float(passive["parameters"].get("armor_reduction", 0.0)),
        )

    void_debt_generated = 0.0
    void_debt_converted = 0.0
    if character_id == "void_walker":
        parameters = passive["parameters"]
        void_debt_generated = round(
            float(parameters.get("corruption_threshold", 60.0))
            * (0.72 + _stable_unit(seed, character_id, weapon_id, time_pair, "debt") * 0.28),
            6,
        )
        void_debt_converted = round(
            min(float(parameters.get("conversion_cap", 20.0)), void_debt_generated * 0.28),
            6,
        )

    planar_echo_value = 0.0
    if character_id == "primordial_knight":
        planar_echo_value = round(
            float(stats["attack"])
            * float(passive["parameters"].get("echo_multiplier", 0.0))
            * (1.25 if "rift" in time_pair else 1.0),
            6,
        )

    codex_pair_frequency = 0.0
    if character_id == "time_lord":
        codex_pair_frequency = _clamp(
            0.52 + (0.08 if "accelerate" in time_pair else 0.0) + (0.06 if "stop" in time_pair else 0.0)
        )

    cooldown = max(1.0, float(skill.get("cooldown_frames", 1.0)))
    energy_cost = max(0.0, float(skill.get("energy_cost", 0.0)))
    skill_use = _clamp((600.0 / cooldown) * (1.0 - min(0.8, energy_cost / energy_capacity)) / 4.0)
    skill_rejection = _clamp(0.04 + energy_cost / energy_capacity * 0.28 + result["risk_uptime"] * 0.08)

    result.update(
        {
            "signature_resource_efficiency": round(signature_efficiency, 6),
            "mastery_conversion_rate": round(_clamp(mastery_conversion), 6),
            "damage_prevention_value": round(_clamp(damage_prevention), 6),
            "void_debt_generated": void_debt_generated,
            "void_debt_converted": void_debt_converted,
            "planar_echo_value": planar_echo_value,
            "codex_pair_completion_frequency": round(codex_pair_frequency, 6),
            "character_skill_use_rate": round(skill_use, 6),
            "character_skill_rejection_rate": round(skill_rejection, 6),
        }
    )
    return {field: float(result[field]) for field in METRIC_FIELDS}


def _average_metrics(samples: Iterable[dict[str, float]]) -> dict[str, float]:
    collected = list(samples)
    if not collected:
        return {metric: 0.0 for metric in METRIC_FIELDS}
    return {
        metric: round(fmean(sample[metric] for sample in collected), 6)
        for metric in METRIC_FIELDS
    }


def _validate_metrics(value: Any, path: str, violations: list[str]) -> None:
    if type(value) is not dict:
        violations.append(f"{path}: expected object")
        return
    _check_exact_fields(value, set(METRIC_FIELDS), path, violations)
    for metric in METRIC_FIELDS:
        raw = value.get(metric)
        if type(raw) is not float:
            violations.append(f"{path}.{metric}: expected float")
            continue
        if not math.isfinite(raw):
            violations.append(f"{path}.{metric}: expected finite value")
            continue
        if raw < 0.0:
            violations.append(f"{path}.{metric}: expected non-negative value")
        if metric in RATIO_METRICS and raw > 1.0:
            violations.append(f"{path}.{metric}: ratio exceeds one")


def _check_exact_fields(value: dict[str, Any], expected: set[str], path: str, violations: list[str]) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing:
        violations.append(f"{path}: missing fields: {', '.join(missing)}")
    if unexpected:
        violations.append(f"{path}: unexpected fields: {', '.join(unexpected)}")


def _file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _stable_unit(
    seed: int,
    character_id: str,
    weapon_id: str,
    time_pair: tuple[str, str],
    channel: str,
) -> float:
    material = (
        f"{MODEL_VERSION}|{seed}|{character_id}|{weapon_id}|"
        f"{time_pair[0]}+{time_pair[1]}|{channel}"
    ).encode("utf-8")
    value = int.from_bytes(hashlib.sha256(material).digest()[:8], "big")
    return value / float((1 << 64) - 1)


def _contains_non_finite(value: Any) -> bool:
    if type(value) is float:
        return not math.isfinite(value)
    if type(value) is dict:
        return any(_contains_non_finite(item) for item in value.values())
    if type(value) is list:
        return any(_contains_non_finite(item) for item in value)
    return False


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

    report = build_report(seed_count=args.seeds)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, allow_nan=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "Wrote synthetic deterministic character/weapon simulation report "
        f"({report['methodology']['total_samples']} samples, digest {report['content_digest']}) "
        f"to {args.output}"
    )
    print("This output is synthetic and is not human playtest evidence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
