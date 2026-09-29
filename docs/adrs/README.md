# Plane Walker Architecture Decision Records

- Status: Approved / Current
- Document Role: Current ADR index
- Authority Level: Accepted architecture and governance decision index
- Applies To: Repository-wide architecture, authority, lifecycle, compatibility, and irreversible technical decisions
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/contracts/document-governance-v1.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29

## Purpose

This index is the authoritative list of accepted and superseded Plane Walker Architecture Decision Records. A numbered ADR is immutable decision history: later decisions supersede it explicitly instead of silently rewriting its meaning.

## Authority context

The decision chain is governed by:

1. [Project authorization and safety policy](../../AGENTS.md).
2. Accepted ADRs listed below.
3. [Full Product Completion Design](../superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md).
4. Current contracts and implementation plans indexed by the [documentation entrypoint](../README.md).
5. Historical documents, which preserve evidence but do not schedule new work.

Metadata, lifecycle, and link requirements are defined by the [Document Governance v1 Contract](../contracts/document-governance-v1.md).

## Decisions

| ID | Decision | Decision Status | Outcome |
|---|---|---|---|
| 0001 | [Document authority and lifecycle](0001-document-authority-and-lifecycle.md) | Accepted | Establishes the repository authority order, Current/Historical semantics, and supersession process |

## Decision maintenance

- Accepted decisions remain linked exactly once from this index.
- A replacement ADR receives the next unused four-digit ID, links the decision it replaces, and records `Decision Status: Accepted`.
- The replaced ADR changes only `Decision Status` to `Superseded` and adds a link to the replacement; its original context, decision, and consequences remain intact.
- Draft proposals are not assigned a numbered ADR filename. Numbered ADRs may use only `Accepted` or `Superseded`.
