# Native Action Validation Template Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Boss historical Action validation-only configuration work
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-unified-hotpath-diagnostic-evidence.md`
- Last Verified: 2026-10-06

## Measured Problem

The frozen `10a3e96` native diagnostic configures 1,099 Action coordinators in
120 measured frames, consuming 1.712 exclusive ms per frame. Boss historical
validation repeatedly builds independent mutable Action objects even when it
only needs the parsed actions, actor kind, initial identity and definition
digest. The snapshot validator itself does not mutate these inputs.

## Narrow Change

Extract the original Action snapshot checks into one pure static validator.
Live coordinators call that same validator with their live configured authority.
Boss validation may use a privately retained, recursively read-only normalized
template produced by a successfully configured fresh Action. It must reuse the
complete typed configuration context already computed by `can_restore_snapshot`;
it must not serialize another large key. Phase, enrage, current/historical Void
geometry and current/historical Time response flags remain separate exact key
fields. Direct definition, origin and initial-state mutations remain visible.

Retain at most four templates. Each retained context plus normalized template
must fit 262,144 encoded bytes, and total retained encoded authority must stay
within 1,048,576 bytes. Oversized sources use the complete uncached path. A
failed configuration never populates the cache and retains the original cold
fallback. Actual Boss restoration and action-regime changes continue to create
independent mutable Action coordinators. Templates cannot certify a complete
Boss snapshot or bypass strict native auxiliary, receipt or physical checks.

## Executable Acceptance

RED counts fresh Action construction in repeated full uncached Boss validation.
GREEN must reduce repeated validation-only construction to zero after a valid
template is retained. The original current/historical regimes, typed guards,
geometry and receipt checks must remain executable. Five authored Bosses,
all phase/enrage and historical flag combinations, warm/cold snapshots,
direct configured-authority mutation, negative configuration, independent
mutable restoration, concurrent read-only access, entry eviction and byte
limits must have focused contracts. Existing direct-mutation and full Boss,
Action, native transaction and replay contracts remain required.

This is a configuration-work optimization. The 16.667 ms frame budget,
rendered verification, soak and human playtesting remain independent gates.
