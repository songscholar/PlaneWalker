# Native Forest Auxiliary Evidence

- Status: Focused Verified / Current
- Document Role: Current focused retention evidence
- Authority Level: Evidence below approved P15 specification
- Applies To: Forest auxiliary domain, native bodies, damage, recovery and presentation
- Depends On: [approved P15 enemies and bosses design](../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md), section 7.2; [focused plan](../superpowers/plans/2026-10-05-native-forest-auxiliary.md)
- Owner: Plane Walker implementation team
- Last Verified: 2026-10-05

## Behavior

The production Forest Boss preserves its six HP100 roots and adds four real HP30
sacs and three one-use healing flowers. Flowers heal only actual missing Player
HP, up to20, through HealthComponent. Full HP preserves the flower. Flowers and
arena fixtures do not become counted enemies or generate encounter rewards.

The seed freezes the nearest live sac for its complete40-frame warning.
Destroying that sac cancels the owned generation. The accepted burst deals35
within radius40 and owns a radius29 pool for480 frames, with12 damage every60
frames. Capacity-delayed pool admission receives a new complete40-frame warning.

The cage creates three HP50 physical segments around a48-pixel square with a
permanent32-pixel opening. Each inner pulse owns30 warning frames and deals8;
each surviving segment owns40 collapse warning frames and deals15. Segment
lifetime is300 accepted frames. Room bounds and physical collision are checked
at admission, commit and publication. A late obstacle refuses publication and
compensates geometry, HP, identities and effect reservations.

Drain freezes three lanes and resolves four offsets0/15/30/45. Boss healing uses
actual accepted Player HP loss, capped80 per cast and200 per encounter. Misses
and invulnerability consume no healing budget. Two bounded16-pixel erosion steps
produce actual perimeter barriers. Terminal source death retires all auxiliary
collision, visuals and harmful pools.

All auxiliary state is event-replayed, definition-bound and deterministic.
Cold restore rejects invented HP or effect identities and recreates physical
constructs in a fresh World2D. Explicit Forest Boss schemas1/2/3 migrate to
schema4. Historical active seeds preserve their frozen origin and original
warning clock without inventing retroactive sac ownership or damage.

## Evidence

- Initial RED logs: `build/forest-aux-native-red`, `build/forest-aux-native-diagnostic` and `build/forest-aux-native-diagnostic2` retain parse, rollback, admission and contract failures that drove the fixes.
- Headless GREEN: `build/forest-aux-green`,2/2, includes domain and production native Actor/Player/Bridge execution.
- Root input follow-up GREEN: `build/forest-aux-root-input-green`,2/2, preserves all prior probes and adds five actual weapon inputs against roots.
- Existing root regression GREEN: `build/forest-root-green`,4/4.
- Native Metal GREEN: `build/forest-aux-native-green/visual.log`, all assertions and raster pixel checks pass.
- Actual sword, bow, gun, staff and gauntlet input damages native roots, sacs and cage walls through real physics producers, including the legacy Sword adapter's authenticated run binding.

The original CC0 raster atlases are reproducible with
`tools/production_art/generate_forest_auxiliary_atlases.py`; manifest hashes and
provenance are retained with the assets. Ten640x360 and1280x720 native screenshots
under `build/visual-evidence/p15b-native-arena/forest-aux-*.png` cover flowers,
cancelled seed, burst pool, cage warning and erosion. Atlas and cage framing were
visually inspected. Successful logs contain no script errors, warnings or leaks.
Installed Godot does not provide line coverage for these focused suites.

## Integration Gate

The focused helper/assets/tests commit depends on the parent's simultaneous
Forest/Void/Forge retention of shared Boss and effect-authority integration.
Replay auxiliary projection and the combined clean-checkout certification remain
in that parent gate. This evidence does not mark the full game complete. Native
summon materialization is the next required P15 behavior.
