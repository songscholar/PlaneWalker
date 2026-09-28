from __future__ import annotations

import copy
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
    compare_seed_matrices,
    evaluate_m1,
    load_observations_jsonl,
    make_seed_matrix,
    render_release_report,
    validate_observation,
    validate_seed_matrix,
)
from playtest_data import load_jsonl  # noqa: E402


COHORT = {
    "build_version": "0.4.0-dev",
    "commit": "a1b2c3d4",
    "content_version": "m1.encounters.v1",
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
        "failure_codes": [],
        "duration_proxy_ms": 500_000,
    }


def make_matrix() -> dict:
    return make_seed_matrix(
        [make_raw_run(seed) for seed in range(30)],
        cohort=COHORT,
        seed_start=0,
        seed_count=30,
    )


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
            "started_at_utc": "2026-09-29T08:00:00Z",
            "ended_at_utc": "2026-09-29T08:09:00Z",
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
        )

        comparison = compare_seed_matrices(first, changed)
        self.assertFalse(comparison.matched)
        self.assertIn(7, comparison.changed_seeds)


class ObservationAndDecisionContractTest(unittest.TestCase):
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

        self.assertEqual(decision.state, M1_GO)
        self.assertTrue(decision.repository_gate["passed"])
        self.assertTrue(decision.external_gate["passed"])
        self.assertEqual(decision.external_gate["joined_observations"], 20)

    def test_human_threshold_failure_is_no_go(self) -> None:
        sessions = [make_session(index) for index in range(1, 21)]
        observations = [make_observation(index) for index in range(1, 21)]
        for observation in observations[:9]:
            observation["experience"]["responsiveness_rating"] = 3

        decision = evaluate_m1(make_matrix(), sessions, observations=observations)

        self.assertEqual(decision.state, M1_NO_GO)
        self.assertFalse(decision.external_gate["thresholds"]["responsiveness_4plus_rate"]["passed"])

    def test_repository_failure_is_no_go_even_without_human_sessions(self) -> None:
        runs = [make_raw_run(seed) for seed in range(30)]
        runs[3]["terminal_state"] = "technical_failure"
        runs[3]["failure_codes"] = ["soft_lock"]
        failed_matrix = make_seed_matrix(runs, cohort=COHORT, seed_start=0, seed_count=30)

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


class M1CliContractTest(unittest.TestCase):
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

            common = [
                "--seed-start", "0",
                "--seed-count", "30",
                "--build-version", COHORT["build_version"],
                "--commit", COHORT["commit"],
                "--content-version", COHORT["content_version"],
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
