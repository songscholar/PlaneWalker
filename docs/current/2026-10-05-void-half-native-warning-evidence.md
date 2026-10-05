# Void Half Arena And Native Warning Evidence

- Status: Focused Verified / Combined certification pending
- Document Role: Current retention evidence
- Authority Level: Evidence below approved P15 specification
- Applies To: Void room-half geometry, snapshot8 migration and native hostile warnings
- Owner: Plane Walker native hostile team
- Last Verified: 2026-10-05
- Depends On: `../../AGENTS.md`, `../superpowers/plans/2026-10-05-void-half-arena.md`, `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`

## Retained Behavior

Void End marks the entire top half of its 640x360 room and two radius24 circles
in the opposite half. A centered 48px route stays clear for the radius14 Player.
An accepted enrage warning alternates top and bottom, including after intervening
attacks and interruption. A translated room and moving Boss or Player never move
the committed half. The global enrage damage1.20 and cooldown0.85 still apply.

Snapshot8 preserves the accepted half counter. Exact historical schemas1,5,7
retain their previous in-flight action digest and geometry; their next idle
regime uses the current recipe. Forged room anchors or parity refuse without
partial restoration. The auxiliary authority checks the same shared geometry.

Actual Boss and enemy Actors now display each committed threat fact during
warning and active frames. Cancellation, death and recovery remove primary
projections. Forest's separately verified root sweep keeps its dedicated cue.
The owner accepted clock drives projection; wall-clock processing is disabled.
Cone triangles and line capsules match the threat registry. Room bounds clip
primary projections. The persistent Void half zone uses the exact capsule,
clipped to the room, through its independent 300-frame lifetime.

## Executable Evidence

- Domain RED: `build/test-evidence/void-half-room-red-actual` lacked a complete
  translated half and snapshot8.
- Warning RED: `build/test-evidence/void-half-warning-red-actual` lacked all three
  native warning primitives before damage.
- Domain GREEN: `build/test-evidence/void-half-domain-retention`,1/1; translated
  origin(704,-384), full half, clear48px route, typed cold recovery, exact old
  warning, idle migration, 10800 real accepted enrage frames and core interruption.
- Native GREEN: `build/test-evidence/void-half-projection-native-green`,1/1;
  actual55 Health loss, rollback/retry, three zones, last live frame499 and expiry500,
  physical SaveService/Replay and fresh Boss/Player/Effects reconstruction.
- Historical GREEN: `void-half-auxiliary-migration` and
  `void-half-arena-migration`,1/1 each.
- Eight-Actor warning GREEN: `build/test-evidence/native-hostile-telegraph-clean`,
  1/1; five Bosses, Sentinel, Moth and Bramble, exact facts, cold restore and cancel.
- Boss runtime GREEN: `build/test-evidence/void-half-boss-runtime-current`,1/1;
  updated long battle identity retention and full separately warned Void Step
  follow-up. The previous512-history assertion and pre-follow-up schedule were
  obsolete after the retained native behavior changes.
- Existing telegraph GREEN: `hostile-telegraph-existing-regression`,1/1.

Actual native OpenGL/Metal captures at640x360,1280x720,2560x1080 require danger
pixels at the left, center and right of the marked half and no false danger in
the safe corridor. Warning, active and post-primary persistent poses produce
nine images in `build/void-half-native-screenshots/`. The stretched pool raster
failed three strict sample checks in `void-half-native-raster-final`; the exact
geometry repair passed `void-half-native-raster-corrected.godot.log`. The final
room-clipped capture `build/void-half-isolated-raster.godot.log` additionally
checks ultrawide side margins and passes all assertions. Its fixed source is
retained HEAD46f324e plus this milestone's exact files in
`build/test-source/void-half-retention/`. The same source passes warning1/1 and
native body settlement1/1 at `void-half-isolated-warning` and
`void-half-isolated-body`. Second-phase clean import has no script errors.

## Remaining Gates

This evidence does not certify all enemy/Boss mechanics, long complete-game
combat, instrumented line coverage or immutable-source release packages. Runs
contaminated by concurrently unfinished spatial parser changes remain failed
at `native-hostile-telegraph-final` and `void-half-boss-runtime-regression`;
their later parse-clean replacements above provide the valid evidence.
