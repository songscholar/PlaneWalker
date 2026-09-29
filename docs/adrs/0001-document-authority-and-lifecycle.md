# ADR 0001: Document Authority and Lifecycle

- Status: Approved / Current
- Document Role: Current architecture decision
- Authority Level: Accepted repository governance decision
- Applies To: Documentation authority order, Current/Historical lifecycle, conflicts, amendments, and supersession
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/contracts/document-governance-v1.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Decision Status: Accepted

## Context

Plane Walker contains product specifications, implementation plans, executable contracts, completion evidence, legacy design material, and project-wide authorization rules. Before P8, several completed plans still appeared Current, active plans lacked explicit lifecycle metadata, and no accepted ADR defined how conflicts or governance changes should be resolved.

The repository needs one authority chain that preserves verified history without allowing Historical documents to schedule new work. It also needs an amendment mechanism that does not erase the reasoning behind an accepted decision.

## Decision

Plane Walker uses this descending authority order:

1. [`AGENTS.md`](../../AGENTS.md) controls standing authorization, safety boundaries, external-operation limits, engineering rules, and the full authorized product scope.
2. Accepted ADRs in the [ADR index](README.md) control reviewed architecture and governance decisions. A later accepted ADR may supersede an earlier ADR only through an explicit link and lifecycle transition.
3. The Current [Full Product Completion Design](../superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md) controls product scope, canonical counts and IDs, architecture authorities, delivery gates, and terminal completion criteria.
4. Current contracts control stable data formats, trust boundaries, compatibility behavior, and executable validation rules. Current implementation plans control execution order, file ownership, TDD steps, and exit gates without overriding a higher authority.
5. Current engineering documents may explain an implementation but cannot override a contract, plan, specification, ADR, or `AGENTS.md`.
6. Historical documents preserve decisions, implementation evidence, rollback points, and regression obligations. They cannot authorize, prioritize, or schedule new work.

When two documents at the same authority level conflict, the more specific Current document governs its declared `Applies To` scope. If specificity does not resolve the conflict, work stops only on the conflicting decision and a new ADR resolves it; unrelated authorized work continues.

## Lifecycle rules

The [Document Governance v1 Contract](../contracts/document-governance-v1.md) defines executable metadata and link validation.

- `Current` means the document participates in the active authority, execution, contract, protocol, evidence, or index chain.
- `Historical` means the document preserves completed, superseded, or archived evidence and constraints but does not create a new task queue.
- Completion of an implementation slice is recorded under `Implementation Status` when its evidence remains Current.
- A completed or superseded plan becomes a Historical implementation record and retains its completion evidence.
- External work remains Current with `External Validation Pending`; repository automation never relabels missing human, credential, platform, commercial, or publication evidence as complete.

## Amendment and supersession

This accepted decision may receive spelling, formatting, and link repairs that do not change meaning. Any change to the authority order, lifecycle vocabulary, conflict rule, or supersession process requires a new numbered ADR.

The new ADR must:

1. identify ADR 0001 as the decision being replaced;
2. explain the new evidence or constraint;
3. state the replacement decision and consequences;
4. be added exactly once to the ADR index;
5. change ADR 0001 `Decision Status` from `Accepted` to `Superseded` and link back to the replacement.

## Consequences

- Agents can determine which document governs without conversational permission or undocumented judgment.
- Completed plans remain useful regression evidence but cannot accidentally reactivate old implementation order.
- Current contracts and plans remain independently editable within their declared scope while higher-level product and safety authority stays stable.
- Governance changes become reviewable, reversible Git history rather than silent edits to prior reasoning.
- The ADR index and decision status are enforced offline by `tools/document_governance.py` and the unified repository validation entrypoint.

## Verification

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --baseline tools/document_governance_baseline.json
```
