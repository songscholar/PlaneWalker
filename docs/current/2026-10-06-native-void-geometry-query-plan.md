# Native Void Geometry Query Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Native Void arena geometry and active pickup observation
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-hostile-boundary-query-evidence.md`
- Last Verified: 2026-10-06

## Measured Problem

The unified native diagnostic calls Boss physical geometry validation 1,200
times across 120 frames. Void physical geometry and refresh currently copy
complete arena events and auxiliary cast/receipt histories to obtain current
construct rows and active pickups. Those histories grow during real admission
and later measured frames.

## Narrow Change

Add a Void arena-owned detached projection of current arena origin, terminal
state, pillars and cores. Add Boss query wrappers for that projection and the
existing detached `VoidAuxiliaryRuntime.active_pickups()` API. Use these only
at native Void internal geometry and presentation observation sites. Preserve
original full-snapshot fallbacks for query-less runtime implementations.

No query certifies state for restoration or skips physical checks. Complete
public snapshots, every accepted cast/resource receipt, full restoration,
preparation, rollback, cold validation and recorder data remain authoritative.
No auxiliary validation implementation, capacity or gameplay value changes.

## Executable Acceptance

Retain one missing-query assertion as RED without parse/script failures or
leaks before production edits. GREEN must compare exact typed bytes with the
original full projection across live damage, phase transition, second-round
regeneration, retirement, historical restoration and changed arena origin.
Every nested query output must be detached. Existing active pickup semantics
must remain exact for consumption, expiration, phase retirement and rollback.

An actual authored Void actor with counted real arena/auxiliary domains must
make zero complete domain captures in narrow geometry, pickup refresh and
physical validation. Full public snapshots must retain one original capture.
All physical node/shape checks must still refuse tampering. Query-less runtime
fallbacks must preserve original complete projections. Run the actual Void
Player frame, Boss actor/transaction, Bridge and enemy contracts with strict
scoped logs, then retain uninstrumented timing on an isolated source.
