# Native Boss Contact Refresh Evidence

- Status: Retained / Current
- Document Role: Current native Boss collision-query refresh regression evidence
- Authority Level: Approved P15 specification and project standing authorization
- Applies To: Actual Hitbox contact dispatch and native Boss arena projections
- Owner: Native hostile integration team
- Depends On: `docs/superpowers/plans/2026-10-05-native-boss-loadout-matrix.md`
- Last Verified: 2026-10-05

## Trigger And Repair

The canonical60Hz Sword matrix crossed the Void Boss phase-three threshold
from the actual Hitbox `area_entered` callback. Health and native damage claims
committed correctly, but the damaged signal immediately added four new core
collision bodies while Godot was flushing physics queries. Godot emitted
body/area shape errors, so the matrix must fail even though its gameplay
assertions reached final death.

Hitbox now exposes its synchronous contact-dispatch depth. Boss presentation
coalesces refresh requests within that dispatch and projects the latest native
state through `call_deferred` after queries finish. Damage, phase, claims and
death receipts remain synchronous. Preparation, rollback, cold reconstruction
and all refreshes outside contact dispatch still project synchronously. This
flag is a presentation scheduling signal, not damage authentication authority.

## Executable Evidence

`native_void_collision_refresh_test` uses a real Hitbox under the actual Player
Sword adapter. Its physical contacts commit an authenticated P3 transition,
a finite core break and final Boss death. It checks that the contact callback
retains the old four-node topology, the next frame owns eight exact projected
constructs, the broken core loses bodyHP once and terminal constructs have no
live collision or visibility.

- Semantic RED: `build/test-evidence/native-void-collision-refresh-owned-red`,
  failed with the original query-flush errors and premature core topology.
- GREEN: `build/test-evidence/native-void-collision-refresh-final`,1/1 with no
  engine/script error or leak diagnostics.
- Existing `void_arena_native_test`:1/1 GREEN under
  `build/test-evidence/native-void-collision-existing-isolated`, preserving
  synchronous phase rollback/retry, physical Save/Replay cold reconstruction,
  all five normal weapon contacts and terminal collision retirement.
- Existing `boss_watch_native_test`:1/1 GREEN under
  `build/test-evidence/native-contact-boss-watch-regression`.
- Existing `boss_arena_native_test`:1/1 GREEN under
  `build/test-evidence/native-contact-boss-arena-valid-target`, preserving
  all weapon cover contacts, native phase/death aftershock retirement and
  rollback/retry/cold arena projection.

The Void Save fixture now uses the runner's isolated test-data root. A stale
fixed `build/test-data/void-arena` profile with another content binding caused
an unrelated Save refusal; the clean pre-fix archive passed that same fixture.
The Ruin arena fixture now supplies the accepted `pending_target` alias for
body hits and waits for contact projection before inspecting construct nodes.
Its pre-fix immutable archive independently reproduced six body-authentication
failures with the obsolete `pending_cover` alias.

The original canonical Sword0--29 run completed all30 gameplay cases and66792
accepted frames, but all five engine-log shards retain query-flush errors.
`build/p15-native-canonical-clock-sword-thirty.json` remains a failing diagnostic
report. A final immutable-source matrix must rerun all750 combinations.
