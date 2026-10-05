# Native Void Exposure Query Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Current Void auxiliary exposure cutoff observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-unified-hotpath-diagnostic-evidence.md`
- Last Verified: 2026-10-06

## Measured Problem

The retained `10a3e96` diagnostic observes 261 Boss exposure checks and 240
Character-tail checks in 120 actual native frames. Their auxiliary observation
needs only the current exposure cutoff, but captures a complete detached Void
history. These two sites account for approximately 0.65 ms per measured frame.

## Narrow Change

Add a Void auxiliary-owned integer cutoff query. Both Boss sites retain their
original comparison against the Boss frame, original terminal handling and
short-circuit order. The query adds no auxiliary-clock or terminal rule. A
query-less component retains the original complete-snapshot observation.
Snapshots, validation, receipts, restoration and gameplay values remain intact.

## Executable Acceptance

RED uses counted real Void auxiliary authority to prove the original repeated
Boss and Character-tail checks capture complete histories. GREEN must make zero
such captures and preserve both original boolean algorithms through initial
state, a real phase change, authored warning and tentacle activation, the exact
inclusive exposure cutoff, expiry, terminal state and historical rollback.
Direct current cutoff changes must be observed immediately. Foreign query-less
fallback must still capture once per check. Existing complete comparison, Boss
UI, auxiliary, conversion and actual native frame contracts must remain clean.
Integrated performance is a separate gate.
