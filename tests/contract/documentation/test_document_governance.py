from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from document_governance import validate_repository  # noqa: E402


CURRENT_PLAN = """# Current plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Test authority
- Applies To: Test current work
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29
- Exit Gate: The focused contract passes

## Work
"""

HISTORICAL_PLAN = """# Historical plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Preserved test evidence
- Applies To: Completed test work
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29
- Implementation Status: Verified locally
- Completion Evidence: Commit `0123456` and focused contract

## Outcome
"""

CURRENT_ROLE_COMPLETED_STATUS = CURRENT_PLAN.replace(
    "Status: Active / Current",
    "Status: Completed / Historical",
)

VALID_CURRENT_SPEC = """# 设计

- Status: Approved / Current
- Document Role: Current specification
- Authority Level: Test authority
- Applies To: Encoded link target
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29

## 决策
"""

VALID_CURRENT_EVIDENCE_WITH_ENCODED_LINK = """# Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Test evidence
- Applies To: Encoded relative links
- Owner: Test owner
- Depends On: [设计](../%E8%AE%BE%E8%AE%A1.md)
- Last Verified: 2026-09-29

The [design](../%E8%AE%BE%E8%AE%A1.md) is available offline.
"""

VALID_CURRENT_EVIDENCE_WITH_ESCAPE_LINK = VALID_CURRENT_EVIDENCE_WITH_ENCODED_LINK.replace(
    "../%E8%AE%BE%E8%AE%A1.md",
    "../../../outside.md",
)

VALID_DOCUMENT_WITH_CODE_LINK_SYNTAX = """# Examples

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Test evidence
- Applies To: Markdown parser exclusions
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29

Inline code is `label](missing-inline.md)` and must not be parsed.

```gdscript
var typed_array := []([])
[example](missing-fenced.md)
```
"""

LEGACY_CONTRACT = """# Legacy contract

- Status: Approved / Current
- Document Role: Current contract
- Authority Level: Test authority
- Applies To: Baseline behavior
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29
"""


class DocumentGovernanceTest(unittest.TestCase):
    def test_valid_current_plan_and_historical_plan_pass(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/superpowers/plans/current.md", CURRENT_PLAN)
            write_document(root / "docs/superpowers/plans/history.md", HISTORICAL_PLAN)

            report = validate_repository(root)

        self.assertEqual(report.violations, ())
        self.assertTrue(report.ok)

    def test_required_metadata_is_reported_with_stable_ids(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/current/evidence.md",
                "# Evidence\n\n- Status: Active / Current\n",
            )

            report = validate_repository(root)

        violation_ids = {item.violation_id for item in report.violations}
        self.assertIn(
            "docs/current/evidence.md::missing_metadata::Document Role",
            violation_ids,
        )
        self.assertIn(
            "docs/current/evidence.md::missing_metadata::Last Verified",
            violation_ids,
        )

    def test_metadata_must_follow_the_first_h1(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/current/evidence.md",
                VALID_CURRENT_SPEC.replace(
                    "- Owner: Test owner\n",
                    "",
                )
                + "\n- Owner: Test owner\n",
            )

            report = validate_repository(root)

        codes = {item.code for item in report.violations}
        self.assertIn("missing_metadata", codes)
        self.assertIn("metadata_outside_header", codes)

    def test_current_and_historical_roles_cannot_contradict_status(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/superpowers/plans/wrong.md",
                CURRENT_ROLE_COMPLETED_STATUS,
            )

            report = validate_repository(root)

        self.assertIn(
            "lifecycle_status_mismatch",
            {item.code for item in report.violations},
        )

    def test_current_plan_requires_exit_gate(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/superpowers/plans/current.md",
                CURRENT_PLAN.replace("- Exit Gate: The focused contract passes\n", ""),
            )

            report = validate_repository(root)

        self.assertIn(
            "docs/superpowers/plans/current.md::missing_metadata::Exit Gate",
            {item.violation_id for item in report.violations},
        )

    def test_historical_plan_requires_completion_fields(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/superpowers/plans/history.md",
                HISTORICAL_PLAN.replace(
                    "- Completion Evidence: Commit `0123456` and focused contract\n",
                    "",
                ),
            )

            report = validate_repository(root)

        self.assertIn(
            "docs/superpowers/plans/history.md::missing_metadata::Completion Evidence",
            {item.violation_id for item in report.violations},
        )

    def test_relative_links_percent_decode_and_resolve_inside_repository(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/设计.md", VALID_CURRENT_SPEC)
            write_document(
                root / "docs/current/index.md",
                VALID_CURRENT_EVIDENCE_WITH_ENCODED_LINK,
            )

            report = validate_repository(root)

        self.assertEqual(report.violations, ())

    def test_relative_links_may_not_escape_repository(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/current/index.md",
                VALID_CURRENT_EVIDENCE_WITH_ESCAPE_LINK,
            )

            report = validate_repository(root)

        self.assertIn(
            "link_outside_repository",
            {item.code for item in report.violations},
        )

    def test_missing_relative_link_is_reported(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/current/index.md",
                VALID_CURRENT_EVIDENCE_WITH_ENCODED_LINK.replace(
                    "../%E8%AE%BE%E8%AE%A1.md",
                    "../missing.md",
                ),
            )

            report = validate_repository(root)

        self.assertIn("missing_link_target", {item.code for item in report.violations})

    def test_absolute_local_link_is_rejected(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/current/index.md",
                VALID_CURRENT_EVIDENCE_WITH_ENCODED_LINK.replace(
                    "../%E8%AE%BE%E8%AE%A1.md",
                    "/docs/absolute.md",
                ),
            )

            report = validate_repository(root)

        self.assertIn("absolute_local_link", {item.code for item in report.violations})

    def test_external_and_fragment_links_are_not_dereferenced(self) -> None:
        with repository_fixture() as root:
            document = VALID_CURRENT_SPEC + (
                "\n[Web](https://example.invalid/docs) "
                "[Mail](mailto:test@example.invalid) [Section](#决策)\n"
            )
            write_document(root / "docs/current/evidence.md", document)

            report = validate_repository(root)

        self.assertEqual(report.violations, ())

    def test_fenced_and_inline_examples_are_not_parsed_as_links(self) -> None:
        with repository_fixture() as root:
            write_document(
                root / "docs/current/example.md",
                VALID_DOCUMENT_WITH_CODE_LINK_SYNTAX,
            )

            report = validate_repository(root)

        self.assertEqual(report.violations, ())

    def test_exact_baseline_suppresses_known_debt(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/contracts/legacy.md", LEGACY_CONTRACT)
            baseline = root / "tools/document_governance_baseline.json"
            write_baseline(
                baseline,
                ["docs/contracts/legacy.md::missing_metadata::Owner"],
            )

            report = validate_repository(root, baseline)

        self.assertEqual(report.new_violation_ids, ())
        self.assertEqual(report.stale_baseline_ids, ())
        self.assertTrue(report.ok)

    def test_baseline_rejects_new_and_stale_entries(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/contracts/legacy.md", LEGACY_CONTRACT)
            baseline = root / "tools/document_governance_baseline.json"
            write_baseline(
                baseline,
                ["docs/contracts/legacy.md::missing_metadata::Not A Real Field"],
            )

            report = validate_repository(root, baseline)

        self.assertIn(
            "docs/contracts/legacy.md::missing_metadata::Owner",
            report.new_violation_ids,
        )
        self.assertEqual(
            report.stale_baseline_ids,
            ("docs/contracts/legacy.md::missing_metadata::Not A Real Field",),
        )
        self.assertFalse(report.ok)

    def test_invalid_baseline_schema_fails_closed(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/contracts/legacy.md", LEGACY_CONTRACT)
            baseline = root / "tools/document_governance_baseline.json"
            baseline.parent.mkdir(parents=True, exist_ok=True)
            baseline.write_text(
                json.dumps({"schema_version": 2, "allowed_violation_ids": []}),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "schema_version"):
                validate_repository(root, baseline)

    def test_cli_json_and_exit_status_match_report(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/contracts/legacy.md", LEGACY_CONTRACT)
            result = subprocess.run(
                [
                    sys.executable,
                    str(PROJECT_ROOT / "tools/document_governance.py"),
                    "--project-root",
                    str(root),
                    "--json",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(payload["ok"])
        self.assertIn(
            "docs/contracts/legacy.md::missing_metadata::Owner",
            payload["new_violation_ids"],
        )

    def test_refresh_baseline_writes_sorted_exact_ids(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/contracts/legacy.md", LEGACY_CONTRACT)
            baseline = root / "tools/document_governance_baseline.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(PROJECT_ROOT / "tools/document_governance.py"),
                    "--project-root",
                    str(root),
                    "--baseline",
                    str(baseline),
                    "--refresh-baseline",
                    "--json",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            payload = json.loads(baseline.read_text(encoding="utf-8"))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(
            payload["allowed_violation_ids"],
            sorted(payload["allowed_violation_ids"]),
        )
        self.assertEqual(len(payload["allowed_violation_ids"]), 1)

    def test_project_validation_runs_documentation_contracts(self) -> None:
        validation_script = (PROJECT_ROOT / "tools/validate_project.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            "python3 -m unittest tests.contract.documentation.test_document_governance",
            validation_script,
        )
        self.assertIn("python3 tools/document_governance.py", validation_script)
        self.assertIn("tools/document_governance_baseline.json", validation_script)

    def test_repository_documents_have_complete_metadata_and_lifecycle(self) -> None:
        report = validate_repository(
            PROJECT_ROOT,
            PROJECT_ROOT / "tools/document_governance_baseline.json",
        )
        forbidden_codes = {
            "missing_metadata",
            "empty_metadata",
            "metadata_outside_header",
            "ambiguous_lifecycle",
            "lifecycle_status_mismatch",
            "invalid_verified_date",
        }

        remaining = [
            violation.violation_id
            for violation in report.violations
            if violation.code in forbidden_codes
        ]

        self.assertEqual(remaining, [])


@contextmanager
def repository_fixture() -> Iterator[Path]:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        (root / "tools").mkdir(parents=True)
        yield root


def write_document(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_baseline(path: Path, violation_ids: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "allowed_violation_ids": violation_ids,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    unittest.main()
