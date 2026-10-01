#!/usr/bin/env python3
"""Build deterministic synthetic P13B Launch-pool formation evidence.

This tool models content availability and build formation only. Its output is
never human playtest evidence and cannot satisfy the M1 external-playtest gate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
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

SCHEMA_VERSION = "1.0.0"
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
    "formation_success",
    "failure_reasons",
    "selected",
    "option_exposure",
    "effect_execution_count",
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


def build_report(seed_count: int = EXPECTED_SEED_COUNT) -> dict[str, Any]:
    if seed_count != EXPECTED_SEED_COUNT:
        raise ValueError(f"seed_count must be exactly {EXPECTED_SEED_COUNT}")

    catalog = _load_json(CATALOG_PATH)
    live = {
        "item": _launch_rows(_require_rows(_load_json(ITEMS_PATH), ITEMS_PATH)),
        "blessing": _launch_rows(_require_rows(_load_json(BLESSINGS_PATH), BLESSINGS_PATH)),
        "curse": _launch_rows(_require_rows(_load_json(CURSES_PATH), CURSES_PATH)),
        "talent": _launch_rows(_require_rows(_load_json(TALENTS_PATH), TALENTS_PATH)),
    }
    archetype_profiles = _require_rows(_load_json(ARCHETYPES_PATH), ARCHETYPES_PATH)
    _require_catalog(catalog, live, archetype_profiles)

    rows_by_id: dict[str, tuple[str, dict[str, Any]]] = {}
    for category, rows in live.items():
        for row in rows:
            rows_by_id[str(row["id"])] = (category, row)

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

    source_paths = {
        "catalog": CATALOG_PATH,
        "items": ITEMS_PATH,
        "blessings": BLESSINGS_PATH,
        "curses": CURSES_PATH,
        "talents": TALENTS_PATH,
        "archetypes": ARCHETYPES_PATH,
    }
    content_digests = {key: _file_digest(path) for key, path in source_paths.items()}
    content_digests["combined"] = _canonical_digest(content_digests)

    catalog_groups = {
        "item": _require_rows(catalog.get("items"), CATALOG_PATH),
        "blessing": _require_rows(catalog.get("blessings"), CATALOG_PATH),
        "curse": _require_rows(catalog.get("curses"), CATALOG_PATH),
        "talent": _require_rows(catalog.get("talents"), CATALOG_PATH),
    }
    talents = catalog_groups["talent"]
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
            chosen_starters = _rotate_pick(starters, FORMATION_REQUIREMENTS["starters"], seed, "starter")
            chosen_payoffs = _rotate_pick(payoffs, FORMATION_REQUIREMENTS["payoffs"], seed, "payoff")
            chosen_risks = _rotate_pick(risks, FORMATION_REQUIREMENTS["risks"], seed, "risk")
            chosen_utility = _rotate_pick(utilities, 1, seed + route_index, "utility")
            talent_index = (route_index * EXPECTED_SEED_COUNT + seed_index) % len(talents)
            chosen_talent = [("talent", talents[talent_index])]
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
            failures = _formation_failures(selected)
            exposure = {key: 0 for key in sorted(EXPOSURE_FIELDS)}
            effect_execution_count = 0
            active_usage_count = 0
            curse_tradeoff_count = 0
            for category, catalog_row in chosen:
                content_id = str(catalog_row["id"])
                live_category, definition = rows_by_id[content_id]
                if live_category != category:
                    raise ValueError(
                        f"{content_id}: catalog category {category} != live {live_category}"
                    )
                exposure[category] += 1
                effects = definition.get("effects", {})
                if isinstance(effects, dict):
                    effect_execution_count += len(effects)
                if category == "item" and definition.get("item_mode") == "active":
                    exposure["active"] += 1
                    active_usage_count += 1
                    effect_execution_count += 1
                if category == "curse":
                    curse_tradeoff_count += 1
            talent_definition = rows_by_id[selected["talent"][0]][1]
            character_ids = talent_definition.get("compatibility", {}).get(
                "character_ids", []
            )
            if not isinstance(character_ids, list) or len(character_ids) != 1:
                raise ValueError(
                    f"{selected['talent'][0]}: expected one compatible character"
                )
            samples.append(
                {
                    "archetype_id": archetype_id,
                    "seed": seed,
                    "character_id": str(character_ids[0]),
                    "formation_success": not failures,
                    "failure_reasons": failures,
                    "selected": selected,
                    "option_exposure": exposure,
                    "effect_execution_count": effect_execution_count,
                    "active_usage_count": active_usage_count,
                    "curse_tradeoff_count": curse_tradeoff_count,
                }
            )

    route_summaries = _summaries_from_samples(samples, pool_counts)
    report: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "report_type": REPORT_TYPE,
        "evidence": EVIDENCE.copy(),
        "methodology": {
            "model_version": "p13b-launch-pool-formation-v1",
            "seed_policy": "canonical_20260901_through_20260930_exact",
            "samples_per_archetype": EXPECTED_SEED_COUNT,
            "total_samples": len(CANONICAL_ARCHETYPES) * EXPECTED_SEED_COUNT,
            "formation_requirements": FORMATION_REQUIREMENTS.copy(),
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
        if "synthetic" not in str(methodology.get("disclaimer", "")).lower():
            violations.append("methodology.disclaimer: synthetic boundary required")

    content_digests = report.get("content_digests")
    if not isinstance(content_digests, dict):
        violations.append("content_digests: expected object")
    else:
        expected_digest_fields = {
            "catalog", "items", "blessings", "curses", "talents", "archetypes", "combined"
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
        if sample.get("formation_success") is not True or sample.get("failure_reasons") != []:
            violations.append(f"{path}: every canonical route must form successfully")
        for key in ("effect_execution_count", "active_usage_count", "curse_tradeoff_count"):
            if type(sample.get(key)) is not int or sample.get(key, -1) < 0:
                violations.append(f"{path}.{key}: expected non-negative integer")
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
