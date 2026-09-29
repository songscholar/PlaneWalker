# Plane Walker P8 Documentation Governance Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P8 documentation-governance certification evidence
- Applies To: Governed metadata, Current/Historical lifecycle roles, relative links, ADR indexing, evidence-state vocabulary, Current authority indexing, and the migration baseline
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/contracts/document-governance-v1.md`, `docs/adrs/README.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p8-document-governance.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified Repository State: `bc34991` plus this documentation-certification commit
- Rollback Point: `7dc7260`

## Completion decision

P8 is locally complete. Every governed Markdown document has a valid metadata block, one unambiguous Current or Historical lifecycle role, an offline-resolvable repository link graph, and a truthful implementation/evidence state. The README directly indexes every Current specification, plan, contract, protocol, evidence record, and the ADR index.

The migration baseline is exactly:

```json
{
  "schema_version": 1,
  "allowed_violation_ids": []
}
```

No documentation exception, stale baseline entry, missing Current index entry, invalid ADR state, broken relative link, or non-canonical release evidence label remains.

This certification does not promote M1, exports, coverage, packaged startup, or publication. Those states remain governed by their own fail-closed evidence records.

## Certified implementation chain

| Commit | Deliverable |
|---|---|
| `7dc7260` | Adds the offline documentation-governance parser, CLI, contracts, baseline handling, and CI integration |
| `85a9a42` | Normalizes governed metadata and Current/Historical lifecycle roles |
| `74ed576` | Establishes the ADR index and accepted authority-chain decision |
| `272a6b2` | Publishes the complete Current authority map and canonical evidence-state vocabulary |
| `bc34991` | Verifies the expanded P4/P5 Current evidence remains indexed with zero governance violations |

## Executable governance boundary

The governed set is:

```text
docs/README.md
docs/current/*.md
docs/contracts/*.md
docs/adrs/*.md
docs/superpowers/specs/*.md
docs/superpowers/plans/*.md
```

The contract enforces:

- exact required metadata keys and real ISO dates;
- valid lifecycle pairing between `Status` and `Document Role`;
- `Exit Gate` for Current plans;
- `Implementation Status` and `Completion Evidence` for Historical plans;
- accepted/superseded ADR semantics and complete ADR indexing;
- direct README indexing of every Current authority document;
- canonical `Implemented`, `Verified Locally`, `External Validation Pending`, or `Published` evidence states where required;
- relative links that stay inside the repository, percent-decode correctly, exist with exact case, and resolve offline;
- an empty, sorted, duplicate-free migration baseline.

The repository completion test verifies all three P8 conditions together:

```python
self.assertEqual(report.allowed_violation_ids, ())
self.assertEqual(report.violations, ())
self.assertTrue(report.ok)
```

## Verification evidence

The focused commands are:

```text
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
bash tools/test_ci_contract.sh
VALIDATION_LOG_DIR=/tmp/planewalker-p8-validation ./tools/validate_project.sh
```

The final unified verification reports:

| Gate | Required result |
|---|---:|
| Documentation governance | 29 / 29 tests; zero violations, zero baselined, zero new, zero stale |
| CI contract | Full stable scene discovery, including all event contracts |
| Godot scene tests | 59 / 59 passed |
| Localization contracts | 7 / 7 passed |
| Playtest-data contracts | 13 / 13 passed |
| M1 release-gate contracts | 27 / 27 passed |
| GDScript coverage contracts | 5 / 5 passed |
| Export contracts | 37 / 37 passed |

The only accepted scene-suite warning remains the registered `reward_system_smoke` ObjectDB warning. Bootstrap and clean imports may report the approved macOS sandbox inability to persist global editor settings or read the system CA store; neither is a project error.

## Honest remaining boundaries

- Formal M1 remains `M1 Candidate — External Validation Pending` with authentic human evidence at `0 / 20`.
- GDScript line coverage remains unavailable and is not inferred from scene-test counts.
- Windows, Linux, and macOS export templates are absent locally; real export and packaged startup remain uncertified.
- No remote push, public publication, signing, store configuration, paid service, or private credential use occurred.

P8 is therefore `Verified Locally`. Its contract and evidence remain Current authority; its implementation plan is preserved as Historical regression evidence.
