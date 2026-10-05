# P15B Native Ruin Delayed Aftershock

- Status: Verified Locally; full Boss arena scope remains active
- Document Role: Current implementation and verification evidence
- Authority Level: Retained milestone evidence below the approved P15 Boss specification
- Applies To: Ruin slam aftershock, native payload admission, owner retirement and current cold reconstruction
- Owner: Plane Walker native Boss implementation lead
- Depends On: `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/plans/2026-10-05-native-boss-arena-constructs.md`
- Last Verified: 2026-10-05

## Accepted Behavior

The actual first active `guardian_fist_slam` hit emits one sealed arena payload request at its committed impact position. BossActor adds the actual declared room bounds and permits only the request retained in its prepared batch. The existing payload authority owns admission, native raster projection, telegraph facts, accepted Player damage and rollback.

The authored60-frame impact delay contains20 invisible dormant frames followed by40 complete visible warning frames. A slam at frame55 reserves a dormant payload; frame75 opens its own warning; frame115 deals12 physical damage once within radius32 and retires the hazard. Enrage scales damage to14.4. The warning uses the original `physical_pool.png` raster and an independent telegraph source. Dormant payloads remain invisible and register no threat facts. They conservatively reserve one shared zone slot; if all12 slots are occupied, admission waits and then preserves the complete dormant and warning durations. Stop pauses an admitted visible warning without spending its warning frames.

Phase-transition cues and terminal owner death retire the owner's pending aftershocks before activation. Terminal actors can be absent from prepared action batches, so the authority also inspects the retained actor roster. Rejected reservation, warning and impact frames restore the entire payload ledger, actual telegraphs and native projection. Player Health uses the enclosing Health transaction for candidate damage compensation; the combat bridge does not independently own that transaction.

Only the new `boss_aftershock` zone definition includes `delay_frames`; historical death and impact pool field sets remain exact. Cold validation omits both pending and dormant payloads when rebuilding required threat facts, while preserving their complete strict runtime state. The actual production Host captures both dormant and warning aftershocks through physical Profile/SaveService and resumes them in a fresh Main.

## Verification

- Native Boss arena `planewalker-tests.iYvWzT`,1/1: real slam reservation, exact55/75/115 timing, real12HP Player damage, complete refusal/retry at all three transitions, phase cancellation and terminal cancellation. Existing five-weapon cover, charge and beam tests also pass in this scene.
- Pure payload `planewalker-tests.z6pBfe`,1/1: strict aftershock fields, damage bounds, dormant invisibility facts, fresh warning continuation, shared12-zone admission and a three-frame Stop moving the sole accepted hit to frame63 with12 damage.
- Actual physical dormant checkpoint `planewalker-tests.SfQC2g`,1/1, and warning checkpoint `planewalker-tests.mQRQvz`,1/1: fresh native nodes and uninterrupted accepted Player/native continuation match after cold reconstruction.
- Boss Actor/payload/runtime `planewalker-tests.Nq1eaj`,3/3; semantic effects/router/Player weapon input `planewalker-tests.mWoDl6`,3/3. These regression logs contain no script errors or known leaks.
- Native GL capture `build/test-logs/p15b-native-arena/engine.log` passes without script errors or known leaks. Inspected640x360 and1280x720 warning captures are retained at `build/visual-evidence/p15b-native-arena/ruin-aftershock-warning-640x360.png` and `ruin-aftershock-warning-1280x720.png`. Raster path and at least four foreground colors are checked. These are focused native fixtures, not full production-room/UI certification.
- The first expanded17-case checkpoint run `planewalker-tests.94t4go` passed assertions but exposed four stale CombatFeedback deferred callbacks in the engine log. It is not retained as clean verification. A separate presentation lifecycle regression reproduces that error in `planewalker-tests.jcrU9y`; deferred spawn feedback now carries a WeakRef and ignores retired actors before calling its typed presentation endpoint.
- Clean full17-case physical checkpoint rerun `planewalker-tests.NIHMmP`,1/1, and presentation lifecycle regression `planewalker-tests.L7OsKA`,1/1, pass without engine errors or known leaks. The presentation fix is retained separately in `aa67d99`.
- Ordinary scene runs report `godot_line_coverage_unsupported`; these results claim no line-coverage percentage.

## Remaining Work

Ruin HP150/TTL600 walls, HP20/TTL480/cap4 debris, enrage cover retirement and combined48px escape certification remain open. Forest, Forge and Void construct interactions, authentic Time ability responses and the complete750 loadout/Boss matrix remain open. The Base descriptor still binds Boss room scenes rather than the native actor/art surface; no content fingerprint or authenticated historical descriptor transition changes in this slice.

No dependency changed, remote push, publication or purchase occurred. Source, tests and this focused evidence are retained through precise local commits.
