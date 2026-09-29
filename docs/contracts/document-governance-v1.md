# Plane Walker Document Governance v1 Contract

- Status: Approved / Current
- Document Role: Current contract
- Authority Level: Repository documentation metadata, lifecycle, and link-validation contract
- Applies To: `docs/README.md`, Current evidence, contracts, ADRs, specifications, and implementation plans
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Schema Version: `1`

## 1. Purpose

Plane Walker documentation is executable project state, not an informal collection of notes. This contract makes each governed document identify its authority, lifecycle, owner, dependency chain, and verification date in a format that can be checked without network access.

The offline validator is `tools/document_governance.py`. The repository gate invokes it through `tools/validate_project.sh`.

## 2. Governed documents

The following Markdown files are governed:

- `docs/README.md`;
- direct `*.md` children of `docs/current/`;
- direct `*.md` children of `docs/contracts/`;
- direct `*.md` children of `docs/adrs/` when that directory exists;
- direct `*.md` children of `docs/superpowers/specs/`;
- direct `*.md` children of `docs/superpowers/plans/`.

JSON templates under `docs/current/templates/` are governed by their data-schema tests rather than this Markdown metadata contract.

## 3. Required metadata block

Every governed document starts with one level-one Markdown title. The metadata block immediately follows that title and contains non-empty values for these exact case-sensitive keys:

- `Status`;
- `Document Role`;
- `Authority Level`;
- `Applies To`;
- `Owner`;
- `Depends On`;
- `Last Verified`.

`Last Verified` is a real ISO calendar date in `YYYY-MM-DD` form. Metadata repeated later in the document does not satisfy the header contract. Duplicate keys in the header are invalid.

A Current implementation plan also requires `Exit Gate`. A Historical implementation plan also requires `Implementation Status` and `Completion Evidence`.

Canonical Current-plan header:

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

Canonical Historical-plan header:

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

## 4. Lifecycle vocabulary

`Document Role` contains exactly one lifecycle word:

- `Current`: the document participates in the active authority, execution, contract, protocol, evidence, or index chain;
- `Historical`: the document preserves completed, superseded, or archived intent and evidence but does not schedule new work.

A Current document must not use `Completed`, `Historical`, `Archived`, or `Superseded` in `Status`. Completion of one implementation slice is recorded under `Implementation Status`, while `Status` continues to express that the evidence or contract remains Current.

A Historical document uses at least one of `Completed`, `Historical`, `Archived`, or `Superseded` in `Status`. A completed plan remains binding as regression evidence until a tested Current replacement supersedes its contracts.

Examples of valid lifecycle pairs:

| Status | Document Role |
|---|---|
| `Approved / Current` | `Current specification` |
| `Active / Current` | `Current implementation plan` |
| `Verified Locally / Current` | `Current evidence record` |
| `External Validation Pending / Current` | `Current evidence record` |
| `Frozen / Current` | `Current contract` |
| `Completed / Historical` | `Historical implementation record` |
| `Superseded / Historical` | `Historical specification` |

## 5. Relative-link contract

Repository-local Markdown destinations are relative to the document containing the link. They must:

- remain inside the repository after `..` resolution;
- percent-decode before filesystem resolution;
- exist with exact filename case;
- avoid absolute POSIX paths, Windows drive paths, and `file:` URLs.

HTTP, HTTPS, `mailto:`, and fragment-only links are accepted without network access. The validator never dereferences an external URL. Markdown-like examples inside fenced or inline code are not links.

## 6. Migration baseline

`tools/document_governance_baseline.json` is a temporary migration ledger, not a permanent exemption mechanism. Its exact schema is:

```json
{
  "schema_version": 1,
  "allowed_violation_ids": []
}
```

Each ID is stable as `path::code::subject`. The list is sorted and unique. Validation fails for both a new violation not present in the ledger and a stale ledger entry whose violation no longer exists. A resolved ID is removed immediately; broad wildcard exemptions are unsupported.

The final P8 exit gate requires an empty `allowed_violation_ids` list.

## 7. Verification commands

Focused contract:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance -v
```

Repository document check:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --baseline tools/document_governance_baseline.json
```

Refresh the exact migration ledger only after reviewing the reported violations:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
  --baseline tools/document_governance_baseline.json \
  --refresh-baseline
```

Unified repository gate:

```bash
./tools/validate_project.sh
```
