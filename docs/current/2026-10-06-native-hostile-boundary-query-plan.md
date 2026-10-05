# Native Hostile Boundary Query Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Hostile Bridge run identity, frame clock and terminal observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-hostile-frame-query-evidence.md`
- Last Verified: 2026-10-06

## Measured Problem

The unified `abd5b6f` main-thread diagnostic makes 1,200 complete Actor runtime
observations in 120 accepted actual frames, consuming 2.040 ms per frame.
Bridge readiness runs twice and frame start once per frame; these observations
need only current run identity, clock and terminal state. Full frame-start
transaction compensation is a separate mandatory capture.

## Narrow Change

Add Boss-owned current run identity and Actor-owned detached three-field frame
boundary queries. Queries read current domain state every time; no shadow cache
or caller-supplied readiness certificate is used. Foreign runtimes and actors
without native query APIs retain their original complete-snapshot fallback.
Switch only Bridge scalar boundary observation sites. Keep its full transaction
checkpoint, restoration, health publication, physical geometry and receipt
authority behavior.

## Executable Acceptance

First retain the missing native API assertion as RED without parse errors or
leaks. GREEN uses counted actual runtimes for all five authored Boss scenes:
configuration/readiness must make zero complete runtime captures and frame
start must still make exactly one full compensation checkpoint. Real clock
advance must refuse stale readiness, historical rollback must restore complete
typed state, terminal mutation must preserve readiness and retirement, and
runtime reconfiguration must immediately refuse foreign run identity. Mutating
public boundary output must not mutate domain state. Ordinary enemy runtimes
without queries must still take exactly one original full-snapshot fallback.

Then run actual Bridge, Boss transaction, native Void frame, five-Boss frame
query and existing enemy contracts with strict logs. Retain an isolated complete
frame comparison before a later slice. This plan changes no admission rule,
validation, physical check, recorder capacity or gameplay value.
