# Native UI Onboarding And Results Evidence

- Status: Implemented / Full matrix and native captures passed
- Document Role: Current
- Authority Level: Evidence below AGENTS.md and the native UI finish specification
- Applies To: Accessibility settings, input remapping, tutorial, hints, training, narrative and run results
- Owner: Native UI implementation worker
- Last Verified: 2026-10-06
- Depends On: [Native UI finish design](../superpowers/specs/2026-10-06-native-ui-finish-design.md), [Native UI core finish evidence](2026-10-06-native-ui-core-finish-evidence.md)

## Implemented Behavior

Settings keep the existing setting keys and controls while adding a bounded
five-category TabBar, authored pixel theme, translated labels, and controller
focus links. Input remapping retains its capture epoch and saved bindings while
showing authenticated keyboard/mouse and controller glyphs, icon-only resets,
wrapped binding labels, and a bounded capture prompt.

Tutorial recall now presents an authenticated training mark, a canonical
requirement progress meter, readable lesson detail, icon commands and saved
training meters. Hints use the production pixel Theme and neutral training art;
the close command remains unfocused so a contextual hint never steals gameplay
focus. Training selectors retain their exact request and now show character,
weapon and paired time-ability artwork through the production catalog.

Narrative and results preserve their existing projected state and command
contracts. Language refresh keeps pending capture, scroll, retry and focus
identity. Terminal rewards remain read-only. Unknown data-only Mod content uses
an authenticated neutral package glyph carrying the requested id/category
metadata rather than an empty or misleading known item icon.

## Verification

The focused matrix in `build/ui-secondary-matrix-final-green` passed onboarding,
settings, narrative, results, accessibility persistence, remapping, tutorial,
training, narrative checkpoint and progression flows. It covered `zh_CN` and
`en`, text scales `1.0` and `1.5`, and `640x360`, `1280x720`, `1920x1080` and
`3440x1440` where the view fixture supports each resolution.

The native 640x360 capture cohort in
`build/ui-finish-native-cohort-20261006` passed strict paired stdout/Godot
runtime-log validation for Hub, HUD, dungeon, choice, build inspector, pause,
narrative, results, settings and onboarding. Captures were inspected at 1.5x
English and Simplified Chinese for the compact panels; no blank or overlapping
primary content was found.

The added 240 PNGs retain true 640x360, 1280x720, 1920x1080 and 3440x1440
images for narrative, settings and onboarding. The twelve requested 3440x1440
run-results captures are physically 2560x1440 because the macOS display
environment clamps the native window width; they are retained as an explicit
environment boundary, not counted as true 3440x1440 output.

Meaningful RED evidence is retained in `build/ui-onboarding-assertion-red` for
the missing lesson meter/theme/art behavior and
`build/ui-settings-navigation-assertion-red` for missing category/device art.
The earlier pre-import onboarding run is excluded because an unrelated global
script cache import error (`PlayerZoneAtlasProjection`) occurred before the UI
assertions.

Mod fallback coverage is retained in `build/ui-content-fallback-meaningful-green`.
