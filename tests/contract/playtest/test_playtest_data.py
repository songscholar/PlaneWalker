from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
TOOLS_DIR = PROJECT_ROOT / "tools" / "playtest"
sys.path.insert(0, str(TOOLS_DIR))

from playtest_data import (  # noqa: E402
    EvidenceGate,
    deidentify_session,
    load_jsonl,
    summarize_sessions,
    validate_session,
)


def make_session(index: int = 1, *, source: str = "human") -> dict:
    synthetic = source == "synthetic"
    return {
        "schema_version": "1.0.0",
        "session_id": f"pws_{index:032x}",
        "evidence": {
            "source": source,
            "synthetic": synthetic,
            "collection_method": "automated_fixture" if synthetic else "observed_playtest",
        },
        "build": {
            "version": "0.4.0-dev",
            "commit": "a1b2c3d4",
            "content_version": "m1-wave4",
        },
        "run": {"seed": 1000 + index, "input_device": "keyboard_mouse"},
        "timing": {
            "started_at_utc": "2026-09-28T08:00:00Z",
            "ended_at_utc": "2026-09-28T08:05:00Z",
            "duration_ms": 300000,
        },
        "rooms": [
            {
                "room_id": "combat_01",
                "room_type": "combat",
                "room_index": 0,
                "entered_at_ms": 0,
                "completed_at_ms": 45000,
                "duration_ms": 45000,
                "result": "cleared",
            }
        ],
        "damage": {
            "dealt": 480,
            "taken": 25,
            "hits_dealt": 12,
            "hits_taken": 2,
        },
        "failures": [],
        "build_choices": [
            {
                "choice_type": "item",
                "choice_id": "volatile_clock",
                "room_index": 0,
                "at_ms": 46000,
            }
        ],
        "terminal_result": {
            "outcome": "completed",
            "floor": 1,
            "room_index": 4,
            "duration_ms": 300000,
            "cause": "boss_defeated",
        },
    }


class PlaytestSchemaContractTest(unittest.TestCase):
    def test_json_schema_declares_version_and_all_top_level_fields(self) -> None:
        schema_path = PROJECT_ROOT / "data" / "schemas" / "playtest_session_v1.schema.json"
        schema = json.loads(schema_path.read_text(encoding="utf-8"))

        self.assertEqual(schema["$id"], "planewalker://schemas/playtest-session/1.0.0")
        self.assertEqual(schema["properties"]["schema_version"]["const"], "1.0.0")
        self.assertEqual(
            set(schema["required"]),
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
            },
        )

    def test_valid_session_covers_required_wave4a_fields(self) -> None:
        self.assertEqual(validate_session(make_session()), [])

    def test_rejects_missing_required_field_and_invalid_enum(self) -> None:
        session = make_session()
        del session["damage"]
        session["run"]["input_device"] = "neural_link"

        violations = validate_session(session)

        codes = {violation.code for violation in violations}
        self.assertIn("missing-field", codes)
        self.assertIn("invalid-enum", codes)

    def test_synthetic_flag_cannot_claim_human_evidence(self) -> None:
        session = make_session(source="synthetic")
        session["evidence"]["source"] = "human"

        violations = validate_session(session)

        self.assertIn("evidence-mismatch", {item.code for item in violations})

    def test_session_id_is_anonymous_and_strictly_formatted(self) -> None:
        session = make_session()
        session["session_id"] = "isaac@example.com"

        violations = validate_session(session)

        self.assertIn("invalid-session-id", {item.code for item in violations})

    def test_jsonl_import_reports_line_number_and_duplicate_session(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "sessions.jsonl"
            valid = make_session(1)
            path.write_text(
                "\n".join((json.dumps(valid), "not json", json.dumps(valid))) + "\n",
                encoding="utf-8",
            )

            result = load_jsonl(path)

            self.assertEqual(len(result.sessions), 1)
            self.assertEqual(
                {(item.code, item.line) for item in result.violations},
                {("invalid-json", 2), ("duplicate-session", 3)},
            )

    def test_deidentification_hashes_id_strips_pii_and_preserves_evidence(self) -> None:
        session = make_session()
        session["tester_email"] = "isaac@example.com"
        session["device"] = {"device_name": "Isaac's Mac", "platform": "macOS"}

        cleaned = deidentify_session(session, salt="local-test-salt")

        expected_digest = hashlib.sha256(
            b"local-test-salt:pws_00000000000000000000000000000001"
        ).hexdigest()[:32]
        self.assertEqual(cleaned["session_id"], f"pws_{expected_digest}")
        self.assertNotIn("tester_email", cleaned)
        self.assertNotIn("device_name", cleaned["device"])
        self.assertEqual(cleaned["device"]["platform"], "macOS")
        self.assertEqual(cleaned["evidence"], session["evidence"])
        self.assertEqual(validate_session(cleaned), [])

    def test_repository_fixture_is_synthetic_and_never_passes_human_gate(self) -> None:
        fixture = PROJECT_ROOT / "tests" / "fixtures" / "playtest" / "synthetic_sessions.jsonl"

        imported = load_jsonl(fixture)
        gate = EvidenceGate(minimum_human_sessions=1).evaluate(imported.sessions)

        self.assertEqual(imported.violations, [])
        self.assertGreater(len(imported.sessions), 0)
        self.assertFalse(gate.passed)
        self.assertEqual(gate.human_sessions, 0)
        self.assertEqual(gate.synthetic_sessions, len(imported.sessions))

    def test_summary_separates_human_and_synthetic_and_reports_metrics(self) -> None:
        human = make_session(1, source="human")
        synthetic = make_session(2, source="synthetic")
        failed = make_session(3, source="human")
        failed["terminal_result"]["outcome"] = "death"
        failed["terminal_result"]["cause"] = "enemy_damage"
        failed["failures"] = [
            {
                "code": "player_death",
                "phase": "combat",
                "room_index": 2,
                "at_ms": 180000,
            }
        ]

        report = summarize_sessions([human, synthetic, failed])

        self.assertEqual(report["evidence"], {"human": 2, "synthetic": 1})
        self.assertEqual(report["human_metrics"]["completion_rate"], 0.5)
        self.assertEqual(report["human_metrics"]["average_damage_taken"], 25.0)
        self.assertEqual(report["human_metrics"]["failure_codes"], {"player_death": 1})

    def test_evidence_gate_requires_twenty_unique_valid_human_sessions(self) -> None:
        sessions = [make_session(index) for index in range(1, 20)]
        sessions.extend(make_session(index, source="synthetic") for index in range(20, 26))

        failed = EvidenceGate(minimum_human_sessions=20).evaluate(sessions)
        passed = EvidenceGate(minimum_human_sessions=20).evaluate(
            sessions + [make_session(26)]
        )

        self.assertFalse(failed.passed)
        self.assertEqual(failed.human_sessions, 19)
        self.assertEqual(failed.synthetic_sessions, 6)
        self.assertTrue(passed.passed)
        self.assertEqual(passed.human_sessions, 20)

    def test_evidence_gate_can_require_one_build_cohort(self) -> None:
        sessions = [make_session(index) for index in range(1, 21)]
        sessions[-1]["build"]["commit"] = "deadbeef"

        result = EvidenceGate(
            minimum_human_sessions=20,
            required_commit="a1b2c3d4",
        ).evaluate(sessions)

        self.assertFalse(result.passed)
        self.assertEqual(result.human_sessions, 19)
        self.assertEqual(result.excluded_sessions, 1)

    def test_cli_validation_summary_and_gate_are_machine_readable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "sessions.jsonl"
            path.write_text(
                "\n".join(json.dumps(make_session(index)) for index in range(1, 21))
                + "\n",
                encoding="utf-8",
            )

            validate_result = self._run_cli("validate_sessions.py", str(path), "--json")
            summary_result = self._run_cli("summarize_sessions.py", str(path), "--json")
            gate_result = self._run_cli(
                "evidence_gate.py", str(path), "--minimum-human", "20", "--json"
            )

            self.assertEqual(validate_result.returncode, 0, validate_result.stderr)
            self.assertEqual(summary_result.returncode, 0, summary_result.stderr)
            self.assertEqual(gate_result.returncode, 0, gate_result.stderr)
            self.assertEqual(json.loads(validate_result.stdout)["valid_sessions"], 20)
            self.assertEqual(json.loads(summary_result.stdout)["evidence"]["human"], 20)
            self.assertTrue(json.loads(gate_result.stdout)["passed"])

    def test_deidentify_cli_cleans_legacy_pii_before_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "legacy.jsonl"
            destination = Path(temp_dir) / "clean.jsonl"
            session = make_session()
            session["tester_email"] = "player@example.com"
            source.write_text(json.dumps(session) + "\n", encoding="utf-8")

            result = self._run_cli(
                "deidentify_sessions.py",
                str(source),
                str(destination),
                "--salt",
                "local-test-salt",
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            imported = load_jsonl(destination)
            self.assertEqual(imported.violations, [])
            self.assertEqual(len(imported.sessions), 1)
            self.assertNotIn("tester_email", imported.sessions[0])

    @staticmethod
    def _run_cli(script_name: str, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOLS_DIR / script_name), *arguments],
            cwd=PROJECT_ROOT,
            capture_output=True,
            check=False,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
