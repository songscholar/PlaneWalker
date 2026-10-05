# Void Half Arena Implementation Plan

- Status: Completed
- Document Role: Historical implementation plan
- Authority Level: Execution details below approved P15 section 7.5
- Applies To: Void End, enrage half geometry and native cold recovery
- Owner: Native Boss implementation lead
- Last Verified: 2026-10-05
- Depends On: `AGENTS.md`, `../specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Exit Gate: Domain and native marked half, opposite safe route, alternating enrage, TTL300, core interruption, rollback and cold migration pass without script errors or leaks.
- Implementation Status: Implemented and focused verified
- Completion Evidence: `../../current/2026-10-05-void-half-native-warning-evidence.md`

## Design

Use one shared deterministic geometry helper for the action coordinator and
Void auxiliary validation. The 640x360 room has a horizontal 640px line of
half-width 90 at local y90 or y270. Void End also marks two radius24 circles at
local x176/464 in the opposite half. A centered 48px route in that half remains
clear for a radius14 Player. Geometry is frozen against room corners and never
tracks Boss or Player motion after warning.

Enrage commits alternate top/bottom using a finite accepted-commit counter.
Void Boss snapshot8 stores the counter. Exact historical snapshot1/5/7 action
digests remain reconstructible and preserve already warned source-relative
geometry; the next idle action regime switches to the new recipe. Authored
content remains sealed: runtime projection supplies the verified replacement.

## Execution

- [x] Add meaningful failing room translation, safe-route, alternating enrage and native hit tests.
- [x] Implement shared recipe, anchored action commits and strict auxiliary validation.
- [x] Migrate historical snapshots without changing in-flight warnings or settled identities.
- [x] Verify native TTL300, actual damage, core-break interruption, accepted-frame rollback and fresh physical cold recovery.
- [x] Project all actual primary warnings and persist exact half geometry through zone expiry.
- [x] Record evidence, update plan and document index, and retain a focused local commit.
