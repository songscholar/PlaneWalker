# Native UI Finish Implementation Plan

- Status: Prepared / Gameplay-first sequencing gate
- Document Role: Current product UI completion execution plan
- Authority Level: Below AGENTS.md and the linked specification
- Applies To: All player-facing native Godot UI and its raster resources
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Implementation Status: Not started; preparation only
- Depends On: [Native UI finish design](../specs/2026-10-06-native-ui-finish-design.md)
- Exit Gate: All tasks and retained acceptance criteria pass from the final committed source

> **For agentic workers:** Execute task-by-task with the available collaboration tools and review each finished task before integration. The usual superpowers execution sub-skills are not installed in this session; the repository's existing tests, focused commits and milestone retention rules provide the execution workflow.

**Goal:** Complete all existing native player UI with a coherent modern pixel ruins design, authenticated bitmap/font resources, accessible interactions and retained visual/input/export evidence.

**Architecture:** Preserve existing domain ViewStates, validators, command signals, revisions and focus scopes. Introduce one shared Theme, an authenticated UI art catalog and small presentation components; replace generic layouts with page-specific composition in independently verified tasks. Use existing ContentRegistry snapshots for names/effects and immutable presentation mappings for art.

**Tech Stack:** Godot 4.6.1 compatibility renderer, native Control/Theme/AtlasTexture/StyleBoxTexture/Tween, FocusCoordinator, AccessibilityRuntime, existing Pillow 12.3.0 tooling, Python unittest and the native scene-test runner.

## Global Constraints

- Do not start runtime, resource-generator, asset or test implementation until the integration lead records the gameplay milestone passing and announces the UI phase.
- Canonical logical canvas: `640x360`.
- Supported output sizes: `640x360`, `1280x720`, `1920x1080`, `3440x1440`.
- Locales: `zh_CN`, `en`; required text scales: `1.0`, `1.5`.
- Keep existing two equipped time slots and one authoritative active-item state.
- Keep existing `render(view_state)`, signals, payloads, action ids, revisions, epoch/submission checks, `close_available` and focus restoration.
- Shared display facts come from immutable content snapshots and existing ViewStates; no presentation mutation of RunState/Profile/save data.
- Use nearest-sampled authored PNG artwork; final icons must differ by silhouette/detail rather than only hue or border.
- Vendored fonts require complete upstream OFL-1.1 text, declared source/version and SHA-256; no runtime font/network download.
- Normal text contrast is at least 4.5:1; essential icons and large text at least 3:1; all critical color states include shape/text.
- Every task starts with a meaningful failing resource, visual, contract or interaction test, retains its RED evidence, then runs the scoped regressions.
- No remote push, public publication, paid purchase or unprovided credential is part of this plan.
- Stage only the explicit reviewed paths for the task; preserve other agents' work.
- Use strict runtime-log scanning; an exit code alone never certifies Godot success.

## Execution Map

| Task | Independently reviewable deliverable | Depends on |
|---|---|---|
| 1 | Authenticated bitmap UI art and font bundle | Gameplay passing record |
| 2 | Shared Theme, controls and motion/accessibility components | 1 |
| 3 | Graphical Combat HUD and read-only build inspection | 2 |
| 4 | Purpose-built Hub/loadout/meta/forge/build/collection views | 2 |
| 5 | Choices, graph map/routes, shop and room interactions | 2 |
| 6 | Events, narrative, results, floor transitions and credits | 2, 5 |
| 7 | Pause/settings/remapping/tutorial/training | 2, 3 |
| 8 | Challenge and reward surfaces | 3, 5, 6 |
| 9 | Replay, local records/platform and Mod views | 2, 4 |
| 10 | Full visual/input/integration/export certification | 1-9 |

Tasks 3, 4 and 5 can run in parallel after Task 2 with distinct owned files.
The integration lead owns `scripts/main.gd`, `scenes/main.tscn`,
`project.godot`, common contracts and final resource catalogs. Workers send
assembly changes to the lead instead of independently editing those files.
No gameplay-authority refactor is hidden inside UI work.

## Shared Interfaces

New interfaces are defined here so later tasks have one consistent contract:

```gdscript
# UiArtCatalog, RefCounted, scripts/ui/style/ui_art_catalog.gd
func configure(manifest_path: String = "res://assets/production/ui/manifest.json") -> Dictionary
func texture(icon_id: StringName) -> Texture2D
func content_icon(content_id: StringName) -> Texture2D
func has_icon(icon_id: StringName) -> bool
func missing_ids() -> Array[StringName]

# UiTheme, RefCounted, scripts/ui/style/ui_theme.gd
static func apply(root: Control) -> void
static func icon_command(button: Button, icon_id: StringName, tooltip_key: String) -> void

# UiResourceSlot, Control, scripts/ui/components/ui_resource_slot.gd
func render_slot(icon_id: StringName, current: float, maximum: float, ready: bool, status_text: String = "") -> void
func apply_accessibility_settings(settings: Dictionary) -> void

# UiMotion, RefCounted, scripts/ui/components/ui_motion.gd
func configure(owner: CanvasItem, settings: Dictionary) -> void
func reveal() -> void
func accept() -> void
func cancel() -> void

# UiBuildInspector, Control, scripts/ui/components/ui_build_inspector.gd
func configure(registry: RefCounted) -> Dictionary
func render_build(build: Dictionary) -> Dictionary
func focus_controls() -> Array[Control]

# UiFinishFixtures, RefCounted, tests/visual/ui_finish_fixtures.gd
static func state_ids() -> Array[String]
func configure(main: Node) -> void
func show_state(state_id: String) -> Dictionary
func inspected_root() -> Control
func capture_regions() -> Array[Rect2i]
```

`configure`/`render_build` return the local standard
`{"ok": bool, "code": StringName, "context": Dictionary}` shape. Invalid
asset manifests fail closed before a partially configured catalog is installed.
An unknown optional Mod icon returns the declared missing-art texture and
records its id; an unknown required first-party icon fails the resource gate.
`render_slot` only updates presentation, clamps the display fraction and keeps
the slot frame fixed. `UiBuildInspector.configure` receives a read-only
registry reference; it never calls mutation APIs. UiMotion owns and kills all
its tweens and cannot delay commands. Fixtures use production views/services
with deterministic Profile data and label assisted states in the manifest.

All new visual scenes are native `.tscn` scenes, and all new generator/fixture
output directories stay under the workspace. Art catalog fields and class
names here must remain identical across tasks.

## Task 1: Authenticated Art and Fonts

**Files:**

- Create: `tools/production_art/generate_ui_assets.py`, `tools/production_art/ui_icon_recipes.json`.
- Create: `tools/ui/check_font_coverage.gd`.
- Create: `assets/production/ui/catalog.json`, `assets/production/ui/manifest.json`, `assets/production/ui/LICENSE.txt`, `assets/production/ui/contact_sheet.png`.
- Create: `assets/production/ui/frames.png`, `controls.png`, `room_icons.png`, `time_icons.png`, `weapon_icons.png`, `content_icons.png`, `character_portraits.png`, `boss_portraits.png` in that same directory.
- Create: `assets/production/fonts/manifest.json`, `NotoSansSC.ttf`, `PixelifySans.ttf`, `NOTO-OFL.txt`, `PIXELIFY-OFL.txt` in `assets/production/fonts/`.
- Create: `tests/contract/presentation/test_ui_art.py`, `tests/contract/presentation/test_ui_fonts.py`.
- Existing dependencies: `requirements-production-art.txt` remains sufficient; no new raster/font dependency is planned.

**Interfaces:** Consumes canonical content JSON, current authenticated actor
atlases and project art direction. Produces checked-in catalog mappings and
hash manifests consumed by UiArtCatalog/Theme. `generate_ui_assets.py --check`
checks committed outputs without modifying them; default mode regenerates
deterministically. Required semantic ids are derived from canonical content
`icon_id`/identity fields. Never assign new gameplay icon ids.

- [ ] Step 1: Add resource acceptance tests before asset implementation. Test all required ids, unique nonblank silhouette/detail, atlas bounds, safe relative paths, nearest policy and hash/license provenance. Font test derives code points from every shipping localization CSV and invokes the new Godot probe, which loads both FontFiles and checks `has_char(codepoint)` for each localized code point. Decode CSV with Python's standard `csv` parser and pass the exact code-point array through a workspace JSON fixture; no new font parser is needed.

```python
def test_every_launch_icon_has_raster_art(self):
    catalog = self.load_catalog()
    required = self.required_content_icon_ids()
    self.assertTrue(required.issubset(catalog["entries"]))
    for icon_id in required:
        self.assertGreater(self.visible_pixels(catalog, icon_id), 12)
    self.assertEqual(len(required), len(self.normalized_shapes(catalog, required)))
```

Test helpers use `json`, `hashlib`, `pathlib` and existing Pillow, calculate
normalized object pixels after stripping the shared frame, and do not equate
an icon border with its silhouette. Record a review contact sheet even if the
automated shape comparison passes.

- [ ] Step 2: Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.presentation.test_ui_art tests.contract.presentation.test_ui_fonts`. Expected RED: required catalog/font resources absent. Retain failing log.
- [ ] Step 3: Author recipe masks, original frames, recognizable glyphs/portraits and contact sheets; derive semantic artwork mappings from current content. Use existing Pillow 12.3.0, or the local raster encoder for small art. Large portraits may use imagegen after reading its skill; retain original outputs/prompts and terms. Obtain fonts from official `google/fonts` `ofl/notosanssc` and `ofl/pixelifysans` sources, verify OFL text/name/version, record actual downloaded digests and vendor locally. No guessed digest or private system-font copy is accepted.
- [ ] Step 4: Regenerate twice into isolated workspace temporary directories and compare bytes/hashes; run `python3 tools/production_art/generate_ui_assets.py --check` and the two resource suites. Expected GREEN: every required icon covered, valid atlas/license/hash data, all localized glyphs present. Visually inspect the contact sheet for object recognition and repeated-shape defects.
- [ ] Step 5: Review the precise art/tool/test diff and commit it as `art: add authenticated native UI pixel resources and fonts`. The commit must contain binaries, source recipes, generator, manifest and license texts together.

## Task 2: Shared Theme and Components

**Files:**

- Create: `assets/production/ui/plane_walker_theme.tres`.
- Create: `scripts/ui/style/ui_art_catalog.gd`, `scripts/ui/style/ui_theme.gd`.
- Create: `scripts/ui/components/ui_resource_slot.gd`, `ui_icon_command.gd`, `ui_currency_strip.gd`, `ui_tooltip.gd`, `ui_motion.gd` in `scripts/ui/components/`.
- Create: matching `scenes/ui/components/resource_slot.tscn`, `icon_command.tscn`, `currency_strip.tscn`, `tooltip.tscn`.
- Create: `tests/ui/ui_style_contract_test.gd`, its `.tscn`, `tests/ui/ui_components_test.gd`, its `.tscn`.
- Modify: `scripts/ui/dungeon_panel_view.gd` and the integration lead's narrowly scoped assembly paths.
- Modify: `assets/production/ui/manifest.json` to authenticate the shared Theme resource after it is added.

**Interfaces:** Implements the shared interfaces above. Theme is the source
for fonts, semantic style variants, all button states, sliders, checkboxes,
tabs, popup menus, progress meters and file/confirmation dialogs. Component
focus controls remain native Godot Controls.

- [ ] Step 1: Add failing style/component tests. Assert texture-backed frames/fonts, all normal/hover/focus/pressed/disabled states, catalog failures, no node-size change on hover, bounded tooltip and cancellation after owner destruction.

```gdscript
var slot = load("res://scenes/ui/components/resource_slot.tscn").instantiate()
add_child(slot)
slot.render_slot(&"time_stop", 2.0, 4.0, false, "2.0s")
var before: Vector2 = slot.size
slot.apply_accessibility_settings({"reduced_motion": true})
slot.render_slot(&"time_stop", 4.0, 4.0, true, "")
suite.assert_equal(slot.size, before, "ready state keeps stable slot dimensions")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter ui_style_contract` and `./tools/run_tests.sh --filter ui_components`. Expected RED: components/catalog/Theme absent; retain logs.
- [ ] Step 3: Implement resource authentication and the native shared Theme; add texture-backed hard-edge frames, declared font fallback and 28px controls. Implement bitmap icon commands with localized tooltips, bounded focus tooltips and UiMotion lifecycle/reduced-motion behavior. Apply Theme before AccessibilityRuntime computes base font metrics. Replace only generic shared chrome, preserving `panel_root`, labels, scroll, footer, back_button and command guards.

```gdscript
static func apply(root: Control) -> void:
    root.theme = preload("res://assets/production/ui/plane_walker_theme.tres")
    root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

- [ ] Step 4: Run both new scenes, existing `./tools/run_tests.sh --filter tests/ui/` and `./tools/run_tests.sh --filter controller_focus`. Expected GREEN: style/resource/geometry/focus contracts; visually inspect Theme applied to a compact panel and large-text popup. Scan strict logs.
- [ ] Step 5: Commit only reviewed shared Theme/component and compatibility paths as `ui: establish shared pixel theme and accessible controls`.

## Task 3: Combat HUD and Build Inspection

**Files:**

- Modify: `scripts/ui/views/combat_hud_view.gd`, `scenes/ui/combat_hud_v2.tscn`.
- Create: `scripts/ui/components/ui_build_inspector.gd`, `scenes/ui/components/build_inspector.tscn`.
- Create: `scripts/ui/components/ui_map_inset.gd`, `scenes/ui/components/map_inset.tscn`.
- Modify: `tests/ui/combat_hud_v2_scene_test.gd` and existing fixtures only by adding valid presentation scenarios.
- Create: `tests/ui/combat_hud_finish_test.gd`, its `.tscn`, `tests/ui/build_inspector_test.gd`, its `.tscn`.
- Integration request to lead: read-only registry configuration and pause build-inspection tab.

**Interfaces:** Consumes validated RunViewState; existing top-level
weapon/character/active-item unions and build/dungeon projections. Produces
graphical UI with the same `render` result and retained named data labels
needed by existing consumers. BuildInspector consumes current build ids and
scores; MapInset consumes DungeonMapViewState only.

- [ ] Step 1: Add failing tests for two time icons plus current weapon/character/active-item art, numerical resource parity, central safe gameplay region, delayed damage presentation, live reduced-motion toggle and hidden-room secrecy.

```gdscript
var state: Dictionary = Fixtures.load_fixture("res://tests/fixtures/ui/hud_boss.json")
var before := state.duplicate(true)
suite.assert_true(hud.render(state).ok, "current RunViewState renders")
suite.assert_equal(hud.latest_state(), before, "HUD retains the exact accepted snapshot")
suite.assert_true(hud.find_child("TimeSlot1", true, false) != null, "first graphical time slot exists")
suite.assert_true(hud.find_child("TimeSlot2", true, false) != null, "second graphical time slot exists")
suite.assert_equal(state, before, "presentation does not mutate input")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter combat_hud_finish` and `./tools/run_tests.sh --filter build_inspector`. Expected RED: graphical slot/inspector features missing.
- [ ] Step 3: Replace broad text panels with constrained vitals and bitmap slots. Show exact resource values; animate only visual HP trail using accepted state differences. Bind cooldown labels/overlays to existing values. Resolve build icon/name/description from read-only registry; display current stacks and eight projected archetype scores. Add a small graph inset only from validated dungeon_state and keep hidden nodes unknown. No new combat variables or input actions are added.
- [ ] Step 4: Run new scenes, `./tools/run_tests.sh --filter combat_hud_v2`, `./tools/run_tests.sh --filter run_view_state`, `./tools/run_tests.sh --filter player_loadout`, and existing time-ability/UI replay contracts. Inspect 640x360 large-text, 1920x1080 and ultrawide HUD captures in combat/boss/low-HP/cooldown states; ensure actions remain visible without covering the center.
- [ ] Step 5: Commit reviewed HUD/inspector/inset paths as `ui: finish graphical combat HUD and build inspection`.

## Task 4: Hub and Character Preparation

**Files:**

- Modify: `scripts/ui/hub_panel_view.gd`, `scripts/hub/hub_flow_coordinator.gd`, `scripts/hub/hub_district_scene.gd`, `scripts/ui/hub_cosmetics_panel.gd`.
- Modify: `scripts/ui/launch_loadout_panel.gd`, `scenes/ui/launch_loadout_panel.tscn`, `scripts/ui/candidate_loadout_panel.gd`, `scenes/ui/candidate_loadout_panel.tscn`.
- Create: `scripts/ui/hub_pages/gateway_layout.gd`, `council_layout.gd`, `forge_layout.gd`, `builds_layout.gd`, `collection_layout.gd` in that directory; matching scenes under `scenes/ui/hub_pages/`.
- Modify: `tests/ui/main_hub_visual_test.gd`, `tests/ui/build_sharing_visual_test.gd`, `tests/ui/local_records_visual_test.gd`.
- Create: `tests/ui/hub_finish_layout_test.gd` and its `.tscn`.

**Interfaces:** HubPanelView remains the command/focus owner. Page builders
consume `_state` copies and return native focus Controls carrying current
`action_id`/`available` metadata; callbacks invoke existing owner functions.
No page persists its own loadout or recalculates meta prices.

- [ ] Step 1: Add failing tests for all nine functions with distinct composition, five character/weapon choices, exactly two equipped time slots, branch ownership, selected-weapon upgrades, share-draft preservation and cosmetic art. Retain every existing command payload test.

```gdscript
var hub: Node = main.get_node("HubFlowCoordinator")
suite.assert_true(hub.open_function("gateway").ok, "gateway opens")
var panel: Control = hub.panel_view()
suite.assert_true(panel.find_child("CharacterRoster", true, false) != null, "portrait roster is present")
suite.assert_true(panel.find_child("WeaponRoster", true, false) != null, "weapon glyph roster is present")
suite.assert_equal(panel.view_state(), hub.view_state(), "page consumes authoritative Hub state")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter hub_finish_layout`; expected RED: purpose-built roster/layout absent. Retain baseline screenshots from the existing Main Hub fixture.
- [ ] Step 3: Build bounded gateway selector/preview, meta branch tracks, selected-weapon forge, saved-build/detail view and collection/category views. Use current actor/cosmetic atlases and new art. Theme Hub chrome/travel/NPC glyphs while preserving full background scale. Adapt compatibility loadout panels to the same visual components and existing legal time-pair policy. Preserve user draft strings, availability reasons and `revision`/`epoch` on callbacks.
- [ ] Step 4: Run new layout test, `./tools/run_tests.sh --filter main_hub`, `./tools/run_tests.sh --filter main_build_sharing`, `./tools/run_tests.sh --filter main_cosmetics`, and current launch/candidate loadout tests. Capture all 12 Hub states, check large-text reflow, scroll-to-focus, visible launch/resume footer and travel/settings focus restoration.
- [ ] Step 5: Commit reviewed Hub page/chrome/loadout paths as `ui: finish native Hub and loadout presentation`.

## Task 5: Choices, Map and Economy

**Files:**

- Modify: `scripts/ui/views/choice_panel_view.gd`, `scenes/ui/choice_panel_v2.tscn`, `scripts/ui/dungeon_map_panel.gd`, `scripts/ui/route_choice_panel.gd`, `scripts/ui/merchant_panel.gd`, `scripts/ui/room_interaction_panel.gd` and their existing scenes.
- Create: `scripts/ui/components/ui_reward_card.gd`, `scenes/ui/components/reward_card.tscn`, `scripts/ui/components/ui_route_graph.gd`, `scenes/ui/components/route_graph.tscn`.
- Modify: `tests/ui/choice_panel_v2_scene_test.gd`, `tests/ui/p14_panel_visual_contract_test.gd`.
- Create: `tests/ui/choice_map_shop_finish_test.gd` and its `.tscn`.

**Interfaces:** RewardCard presents current option data and emits existing
option identity. RouteGraph presents projected nodes/edges and emits a
focused node id for detail; route activation remains RouteChoicePanel's
existing edge id/revision signal. Economy commands/prices remain authored.

- [ ] Step 1: Add failing tests for item art, rarity shape, exact prices, sold/disabled states, map room-type glyphs, hidden knowledge and mandatory/replacement choice. Assertions inspect actual visible text/texture and captured command payloads.

```gdscript
var map_before: Dictionary = map_state.duplicate(true)
suite.assert_true(map_panel.render(map_state).ok, "map contract renders")
suite.assert_equal(map_state, map_before, "map view preserves hidden knowledge")
suite.assert_true(map_panel.find_child("RouteGraph", true, false) != null, "graph remains present")
for node: Dictionary in map_state.nodes:
    if not node.revealed:
        suite.assert_equal(node.room_type, "unknown", "UI receives no concealed room type")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter choice_map_shop_finish`; expected RED: required bitmap cards/node types missing. Preserve existing choice/map/shop screenshots.
- [ ] Step 3: Add texture-backed reward frames, art/effect hierarchy, icon replacement and constrained footer; render a glyph graph/details panel with selected routes and clear unknown state. Build shop shelves, service rows and room-context art with exact cost and eligibility labels. Keep mandatory-choice dismissal rules and per-run accepted-command handling.
- [ ] Step 4: Run new finish test, current choice scene, `./tools/run_tests.sh --filter tests/ui/`, and `./tools/run_tests.sh --filter p14_controller_flow`. Capture item/blessing/curse, route/map, shop/rest states at required text scales; test real key/mouse/joypad route/selection/purchase/back events and presentation-only focus navigation.
- [ ] Step 5: Commit reviewed choice/map/economy paths as `ui: finish reward map and merchant presentation`.

## Task 6: Events, Narrative and Results

**Files:**

- Modify: `scripts/ui/dungeon_event_panel.gd`, `scripts/ui/narrative_panel_view.gd`, `scripts/ui/run_end_overlay.gd`, `scripts/ui/floor_transition_panel.gd` and their existing scenes/assembly nodes.
- Create: `scenes/ui/run_end_overlay.tscn`, `scenes/ui/narrative_panel.tscn`, `scripts/ui/components/ui_result_summary.gd`.
- Modify: `tests/ui/dungeon_event_panel_test.gd`, `tests/ui/floor_transition_panel_test.gd`.
- Create: `tests/ui/narrative_result_finish_test.gd` and its `.tscn`.
- Integration request to lead: replace corresponding inline Main nodes with native scenes while retaining paths and signals.

**Interfaces:** Existing event/narrative ViewState and run-ended facts; no
new result calculation. ResultSummary consumes terminal result copies and
art identities; RunEndOverlay still owns one terminal presentation per run,
settlement retry and Profile return. Credits consume actual bundled license
manifest entries rather than an invented contributor list.

- [ ] Step 1: Add failing tests for event art and distinct pending/reward/result state, portrait/dialogue composition, `close_available`, readable results/earned glyphs, save-retry command and credits source truth.

```gdscript
var before := narrative_state.duplicate(true)
suite.assert_true(narrative_panel.render(narrative_state).ok, "authored narrative renders")
suite.assert_equal(narrative_panel.back_button.visible, bool(before.close_available), "close policy remains authoritative")
suite.assert_equal(narrative_state, before, "dialogue reveal cannot change narrative state")
suite.assert_true(narrative_panel.find_child("DialogueText", true, false) != null, "dialogue text region is present")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter narrative_result_finish`; expected RED: purpose-built dialogue/result components absent.
- [ ] Step 3: Compose event vignette/text/preview choices, readable portrait dialogue and ending/archive/credits views. Use skippable reveal in normal motion and instant text with reduced motion. Compose outcome, kit art, terminal metrics and existing earned-build summaries as separate regions; expose actual settlement retry without losing terminal identity. Add next-floor art without auto-accepting transition.
- [ ] Step 4: Run new scene, existing event/floor tests, `./tools/run_tests.sh --filter main_narrative`, `./tools/run_tests.sh --filter narrative`, and `./tools/run_tests.sh --filter controller_focus`. Capture each pending/error/closed-policy path. Verify input reveals text before continuing and no duplicate run_ended/return mutation occurs.
- [ ] Step 5: Commit reviewed event/narrative/result paths as `ui: finish narrative and run result presentation`.

## Task 7: Settings, Onboarding and Training

**Files:**

- Modify: `scripts/ui/pause_menu.gd`, `scripts/ui/accessibility_settings_panel.gd`, `scenes/ui/accessibility_settings_panel.tscn`, `scripts/ui/input_remap_panel.gd`, `scenes/ui/input_remap_panel.tscn`.
- Modify: `scripts/ui/tutorial_panel.gd`, `scenes/ui/tutorial_panel.tscn`, `scripts/ui/tutorial_hint_presenter.gd`, `scenes/ui/tutorial_hint_presenter.tscn`, `scripts/training/training_panel_view.gd`.
- Create: `scenes/ui/pause_menu.tscn`, `tests/ui/settings_onboarding_finish_test.gd` and its `.tscn`.
- Modify: existing accessibility/remap/tutorial/training integration tests only where new visual assertions belong.
- Integration request to lead: native PauseMenu scene and read-only build tab feed.

**Interfaces:** Existing setting keys and remap service. Reuse
AccessibilityRuntime live hooks and the existing input label codec. Keep
existing training play/pause/reset/back raster icons and successful-frame
observer facts. New categories are presentation tabs, not new save settings.

- [ ] Step 1: Add failing tests for category layout, themed controls and device glyphs, reduced-motion live behavior, text-scale reflow, visible remap conflicts, tutorial progress, and successful focus return after settings close.

```gdscript
suite.assert_true(GameState.set_setting("reduced_motion", true), "existing setting accepts the value")
var runtime: Node = main.get_node("AccessibilityRuntime")
runtime.apply_to_tree(panel)
suite.assert_true(runtime.settings_snapshot().reduced_motion, "current reduced-motion value is applied")
suite.assert_true(panel.find_child("SettingsTabs", true, false) != null, "grouped settings navigation exists")
suite.assert_true(panel.back_button.is_visible_in_tree(), "large text retains a reachable exit")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter settings_onboarding_finish`; expected RED: grouped native layout/glyph behavior absent.
- [ ] Step 3: Compose pause commands/build tab, setting categories, native sliders/checkboxes/option sets, device glyphs, focused remap capture/conflict and font preview. Finish lesson checklist/progress/hint and training selector layout. Apply Theme before accessibility scaling; localize all new labels in shipping CSV, never expose raw implementation ids in player copy.
- [ ] Step 4: Run new scene, `./tools/run_tests.sh --filter accessibility_settings`, `./tools/run_tests.sh --filter input_remap`, `./tools/run_tests.sh --filter tutorial`, `./tools/run_tests.sh --filter training`, and current controller flows. Retain mapped keyboard/mouse/joypad interactions, capture/conflict cancel, live language change, cold setting recovery and assist disclosure.
- [ ] Step 5: Commit reviewed settings/onboarding/training paths as `ui: finish accessible settings and onboarding surfaces`.

## Task 8: Challenge Modes and Rewards

**Files:**

- Modify: `scripts/modes/boss_rush_panel_view.gd`, `daily_boss_panel_view.gd`, `authored_challenge_panel_view.gd`, `endless_panel_view.gd` in `scripts/modes/`.
- Modify: `scripts/ui/challenge_rewards_panel.gd`.
- Create: `scenes/ui/modes/mode_header.tscn`, `scenes/ui/modes/boss_track.tscn`, `scenes/ui/modes/mode_record_list.tscn` and `scripts/ui/components/ui_boss_track.gd`.
- Modify: `tests/ui/boss_rush_visual_test.gd`, `daily_boss_visual_test.gd`, `authored_challenge_visual_test.gd`, `challenge_equipment_visual_test.gd` in `tests/ui/`.
- Create: `tests/ui/mode_finish_test.gd` and its `.tscn`.

**Interfaces:** Existing mode preview/session/request dictionaries, current
`action_requested`/`set_selected` signals and reward service. Shared reward
card and result presentation from Tasks 5/6; no mode-state normalization in
the UI. Fixed loadouts remain fixed.

- [ ] Step 1: Add failing tests for authored mode objective/kit art, five-Boss/three-stage track, current cycle/attempt/countdown, carried choices, practice/assist status, earned equipment and pending save errors.

```gdscript
suite.assert_true(mode_panel.render(mode_state).ok, "mode snapshot renders")
suite.assert_true(mode_panel.find_child("ModeLoadout", true, false) != null, "fixed loadout is graphical")
suite.assert_equal(mode_panel.view_state(), mode_state, "UI retains the exact session projection")
suite.assert_equal(mode_panel.back_button.disabled, bool(mode_state.pending), "pending save preserves return lock")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter mode_finish`; expected RED: new mode composition absent.
- [ ] Step 3: Add specific mode artwork/objective/track/record composition with stable commands outside details scroll. Present carried choices via RewardCard, terminal mode result via ResultSummary and reward collection with actual ownership/equip states. Preserve retry/reload identity, attempt decrement boundaries and eligibility disclosure.
- [ ] Step 4: Run new scene and current Boss Rush/daily/authored/endless/reward suites. Preserve the current full-resolution visual matrices, inspect large-text current-stage/pending-save/terminal states and drive actual mapped mode return/retry/reward-selection events.
- [ ] Step 5: Commit reviewed mode/reward presentation paths as `ui: finish native challenge mode presentation`.

## Task 9: Replay, Platform and Content Management

**Files:**

- Modify: `scripts/replay/player_replay_library_panel.gd`, `scripts/platform/platform_panel.gd`, `scripts/ui/content_management_panel.gd`.
- Modify: `tests/ui/local_records_visual_test.gd`, `tests/integration/ui/main_replay_library_test.gd`, `tests/platform/platform_panel_test.gd`, `tests/ui/content_management_panel_test.gd`.
- Create: `tests/ui/replay_platform_content_finish_test.gd` and its `.tscn`.
- Create: page scenes under `scenes/ui/replay/`, `scenes/ui/platform/`, `scenes/ui/content/` only where a stable reusable view needs framing.

**Interfaces:** Existing replay library/router/coordinator, platform
provider/coordinator, content-manager discovery/activation and file dialogs.
Presentation keeps actual world SubViewport, Timeline frame index, playback
speeds, import/export/delete policy, local/offline capability labels, content
mutation locks and separate save domains.

- [ ] Step 1: Add failing tests for visible replay art/list with icon toolbar, stable real-world viewport/timeline, offline platform section/status and pack glyph/diagnostics. Preserve unavailable capabilities as clear states rather than simulated account success.

```gdscript
suite.assert_true(replay_panel.open().ok, "library opens through current router")
suite.assert_true(replay_panel.find_child("ReplayPicture", true, false) != null, "actual playback viewport is retained")
suite.assert_true(replay_panel.find_child("ReplayTimeline", true, false) != null, "timeline stays a native slider")
suite.assert_true(replay_panel.find_child("ReplayControls", true, false) != null, "playback toolbar is reachable")
```

Use a real retained deterministic recording fixture before this assertion;
empty-state tests intentionally expect no ReplayPicture.

- [ ] Step 2: Run `./tools/run_tests.sh --filter replay_platform_content_finish`; expected RED: complete new raster/tool layout not present.
- [ ] Step 3: Replace recording dropdown/list chrome with compact rows/detail and unframed native gameplay viewport; use bitmap tool buttons and stable scrubber. Add aligned local-record rows and platform section tabs, capability/status affordances, actual screenshot preview and offline reason. Add pack emblem/status/dependency/diagnostic rows, themed native file/confirmation dialogs and current lock reasons. No optional online capability may block offline navigation.
- [ ] Step 4: Run new scene, existing replay library/platform/content-manager and Main integration tests. Verify seek/playback/import/export/delete cancel, recorded divergence/missing packs, local share/storage refusal, mod quarantine/mutation lock and file-dialog focus return; capture empty, playback, offline and rejected-pack states.
- [ ] Step 5: Commit reviewed replay/platform/content paths as `ui: finish replay and offline product surfaces`.

## Task 10: Native Visual and Release Certification

**Files:**

- Create: `tests/visual/ui_finish_fixtures.gd`, `tests/visual/ui_finish_visual_test.gd`, `tests/visual/ui_finish_visual_test.tscn`, `tests/fixtures/ui/ui_finish_states.json`.
- Create: `tests/integration/ui/ui_finish_input_flow_test.gd` and its `.tscn`.
- Create: `tools/ui/capture_ui_finish.py`, `tools/ui/verify_ui_finish.py`.
- Create: `docs/current/2026-10-06-native-ui-finish-evidence.md`.
- Integration lead updates documentation status and release tooling only after authenticated passing evidence exists.

**Interfaces:** Implements UiFinishFixtures above. Capture tool runs a
sequential native OpenGL fixture using the configured Godot executable,
isolated workspace user-data, renderer-log capture and bounded processes.
Verification tool checks the 49-state registry, all 784 minimum combinations,
PNG/file hashes, expected artwork regions and retained inspection decisions.
No screenshot helper may write production gameplay state or fake victories.

- [ ] Step 1: Before implementing the matrix, add failing acceptance for
the exact state/locale/text-scale/resolution Cartesian product. Add actual
input journeys from Hub through launch/loadout, choices/routes/shop/events,
terminal return, settings/remap, modes, replay/cosmetics and offline packs.

```gdscript
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]
const LOCALES := ["zh_CN", "en"]
const TEXT_SCALES := [1.0, 1.5]
suite.assert_equal(Fixtures.state_ids().size(), 49, "every specified surface has a retained state")
suite.assert_equal(Fixtures.state_ids().size() * RESOLUTIONS.size() * LOCALES.size() * TEXT_SCALES.size(), 784, "complete minimum capture matrix")
```

- [ ] Step 2: Run `./tools/run_tests.sh --filter ui_finish_input_flow` and `python3 tools/ui/verify_ui_finish.py --root build/ui-finish/captures`. Expected RED: missing journeys/capture combinations, retained before changes.
- [ ] Step 3: Implement all 49 fixtures using production Main/coordinators and deterministic isolated Profiles. Implement pixel/text/viewport/tooltip/scroll-visible/focus assertions; capture expected asset regions so monochrome/missing assets cannot pass a general nonblank check. Freeze deterministic visual clocks for comparisons while testing normal and reduced motion behavior independently. Generate screenshot manifest with source commit and per-image hashes. Keep real playback active across two captures and assert pixels change.
- [ ] Step 4: Commit the complete UI candidate, then certify that exact source from a clean workspace checkout. Run these commands from that checkout with `GODOT_BIN` set to the project-local Godot 4.6.1 executable:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/contract/presentation -p 'test_*.py'
./tools/run_tests.sh --filter tests/ui/
./tools/run_tests.sh --filter tests/integration/ui/
python3 tools/ui/capture_ui_finish.py --godot-bin "$GODOT_BIN" --output build/ui-finish/captures
python3 tools/ui/verify_ui_finish.py --root build/ui-finish/captures
./tools/run_tests.sh --timeout 90
python3 tools/export/certify_checkout.py --commit HEAD --godot-bin "$GODOT_BIN" --templates-dir build/toolchain/godot-4.6.1/templates --validation-timeout-seconds 18000 --verify-packaged-startup --artifact-dir build/ui-finish/certified-packages
```

Capture/verification CLI interfaces above are part of this task and must be
implemented exactly. Capture defaults to the 784-state matrix and also creates
reduced-motion/high-contrast captures for HUD, gateway, choices, map, results,
settings and replay. New verifier rejects missing combinations, duplicate
state ids, changed hashes, empty essential regions and unreviewed required
inspection states. Existing `tools/runtime_log_validation.py` scans renderer,
test and startup logs; the scene runner already scans its own strict logs.

Manually inspect all 49 states in `640x360` at text scale `1.5` and in
`3440x1440` at `1.0`, including actual image assets and focus. Verify ordinary
1080p representative scenes for framing and hierarchy. Fix defects in their
own focused task commits, then recapture affected states and recertify only
the changed candidate. A physical controller is additional evidence only
when attached; injected device-shaped events must be labeled honestly.

- [ ] Step 5: Retain commands, RED/GREEN logs, source/art hashes, all screenshot
inspection findings, full-suite/export/startup results, rollback commits and
remaining external limitations. Commit evidence as
`docs: retain complete native UI visual and input certification`. The
integration lead provides one non-blocking milestone retention review and
continues the authorized product program.

## Review and Retention Rules

No task is complete solely because its test scene passed. Inspect its real
native screenshots for art/typography/spacing and drive its actual user
journey. Keep each independently tested change in a focused local commit and
record its rollback id. Do not claim design approval, physical device tests,
full combat victories or operating-system startup without the corresponding
evidence. Final known limitations may concern external publication/accounts,
commercial approval and real-world player feedback, never unfinished UI
resources, missing input actions, unreadable text or unverified local exports.

This plan is prepared on 2026-10-06 and has not executed any implementation
steps. UI code, runtime, assets and README remain owned by the existing
program until the gameplay-first sequencing gate opens.
