#!/usr/bin/env python3
"""Deterministic M1 seed, observation, tuning, and release gate contracts."""

from __future__ import annotations

import base64
import hashlib
import json
import re
import subprocess
import tempfile
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Mapping, Sequence


M1_GO = "M1 Go"
M1_NO_GO = "M1 No-Go"
M1_CANDIDATE = "M1 Candidate — External Validation Pending"
SEED_MATRIX_SCHEMA = "2.0.0"
OBSERVATION_SCHEMA = "1.0.0"
TUNING_INPUT_SCHEMA = "1.0.0"
EXTERNAL_ATTESTATION_SCHEMA = "2.0.0"
PROBE_VERSION = "2.0.0"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
ATTESTOR_TRUST_PATH = PROJECT_ROOT / "data" / "trust" / "m1_external_attestors.json"
CANONICAL_SEED_START = 0
CANONICAL_SEED_COUNT = 30
MINIMUM_HUMAN_SESSIONS = 20
SESSION_ID_RE = re.compile(r"^pws_[0-9a-f]{32}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{7,40}$")
IDENTIFIER_RE = re.compile(r"^[a-z0-9_][a-z0-9_.-]*$")
HUMAN_COLLECTION_METHODS = frozenset({"observed_playtest", "imported_observation"})
SYNTHETIC_COLLECTION_METHODS = frozenset({"automated_fixture", "simulation"})
REPLAY_INTENTS = frozenset({"restarted", "would_replay", "would_not_replay", "unknown"})
ISSUE_SEVERITIES = frozenset({"p0", "p1", "p2", "p3"})
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TREE_DIGEST_RE = re.compile(r"^[0-9a-f]{40,64}$")
UTC_TIMESTAMP_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"
)
RUN_DIGEST_FIELDS = (
    "seed",
    "terminal_state",
    "room_sequence",
    "encounter_ids",
    "spawn_sequences",
    "reward_offers",
    "selected_choices",
    "choice_snapshots",
    "failure_codes",
    "duration_proxy_ms",
)


@dataclass(frozen=True, order=True)
class ObservationViolation:
    code: str
    path: str
    message: str
    line: int = 0

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class ObservationImportResult:
    observations: list[dict]
    violations: list[ObservationViolation]


@dataclass(frozen=True)
class SeedMatrixValidation:
    passed: bool
    release_eligible: bool
    seed_count: int
    seeds: tuple[int, ...]
    reasons: tuple[str, ...]
    release_reasons: tuple[str, ...]

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class SeedMatrixComparison:
    matched: bool
    changed_seeds: tuple[int, ...]
    reasons: tuple[str, ...]

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class M1Decision:
    state: str
    cohort: dict
    repository_gate: dict
    external_gate: dict
    tuning_input: dict
    reasons: tuple[str, ...]

    def to_dict(self) -> dict:
        return asdict(self)


def canonical_digest(value: object) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def canonical_records_digest(records: Sequence[Mapping[str, object]]) -> str:
    normalized = sorted(
        (_deep_copy(record) for record in records),
        key=lambda item: str(item.get("session_id", "")) if isinstance(item, dict) else "",
    )
    return canonical_digest(normalized)


def make_seed_matrix(
    raw_runs: Sequence[Mapping[str, object]],
    *,
    cohort: Mapping[str, str],
    seed_start: int,
    seed_count: int,
    evidence: Mapping[str, object],
) -> dict:
    runs: list[dict] = []
    for raw_run in raw_runs:
        run = {field: _deep_copy(raw_run.get(field)) for field in RUN_DIGEST_FIELDS}
        run["digest"] = canonical_digest(run)
        runs.append(run)
    matrix_core = {
        "cohort": dict(cohort),
        "evidence": _deep_copy(evidence),
        "seed_start": seed_start,
        "seed_count": seed_count,
        "run_digests": [
            {"seed": run.get("seed"), "digest": run.get("digest")} for run in runs
        ],
    }
    return {
        "schema_version": SEED_MATRIX_SCHEMA,
        "cohort": dict(cohort),
        "evidence": _deep_copy(evidence),
        "seed_start": seed_start,
        "seed_count": seed_count,
        "runs": runs,
        "matrix_digest": canonical_digest(matrix_core),
    }


def validate_seed_matrix(
    report: object,
    *,
    expected_start: int = CANONICAL_SEED_START,
    expected_count: int = CANONICAL_SEED_COUNT,
    verify_repository_artifacts: bool = True,
    trusted_runtime_matrix_digest: str | None = None,
) -> SeedMatrixValidation:
    reasons: list[str] = []
    release_reasons: list[str] = []
    if not isinstance(report, dict):
        return SeedMatrixValidation(
            False,
            False,
            0,
            (),
            ("seed report must be a JSON object",),
            ("seed report is not release eligible",),
        )
    if report.get("schema_version") != SEED_MATRIX_SCHEMA:
        reasons.append(f"unsupported seed report schema: {report.get('schema_version')!r}")
    if report.get("seed_start") != expected_start:
        reasons.append(f"seed_start must be {expected_start}")
    if report.get("seed_count") != expected_count:
        reasons.append(f"seed_count must be {expected_count}")
    reasons.extend(_validate_cohort(report.get("cohort")))
    evidence_reasons, release_reasons = _validate_matrix_evidence(
        report.get("evidence"),
        report.get("cohort"),
        verify_repository_artifacts=verify_repository_artifacts,
    )
    reasons.extend(evidence_reasons)

    raw_runs = report.get("runs")
    if not isinstance(raw_runs, list):
        return SeedMatrixValidation(
            False,
            False,
            0,
            (),
            tuple(reasons + ["runs must be an array"]),
            tuple(release_reasons),
        )
    seed_counts: Counter[int] = Counter()
    valid_seeds: list[int] = []
    for index, raw_run in enumerate(raw_runs):
        path = f"runs[{index}]"
        if not isinstance(raw_run, dict):
            reasons.append(f"{path} must be an object")
            continue
        seed = raw_run.get("seed")
        if isinstance(seed, bool) or not isinstance(seed, int):
            reasons.append(f"{path}.seed must be an integer")
            continue
        valid_seeds.append(seed)
        seed_counts[seed] += 1
        for field in RUN_DIGEST_FIELDS:
            if field not in raw_run:
                reasons.append(f"{path}.{field} is required")
        if not isinstance(raw_run.get("failure_codes"), list):
            reasons.append(f"{path}.failure_codes must be an array")
        if not isinstance(raw_run.get("duration_proxy_ms"), int) or isinstance(raw_run.get("duration_proxy_ms"), bool):
            reasons.append(f"{path}.duration_proxy_ms must be an integer")
        _validate_run_shape(raw_run, path, reasons)
        digest_input = {field: _deep_copy(raw_run.get(field)) for field in RUN_DIGEST_FIELDS}
        expected_digest = canonical_digest(digest_input)
        if raw_run.get("digest") != expected_digest:
            reasons.append(f"{path}.digest does not match the deterministic run facts")

    for seed, count in sorted(seed_counts.items()):
        if count > 1:
            reasons.append(f"duplicate seed {seed}")
    expected_seeds = set(range(expected_start, expected_start + expected_count))
    actual_seeds = set(valid_seeds)
    missing = sorted(expected_seeds - actual_seeds)
    extra = sorted(actual_seeds - expected_seeds)
    if missing:
        reasons.append("missing seeds: " + ", ".join(str(seed) for seed in missing))
    if extra:
        reasons.append("unexpected seeds: " + ", ".join(str(seed) for seed in extra))
    if len(raw_runs) != expected_count:
        reasons.append(f"expected {expected_count} run records; found {len(raw_runs)}")

    matrix_core = {
        "cohort": _deep_copy(report.get("cohort")),
        "evidence": _deep_copy(report.get("evidence")),
        "seed_start": report.get("seed_start"),
        "seed_count": report.get("seed_count"),
        "run_digests": [
            {"seed": run.get("seed"), "digest": run.get("digest")}
            for run in raw_runs
            if isinstance(run, dict)
        ],
    }
    matrix_digest = report.get("matrix_digest")
    if matrix_digest != canonical_digest(matrix_core):
        reasons.append("matrix_digest does not match the report cohort and run digests")
    evidence = _mapping(report.get("evidence"))
    if (
        evidence.get("evidence_origin") == "godot_authoritative_probe"
        and evidence.get("classification") == "release"
    ):
        if trusted_runtime_matrix_digest is None:
            release_reasons.append("release seed matrix requires trusted live Godot verification")
        elif trusted_runtime_matrix_digest != matrix_digest:
            release_reasons.append("trusted live Godot matrix digest does not match the supplied report")
    return SeedMatrixValidation(
        passed=not reasons,
        release_eligible=not reasons and not release_reasons,
        seed_count=len(raw_runs),
        seeds=tuple(sorted(actual_seeds)),
        reasons=tuple(reasons),
        release_reasons=tuple(release_reasons),
    )


def compare_seed_matrices(first: object, second: object) -> SeedMatrixComparison:
    first_validation = validate_seed_matrix(first)
    second_validation = validate_seed_matrix(second)
    reasons: list[str] = []
    if not first_validation.passed:
        reasons.extend(f"first: {reason}" for reason in first_validation.reasons)
    if not second_validation.passed:
        reasons.extend(f"second: {reason}" for reason in second_validation.reasons)
    if not isinstance(first, dict) or not isinstance(second, dict):
        return SeedMatrixComparison(False, (), tuple(reasons or ["reports must be objects"]))
    if first.get("cohort") != second.get("cohort"):
        reasons.append("build/content cohort differs")
    first_digests = _seed_digest_map(first)
    second_digests = _seed_digest_map(second)
    changed = sorted(
        seed
        for seed in set(first_digests) | set(second_digests)
        if first_digests.get(seed) != second_digests.get(seed)
    )
    if changed:
        reasons.append("deterministic digest drift for seeds: " + ", ".join(map(str, changed)))
    if first.get("matrix_digest") != second.get("matrix_digest") and not changed:
        reasons.append("matrix digest differs")
    return SeedMatrixComparison(not reasons, tuple(changed), tuple(reasons))


def validate_observation(value: object) -> list[ObservationViolation]:
    errors: list[ObservationViolation] = []
    if not isinstance(value, dict):
        return [ObservationViolation("invalid-type", "$", "observation must be an object")]
    fields = frozenset(
        {"schema_version", "session_id", "evidence", "time_abilities", "comprehension", "experience", "issues"}
    )
    _require_fields(value, fields, "$", errors)
    _reject_extra_fields(value, fields, "$", errors)
    if value.get("schema_version") != OBSERVATION_SCHEMA:
        errors.append(ObservationViolation("unsupported-schema-version", "$.schema_version", f"expected {OBSERVATION_SCHEMA}"))
    session_id = value.get("session_id")
    if not isinstance(session_id, str) or SESSION_ID_RE.fullmatch(session_id) is None:
        errors.append(ObservationViolation("invalid-session-id", "$.session_id", "expected anonymous pws_ session id"))
    _validate_observation_evidence(value.get("evidence"), errors)
    _validate_time_abilities(value.get("time_abilities"), errors)
    _validate_comprehension(value.get("comprehension"), errors)
    _validate_experience(value.get("experience"), errors)
    _validate_issues(value.get("issues"), errors)
    return sorted(errors)


def load_observations_jsonl(path: str | Path) -> ObservationImportResult:
    source = Path(path)
    observations: list[dict] = []
    violations: list[ObservationViolation] = []
    seen: set[str] = set()
    try:
        lines = source.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        return ObservationImportResult([], [ObservationViolation("unreadable-file", str(source), str(error))])
    for line_number, raw_line in enumerate(lines, start=1):
        if not raw_line.strip():
            continue
        try:
            value = json.loads(raw_line)
        except json.JSONDecodeError as error:
            violations.append(ObservationViolation("invalid-json", "$", error.msg, line_number))
            continue
        line_errors = validate_observation(value)
        if line_errors:
            violations.extend(
                ObservationViolation(item.code, item.path, item.message, line_number)
                for item in line_errors
            )
            continue
        session_id = str(value["session_id"])
        if session_id in seen:
            violations.append(
                ObservationViolation("duplicate-session", "$.session_id", f"observation for {session_id} already appeared", line_number)
            )
            continue
        seen.add(session_id)
        observations.append(value)
    return ObservationImportResult(observations, sorted(violations))


def evaluate_m1(
    seed_report: object,
    sessions: Iterable[Mapping[str, object]],
    *,
    session_violations: Sequence[object] = (),
    observations: Iterable[Mapping[str, object]] = (),
    observation_violations: Sequence[object] = (),
    attestation: object = None,
    minimum_human_sessions: int = MINIMUM_HUMAN_SESSIONS,
    verify_repository_artifacts: bool = True,
    attestation_trust: Mapping[str, object] | None = None,
    trusted_runtime_matrix_digest: str | None = None,
) -> M1Decision:
    from playtest_data import validate_session

    if minimum_human_sessions <= 0:
        raise ValueError("minimum_human_sessions must be positive")
    matrix_validation = validate_seed_matrix(
        seed_report,
        verify_repository_artifacts=verify_repository_artifacts,
        trusted_runtime_matrix_digest=trusted_runtime_matrix_digest,
    )
    report = seed_report if isinstance(seed_report, dict) else {}
    cohort = dict(report.get("cohort", {})) if isinstance(report.get("cohort"), dict) else {}
    repository_reasons = list(matrix_validation.reasons) + list(matrix_validation.release_reasons)
    runs = report.get("runs", []) if isinstance(report.get("runs"), list) else []
    failed_seeds: list[dict] = []
    for run in runs:
        if not isinstance(run, dict):
            continue
        failures = run.get("failure_codes", [])
        if run.get("terminal_state") != "victory" or failures:
            failed_seeds.append(
                {
                    "seed": run.get("seed"),
                    "terminal_state": run.get("terminal_state"),
                    "failure_codes": list(failures) if isinstance(failures, list) else ["invalid_failure_codes"],
                }
            )
    if failed_seeds:
        repository_reasons.append(f"{len(failed_seeds)} deterministic seeds did not finish cleanly")
    repository_gate = {
        "passed": matrix_validation.release_eligible and not failed_seeds,
        "matrix_valid": matrix_validation.passed,
        "release_eligible": matrix_validation.release_eligible,
        "live_runtime_verified": (
            isinstance(report.get("matrix_digest"), str)
            and trusted_runtime_matrix_digest == report.get("matrix_digest")
        ),
        "seed_count": matrix_validation.seed_count,
        "matrix_digest": report.get("matrix_digest", ""),
        "evidence": _deep_copy(report.get("evidence", {})),
        "failed_seeds": failed_seeds,
        "reasons": repository_reasons,
    }

    human_sessions: list[Mapping[str, object]] = []
    synthetic_count = 0
    excluded_cohort_count = 0
    duplicate_sessions = 0
    imported_duplicate_sessions = count_invalid_records(
        [item for item in session_violations if getattr(item, "code", "") == "duplicate-session"]
    )
    invalid_session_count = count_invalid_records(
        [item for item in session_violations if getattr(item, "code", "") != "duplicate-session"]
    )
    session_violation_count = len(session_violations)
    duplicate_sessions = imported_duplicate_sessions
    seen_sessions: set[str] = set()
    for session in sessions:
        validation_errors = validate_session(session)
        if validation_errors:
            invalid_session_count += 1
            session_violation_count += len(validation_errors)
            continue
        session_id = str(session.get("session_id", ""))
        if session_id in seen_sessions:
            duplicate_sessions += 1
            continue
        seen_sessions.add(session_id)
        evidence = _mapping(session.get("evidence"))
        if evidence.get("source") == "synthetic" and evidence.get("synthetic") is True:
            synthetic_count += 1
            continue
        if not _session_matches_cohort(session, cohort):
            excluded_cohort_count += 1
            continue
        human_sessions.append(session)

    valid_observations: dict[str, Mapping[str, object]] = {}
    synthetic_observations = 0
    duplicate_observations = count_invalid_records(
        [item for item in observation_violations if getattr(item, "code", "") == "duplicate-session"]
    )
    invalid_observation_count = count_invalid_records(
        [item for item in observation_violations if getattr(item, "code", "") != "duplicate-session"]
    )
    observation_violation_count = len(observation_violations)
    for observation in observations:
        errors = validate_observation(observation)
        if errors:
            invalid_observation_count += 1
            observation_violation_count += len(errors)
            continue
        session_id = str(observation.get("session_id", ""))
        if session_id in valid_observations:
            duplicate_observations += 1
            continue
        evidence = _mapping(observation.get("evidence"))
        if evidence.get("source") == "synthetic" and evidence.get("synthetic") is True:
            synthetic_observations += 1
            continue
        valid_observations[session_id] = observation

    joined = [
        (session, valid_observations[str(session.get("session_id", ""))])
        for session in human_sessions
        if str(session.get("session_id", "")) in valid_observations
    ]
    joined_session_ids = [str(session.get("session_id", "")) for session, _ in joined]
    thresholds = _evaluate_thresholds(joined)
    blocking_issues = _blocking_issues(joined)
    attestation_result = _evaluate_attestation(
        attestation,
        cohort=cohort,
        joined_session_ids=joined_session_ids,
        minimum_human_sessions=minimum_human_sessions,
        matrix_digest=str(report.get("matrix_digest", "")),
        sessions_digest=canonical_records_digest([session for session, _ in joined]),
        observations_digest=canonical_records_digest([observation for _, observation in joined]),
        trust_store=attestation_trust,
    )
    integrity_failures = (
        invalid_session_count
        + duplicate_sessions
        + invalid_observation_count
        + duplicate_observations
    )
    complete_external_cohort = (
        len(human_sessions) >= minimum_human_sessions
        and len(joined) >= minimum_human_sessions
    )
    thresholds_passed = complete_external_cohort and all(
        bool(threshold["passed"]) for threshold in thresholds.values()
    )
    external_reasons: list[str] = []
    if len(human_sessions) < minimum_human_sessions:
        external_reasons.append(
            f"requires {minimum_human_sessions} valid authentic human sessions; found {len(human_sessions)}"
        )
    if len(joined) < minimum_human_sessions:
        external_reasons.append(
            f"requires {minimum_human_sessions} matching structured observations; found {len(joined)}"
        )
    if invalid_session_count:
        external_reasons.append(f"{invalid_session_count} invalid session records")
    if duplicate_sessions:
        external_reasons.append(f"{duplicate_sessions} duplicate session records")
    if invalid_observation_count:
        external_reasons.append(f"{invalid_observation_count} invalid observation records")
    if duplicate_observations:
        external_reasons.append(f"{duplicate_observations} duplicate observation records")
    if excluded_cohort_count:
        external_reasons.append(f"{excluded_cohort_count} human sessions belong to another build/content cohort")
    if blocking_issues:
        external_reasons.append(f"{len(blocking_issues)} p0/p1 or explicit release-blocking issues")
    if complete_external_cohort:
        for name, threshold in thresholds.items():
            if not threshold["passed"]:
                external_reasons.append(f"release threshold failed: {name}")
    external_reasons.extend(attestation_result["reasons"])
    external_gate = {
        "passed": (
            thresholds_passed
            and integrity_failures == 0
            and not blocking_issues
            and attestation_result["approved"]
        ),
        "required_human_sessions": minimum_human_sessions,
        "human_sessions": len(human_sessions),
        "synthetic_sessions": synthetic_count,
        "joined_observations": len(joined),
        "synthetic_observations": synthetic_observations,
        "excluded_cohort_sessions": excluded_cohort_count,
        "invalid_sessions": invalid_session_count,
        "session_violations": session_violation_count,
        "duplicate_sessions": duplicate_sessions,
        "invalid_observations": invalid_observation_count,
        "observation_violations": observation_violation_count,
        "duplicate_observations": duplicate_observations,
        "complete_cohort": complete_external_cohort,
        "blocking_issues": blocking_issues,
        "attestation": attestation_result,
        "thresholds": thresholds,
        "reasons": external_reasons,
    }

    hard_repository_failure = not matrix_validation.passed or bool(failed_seeds)
    if hard_repository_failure or integrity_failures or blocking_issues:
        state = M1_NO_GO
    elif complete_external_cohort and not thresholds_passed:
        state = M1_NO_GO
    elif not repository_gate["passed"]:
        state = M1_CANDIDATE
    elif not complete_external_cohort:
        state = M1_CANDIDATE
    elif not external_gate["passed"]:
        state = M1_CANDIDATE
    else:
        state = M1_GO

    tuning_input = _build_tuning_input(
        cohort,
        runs,
        human_sessions,
        joined,
        thresholds,
        complete_external_cohort and integrity_failures == 0,
    )
    reasons = tuple(repository_reasons + external_reasons)
    return M1Decision(state, cohort, repository_gate, external_gate, tuning_input, reasons)


def render_release_report(decision: M1Decision) -> str:
    repository = decision.repository_gate
    external = decision.external_gate
    tuning = decision.tuning_input
    threshold_rows = []
    for name, threshold in external["thresholds"].items():
        actual = threshold["actual"]
        target = threshold["target"]
        if threshold["passed"]:
            result = "PASS"
        elif external["complete_cohort"]:
            result = "FAIL"
        else:
            result = "PENDING"
        threshold_rows.append(
            f"| `{name}` | {actual:.1%} | {threshold['comparison']} {target:.1%} | "
            f"{result} |"
        )
    reasons = "\n".join(f"- {reason}" for reason in decision.reasons) or "- 无。"
    blocked = "\n".join(f"- {item}" for item in tuning["blocked_claims"]) or "- 无。"
    signatures = "\n".join(
        f"- `{item['code']}`: {item['count']}"
        for item in tuning["dominant_failure_signatures"]
    ) or "- 当前没有足够的结构化失败签名。"
    evidence = _mapping(repository.get("evidence"))
    attestation = _mapping(external.get("attestation"))
    if repository["passed"]:
        repository_status = "PASS"
    elif repository["matrix_valid"] and not repository["failed_seeds"]:
        repository_status = "NON-RELEASE"
    else:
        repository_status = "FAIL"
    if decision.state == M1_GO:
        retention_note = (
            f"- 状态为 `{M1_GO}`：正式仓库证据、完整真人 cohort、独立证明与全部阈值均已通过。"
        )
    elif decision.state == M1_NO_GO:
        retention_note = (
            f"- 状态保持 `{M1_NO_GO}`，直到阻断项修复并以新的干净 cohort 重跑全部正式证据；"
            "旧 cohort 不得拼接复用。"
        )
    else:
        retention_note = (
            f"- 状态保持 `{M1_CANDIDATE}`，直到正式干净 Seed Matrix、真实 20 局和独立外部证明全部齐备；"
            "Candidate 不等于放行。"
        )
    return f"""# Plane Walker M1 放行报告

- Status: {decision.state}
- Evidence Schema: M1 seed matrix `{SEED_MATRIX_SCHEMA}` / playtest session `1.0.0` / observation `{OBSERVATION_SCHEMA}` / external attestation `{EXTERNAL_ATTESTATION_SCHEMA}`
- Build Version: `{decision.cohort.get('build_version', 'unknown')}`
- Commit: `{decision.cohort.get('commit', 'unknown')}`
- Content Version: `{decision.cohort.get('content_version', 'unknown')}`
- Evidence Origin: `{evidence.get('evidence_origin', 'unknown')}`
- Evidence Classification: `{evidence.get('classification', 'unknown')}`
- Probe Version: `{evidence.get('probe_version', 'unknown')}`
- Worktree Clean: `{str(evidence.get('worktree_clean', False)).lower()}`
- Tree Digest: `{evidence.get('tree_digest', 'unknown')}`
- Probe Digest: `{evidence.get('probe_digest', 'unknown')}`
- Godot Version: `{evidence.get('godot_version', 'unknown')}`
- Content Digest: `{evidence.get('content_digest', 'unknown')}`

## 正式结论

**{decision.state}**

30 Seed 仓库门禁：**{repository_status}**；真实外部试玩：**{external['human_sessions']} / {external['required_human_sessions']}**；匹配结构化观察：**{external['joined_observations']} / {external['required_human_sessions']}**。

Synthetic 数据只用于验证工具、稳定性和确定性，永久不计入真实玩家门禁。当前证据不足时，不得据此声称手感、公平性或重玩意愿已验证。

## 30 Seed 稳定性

- Matrix digest: `{repository['matrix_digest']}`
- Seed records: {repository['seed_count']}
- Failed seeds: {len(repository['failed_seeds'])}
- Live Godot verification: {str(repository['live_runtime_verified']).lower()}
- Gate: {repository_status}
- Release eligible: {str(repository['release_eligible']).lower()}

## 外部试玩与玩法阈值

| 指标 | 实测 | 门槛 | 结果 |
|---|---:|---:|---|
{chr(10).join(threshold_rows)}

独立外部证明：**{'APPROVED' if attestation.get('approved') else 'PENDING/INVALID'}**；证明 ID：`{attestation.get('attestation_id', 'none')}`。

## 调参输入契约

- Schema: `{tuning['schema_version']}`
- Evidence class: `{tuning['evidence_class']}`
- Human tuning authorized: `{str(tuning['human_tuning_authorized']).lower()}`

结构化失败签名：

{signatures}

当前禁止的结论：

{blocked}

## 未满足项与风险

{reasons}

## 保留/回滚说明

- 报告由机器可读 Seed Matrix、已校验会话 JSONL 和已校验观察 JSONL 生成。
- 自由文本、未校验表格和 synthetic fixture 不进入放行计算。
- 数值改动必须引用本报告调参输入中的指标或失败签名，并记录旧值、新值、预期影响和回归测试。
{retention_note}
"""


def _evaluate_thresholds(
    joined: Sequence[tuple[Mapping[str, object], Mapping[str, object]]]
) -> dict:
    completed = [
        (session, observation)
        for session, observation in joined
        if _mapping(session.get("terminal_result")).get("outcome") == "completed"
    ]
    duration_in_target = sum(
        1
        for session, _ in completed
        if 480_000 <= _safe_int(_mapping(session.get("terminal_result")).get("duration_ms")) <= 720_000
    )
    count = len(joined)
    stop_used = sum(1 for _, item in joined if _mapping(item.get("time_abilities")).get("time_stop_used") is True)
    rewind_used = sum(1 for _, item in joined if _mapping(item.get("time_abilities")).get("time_rewind_used") is True)
    build_described = sum(1 for _, item in joined if _mapping(item.get("comprehension")).get("build_described") is True)
    boss_interactions = sum(
        1
        for _, item in joined
        if _safe_int(_mapping(item.get("comprehension")).get("boss_time_interactions_identified")) >= 2
    )
    unexplained = sum(
        1
        for _, item in joined
        if _mapping(item.get("experience")).get("unexplained_damage_or_death") is True
    )
    responsive = sum(
        1
        for _, item in joined
        if _safe_int(_mapping(item.get("experience")).get("responsiveness_rating")) >= 4
    )
    replay = sum(
        1
        for _, item in joined
        if _mapping(item.get("experience")).get("replay_intent") in ("restarted", "would_replay")
    )
    return {
        "human_completion_rate": _threshold(len(completed), count, 0.80, ">="),
        "successful_run_duration_8_12_rate": _threshold(duration_in_target, len(completed), 0.80, ">="),
        "time_stop_usage_rate": _threshold(stop_used, count, 0.80, ">="),
        "time_rewind_usage_rate": _threshold(rewind_used, count, 0.80, ">="),
        "build_comprehension_rate": _threshold(build_described, count, 0.80, ">="),
        "boss_time_interactions_rate": _threshold(boss_interactions, count, 0.80, ">="),
        "unexplained_harm_rate": _threshold(unexplained, count, 0.10, "<"),
        "responsiveness_4plus_rate": _threshold(responsive, count, 0.80, ">="),
        "replay_intent_rate": _threshold(replay, count, 0.60, ">="),
    }


def _threshold(numerator: int, denominator: int, target: float, comparison: str) -> dict:
    actual = round(numerator / denominator, 4) if denominator else 0.0
    passed = denominator > 0 and (actual >= target if comparison == ">=" else actual < target)
    return {
        "numerator": numerator,
        "denominator": denominator,
        "actual": actual,
        "target": target,
        "comparison": comparison,
        "passed": passed,
    }


def _build_tuning_input(
    cohort: Mapping[str, object],
    runs: Sequence[object],
    human_sessions: Sequence[Mapping[str, object]],
    joined: Sequence[tuple[Mapping[str, object], Mapping[str, object]]],
    thresholds: Mapping[str, Mapping[str, object]],
    human_tuning_authorized: bool,
) -> dict:
    signatures: Counter[str] = Counter()
    for run in runs:
        if isinstance(run, dict):
            for code in run.get("failure_codes", []):
                signatures[f"seed:{code}"] += 1
    for session in human_sessions:
        for failure in session.get("failures", []):
            if isinstance(failure, dict):
                signatures[f"human:{failure.get('code', 'unknown')}"] += 1
    for _, observation in joined:
        for issue in observation.get("issues", []):
            if isinstance(issue, dict):
                signatures[f"observation:{issue.get('code', 'unknown')}"] += 1
    blocked_claims = []
    if not human_tuning_authorized:
        blocked_claims.extend(
            [
                "手感或响应性已经达到正式放行标准",
                "受伤、公平性与死亡原因已被真实玩家验证",
                "构筑理解、Boss 时间交互与重玩意愿已被验证",
                "基于 synthetic 数据进行体验型数值调优",
            ]
        )
    return {
        "schema_version": TUNING_INPUT_SCHEMA,
        "cohort": dict(cohort),
        "evidence_class": "human_tuning_cohort" if human_tuning_authorized else "repository_stability_only",
        "human_tuning_authorized": human_tuning_authorized,
        "human_sessions": len(human_sessions),
        "joined_observations": len(joined),
        "threshold_metrics": {name: dict(value) for name, value in thresholds.items()},
        "dominant_failure_signatures": [
            {"code": code, "count": count}
            for code, count in sorted(signatures.items(), key=lambda item: (-item[1], item[0]))
        ],
        "permitted_actions": [
            "repair deterministic crashes, script errors, leaks, soft locks, or digest drift",
            "adjust numeric gameplay values only when a recorded metric or failure signature identifies the problem",
            "record old value, new value, expected effect, evidence, and regression test for every retained change",
        ],
        "blocked_claims": blocked_claims,
    }


def _validate_observation_evidence(value: object, errors: list[ObservationViolation]) -> None:
    path = "$.evidence"
    evidence = _expect_mapping(value, path, errors)
    if evidence is None:
        return
    fields = frozenset({"source", "synthetic", "collection_method"})
    _require_fields(evidence, fields, path, errors)
    _reject_extra_fields(evidence, fields, path, errors)
    source = evidence.get("source")
    synthetic = evidence.get("synthetic")
    method = evidence.get("collection_method")
    if source == "human" and (synthetic is not False or method not in HUMAN_COLLECTION_METHODS):
        errors.append(ObservationViolation("evidence-mismatch", path, "human observation must be non-synthetic and directly observed"))
    elif source == "synthetic" and (synthetic is not True or method not in SYNTHETIC_COLLECTION_METHODS):
        errors.append(ObservationViolation("evidence-mismatch", path, "synthetic observation must remain marked synthetic"))
    elif source not in ("human", "synthetic"):
        errors.append(ObservationViolation("invalid-enum", f"{path}.source", "expected human or synthetic"))


def _validate_time_abilities(value: object, errors: list[ObservationViolation]) -> None:
    path = "$.time_abilities"
    item = _expect_mapping(value, path, errors)
    if item is None:
        return
    fields = frozenset({"time_stop_used", "time_rewind_used"})
    _require_fields(item, fields, path, errors)
    _reject_extra_fields(item, fields, path, errors)
    for field in fields:
        if not isinstance(item.get(field), bool):
            errors.append(ObservationViolation("invalid-type", f"{path}.{field}", "expected boolean"))


def _validate_comprehension(value: object, errors: list[ObservationViolation]) -> None:
    path = "$.comprehension"
    item = _expect_mapping(value, path, errors)
    if item is None:
        return
    fields = frozenset({"build_described", "boss_time_interactions_identified"})
    _require_fields(item, fields, path, errors)
    _reject_extra_fields(item, fields, path, errors)
    if not isinstance(item.get("build_described"), bool):
        errors.append(ObservationViolation("invalid-type", f"{path}.build_described", "expected boolean"))
    interactions = item.get("boss_time_interactions_identified")
    if isinstance(interactions, bool) or not isinstance(interactions, int) or not 0 <= interactions <= 10:
        errors.append(ObservationViolation("out-of-range", f"{path}.boss_time_interactions_identified", "expected integer from 0 to 10"))


def _validate_experience(value: object, errors: list[ObservationViolation]) -> None:
    path = "$.experience"
    item = _expect_mapping(value, path, errors)
    if item is None:
        return
    fields = frozenset({"unexplained_damage_or_death", "responsiveness_rating", "replay_intent"})
    _require_fields(item, fields, path, errors)
    _reject_extra_fields(item, fields, path, errors)
    if not isinstance(item.get("unexplained_damage_or_death"), bool):
        errors.append(ObservationViolation("invalid-type", f"{path}.unexplained_damage_or_death", "expected boolean"))
    rating = item.get("responsiveness_rating")
    if isinstance(rating, bool) or not isinstance(rating, int) or not 1 <= rating <= 5:
        errors.append(ObservationViolation("out-of-range", f"{path}.responsiveness_rating", "expected integer from 1 to 5"))
    if item.get("replay_intent") not in REPLAY_INTENTS:
        errors.append(ObservationViolation("invalid-enum", f"{path}.replay_intent", "unsupported replay intent"))


def _validate_issues(value: object, errors: list[ObservationViolation]) -> None:
    if not isinstance(value, list):
        errors.append(ObservationViolation("invalid-type", "$.issues", "expected array"))
        return
    fields = frozenset({"code", "severity", "system", "room_index", "blocks_release"})
    for index, raw_issue in enumerate(value):
        path = f"$.issues[{index}]"
        issue = _expect_mapping(raw_issue, path, errors)
        if issue is None:
            continue
        _require_fields(issue, fields, path, errors)
        _reject_extra_fields(issue, fields, path, errors)
        for field in ("code", "system"):
            text = issue.get(field)
            if not isinstance(text, str) or IDENTIFIER_RE.fullmatch(text) is None:
                errors.append(ObservationViolation("invalid-identifier", f"{path}.{field}", "expected lowercase identifier"))
        if issue.get("severity") not in ISSUE_SEVERITIES:
            errors.append(ObservationViolation("invalid-enum", f"{path}.severity", "expected p0, p1, p2, or p3"))
        room_index = issue.get("room_index")
        if isinstance(room_index, bool) or not isinstance(room_index, int) or not -1 <= room_index <= 4:
            errors.append(ObservationViolation("out-of-range", f"{path}.room_index", "expected -1 through 4"))
        if not isinstance(issue.get("blocks_release"), bool):
            errors.append(ObservationViolation("invalid-type", f"{path}.blocks_release", "expected boolean"))


def _validate_matrix_evidence(
    value: object,
    cohort_value: object,
    *,
    verify_repository_artifacts: bool,
) -> tuple[list[str], list[str]]:
    if not isinstance(value, dict):
        return ["evidence must be an object"], ["matrix evidence is not release eligible"]
    reasons: list[str] = []
    release_reasons: list[str] = []
    fields = {
        "evidence_origin",
        "classification",
        "probe_version",
        "worktree_clean",
        "head_commit",
        "tree_digest",
        "probe_digest",
        "godot_version",
        "godot_platform",
        "godot_binary_digest",
        "godot_toolchain_id",
        "content_digest",
        "catalog_content_version",
    }
    missing = fields - value.keys()
    extra = value.keys() - fields
    for field in sorted(missing):
        reasons.append(f"evidence.{field} is required")
    for field in sorted(extra):
        reasons.append(f"evidence.{field} is not allowed")
    origin = value.get("evidence_origin")
    if origin not in ("godot_authoritative_probe", "raw_results_adapter"):
        reasons.append("evidence.evidence_origin is unsupported")
    classification = value.get("classification")
    if classification not in ("release", "non_release_candidate", "non_release_synthetic"):
        reasons.append("evidence.classification is unsupported")
    if value.get("probe_version") != PROBE_VERSION:
        reasons.append(f"evidence.probe_version must be {PROBE_VERSION}")
    if not isinstance(value.get("worktree_clean"), bool):
        reasons.append("evidence.worktree_clean must be boolean")
    head_commit = value.get("head_commit")
    if not isinstance(head_commit, str) or COMMIT_RE.fullmatch(head_commit) is None:
        reasons.append("evidence.head_commit must be 7-40 lowercase hex characters")
    tree_digest = value.get("tree_digest")
    if not isinstance(tree_digest, str) or TREE_DIGEST_RE.fullmatch(tree_digest) is None:
        reasons.append("evidence.tree_digest must be a 40-64 character lowercase hex digest")
    for field in ("probe_digest", "content_digest", "godot_binary_digest"):
        digest = value.get(field)
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            reasons.append(f"evidence.{field} must be a lowercase SHA-256 digest")
    if not isinstance(value.get("godot_version"), str) or not str(value.get("godot_version")).strip():
        reasons.append("evidence.godot_version must be a non-blank string")
    for field in ("godot_platform", "godot_toolchain_id"):
        if not isinstance(value.get(field), str) or not str(value.get(field)).strip():
            reasons.append(f"evidence.{field} must be a non-blank string")
    if not isinstance(value.get("catalog_content_version"), str) or not str(value.get("catalog_content_version")).strip():
        reasons.append("evidence.catalog_content_version must be a non-blank string")
    if origin == "raw_results_adapter" and classification != "non_release_synthetic":
        reasons.append("raw_results_adapter evidence must remain non_release_synthetic")
    if origin == "godot_authoritative_probe" and value.get("godot_version") == "not_executed":
        reasons.append("godot_authoritative_probe evidence must record an executed Godot version")

    cohort = cohort_value if isinstance(cohort_value, dict) else {}
    if origin != "godot_authoritative_probe":
        release_reasons.append("formal repository gate requires evidence_origin godot_authoritative_probe")
    if classification != "release":
        release_reasons.append("formal repository gate requires release evidence classification")
    if value.get("worktree_clean") is not True:
        release_reasons.append("formal repository gate requires a clean worktree")
    if head_commit != cohort.get("commit"):
        release_reasons.append("evidence head_commit must equal cohort.commit")
    if value.get("catalog_content_version") != cohort.get("content_version"):
        release_reasons.append("catalog content version must equal cohort.content_version")
    if (
        verify_repository_artifacts
        and origin == "godot_authoritative_probe"
        and classification == "release"
    ):
        release_reasons.extend(_verify_repository_evidence(value, cohort))
    return reasons, release_reasons


def _verify_repository_evidence(
    evidence: Mapping[str, object],
    cohort: Mapping[str, object],
) -> list[str]:
    reasons: list[str] = []
    commit = str(cohort.get("commit", ""))
    tree = _git_text("rev-parse", f"{commit}^{{tree}}")
    if tree is None:
        return ["cohort commit is not available in the repository"]
    if evidence.get("tree_digest") != tree:
        reasons.append("evidence tree_digest does not match cohort.commit")

    probe_bytes = _git_blob(commit, "tools/m1/seed_matrix_probe.gd")
    catalog_bytes = _git_blob(commit, "data/encounters/m1_encounters.json")
    toolchain_bytes = _git_blob(commit, "data/toolchain/m1_godot_toolchains.json")
    if probe_bytes is None:
        reasons.append("cohort commit does not contain the M1 seed probe")
    elif evidence.get("probe_digest") != hashlib.sha256(probe_bytes).hexdigest():
        reasons.append("evidence probe_digest does not match cohort.commit")
    if catalog_bytes is None:
        reasons.append("cohort commit does not contain the encounter catalog")
    else:
        if evidence.get("content_digest") != hashlib.sha256(catalog_bytes).hexdigest():
            reasons.append("evidence content_digest does not match cohort.commit")
        try:
            catalog = json.loads(catalog_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            reasons.append("cohort encounter catalog is not valid UTF-8 JSON")
        else:
            if catalog.get("plan_id") != cohort.get("content_version"):
                reasons.append("cohort content_version does not match the committed catalog plan_id")

    if toolchain_bytes is None:
        reasons.append("cohort commit does not contain the trusted Godot toolchain manifest")
    else:
        try:
            manifest = json.loads(toolchain_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            reasons.append("trusted Godot toolchain manifest is invalid")
        else:
            entries = manifest.get("toolchains", []) if isinstance(manifest, dict) else []
            matched = any(
                isinstance(entry, dict)
                and entry.get("id") == evidence.get("godot_toolchain_id")
                and entry.get("platform") == evidence.get("godot_platform")
                and entry.get("version") == evidence.get("godot_version")
                and entry.get("sha256") == evidence.get("godot_binary_digest")
                for entry in entries
            )
            if not matched:
                reasons.append("Godot binary fingerprint is not trusted by cohort.commit")
    return reasons


def _git_text(*arguments: str) -> str | None:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    value = completed.stdout.strip().lower()
    return value if completed.returncode == 0 and value else None


def _git_blob(commit: str, relative_path: str) -> bytes | None:
    completed = subprocess.run(
        ["git", "show", f"{commit}:{relative_path}"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        check=False,
    )
    return completed.stdout if completed.returncode == 0 else None


def _validate_run_shape(run: Mapping[str, object], path: str, reasons: list[str]) -> None:
    if run.get("room_sequence") != [1, 2, 3, 4, 5]:
        reasons.append(f"{path}.room_sequence must be exactly [1, 2, 3, 4, 5]")

    encounters = run.get("encounter_ids")
    if not isinstance(encounters, list) or len(encounters) != 5:
        reasons.append(f"{path}.encounter_ids must contain exactly five entries")
    elif any(not isinstance(value, str) or not value.strip() for value in encounters):
        reasons.append(f"{path}.encounter_ids entries must be non-blank strings")
    elif len(set(encounters)) != 5:
        reasons.append(f"{path}.encounter_ids must be unique across the five rooms")

    spawns = run.get("spawn_sequences")
    if not isinstance(spawns, list) or len(spawns) != 5:
        reasons.append(f"{path}.spawn_sequences must contain exactly five room entries")
    else:
        for room_index, room_waves in enumerate(spawns):
            room_path = f"{path}.spawn_sequences[{room_index}]"
            if not isinstance(room_waves, list) or not room_waves:
                reasons.append(f"{room_path} must contain at least one wave")
                continue
            for wave_index, wave in enumerate(room_waves):
                wave_path = f"{room_path}[{wave_index}]"
                if not isinstance(wave, list) or not wave:
                    reasons.append(f"{wave_path} must contain at least one enemy")
                elif any(not isinstance(enemy, str) or not enemy.strip() for enemy in wave):
                    reasons.append(f"{wave_path} enemy ids must be non-blank strings")

    offers = run.get("reward_offers")
    if not isinstance(offers, list) or len(offers) != 4:
        reasons.append(f"{path}.reward_offers must contain exactly four offers")
    elif any(
        not isinstance(offer, list)
        or len(offer) != 3
        or any(not isinstance(option, str) or not option.strip() for option in offer)
        or len(set(offer)) != 3
        for offer in offers
    ):
        reasons.append(f"{path}.reward_offers must contain exactly three unique option ids")

    choices = run.get("selected_choices")
    if not isinstance(choices, list) or len(choices) != 4:
        reasons.append(f"{path}.selected_choices must contain exactly four choices")
        choices = []
    elif any(not isinstance(choice, str) or not choice.strip() for choice in choices):
        reasons.append(f"{path}.selected_choices entries must be non-blank strings")
    if isinstance(offers, list) and len(offers) == 4 and len(choices) == 4:
        for choice_index, choice in enumerate(choices):
            offer = offers[choice_index]
            if isinstance(offer, list) and choice not in offer:
                reasons.append(
                    f"{path}.selected_choices[{choice_index}] must belong to reward_offers[{choice_index}]"
                )

    snapshots = run.get("choice_snapshots")
    revisions: list[int] = []
    previous_history_size = 0
    previous_build: dict = {
        "items": [],
        "blessings": [],
        "curses": [],
        "talents": [],
        "reward_history": [],
        "archetypes": {},
        "dominant_archetype": "",
    }
    build_fields = {
        "items",
        "blessings",
        "curses",
        "talents",
        "reward_history",
        "archetypes",
        "dominant_archetype",
    }
    if not isinstance(snapshots, list) or len(snapshots) != 4:
        reasons.append(f"{path}.choice_snapshots must contain exactly four post-choice snapshots")
    else:
        for snapshot_index, snapshot in enumerate(snapshots):
            snapshot_path = f"{path}.choice_snapshots[{snapshot_index}]"
            if not isinstance(snapshot, dict):
                reasons.append(f"{snapshot_path} must be an object")
                continue
            if set(snapshot) != {"choice_id", "revision", "outcome", "build"}:
                reasons.append(f"{snapshot_path} must contain only choice_id, revision, outcome, and build")
            if snapshot_index < len(choices) and snapshot.get("choice_id") != choices[snapshot_index]:
                reasons.append(f"{snapshot_path}.choice_id must match selected_choices")
            revision = snapshot.get("revision")
            if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
                reasons.append(f"{snapshot_path}.revision must be a non-negative integer")
            else:
                revisions.append(revision)
            outcome = snapshot.get("outcome")
            if outcome not in ("applied", "no_state_change"):
                reasons.append(f"{snapshot_path}.outcome must be applied or no_state_change")
            build = snapshot.get("build")
            if not isinstance(build, dict):
                reasons.append(f"{snapshot_path}.build must be a normalized object")
                continue
            if set(build) != build_fields:
                reasons.append(f"{snapshot_path}.build must contain the normalized RunBuildState fields")
                continue
            for field in ("items", "blessings", "curses", "talents", "reward_history"):
                if not isinstance(build.get(field), list):
                    reasons.append(f"{snapshot_path}.build.{field} must be an array")
            archetypes = build.get("archetypes")
            if not isinstance(archetypes, dict):
                reasons.append(f"{snapshot_path}.build.archetypes must be an object")
            elif any(
                not isinstance(key, str)
                or not key
                or isinstance(value, bool)
                or not isinstance(value, int)
                or value < 0
                for key, value in archetypes.items()
            ):
                reasons.append(f"{snapshot_path}.build.archetypes must contain non-negative integer counts")
            if not isinstance(build.get("dominant_archetype"), str):
                reasons.append(f"{snapshot_path}.build.dominant_archetype must be a string")
            history = build.get("reward_history")
            if not isinstance(history, list):
                continue
            if outcome == "no_state_change":
                if snapshot.get("choice_id") != "decline_contract":
                    reasons.append(f"{snapshot_path}.no_state_change is only valid for decline_contract")
                if build != previous_build:
                    reasons.append(f"{snapshot_path}.no_state_change must preserve the complete build snapshot")
            else:
                if len(history) != previous_history_size + 1:
                    reasons.append(f"{snapshot_path}.applied must append exactly one reward history entry")
                elif not isinstance(history[-1], dict) or history[-1].get("id") != snapshot.get("choice_id"):
                    reasons.append(f"{snapshot_path}.reward_history must end with the selected choice id")
                previous_history = previous_build["reward_history"]
                if history[:len(previous_history)] != previous_history:
                    reasons.append(f"{snapshot_path}.reward_history must preserve all prior entries")
                category_fields = {
                    "item": "items",
                    "blessing": "blessings",
                    "curse": "curses",
                    "talent": "talents",
                }
                selected_entry = history[-1] if isinstance(history[-1], dict) else {}
                selected_category = selected_entry.get("category")
                selected_field = category_fields.get(selected_category)
                if selected_field is None:
                    reasons.append(f"{snapshot_path}.reward_history must declare a supported category")
                previously_owned = {
                    str(content_id)
                    for field in ("items", "blessings", "curses", "talents")
                    for content_id in previous_build[field]
                }
                if snapshot.get("choice_id") in previously_owned:
                    reasons.append(f"{snapshot_path}.selected choice must not already be owned")
                current_owned: list[str] = []
                for field in ("items", "blessings", "curses", "talents"):
                    values = build.get(field)
                    if isinstance(values, list):
                        current_owned.extend(str(content_id) for content_id in values)
                        previous_values = previous_build[field]
                        expected_values = list(previous_values)
                        if field == selected_field:
                            expected_values.append(snapshot.get("choice_id"))
                        if values != expected_values:
                            reasons.append(
                                f"{snapshot_path}.build.{field} must equal the exact recorded reward transition"
                            )
                if len(current_owned) != len(set(current_owned)):
                    reasons.append(f"{snapshot_path}.typed build ids must remain globally unique")
                if isinstance(archetypes, dict):
                    expected_archetypes = dict(previous_build["archetypes"])
                    selected_archetype = selected_entry.get("archetype", "")
                    if not isinstance(selected_archetype, str):
                        reasons.append(f"{snapshot_path}.reward_history archetype must be a string")
                    elif selected_category != "curse" and selected_archetype:
                        expected_archetypes[selected_archetype] = int(
                            expected_archetypes.get(selected_archetype, 0)
                        ) + 1
                    if archetypes != expected_archetypes:
                        reasons.append(
                            f"{snapshot_path}.build.archetypes must equal the exact recorded reward transition"
                        )
                    dominant = build.get("dominant_archetype")
                    if expected_archetypes:
                        expected_dominant = ""
                        best_count = -1
                        for archetype_id, count in expected_archetypes.items():
                            if count > best_count:
                                expected_dominant = archetype_id
                                best_count = count
                        if dominant != expected_dominant:
                            reasons.append(
                                f"{snapshot_path}.build.dominant_archetype must match the runtime tie-break"
                            )
                    elif dominant != "":
                        reasons.append(
                            f"{snapshot_path}.build.dominant_archetype must be empty without archetype counts"
                        )
            previous_history_size = len(history)
            previous_build = _deep_copy(build)
        if len(revisions) == 4 and any(later <= earlier for earlier, later in zip(revisions, revisions[1:])):
            reasons.append(f"{path}.choice_snapshots revisions must increase strictly")

    if run.get("terminal_state") != "victory":
        reasons.append(f"{path}.terminal_state must be victory")
    failure_codes = run.get("failure_codes")
    if isinstance(failure_codes, list) and failure_codes:
        reasons.append(f"{path}.failure_codes must be empty")
    duration = run.get("duration_proxy_ms")
    if isinstance(duration, int) and not isinstance(duration, bool) and duration <= 0:
        reasons.append(f"{path}.duration_proxy_ms must be positive")


def count_invalid_records(violations: Sequence[object]) -> int:
    lines = {
        int(getattr(item, "line", 0))
        for item in violations
        if isinstance(getattr(item, "line", 0), int) and int(getattr(item, "line", 0)) > 0
    }
    has_unscoped = any(
        not isinstance(getattr(item, "line", 0), int)
        or int(getattr(item, "line", 0)) <= 0
        for item in violations
    )
    return len(lines) + (1 if has_unscoped else 0)


def _blocking_issues(
    joined: Sequence[tuple[Mapping[str, object], Mapping[str, object]]]
) -> list[dict]:
    result: list[dict] = []
    for session, observation in joined:
        for issue in observation.get("issues", []):
            if not isinstance(issue, dict):
                continue
            if issue.get("severity") in ("p0", "p1") or issue.get("blocks_release") is True:
                result.append(
                    {
                        "session_id": session.get("session_id"),
                        "code": issue.get("code"),
                        "severity": issue.get("severity"),
                        "system": issue.get("system"),
                        "room_index": issue.get("room_index"),
                        "blocks_release": issue.get("blocks_release"),
                    }
                )
    return result


def _evaluate_attestation(
    value: object,
    *,
    cohort: Mapping[str, object],
    joined_session_ids: Sequence[str],
    minimum_human_sessions: int,
    matrix_digest: str,
    sessions_digest: str,
    observations_digest: str,
    trust_store: Mapping[str, object] | None,
) -> dict:
    if value is None:
        return {
            "approved": False,
            "attestation_id": "",
            "key_id": "",
            "signature_verified": False,
            "attested_sessions": 0,
            "reasons": ["signed independent external attestation is required for M1 Go"],
        }
    reasons: list[str] = []
    if not isinstance(value, dict):
        reasons.append("external attestation must be an object")
        value = {}
    fields = {
        "schema_version",
        "attestation_id",
        "cohort",
        "attestor",
        "approval",
        "evidence",
        "session_ids",
        "signature",
    }
    for field in sorted(fields - value.keys()):
        reasons.append(f"attestation.{field} is required")
    for field in sorted(value.keys() - fields):
        reasons.append(f"attestation.{field} is not allowed")
    if value.get("schema_version") != EXTERNAL_ATTESTATION_SCHEMA:
        reasons.append(f"attestation.schema_version must be {EXTERNAL_ATTESTATION_SCHEMA}")
    attestation_id = value.get("attestation_id")
    if not isinstance(attestation_id, str) or IDENTIFIER_RE.fullmatch(attestation_id) is None:
        reasons.append("attestation.attestation_id must be a lowercase identifier")
    if value.get("cohort") != dict(cohort):
        reasons.append("attestation.cohort must exactly match the seed matrix cohort")
    attestor = _mapping(value.get("attestor"))
    if set(attestor) != {"key_id", "role", "independent_from_development"}:
        reasons.append("attestation.attestor must contain key_id, role, and independent_from_development")
    key_id = attestor.get("key_id")
    if not isinstance(key_id, str) or IDENTIFIER_RE.fullmatch(key_id) is None:
        reasons.append("attestation.attestor.key_id must be a lowercase identifier")
    if attestor.get("role") != "external_playtest_coordinator":
        reasons.append("attestation.attestor.role must be external_playtest_coordinator")
    if attestor.get("independent_from_development") is not True:
        reasons.append("attestation must be approved independently from development")
    approval = _mapping(value.get("approval"))
    if set(approval) != {"status", "statement", "approved_at_utc"}:
        reasons.append("attestation.approval must contain status, statement, and approved_at_utc")
    if approval.get("status") != "approved":
        reasons.append("attestation approval status must be approved")
    if approval.get("statement") != "authentic_human_evidence_verified":
        reasons.append("attestation approval statement is unsupported")
    approved_at = approval.get("approved_at_utc")
    if not isinstance(approved_at, str) or UTC_TIMESTAMP_RE.fullmatch(approved_at) is None:
        reasons.append("attestation approved_at_utc must be a UTC timestamp")
    evidence = _mapping(value.get("evidence"))
    expected_evidence = {
        "matrix_digest": matrix_digest,
        "sessions_digest": sessions_digest,
        "observations_digest": observations_digest,
        "session_ids_digest": canonical_digest(sorted(joined_session_ids)),
    }
    if evidence != expected_evidence:
        reasons.append("attestation.evidence must bind the exact matrix, sessions, observations, and session ids")
    session_ids = value.get("session_ids")
    normalized_ids: list[str] = []
    if not isinstance(session_ids, list):
        reasons.append("attestation.session_ids must be an array")
    else:
        normalized_ids = [item for item in session_ids if isinstance(item, str)]
        if len(normalized_ids) != len(session_ids) or any(SESSION_ID_RE.fullmatch(item) is None for item in normalized_ids):
            reasons.append("attestation.session_ids must contain anonymous session ids")
        if len(set(normalized_ids)) != len(normalized_ids):
            reasons.append("attestation.session_ids must be unique")
        if set(normalized_ids) != set(joined_session_ids):
            reasons.append("attestation.session_ids must exactly match the joined human cohort")
        if len(normalized_ids) < minimum_human_sessions:
            reasons.append(f"attestation must cover at least {minimum_human_sessions} joined sessions")
    signature = _mapping(value.get("signature"))
    if set(signature) != {"algorithm", "value_base64"}:
        reasons.append("attestation.signature must contain algorithm and value_base64")
    if signature.get("algorithm") != "rsa-sha256":
        reasons.append("attestation.signature.algorithm must be rsa-sha256")
    signature_verified = False
    if not reasons:
        signature_verified, signature_reason = _verify_attestation_signature(
            value,
            key_id=str(key_id),
            cohort_commit=str(cohort.get("commit", "")),
            trust_store=trust_store,
        )
        if not signature_verified:
            reasons.append(signature_reason)
    return {
        "approved": not reasons,
        "attestation_id": attestation_id if isinstance(attestation_id, str) else "",
        "key_id": key_id if isinstance(key_id, str) else "",
        "signature_verified": signature_verified,
        "attested_sessions": len(set(normalized_ids)),
        "reasons": reasons,
    }


def _verify_attestation_signature(
    attestation: Mapping[str, object],
    *,
    key_id: str,
    cohort_commit: str,
    trust_store: Mapping[str, object] | None,
) -> tuple[bool, str]:
    injected_trust = trust_store is not None
    store = trust_store if injected_trust else _load_attestor_trust_store(cohort_commit)
    keys = store.get("keys") if isinstance(store, Mapping) else None
    if not isinstance(keys, list):
        return False, "external attestor trust store is invalid"
    trusted_key: Mapping[str, object] | None = None
    for raw_key in keys:
        if (
            isinstance(raw_key, Mapping)
            and raw_key.get("key_id") == key_id
            and raw_key.get("active") is True
            and raw_key.get("algorithm") == "rsa-sha256"
        ):
            trusted_key = raw_key
            break
    if trusted_key is None:
        return False, f"attestor key is not trusted: {key_id}"
    public_key_value = trusted_key.get("public_key_path")
    if not isinstance(public_key_value, str) or not public_key_value.strip():
        return False, "trusted attestor public key path is missing"
    public_key_bytes: bytes | None = None
    public_key_path = Path(public_key_value)
    if injected_trust:
        if not public_key_path.is_absolute():
            public_key_path = PROJECT_ROOT / public_key_path
        if not public_key_path.is_file():
            return False, f"trusted attestor public key is unavailable: {public_key_path}"
    else:
        if public_key_path.is_absolute() or ".." in public_key_path.parts:
            return False, "tracked attestor public key path must be repository-relative"
        public_key_bytes = _git_blob(cohort_commit, public_key_path.as_posix())
        if public_key_bytes is None:
            return False, "tracked attestor public key is unavailable in cohort.commit"

    signature = _mapping(attestation.get("signature"))
    encoded_signature = signature.get("value_base64")
    if not isinstance(encoded_signature, str):
        return False, "attestation signature is missing"
    try:
        signature_bytes = base64.b64decode(encoded_signature, validate=True)
    except (ValueError, TypeError):
        return False, "attestation signature is not valid base64"
    payload = {
        key: _deep_copy(value)
        for key, value in attestation.items()
        if key != "signature"
    }
    payload_bytes = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    with tempfile.TemporaryDirectory(prefix="planewalker-m1-attestation-") as temp_dir:
        payload_path = Path(temp_dir) / "payload.json"
        signature_path = Path(temp_dir) / "signature.bin"
        verification_key_path = public_key_path
        if public_key_bytes is not None:
            verification_key_path = Path(temp_dir) / "attestor-public.pem"
            verification_key_path.write_bytes(public_key_bytes)
        payload_path.write_bytes(payload_bytes)
        signature_path.write_bytes(signature_bytes)
        try:
            completed = subprocess.run(
                [
                    "openssl",
                    "dgst",
                    "-sha256",
                    "-verify",
                    str(verification_key_path),
                    "-signature",
                    str(signature_path),
                    str(payload_path),
                ],
                capture_output=True,
                check=False,
                text=True,
            )
        except OSError:
            return False, "OpenSSL is unavailable for attestation verification"
    if completed.returncode != 0:
        return False, "attestation signature verification failed"
    return True, ""


def _load_attestor_trust_store(cohort_commit: str) -> Mapping[str, object]:
    trust_bytes = _git_blob(
        cohort_commit,
        ATTESTOR_TRUST_PATH.relative_to(PROJECT_ROOT).as_posix(),
    )
    if trust_bytes is None:
        return {"keys": []}
    try:
        value = json.loads(trust_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _validate_cohort(value: object) -> list[str]:
    if not isinstance(value, dict):
        return ["cohort must be an object"]
    reasons: list[str] = []
    required = {"build_version", "commit", "content_version"}
    for field in sorted(required - value.keys()):
        reasons.append(f"cohort.{field} is required")
    for field in ("build_version", "content_version"):
        if not isinstance(value.get(field), str) or not str(value.get(field)).strip():
            reasons.append(f"cohort.{field} must be a non-blank string")
    commit = value.get("commit")
    if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit) is None:
        reasons.append("cohort.commit must be 7-40 lowercase hex characters")
    return reasons


def _session_matches_cohort(session: Mapping[str, object], cohort: Mapping[str, object]) -> bool:
    build = _mapping(session.get("build"))
    return (
        build.get("version") == cohort.get("build_version")
        and build.get("commit") == cohort.get("commit")
        and build.get("content_version") == cohort.get("content_version")
    )


def _seed_digest_map(report: Mapping[str, object]) -> dict[int, str]:
    result: dict[int, str] = {}
    runs = report.get("runs", [])
    if not isinstance(runs, list):
        return result
    for run in runs:
        if isinstance(run, dict) and isinstance(run.get("seed"), int) and isinstance(run.get("digest"), str):
            result[int(run["seed"])] = str(run["digest"])
    return result


def _require_fields(value: Mapping[str, object], fields: frozenset[str], path: str, errors: list[ObservationViolation]) -> None:
    for field in sorted(fields - value.keys()):
        errors.append(ObservationViolation("missing-field", f"{path}.{field}", "required field is absent"))


def _reject_extra_fields(value: Mapping[str, object], fields: frozenset[str], path: str, errors: list[ObservationViolation]) -> None:
    for field in sorted(value.keys() - fields):
        errors.append(ObservationViolation("unexpected-field", f"{path}.{field}", "field is not allowed"))


def _expect_mapping(value: object, path: str, errors: list[ObservationViolation]) -> Mapping[str, object] | None:
    if not isinstance(value, dict):
        errors.append(ObservationViolation("invalid-type", path, "expected object"))
        return None
    return value


def _mapping(value: object) -> Mapping[str, object]:
    return value if isinstance(value, dict) else {}


def _safe_int(value: object) -> int:
    return int(value) if isinstance(value, int) and not isinstance(value, bool) else 0


def _deep_copy(value: object) -> object:
    return json.loads(json.dumps(value, ensure_ascii=False))
