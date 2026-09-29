# Plane Walker P6 Controller, Focus, and Accessibility Implementation Plan

- Status: Active / Tasks 1–4 implemented
- Document Role: Current implementation plan
- Authority Level: P6 foundation execution plan
- Applies To: Current start, combat, selection, pause, result, remapping, and accessibility flows
- Owner: Project integration lead
- Exit Gate: Every Current flow completes controller-only, focus recovers after every modal transition, remaps and accessibility settings survive restart, and the complete P6 regression set passes with clean logs
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Integration Order: Tasks 1–5 are input/UI-owned; Tasks 6–9 begin only after the active P2 save and P3 content changes are committed so P6 never writes through another lane's uncommitted files
- Last Verified: 2026-09-29

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Current Plane Walker flow operable without a mouse, guarantee deterministic focus entry and restoration, provide persistent remapping, and complete the Current accessibility settings required by the full-product contract.

**Architecture:** `InputActionContract` is the authoritative action list and default device grammar. `InputRemapService` owns runtime bindings and a separate versioned global input profile, while `FocusCoordinator` owns modal focus frames so individual screens only declare their initial focus. `AccessibilityRuntime` consumes validated settings and applies text, contrast, subtitle, motion, audio-bus, and ranged-charge alternatives without allowing presentation state to mutate gameplay domain state.

**Tech Stack:** Godot 4.6.1, typed GDScript 2.0, Godot `InputMap`, native `Control` focus APIs, JSON v1 input profiles, the existing atomic save/settings services, and serial headless scene tests.

## Global Constraints

- The approved full-product presentation contract requires controller-only completion, remapping, focus recovery, hold/toggle alternatives, camera-shake control, hit-flash control, readable text scale, high-contrast danger language, color-independent cues, subtitle controls, volume buses, and non-shaming difficulty-assist disclosure.
- The logical canvas remains 640×360 with integer scaling. Every new settings view must fit the 16-pixel safe area at 640×360 and remain usable at 1280×720 and 1920×1080.
- Required gameplay actions always retain at least one keyboard/mouse binding and one controller binding. Remapping may swap conflicts but may not leave an action unreachable.
- Controller mappings use Godot's standard SDL layout: A confirm/interact, B dash/cancel, X light attack, Y heavy attack, Start pause, shoulders for Stop/Rewind, left trigger Rift, right trigger ranged charge, and right-stick click Accelerate.
- Gameplay domain state remains independent from `Control`, focus, prompts, and accessibility presentation nodes.
- Input profiles are global and content-pack independent. They use `user://plane_walker/input/input_profile_v1.json`, an adjacent `pending.tmp`, and one verified `backup_1.json`; they do not enter ranked/replay state hashes.
- Existing settings v1 files remain readable. New settings are optional on read and normalized to exact defaults before use; every new write contains the complete Current settings payload.
- Difficulty assist is disclosed in neutral language and recorded in run configuration/telemetry. It never alters content eligibility silently.
- Every test run must scan for `SCRIPT ERROR`, `Parse Error`, failed assertions, `ObjectDB instances leaked`, and `RID allocations leaked`; exit code zero alone is insufficient.
- Do not modify the active dirty `scripts/application/*`, `scripts/rewards/*`, `scripts/curses/*`, or `tests/integration/save/*` files while their owning lanes are uncommitted.
- Stage exact paths only. Never use `git add .`, never push, and never claim human accessibility validation from automated tests.

---

## File Map

### Input and remapping

- `scripts/input/input_action_contract.gd` — authoritative required actions and binding-family inspection.
- `scripts/input/input_binding_codec.gd` — stable JSON representation for key, mouse button, joypad button, and one-direction joypad axis events.
- `scripts/input/input_profile_store.gd` — versioned atomic persistence and backup recovery for global remaps.
- `scripts/input/input_remap_service.gd` — validates, swaps, applies, resets, and persists bindings.
- `scenes/ui/input_remap_panel.tscn` and `scripts/ui/input_remap_panel.gd` — controller-operable binding list and capture modal.

### Focus and accessibility

- `scripts/ui/focus_coordinator.gd` — modal focus stack, deferred entry, ring navigation, and restoration.
- `scripts/accessibility/accessibility_runtime.gd` — applies normalized visual/audio settings and exposes assist configuration.
- `scripts/accessibility/subtitle_presenter.gd` — localized, timed subtitle cue presentation.
- `default_bus_layout.tres` — Master, Music, SFX, and Dialogue buses.

### Existing integration points

- `project.godot`
- `autoload/game_state.gd`
- `scripts/main.gd`
- `scenes/main.tscn`
- `scripts/ui/pause_menu.gd`
- `scripts/ui/run_end_overlay.gd`
- `scripts/ui/views/choice_panel_view.gd`
- `scripts/player/player_controller.gd`
- `scripts/presentation/combat_audio_synth.gd`
- `scripts/presentation/combat_feedback_overlay.gd`
- `scripts/fx/combat_telegraph_2d.gd`
- `data/schemas/save_settings_v1.schema.json`
- `scripts/save/save_envelope.gd`
- `scripts/save/migrations/save_migration_v0_to_v1.gd`
- `data/localization/translations.csv`
- `data/content_packs/base/localization/translations.csv`

### Verification

- `tests/contract/input/input_action_contract_test.gd`
- `tests/contract/input/input_action_contract_test.tscn`
- `tests/unit/input/input_binding_codec_test.gd`
- `tests/unit/input/input_profile_store_test.gd`
- `tests/unit/input/input_remap_service_test.gd`
- `tests/unit/ui/focus_coordinator_test.gd`
- `tests/integration/ui/controller_focus_flow_test.gd`
- `tests/integration/ui/controller_focus_flow_test.tscn`
- `tests/integration/ui/accessibility_settings_flow_test.gd`
- `tests/integration/ui/accessibility_settings_flow_test.tscn`
- `tests/player/ranged_charge_accessibility_test.gd`
- `tests/player/ranged_charge_accessibility_test.tscn`
- `docs/current/2026-09-29-p6-controller-accessibility-evidence.md`

---

### Task 1: Freeze the required dual-device input contract

**Files:**

- Create: `scripts/input/input_action_contract.gd`
- Modify: `project.godot:42-140`
- Create: `tests/contract/input/input_action_contract_test.gd`
- Create: `tests/contract/input/input_action_contract_test.tscn`

**Interfaces:**

- Consumes: Godot `InputMap` entries from `project.godot`.
- Produces: `InputActionContract.required_actions() -> Array[StringName]`, `binding_families(action: StringName) -> Dictionary`, `missing_required_bindings() -> Array[Dictionary]`, and `controller_binding_ids(action: StringName) -> Array[String]`.

- [x] **Step 1: Record the scene-suite baseline**

Run:

```bash
./tools/run_tests.sh
```

Recorded result on 2026-09-29: 42 scenes discovered. The active P3 pool cutover made `tests/reward_system_smoke.tscn` fail to parse because its historical `REWARDS`, `CURSES`, `BLESSINGS`, and `TALENTS` constants were being removed in another lane. All P6-adjacent UI, presentation, player, time, and contract scenes reached green in the captured run. This is a pre-existing concurrent-lane signature, not a P6 regression.

- [x] **Step 2: Write the failing input contract**

The test requires the following controller IDs and a 0.25 deadzone for all four movement actions:

```gdscript
var expected_controller_bindings := {
	&"move_up": ["axis:1:-1", "button:11"],
	&"move_down": ["axis:1:1", "button:12"],
	&"move_left": ["axis:0:-1", "button:13"],
	&"move_right": ["axis:0:1", "button:14"],
	&"attack": ["button:2"],
	&"heavy_attack": ["button:3"],
	&"ranged_attack": ["axis:5:1"],
	&"dash": ["button:1"],
	&"time_stop": ["button:9"],
	&"time_rewind": ["button:10"],
	&"time_rift": ["axis:4:1"],
	&"time_accelerate": ["button:8"],
	&"interact": ["button:0"],
	&"pause": ["button:6"],
}
```

- [x] **Step 3: Verify the red state**

Run:

```bash
./tools/run_tests.sh --filter input_action_contract_test --timeout 2
```

Recorded expected failure:

```text
Parse Error: Preload file "res://scripts/input/input_action_contract.gd" does not exist.
Scene tests: 0 passed, 1 failed, 1 total
```

- [x] **Step 4: Implement the minimal contract and mappings**

`InputActionContract.missing_required_bindings()` reports `{ "action": <id>, "family": "keyboard_mouse" | "controller" | "action" }`. `project.godot` adds one standard joypad binding to each non-movement action and both left-stick and D-pad bindings to movement.

- [x] **Step 5: Verify the focused green state**

Run:

```bash
./tools/run_tests.sh --filter input_action_contract_test --timeout 20
```

Recorded result:

```text
Scene tests: 1 passed, 0 failed, 1 total
```

- [x] **Step 6: Create the focused commit**

Run:

```bash
git add project.godot scripts/input/input_action_contract.gd tests/contract/input/input_action_contract_test.gd tests/contract/input/input_action_contract_test.tscn docs/superpowers/plans/2026-09-29-plane-walker-p6-controller-accessibility.md
git diff --cached --check
git commit -m "feat(input): define controller action contract"
```

Expected: only the five named P6 paths are committed; concurrent dirty files remain unstaged.

---

### Task 2: Add a versioned, recoverable input profile

**Files:**

- Create: `scripts/input/input_binding_codec.gd`
- Create: `scripts/input/input_profile_store.gd`
- Create: `tests/unit/input/input_binding_codec_test.gd`
- Create: `tests/unit/input/input_binding_codec_test.tscn`
- Create: `tests/unit/input/input_profile_store_test.gd`
- Create: `tests/unit/input/input_profile_store_test.tscn`

**Interfaces:**

- Consumes: `InputEventKey`, `InputEventMouseButton`, `InputEventJoypadButton`, and `InputEventJoypadMotion`.
- Produces: `InputBindingCodec.encode(event: InputEvent) -> Dictionary`, `decode(record: Dictionary) -> InputEvent`, `canonical_id(record: Dictionary) -> String`, `InputProfileStore.save(profile: Dictionary) -> Dictionary`, and `load() -> Dictionary`.
- Input profile document shape is exact:

```json
{
  "schema_version": 1,
  "bindings": {
    "attack": {
      "keyboard_mouse": [{"type":"mouse_button","button_index":1}],
      "controller": [{"type":"joypad_button","button_index":2}]
    }
  }
}
```

- [x] **Step 1: Write codec failures before production code**

Create round-trip assertions for one event of each supported type:

```gdscript
var records := [
	{"type": "key", "physical_keycode": KEY_Q},
	{"type": "mouse_button", "button_index": MOUSE_BUTTON_LEFT},
	{"type": "joypad_button", "button_index": JOY_BUTTON_X},
	{"type": "joypad_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "direction": 1},
]
for record: Dictionary in records:
	var decoded: InputEvent = InputBindingCodecScript.decode(record)
	_suite.assert_true(decoded != null, "supported record decodes")
	_suite.assert_equal(InputBindingCodecScript.encode(decoded), record, "binding round-trips")
```

Reject unknown keys, device-specific IDs, zero axis direction, and unsupported event classes with an empty dictionary/null result.

- [x] **Step 2: Run the codec test and capture the missing-script failure**

Run:

```bash
./tools/run_tests.sh --filter input_binding_codec_test --timeout 3
```

Expected: parse failure naming `scripts/input/input_binding_codec.gd`.

- [x] **Step 3: Implement the exact codec**

Use this dispatch and no `str(event)` serialization:

```gdscript
static func encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "physical_keycode": (event as InputEventKey).physical_keycode}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button_index": (event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"type": "joypad_button", "button_index": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "joypad_axis", "axis": motion.axis, "direction": -1 if motion.axis_value < 0.0 else 1}
	return {}
```

`decode()` always sets `device = -1`; axis values are exactly `-1.0` or `1.0`.

- [x] **Step 4: Write atomic-store failures**

The store test uses a unique `PLANEWALKER_TEST_DATA_DIR` root and asserts:

```gdscript
var saved := store.save(profile)
suite.assert_true(saved.ok, "valid profile saves")
suite.assert_equal(store.load().profile, profile, "saved profile loads exactly")
_write_text(store.primary_path(), "{")
suite.assert_equal(store.load().source, "backup_1", "corrupt primary recovers backup")
suite.assert_true(not FileAccess.file_exists(store.pending_path()), "pending file is removed after success")
```

Invalid schema version, unknown action, missing binding family, duplicate canonical binding, and a binding belonging to the wrong family return `ok=false` without replacing the primary.

- [x] **Step 5: Implement `InputProfileStore`**

Constructor/configuration:

```gdscript
func configure(root_path: String = "user://plane_walker/input") -> void:
	_root_path = ProjectSettings.globalize_path(root_path)
```

Save order is exact: validate → write `pending.tmp` → parse/validate pending → copy verified primary to `backup_1.json` → rename pending to `input_profile_v1.json` → parse/validate primary. A failure preserves the last verified primary and returns `{ "ok": false, "code": <stable_code> }`.

- [x] **Step 6: Run focused tests and commit**

Run:

```bash
./tools/run_tests.sh --filter input_binding_codec_test
./tools/run_tests.sh --filter input_profile_store_test
git add scripts/input/input_binding_codec.gd scripts/input/input_profile_store.gd tests/unit/input/input_binding_codec_test.gd tests/unit/input/input_binding_codec_test.tscn tests/unit/input/input_profile_store_test.gd tests/unit/input/input_profile_store_test.tscn
git diff --cached --check
git commit -m "feat(input): persist recoverable remap profiles"
```

Expected: both scenes pass with no runtime or leak signatures.

---

### Task 3: Apply safe remaps without making actions unreachable

**Files:**

- Create: `scripts/input/input_remap_service.gd`
- Create: `tests/unit/input/input_remap_service_test.gd`
- Create: `tests/unit/input/input_remap_service_test.tscn`

**Interfaces:**

- Consumes: `InputActionContract`, `InputBindingCodec`, `InputProfileStore`, and current `InputMap` defaults.
- Produces: `load_or_defaults() -> Dictionary`, `remap(action: StringName, family: StringName, event: InputEvent) -> Dictionary`, `reset_action(action: StringName) -> Dictionary`, `reset_all() -> Dictionary`, `binding_labels(action: StringName) -> Dictionary`, and `bindings_changed(action: StringName)`.
- Conflict rule: if the requested canonical binding already belongs to a different required action in the same family, swap the two actions' first bindings atomically. If the displaced action has no first binding, reject with `UNREACHABLE_ACTION`.

- [x] **Step 1: Write remap invariants as failing tests**

```gdscript
var result := service.remap(&"attack", &"controller", _joy_button(JOY_BUTTON_Y))
suite.assert_true(result.ok, "controller binding remaps")
suite.assert_equal(_controller_buttons(&"attack"), [JOY_BUTTON_Y], "attack receives Y")
suite.assert_equal(_controller_buttons(&"heavy_attack"), [JOY_BUTTON_X], "conflicting heavy attack receives displaced X")
suite.assert_equal(InputActionContractScript.missing_required_bindings(), [], "swap preserves reachability")
```

Also assert that Esc/Start cannot be bound away from `pause` unless another pause binding remains, analog axis values below `0.75` are rejected for capture, and `reset_all()` reproduces the Task 1 controller IDs exactly.

- [x] **Step 2: Verify the red state**

Run:

```bash
./tools/run_tests.sh --filter input_remap_service_test --timeout 3
```

Expected: missing `input_remap_service.gd` parse failure.

- [x] **Step 3: Implement validation, swapping, and rollback**

The mutation sequence is exact:

```gdscript
var before := _snapshot_runtime_bindings()
var candidate := _build_swapped_candidate(action, family, event)
var validation := _validate_profile(candidate)
if not validation.ok:
	return validation
_apply_profile(candidate)
var saved := _store.save(candidate)
if not saved.ok:
	_apply_profile(before)
	return saved
bindings_changed.emit(action)
return {"ok": true, "profile": candidate.duplicate(true)}
```

`load_or_defaults()` applies a verified profile only after complete validation; corrupt/invalid data recovers backup or resets to project defaults and returns a non-fatal status code for UI messaging.

- [x] **Step 4: Run tests and commit**

Run:

```bash
./tools/run_tests.sh --filter input_remap_service_test
./tools/run_tests.sh --filter input_action_contract_test
git add scripts/input/input_remap_service.gd tests/unit/input/input_remap_service_test.gd tests/unit/input/input_remap_service_test.tscn
git diff --cached --check
git commit -m "feat(input): apply safe persistent remaps"
```

Expected: both tests pass and `missing_required_bindings()` remains empty after all test mutations.

---

### Task 4: Centralize modal focus entry and restoration

**Files:**

- Create: `scripts/ui/focus_coordinator.gd`
- Create: `tests/unit/ui/focus_coordinator_test.gd`
- Create: `tests/unit/ui/focus_coordinator_test.tscn`
- Modify: `project.godot:23-29`

**Interfaces:**

- Consumes: modal root `Node`, initial `Control`, current viewport focus owner, and valid visible focusable descendants.
- Produces: autoload `FocusCoordinator.open_scope(scope: Node, initial_focus: Control)`, `close_scope(scope: Node)`, `recover(scope: Node, fallback: Control)`, `link_ring(controls: Array[Control], horizontal: bool)`, and `active_scope() -> Node`.

- [x] **Step 1: Write nested-modal focus failures**

Build controls entirely in the test and assert:

```gdscript
base_button.grab_focus()
FocusCoordinator.open_scope(selection, option_one)
await get_tree().process_frame
suite.assert_equal(get_viewport().gui_get_focus_owner(), option_one, "selection receives initial focus")
FocusCoordinator.open_scope(pause, resume_button)
await get_tree().process_frame
suite.assert_equal(get_viewport().gui_get_focus_owner(), resume_button, "pause takes focus")
FocusCoordinator.close_scope(pause)
await get_tree().process_frame
suite.assert_equal(get_viewport().gui_get_focus_owner(), option_one, "closing pause restores selection")
```

Also cover a freed previous owner, hidden initial control, disabled button, closing a non-top scope, and `recover()` when focus escapes outside the active scope.

- [x] **Step 2: Verify the red state**

Run:

```bash
./tools/run_tests.sh --filter focus_coordinator_test --timeout 3
```

Expected: the `FocusCoordinator` autoload or script is absent.

- [x] **Step 3: Implement a bounded focus-frame stack**

Each frame stores weak references to `scope`, `initial_focus`, and `previous_owner`. `open_scope()` removes an older frame for the same scope, pushes one frame, and uses `call_deferred("_focus_first_valid", scope, initial_focus)`. `_is_focusable()` requires `is_instance_valid`, `is_visible_in_tree`, `focus_mode != Control.FOCUS_NONE`, and `not disabled` for `BaseButton`.

`link_ring()` sets both `focus_neighbor_left/right` or `focus_neighbor_top/bottom` plus `focus_next/focus_previous`, wrapping first and last controls.

- [x] **Step 4: Register the autoload and verify**

Add:

```ini
FocusCoordinator="*res://scripts/ui/focus_coordinator.gd"
```

Run:

```bash
./tools/run_tests.sh --filter focus_coordinator_test
git add project.godot scripts/ui/focus_coordinator.gd tests/unit/ui/focus_coordinator_test.gd tests/unit/ui/focus_coordinator_test.tscn
git diff --cached --check
git commit -m "feat(ui): centralize modal focus recovery"
```

Expected: nested and invalid-owner cases pass with no orphan nodes.

---

### Task 5: Complete all Current flows with controller-only focus

**Files:**

- Modify: `scripts/main.gd:18-166`
- Modify: `scripts/ui/pause_menu.gd:18-96`
- Modify: `scripts/ui/run_end_overlay.gd:9-52`
- Modify: `scripts/ui/views/choice_panel_view.gd:22-117`
- Modify: `scenes/main.tscn:80-200`
- Modify: `tests/ui/choice_panel_v2_scene_test.gd`
- Create: `tests/integration/ui/controller_focus_flow_test.gd`
- Create: `tests/integration/ui/controller_focus_flow_test.tscn`

**Interfaces:**

- Consumes: `FocusCoordinator`, existing `interact`, `pause`, built-in `ui_accept`, `ui_cancel`, and directional UI actions.
- Produces: deterministic focus ownership for Start → Choice → Pause-over-Choice → Choice restore → Run End → Restart.

- [ ] **Step 1: Write the authoritative controller-flow test**

Instantiate `scenes/main.tscn`, disable `RuntimeV2Adapter` where domain setup is not under test, and drive actions through `Input.parse_input_event()`:

```gdscript
await _settle()
suite.assert_equal(_focus_name(), "StartButton", "start menu owns focus")
_press_action(&"ui_accept")
await _settle()
suite.assert_true(not main.start_menu.visible, "controller starts a run")
choice_panel.render(FixturesScript.load_fixture("res://tests/fixtures/ui/choice_item_three.json"))
await _settle()
suite.assert_equal(_focus_name(), "Option_choose_frozen_burst", "first valid choice owns focus")
_press_action(&"pause")
await _settle()
suite.assert_equal(_focus_name(), "ResumeButton", "pause owns focus over selection")
_press_action(&"ui_cancel")
await _settle()
suite.assert_equal(_focus_name(), "Option_choose_frozen_burst", "closing pause restores choice focus")
```

The test then emits `run_ended`, verifies `RestartButton`, accepts it through a test-safe restart callable, and asserts Start receives focus after reset. It also proves every choice is reachable with `ui_right` and that rejection returns focus to the previously submitted option.

- [ ] **Step 2: Run the flow test red**

Run:

```bash
./tools/run_tests.sh --filter controller_focus_flow_test --timeout 20
```

Expected: start menu has no focus and pause close does not restore selection.

- [ ] **Step 3: Add screen-owned focus declarations**

Use these exact calls:

```gdscript
# scripts/main.gd
func _show_start_menu() -> void:
	start_menu.visible = true
	FocusCoordinator.open_scope(start_menu, start_button)
	# existing summary rendering follows

func _start_new_run() -> void:
	if not start_menu.visible:
		return
	FocusCoordinator.close_scope(start_menu)
	# existing run startup follows
```

```gdscript
# scripts/ui/pause_menu.gd
func show_pause() -> void:
	visible = true
	FocusCoordinator.open_scope(self, resume_button)

func hide_pause() -> void:
	FocusCoordinator.close_scope(self)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()
```

```gdscript
# scripts/ui/run_end_overlay.gd
visible = true
FocusCoordinator.open_scope(self, restart_button)
```

```gdscript
# choice_panel_view.gd, after all buttons are children
var buttons: Array[Control] = []
for child: Node in options_container.get_children():
	if child is Button and not (child as Button).disabled:
		buttons.append(child as Control)
FocusCoordinator.link_ring(buttons, true)
FocusCoordinator.open_scope(self, buttons[0])
```

`show_rejection()` recovers the first enabled option; `close_panel()` closes its scope before deleting buttons.

- [ ] **Step 4: Declare explicit scene navigation order**

In `scenes/main.tscn`, set `focus_mode = 2` on Start, Resume, Restart, Quit, sliders, and toggles. Set `focus_next`/`focus_previous` as a closed vertical ring for pause controls. Noninteractive labels keep `focus_mode = 0`.

- [ ] **Step 5: Run Current-flow regressions and commit**

Run:

```bash
./tools/run_tests.sh --filter controller_focus_flow_test
./tools/run_tests.sh --filter choice_panel_v2_scene_test
./tools/run_tests.sh --filter pixel_canvas_test
git add scripts/main.gd scripts/ui/pause_menu.gd scripts/ui/run_end_overlay.gd scripts/ui/views/choice_panel_view.gd scenes/main.tscn tests/ui/choice_panel_v2_scene_test.gd tests/integration/ui/controller_focus_flow_test.gd tests/integration/ui/controller_focus_flow_test.tscn
git diff --cached --check
git commit -m "feat(ui): complete controller focus flows"
```

Expected: controller flow, choice, and 640×360 layout tests all pass.

---

### Task 6: Add an in-game remapping panel

**Files:**

- Create: `scripts/ui/input_remap_panel.gd`
- Create: `scenes/ui/input_remap_panel.tscn`
- Modify: `scripts/ui/pause_menu.gd`
- Modify: `scenes/main.tscn`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/localization/translations.csv`
- Create: `tests/integration/ui/input_remap_panel_test.gd`
- Create: `tests/integration/ui/input_remap_panel_test.tscn`

**Interfaces:**

- Consumes: `InputActionContract.required_actions()`, `InputRemapService.binding_labels()`, captured input events, and `FocusCoordinator`.
- Produces: `open_panel()`, `close_panel()`, `capture_started(action, family)`, localized conflict/recovery messages, Reset Action, and Reset All.

- [ ] **Step 1: Write UI capture failures**

Assert that the panel renders exactly 14 action rows, each row exposes keyboard/mouse and controller buttons, opening focuses the first binding, choosing Attack Controller opens a capture modal, a Y event swaps Attack/Heavy Attack labels, B cancels capture without mutation, Reset All restores Task 1 labels, and closing restores the pause menu's Remap button.

Use synthetic events:

```gdscript
var event := InputEventJoypadButton.new()
event.button_index = JOY_BUTTON_Y
event.pressed = true
Input.parse_input_event(event)
```

- [ ] **Step 2: Verify the red state**

Run:

```bash
./tools/run_tests.sh --filter input_remap_panel_test --timeout 20
```

Expected: remap scene/script is absent.

- [ ] **Step 3: Build the viewport-safe remap scene**

Use a `PanelContainer` no larger than `608×328`, a `ScrollContainer`, one vertical row per action, two binding buttons per row, Reset Action, Reset All, Back, and a capture overlay. All action labels use `INPUT_ACTION_<UPPER_ID>` keys. Binding labels use Godot enum display names and the forms `Left Stick Up`, `D-pad Up`, `Left Trigger`, and `Right Trigger`.

Capture accepts only:

- non-echo key press with nonzero physical keycode;
- mouse button press;
- joypad button press;
- joypad axis motion with absolute value at least `0.75`.

`ui_cancel` closes capture first, then closes the panel on the next press.

- [ ] **Step 4: Add exact localization keys to both catalogs**

Add English and Simplified Chinese values for `UI_INPUT_REMAP`, `UI_BINDING_KEYBOARD_MOUSE`, `UI_BINDING_CONTROLLER`, `UI_PRESS_INPUT`, `UI_BINDING_CONFLICT_SWAPPED`, `UI_BINDING_REJECTED`, `UI_RESET_ACTION`, `UI_RESET_ALL`, `UI_BACK`, and all 14 `INPUT_ACTION_*` labels. Run the localization validator before committing.

- [ ] **Step 5: Verify and commit**

Run:

```bash
python3 tools/validate_localization.py
./tools/run_tests.sh --filter input_remap_panel_test
./tools/run_tests.sh --filter controller_focus_flow_test
./tools/run_tests.sh --filter pixel_canvas_test
git add scripts/ui/input_remap_panel.gd scenes/ui/input_remap_panel.tscn scripts/ui/pause_menu.gd scenes/main.tscn data/localization/translations.csv data/content_packs/base/localization/translations.csv tests/integration/ui/input_remap_panel_test.gd tests/integration/ui/input_remap_panel_test.tscn
git diff --cached --check
git commit -m "feat(ui): add controller-safe input remapping"
```

Expected: localization, remap behavior, focus restoration, and 640×360 fit pass.

---

### Task 7: Normalize and persist the complete Current accessibility settings

**Files:**

- Modify after P2 integration: `autoload/game_state.gd:8-18,231-340`
- Modify after P2 integration: `data/schemas/save_settings_v1.schema.json:26-45`
- Modify after P2 integration: `scripts/save/save_envelope.gd:43-50,324-338`
- Modify after P2 integration: `scripts/save/migrations/save_migration_v0_to_v1.gd:4-15`
- Modify after P2 integration: `tests/contract/save/save_contract_test.gd:86-114`
- Modify after P2 integration: `tests/unit/save/save_envelope_test.gd`
- Modify after P2 integration: `tests/unit/save/save_service_test.gd`
- Create: `tests/integration/ui/accessibility_settings_flow_test.gd`
- Create: `tests/integration/ui/accessibility_settings_flow_test.tscn`

**Interfaces:**

- Consumes: existing global settings envelope and atomic `SaveService.save_settings/load_settings`.
- Produces: `GameState.normalized_settings() -> Dictionary` with these exact defaults:

```gdscript
const DEFAULT_SETTINGS := {
	"locale": "zh_CN",
	"master_volume": 0.85,
	"master_muted": false,
	"music_volume": 0.80,
	"sfx_volume": 0.90,
	"dialogue_volume": 0.90,
	"camera_shake_enabled": true,
	"hit_flash_enabled": true,
	"reduced_motion": false,
	"text_scale": 1.0,
	"high_contrast_danger": false,
	"subtitles_enabled": true,
	"subtitle_scale": 1.0,
	"ranged_charge_mode": "hold",
	"damage_received_multiplier": 1.0,
	"enemy_telegraph_scale": 1.0,
}
```

- [ ] **Step 1: Write backward-compatibility and persistence failures**

Tests load a historical six-field settings v1 payload, require the exact defaults above for absent fields, write the expanded payload, reload it, and assert every field survives. Invalid enum/number values are rejected: text/subtitle scale must be one of `1.0`, `1.25`, `1.5`; charge mode is `hold` or `toggle`; damage multiplier is `1.0`, `0.8`, or `0.6`; telegraph scale is `1.0`, `1.25`, or `1.5`; all volumes are finite `0.0…1.0`.

- [ ] **Step 2: Run the focused save/UI tests red**

Run:

```bash
./tools/run_tests.sh --filter save_envelope_test
./tools/run_tests.sh --filter accessibility_settings_flow_test --timeout 20
```

Expected: the expanded payload is rejected and the accessibility scene test is absent.

- [ ] **Step 3: Add read-compatible schema normalization**

Keep settings schema ID and envelope `schema_version` at `1`. The original six fields remain required in the JSON schema; new fields are declared properties but are optional on read. `GameState._settings_payload()` always merges `DEFAULT_SETTINGS` first, so every newly written payload is complete.

Replace exact-field validation for settings with:

```gdscript
if not _has_required_fields(payload, LEGACY_SETTINGS_REQUIRED_FIELDS):
	return {"field": "payload", "reason": "missing-required-fields"}
if not _has_only_known_fields(payload, SETTINGS_PAYLOAD_FIELDS):
	return {"field": "payload", "reason": "unknown-fields"}
```

Then validate each optional new field only when present. On load, merge defaults before exposing values or saving again.

- [ ] **Step 4: Verify compatibility and commit the save-owned batch**

Run:

```bash
./tools/run_tests.sh --filter save_contract_test
./tools/run_tests.sh --filter save_envelope_test
./tools/run_tests.sh --filter save_service_test
./tools/run_tests.sh --filter game_state_save_integration_test
git add autoload/game_state.gd data/schemas/save_settings_v1.schema.json scripts/save/save_envelope.gd scripts/save/migrations/save_migration_v0_to_v1.gd tests/contract/save/save_contract_test.gd tests/unit/save/save_envelope_test.gd tests/unit/save/save_service_test.gd tests/integration/ui/accessibility_settings_flow_test.gd tests/integration/ui/accessibility_settings_flow_test.tscn
git diff --cached --check
git commit -m "feat(accessibility): persist normalized settings"
```

Expected: historical settings remain readable, new settings round-trip, and the P2 corruption/backup tests remain green.

---

### Task 8: Apply visual, subtitle, audio-bus, and hold/toggle alternatives

**Files:**

- Create: `scripts/accessibility/accessibility_runtime.gd`
- Create: `scripts/accessibility/subtitle_presenter.gd`
- Create: `default_bus_layout.tres`
- Modify: `project.godot`
- Modify: `scripts/ui/pause_menu.gd`
- Modify: `scenes/main.tscn`
- Modify: `scripts/player/player_controller.gd:72-81`
- Modify: `scripts/presentation/combat_audio_synth.gd`
- Modify: `scripts/presentation/combat_feedback_overlay.gd`
- Modify: `scripts/fx/combat_telegraph_2d.gd`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/localization/translations.csv`
- Create: `tests/player/ranged_charge_accessibility_test.gd`
- Create: `tests/player/ranged_charge_accessibility_test.tscn`
- Extend: `tests/integration/ui/accessibility_settings_flow_test.gd`
- Extend: `tests/presentation/combat_feedback_runtime_test.gd`

**Interfaces:**

- Consumes: `GameState.setting_changed`, normalized settings, UI roots, combat danger overlays/telegraphs, and ranged input edges.
- Produces: `AccessibilityRuntime.apply_to_tree(root: Node)`, `settings_snapshot() -> Dictionary`, `damage_received_multiplier() -> float`, `enemy_telegraph_scale() -> float`, and `SubtitlePresenter.present(cue_key: StringName, duration: float, speaker_key: StringName = &"")`.

- [ ] **Step 1: Write failing behavior tests**

Accessibility integration assertions:

```gdscript
GameState.set_setting("text_scale", 1.5)
suite.assert_equal(accessibility.settings_snapshot()["text_scale"], 1.5, "text scale applies immediately")
suite.assert_true(title_label.get_theme_font_size("font_size") >= 24, "title text scales from its base size")
GameState.set_setting("subtitles_enabled", false)
subtitle_presenter.present(&"TEST_SUBTITLE", 1.0)
suite.assert_true(not subtitle_presenter.visible, "disabled subtitles remain hidden")
```

Ranged toggle assertions:

```gdscript
GameState.set_setting("ranged_charge_mode", "toggle")
player.handle_ranged_input_for_test(true, false)
suite.assert_true(player.bow_weapon.is_charging(), "first toggle press starts charge")
player.handle_ranged_input_for_test(true, false)
suite.assert_true(not player.bow_weapon.is_charging(), "second toggle press releases charge")
```

Presentation assertions require high-contrast danger to use a light/dark luminance delta of at least `0.70`, retain the existing geometric band/telegraph cue, and reduced motion to suppress only nonessential motion, never timing or danger visibility.

- [ ] **Step 2: Verify focused red states**

Run:

```bash
./tools/run_tests.sh --filter accessibility_settings_flow_test
./tools/run_tests.sh --filter ranged_charge_accessibility_test --timeout 20
./tools/run_tests.sh --filter combat_feedback_runtime_test
```

Expected: new runtime/script/settings behaviors are absent.

- [ ] **Step 3: Add the bus layout and deterministic volume application**

`default_bus_layout.tres` defines Master plus Music, SFX, and Dialogue child buses. `AccessibilityRuntime` maps linear settings to decibels with `linear_to_db(clampf(value, 0.001, 1.0))`; master mute applies only to Master. `CombatAudioSynth` assigns generated combat players to `SFX`. `SubtitlePresenter` is presentation-only and uses the Dialogue setting for future spoken cues without requiring audio to show text.

- [ ] **Step 4: Apply text scale without cumulative multiplication**

For each `Control`, store original explicit font sizes in metadata keys beginning `accessibility_base_font_`. Reapplication always computes `roundi(base_size * text_scale)`, never current size times scale. Dynamically created choice cards call `AccessibilityRuntime.apply_to_tree(button)` after their labels are added.

- [ ] **Step 5: Apply high-contrast and color-independent danger cues**

High contrast changes overlay/telegraph palette to near-black `Color("101216")`, white `Color("f7fbff")`, and amber `Color("ffd166")`. Existing pulse bands, outlines, attack arcs, and audio cues remain active so color is never the only channel. `enemy_telegraph_scale` multiplies visual lead duration/size only; it does not change the authoritative enemy attack frame.

- [ ] **Step 6: Implement hold/toggle ranged input**

Extract input edges into:

```gdscript
func handle_ranged_input_for_test(just_pressed: bool, just_released: bool) -> void:
	var mode := str(GameState.get_setting("ranged_charge_mode", "hold"))
	if mode == "toggle":
		if just_pressed:
			try_action(&"ranged_release" if bow_weapon.is_charging() else &"ranged_attack")
		return
	if just_pressed:
		try_action(&"ranged_attack")
	if just_released:
		try_action(&"ranged_release")
```

`_handle_attack_input()` delegates its ranged edges to this method. Hold mode preserves existing behavior exactly.

- [ ] **Step 7: Add the complete pause/settings controls and disclosure**

Use controller-focusable OptionButtons/CheckButtons/Sliders for the exact Task 7 fields. The assist group displays localized neutral copy equivalent to: “Assist options change incoming damage or warning visibility. They do not reduce rewards, disable progression, or label the player.” The run start payload records both assist values under `accessibility_assists`.

- [ ] **Step 8: Verify and commit**

Run:

```bash
python3 tools/validate_localization.py
./tools/run_tests.sh --filter accessibility_settings_flow_test
./tools/run_tests.sh --filter ranged_charge_accessibility_test
./tools/run_tests.sh --filter combat_feedback_runtime_test
./tools/run_tests.sh --filter pixel_canvas_test
git add scripts/accessibility/accessibility_runtime.gd scripts/accessibility/subtitle_presenter.gd default_bus_layout.tres project.godot scripts/ui/pause_menu.gd scenes/main.tscn scripts/player/player_controller.gd scripts/presentation/combat_audio_synth.gd scripts/presentation/combat_feedback_overlay.gd scripts/fx/combat_telegraph_2d.gd data/localization/translations.csv data/content_packs/base/localization/translations.csv tests/player/ranged_charge_accessibility_test.gd tests/player/ranged_charge_accessibility_test.tscn tests/integration/ui/accessibility_settings_flow_test.gd tests/presentation/combat_feedback_runtime_test.gd
git diff --cached --check
git commit -m "feat(accessibility): apply readable persistent options"
```

Expected: settings apply immediately, persist, preserve existing hold behavior, provide toggle behavior, fit 640×360, and keep presentation tests green.

---

### Task 9: Certify the P6 gate and publish repository evidence

**Files:**

- Create: `docs/current/2026-09-29-p6-controller-accessibility-evidence.md`
- Modify: `docs/README.md`

**Interfaces:**

- Consumes: all P6 focused tests, the repository validation entrypoint, clean-log scans, and a detached-worktree check.
- Produces: exact commits, tool versions, commands, results, limitations, rollback points, and an honest automated-versus-human evidence boundary.

- [ ] **Step 1: Run all focused P6 tests**

Run:

```bash
./tools/run_tests.sh --filter input_action_contract_test
./tools/run_tests.sh --filter input_binding_codec_test
./tools/run_tests.sh --filter input_profile_store_test
./tools/run_tests.sh --filter input_remap_service_test
./tools/run_tests.sh --filter focus_coordinator_test
./tools/run_tests.sh --filter input_remap_panel_test
./tools/run_tests.sh --filter controller_focus_flow_test
./tools/run_tests.sh --filter accessibility_settings_flow_test
./tools/run_tests.sh --filter ranged_charge_accessibility_test
```

Expected: every scene passes with zero runtime/leak signatures.

- [ ] **Step 2: Run the complete repository gate**

Run:

```bash
./tools/validate_project.sh
```

Expected: localization, playtest/M1 contracts, two imports, and every discovered scene test pass. If a concurrent lane changed a contract, rebase the P6 assertion on the new authoritative interface rather than weakening the P6 invariant.

- [ ] **Step 3: Certify from a detached checkout**

From a temporary path outside the active worktree, create a detached worktree at the P6 candidate commit, run `./tools/validate_project.sh`, then remove that exact temporary worktree through normal `git worktree remove`. Record the candidate commit and Godot `4.6.1.stable.official.14d19694e` in the evidence file.

- [ ] **Step 4: Write the evidence record**

The evidence document states:

- the exact P6 commits and rollback boundary;
- all focused and repository commands with pass counts;
- the default controller grammar and input-profile recovery behavior;
- focus transitions verified by automation;
- persisted setting IDs/defaults and legacy-read compatibility;
- resolutions verified by automated layout checks;
- human controller comfort, motor accessibility, subtitle comprehension, and real hardware diversity remain authentic external QA and are not claimed by headless tests.

- [ ] **Step 5: Update the documentation index and commit**

Run:

```bash
git add docs/current/2026-09-29-p6-controller-accessibility-evidence.md docs/README.md
git diff --cached --check
git commit -m "docs(accessibility): certify P6 controller gate"
```

Expected: the README links the P6 plan and evidence as `Verified / Completed`, while the full-product spec remains the authority for later Launch/Expansion accessibility work.

---

## Plan Self-Review

- **Spec coverage:** Controller-only completion is Tasks 1, 4, 5, and 6; remapping is Tasks 2, 3, and 6; focus recovery is Tasks 4 and 5; persistence is Tasks 2, 3, and 7; hold/toggle, shake, flash, text scale, high contrast, color-independent cues, subtitles, volume buses, and assist disclosure are Tasks 7 and 8; repository certification is Task 9.
- **Isolation:** Input profiles are separate from gameplay saves and content snapshots. Save-envelope edits are deferred until the active P2 integration is committed. UI focus changes do not write run/domain state.
- **Type consistency:** `InputActionContract`, `InputBindingCodec`, `InputProfileStore`, `InputRemapService`, `FocusCoordinator`, `AccessibilityRuntime`, and `SubtitlePresenter` signatures are defined once and used consistently by later tasks.
- **No hidden evidence:** Automated tests prove bindings, focus ownership, persistence, rendering invariants, and deterministic input behavior. They do not claim real-player comfort or hardware coverage.
- **Rollback:** Each dominant risk has its own focused commit: defaults, persistence, runtime remapping, focus coordinator, flow integration, remap UI, settings compatibility, runtime accessibility, and evidence.
