# Plane Walker Wave 2 Systems Implementation Plan

> **For agentic workers:** Execute each task with a red-green-refactor loop. Steps use checkbox (`- [ ]`) syntax for tracking. In the shared workspace, workers must not run Git write commands; the integration owner reviews and commits each lane.

**Goal:** Add a single validated content registry, the authoritative M1 five-room plan, deterministic route-aware reward drafting, a pure player-action timing model, and a reusable contract-driven choice panel without integrating into the user's currently modified legacy UI.

**Architecture:** Content files remain unchanged and are normalized through a manifest-driven compatibility registry. Drafting consumes registry definitions, a read-only RunState snapshot, SeedService, and room definitions; it returns SelectionOffer data without applying effects. Player action timing and UI choice rendering are independent pure/testable modules, allowing three agents to work in parallel.

**Tech Stack:** Godot 4.6.1, GDScript 2.0, JSON manifests and fixtures, native Godot Control scenes, headless scene tests.

## Global Constraints

- Keep the complete product vision; only M1 availability is filtered.
- Do not edit the four user-modified content JSON files in this wave.
- Do not edit existing reward, curse, event, pause, result, or combat HUD scripts.
- Do not edit `project.godot`, `main.tscn`, `combat_room_01.tscn`, `GameState`, or EventBus.
- ContentRegistry is the only new-code loader and index for runtime content definitions.
- Current `name` and `description` fields normalize to `name_key` and `description_key` without duplicating content data.
- M1 reward generation only uses sword, time stop, time rewind, and general survival/resource definitions.
- Room order is combat, combat, combat, elite, boss; room 2 is not an event and room 5 has no post-Boss reward.
- Gameplay RNG derives through SeedService; UI animation never consumes gameplay RNG.
- DraftService produces immutable SelectionOffer dictionaries and never calls Player, GameState, UI, or effect application.
- Input buffering uses 60 Hz frame counts: eight frames for normal buffered input and twelve frames for combo continuation.
- ChoicePanel consumes SelectionOffer and emits `{offer_id, option_id, revision}` only.
- Existing Wave 0/1 tests and legacy smoke remain regression gates.

---

## File Ownership

### Lane A: Content, rooms, and draft

Owns:

- `data/content_manifest.json`
- `scripts/content/`
- `scripts/dungeon/m1_room_plan.gd`
- `scripts/dungeon/run_director.gd`
- `scripts/rewards/draft_service.gd`
- `tests/contract/content_schema/`
- `tests/unit/dungeon/`
- `tests/unit/rewards/`
- `tests/fixtures/content/`

### Lane B: Player action timing

Owns:

- `scripts/player/player_action_state.gd`
- `tests/player/player_action_state_test.gd`
- `tests/player/player_action_state_test.tscn`

It must not modify `player_controller.gd`, weapons, combat scenes, or InputMap in this wave.

### Lane C: Unified choice view

Owns:

- `scripts/ui/fixtures/selection_offer_fixtures.gd`
- `scripts/ui/views/choice_panel_view.gd`
- `scenes/ui/choice_panel_v2.tscn`
- `tests/fixtures/ui/choice_item_three.json`
- `tests/fixtures/ui/choice_contract_three.json`
- `tests/ui/choice_panel_v2_scene_test.gd`
- `tests/ui/choice_panel_v2_scene_test.tscn`

It must not modify the existing selection UI scripts or total assembly scenes.

---

### Task 1: Build the manifest-driven ContentRegistry

**Files:**

- Create: `data/content_manifest.json`
- Create: `scripts/content/content_validation_report.gd`
- Create: `scripts/content/content_registry.gd`
- Create: `tests/contract/content_schema/content_registry_test.gd`
- Create: `tests/contract/content_schema/content_registry_test.tscn`
- Create: `tests/fixtures/content/valid_items.json`
- Create: `tests/fixtures/content/duplicate_ids.json`
- Create: `tests/fixtures/content/missing_required_field.json`
- Create: `tests/fixtures/content/test_manifest.json`

**Interfaces:**

- Consumes: existing JSON files as read-only inputs.
- Produces: `ContentValidationReport`, `ContentRegistry.load_manifest()`, `load_entries()`, `get_content()`, `get_by_category()`, and `all_content()`.

- [ ] **Step 1: Write failing registry tests**

The test must cover:

```gdscript
var registry = ContentRegistryScript.new()
var report = registry.load_manifest("res://data/content_manifest.json")
suite.assert_true(not report.has_blocking_errors(), "project manifest loads M1 content")

var frozen_burst := registry.get_content(&"frozen_burst")
suite.assert_equal(frozen_burst["name_key"], "FROZEN_BURST_NAME", "legacy name normalizes")
suite.assert_equal(frozen_burst["description_key"], "FROZEN_BURST_DESC", "legacy description normalizes")
suite.assert_true(frozen_burst["availability"].has("M1"), "M1 item is enabled")

suite.assert_true(registry.get_content(&"piercing_draw")["availability"].has("NEXT"), "bow content is preserved as next")
suite.assert_true(registry.get_content(&"rift_snare")["availability"].has("NEXT"), "rift content is preserved as next")
suite.assert_true(registry.get_by_category(&"item", &"M1").all(func(entry): return not str(entry["id"]).contains("piercing")), "M1 item query excludes bow route")
```

Also assert global ID uniqueness, deep-copy results, missing file errors, malformed root errors, duplicate ID blocking errors, missing `id`/`name`/`description`/`effects` errors, and non-M1 invalid entries reported as non-blocking isolation errors.

- [ ] **Step 2: Create the project manifest**

The manifest has this exact shape:

```json
{
  "schema_version": 1,
  "sources": [
    {
      "path": "res://data/items/mvp_items.json",
      "category": "item",
      "default_availability": "NEXT",
      "m1_ids": [
        "sword_edge",
        "quickened_blade",
        "chronal_battery",
        "rewind_salve",
        "tempered_guard",
        "frozen_burst",
        "rewind_echo",
        "accelerated_combo"
      ]
    },
    {
      "path": "res://data/blessings/mvp_blessings.json",
      "category": "blessing",
      "default_availability": "M1",
      "m1_ids": []
    },
    {
      "path": "res://data/talents/mvp_talents.json",
      "category": "talent",
      "default_availability": "NEXT",
      "m1_ids": ["tal_ruin_execute", "tal_steel_recover"]
    },
    {
      "path": "res://data/curses/mvp_curses.json",
      "category": "curse",
      "default_availability": "NEXT",
      "m1_ids": ["glass_tempo", "blood_rewind", "overclocked_stasis"]
    }
  ]
}
```

- [ ] **Step 3: Implement ContentValidationReport**

It stores blocking errors, isolated errors, warnings, and loaded count:

```gdscript
class_name ContentValidationReport
extends RefCounted

var blocking_errors: Array[Dictionary] = []
var isolated_errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
var loaded_count: int = 0

func has_blocking_errors() -> bool:
	return not blocking_errors.is_empty()

func add_error(message: String, context: Dictionary, blocking: bool) -> void:
	var target := blocking_errors if blocking else isolated_errors
	target.append({"message": message, "context": context.duplicate(true)})
```

- [ ] **Step 4: Implement ContentRegistry normalization**

Every valid entry normalizes to:

```gdscript
{
	"schema_version": 1,
	"id": source_entry["id"],
	"category": source_category,
	"availability": ["M1"] or [default_availability],
	"name_key": source_entry["name"],
	"description_key": source_entry["description"],
	"kind": source_entry.get("kind", ""),
	"archetype": source_entry.get("archetype", ""),
	"role": source_entry.get("role", "utility"),
	"rarity": source_entry.get("rarity", "common"),
	"effects": source_entry["effects"].duplicate(true),
}
```

Definitions are stored once by ID; every public getter returns a deep copy. A source marked M1 treats invalid entries as blocking. A NEXT source entry is isolated and omitted from indexes.

- [ ] **Step 5: Run registry tests**

Run:

```bash
godot --headless --path . --scene res://tests/contract/content_schema/content_registry_test.tscn
```

Expected: exit `0`; current content files are read but unchanged.

- [ ] **Step 6: Commit Lane A registry files**

```bash
git add data/content_manifest.json scripts/content tests/contract/content_schema tests/fixtures/content
git commit -m "feat: add validated content registry"
```

---

### Task 2: Freeze the M1 five-room plan

**Files:**

- Create: `scripts/dungeon/m1_room_plan.gd`
- Modify: `scripts/dungeon/run_director.gd`
- Create: `tests/unit/dungeon/m1_room_plan_test.gd`
- Create: `tests/unit/dungeon/m1_room_plan_test.tscn`

**Interfaces:**

- Produces: `M1RoomPlan.definitions()` and `RunDirector.configure_from_definitions()`.
- Preserves: existing `configure_fixed_sequence()` behavior for the legacy runtime.

- [ ] **Step 1: Write the failing room-plan test**

Assert the exact definitions:

```gdscript
[
	{"room_number": 1, "type": "combat", "reward_kind": "starter", "target_seconds_min": 45, "target_seconds_max": 70},
	{"room_number": 2, "type": "combat", "reward_kind": "reinforcement", "target_seconds_min": 60, "target_seconds_max": 85},
	{"room_number": 3, "type": "combat", "reward_kind": "talent", "target_seconds_min": 70, "target_seconds_max": 100},
	{"room_number": 4, "type": "elite", "reward_kind": "contract", "target_seconds_min": 90, "target_seconds_max": 125},
	{"room_number": 5, "type": "boss", "reward_kind": "none", "target_seconds_min": 120, "target_seconds_max": 170},
]
```

Verify there are exactly five rooms, no event room, room 4 is elite, room 5 has no reward, returned arrays are deep copies, and RunDirector returns the same room definitions after configuration.

- [ ] **Step 2: Implement M1RoomPlan**

Use one constant definition array and return `duplicate(true)`. Do not read `GameState` or scenes.

- [ ] **Step 3: Add RunDirector.configure_from_definitions**

```gdscript
func configure_from_definitions(definitions: Array[Dictionary]) -> void:
	room_sequence = definitions.duplicate(true)
	current_room_index = 0
```

Keep `configure_fixed_sequence()` unchanged except for reusing `configure_from_definitions()` if doing so preserves its existing output.

- [ ] **Step 4: Run room-plan and legacy smoke tests**

Run:

```bash
godot --headless --path . --scene res://tests/unit/dungeon/m1_room_plan_test.tscn
godot --headless --path . --scene res://tests/reward_system_smoke.tscn
```

Expected: both exit `0`.

- [ ] **Step 5: Commit room-plan files**

```bash
git add scripts/dungeon/m1_room_plan.gd scripts/dungeon/run_director.gd tests/unit/dungeon
git commit -m "feat: define authoritative M1 room plan"
```

---

### Task 3: Add deterministic route-aware DraftService

**Files:**

- Create: `scripts/rewards/draft_service.gd`
- Create: `tests/unit/rewards/draft_service_test.gd`
- Create: `tests/unit/rewards/draft_service_test.tscn`
- Create: `tests/fixtures/content/draft_entries.json`

**Interfaces:**

- Consumes: `ContentRegistry`, `SeedService`, read-only RunState snapshot dictionaries, M1 room definitions, and `SelectionOffer` validation.
- Produces: `create_offer(registry, state_snapshot, room_definition) -> CommandResult` and `resolve_option(offer, option_id) -> CommandResult`.

- [ ] **Step 1: Write deterministic offer tests**

Use fixture entries containing three starter routes (`time_stop_burst`, `rewind_echo`, `accelerated_combo`), route payoffs, utility entries, three talents, and three curse contracts.

Assert:

- Same seed, snapshot, and room produce identical option IDs.
- Room 1 returns exactly one starter for each of the three routes.
- Room 2 includes one dominant-route reinforcement, one alternative starter, and one utility option.
- Room 3 only returns talent category definitions.
- Room 4 returns two curse options plus a synthetic `decline_contract` safe option.
- Room 5 returns `INVALID_ARGUMENT` because `reward_kind` is `none`.
- Owned IDs never appear.
- Definitions unavailable in M1 never appear.
- Every generated offer passes `SelectionOffer.validate()`.
- All 1,000 seeds return the three valid room-1 routes.
- `resolve_option()` rejects missing options and returns a deep-copied selected definition for valid options.

- [ ] **Step 2: Implement offer identity and RNG**

Offer ID format:

```text
run_id:room-XX:category:revision
```

Draft RNG uses:

```gdscript
SeedService.make_rng(run_seed, &"draft", 1, room_index, revision)
```

Never use global `randf()`, `randi()`, or visual RNG.

- [ ] **Step 3: Implement role-aware option selection**

Internal helpers are:

```gdscript
func _starter_offer(candidates, rng) -> Array[Dictionary]
func _reinforcement_offer(candidates, dominant_archetype, rng) -> Array[Dictionary]
func _talent_offer(candidates, rng) -> Array[Dictionary]
func _contract_offer(candidates, rng) -> Array[Dictionary]
func _to_option(definition: Dictionary) -> Dictionary
```

`_to_option()` emits only serializable UI fields plus a private copied `definition` field used by `resolve_option()`. The public UI contract fields remain `option_id`, `content_id`, `name_key`, `description_key`, `archetype_key`, `role_key`, `rarity`, `icon_id`, and `effect_summary_keys`.

- [ ] **Step 4: Run DraftService tests**

Run:

```bash
godot --headless --path . --scene res://tests/unit/rewards/draft_service_test.tscn
```

Expected: exit `0`; 1,000-seed coverage completes without invalid offers.

- [ ] **Step 5: Commit DraftService files**

```bash
git add scripts/rewards/draft_service.gd tests/unit/rewards tests/fixtures/content/draft_entries.json
git commit -m "feat: add deterministic M1 draft service"
```

---

### Task 4: Add the pure player action and input-buffer model

**Files:**

- Create: `scripts/player/player_action_state.gd`
- Create: `tests/player/player_action_state_test.gd`
- Create: `tests/player/player_action_state_test.tscn`

**Interfaces:**

- Produces: action-state transitions and frame-based input buffers.
- Does not consume Input singleton, PlayerController, weapon nodes, animation, or scenes.

- [ ] **Step 1: Write failing action-state tests**

The enum is exactly:

```gdscript
enum State {
	FREE,
	ATTACK_WINDUP,
	ATTACK_ACTIVE,
	ATTACK_RECOVERY,
	DASH,
	TIME_CAST,
	HITSTUN,
	DEAD,
}
```

Test:

- An attack buffer remains valid for frames 0–7 and expires on frame 8.
- A combo buffer remains valid for frames 0–11 and expires on frame 12.
- `FREE` allows attack, dash, and time cast.
- `ATTACK_ACTIVE` rejects dash and another attack.
- `ATTACK_RECOVERY` rejects dash before `cancel_from_frame` and accepts it at the cancel frame.
- `DASH` rejects attack.
- `HITSTUN` rejects all actions until its duration completes.
- `DEAD` never returns to FREE through frame advancement.
- State duration completion returns non-terminal states to FREE.

- [ ] **Step 2: Implement frame buffers**

```gdscript
const INPUT_BUFFER_FRAMES := 8
const COMBO_BUFFER_FRAMES := 12

var _frame: int = 0
var _buffers: Dictionary = {}

func buffer_input(action_id: StringName, frames: int = INPUT_BUFFER_FRAMES) -> void:
	_buffers[action_id] = _frame + maxi(1, frames)

func has_buffered_input(action_id: StringName) -> bool:
	return int(_buffers.get(action_id, -1)) > _frame

func consume_buffered_input(action_id: StringName) -> bool:
	if not has_buffered_input(action_id):
		return false
	_buffers.erase(action_id)
	return true
```

- [ ] **Step 3: Implement legal transitions**

Expose:

```gdscript
func transition_to(next_state: State, duration_frames: int, cancel_from_frame: int = -1) -> bool
func can_transition_to(next_state: State) -> bool
func advance_frame() -> void
func elapsed_state_frames() -> int
func remaining_state_frames() -> int
```

Transition priority is `DEAD > HITSTUN > DASH > TIME_CAST > ATTACK > FREE`. `cancel_from_frame` applies only to attack recovery cancellation.

- [ ] **Step 4: Run action-state tests**

Run:

```bash
godot --headless --path . --scene res://tests/player/player_action_state_test.tscn
```

Expected: exit `0` without loading Player scene or InputMap.

- [ ] **Step 5: Commit action-state files**

```bash
git add scripts/player/player_action_state.gd tests/player
git commit -m "feat: add frame-based player action state"
```

---

### Task 5: Build the unified contract-driven choice panel

**Files:**

- Create: `scripts/ui/fixtures/selection_offer_fixtures.gd`
- Create: `scripts/ui/views/choice_panel_view.gd`
- Create: `scenes/ui/choice_panel_v2.tscn`
- Create: `tests/fixtures/ui/choice_item_three.json`
- Create: `tests/fixtures/ui/choice_contract_three.json`
- Create: `tests/ui/choice_panel_v2_scene_test.gd`
- Create: `tests/ui/choice_panel_v2_scene_test.tscn`

**Interfaces:**

- Consumes: dictionaries accepted by `SelectionOffer.validate()`.
- Produces: `render(offer) -> CommandResult`, `show_rejection(message_key)`, `close_panel()`, and signal `option_chosen(offer_id, option_id, revision)`.

- [ ] **Step 1: Create valid item and contract fixtures**

The item fixture has three normal options. The contract fixture has two risk definitions and one `decline_contract` option. Both use schema version 1, stable IDs, localization keys, role keys, rarity, icon ID, and effect summary keys.

- [ ] **Step 2: Write the failing scene test**

Test:

- Scene loads without Player, CombatRoom, GameState access, or reward pools.
- Item fixture renders three buttons.
- Contract fixture renders two risk buttons and one safe decline button.
- Clicking emits exactly `{offer_id, option_id, revision}`.
- Buttons disable immediately after the first click, preventing double submit.
- A second click emits no second signal.
- `show_rejection()` keeps the panel open, shows an error label, and re-enables valid buttons.
- Rendering the same or older revision for the same offer returns `STALE_REVISION`.
- Rendering a different offer ID resets the revision baseline.
- `close_panel()` hides the view and clears generated buttons.

- [ ] **Step 3: Implement fixture loading and pure rendering**

The fixture loader mirrors `RunViewStateFixtures`: FileAccess, JSON parse, SelectionOffer validation, deep copy. The View script may dynamically create Buttons, Labels, VBox/HBox containers, but it must not preload RewardPool, CursePool, Player, GameState, or EventBus.

- [ ] **Step 4: Implement pixel-safe layout**

The scene uses a full-viewport Control, 16-pixel safe margin, centered panel, title, error label, and a horizontal options container. At 640×360, three option cards fit within 608 pixels. Risk cards use red/orange borders; normal time cards use cyan/blue accents; safe decline uses neutral gray.

- [ ] **Step 5: Run tests and dependency scan**

Run:

```bash
godot --headless --path . --scene res://tests/ui/choice_panel_v2_scene_test.tscn
rg -n "GameState|EventBus|PlayerController|RewardPool|CursePool|apply_reward|apply_curse" scripts/ui/fixtures/selection_offer_fixtures.gd scripts/ui/views/choice_panel_view.gd scenes/ui/choice_panel_v2.tscn
```

Expected: test exits `0`; scan has no matches.

- [ ] **Step 6: Commit unified choice files**

```bash
git add scripts/ui/fixtures/selection_offer_fixtures.gd scripts/ui/views/choice_panel_view.gd scenes/ui/choice_panel_v2.tscn tests/fixtures/ui/choice_item_three.json tests/fixtures/ui/choice_contract_three.json tests/ui/choice_panel_v2_scene_test.gd tests/ui/choice_panel_v2_scene_test.tscn
git commit -m "feat: add contract-driven choice panel"
```

---

### Task 6: Wave 2 verification checkpoint

**Files:**

- Modify only newly added Wave 2 files when verification exposes a defect.

- [ ] **Step 1: Import and parse the project**

```bash
godot --headless --editor --path . --quit
```

- [ ] **Step 2: Run Wave 2 tests**

```bash
godot --headless --path . --scene res://tests/contract/content_schema/content_registry_test.tscn
godot --headless --path . --scene res://tests/unit/dungeon/m1_room_plan_test.tscn
godot --headless --path . --scene res://tests/unit/rewards/draft_service_test.tscn
godot --headless --path . --scene res://tests/player/player_action_state_test.tscn
godot --headless --path . --scene res://tests/ui/choice_panel_v2_scene_test.tscn
```

- [ ] **Step 3: Run Wave 0/1 regression tests**

```bash
godot --headless --path . --scene res://tests/unit/application/run_orchestrator_test.tscn
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn
godot --headless --path . --scene res://tests/reward_system_smoke.tscn
```

- [ ] **Step 4: Verify workspace isolation**

```bash
git diff --check
git status --short
```

Only the clean `run_director.gd` may be modified from pre-existing files. User-modified content, localization, legacy UI, main, room controller, project settings, and smoke test must remain untouched.

- [ ] **Step 5: Completion gate**

Wave 2 is complete when:

- One registry loads and validates all four content sources.
- Full content remains indexed while M1 queries exclude bow, rift, and time acceleration dependencies.
- M1 room 2 is combat, room 4 is elite contract, and Boss has no reward.
- Drafts are deterministic, route-aware, owned-item safe, and contract-valid.
- The action model proves 8-frame and 12-frame buffers without scene coupling.
- The unified choice panel works from fixtures and emits one intent per selection.
- Every new and prior regression test exits `0`.

---

## Deferred Integration Boundary

Wave 2 does not replace the legacy runtime. The following remain in the next integration plan:

- Register ContentRegistry and RunOrchestrator in the runtime facade.
- Connect M1RoomPlan to RoomController.
- Route DraftService offers into the choice panel.
- Apply selected effects through an application service.
- Connect PlayerActionState to PlayerController and SwordWeapon.
- Replace existing embedded HUD and reward views in total assembly scenes.
- Add rewind safe-action hooks, enemy telegraphs, elite time-stop resistance, and Boss action mutual exclusion.
