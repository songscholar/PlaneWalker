#!/usr/bin/env python3
"""Validation, de-identification, aggregation, and evidence gates for playtests."""

from __future__ import annotations

import copy
import hashlib
import json
import re
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Mapping, Sequence


SCHEMA_VERSION = "1.0.0"
SESSION_ID_RE = re.compile(r"^pws_[0-9a-f]{32}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{7,40}$")
IDENTIFIER_RE = re.compile(r"^[a-z0-9_][a-z0-9_.-]*$")
UTC_TIMESTAMP_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"
)

TOP_LEVEL_FIELDS = frozenset(
    {
        "schema_version",
        "session_id",
        "evidence",
        "build",
        "run",
        "timing",
        "rooms",
        "damage",
        "failures",
        "build_choices",
        "terminal_result",
    }
)
TOP_LEVEL_OPTIONAL_FIELDS = frozenset({"device"})
INPUT_DEVICES = frozenset({"keyboard_mouse", "controller", "mixed", "automation"})
ROOM_TYPES = frozenset({"combat", "elite", "boss", "event", "merchant", "rest"})
ROOM_RESULTS = frozenset({"cleared", "failed", "abandoned", "skipped"})
FAILURE_PHASES = frozenset({"setup", "exploration", "combat", "choice", "boss", "result"})
CHOICE_TYPES = frozenset({"item", "blessing", "curse", "talent", "weapon", "time_ability"})
OUTCOMES = frozenset({"completed", "death", "abandoned", "technical_failure"})
HUMAN_COLLECTION_METHODS = frozenset({"observed_playtest", "imported_observation"})
SYNTHETIC_COLLECTION_METHODS = frozenset({"automated_fixture", "simulation"})
PII_KEYS = frozenset(
    {
        "email",
        "tester_email",
        "participant_email",
        "name",
        "tester_name",
        "participant_name",
        "participant_id",
        "external_user_id",
        "steam_id",
        "discord_id",
        "ip",
        "ip_address",
        "device_id",
        "device_name",
        "hostname",
        "username",
        "user_name",
        "notes",
        "free_text",
    }
)


@dataclass(frozen=True, order=True)
class Violation:
    code: str
    path: str
    message: str
    line: int = 0

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class ImportResult:
    sessions: list[dict]
    violations: list[Violation]


@dataclass(frozen=True)
class EvidenceGateResult:
    passed: bool
    required_human_sessions: int
    human_sessions: int
    synthetic_sessions: int
    invalid_sessions: int
    duplicate_sessions: int
    excluded_sessions: int
    reasons: tuple[str, ...]

    def to_dict(self) -> dict:
        return asdict(self)


def validate_session(session: object) -> list[Violation]:
    violations: list[Violation] = []
    if not isinstance(session, dict):
        return [Violation("invalid-type", "$", "session must be a JSON object")]

    _required_fields(session, TOP_LEVEL_FIELDS, "$", violations)
    _reject_extra_fields(
        session,
        TOP_LEVEL_FIELDS | TOP_LEVEL_OPTIONAL_FIELDS,
        "$",
        violations,
    )

    if session.get("schema_version") != SCHEMA_VERSION:
        violations.append(
            Violation(
                "unsupported-schema-version",
                "$.schema_version",
                f"expected {SCHEMA_VERSION}",
            )
        )

    session_id = session.get("session_id")
    if not isinstance(session_id, str) or SESSION_ID_RE.fullmatch(session_id) is None:
        violations.append(
            Violation(
                "invalid-session-id",
                "$.session_id",
                "expected anonymous pws_ plus 32 lowercase hex characters",
            )
        )

    _validate_evidence(session.get("evidence"), violations)
    _validate_build(session.get("build"), violations)
    _validate_run(session.get("run"), violations)
    _validate_timing(session.get("timing"), violations)
    _validate_rooms(session.get("rooms"), violations)
    _validate_damage(session.get("damage"), violations)
    _validate_failures(session.get("failures"), violations)
    _validate_choices(session.get("build_choices"), violations)
    _validate_terminal_result(session.get("terminal_result"), violations)
    _validate_device(session.get("device"), violations)
    return sorted(violations)


def load_jsonl(path: str | Path) -> ImportResult:
    source_path = Path(path)
    sessions: list[dict] = []
    violations: list[Violation] = []
    seen_ids: set[str] = set()
    try:
        lines = source_path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        return ImportResult([], [Violation("unreadable-file", str(source_path), str(error))])

    for line_number, raw_line in enumerate(lines, start=1):
        if not raw_line.strip():
            continue
        try:
            value = json.loads(raw_line)
        except json.JSONDecodeError as error:
            violations.append(
                Violation("invalid-json", "$", error.msg, line=line_number)
            )
            continue

        line_violations = validate_session(value)
        if line_violations:
            violations.extend(
                Violation(item.code, item.path, item.message, line=line_number)
                for item in line_violations
            )
            continue

        session_id = str(value["session_id"])
        if session_id in seen_ids:
            violations.append(
                Violation(
                    "duplicate-session",
                    "$.session_id",
                    f"session_id {session_id} already appeared in this file",
                    line=line_number,
                )
            )
            continue
        seen_ids.add(session_id)
        sessions.append(value)
    return ImportResult(sessions, sorted(violations))


def deidentify_session(session: Mapping[str, object], *, salt: str) -> dict:
    if not salt:
        raise ValueError("salt must not be blank")
    cleaned = _remove_pii(copy.deepcopy(dict(session)))
    original_id = str(session.get("session_id", ""))
    digest = hashlib.sha256(f"{salt}:{original_id}".encode("utf-8")).hexdigest()[:32]
    cleaned["session_id"] = f"pws_{digest}"
    return cleaned


def summarize_sessions(sessions: Sequence[Mapping[str, object]]) -> dict:
    human = [session for session in sessions if _is_human(session)]
    synthetic_count = sum(1 for session in sessions if _is_synthetic(session))
    outcome_counts = Counter(
        str(_mapping(session.get("terminal_result")).get("outcome", "unknown"))
        for session in human
    )
    failure_counts: Counter[str] = Counter()
    choice_counts: Counter[str] = Counter()
    durations: list[int] = []
    room_durations: list[int] = []
    damage_taken: list[int] = []
    damage_dealt: list[int] = []
    seeds: set[int] = set()

    for session in human:
        timing = _mapping(session.get("timing"))
        damage = _mapping(session.get("damage"))
        run = _mapping(session.get("run"))
        durations.append(_safe_int(timing.get("duration_ms")))
        damage_taken.append(_safe_int(damage.get("taken")))
        damage_dealt.append(_safe_int(damage.get("dealt")))
        seeds.add(_safe_int(run.get("seed")))
        for room in _sequence(session.get("rooms")):
            room_durations.append(_safe_int(_mapping(room).get("duration_ms")))
        for failure in _sequence(session.get("failures")):
            failure_counts[str(_mapping(failure).get("code", "unknown"))] += 1
        for choice in _sequence(session.get("build_choices")):
            choice_data = _mapping(choice)
            key = f"{choice_data.get('choice_type', 'unknown')}:{choice_data.get('choice_id', 'unknown')}"
            choice_counts[key] += 1

    human_count = len(human)
    completed = outcome_counts.get("completed", 0)
    return {
        "schema_version": SCHEMA_VERSION,
        "total_sessions": len(sessions),
        "evidence": {"human": human_count, "synthetic": synthetic_count},
        "human_metrics": {
            "unique_seeds": len(seeds),
            "completion_rate": _ratio(completed, human_count),
            "average_duration_ms": _average(durations),
            "average_room_duration_ms": _average(room_durations),
            "average_damage_dealt": _average(damage_dealt),
            "average_damage_taken": _average(damage_taken),
            "outcomes": dict(sorted(outcome_counts.items())),
            "failure_codes": dict(sorted(failure_counts.items())),
            "build_choices": dict(sorted(choice_counts.items())),
        },
    }


class EvidenceGate:
    def __init__(
        self,
        *,
        minimum_human_sessions: int = 20,
        required_build_version: str | None = None,
        required_commit: str | None = None,
        required_content_version: str | None = None,
    ) -> None:
        if minimum_human_sessions <= 0:
            raise ValueError("minimum_human_sessions must be positive")
        self.minimum_human_sessions = minimum_human_sessions
        self.required_build_version = required_build_version
        self.required_commit = required_commit
        self.required_content_version = required_content_version

    def evaluate(self, sessions: Iterable[Mapping[str, object]]) -> EvidenceGateResult:
        human_count = 0
        synthetic_count = 0
        invalid_count = 0
        duplicate_count = 0
        excluded_count = 0
        seen_ids: set[str] = set()

        for session in sessions:
            violations = validate_session(session)
            if violations:
                invalid_count += 1
                continue
            session_id = str(session["session_id"])
            if session_id in seen_ids:
                duplicate_count += 1
                continue
            seen_ids.add(session_id)

            if _is_synthetic(session):
                synthetic_count += 1
                continue
            if not _matches_cohort(
                session,
                build_version=self.required_build_version,
                commit=self.required_commit,
                content_version=self.required_content_version,
            ):
                excluded_count += 1
                continue
            human_count += 1

        reasons: list[str] = []
        if human_count < self.minimum_human_sessions:
            reasons.append(
                f"requires {self.minimum_human_sessions} unique valid human sessions; found {human_count}"
            )
        if invalid_count:
            reasons.append(f"{invalid_count} invalid sessions were excluded")
        if duplicate_count:
            reasons.append(f"{duplicate_count} duplicate sessions were excluded")
        if excluded_count:
            reasons.append(f"{excluded_count} human sessions did not match the required build cohort")

        return EvidenceGateResult(
            passed=human_count >= self.minimum_human_sessions,
            required_human_sessions=self.minimum_human_sessions,
            human_sessions=human_count,
            synthetic_sessions=synthetic_count,
            invalid_sessions=invalid_count,
            duplicate_sessions=duplicate_count,
            excluded_sessions=excluded_count,
            reasons=tuple(reasons),
        )


def _validate_evidence(value: object, violations: list[Violation]) -> None:
    evidence = _expect_mapping(value, "$.evidence", violations)
    if evidence is None:
        return
    fields = frozenset({"source", "synthetic", "collection_method"})
    _required_fields(evidence, fields, "$.evidence", violations)
    _reject_extra_fields(evidence, fields, "$.evidence", violations)
    source = evidence.get("source")
    synthetic = evidence.get("synthetic")
    method = evidence.get("collection_method")
    if source not in ("human", "synthetic"):
        _invalid_enum("$.evidence.source", source, {"human", "synthetic"}, violations)
    if not isinstance(synthetic, bool):
        violations.append(Violation("invalid-type", "$.evidence.synthetic", "expected boolean"))
    if source == "human" and (synthetic is not False or method not in HUMAN_COLLECTION_METHODS):
        violations.append(
            Violation(
                "evidence-mismatch",
                "$.evidence",
                "human evidence must be non-synthetic and use a human collection method",
            )
        )
    if source == "synthetic" and (synthetic is not True or method not in SYNTHETIC_COLLECTION_METHODS):
        violations.append(
            Violation(
                "evidence-mismatch",
                "$.evidence",
                "synthetic evidence must stay marked synthetic and use a synthetic collection method",
            )
        )


def _validate_build(value: object, violations: list[Violation]) -> None:
    build = _expect_mapping(value, "$.build", violations)
    if build is None:
        return
    fields = frozenset({"version", "commit", "content_version"})
    _required_fields(build, fields, "$.build", violations)
    _reject_extra_fields(build, fields, "$.build", violations)
    _nonempty_string(build.get("version"), "$.build.version", violations, max_length=64)
    commit = build.get("commit")
    if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit) is None:
        violations.append(Violation("invalid-commit", "$.build.commit", "expected 7-40 lowercase hex characters"))
    _nonempty_string(build.get("content_version"), "$.build.content_version", violations, max_length=64)


def _validate_run(value: object, violations: list[Violation]) -> None:
    run = _expect_mapping(value, "$.run", violations)
    if run is None:
        return
    fields = frozenset({"seed", "input_device"})
    _required_fields(run, fields, "$.run", violations)
    _reject_extra_fields(run, fields, "$.run", violations)
    _integer(run.get("seed"), "$.run.seed", violations)
    if run.get("input_device") not in INPUT_DEVICES:
        _invalid_enum("$.run.input_device", run.get("input_device"), INPUT_DEVICES, violations)


def _validate_timing(value: object, violations: list[Violation]) -> None:
    timing = _expect_mapping(value, "$.timing", violations)
    if timing is None:
        return
    fields = frozenset({"started_at_utc", "ended_at_utc", "duration_ms"})
    _required_fields(timing, fields, "$.timing", violations)
    _reject_extra_fields(timing, fields, "$.timing", violations)
    for field in ("started_at_utc", "ended_at_utc"):
        timestamp = timing.get(field)
        if not isinstance(timestamp, str) or UTC_TIMESTAMP_RE.fullmatch(timestamp) is None:
            violations.append(Violation("invalid-timestamp", f"$.timing.{field}", "expected UTC ISO-8601 timestamp ending in Z"))
    _integer(timing.get("duration_ms"), "$.timing.duration_ms", violations, minimum=0)


def _validate_rooms(value: object, violations: list[Violation]) -> None:
    rooms = _expect_list(value, "$.rooms", violations)
    if rooms is None:
        return
    fields = frozenset({"room_id", "room_type", "room_index", "entered_at_ms", "completed_at_ms", "duration_ms", "result"})
    for index, raw_room in enumerate(rooms):
        path = f"$.rooms[{index}]"
        room = _expect_mapping(raw_room, path, violations)
        if room is None:
            continue
        _required_fields(room, fields, path, violations)
        _reject_extra_fields(room, fields, path, violations)
        _identifier(room.get("room_id"), f"{path}.room_id", violations)
        if room.get("room_type") not in ROOM_TYPES:
            _invalid_enum(f"{path}.room_type", room.get("room_type"), ROOM_TYPES, violations)
        _integer(room.get("room_index"), f"{path}.room_index", violations, minimum=0)
        entered = _integer(room.get("entered_at_ms"), f"{path}.entered_at_ms", violations, minimum=0)
        completed = _integer(room.get("completed_at_ms"), f"{path}.completed_at_ms", violations, minimum=0)
        duration = _integer(room.get("duration_ms"), f"{path}.duration_ms", violations, minimum=0)
        if None not in (entered, completed, duration) and (completed - entered) != duration:
            violations.append(Violation("timing-mismatch", path, "duration_ms must equal completed_at_ms - entered_at_ms"))
        if room.get("result") not in ROOM_RESULTS:
            _invalid_enum(f"{path}.result", room.get("result"), ROOM_RESULTS, violations)


def _validate_damage(value: object, violations: list[Violation]) -> None:
    damage = _expect_mapping(value, "$.damage", violations)
    if damage is None:
        return
    fields = frozenset({"dealt", "taken", "hits_dealt", "hits_taken"})
    _required_fields(damage, fields, "$.damage", violations)
    _reject_extra_fields(damage, fields, "$.damage", violations)
    for field in sorted(fields):
        _integer(damage.get(field), f"$.damage.{field}", violations, minimum=0)


def _validate_failures(value: object, violations: list[Violation]) -> None:
    failures = _expect_list(value, "$.failures", violations)
    if failures is None:
        return
    fields = frozenset({"code", "phase", "room_index", "at_ms"})
    for index, raw_failure in enumerate(failures):
        path = f"$.failures[{index}]"
        failure = _expect_mapping(raw_failure, path, violations)
        if failure is None:
            continue
        _required_fields(failure, fields, path, violations)
        _reject_extra_fields(failure, fields, path, violations)
        _identifier(failure.get("code"), f"{path}.code", violations)
        if failure.get("phase") not in FAILURE_PHASES:
            _invalid_enum(f"{path}.phase", failure.get("phase"), FAILURE_PHASES, violations)
        _integer(failure.get("room_index"), f"{path}.room_index", violations, minimum=-1)
        _integer(failure.get("at_ms"), f"{path}.at_ms", violations, minimum=0)


def _validate_choices(value: object, violations: list[Violation]) -> None:
    choices = _expect_list(value, "$.build_choices", violations)
    if choices is None:
        return
    fields = frozenset({"choice_type", "choice_id", "room_index", "at_ms"})
    for index, raw_choice in enumerate(choices):
        path = f"$.build_choices[{index}]"
        choice = _expect_mapping(raw_choice, path, violations)
        if choice is None:
            continue
        _required_fields(choice, fields, path, violations)
        _reject_extra_fields(choice, fields, path, violations)
        if choice.get("choice_type") not in CHOICE_TYPES:
            _invalid_enum(f"{path}.choice_type", choice.get("choice_type"), CHOICE_TYPES, violations)
        _identifier(choice.get("choice_id"), f"{path}.choice_id", violations)
        _integer(choice.get("room_index"), f"{path}.room_index", violations, minimum=-1)
        _integer(choice.get("at_ms"), f"{path}.at_ms", violations, minimum=0)


def _validate_terminal_result(value: object, violations: list[Violation]) -> None:
    result = _expect_mapping(value, "$.terminal_result", violations)
    if result is None:
        return
    fields = frozenset({"outcome", "floor", "room_index", "duration_ms", "cause"})
    _required_fields(result, fields, "$.terminal_result", violations)
    _reject_extra_fields(result, fields, "$.terminal_result", violations)
    if result.get("outcome") not in OUTCOMES:
        _invalid_enum("$.terminal_result.outcome", result.get("outcome"), OUTCOMES, violations)
    _integer(result.get("floor"), "$.terminal_result.floor", violations, minimum=0)
    _integer(result.get("room_index"), "$.terminal_result.room_index", violations, minimum=-1)
    _integer(result.get("duration_ms"), "$.terminal_result.duration_ms", violations, minimum=0)
    _identifier(result.get("cause"), "$.terminal_result.cause", violations)


def _validate_device(value: object, violations: list[Violation]) -> None:
    if value is None:
        return
    device = _expect_mapping(value, "$.device", violations)
    if device is None:
        return
    _reject_extra_fields(device, frozenset({"platform"}), "$.device", violations)
    if "platform" in device:
        _nonempty_string(device.get("platform"), "$.device.platform", violations, max_length=64)


def _required_fields(value: Mapping[str, object], fields: frozenset[str], path: str, violations: list[Violation]) -> None:
    for field in sorted(fields - value.keys()):
        violations.append(Violation("missing-field", f"{path}.{field}", "required field is absent"))


def _reject_extra_fields(value: Mapping[str, object], fields: frozenset[str], path: str, violations: list[Violation]) -> None:
    for field in sorted(value.keys() - fields):
        violations.append(Violation("unexpected-field", f"{path}.{field}", "field is not allowed by the playtest schema"))


def _expect_mapping(value: object, path: str, violations: list[Violation]) -> Mapping[str, object] | None:
    if not isinstance(value, dict):
        violations.append(Violation("invalid-type", path, "expected object"))
        return None
    return value


def _expect_list(value: object, path: str, violations: list[Violation]) -> list | None:
    if not isinstance(value, list):
        violations.append(Violation("invalid-type", path, "expected array"))
        return None
    return value


def _integer(value: object, path: str, violations: list[Violation], minimum: int | None = None) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        violations.append(Violation("invalid-type", path, "expected integer"))
        return None
    if minimum is not None and value < minimum:
        violations.append(Violation("out-of-range", path, f"expected value >= {minimum}"))
    return value


def _identifier(value: object, path: str, violations: list[Violation]) -> None:
    if not isinstance(value, str) or IDENTIFIER_RE.fullmatch(value) is None:
        violations.append(Violation("invalid-identifier", path, "expected lowercase data identifier"))


def _nonempty_string(value: object, path: str, violations: list[Violation], *, max_length: int) -> None:
    if not isinstance(value, str) or not value.strip() or len(value) > max_length:
        violations.append(Violation("invalid-string", path, f"expected 1-{max_length} non-blank characters"))


def _invalid_enum(path: str, value: object, allowed: Iterable[str], violations: list[Violation]) -> None:
    violations.append(Violation("invalid-enum", path, f"got {value!r}; expected one of {', '.join(sorted(allowed))}"))


def _remove_pii(value: object) -> object:
    if isinstance(value, dict):
        return {
            key: _remove_pii(child)
            for key, child in value.items()
            if str(key).lower() not in PII_KEYS
        }
    if isinstance(value, list):
        return [_remove_pii(child) for child in value]
    return value


def _is_human(session: Mapping[str, object]) -> bool:
    evidence = _mapping(session.get("evidence"))
    return evidence.get("source") == "human" and evidence.get("synthetic") is False


def _is_synthetic(session: Mapping[str, object]) -> bool:
    evidence = _mapping(session.get("evidence"))
    return evidence.get("source") == "synthetic" and evidence.get("synthetic") is True


def _matches_cohort(
    session: Mapping[str, object],
    *,
    build_version: str | None,
    commit: str | None,
    content_version: str | None,
) -> bool:
    build = _mapping(session.get("build"))
    return (
        (build_version is None or build.get("version") == build_version)
        and (commit is None or build.get("commit") == commit)
        and (content_version is None or build.get("content_version") == content_version)
    )


def _mapping(value: object) -> Mapping[str, object]:
    return value if isinstance(value, dict) else {}


def _sequence(value: object) -> Sequence[object]:
    return value if isinstance(value, list) else []


def _safe_int(value: object) -> int:
    return int(value) if isinstance(value, int) and not isinstance(value, bool) else 0


def _average(values: Sequence[int]) -> float:
    return round(sum(values) / len(values), 3) if values else 0.0


def _ratio(numerator: int, denominator: int) -> float:
    return round(numerator / denominator, 4) if denominator else 0.0
