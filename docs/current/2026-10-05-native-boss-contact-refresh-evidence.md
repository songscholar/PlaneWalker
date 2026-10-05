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

The fixed-source `9c5d517` full matrix exposed a second boundary: its immediate
next `physics_frame` resumed before deferred presentation drained. All five
character shards completed their first Ruin case, then correctly refused the
next frame because cover HP had changed from80to2 while the actual cover still
projected80. The original `build/p15-native-9c5d517-source/build/p15-native-full.json`
is retained as a5/750 failing diagnostic, including the original preparation
and rollback failures. A pending Boss projection now flushes at transaction
checkpoint and frame preparation, after physical contact dispatch has ended.
Only an owned pending refresh triggers this work; ordinary geometry tampering
still reaches the strict geometry checks.

Bow, Gun and Staff projectile signals and Sword wave/zone signals now share
the contact-dispatch scope. Their swept/manual delivery keeps its synchronous
path. Gauntlets already defers its physical signal's target-hit execution and
needs no additional wrapper.

## Executable Evidence

`native_void_collision_refresh_test` uses a real Hitbox under the actual Player
Sword adapter. Its physical contacts commit an authenticated P3 transition,
a finite core break and final Boss death. It checks that the contact callback
retains the old four-node topology, the next frame owns eight exact projected
constructs, the broken core loses bodyHP once and terminal constructs have no
live collision or visibility.

The same regression now includes an actual Ruin cover contact followed by
immediate production `begin_frame`/`prepare_frame`/rollback, with no intervening
idle wait. Actual Bow, Gun and Staff query signals each cause a Void phase-three
transition and prove accepted HP is synchronous while collision-body creation
waits until after the callback. The semantic RED log at
`build/test-evidence/native-contact-next-frame-red-active-engine.log` retains
the Ruin preparation/rollback refusals and Bow query-flush errors. GREEN at
`build/test-evidence/native-contact-next-frame-all-projectiles` passes1/1 with
strict engine-log validation. Existing Ruin/Void/Time scenes pass3/3 under the
`native-contact-next-frame-{boss-arena,void-arena,boss-watch}` evidence roots.
All13native matrix report contracts also pass.
Gun projectile, Staff damage pipeline, Bow reward and Sword runtime regressions
pass4/4 under `native-contact-next-frame-{gun,staff,bow,sword}` evidence roots,
with strict logs preserving synchronous manual/swept delivery.

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
