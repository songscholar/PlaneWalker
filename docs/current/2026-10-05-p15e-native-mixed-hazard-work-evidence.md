# P15E Native Mixed Hazard Work

- Status: retained implementation evidence; full Boss and enemy production scope remains active
- Document Role: Current implementation and verification evidence
- Authority Level: retained milestone evidence
- Applies To: native hostile pending work, mixed zone admission and room completion
- Owner: Plane Walker implementation team
- Depends On: P15D semantic effects `cb1b4db`, P15B native temporal Router `738a252`
- Last Verified: 2026-10-05

## Accepted Behavior

The room ledger now owns a sealed aggregate of native projectile, payload-zone and semantic-zone work. It cannot clear a room while an independently owned semantic hazard remains active or queued after its original enemy dies. The aggregate shares one twelve-zone admission budget: visible warnings count toward the cap, queued zones retain their authored lifetime and acquire a complete new warning when admitted.

Executable acceptance criteria:

1. A real Chrono Guard emits one corridor after its complete warning. Its authentic native death removes the roster body while the corridor remains pending room work.
2. Room completion occurs exactly once at frame 426, after the corridor's authored 360-frame lifetime. Rejection of that last retirement restores the hazard, room clock and pending work; retry publishes one completion.
3. Twelve actual native semantic projections prevent an independent queued death pool from becoming visible or damaging. Their expiry frees a shared slot at frame 37; the admitted death pool starts its thirty-frame warning at age zero and deals its sole 8 HP burst at frame 67.
4. Both child states can be individually valid while their combined visible count exceeds twelve. The shared Router rejects that snapshot before native restoration.
5. Rejection and retry of mixed admission or damage preserve the queued work, warning clock, native projections and Player HP, with one accepted damage observation.
6. Native target identities shared between Actor and target maps must refer to the same native body. Ambiguous identities fail before preparing a child transaction.
7. The Chrono Guard corridor deals its authored 28 HP initial slash once, then retains slow for its finite lifetime without repeating that initial damage at frame 126.

## Implementation

`LaunchHostileEffectAuthority.work_snapshot()` returns `{run_id, runtime_frame, records}`. `prepared_work_transition(ticket)` exposes the before/after work records of an authentic effect ticket. `LaunchEncounterFrameAuthority` validates, stages, compensates and publishes this aggregate rather than counting only payload rows. Existing payload APIs remain available to their callers.

Payload admission receives the current semantic visible count; semantic admission receives the candidate payload visible count. Expired hazards release slots, existing visible hazards retain ownership, and remaining reservations wait. Snapshot validation also enforces the combined cap.

The Router forwards `bind_native_targets()` for immediate semantic status reconstruction on a cold restore and `dispose_native_effects()` for owned Player/Actor status cleanup on native teardown. Native driver integration and semantic status disposal validation belong to P16R/P15D, respectively.

## Verification

- Native room-work RED: `planewalker-tests.cLHBqC`, missing corridor reservation after actual owner death.
- Native room-work GREEN: `planewalker-tests.6nk4Tf`, `launch_semantic_router`, 1/1.
- Initial-only corridor damage RED: `planewalker-tests.NRSHko`, actual Player lost a second 28 HP at frame 126.
- Final native room-work and initial-only damage GREEN: `planewalker-tests.WkmAen`, `launch_semantic_router`, 1/1.
- Native mixed projection / shared cap / complete queued warning GREEN: `planewalker-tests.tx2M8y`, `launch_mixed_zone_budget`, 1/1.
- Existing actual Moth projectile / death-pool / impact-pool room completion: `planewalker-tests.PSqe7D`, 1/1.
- Payload deterministic runtime: `planewalker-tests.dS2rmH`, 1/1.
- Semantic native sink and Router: `planewalker-tests.YL6Sq1`, 2/2.
- Native effects and ambiguous target-identity boundary: `planewalker-tests.NFBXGo`, 1/1.
- Boss temporal regressions: `planewalker-tests.ukxMFJ`, 2/2.
- Final P15D dependency regressions: shared mixed budget `planewalker-tests.yi2Zz8`, 1/1; semantic sink and Router `planewalker-tests.5qDhNV`, 2/2; native effects `planewalker-tests.BfP5Bi`, 1/1; payload runtime `planewalker-tests.6dC6Gh`, 1/1; Boss temporal `planewalker-tests.X8kYlx`, 2/2.
- Final test runner scans found no script/load failures or known leak warnings. GDScript line coverage is unavailable, so no coverage percentage is claimed.
- The existing pinned development dependency audit was attempted with `python3 -m pip_audit -r requirements-dev.txt --no-deps --disable-pip --cache-dir build/p15-pip-audit-cache --timeout 10 --progress-spinner off`; this fresh advisory query could not resolve `pypi.org` in the sandbox. No dependency was added or changed. Earlier P16 evidence records a successful audit of the same pin; this milestone does not claim a new online audit.

## Remaining Work

This milestone certifies mixed native hazard lifetime and room ownership, not every authored hostile mechanic. Full arena constructs, weapon-targetable Boss weakpoints, summons, links, portals and the remaining phase mechanics still need native implementation and tests. P15D `cb1b4db` separates initial-only area damage from authored periodic damage; the actual Chrono Guard regression above verifies its shared Router integration.

No remote push, publication or purchase occurred. A precise local commit preserves this milestone for review and rollback without disturbing unrelated workspace changes.
