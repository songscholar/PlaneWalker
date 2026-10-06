# Mode and Product UI Finish Evidence

- Status: Focused Verified / Final product certification pending
- Document Role: Current graphical mode HUD and secondary product UI evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Boss Rush, daily Boss, authored challenges, Endless, rewards, replay, platform, content management
- Owner: Plane Walker mode and product UI lane
- Depends On: `../superpowers/specs/2026-10-06-native-ui-finish-design.md`; `../superpowers/plans/2026-10-06-native-ui-finish.md`
- Last Verified: 2026-10-06

## Retained Behavior

All four mode coordinators now project their actual Player and native Boss
facts into one graphical mode HUD. Health and energy gauges, actual character
and weapon artwork, both time slots, active-item state, Boss health and phase
pips, and a mapped pause command replace the text-only combat counters.
The projection uses the same resource contracts as the regular run HUD without
constructing a synthetic dungeon RunState. Invalid state, duplicate revisions,
and retired run identities refuse while retaining the accepted presentation.
Public projections and snapshots remain detached from domain state.

Mode menus expose authentic equipment artwork and their authored Boss route.
Start, resume, save/retry, and return commands stay outside detail scrolling.
Existing command IDs, controller focus, domain clocks, durable save policy,
carried choices, and accessibility assists are retained. Endless hides its
original duplicate dungeon HUD and places the replacement at CanvasLayer 10,
below focused dungeon overlays; its pause/menu layer remains at 51.

Challenge rewards bind each canonical reward ID to its own authored atlas,
retaining tint swatches and equipped checkboxes. Replay keeps its actual
SubViewport, native seek slider, speed selector, physical recording state,
import/export/delete policy, and controller flows. Transport controls now have
raster artwork, accessible names, and a fixed position outside detail scroll.
Deferred fitting after minimum-size and accessibility changes prevents a
previous large viewport from leaving the return command below a 640x360 screen.

Platform uses persistent native tabs and its actual offline capability state.
Content management has fixed install/refresh commands, installed-package
artwork and toggles, and distinct quarantine rows. Epoch, revision, ownership,
content mutation locks, fault recovery, and command payloads are retained.
No online provider or ownership result is invented by the presentation.

## Executable Evidence

Godot 4.6.1 stdout and corresponding engine logs are checked with
`tools/runtime_log_validation.py --test-suite-scopes`; exit zero alone is not
accepted. The focused final mode test exercises all four production Main
gateway routes, actual Player and Boss facts, run identity/refusal isolation,
real Endless combat admission, pause clock freezing, and durable return.

| Checks | Retained final logs under build/ |
| --- | --- |
| Shared mode contract and real four-mode integration | `ui-mode-finish/native-layer-final/` |
| Boss Rush locale/text-scale/resolution matrix | `ui-mode-finish/boss-rush/` |
| Daily Boss locale/text-scale/resolution matrix | `ui-mode-finish/daily/` |
| Authored challenge locale/text-scale/resolution matrix | `ui-mode-finish/authored/` |
| Equipment visual matrix | `ui-mode-finish/equipment/` |
| Endless controller save/retry policy | `ui-mode-finish/endless-coordinator/` |
| Endless native combat/checkpoint policy | `ui-mode-finish/endless-native/` |
| Replay/platform/content layout and authentic facts | `ui-product-surfaces/production-layer-final/` |
| Replay retired callbacks and native controller transport | `ui-product-surfaces/replay-neighbor/` |
| Production Main replay routing and locks | `ui-product-surfaces/main-replay/` |
| Platform offline/refusal/controller neighbors | `ui-product-surfaces/platform-neighbor/` |
| Content ownership/epoch/lock neighbors | `ui-product-surfaces/content-neighbor/` |
| Main durable reward flow and canonical earned atlas | `ui-product-surfaces/challenge-rewards-art-final/` |

The surfaces test covers 640x360, 1280x720, 1920x1080, and 3440x1440,
English and Simplified Chinese, and text scales 1.0 and 1.5. It checks shell
bounds, visible commands, and text minimum sizes, while allowing long detail
rows to scroll. It opens the actual Main content-management layer; a standalone
layer-zero fixture would incorrectly capture the underlying Hub.

## Native Screenshots

Two final serial OpenGL Compatibility runs use absolute, isolated
`PLANEWALKER_TEST_DATA_DIR` roots. Their strict paired logs are
`ui-mode-finish/production-combat-rendered-stdout.log` and
`production-combat-rendered-engine.log`, and
`ui-product-surfaces/production-layer-rendered-stdout.log` and
`production-layer-rendered-engine.log`. Both pass without script errors or
engine object leaks.

Twelve mode captures are retained in `build/ui-mode-finish-screenshots/`:
menu, real combat, and pause for each mode. Forty-eight surface captures are
retained in `build/ui-product-surfaces-screenshots/`, covering the full matrix.
By-eye inspection includes all three surfaces at the smallest large-text
viewport, content management at 1280x720, Boss Rush menu, daily combat, and
actual Endless combat. Artwork, gauges, native playback pixels, and persistent
commands are present. These are engine captures, not human playtests.

## Failed Iterations and Limits

Original RED logs in `ui-mode-finish/red/` and
`ui-product-surfaces/red/` retain missing composition assertions. Earlier
Endless first-projection, unsupported refusal-code, replay null-world, and
minimum-viewport overflow runs remain failed. The first mode identity GREEN
had an audio mixer leak and is excluded; final teardown drains the mixer
before exit. An earlier direct run used a relative user-data root and does
not certify storage behavior. Earlier screenshot attempts that captured Hub
over a standalone content panel or Endless route selection are superseded by
the final production-layer and real-combat captures above.

The actual Endless room is still framed into the top-left 320x180 area of its
640x360 capture, leaving a gray world background. This existing native-world
camera/framing problem is reported to the integration lead and remains open;
the full-viewport HUD is not proof that arena presentation is complete.
Other mode arenas still use their existing native scene backgrounds. Sustained
performance, whole-product input/export certification, and real player feedback
are not claimed by this focused UI cohort.

The reversible implementation boundary is the mode/product UI source, its
two focused scenes, and the two adjusted neighboring UI tests. Domain service,
save, replay, and online formats are unchanged.
