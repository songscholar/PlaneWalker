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

EMPTY_ADR_INDEX = """# Architecture Decision Records

- Status: Approved / Current
- Document Role: Current ADR index
- Authority Level: Test ADR authority index
- Applies To: Repository architecture decisions
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29

No numbered decisions have been accepted.
"""

VALID_ADR = """# ADR 0001: Test decision

- Status: Approved / Current
- Document Role: Current architecture decision
- Authority Level: Accepted test decision
- Applies To: ADR contract fixtures
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29
- Decision Status: Accepted

## Decision

The fixture decision is accepted.
"""

VALID_ADR_INDEX = EMPTY_ADR_INDEX.replace(
    "No numbered decisions have been accepted.",
    "- [ADR 0001: Test decision](0001-test-decision.md)",
)

CURRENT_DOCUMENT_INDEX = """# Documentation index

- Status: Approved / Current
- Document Role: Current documentation index
- Authority Level: Test documentation index
- Applies To: Current test authorities
- Owner: Test owner
- Depends On: `AGENTS.md`
- Last Verified: 2026-09-29

- [ADR index](adrs/README.md)
"""

RELEASE_EVIDENCE_PATH = Path("docs/current/2026-09-28-m1-release-report.md")


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

    def test_adr_index_is_required(self) -> None:
        with repository_fixture() as root:
            (root / "docs/adrs/README.md").unlink()

            report = validate_repository(root)

        self.assertIn("adr_index_missing", {item.code for item in report.violations})

    def test_numbered_adr_requires_valid_decision_status(self) -> None:
        with repository_fixture() as root:
            adr_path = root / "docs/adrs/0001-test-decision.md"
            write_document(
                adr_path,
                VALID_ADR.replace("- Decision Status: Accepted\n", ""),
            )

            missing_report = validate_repository(root)
            write_document(
                adr_path,
                VALID_ADR.replace("Decision Status: Accepted", "Decision Status: Draft"),
            )
            invalid_report = validate_repository(root)

        self.assertIn(
            "adr_decision_status_missing",
            {item.code for item in missing_report.violations},
        )
        self.assertIn(
            "adr_decision_status_invalid",
            {item.code for item in invalid_report.violations},
        )

    def test_adr_index_links_every_numbered_adr_exactly_once(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/adrs/0001-test-decision.md", VALID_ADR)

            missing_report = validate_repository(root)
            write_document(
                root / "docs/adrs/README.md",
                VALID_ADR_INDEX
                + "\n- [Duplicate decision](0001-test-decision.md)\n",
            )
            duplicate_report = validate_repository(root)

        self.assertIn("adr_unindexed", {item.code for item in missing_report.violations})
        self.assertIn(
            "adr_duplicate_index_link",
            {item.code for item in duplicate_report.violations},
        )

    def test_valid_adr_chain_passes(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/adrs/0001-test-decision.md", VALID_ADR)
            write_document(root / "docs/adrs/README.md", VALID_ADR_INDEX)

            report = validate_repository(root)

        self.assertEqual(
            [item for item in report.violations if item.code.startswith("adr_")],
            [],
        )

    def test_repository_adr_index_covers_every_numbered_adr(self) -> None:
        self.assertTrue((PROJECT_ROOT / "docs/adrs/README.md").is_file())
        self.assertTrue(
            (
                PROJECT_ROOT
                / "docs/adrs/0001-document-authority-and-lifecycle.md"
            ).is_file()
        )
        report = validate_repository(
            PROJECT_ROOT,
            PROJECT_ROOT / "tools/document_governance_baseline.json",
        )

        self.assertEqual(
            [item for item in report.violations if item.code.startswith("adr_")],
            [],
        )

    def test_current_documents_must_be_linked_from_docs_readme(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/README.md", CURRENT_DOCUMENT_INDEX)
            write_document(root / "docs/contracts/current.md", VALID_CURRENT_SPEC)

            missing_report = validate_repository(root)
            write_document(
                root / "docs/README.md",
                CURRENT_DOCUMENT_INDEX
                + "\n- [Current contract](contracts/current.md)\n",
            )
            indexed_report = validate_repository(root)

        self.assertIn(
            "docs/README.md::current_document_unindexed::docs/contracts/current.md",
            {item.violation_id for item in missing_report.violations},
        )
        self.assertNotIn(
            "current_document_unindexed",
            {item.code for item in indexed_report.violations},
        )

    def test_release_evidence_requires_one_canonical_state(self) -> None:
        with repository_fixture() as root:
            evidence_path = root / RELEASE_EVIDENCE_PATH
            write_document(evidence_path, VALID_CURRENT_SPEC)
            missing_report = validate_repository(root)

            write_document(
                evidence_path,
                VALID_CURRENT_SPEC.replace(
                    "- Last Verified: 2026-09-29",
                    "- Last Verified: 2026-09-29\n- Evidence Status: Verified",
                ),
            )
            invalid_report = validate_repository(root)

            canonical_reports = []
            for evidence_status in (
                "Implemented",
                "Verified Locally",
                "External Validation Pending",
                "Published",
            ):
                write_document(
                    evidence_path,
                    VALID_CURRENT_SPEC.replace(
                        "- Last Verified: 2026-09-29",
                        "- Last Verified: 2026-09-29\n"
                        f"- Evidence Status: {evidence_status}",
                    ),
                )
                canonical_reports.append(validate_repository(root))

        self.assertIn(
            "invalid_evidence_state",
            {item.code for item in missing_report.violations},
        )
        self.assertIn(
            "invalid_evidence_state",
            {item.code for item in invalid_report.violations},
        )
        self.assertTrue(
            all(
                "invalid_evidence_state"
                not in {item.code for item in report.violations}
                for report in canonical_reports
            )
        )

    def test_repository_readme_indexes_every_current_authority(self) -> None:
        self.assertTrue((PROJECT_ROOT / "docs/README.md").is_file())
        report = validate_repository(
            PROJECT_ROOT,
            PROJECT_ROOT / "tools/document_governance_baseline.json",
        )

        self.assertEqual(
            [
                item.violation_id
                for item in report.violations
                if item.code == "current_document_unindexed"
            ],
            [],
        )

    def test_repository_release_documents_use_canonical_evidence_states(self) -> None:
        report = validate_repository(
            PROJECT_ROOT,
            PROJECT_ROOT / "tools/document_governance_baseline.json",
        )

        self.assertEqual(
            [
                item.violation_id
                for item in report.violations
                if item.code == "invalid_evidence_state"
            ],
            [],
        )

    def test_p8_completion_has_no_baselined_or_new_violations(self) -> None:
        report = validate_repository(
            PROJECT_ROOT,
            PROJECT_ROOT / "tools/document_governance_baseline.json",
        )

        self.assertEqual(report.allowed_violation_ids, ())
        self.assertEqual(report.violations, ())
        self.assertTrue(report.ok)


@contextmanager
def repository_fixture() -> Iterator[Path]:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        (root / "tools").mkdir(parents=True)
        write_document(root / "docs/adrs/README.md", EMPTY_ADR_INDEX)
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
