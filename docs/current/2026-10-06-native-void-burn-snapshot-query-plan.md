# Native Void Burn Snapshot Query Plan

- Status: Approved / Current
- Document Role: Current focused gameplay performance execution plan
- Authority Level: Below approved full-product completion contract
- Applies To: Void candidate-frame burn request observation
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `docs/current/2026-10-06-native-unified-hotpath-diagnostic-evidence.md`

## Investigated Cause

The latest integrated diagnostic measures two private Boss preview restores per
frame, plus the real commit restore. Void's arena preview only reads
`void_burn_damage_requests` from the already generated candidate snapshot;
it performs no domain mutation. The body/arena previews together cost 8.162
inclusive ms per measured frame. That inclusive attribution does not isolate
this specific burn read or establish an optimization benefit.

## Narrow Change

Add an instance-owned full-snapshot burn query. Boss authority applies its
original complete `can_restore_snapshot` predicate to the supplied historical
or candidate state; the Void auxiliary applies its original complete child
validator. A shared internal read algorithm receives that validated state
without installing it. Existing live burn queries use the same algorithm.
No validator, accepted-boundary distinction, history, receipt, damage value,
frame rule, native geometry check or transaction rollback is removed.

Use this query only in the actual Void actor's candidate preparation. Runtimes
without the new method retain the original arena preview/restore algorithm.
Forest, Forge and Ruin previews still own real mutations and remain intact.

## Executable Acceptance

Before production edits retain missing-query and actual unnecessary arena-slot
failures. Generate a real Scepter cast and accepted damage receipt, then compare
all returned typed request fields against a separately restored original Boss
at warning, receipt, all six 30-frame ticks, exclusive expiry and terminal
boundaries. Queries of old states after live advance/terminal must retain exact
original input and live typed bytes. Caller request mutation must remain
detached. Wrong schemas, owner/definition, full Boss histories, derived burn
values and unrelated sub-authority corruption must still refuse after a valid
query. Actual native Void preparation must preserve its complete ticket/batch
bytes with the query-less fallback, own no extra arena preview on the query
path, and retain complete rollback. Run actual burn damage, rollback/retry,
pickups, Step, phase, cold storage and replay neighbors with strict paired logs.

Final integrated timing, sustained recording, RSS, rendered load and full
gameplay certification remain separate gates.
