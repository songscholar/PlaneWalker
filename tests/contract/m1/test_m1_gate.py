from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
M1_TOOLS = PROJECT_ROOT / "tools" / "m1"
PLAYTEST_TOOLS = PROJECT_ROOT / "tools" / "playtest"
sys.path.insert(0, str(M1_TOOLS))
sys.path.insert(0, str(PLAYTEST_TOOLS))

from m1_gate import (  # noqa: E402
    M1_CANDIDATE,
    M1_GO,
    M1_NO_GO,
    PROBE_VERSION,
    compare_seed_matrices,
    evaluate_m1,
    load_observations_jsonl,
    make_seed_matrix,
    render_release_report,
    validate_observation,
    validate_seed_matrix,
)
from playtest_data import load_jsonl  # noqa: E402
from run_seed_matrix import (  # noqa: E402
    MACOS_CA_CALLSITE,
    MACOS_CA_ERROR,
    _unapproved_error_lines,
)


COHORT = {
    "build_version": "0.4.0-dev",
    "commit": "a1b2c3d4",
    "content_version": "m1.encounters.v1",
}


def make_evidence(*, origin: str = "godot_authoritative_probe", clean: bool = True) -> dict:
    return {
        "evidence_origin": origin,
        "classification": "release" if origin == "godot_authoritative_probe" and clean else "non_release_synthetic",
        "probe_version": PROBE_VERSION,
        "worktree_clean": clean,
        "head_commit": COHORT["commit"],
        "tree_digest": "1" * 40,
        "probe_digest": "2" * 64,
        "godot_version": "4.6.stable",
        "content_digest": "3" * 64,
        "catalog_content_version": COHORT["content_version"],
    }


def make_raw_run(seed: int) -> dict:
    return {
        "seed": seed,
        "terminal_state": "victory",
        "room_sequence": [1, 2, 3, 4, 5],
        "encounter_ids": [
            "m1_room_01",
            "m1_room_02",
            "m1_room_03",
            "m1_room_04_elite",
            "m1_room_05_boss",
        ],
        "spawn_sequences": [
            [["chaser"]],
            [["chaser", "shooter"]],
            [["chaser", "shooter"], ["tank"]],
            [["tank"]],
            [["chrono_warden"]],
        ],
        "reward_offers": [["a", "b", "c"]] * 4,
        "selected_choices": ["a", "a", "a", "a"],
        "choice_snapshots": [
            {
                "choice_id": "a",
                "revision": revision,
                "build": {"items": [f"item_{revision}"], "blessings": [], "curses": []},
            }
            for revision in range(1, 5)
        ],
        "failure_codes": [],
        "duration_proxy_ms": 500_000,
    }


def make_matrix() -> dict:
    return make_seed_matrix(
        [make_raw_run(seed) for seed in range(30)],
        cohort=COHORT,
        seed_start=0,
        seed_count=30,
        evidence=make_evidence(),
    )


def make_attestation(session_ids: list[str]) -> dict:
    return {
        "schema_version": "1.0.0",
        "attestation_id": "m1_external_cohort_001",
        "cohort": dict(COHORT),
        "attestor": {
            "role": "external_playtest_coordinator",
            "independent_from_development": True,
        },
        "approval": {
            "status": "approved",
            "statement": "authentic_human_evidence_verified",
            "approved_at_utc": "2026-09-28T12:00:00Z",
        },
        "session_ids": session_ids,
    }


def make_session(index: int, *, source: str = "human") -> dict:
    synthetic = source == "synthetic"
    return {
        "schema_version": "1.0.0",
        "session_id": f"pws_{index:032x}",
        "evidence": {
            "source": source,
            "synthetic": synthetic,
            "collection_method": "simulation" if synthetic else "observed_playtest",
        },
        "build": {
            "version": COHORT["build_version"],
            "commit": COHORT["commit"],
            "content_version": COHORT["content_version"],
        },
        "run": {"seed": index, "input_device": "automation" if synthetic else "keyboard_mouse"},
        "timing": {
            "started_at_utc": "2026-09-28T08:00:00Z",
            "ended_at_utc": "2026-09-28T08:09:00Z",
            "duration_ms": 540_000,
        },
        "rooms": [],
        "damage": {"dealt": 1000, "taken": 20, "hits_dealt": 40, "hits_taken": 2},
        "failures": [],
        "build_choices": [],
        "terminal_result": {
            "outcome": "completed",
            "floor": 1,
            "room_index": 4,
            "duration_ms": 540_000,
            "cause": "boss_defeated",
        },
    }


def make_observation(index: int, *, source: str = "human") -> dict:
    synthetic = source == "synthetic"
    return {
        "schema_version": "1.0.0",
        "session_id": f"pws_{index:032x}",
        "evidence": {
            "source": source,
            "synthetic": synthetic,
            "collection_method": "simulation" if synthetic else "observed_playtest",
        },
        "time_abilities": {"time_stop_used": True, "time_rewind_used": True},
        "comprehension": {
            "build_described": True,
            "boss_time_interactions_identified": 2,
        },
        "experience": {
            "unexplained_damage_or_death": False,
            "responsiveness_rating": 5,
            "replay_intent": "would_replay",
        },
        "issues": [],
    }


class SeedMatrixContractTest(unittest.TestCase):
    def test_exact_canonical_seed_coverage_passes(self) -> None:
        result = validate_seed_matrix(make_matrix())

        self.assertTrue(result.passed, result.reasons)
        self.assertEqual(result.seed_count, 30)
        self.assertEqual(result.seeds, tuple(range(30)))

    def test_missing_and_duplicate_seed_are_rejected(self) -> None:
        raw_runs = [make_raw_run(seed) for seed in range(29)]
        raw_runs.append(make_raw_run(28))
        report = make_seed_matrix(
            raw_runs,
            cohort=COHORT,
            seed_start=0,
            seed_count=30,
            evidence=make_evidence(),
        )

        result = validate_seed_matrix(report)

        self.assertFalse(result.passed)
        self.assertTrue(any("duplicate seed 28" in reason for reason in result.reasons))
        self.assertTrue(any("missing seeds: 29" in reason for reason in result.reasons))

    def test_digest_comparison_detects_semantic_drift(self) -> None:
        first = make_matrix()
        second = make_matrix()

        self.assertTrue(compare_seed_matrices(first, second).matched)

        changed_runs = [make_raw_run(seed) for seed in range(30)]
        changed_runs[7]["selected_choices"][0] = "different"
        changed = make_seed_matrix(
            changed_runs,
            cohort=COHORT,
            seed_start=0,
            seed_count=30,
            evidence=make_evidence(),
        )

        comparison = compare_seed_matrices(first, changed)
        self.assertFalse(comparison.matched)
        self.assertIn(7, comparison.changed_seeds)

    def test_formal_matrix_requires_authoritative_clean_probe_provenance(self) -> None:
        raw_adapter = make_seed_matrix(
            [make_raw_run(seed) for seed in range(30)],
            cohort=COHORT,
            seed_start=0,
            seed_count=30,
            evidence=make_evidence(origin="raw_results_adapter"),
        )
        dirty_probe = make_seed_matrix(
            [make_raw_run(seed) for seed in range(30)],
            cohort=COHORT,
            seed_start=0,
            seed_count=30,
            evidence=make_evidence(clean=False) | {
                "evidence_origin": "godot_authoritative_probe",
                "classification": "non_release_candidate",
            },
        )

        raw_result = validate_seed_matrix(raw_adapter)
        dirty_result = validate_seed_matrix(dirty_probe)

        self.assertTrue(raw_result.passed, raw_result.reasons)
        self.assertFalse(raw_result.release_eligible)
        self.assertTrue(dirty_result.passed, dirty_result.reasons)
        self.assertFalse(dirty_result.release_eligible)
        self.assertTrue(any("godot_authoritative_probe" in reason for reason in raw_result.release_reasons))
        self.assertTrue(any("clean worktree" in reason for reason in dirty_result.release_reasons))

    def test_strict_run_shape_rejects_missing_room_spawn_choice_snapshot_and_duration(self) -> None:
        cases = {
            "room": lambda run: run["room_sequence"].pop(),
            "encounter": lambda run: run["encounter_ids"].__setitem__(2, ""),
            "spawn": lambda run: run["spawn_sequences"].__setitem__(1, []),
            "offer": lambda run: run["reward_offers"].pop(),
            "choice": lambda run: run["selected_choices"].pop(),
            "snapshot": lambda run: run["choice_snapshots"].pop(),
            "victory": lambda run: run.__setitem__("terminal_state", "death"),
            "duration": lambda run: run.__setitem__("duration_proxy_ms", 0),
        }
        for label, mutate in cases.items():
            with self.subTest(label=label):
                runs = [make_raw_run(seed) for seed in range(30)]
                mutate(runs[0])
                report = make_seed_matrix(
                    runs,
                    cohort=COHORT,
                    seed_start=0,
                    seed_count=30,
                    evidence=make_evidence(),
                )
                result = validate_seed_matrix(report)
                self.assertFalse(result.passed, label)


class ObservationAndDecisionContractTest(unittest.TestCase):
    def test_external_attestation_schema_requires_independent_exact_cohort_approval(self) -> None:
        schema = json.loads(
            (PROJECT_ROOT / "data" / "schemas" / "m1_external_attestation_v1.schema.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual(schema["$id"], "planewalker://schemas/m1-external-attestation/1.0.0")
        self.assertEqual(schema["properties"]["attestor"]["properties"]["independent_from_development"]["const"], True)
        self.assertEqual(schema["properties"]["session_ids"]["minItems"], 20)

    def test_observation_schema_rejects_pii_and_synthetic_human_mismatch(self) -> None:
        observation = make_observation(1)
        observation["tester_name"] = "A person"
        observation["evidence"]["synthetic"] = True

        codes = {item.code for item in validate_observation(observation)}

        self.assertIn("unexpected-field", codes)
        self.assertIn("evidence-mismatch", codes)

    def test_observation_jsonl_rejects_duplicate_session(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "observations.jsonl"
            observation = make_observation(1)
            path.write_text(
                json.dumps(observation) + "\n" + json.dumps(observation) + "\n",
                encoding="utf-8",
            )

            imported = load_observations_jsonl(path)

            self.assertEqual(len(imported.observations), 1)
            self.assertEqual([(item.code, item.line) for item in imported.violations], [("duplicate-session", 2)])

    def test_observation_cli_separates_invalid_records_from_field_violations(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "observations.jsonl"
            invalid = make_observation(1)
            invalid["tester_name"] = "not allowed"
            invalid["evidence"]["synthetic"] = True
            path.write_text(json.dumps(invalid) + "\n", encoding="utf-8")

            result = M1CliContractTest._run("validate_observations.py", str(path), "--json")
            report = json.loads(result.stdout)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(report["invalid_observations"], 1)
            self.assertEqual(report["violation_count"], 2)

    def test_synthetic_fixture_never_satisfies_external_gate(self) -> None:
        imported = load_jsonl(
            PROJECT_ROOT / "tests" / "fixtures" / "playtest" / "synthetic_sessions.jsonl"
        )

        decision = evaluate_m1(
            make_matrix(),
            imported.sessions,
            session_violations=imported.violations,
            observations=[make_observation(1, source="synthetic")],
        )

        self.assertEqual(decision.state, M1_CANDIDATE)
        self.assertEqual(decision.external_gate["human_sessions"], 0)
        self.assertEqual(decision.external_gate["synthetic_sessions"], len(imported.sessions))
        self.assertFalse(decision.external_gate["passed"])

    def test_twenty_complete_human_records_can_pass_m1(self) -> None:
        sessions = [make_session(index) for index in range(1, 21)]
        observations = [make_observation(index) for index in range(1, 21)]

        decision = evaluate_m1(make_matrix(), sessions, observations=observations)

        self.assertEqual(decision.state, M1_CANDIDATE)
        self.assertFalse(decision.external_gate["attestation"]["approved"])

        decision = evaluate_m1(
            make_matrix(),
            sessions,
            observations=observations,
            attestation=make_attestation([session["session_id"] for session in sessions]),
        )

        self.assertEqual(decision.state, M1_GO)
        self.assertTrue(decision.repository_gate["passed"])
        self.assertTrue(decision.external_gate["passed"])
        self.assertEqual(decision.external_gate["joined_observations"], 20)
        go_markdown = render_release_report(decision)
        self.assertIn("状态为 `M1 Go`", go_markdown)
        self.assertNotIn("状态保持 `M1 Candidate", go_markdown)

    def test_nineteen_deaths_cannot_exploit_successful_duration_denominator(self) -> None:
        sessions = [make_session(index) for index in range(1, 21)]
        observations = [make_observation(index) for index in range(1, 21)]
        for session in sessions[:19]:
            session["terminal_result"].update({"outcome": "death", "cause": "enemy_damage"})

        decision = evaluate_m1(
            make_matrix(),
            sessions,
            observations=observations,
            attestation=make_attestation([session["session_id"] for session in sessions]),
        )

        completion = decision.external_gate["thresholds"]["human_completion_rate"]
        self.assertEqual((completion["numerator"], completion["denominator"]), (1, 20))
        self.assertFalse(completion["passed"])
        self.assertEqual(decision.state, M1_NO_GO)

    def test_p0_p1_or_explicit_blocker_forces_no_go(self) -> None:
        for severity, blocks_release in (("p0", False), ("p1", False), ("p2", True)):
            with self.subTest(severity=severity, blocks_release=blocks_release):
                sessions = [make_session(index) for index in range(1, 21)]
                observations = [make_observation(index) for index in range(1, 21)]
                observations[0]["issues"] = [{
                    "code": "combat_blocker",
                    "severity": severity,
                    "system": "combat",
                    "room_index": 2,
                    "blocks_release": blocks_release,
                }]
                decision = evaluate_m1(
                    make_matrix(),
                    sessions,
                    observations=observations,
                    attestation=make_attestation([session["session_id"] for session in sessions]),
                )
                self.assertEqual(decision.state, M1_NO_GO)
                self.assertEqual(len(decision.external_gate["blocking_issues"]), 1)

    def test_invalid_records_are_deduplicated_from_violation_count(self) -> None:
        class ImportedViolation:
            def __init__(self, line: int, code: str = "invalid-field") -> None:
                self.line = line
                self.code = code

        decision = evaluate_m1(
            make_matrix(),
            [],
            session_violations=[
                ImportedViolation(4),
                ImportedViolation(4),
                ImportedViolation(9),
                ImportedViolation(12, "duplicate-session"),
            ],
            observation_violations=[ImportedViolation(3), ImportedViolation(3), ImportedViolation(3)],
        )

        self.assertEqual(decision.external_gate["invalid_sessions"], 2)
        self.assertEqual(decision.external_gate["session_violations"], 4)
        self.assertEqual(decision.external_gate["duplicate_sessions"], 1)
        self.assertEqual(decision.external_gate["invalid_observations"], 1)
        self.assertEqual(decision.external_gate["observation_violations"], 3)

    def test_human_threshold_failure_is_no_go(self) -> None:
        sessions = [make_session(index) for index in range(1, 21)]
        observations = [make_observation(index) for index in range(1, 21)]
        for observation in observations[:9]:
            observation["experience"]["responsiveness_rating"] = 3

        decision = evaluate_m1(make_matrix(), sessions, observations=observations)

        self.assertEqual(decision.state, M1_NO_GO)
        self.assertFalse(decision.external_gate["thresholds"]["responsiveness_4plus_rate"]["passed"])
        self.assertTrue(decision.tuning_input["human_tuning_authorized"])

    def test_repository_failure_is_no_go_even_without_human_sessions(self) -> None:
        runs = [make_raw_run(seed) for seed in range(30)]
        runs[3]["terminal_state"] = "technical_failure"
        runs[3]["failure_codes"] = ["soft_lock"]
        failed_matrix = make_seed_matrix(
            runs,
            cohort=COHORT,
            seed_start=0,
            seed_count=30,
            evidence=make_evidence(),
        )

        decision = evaluate_m1(failed_matrix, [])

        self.assertEqual(decision.state, M1_NO_GO)
        self.assertFalse(decision.repository_gate["passed"])

    def test_report_states_external_limitation_and_tuning_boundary(self) -> None:
        decision = evaluate_m1(make_matrix(), [])

        markdown = render_release_report(decision)

        self.assertIn(M1_CANDIDATE, markdown)
        self.assertIn("0 / 20", markdown)
        self.assertIn("synthetic", markdown.lower())
        self.assertIn("不得据此声称手感、公平性或重玩意愿已验证", markdown)
        self.assertIn("状态保持 `M1 Candidate", markdown)

        no_go_runs = [make_raw_run(seed) for seed in range(30)]
        no_go_runs[0]["terminal_state"] = "death"
        no_go = evaluate_m1(
            make_seed_matrix(no_go_runs, cohort=COHORT, seed_start=0, seed_count=30, evidence=make_evidence()),
            [],
        )
        no_go_markdown = render_release_report(no_go)
        self.assertIn("状态保持 `M1 No-Go`", no_go_markdown)
        self.assertNotIn("状态保持 `M1 Candidate", no_go_markdown)


class M1CliContractTest(unittest.TestCase):
    def test_log_scanner_rejects_every_unallowlisted_error(self) -> None:
        self.assertEqual(
            _unapproved_error_lines(MACOS_CA_ERROR + "\n" + MACOS_CA_CALLSITE + "123)"),
            [],
        )
        self.assertTrue(_unapproved_error_lines("ERROR: unrelated runtime failure"))
        self.assertTrue(_unapproved_error_lines(MACOS_CA_ERROR))

    def test_offline_raw_results_and_report_generation_are_machine_readable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            raw_path = temp / "raw.json"
            seed_path = temp / "seeds.json"
            repeat_path = temp / "seeds-repeat.json"
            report_path = temp / "report.md"
            report_json_path = temp / "report.json"
            raw_path.write_text(
                json.dumps({"runs": [make_raw_run(seed) for seed in range(30)]}),
                encoding="utf-8",
            )

            actual_commit = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=PROJECT_ROOT, capture_output=True, check=True, text=True
            ).stdout.strip()
            catalog_version = json.loads(
                (PROJECT_ROOT / "data" / "encounters" / "m1_encounters.json").read_text(encoding="utf-8")
            )["plan_id"]
            common = [
                "--seed-start", "0",
                "--seed-count", "30",
                "--build-version", COHORT["build_version"],
                "--commit", actual_commit,
                "--content-version", catalog_version,
                "--raw-results", str(raw_path),
            ]
            first = self._run("run_seed_matrix.py", *common, "--output", str(seed_path))
            second = self._run("run_seed_matrix.py", *common, "--output", str(repeat_path))
            compared = self._run("compare_seed_reports.py", str(seed_path), str(repeat_path), "--json")
            generated = self._run(
                "generate_release_report.py",
                "--seed-report", str(seed_path),
                "--sessions", str(PROJECT_ROOT / "tests" / "fixtures" / "playtest" / "synthetic_sessions.jsonl"),
                "--output", str(report_path),
                "--json-output", str(report_json_path),
            )

            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertEqual(compared.returncode, 0, compared.stdout + compared.stderr)
            self.assertTrue(json.loads(compared.stdout)["matched"])
            self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
            self.assertEqual(json.loads(report_json_path.read_text(encoding="utf-8"))["state"], M1_CANDIDATE)
            self.assertIn(M1_CANDIDATE, report_path.read_text(encoding="utf-8"))
            seed_report = json.loads(seed_path.read_text(encoding="utf-8"))
            self.assertEqual(seed_report["evidence"]["evidence_origin"], "raw_results_adapter")
            self.assertEqual(seed_report["evidence"]["classification"], "non_release_synthetic")
            self.assertFalse(json.loads(first.stdout)["release_eligible"])

            required_go = self._run(
                "generate_release_report.py",
                "--seed-report", str(seed_path),
                "--output", str(temp / "require-go.md"),
                "--require-go",
            )
            self.assertNotEqual(required_go.returncode, 0)
            self.assertEqual(json.loads(required_go.stdout)["state"], M1_CANDIDATE)

            mismatched_commit = self._run(
                "run_seed_matrix.py",
                *[argument for pair in (
                    ("--seed-start", "0"),
                    ("--seed-count", "30"),
                    ("--commit", "deadbeef"),
                    ("--raw-results", str(raw_path)),
                    ("--output", str(temp / "bad-commit.json")),
                ) for argument in pair],
            )
            self.assertNotEqual(mismatched_commit.returncode, 0)
            self.assertIn("must equal the current HEAD", mismatched_commit.stderr)

    def test_require_go_accepts_only_attested_release_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            seed_path = temp / "release-seeds.json"
            sessions_path = temp / "sessions.jsonl"
            observations_path = temp / "observations.jsonl"
            attestation_path = temp / "attestation.json"
            report_path = temp / "report.md"
            sessions = [make_session(index) for index in range(1, 21)]
            seed_path.write_text(json.dumps(make_matrix()), encoding="utf-8")
            sessions_path.write_text(
                "\n".join(json.dumps(session) for session in sessions) + "\n",
                encoding="utf-8",
            )
            observations_path.write_text(
                "\n".join(json.dumps(make_observation(index)) for index in range(1, 21)) + "\n",
                encoding="utf-8",
            )
            attestation_path.write_text(
                json.dumps(make_attestation([session["session_id"] for session in sessions])),
                encoding="utf-8",
            )

            result = self._run(
                "generate_release_report.py",
                "--seed-report", str(seed_path),
                "--sessions", str(sessions_path),
                "--observations", str(observations_path),
                "--attestation", str(attestation_path),
                "--output", str(report_path),
                "--require-go",
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(json.loads(result.stdout)["release_ready"])
            self.assertIn("状态为 `M1 Go`", report_path.read_text(encoding="utf-8"))

    @staticmethod
    def _run(script: str, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(M1_TOOLS / script), *arguments],
            cwd=PROJECT_ROOT,
            capture_output=True,
            check=False,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
