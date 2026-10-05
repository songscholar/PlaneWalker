# Native Rendered UI Coverage Plan

- Status: Active
- Document Role: Current focused native UI verification plan
- Authority Level: Local completion QA
- Applies To: Four supported resolutions, bilingual text scales and mapped input events
- Owner: Project owner
- Last Verified: 2026-10-05
- Implementation Status: In progress
- Depends On: [Full product completion design](../specs/2026-09-28-plane-walker-full-product-completion-design.md); [prior UI repairs](../../current/2026-10-05-native-ui-certification-repairs-evidence.md)
- Exit Gate: Clean exact-source OpenGL scenes, expected screenshots and input-flow assertions

**Goal:** Extend the three native challenge visual fixtures through 1920x1080 and 3440x1440, and rerun native Hub and relevant actual-input QA against retained source.

**Architecture:** Reuse existing native SubViewport screenshot fixtures and actual Main/controller integration scenes. Expand only the three resolution matrices, then run the fixtures with a real OpenGL renderer from a clean committed checkout and isolated application storage. Fixture deaths authenticate visible result views; they remain explicitly assisted visual evidence rather than combat victories.

**Tech Stack:** Godot 4.6.1 official editor, OpenGL compatibility renderer, existing native screenshot tests and strict log scanner.

## Completion Criteria

For each of two locales (`en`, `zh_CN`), two text scales (1.0, 1.5) and four
resolutions (640x360, 1280x720, 1920x1080, 3440x1440), retain all native states:

| Fixture | States | Exact PNG count |
|---|---|---:|
| Main Hub | Three districts and nine functions | 192 |
| Boss Rush | Menu, combat, pause, victory | 64 |
| Daily Boss | Menu, combat, pause, victory | 64 |
| Authored challenges | Menu, combat, pause, stage clear, victory | 80 |

Every existing geometry/text assertion and nonblank raster assertion must pass.
Inspect representative minimum-size and ultrawide images. Actual InputEventKey,
InputEventMouseButton and InputEventJoypadButton integration coverage must pass
for owned loadouts, native Hub toolbar, Build sharing, replay, cosmetics and
mode return. These are injected device-shaped events; no physical gamepad device
is attached or claimed.

- [ ] Run the preimplementation support-resolution assertion and retain the missing 1920/3440 failure.
- [ ] Expand only `RESOLUTIONS` in the Boss Rush, Daily Boss and authored challenge visual tests.
- [ ] Retain focused test/plan commit, then create clean exact-source checkout without overlays.
- [ ] Run actual OpenGL native screenshots and exact PNG/pixel verification; scan stdout and engine logs strictly.
- [ ] Rerun actual mapped keyboard/mouse/controller event flows with isolated data.
- [ ] Retain source, commands, logs, screenshot hashes, inspection findings and limitations in evidence.
