#!/usr/bin/env python3
"""Build deterministic synthetic P13B Launch-pool formation evidence.

This tool models content availability and build formation only. Its output is
never human playtest evidence and cannot satisfy the M1 external-playtest gate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable, Mapping


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = PROJECT_ROOT / "data" / "content" / "launch_pool_catalog.json"
BASE_CONTENT_ROOT = PROJECT_ROOT / "data" / "content_packs" / "base" / "content"
ITEMS_PATH = BASE_CONTENT_ROOT / "items.json"
BLESSINGS_PATH = BASE_CONTENT_ROOT / "blessings.json"
CURSES_PATH = BASE_CONTENT_ROOT / "curses.json"
TALENTS_PATH = BASE_CONTENT_ROOT / "talents.json"
ARCHETYPES_PATH = BASE_CONTENT_ROOT / "archetype_profiles.json"
EFFECT_CATALOG_PATH = PROJECT_ROOT / "data" / "content" / "effect_catalog.json"
CHARACTERS_PATH = BASE_CONTENT_ROOT / "characters.json"
CHARACTER_PROFILES_PATH = BASE_CONTENT_ROOT / "character_runtime_profiles.json"
WEAPONS_PATH = BASE_CONTENT_ROOT / "weapons.json"
WEAPON_PROFILES_PATH = BASE_CONTENT_ROOT / "weapon_runtime_profiles.json"
TIME_ABILITIES_PATH = BASE_CONTENT_ROOT / "time_abilities.json"

SCHEMA_VERSION = "2.0.0"
REPORT_TYPE = "launch_pool_formation"
CANONICAL_ARCHETYPES = (
    "freeze_burst",
    "rewind_echo",
    "rift_trap",
    "accelerated_combo",
    "low_hp_void",
    "perfect_guard",
    "piercing_barrage",
    "echo_legion",
)
CANONICAL_SEEDS = tuple(range(20260901, 20260931))
CANONICAL_CHARACTERS = (
    "wanderer",
    "time_guardian",
    "void_walker",
    "primordial_knight",
    "time_lord",
)
CANONICAL_WEAPONS = ("sword", "bow", "gun", "staff", "gauntlets")
CANONICAL_TIME_ABILITIES = ("stop", "rewind", "rift", "accelerate")
CANONICAL_TIME_PAIRS = (
    ("stop", "rewind"),
    ("stop", "rift"),
    ("stop", "accelerate"),
    ("rewind", "rift"),
    ("rewind", "accelerate"),
    ("rift", "accelerate"),
)
EXPECTED_SEED_COUNT = len(CANONICAL_SEEDS)
EXPECTED_COUNTS = {
    "items": 50,
    "passive_items": 42,
    "active_items": 8,
    "blessings": 28,
    "curses": 18,
    "talents": 15,
}
FORMATION_REQUIREMENTS = {"starters": 3, "payoffs": 2, "risks": 1}
EVIDENCE = {
    "source": "synthetic",
    "synthetic": True,
    "human_playtests": 0,
    "claim_boundary": "deterministic_content_formation_only",
}
ROOT_FIELDS = {
    "schema_version",
    "report_type",
    "evidence",
    "methodology",
    "content_counts",
    "content_digests",
    "archetypes",
    "seeds",
    "samples",
    "route_summaries",
    "content_digest",
}
SAMPLE_FIELDS = {
    "archetype_id",
    "seed",
    "character_id",
    "weapon_id",
    "time_ability_ids",
    "formation_success",
    "failure_reasons",
    "selected",
    "option_exposure",
    "effect_execution_count",
    "effect_execution_digest",
    "effect_runtime_domains",
    "active_usage_count",
    "curse_tradeoff_count",
}
SELECTED_FIELDS = {"starters", "payoffs", "risks", "utility", "talent"}
EXPOSURE_FIELDS = {"item", "blessing", "curse", "talent", "active"}
SUMMARY_FIELDS = {
    "archetype_id",
    "sample_count",
    "starter_pool_count",
    "payoff_pool_count",
    "risk_pool_count",
    "formation_success_count",
    "failure_reasons",
    "option_exposure",
    "effect_execution_count",
    "active_usage_count",
    "curse_tradeoff_count",
}
COMPATIBILITY_FIELDS = {
    "archetype_ids",
    "character_ids",
    "weapon_ids",
    "time_ability_ids",
}
ACTIVE_HANDLER_IDS = {
    "absolute_zero",
    "paradox_beacon",
    "gravity_snare",
    "redline_injector",
    "blood_price",
    "aegis_reversal",
    "railshot",
    "army_of_yesterday",
}
TIME_EFFECT_PREFIXES = {
    "time_stop_": "stop",
    "rewind_": "rewind",
    "time_rift_": "rift",
    "time_accelerate_": "accelerate",
}


def build_report(seed_count: int = EXPECTED_SEED_COUNT) -> dict[str, Any]:
    if seed_count != EXPECTED_SEED_COUNT:
        raise ValueError(f"seed_count must be exactly {EXPECTED_SEED_COUNT}")

    context = _load_simulation_context()
    catalog = context["catalog"]
    live = context["live"]
    rows_by_id = context["rows_by_id"]
    effect_catalog = context["effect_catalog"]
    loadouts = context["loadouts"]

    content_counts = {
        "items": len(live["item"]),
        "passive_items": sum(
            1 for row in live["item"] if row.get("item_mode") == "passive"
        ),
        "active_items": sum(
            1 for row in live["item"] if row.get("item_mode") == "active"
        ),
        "blessings": len(live["blessing"]),
        "curses": len(live["curse"]),
        "talents": len(live["talent"]),
    }
    if content_counts != EXPECTED_COUNTS:
        raise ValueError(f"live content counts drifted: {content_counts}")

    source_paths = context["source_paths"]
    content_digests = {key: _file_digest(path) for key, path in source_paths.items()}
    content_digests["combined"] = _canonical_digest(content_digests)

    catalog_groups = context["catalog_groups"]
    utilities = [
        (category, row)
        for category in ("item", "blessing")
        for row in catalog_groups[category]
        if str(row.get("archetype", "")) == ""
    ]

    samples: list[dict[str, Any]] = []
    pool_counts: dict[str, tuple[int, int, int]] = {}
    for route_index, archetype_id in enumerate(CANONICAL_ARCHETYPES):
        starters = _route_rows(catalog_groups, archetype_id, "starter")
        payoffs = _route_rows(catalog_groups, archetype_id, "payoff")
        risks = _route_rows(catalog_groups, archetype_id, "risk")
        pool_counts[archetype_id] = (len(starters), len(payoffs), len(risks))
        for seed_index, seed in enumerate(CANONICAL_SEEDS):
            formation = _select_compatible_formation(
                archetype_id=archetype_id,
                seed=seed,
                route_index=route_index,
                seed_index=seed_index,
                loadouts=loadouts,
                starters=starters,
                payoffs=payoffs,
                risks=risks,
                utilities=utilities,
                talents=[("talent", row) for row in catalog_groups["talent"]],
                rows_by_id=rows_by_id,
                effect_catalog=effect_catalog,
            )
            if formation is None:
                raise ValueError(
                    f"{archetype_id}:{seed}: no compatible character/weapon/time formation"
                )
            loadout = formation["loadout"]
            chosen_starters = formation["starters"]
            chosen_payoffs = formation["payoffs"]
            chosen_risks = formation["risks"]
            chosen_utility = formation["utility"]
            chosen_talent = formation["talent"]
            chosen = (
                chosen_starters
                + chosen_payoffs
                + chosen_risks
                + chosen_utility
                + chosen_talent
            )
            selected = {
                "starters": _row_ids(chosen_starters),
                "payoffs": _row_ids(chosen_payoffs),
                "risks": _row_ids(chosen_risks),
                "utility": _row_ids(chosen_utility),
                "talent": _row_ids(chosen_talent),
            }
            evidence = _selection_evidence(
                archetype_id,
                selected,
                loadout,
                context,
            )
            samples.append(
                {
                    "archetype_id": archetype_id,
                    "seed": seed,
                    "character_id": loadout["character_id"],
                    "weapon_id": loadout["weapon_id"],
                    "time_ability_ids": list(loadout["time_ability_ids"]),
                    "formation_success": not evidence["failures"],
                    "failure_reasons": evidence["failures"],
                    "selected": selected,
                    "option_exposure": evidence["option_exposure"],
                    "effect_execution_count": evidence["effect_execution_count"],
                    "effect_execution_digest": evidence["effect_execution_digest"],
                    "effect_runtime_domains": evidence["effect_runtime_domains"],
                    "active_usage_count": evidence["active_usage_count"],
                    "curse_tradeoff_count": evidence["curse_tradeoff_count"],
                }
            )

    route_summaries = _summaries_from_samples(samples, pool_counts)
    report: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "report_type": REPORT_TYPE,
        "evidence": EVIDENCE.copy(),
        "methodology": {
            "model_version": "p13b-launch-pool-formation-v2",
            "seed_policy": "canonical_20260901_through_20260930_exact",
            "samples_per_archetype": EXPECTED_SEED_COUNT,
            "total_samples": len(CANONICAL_ARCHETYPES) * EXPECTED_SEED_COUNT,
            "formation_requirements": FORMATION_REQUIREMENTS.copy(),
            "loadout_policy": (
                "canonical_5x5x6_launch_loadouts_with_definition_compatibility"
            ),
            "effect_execution_model": (
                "bounded_effect_catalog_dry_run_with_active_handler_receipts"
            ),
            "sources": {
                key: str(path.relative_to(PROJECT_ROOT))
                for key, path in source_paths.items()
            },
            "disclaimer": (
                "Synthetic deterministic content-formation evidence; not human playtest data."
            ),
        },
        "content_counts": content_counts,
        "content_digests": content_digests,
        "archetypes": list(CANONICAL_ARCHETYPES),
        "seeds": list(CANONICAL_SEEDS),
        "samples": samples,
        "route_summaries": route_summaries,
    }
    report["content_digest"] = report_digest(report)
    violations = validate_report(report)
    if violations:
        raise ValueError("generated report violates its contract: " + "; ".join(violations))
    return report


def report_digest(report: Mapping[str, Any]) -> str:
    payload = {key: value for key, value in report.items() if key != "content_digest"}
    return _canonical_digest(payload)


def validate_report(report: Any) -> list[str]:
    violations: list[str] = []
    try:
        context: dict[str, Any] | None = _load_simulation_context()
    except ValueError as exc:
        context = None
        violations.append(f"canonical_content: {exc}")
    if type(report) is not dict:
        return ["root: expected object"]
    _check_exact_fields(report, ROOT_FIELDS, "root", violations)
    if report.get("schema_version") != SCHEMA_VERSION:
        violations.append("schema_version: unsupported value")
    if report.get("report_type") != REPORT_TYPE:
        violations.append("report_type: unsupported value")
    if report.get("evidence") != EVIDENCE:
        violations.append("evidence: report must remain synthetic with zero human playtests")
    if report.get("content_counts") != EXPECTED_COUNTS:
        violations.append("content_counts: exact 50/42/8/28/18/15 counts required")
    if report.get("archetypes") != list(CANONICAL_ARCHETYPES):
        violations.append("archetypes: canonical order required")
    if report.get("seeds") != list(CANONICAL_SEEDS):
        violations.append("seeds: expected exactly 30 canonical seeds")

    methodology = report.get("methodology")
    if not isinstance(methodology, dict):
        violations.append("methodology: expected object")
    else:
        if methodology.get("seed_policy") != "canonical_20260901_through_20260930_exact":
            violations.append("methodology.seed_policy: canonical seed policy required")
        if methodology.get("samples_per_archetype") != EXPECTED_SEED_COUNT:
            violations.append("methodology.samples_per_archetype: expected 30")
        if methodology.get("total_samples") != 240:
            violations.append("methodology.total_samples: expected 240")
        if methodology.get("formation_requirements") != FORMATION_REQUIREMENTS:
            violations.append("methodology.formation_requirements: expected 3/2/1")
        if methodology.get("loadout_policy") != (
            "canonical_5x5x6_launch_loadouts_with_definition_compatibility"
        ):
            violations.append("methodology.loadout_policy: canonical compatibility policy required")
        if methodology.get("effect_execution_model") != (
            "bounded_effect_catalog_dry_run_with_active_handler_receipts"
        ):
            violations.append("methodology.effect_execution_model: bounded dry-run required")
        if "synthetic" not in str(methodology.get("disclaimer", "")).lower():
            violations.append("methodology.disclaimer: synthetic boundary required")

    content_digests = report.get("content_digests")
    if not isinstance(content_digests, dict):
        violations.append("content_digests: expected object")
    else:
        expected_digest_fields = {
            "catalog",
            "items",
            "blessings",
            "curses",
            "talents",
            "archetypes",
            "effect_catalog",
            "characters",
            "character_profiles",
            "weapons",
            "weapon_profiles",
            "time_abilities",
            "combined",
        }
        _check_exact_fields(content_digests, expected_digest_fields, "content_digests", violations)
        for key in expected_digest_fields:
            value = content_digests.get(key)
            if not _is_sha256(value):
                violations.append(f"content_digests.{key}: expected sha256")
        raw_digests = {
            key: content_digests.get(key)
            for key in expected_digest_fields
            if key != "combined"
        }
        if content_digests.get("combined") != _canonical_digest(raw_digests):
            violations.append("content_digests.combined: source digest mismatch")
        if context is not None:
            for key, source_path in context["source_paths"].items():
                if content_digests.get(key) != _file_digest(source_path):
                    violations.append(
                        f"content_digests.{key}: canonical source digest mismatch"
                    )

    samples = report.get("samples")
    if not isinstance(samples, list) or len(samples) != 240:
        violations.append("samples: expected exactly 240 entries")
        samples = []
    expected_order = [
        (archetype_id, seed)
        for archetype_id in CANONICAL_ARCHETYPES
        for seed in CANONICAL_SEEDS
    ]
    actual_order: list[tuple[Any, Any]] = []
    for index, sample in enumerate(samples):
        path = f"samples[{index}]"
        if not isinstance(sample, dict):
            violations.append(f"{path}: expected object")
            continue
        _check_exact_fields(sample, SAMPLE_FIELDS, path, violations)
        actual_order.append((sample.get("archetype_id"), sample.get("seed")))
        selected = sample.get("selected")
        if not isinstance(selected, dict):
            violations.append(f"{path}.selected: expected object")
        else:
            _check_exact_fields(selected, SELECTED_FIELDS, f"{path}.selected", violations)
            for key, count in {**FORMATION_REQUIREMENTS, "utility": 1, "talent": 1}.items():
                values = selected.get(key)
                if not isinstance(values, list) or len(values) != count:
                    violations.append(f"{path}.selected.{key}: expected {count} entries")
        exposure = sample.get("option_exposure")
        if not isinstance(exposure, dict):
            violations.append(f"{path}.option_exposure: expected object")
        else:
            _check_exact_fields(exposure, EXPOSURE_FIELDS, f"{path}.option_exposure", violations)
            for key in EXPOSURE_FIELDS:
                if type(exposure.get(key)) is not int or exposure.get(key, -1) < 0:
                    violations.append(f"{path}.option_exposure.{key}: expected non-negative integer")
        if sample.get("character_id") not in CANONICAL_CHARACTERS:
            violations.append(f"{path}.character_id: expected canonical Launch character")
        if sample.get("weapon_id") not in CANONICAL_WEAPONS:
            violations.append(f"{path}.weapon_id: expected canonical Launch weapon")
        time_ability_ids = sample.get("time_ability_ids")
        if (
            not isinstance(time_ability_ids, list)
            or tuple(time_ability_ids) not in CANONICAL_TIME_PAIRS
        ):
            violations.append(f"{path}.time_ability_ids: expected canonical ordered pair")
        if sample.get("formation_success") is not True or sample.get("failure_reasons") != []:
            violations.append(f"{path}: every canonical route must form successfully")
        for key in ("effect_execution_count", "active_usage_count", "curse_tradeoff_count"):
            if type(sample.get(key)) is not int or sample.get(key, -1) < 0:
                violations.append(f"{path}.{key}: expected non-negative integer")
        if not _is_sha256(sample.get("effect_execution_digest")):
            violations.append(f"{path}.effect_execution_digest: expected sha256")
        runtime_domains = sample.get("effect_runtime_domains")
        if not isinstance(runtime_domains, dict):
            violations.append(f"{path}.effect_runtime_domains: expected object")
        elif any(
            type(value) is not int or value < 0 for value in runtime_domains.values()
        ):
            violations.append(
                f"{path}.effect_runtime_domains: expected non-negative integer counts"
            )
        elif sum(runtime_domains.values()) != sample.get("effect_execution_count"):
            violations.append(
                f"{path}.effect_execution_count: runtime-domain total mismatch"
            )
        if (
            context is not None
            and isinstance(selected, dict)
            and isinstance(time_ability_ids, list)
            and sample.get("character_id") in CANONICAL_CHARACTERS
            and sample.get("weapon_id") in CANONICAL_WEAPONS
        ):
            try:
                recomputed = _selection_evidence(
                    str(sample.get("archetype_id", "")),
                    selected,
                    {
                        "character_id": str(sample["character_id"]),
                        "weapon_id": str(sample["weapon_id"]),
                        "time_ability_ids": tuple(str(value) for value in time_ability_ids),
                    },
                    context,
                )
            except ValueError as exc:
                violations.append(f"{path}.compatibility: {exc}")
            else:
                for failure in recomputed["failures"]:
                    violations.append(f"{path}.compatibility: {failure}")
                for key in (
                    "option_exposure",
                    "effect_execution_count",
                    "effect_execution_digest",
                    "effect_runtime_domains",
                    "active_usage_count",
                    "curse_tradeoff_count",
                ):
                    if sample.get(key) != recomputed[key]:
                        violations.append(f"{path}.{key}: recomputed value mismatch")
    if actual_order != expected_order:
        violations.append("samples: canonical archetype/seed order drifted")

    summaries = report.get("route_summaries")
    if not isinstance(summaries, list) or len(summaries) != len(CANONICAL_ARCHETYPES):
        violations.append("route_summaries: expected exactly eight entries")
        summaries = []
    summary_by_route: dict[str, dict[str, Any]] = {}
    for index, summary in enumerate(summaries):
        path = f"route_summaries[{index}]"
        if not isinstance(summary, dict):
            violations.append(f"{path}: expected object")
            continue
        _check_exact_fields(summary, SUMMARY_FIELDS, path, violations)
        summary_by_route[str(summary.get("archetype_id", ""))] = summary
    for archetype_id in CANONICAL_ARCHETYPES:
        route_samples = [
            sample
            for sample in samples
            if isinstance(sample, dict) and sample.get("archetype_id") == archetype_id
        ]
        summary = summary_by_route.get(archetype_id)
        if summary is None:
            violations.append(f"route_summaries.{archetype_id}: missing")
            continue
        recomputed = _aggregate_route_samples(route_samples)
        for key, value in recomputed.items():
            if summary.get(key) != value:
                violations.append(
                    f"route_summaries.{archetype_id}.{key}: recomputed value mismatch"
                )
        if summary.get("starter_pool_count", 0) < 3:
            violations.append(f"route_summaries.{archetype_id}: starter pool starved")
        if summary.get("payoff_pool_count", 0) < 2:
            violations.append(f"route_summaries.{archetype_id}: payoff pool starved")
        if summary.get("risk_pool_count", 0) < 3:
            violations.append(f"route_summaries.{archetype_id}: risk pool starved")
        for category in EXPOSURE_FIELDS:
            if summary.get("option_exposure", {}).get(category, 0) <= 0:
                violations.append(
                    f"route_summaries.{archetype_id}.option_exposure.{category}: starved"
                )
        if summary.get("active_usage_count", 0) <= 0:
            violations.append(f"route_summaries.{archetype_id}: active item never used")
        if summary.get("curse_tradeoff_count", 0) <= 0:
            violations.append(f"route_summaries.{archetype_id}: curse tradeoff never observed")

    digest = report.get("content_digest")
    if not _is_sha256(digest):
        violations.append("content_digest: expected sha256")
    elif digest != report_digest(report):
        violations.append("content_digest: report payload mismatch")
    return violations


def _load_simulation_context() -> dict[str, Any]:
    catalog = _load_json(CATALOG_PATH)
    live = {
        "item": _launch_rows(_require_rows(_load_json(ITEMS_PATH), ITEMS_PATH)),
        "blessing": _launch_rows(_require_rows(_load_json(BLESSINGS_PATH), BLESSINGS_PATH)),
        "curse": _launch_rows(_require_rows(_load_json(CURSES_PATH), CURSES_PATH)),
        "talent": _launch_rows(_require_rows(_load_json(TALENTS_PATH), TALENTS_PATH)),
    }
    archetype_profiles = _require_rows(_load_json(ARCHETYPES_PATH), ARCHETYPES_PATH)
    _require_catalog(catalog, live, archetype_profiles)

    catalog_groups = {
        "item": _require_rows(catalog.get("items"), CATALOG_PATH),
        "blessing": _require_rows(catalog.get("blessings"), CATALOG_PATH),
        "curse": _require_rows(catalog.get("curses"), CATALOG_PATH),
        "talent": _require_rows(catalog.get("talents"), CATALOG_PATH),
    }
    rows_by_id: dict[str, tuple[str, dict[str, Any]]] = {}
    catalog_by_id: dict[str, tuple[str, dict[str, Any]]] = {}
    for category, rows in live.items():
        for row in rows:
            content_id = str(row.get("id", ""))
            if not content_id or content_id in rows_by_id:
                raise ValueError(f"{category}: missing or duplicate live content id")
            rows_by_id[content_id] = (category, row)
    for category, rows in catalog_groups.items():
        for row in rows:
            content_id = str(row.get("id", ""))
            if not content_id or content_id in catalog_by_id:
                raise ValueError(f"{category}: missing or duplicate catalog content id")
            catalog_by_id[content_id] = (category, row)

    effect_rows = _require_rows(_load_json(EFFECT_CATALOG_PATH), EFFECT_CATALOG_PATH)
    effect_catalog: dict[str, dict[str, Any]] = {}
    for row in effect_rows:
        effect_id = str(row.get("effect_id", ""))
        if not effect_id or effect_id in effect_catalog:
            raise ValueError("effect catalog contains a missing or duplicate effect_id")
        effect_catalog[effect_id] = row

    character_rows = _launch_rows(
        _require_rows(_load_json(CHARACTERS_PATH), CHARACTERS_PATH)
    )
    character_profiles = _launch_rows(
        _require_rows(_load_json(CHARACTER_PROFILES_PATH), CHARACTER_PROFILES_PATH)
    )
    weapon_rows = _launch_rows(_require_rows(_load_json(WEAPONS_PATH), WEAPONS_PATH))
    weapon_profiles = _launch_rows(
        _require_rows(_load_json(WEAPON_PROFILES_PATH), WEAPON_PROFILES_PATH)
    )
    time_ability_rows = _launch_rows(
        _require_rows(_load_json(TIME_ABILITIES_PATH), TIME_ABILITIES_PATH)
    )
    loadouts = _canonical_loadouts(
        character_rows,
        character_profiles,
        weapon_rows,
        weapon_profiles,
        time_ability_rows,
    )

    source_paths = {
        "catalog": CATALOG_PATH,
        "items": ITEMS_PATH,
        "blessings": BLESSINGS_PATH,
        "curses": CURSES_PATH,
        "talents": TALENTS_PATH,
        "archetypes": ARCHETYPES_PATH,
        "effect_catalog": EFFECT_CATALOG_PATH,
        "characters": CHARACTERS_PATH,
        "character_profiles": CHARACTER_PROFILES_PATH,
        "weapons": WEAPONS_PATH,
        "weapon_profiles": WEAPON_PROFILES_PATH,
        "time_abilities": TIME_ABILITIES_PATH,
    }
    return {
        "catalog": catalog,
        "live": live,
        "catalog_groups": catalog_groups,
        "rows_by_id": rows_by_id,
        "catalog_by_id": catalog_by_id,
        "effect_catalog": effect_catalog,
        "loadouts": loadouts,
        "source_paths": source_paths,
    }


def _canonical_loadouts(
    character_rows: list[dict[str, Any]],
    character_profiles: list[dict[str, Any]],
    weapon_rows: list[dict[str, Any]],
    weapon_profiles: list[dict[str, Any]],
    time_ability_rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    _require_identity_set(character_rows, "id", CANONICAL_CHARACTERS, "characters")
    _require_identity_set(weapon_rows, "id", CANONICAL_WEAPONS, "weapons")
    _require_identity_set(
        time_ability_rows,
        "id",
        CANONICAL_TIME_ABILITIES,
        "time abilities",
    )
    character_profiles_by_id = _unique_rows_by_field(
        character_profiles,
        "character_id",
        CANONICAL_CHARACTERS,
        "character runtime profiles",
    )
    weapon_profiles_by_id = _unique_rows_by_field(
        weapon_profiles,
        "weapon_id",
        CANONICAL_WEAPONS,
        "weapon runtime profiles",
    )

    loadouts: list[dict[str, Any]] = []
    for character_id in CANONICAL_CHARACTERS:
        character_profile = character_profiles_by_id[character_id]
        mastery = character_profile.get("weapon_mastery")
        time_interactions = character_profile.get("time_interactions")
        if not isinstance(mastery, dict) or not isinstance(time_interactions, dict):
            raise ValueError(f"{character_id}: incomplete Launch character profile")
        for weapon_id in CANONICAL_WEAPONS:
            weapon_profile = weapon_profiles_by_id[weapon_id]
            weapon_time_interactions = weapon_profile.get("time_interactions")
            if weapon_id not in mastery:
                raise ValueError(f"{character_id}: missing {weapon_id} mastery")
            if not isinstance(weapon_time_interactions, dict):
                raise ValueError(f"{weapon_id}: missing time interactions")
            for time_pair in CANONICAL_TIME_PAIRS:
                missing_character_time = [
                    ability_id
                    for ability_id in time_pair
                    if ability_id not in time_interactions
                ]
                missing_weapon_time = [
                    ability_id
                    for ability_id in time_pair
                    if ability_id not in weapon_time_interactions
                ]
                if missing_character_time or missing_weapon_time:
                    raise ValueError(
                        f"{character_id}/{weapon_id}/{'+'.join(time_pair)}: "
                        "runtime profile compatibility drift"
                    )
                loadouts.append(
                    {
                        "character_id": character_id,
                        "weapon_id": weapon_id,
                        "time_ability_ids": time_pair,
                    }
                )
    if len(loadouts) != 150:
        raise ValueError(f"canonical Launch loadout count drifted: {len(loadouts)}")
    return loadouts


def _require_identity_set(
    rows: list[dict[str, Any]],
    field: str,
    expected: tuple[str, ...],
    label: str,
) -> None:
    actual = [str(row.get(field, "")) for row in rows]
    if len(actual) != len(set(actual)) or set(actual) != set(expected):
        raise ValueError(f"{label}: canonical identities drifted")


def _unique_rows_by_field(
    rows: list[dict[str, Any]],
    field: str,
    expected: tuple[str, ...],
    label: str,
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        content_id = str(row.get(field, ""))
        if not content_id or content_id in result:
            raise ValueError(f"{label}: missing or duplicate {field}")
        result[content_id] = row
    if set(result) != set(expected):
        raise ValueError(f"{label}: canonical identities drifted")
    return result


def _select_compatible_formation(
    *,
    archetype_id: str,
    seed: int,
    route_index: int,
    seed_index: int,
    loadouts: list[dict[str, Any]],
    starters: list[tuple[str, dict[str, Any]]],
    payoffs: list[tuple[str, dict[str, Any]]],
    risks: list[tuple[str, dict[str, Any]]],
    utilities: list[tuple[str, dict[str, Any]]],
    talents: list[tuple[str, dict[str, Any]]],
    rows_by_id: Mapping[str, tuple[str, dict[str, Any]]],
    effect_catalog: Mapping[str, dict[str, Any]],
) -> dict[str, Any] | None:
    start = _stable_index(
        len(loadouts),
        "loadout",
        archetype_id,
        seed,
        route_index,
        seed_index,
    )
    ordered_loadouts = loadouts[start:] + loadouts[:start]
    for loadout in ordered_loadouts:
        compatible_starters = _compatible_rows(
            starters, archetype_id, loadout, rows_by_id, effect_catalog
        )
        compatible_payoffs = _compatible_rows(
            payoffs, archetype_id, loadout, rows_by_id, effect_catalog
        )
        compatible_risks = _compatible_rows(
            risks, archetype_id, loadout, rows_by_id, effect_catalog
        )
        compatible_utilities = _compatible_rows(
            utilities, archetype_id, loadout, rows_by_id, effect_catalog
        )
        compatible_talents = _compatible_rows(
            talents, archetype_id, loadout, rows_by_id, effect_catalog
        )
        if (
            len(compatible_starters) < FORMATION_REQUIREMENTS["starters"]
            or len(compatible_payoffs) < FORMATION_REQUIREMENTS["payoffs"]
            or len(compatible_risks) < FORMATION_REQUIREMENTS["risks"]
            or not compatible_utilities
            or not compatible_talents
        ):
            continue
        return {
            "loadout": loadout,
            "starters": _rotate_pick(
                compatible_starters,
                FORMATION_REQUIREMENTS["starters"],
                seed,
                "starter",
            ),
            "payoffs": _rotate_pick(
                compatible_payoffs,
                FORMATION_REQUIREMENTS["payoffs"],
                seed,
                "payoff",
            ),
            "risks": _rotate_pick(
                compatible_risks,
                FORMATION_REQUIREMENTS["risks"],
                seed,
                "risk",
            ),
            "utility": _rotate_pick(
                compatible_utilities,
                1,
                seed + route_index,
                "utility",
            ),
            "talent": _rotate_pick(
                compatible_talents,
                1,
                seed + seed_index,
                "talent",
            ),
        }
    return None


def _compatible_rows(
    rows: list[tuple[str, dict[str, Any]]],
    archetype_id: str,
    loadout: Mapping[str, Any],
    rows_by_id: Mapping[str, tuple[str, dict[str, Any]]],
    effect_catalog: Mapping[str, dict[str, Any]],
) -> list[tuple[str, dict[str, Any]]]:
    result: list[tuple[str, dict[str, Any]]] = []
    for category, catalog_row in rows:
        content_id = str(catalog_row.get("id", ""))
        live_value = rows_by_id.get(content_id)
        if live_value is None or live_value[0] != category:
            continue
        if not _definition_compatibility_failures(
            live_value[1], archetype_id, loadout, effect_catalog
        ):
            result.append((category, catalog_row))
    return result


def _definition_compatibility_failures(
    definition: Mapping[str, Any],
    archetype_id: str,
    loadout: Mapping[str, Any],
    effect_catalog: Mapping[str, dict[str, Any]],
) -> list[str]:
    content_id = str(definition.get("id", ""))
    compatibility = definition.get("compatibility", {})
    if not isinstance(compatibility, dict):
        return [f"{content_id}:compatibility_type"]
    failures = [
        f"{content_id}:compatibility_unknown_{field}"
        for field in sorted(set(compatibility) - COMPATIBILITY_FIELDS)
    ]
    selections = {
        "archetype_ids": archetype_id,
        "character_ids": str(loadout.get("character_id", "")),
        "weapon_ids": str(loadout.get("weapon_id", "")),
    }
    for field, selected_id in selections.items():
        if field not in compatibility:
            continue
        allowed = compatibility[field]
        if not isinstance(allowed, list) or not allowed:
            failures.append(f"{content_id}:compatibility_{field}_empty")
        elif selected_id not in allowed:
            failures.append(f"{content_id}:compatibility_{field}_{selected_id}")
    time_ability_ids = tuple(str(value) for value in loadout.get("time_ability_ids", ()))
    if "time_ability_ids" in compatibility:
        allowed_time = compatibility["time_ability_ids"]
        if not isinstance(allowed_time, list) or not allowed_time:
            failures.append(f"{content_id}:compatibility_time_ability_ids_empty")
        else:
            for ability_id in time_ability_ids:
                if ability_id not in allowed_time:
                    failures.append(
                        f"{content_id}:compatibility_time_ability_ids_{ability_id}"
                    )

    effects = definition.get("effects", {})
    if not isinstance(effects, dict):
        failures.append(f"{content_id}:effects_type")
        return failures
    required_time_abilities: set[str] = set()
    for effect_id in effects:
        effect_spec = effect_catalog.get(str(effect_id))
        if effect_spec is None:
            failures.append(f"{content_id}:unknown_effect_{effect_id}")
            continue
        for prefix, ability_id in TIME_EFFECT_PREFIXES.items():
            if str(effect_id).startswith(prefix):
                required_time_abilities.add(ability_id)
        capabilities = effect_spec.get("weapon_capabilities", [])
        if capabilities:
            if not isinstance(capabilities, list) or not any(
                isinstance(capability, dict)
                and capability.get("weapon_id") == loadout.get("weapon_id")
                for capability in capabilities
            ):
                failures.append(
                    f"{content_id}:effect_{effect_id}_weapon_{loadout.get('weapon_id', '')}"
                )
    for ability_id in sorted(required_time_abilities):
        if ability_id not in time_ability_ids:
            failures.append(f"{content_id}:effect_requires_time_{ability_id}")
    if definition.get("item_mode") == "active":
        handler_id = str(definition.get("active_handler_id", ""))
        required_active_time = {
            "absolute_zero": "stop",
            "paradox_beacon": "rewind",
            "gravity_snare": "rift",
            "redline_injector": "accelerate",
        }.get(handler_id)
        if required_active_time is not None and required_active_time not in time_ability_ids:
            failures.append(f"{content_id}:active_requires_time_{required_active_time}")
        if handler_id == "railshot" and loadout.get("weapon_id") != "bow":
            failures.append(f"{content_id}:active_requires_weapon_bow")
    return failures


def _selection_evidence(
    archetype_id: str,
    selected: Mapping[str, Any],
    loadout: Mapping[str, Any],
    context: Mapping[str, Any],
) -> dict[str, Any]:
    rows_by_id = context["rows_by_id"]
    catalog_by_id = context["catalog_by_id"]
    effect_catalog = context["effect_catalog"]
    failures = _formation_failures(selected)
    exposure = {key: 0 for key in sorted(EXPOSURE_FIELDS)}
    receipts: list[dict[str, Any]] = []
    state: dict[str, Any] = {}
    active_usage_count = 0
    curse_tradeoff_count = 0
    seen_ids: set[str] = set()
    lane_contracts = {
        "starters": "starter",
        "payoffs": "payoff",
        "risks": "risk",
        "utility": "utility",
        "talent": "talent",
    }
    for lane, expected_role in lane_contracts.items():
        values = selected.get(lane, [])
        if not isinstance(values, list):
            continue
        for content_id_value in values:
            content_id = str(content_id_value)
            if content_id in seen_ids:
                failures.append(f"{content_id}:duplicate_selection")
                continue
            seen_ids.add(content_id)
            live_value = rows_by_id.get(content_id)
            catalog_value = catalog_by_id.get(content_id)
            if live_value is None or catalog_value is None:
                failures.append(f"{content_id}:unknown_selection")
                continue
            category, definition = live_value
            catalog_category, catalog_row = catalog_value
            if category != catalog_category:
                failures.append(f"{content_id}:category_mismatch")
                continue
            if lane == "talent":
                if category != "talent":
                    failures.append(f"{content_id}:talent_category")
            elif lane == "utility":
                if (
                    str(catalog_row.get("archetype", "")) != ""
                    or catalog_row.get("role") != "utility"
                ):
                    failures.append(f"{content_id}:utility_role")
            elif (
                catalog_row.get("archetype") != archetype_id
                or catalog_row.get("role") != expected_role
            ):
                failures.append(f"{content_id}:{lane}_route_role")
            compatibility_failures = _definition_compatibility_failures(
                definition, archetype_id, loadout, effect_catalog
            )
            failures.extend(compatibility_failures)
            exposure[category] += 1
            try:
                content_receipts = _execute_definition_dry_run(
                    category,
                    definition,
                    loadout,
                    effect_catalog,
                    state,
                )
            except ValueError as exc:
                failures.append(f"{content_id}:execution_{exc}")
                continue
            receipts.extend(content_receipts)
            if category == "item" and definition.get("item_mode") == "active":
                exposure["active"] += 1
                active_usage_count += 1
            if category == "curse":
                if len(content_receipts) < 2:
                    failures.append(f"{content_id}:curse_tradeoff_missing")
                else:
                    curse_tradeoff_count += 1
    domain_counts: Counter[str] = Counter(
        str(receipt["runtime_domain"]) for receipt in receipts
    )
    return {
        "failures": sorted(set(failures)),
        "option_exposure": exposure,
        "effect_execution_count": len(receipts),
        "effect_execution_digest": _canonical_digest(receipts),
        "effect_runtime_domains": dict(sorted(domain_counts.items())),
        "active_usage_count": active_usage_count,
        "curse_tradeoff_count": curse_tradeoff_count,
    }


def _execute_definition_dry_run(
    category: str,
    definition: Mapping[str, Any],
    loadout: Mapping[str, Any],
    effect_catalog: Mapping[str, dict[str, Any]],
    state: dict[str, Any],
) -> list[dict[str, Any]]:
    content_id = str(definition.get("id", ""))
    effects = definition.get("effects", {})
    if not isinstance(effects, dict):
        raise ValueError("effects_type")
    receipts: list[dict[str, Any]] = []
    for effect_id in sorted(str(value) for value in effects):
        value = effects[effect_id]
        spec = effect_catalog.get(effect_id)
        if spec is None:
            raise ValueError(f"unknown_effect_{effect_id}")
        allowed_categories = spec.get("allowed_categories", [])
        if not isinstance(allowed_categories, list) or category not in allowed_categories:
            raise ValueError(f"effect_{effect_id}_category")
        _validate_effect_value(effect_id, value, spec)
        capabilities = spec.get("weapon_capabilities", [])
        if capabilities and not any(
            isinstance(capability, dict)
            and capability.get("weapon_id") == loadout.get("weapon_id")
            for capability in capabilities
        ):
            raise ValueError(f"effect_{effect_id}_weapon")
        runtime_domain = str(spec.get("runtime_domain", ""))
        stack_rule = str(spec.get("stack_rule", ""))
        if not runtime_domain or not stack_rule:
            raise ValueError(f"effect_{effect_id}_runtime_contract")
        state_key = f"{runtime_domain}:{effect_id}"
        previous = state.get(state_key)
        result = _apply_stack_rule(stack_rule, previous, value)
        if stack_rule != "trigger":
            state[state_key] = result
        receipts.append(
            {
                "content_id": content_id,
                "effect_id": effect_id,
                "runtime_domain": runtime_domain,
                "stack_rule": stack_rule,
                "previous": previous,
                "value": value,
                "result": result,
            }
        )
    if definition.get("item_mode") == "active":
        handler_id = str(definition.get("active_handler_id", ""))
        cooldown_frames = definition.get("cooldown_frames")
        parameters = definition.get("active_parameters")
        if handler_id not in ACTIVE_HANDLER_IDS:
            raise ValueError("active_handler")
        if type(cooldown_frames) is not int or not 1 <= cooldown_frames <= 3600:
            raise ValueError("active_cooldown")
        if (
            not isinstance(parameters, dict)
            or not parameters
            or any(not _is_finite_number(value) for value in parameters.values())
        ):
            raise ValueError("active_parameters")
        receipts.append(
            {
                "content_id": content_id,
                "effect_id": f"active_handler:{handler_id}",
                "runtime_domain": "active",
                "stack_rule": "trigger",
                "previous": None,
                "value": dict(sorted(parameters.items())),
                "result": {"cooldown_frames": cooldown_frames},
            }
        )
    elif category in {"item", "blessing", "curse", "talent"} and not effects:
        raise ValueError("empty_effects")
    return receipts


def _validate_effect_value(
    effect_id: str,
    value: Any,
    spec: Mapping[str, Any],
) -> None:
    value_type = spec.get("value_type")
    if value_type == "boolean":
        valid_type = type(value) is bool
    elif value_type == "integer":
        valid_type = type(value) is int
    elif value_type == "number":
        valid_type = type(value) in {int, float} and not isinstance(value, bool)
    else:
        raise ValueError(f"effect_{effect_id}_value_type_contract")
    if not valid_type or not _is_finite_scalar(value):
        raise ValueError(f"effect_{effect_id}_value_type")
    minimum = spec.get("minimum")
    maximum = spec.get("maximum")
    if minimum is not None and value < minimum:
        raise ValueError(f"effect_{effect_id}_minimum")
    if maximum is not None and value > maximum:
        raise ValueError(f"effect_{effect_id}_maximum")


def _apply_stack_rule(stack_rule: str, previous: Any, value: Any) -> Any:
    if stack_rule == "add":
        return (0 if previous is None else previous) + value
    if stack_rule == "multiply":
        return (1 if previous is None else previous) * value
    if stack_rule == "maximum":
        return value if previous is None else max(previous, value)
    if stack_rule == "replace":
        return value
    if stack_rule == "set_true":
        if value is not True:
            raise ValueError("set_true_value")
        return True
    if stack_rule == "trigger":
        return value
    raise ValueError(f"unknown_stack_rule_{stack_rule}")


def _is_finite_scalar(value: Any) -> bool:
    if type(value) is bool:
        return True
    return type(value) in {int, float} and math.isfinite(float(value))


def _is_finite_number(value: Any) -> bool:
    return type(value) in {int, float} and math.isfinite(float(value))


def _stable_index(length: int, *parts: Any) -> int:
    if length <= 0:
        return 0
    payload = ":".join(str(part) for part in parts).encode("utf-8")
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "big") % length


def _require_catalog(
    catalog: Any,
    live: Mapping[str, list[dict[str, Any]]],
    archetype_profiles: list[dict[str, Any]],
) -> None:
    if not isinstance(catalog, dict) or catalog.get("schema_version") != 1:
        raise ValueError("launch pool catalog schema must be exactly 1")
    catalog_keys = {"schema_version", "items", "blessings", "curses", "talents"}
    if set(catalog) != catalog_keys:
        raise ValueError("launch pool catalog has unknown or missing fields")
    for singular, plural in (
        ("item", "items"),
        ("blessing", "blessings"),
        ("curse", "curses"),
        ("talent", "talents"),
    ):
        expected_ids = [str(row["id"]) for row in _require_rows(catalog[plural], CATALOG_PATH)]
        live_ids = [str(row["id"]) for row in live[singular]]
        if len(live_ids) != len(set(live_ids)) or set(expected_ids) != set(live_ids):
            raise ValueError(f"{plural}: live Launch identities drifted from target catalog")
    archetype_ids = [str(row.get("archetype_id", "")) for row in archetype_profiles]
    if archetype_ids != list(CANONICAL_ARCHETYPES):
        raise ValueError("archetype profile identity/order drifted")


def _route_rows(
    groups: Mapping[str, list[dict[str, Any]]], archetype_id: str, role: str
) -> list[tuple[str, dict[str, Any]]]:
    return [
        (category, row)
        for category in ("item", "blessing", "curse")
        for row in groups[category]
        if row.get("archetype") == archetype_id and row.get("role") == role
    ]


def _rotate_pick(
    rows: list[tuple[str, dict[str, Any]]], count: int, seed: int, lane: str
) -> list[tuple[str, dict[str, Any]]]:
    if len(rows) < count:
        return []
    lane_digest = hashlib.sha256(f"{seed}:{lane}".encode("utf-8")).digest()
    start = int.from_bytes(lane_digest[:4], "big") % len(rows)
    return [rows[(start + offset) % len(rows)] for offset in range(count)]


def _row_ids(rows: Iterable[tuple[str, Mapping[str, Any]]]) -> list[str]:
    return [str(row["id"]) for _category, row in rows]


def _formation_failures(selected: Mapping[str, list[str]]) -> list[str]:
    failures: list[str] = []
    for key, minimum in FORMATION_REQUIREMENTS.items():
        if len(selected.get(key, [])) != minimum:
            failures.append(f"{key}_starved")
    if len(selected.get("utility", [])) != 1:
        failures.append("utility_starved")
    if len(selected.get("talent", [])) != 1:
        failures.append("talent_starved")
    return failures


def _summaries_from_samples(
    samples: list[dict[str, Any]],
    pool_counts: Mapping[str, tuple[int, int, int]],
) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for archetype_id in CANONICAL_ARCHETYPES:
        route_samples = [sample for sample in samples if sample["archetype_id"] == archetype_id]
        starter_count, payoff_count, risk_count = pool_counts[archetype_id]
        summary = {
            "archetype_id": archetype_id,
            "starter_pool_count": starter_count,
            "payoff_pool_count": payoff_count,
            "risk_pool_count": risk_count,
        }
        summary.update(_aggregate_route_samples(route_samples))
        summaries.append(summary)
    return summaries


def _aggregate_route_samples(samples: list[dict[str, Any]]) -> dict[str, Any]:
    failure_counter: Counter[str] = Counter()
    exposure = {key: 0 for key in sorted(EXPOSURE_FIELDS)}
    for sample in samples:
        failure_counter.update(str(item) for item in sample.get("failure_reasons", []))
        for key in EXPOSURE_FIELDS:
            exposure[key] += int(sample.get("option_exposure", {}).get(key, 0))
    return {
        "sample_count": len(samples),
        "formation_success_count": sum(
            1 for sample in samples if sample.get("formation_success") is True
        ),
        "failure_reasons": dict(sorted(failure_counter.items())),
        "option_exposure": exposure,
        "effect_execution_count": sum(
            int(sample.get("effect_execution_count", 0)) for sample in samples
        ),
        "active_usage_count": sum(
            int(sample.get("active_usage_count", 0)) for sample in samples
        ),
        "curse_tradeoff_count": sum(
            int(sample.get("curse_tradeoff_count", 0)) for sample in samples
        ),
    }


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"failed to load {path}: {exc}") from exc


def _require_rows(value: Any, source: Path) -> list[dict[str, Any]]:
    if not isinstance(value, list) or any(not isinstance(row, dict) for row in value):
        raise ValueError(f"{source}: expected an array of objects")
    return value


def _launch_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        row
        for row in rows
        if isinstance(row.get("availability"), list)
        and "LAUNCH" in row.get("availability", [])
    ]


def _file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _canonical_digest(value: Any) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _is_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    return all(character in "0123456789abcdef" for character in value)


def _check_exact_fields(
    value: Mapping[str, Any], expected: set[str], path: str, violations: list[str]
) -> None:
    actual = set(value)
    for field in sorted(actual - expected):
        violations.append(f"{path}.{field}: unexpected field")
    for field in sorted(expected - actual):
        violations.append(f"{path}.{field}: missing field")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=EXPECTED_SEED_COUNT)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        report = build_report(seed_count=args.seeds)
    except ValueError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, allow_nan=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote synthetic deterministic Launch-pool report with {len(report['samples'])} samples to {args.output}"
    )
    print("This output is synthetic and is not human playtest evidence.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
