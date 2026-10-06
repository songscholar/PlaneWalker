# Content Icons And Player Effect Integration

- Status: Focused checks passed; final product certification remains active
- Document Role: Current content artwork and player feedback evidence
- Authority Level: Local execution evidence below the approved completion scope
- Applies To: Content icons, room glyphs, event vignettes, command art and Player effect projection
- Owner: Project integration lead
- Depends On: [Pixel production integration](2026-10-06-pixel-production-integration-evidence.md), [Native UI finish design](../superpowers/specs/2026-10-06-native-ui-finish-design.md)
- Last Verified: 2026-10-06

## Retained Changes

All 50 items, 28 blessings, 24 curses and 15 talents have a distinct static
first frame as well as a distinct authenticated four-frame atlas. Twelve
semantic artifact families use content identity and kind, authored housings,
material shading and trim. The former hash-selected generic icon families
are replaced. Five weapon icons and five mode icons have refreshed detail.

Nine room glyphs include an independent question-mark image for unknown
rooms. Eighteen 96x64 event vignettes depict the exact authored subjects,
including the traveler under fallen stone, the smith's hammer, memory mirror,
soul contract, rift garden and old reunion. Eight neutral command symbols
are available to UI consumers. Every frame uses binary alpha, nearest
filtering and the shared production palette. Deterministic source geometry,
CC0 dedication, inventory dimensions and PNG SHA-256 values are retained.

The six Player effect strips now render through PixelProxyActor: sword and
gauntlets use weapon_arc; bow uses arrow_trail; gun uses muzzle_flash; staff
uses spell_burst; time stop/rewind/accelerate use time_ring; cast and time
rift use rift_bloom. All four time abilities retain their presentation IDs.
Existing accepted cues and copied weapon phase/token select the effect.
No damage, action, health, time, replay or save state is written by the
projection. Textures authenticate once per effect identity and stay cached;
the canvas transform preserves a two-screen-pixel integer footprint.
Reduced motion fixes frame 1 and disabled flashing suppresses the muzzle.
Completion and unknown weapons hide the effect instead of borrowing art.

## Executed Evidence

| Evidence | Result |
| --- | --- |
| `build/content-icons-red.log`, `build/room-glyphs-red.log`, `build/event-art-red.log` | Missing/distinct-art acceptance checks retained RED |
| `build/event-art-green.log` | Five Python tests passed, including unique first frames and byte reproduction |
| `build/content-vfx-python-green.log` | 35 presentation contracts: 32 passed, 3 external Blender opt-in cases skipped |
| `build/player-effect-atlas-red` | Missing runtime effect consumption retained RED |
| `build/player-effect-isolated-pose-green` | Stub phase/a11y lifecycle and actual Launch Player/EventBus checks passed |
| `build/player-effect-feedback-regression` | Existing combat feedback runtime scene passed |
| `build/content-vfx-presentation-regressions` | All eight native presentation scenes passed strict logs |
| `build/player-effect-resource-cue-red`, `build/player-effect-resource-cue-green` | Reload, element cycling, guard and focus-step refuse attack art; focused RED/GREEN retained |
| `build/player-effect-four-skills-red`, `build/player-effect-four-skills-green` | All four time abilities consume their raster projection; missing accelerate/rift feedback retained RED and corrected |
| `build/event-controls-catalog-green` | All declared resources load with exact source and imported dimensions |
| `build/player-effects-single-proxy-render.{stdout,engine}.log` | All opaque source pixels match actual rendered four-frame and a11y captures |
| `build/event-art-render.{stdout,engine}.log` | All 18 event vignettes match actual rendered source pixels in all four phases |
| `build/event-controls-import.{stdout,engine}.log` | Editor import passed strict log validation |
| `build/enemy-refresh-source-render.{stdout,engine}.log` | Sixteen enemy captures revalidated against PNG source rather than cached imports |

Actual Player tests retain equality of the complete native replay snapshot
before and after presentation and accessibility changes. Directional checks
cover right/down/left/up pixel axes. Both stdout and engine logs are scanned;
process success alone is not accepted as evidence.

## Render Diagnosis And Boundary

The first effect capture installed an unnamed manual proxy while the
production coordinator also installed its named proxy. Two effect sprites
overlapped and failed source-pixel comparison. The capture now uses the
production proxy name; the corrected result is retained above. Earlier
failed captures are diagnosis and are not acceptance evidence.

Native raster previews are under `build/visual-evidence/player-effects/`
and `build/visual-evidence/event-art/`. They validate the exercised projection
and actual raster import, not the complete UI or final gameplay build.
Projectile scene polygons, full 49-state UI acceptance, final stable-source
gameplay/coverage/matrix tests, sustained performance and distributable
build certification remain separate work. External Tripo/Mixamo source
models have not been obtained; no generated model acquisition is claimed.
Real-world player feedback remains 0/20 and Shenzhen playtesting has not
started.
