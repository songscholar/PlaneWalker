# Native Boss State Comparison Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Complete live Boss state equality observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-boss-ui-query-evidence.md`
- Last Verified: 2026-10-06

## Measured Problem

The frozen `10a3e96` diagnostic captures 2,660 complete Boss snapshots and
3,179 complete Void auxiliary snapshots in 120 accepted native frames. Void
auxiliary copies alone consume 4.120 exclusive ms per frame. Some observations
only compare the complete live state with a detached transaction checkpoint.
They do not need another detached copy of every history and receipt.

## Narrow Change

Add runtime-owned `matches_snapshot(value)` predicates. Leaf authorities compare
their complete live state using the original Godot dictionary equality. Boss
composition compares every live base field and every configured child
authority. Unknown or missing fields preserve the original verdict. No live
references escape through this boolean API. Public snapshots retain their
deeply detached output. Historical validation, restoration, compensation
checkpoints, physical checks and native publication remain authoritative.

The Actor integration is a separately owned slice: it may use the predicate for
the runtime portion of an equality-only check and must preserve all remaining
Actor fields and the original complete-snapshot fallback.

## Executable Acceptance

Retain the missing Boss predicate as a clean RED. GREEN must compare all five
authored Bosses against the original complete-snapshot algorithm through
configuration, authored warning/active/recovery/idle, controls and exposure,
phase transition, terminal state and historical rollback. Every nested scalar
mutation, missing and extra field must preserve the old verdict, including
Godot's original integer/float numerical equality. Count every configured
component and prove repeated comparisons take zero complete Boss or leaf
snapshots. Public snapshot output mutation must leave accepted state unchanged.
Parallel read-only comparisons must remain consistent. Existing Boss and
auxiliary validation and native transaction contracts must continue to pass
strict paired runtime-log validation.

Operation counts prove eliminated copies only. Uninstrumented integrated frame
timing, sustained throughput, rendered performance, soak and human playtesting
remain separate acceptance gates.
