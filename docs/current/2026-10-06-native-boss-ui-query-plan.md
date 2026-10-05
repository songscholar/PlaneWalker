# Native Boss UI Query Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan and executable acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Actual Boss UI observations shared by presentation and combat consumers
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-void-geometry-query-evidence.md`
- Last Verified: 2026-10-06

## Observed Problem

`PixelProxyActor._advance_animation()` calls the actual Boss UI endpoint on
every presentation process. The runtime Host also observes the endpoint when
rendering live HUD; projectile and control-conversion consumers share it.
Each call currently copies the complete Boss snapshot, including arena,
auxiliary and accepted event histories, to read the action, current frame and
three scalar mechanism fields. The unified diagnostic records 3,040 complete
Boss snapshots across 120 actual measured frames, but does not separately time
the UI endpoint. This slice makes no initial UI-specific timing claim.

## Narrow Change

Add a Boss-owned detached UI input projection with current frame, detached
action snapshot and phase/delay/enrage scalars. Use it only at the existing
Actor UI observation endpoint; runtimes without the query retain the original
full-snapshot fallback. Preserve exact endpoint field order, types, labels,
remaining-time calculation, actual Health values and exposure authority.

No state cache, presentation-owned clock, gameplay values, full snapshot
schema, restoration, receipts or physical checks change. Exposure still uses
its existing authoritative query.

## Executable Acceptance

Retain a counted actual five-Boss RED demonstrating repeated full captures
before production edits. GREEN must eliminate complete Boss captures for
repeated UI observation, retain exact typed output against the original full
algorithm through configured, warning, active, recovery, phase transition,
exposure, terminal and historical rollback states, and prove detached query
and endpoint output. Public full snapshots and query-less fallback must remain
complete. Run focused Boss, boundary, geometry, transaction, Bridge, Void,
enemy and presentation regressions with strict scoped logs. Retain later
integrated native measurement; snapshot counts alone do not certify FPS.
