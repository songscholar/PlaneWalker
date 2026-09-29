# Plane Walker P8 Documentation Governance Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Preserved P8 documentation-governance regression evidence
- Applies To: Documentation metadata, lifecycle labels, internal links, ADRs, release evidence language, and offline validation
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Implementation Status: Verified locally; governed metadata, lifecycle roles, relative links, ADR indexing, Current indexing, evidence states, and the empty migration baseline pass the unified repository gate
- Completion Evidence: Commits `7dc7260`, `85a9a42`, `74ed576`, and `272a6b2`; see `docs/current/2026-09-29-p8-document-governance-evidence.md`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish executable documentation governance so the repository has one truthful offline-verifiable map of Current authority, Historical records, contracts, ADRs, and release evidence.

**Architecture:** A Python standard-library validator parses the metadata block immediately below each Markdown H1, classifies lifecycle from `Document Role`, validates repository-relative links without network access, and emits stable violation IDs. A checked-in migration baseline exposes existing debt while making new debt fail closed; later tasks normalize every governed document and reduce that baseline to an empty list. ADR and evidence indexes use the same metadata vocabulary and are validated through the existing project entrypoint.

**Tech Stack:** Python 3 standard library, `unittest`, Markdown metadata conventions, JSON migration baseline, Bash validation entrypoint.

## Global Constraints

- The validator must never perform a network request and must not require a third-party Markdown package.
- Governed Markdown includes `docs/README.md`, `docs/current/*.md`, `docs/contracts/*.md`, `docs/adrs/*.md`, `docs/superpowers/specs/*.md`, and `docs/superpowers/plans/*.md`; template JSON files are not Markdown governance subjects.
- Every governed document requires `Status`, `Document Role`, `Authority Level`, `Applies To`, `Owner`, `Depends On`, and ISO date `Last Verified` immediately below its first H1.
- `Document Role` must contain exactly one lifecycle word: `Current` or `Historical`.
- A Current role may not use `Completed`, `Historical`, `Archived`, or `Superseded` in `Status`; a Historical role must use one of `Completed`, `Historical`, `Archived`, or `Superseded` in `Status`.
- Current implementation plans require a non-empty `Exit Gate`; Historical implementation plans require non-empty `Implementation Status` and `Completion Evidence`.
- Repository-local Markdown destinations must be relative to the source document, remain inside the repository, percent-decode before filesystem resolution, and exist with exact case. HTTP(S), `mailto:`, and fragment-only links are allowed but are not dereferenced.
- Fenced and inline code are examples, not links, and are excluded from link validation.
- The migration baseline may suppress only an exact stable violation ID. New violations and stale baseline entries both fail validation.
- Documentation may use only these evidence states for release claims: `Implemented`, `Verified Locally`, `External Validation Pending`, and `Published`.
- No task may change P4 application/dungeon files, P6 input files, or P7 export implementation files.
- `docs/README.md` and the full-product Completion Spec are changed only after the validator and its contract tests pass independently.

---

### Task 1: Add the offline document-governance contract

**Files:**
- Create: `tools/document_governance.py`
- Create: `tools/document_governance_baseline.json`
- Create: `tests/contract/documentation/__init__.py`
- Create: `tests/contract/documentation/test_document_governance.py`
- Modify: `tools/validate_project.sh`
- Modify: `tools/test_ci_contract.sh`

**Interfaces:**
- Consumes: repository root `Path`, governed Markdown files, and JSON object `{ "schema_version": 1, "allowed_violation_ids": [str, ...] }`.
- Produces: `Violation(code: str, path: str, line: int, subject: str, message: str)` with stable `violation_id`; `validate_repository(project_root: Path, baseline_path: Path | None = None) -> ValidationReport`; CLI exit `0` only when there are no unbaselined violations and no stale baseline IDs.

- [ ] **Step 1: Write failing metadata, lifecycle, link, baseline, and entrypoint tests**

```python
class DocumentGovernanceTest(unittest.TestCase):
    def test_valid_current_plan_and_historical_plan_pass(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/superpowers/plans/current.md", CURRENT_PLAN)
            write_document(root / "docs/superpowers/plans/history.md", HISTORICAL_PLAN)
            self.assertEqual(validate_repository(root).violations, ())

    def test_required_metadata_is_reported_with_stable_ids(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/current/evidence.md", "# Evidence\n\n- Status: Active / Current\n")
            report = validate_repository(root)
            self.assertIn(
                "docs/current/evidence.md::missing_metadata::Document Role",
                {item.violation_id for item in report.violations},
            )

    def test_current_and_historical_roles_cannot_contradict_status(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/superpowers/plans/wrong.md", CURRENT_ROLE_COMPLETED_STATUS)
            report = validate_repository(root)
            self.assertIn("lifecycle_status_mismatch", {item.code for item in report.violations})

    def test_relative_links_percent_decode_and_must_resolve_inside_repository(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/设计.md", VALID_CURRENT_SPEC)
            write_document(root / "docs/current/index.md", VALID_CURRENT_EVIDENCE_WITH_ENCODED_LINK)
            self.assertEqual(validate_repository(root).violations, ())
            write_document(root / "docs/current/index.md", VALID_CURRENT_EVIDENCE_WITH_ESCAPE_LINK)
            self.assertIn("link_outside_repository", {item.code for item in validate_repository(root).violations})

    def test_fenced_examples_are_not_parsed_as_links(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/current/example.md", VALID_DOCUMENT_WITH_CODE_LINK_SYNTAX)
            self.assertEqual(validate_repository(root).violations, ())

    def test_exact_baseline_suppresses_known_debt_but_rejects_new_and_stale_entries(self) -> None:
        with repository_fixture() as root:
            write_document(root / "docs/contracts/legacy.md", LEGACY_CONTRACT)
            baseline = root / "tools/document_governance_baseline.json"
            write_baseline(baseline, ["docs/contracts/legacy.md::missing_metadata::Owner"])
            report = validate_repository(root, baseline)
            self.assertNotIn("docs/contracts/legacy.md::missing_metadata::Owner", report.new_violation_ids)
            self.assertEqual(report.stale_baseline_ids, ())
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v`

Expected: `ERROR` because `tools/document_governance.py` does not exist.

- [ ] **Step 3: Implement deterministic parsing and validation**

```python
@dataclass(frozen=True, order=True)
class Violation:
    code: str
    path: str
    line: int
    subject: str
    message: str

    @property
    def violation_id(self) -> str:
        return f"{self.path}::{self.code}::{self.subject}"


@dataclass(frozen=True)
class ValidationReport:
    violations: tuple[Violation, ...]
    allowed_violation_ids: tuple[str, ...]
    new_violation_ids: tuple[str, ...]
    stale_baseline_ids: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.new_violation_ids and not self.stale_baseline_ids


def validate_repository(
    project_root: Path,
    baseline_path: Path | None = None,
) -> ValidationReport:
    documents = discover_governed_documents(project_root)
    violations = tuple(sorted(issue for path in documents for issue in validate_document(project_root, path)))
    allowed = load_baseline(baseline_path) if baseline_path else ()
    actual_ids = {issue.violation_id for issue in violations}
    return ValidationReport(
        violations=violations,
        allowed_violation_ids=tuple(sorted(allowed)),
        new_violation_ids=tuple(sorted(actual_ids - set(allowed))),
        stale_baseline_ids=tuple(sorted(set(allowed) - actual_ids)),
    )
```

The CLI accepts `--project-root`, `--baseline`, `--json`, and `--refresh-baseline`. Normal validation is read-only. `--refresh-baseline` writes sorted unique IDs only after parsing succeeds and prints the exact output path and count.

- [ ] **Step 4: Generate the explicit migration baseline and verify GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --project-root . \
  --baseline tools/document_governance_baseline.json \
  --refresh-baseline
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --project-root . \
  --baseline tools/document_governance_baseline.json
```

Expected: contract tests pass; repository validation prints every explicitly baselined violation as legacy debt, reports `new=0` and `stale=0`, and exits `0`.

- [ ] **Step 5: Connect the contract to the existing validation entrypoints**

Add this block before localization validation in `tools/validate_project.sh`:

```bash
printf '\n== Documentation governance contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
    --baseline tools/document_governance_baseline.json
```

Add exact `assert_file_contains` checks for both commands to `tools/test_ci_contract.sh`.

- [ ] **Step 6: Run focused integration checks and commit**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
bash -n tools/validate_project.sh tools/test_ci_contract.sh
git diff --check
```

Expected: all commands pass; no P4, P6, or P7 implementation file appears in the diff.

Commit:

```bash
git add \
  docs/superpowers/plans/2026-09-29-plane-walker-p8-document-governance.md \
  tools/document_governance.py \
  tools/document_governance_baseline.json \
  tools/validate_project.sh \
  tools/test_ci_contract.sh \
  tests/contract/documentation/__init__.py \
  tests/contract/documentation/test_document_governance.py
git commit -m "feat(docs): enforce offline governance contracts"
```

### Task 2: Normalize all governed metadata and lifecycle roles

**Files:**
- Create: `docs/contracts/document-governance-v1.md`
- Modify: `docs/current/*.md`
- Modify: `docs/contracts/save-service-v1.md`
- Modify: `docs/contracts/content-pack-v2.md`
- Modify: `docs/superpowers/specs/*.md`
- Modify: `docs/superpowers/plans/*.md`
- Modify: `tools/document_governance_baseline.json`
- Test: `tests/contract/documentation/test_document_governance.py`

**Interfaces:**
- Consumes: Task 1 metadata and lifecycle parser.
- Produces: one normalized metadata block per governed document and a reduced baseline containing only link/index debt reserved for Tasks 3–4.

- [ ] **Step 1: Add failing repository assertions for every governed document**

```python
def test_repository_documents_have_complete_metadata_and_lifecycle(self) -> None:
    report = validate_repository(PROJECT_ROOT, PROJECT_ROOT / "tools/document_governance_baseline.json")
    forbidden = {"missing_metadata", "metadata_outside_header", "ambiguous_lifecycle", "lifecycle_status_mismatch"}
    self.assertEqual([issue for issue in report.violations if issue.code in forbidden], [])
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance.DocumentGovernanceTest.test_repository_documents_have_complete_metadata_and_lifecycle -v`

Expected: FAIL listing exact legacy documents and missing or contradictory fields.

- [ ] **Step 3: Publish the exact governance contract**

`docs/contracts/document-governance-v1.md` must define the seven required fields, lifecycle vocabulary, plan-specific fields, evidence-state vocabulary, relative-link rules, baseline removal rule, and these canonical examples:

```markdown
- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: P8 foundation execution plan
- Applies To: Documentation metadata, lifecycle labels, internal links, ADRs, and release evidence language
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Exit Gate: The governance baseline is empty and `./tools/validate_project.sh` passes
```

```markdown
- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Preserved regression evidence
- Applies To: Rewind Echo, Boss telegraphs, elite active mechanics, and authored five-room encounters
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Implementation Status: Verified locally by the Wave 4B focused and unified regression suites
- Completion Evidence: Commits `d17f641`, `651c53b`, `d9aa3f6`, `20bd93f`, and `cd647e2`
```

- [ ] **Step 4: Normalize lifecycle metadata without changing product claims**

Classify active P4/P5, P6, P7/P9, P8, the Completion Spec, and externally pending M1 evidence as Current. Classify completed Wave plans, completed foundation plans, superseded staged designs, and superseded presentation designs as Historical. Keep completed evidence in `docs/current/` as `Current evidence record` when it remains part of the active certification chain; use `Implementation Status` to state the completed slice instead of putting `Completed` in a Current `Status`.

- [ ] **Step 5: Remove resolved baseline IDs and verify GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --baseline tools/document_governance_baseline.json \
  --refresh-baseline
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
```

Expected: no metadata or lifecycle violation remains; the baseline shrinks and stays sorted.

- [ ] **Step 6: Commit normalized metadata**

```bash
git add docs/contracts/document-governance-v1.md docs/current docs/contracts docs/superpowers tools/document_governance_baseline.json tests/contract/documentation/test_document_governance.py
git commit -m "docs(governance): normalize lifecycle metadata"
```

### Task 3: Establish the ADR authority chain

**Files:**
- Create: `docs/adrs/README.md`
- Create: `docs/adrs/0001-document-authority-and-lifecycle.md`
- Modify: `tests/contract/documentation/test_document_governance.py`
- Modify: `tools/document_governance_baseline.json`

**Interfaces:**
- Consumes: governed metadata and relative-link validation from Task 1.
- Produces: a Current ADR index and first accepted ADR with immutable numeric ID, decision state, consequences, supersession rules, and links to the Completion Spec and governance contract.

- [ ] **Step 1: Add failing ADR index and decision tests**

```python
def test_adr_index_covers_every_numbered_adr(self) -> None:
    report = validate_repository(PROJECT_ROOT, PROJECT_ROOT / "tools/document_governance_baseline.json")
    self.assertEqual([issue for issue in report.violations if issue.code.startswith("adr_")], [])
```

The validator requires each `docs/adrs/[0-9][0-9][0-9][0-9]-*.md` document to contain `Decision Status: Accepted` or `Decision Status: Superseded`, and requires `docs/adrs/README.md` to link to each numbered ADR exactly once.

- [ ] **Step 2: Run the ADR test and verify RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance.DocumentGovernanceTest.test_adr_index_covers_every_numbered_adr -v`

Expected: FAIL because the ADR index and ADR 0001 do not exist.

- [ ] **Step 3: Write ADR 0001 and the complete index**

ADR 0001 records: `AGENTS.md` safety/authorization is highest repository authority; accepted ADRs follow; the Current Completion Spec follows; Current plans/contracts follow; Historical documents preserve evidence but cannot schedule new work. It also records that changing authority or lifecycle vocabulary requires a new superseding ADR rather than editing the accepted decision silently.

- [ ] **Step 4: Verify and commit the ADR chain**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
git diff --check
```

Commit:

```bash
git add docs/adrs tools/document_governance_baseline.json tests/contract/documentation/test_document_governance.py
git commit -m "docs(adr): establish authority decision chain"
```

### Task 4: Make the README and release evidence state truthful and complete

**Files:**
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: `docs/current/2026-09-28-m1-release-report.md`
- Modify: `docs/current/2026-09-29-p7-p9-export-certification-evidence.md`
- Modify: `tests/contract/documentation/test_document_governance.py`
- Modify: `tools/document_governance_baseline.json`

**Interfaces:**
- Consumes: normalized lifecycle roles and ADR index.
- Produces: one README map that lists every Current plan/spec/contract/ADR and uses only the four release evidence states; Completion Spec governance text links to the executable contract.

- [ ] **Step 1: Add failing Current-index and evidence-state tests**

```python
def test_readme_indexes_every_current_authority(self) -> None:
    report = validate_repository(PROJECT_ROOT, PROJECT_ROOT / "tools/document_governance_baseline.json")
    self.assertEqual([issue for issue in report.violations if issue.code == "current_document_unindexed"], [])

def test_release_documents_use_canonical_evidence_states(self) -> None:
    report = validate_repository(PROJECT_ROOT, PROJECT_ROOT / "tools/document_governance_baseline.json")
    self.assertEqual([issue for issue in report.violations if issue.code == "invalid_evidence_state"], [])
```

- [ ] **Step 2: Run both tests and verify RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance.DocumentGovernanceTest.test_readme_indexes_every_current_authority tests.contract.documentation.test_document_governance.DocumentGovernanceTest.test_release_documents_use_canonical_evidence_states -v`

Expected: FAIL with the exact unindexed Current paths and non-canonical evidence labels.

- [ ] **Step 3: Update the README map without changing implementation truth**

Add links for the P8 plan, documentation-governance contract, ADR index, all active Current plans, all retained Current evidence, and the authoritative Completion Spec. Preserve `M1 Candidate — External Validation Pending`, `0 / 20` authentic human sessions, and the P7/P9 coverage/template blockers.

- [ ] **Step 4: Link the Completion Spec governance section to executable policy**

Keep product counts and phase status unchanged. Add the P8 contract, ADR index, canonical evidence states, and the exact command:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
```

- [ ] **Step 5: Normalize release evidence states and verify GREEN**

Use `Evidence Status: External Validation Pending` for M1 and P7/P9 documents. Do not claim `Published`; do not convert missing human sessions, coverage, templates, signing, or public release into repository-complete evidence.

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json --refresh-baseline
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
```

- [ ] **Step 6: Commit the authoritative documentation map**

```bash
git add docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md docs/current/2026-09-28-m1-release-report.md docs/current/2026-09-29-p7-p9-export-certification-evidence.md tools/document_governance_baseline.json tests/contract/documentation/test_document_governance.py
git commit -m "docs(governance): publish current authority map"
```

### Task 5: Eliminate the migration baseline and certify P8

**Files:**
- Create: `docs/current/2026-09-29-p8-document-governance-evidence.md`
- Modify: `tools/document_governance_baseline.json`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: `docs/superpowers/plans/2026-09-29-plane-walker-p8-document-governance.md`
- Test: `tests/contract/documentation/test_document_governance.py`

**Interfaces:**
- Consumes: Tasks 1–4 and the unified validation entrypoint.
- Produces: empty baseline `{ "schema_version": 1, "allowed_violation_ids": [] }`, P8 completion evidence, Historical plan status, and P8 completion status in the README and Completion Spec.

- [ ] **Step 1: Add the zero-baseline completion test**

```python
def test_p8_completion_has_no_baselined_or_new_violations(self) -> None:
    report = validate_repository(PROJECT_ROOT, PROJECT_ROOT / "tools/document_governance_baseline.json")
    self.assertEqual(report.allowed_violation_ids, ())
    self.assertEqual(report.violations, ())
    self.assertTrue(report.ok)
```

- [ ] **Step 2: Run the completion test and verify RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance.DocumentGovernanceTest.test_p8_completion_has_no_baselined_or_new_violations -v`

Expected: FAIL while any explicit migration debt remains.

- [ ] **Step 3: Resolve every remaining link, index, ADR, or metadata issue**

Run `python3 tools/document_governance.py --baseline tools/document_governance_baseline.json --json` after each repair. Remove each resolved ID rather than replacing it with a broader exemption. The final baseline is exactly:

```json
{
  "schema_version": 1,
  "allowed_violation_ids": []
}
```

- [ ] **Step 4: Run the P8 verification matrix**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
bash tools/test_ci_contract.sh
VALIDATION_LOG_DIR=/tmp/planewalker-p8-validation ./tools/validate_project.sh
rg -n "SCRIPT ERROR:|Parse Error:|Failed to load script|ObjectDB instances leaked|RID allocations leaked" /tmp/planewalker-p8-validation
git diff --check
```

Expected: documentation tests, CI contract, and unified validation pass; the final `rg` has no unclassified project error or new leak.

- [ ] **Step 5: Record exact evidence and lifecycle transition**

The evidence document records commit hashes, all commands and counts, empty-baseline proof, known external limitations, and rollback points. Change this plan to `Status: Completed / Historical`, `Document Role: Historical implementation record`, add `Implementation Status` and `Completion Evidence`, and mark P8 Completed in the README and Completion Spec without altering P4, P6, P7, P9, or M1 truth.

- [ ] **Step 6: Commit P8 certification**

```bash
git add docs/current/2026-09-29-p8-document-governance-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md docs/superpowers/plans/2026-09-29-plane-walker-p8-document-governance.md tools/document_governance_baseline.json tests/contract/documentation/test_document_governance.py
git commit -m "docs(governance): certify P8 completion"
```

## Plan Self-Review

- Spec coverage: README, Current specs, contracts, ADRs, Historical labels, link/status validation, release evidence honesty, test integration, and P8 certification each have an executable task.
- Placeholder scan: the plan contains no deferred implementation markers; every task names exact files, interfaces, commands, expected states, and commit boundaries.
- Type consistency: every task uses the same `Violation`, `ValidationReport`, `validate_repository`, stable violation ID, baseline schema, and CLI options introduced in Task 1.
- Parallel safety: Task 1 changes only documentation tooling, its tests, the P8 plan, and shared validation shell scripts; it does not edit P4 application/dungeon, P6 input, or P7 export files.
