from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/runtime_log_validation.py"
api = None
if SOURCE.is_file():
    spec = importlib.util.spec_from_file_location("runtime_log_validation", SOURCE)
    api = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(api)


def scope(message="Fixed-frame event buffer settlement rejected runtime frame 30", count=1, operation="Player.advance_action_frame(frame=30)", scope_id="1:1"):
    begin = {"schema_version": 1, "scope_id": scope_id, "operation": operation, "expected": [{"message": message, "count": count}]}
    end = {"schema_version": 1, "scope_id": scope_id, "operation": operation, "result": False}
    return "PLANEWALKER_EXPECTED_ENGINE_ERROR_BEGIN " + json.dumps(begin), "PLANEWALKER_EXPECTED_ENGINE_ERROR_END " + json.dumps(end)


class RuntimeLogValidationContract(unittest.TestCase):
    def validator(self):
        self.assertIsNotNone(api, "strict executable runtime log parser must exist")
        return api.validate_log

    def test_clean_logs_and_exact_scoped_refusals_pass(self):
        validate = self.validator()
        validate("Godot Engine\nPASS: all assertions succeeded\n")
        for scope_id in ["1:1", "-9223371505285462056:1"]:
            begin, end = scope(scope_id=scope_id)
            validate("\n".join([begin, "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30", "   at: push_error (core/variant/variant_utility.cpp:1024)", end]), allow_expected_test_errors=True)

    def test_unscoped_and_extra_or_missing_errors_refuse(self):
        validate = self.validator()
        begin, end = scope()
        for log in ["ERROR: unexpected", "\n".join([begin, end]), "\n".join([begin, "ERROR: other frame", end]), "\n".join([begin, "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30", "ERROR: extra", end]), "\n".join([begin, "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30", "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30", end])]:
            with self.subTest(log=log), self.assertRaises(ValueError):
                validate(log, allow_expected_test_errors=True)

    def test_script_errors_and_leaks_are_never_expected(self):
        validate = self.validator()
        for message in ["SCRIPT ERROR: Invalid call", "Parse Error: missing token", "ObjectDB instances leaked at exit", "RID allocations leaked at exit", "Invalid call. Nonexistent function", "Failed loading resource res://bad.tscn"]:
            begin, end = scope(message)
            with self.subTest(message=message), self.assertRaises(ValueError):
                validate("\n".join([begin, "ERROR: " + message, end]), allow_expected_test_errors=True)

    def test_malformed_nested_reused_and_unclosed_scopes_refuse(self):
        validate = self.validator()
        begin, end = scope()
        for log in [begin, end, begin + "\n" + begin + "\n" + end, begin + "\n" + scope(scope_id="1:2")[1], begin + "\n" + "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30\n" + end + "\n" + begin, "PLANEWALKER_EXPECTED_ENGINE_ERROR_BEGIN malformed", "noise " + begin, begin.replace('"count": 1', '"count": true') + "\n" + end, begin.replace('"count": 1', '"count": 0') + "\n" + end, begin.replace('"schema_version": 1', '"schema_version": true') + "\n" + end, begin.replace('"expected":', '"extra": 1, "expected":') + "\n" + end, end.replace('"result": false', '"result": true')]:
            with self.subTest(log=log), self.assertRaises(ValueError):
                validate(log, allow_expected_test_errors=True)

    def test_scope_cannot_relax_production_scan(self):
        validate = self.validator()
        begin, end = scope()
        with self.assertRaises(ValueError):
            validate("\n".join([begin, "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30", end]))

    def test_message_counts_completion_operation_and_duplicate_json_keys_are_strict(self):
        validate = self.validator()
        begin, end = scope(count=2)
        error = "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30"
        validate("\n".join([begin, error, error, end]), allow_expected_test_errors=True)
        for log in ["\n".join([begin, error, end]), "\n".join([begin, error, error, end.replace("frame=30", "frame=31")]), "\n".join([begin.replace('"schema_version": 1', '"schema_version": 1, "schema_version": 1'), error, error, end])]:
            with self.subTest(log=log), self.assertRaises(ValueError):
                validate(log, allow_expected_test_errors=True)

    def test_every_independent_log_file_is_checked(self):
        self.validator()
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "stdout.log"
            second = Path(directory) / "engine.log"
            first.write_text("PASS: all assertions succeeded\n")
            second.write_text("ERROR: engine-only failure\n")
            with self.assertRaises(ValueError):
                api.validate_logs([first, second], allow_expected_test_errors=True)
            begin, end = scope()
            first.write_text("\n".join([begin, "ERROR: Fixed-frame event buffer settlement rejected runtime frame 30", end]))
            second.write_text("PASS: all assertions succeeded\n")
            with self.assertRaises(ValueError):
                api.validate_logs([first, second], allow_expected_test_errors=True)
            second.unlink()
            with self.assertRaises(ValueError):
                api.validate_logs([first, second], allow_expected_test_errors=True)


if __name__ == "__main__":
    unittest.main()
