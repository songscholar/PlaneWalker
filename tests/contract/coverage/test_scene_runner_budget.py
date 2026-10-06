from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
LOCAL_RECORDS = "tests/integration/save/local_run_records_test.tscn"
NATIVE_CHECKPOINT = "tests/integration/save/native_combat_checkpoint_test.tscn"
NATIVE_MIGRATION = "tests/integration/save/native_content_migration_test.tscn"
CONTROLLER_FLOW = "tests/integration/ui/p14_controller_flow_test.tscn"


class SceneRunnerBudgetTest(unittest.TestCase):
    def run_fixture(self, scene: str, *, instrumented: bool = False, complete_after: int = 4,
                    timeout: int = 1, missing_identity: str = "", runtime_error: bool = False,
                    manifest_digest: str = "a" * 64):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / scene).parent.mkdir(parents=True)
            (root / scene).write_text("fixture scene\n", encoding="utf-8")
            (root / "tools/coverage").mkdir(parents=True)
            for source in ["tools/run_tests.sh", "tools/runtime_log_validation.py",
                           "tools/coverage/collect_gdscript_coverage.py"]:
                shutil.copy2(ROOT / source, root / source)
            fake_engine = root / "fake-godot"
            fake_engine.write_text(ENGINE_FIXTURE, encoding="utf-8")
            fake_engine.chmod(0o755)
            clock = root / "clock.sh"
            clock.write_text(CLOCK_FIXTURE, encoding="utf-8")
            environment = dict(os.environ)
            for name in ["PLANEWALKER_COVERAGE_MANIFEST_SHA256", "PLANEWALKER_COVERAGE_HITS_DIR",
                         "GDSCRIPT_COVERAGE_PROVIDER_REPORT"]:
                environment.pop(name, None)
            environment.update({
                "GODOT_BIN": str(fake_engine), "TEST_LOG_DIR": str(root / "logs"),
                "BASH_ENV": str(clock), "PW_BUDGET_CLOCK": str(root / "clock.steps"),
                "PW_BUDGET_COMPLETE_AFTER": str(complete_after),
                "PW_BUDGET_RUNTIME_ERROR": "1" if runtime_error else "0",
            })
            if instrumented:
                environment["PLANEWALKER_COVERAGE_MANIFEST_SHA256"] = manifest_digest
                environment["PLANEWALKER_COVERAGE_HITS_DIR"] = str(root / "hits")
            if missing_identity:
                environment.pop(missing_identity, None)
            result = subprocess.run(
                ["bash", str(root / "tools/run_tests.sh"), "--timeout", str(timeout)],
                cwd=root, env=environment, text=True, capture_output=True, timeout=15, check=False,
            )
            return result.returncode, result.stdout + result.stderr

    def test_instrumented_save_boundaries_receive_their_bounded_budget(self):
        for scene in [LOCAL_RECORDS, NATIVE_CHECKPOINT, NATIVE_MIGRATION]:
            with self.subTest(scene=scene):
                status, output = self.run_fixture(scene, instrumented=True)
                self.assertEqual(status, 0, output)
                self.assertIn("Scene tests: 1 passed, 0 failed, 1 total", output)
                self.assertIn("Code coverage: not collected", output)

    def test_instrumented_five_floor_controller_flow_receives_its_bounded_budget(self):
        status, output = self.run_fixture(CONTROLLER_FLOW, instrumented=True)
        self.assertEqual(status, 0, output)
        self.assertIn("Scene tests: 1 passed, 0 failed, 1 total", output)
        status, output = self.run_fixture(CONTROLLER_FLOW)
        self.assertEqual(status, 1, output)
        self.assertIn(f"[  TIMEOUT ] {CONTROLLER_FLOW} (300s)", output)

    def test_ordinary_save_budget_is_unchanged_and_reports_effective_timeout(self):
        for scene in [LOCAL_RECORDS, NATIVE_CHECKPOINT, NATIVE_MIGRATION]:
            with self.subTest(scene=scene):
                status, output = self.run_fixture(scene)
                self.assertEqual(status, 1, output)
                self.assertIn(f"[  TIMEOUT ] {scene} (300s)", output)
                self.assertIn("Scene tests: 0 passed, 1 failed, 1 total", output)

    def test_both_instrumentation_identity_fields_are_required(self):
        for field in ["PLANEWALKER_COVERAGE_MANIFEST_SHA256", "PLANEWALKER_COVERAGE_HITS_DIR"]:
            with self.subTest(field=field):
                status, output = self.run_fixture(LOCAL_RECORDS, instrumented=True, missing_identity=field)
                self.assertEqual(status, 1, output)
                self.assertIn(f"[  TIMEOUT ] {LOCAL_RECORDS} (300s)", output)
        status, output = self.run_fixture(LOCAL_RECORDS, instrumented=True, manifest_digest="invalid")
        self.assertEqual(status, 1, output)
        self.assertIn(f"[  TIMEOUT ] {LOCAL_RECORDS} (300s)", output)

    def test_unrelated_scenes_remain_bounded_and_explicit_larger_budget_is_respected(self):
        status, output = self.run_fixture("tests/unrelated_test.tscn", instrumented=True)
        self.assertEqual(status, 1, output)
        self.assertIn("[  TIMEOUT ] tests/unrelated_test.tscn (1s)", output)
        status, output = self.run_fixture(LOCAL_RECORDS, instrumented=True, complete_after=10, timeout=1200)
        self.assertEqual(status, 0, output)

    def test_instrumented_budget_still_terminates_hangs_and_rejects_script_errors(self):
        status, output = self.run_fixture(LOCAL_RECORDS, instrumented=True, complete_after=100)
        self.assertEqual(status, 1, output)
        self.assertIn(f"[  TIMEOUT ] {LOCAL_RECORDS} (900s)", output)
        status, output = self.run_fixture(LOCAL_RECORDS, instrumented=True, runtime_error=True)
        self.assertEqual(status, 1, output)
        self.assertIn("runtime error in log", output)


# Advance the real shell watchdog without spending minutes on each fixture.
CLOCK_FIXTURE = """sleep() {
    local steps=0
    if [[ -f "${PW_BUDGET_CLOCK}" ]]; then
        read -r steps < "${PW_BUDGET_CLOCK}"
    fi
    printf '%s\\n' "$((steps + 1))" > "${PW_BUDGET_CLOCK}"
    SECONDS=$((SECONDS + 100))
    /bin/sleep 0.05
}
"""


ENGINE_FIXTURE = """#!/usr/bin/env python3
import os
import sys
import time
from pathlib import Path

if '--version' in sys.argv:
    print('fixture-godot')
    sys.exit(0)
if '--help' in sys.argv:
    print('fixture engine has no line-coverage capability')
    sys.exit(0)
clock = Path(os.environ['PW_BUDGET_CLOCK'])
complete_after = int(os.environ['PW_BUDGET_COMPLETE_AFTER'])
while True:
    try:
        steps = int(clock.read_text().strip())
    except (OSError, ValueError):
        steps = 0
    if steps >= complete_after:
        break
    time.sleep(0.005)
message = 'SCRIPT ERROR: budget fixture failure\\n' if os.environ['PW_BUDGET_RUNTIME_ERROR'] == '1' else 'PASS budget fixture\\n'
Path(sys.argv[sys.argv.index('--log-file') + 1]).write_text(message)
print(message, end='')
"""
