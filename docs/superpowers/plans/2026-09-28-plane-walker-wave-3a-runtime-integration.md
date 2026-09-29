# Plane Walker Wave 3A Runtime Integration Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Preserved Wave 3A implementation record
- Applies To: Runtime facade, legacy bridge, unified selection, main-scene cutover, and five-room smoke flow
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Implementation Status: Verified by `d161da2`, `573bf44`, `36aed4d`, and status checkpoint `1bff8dd`
- Completion Evidence: Commits `d161da2`, `573bf44`, `36aed4d`, and status checkpoint `1bff8dd`
- Completed On: 2026-09-28
- Execution Authority: Superseded by `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Preservation Rule: Runtime facade idempotency, safe legacy fallback, and five-room smoke behavior remain regression requirements.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the M1 five-room run, canonical reward drafting, and unified ChoicePanel operate in the real main scene through one authoritative application command path while preserving the user's current localization and legacy-runtime edits.

**Architecture:** A feature-flagged strangler adapter observes existing lifecycle facts from `GameState`, `RoomController`, and typed EventBus signals, but delegates M1 phase validation, room definitions, offers, and selection consumption to a new pure `RunRuntimeFacade`. The adapter applies a successfully consumed canonical definition exactly once, mirrors it to legacy `GameState`, and emits the one compatibility `reward_selected` fact that advances the existing room spawner. Legacy selection nodes are removed only after the manifest boots successfully; any boot failure leaves the old flow intact.

**Tech Stack:** Godot 4.6.1, GDScript 2.0, existing RunOrchestrator/RunState/ContentRegistry/DraftService/M1RoomPlan contracts, native signals, headless scene tests.

## Global Constraints

- Preserve the complete product vision; Wave 3A changes activation and ownership, not the content roadmap.
- Do not edit `project.godot`, `scripts/main.gd`, `scripts/dungeon/room_controller.gd`, `autoload/game_state.gd`, `autoload/event_bus.gd`, the four content JSON files, localization files, legacy selection scripts, legacy reward pools, or `tests/reward_system_smoke.gd`.
- The only existing scene modified in this wave is clean `scenes/main.tscn`.
- Directly loading `scenes/rooms/combat_room_01.tscn` must retain the legacy smoke behavior.
- `RunRuntimeFacade` is the only new caller that may coordinate RunOrchestrator, ContentRegistry, DraftService, and M1RoomPlan.
- UI emits only `offer_id`, `option_id`, and `revision`; it never applies effects or mutates GameState.
- A definition is applied to Player and mirrored to GameState only after `submit_selection()` succeeds.
- One Offer may be committed once. Duplicate, stale, forged, closed, terminal, and late commands must not change Player, RunState, GameState, room progression, or result.
- Room order is combat, combat, combat, elite, boss. Room 5 produces no post-Boss Offer.
- During selection, Player processing is disabled and remaining enemy projectiles or Boss hazards are cleared before the panel opens.
- Manifest boot failure is a fail-safe compatibility path: V2 stays inactive and legacy selection nodes remain available.
- Existing Wave 0/1/2 tests and `reward_system_smoke.tscn` remain regression gates.

---

## File Ownership

### Lane A: authoritative application flow

Owns:

- `scripts/application/run_orchestrator.gd`
- `scripts/application/run_runtime_facade.gd`
- `tests/unit/application/run_orchestrator_test.gd`
- `tests/unit/application/run_runtime_facade_test.gd`
- `tests/unit/application/run_runtime_facade_test.tscn`

### Lane B: legacy bridge and unified selection

Owns:

- `scripts/application/legacy_run_adapter.gd`
- `tests/integration/application/legacy_run_adapter_test.gd`
- `tests/integration/application/legacy_run_adapter_test.tscn`

### Lane C: main-scene cutover and fixed-seed run

Owns:

- `scenes/main.tscn`
- `tests/smoke/m1_runtime_smoke_test.gd`
- `tests/smoke/m1_runtime_smoke_test.tscn`

Workers must not run Git write commands. The integration owner reviews and commits each lane.

---

### Task 1: Record canonical selections in RunOrchestrator

**Files:**

- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `tests/unit/application/run_orchestrator_test.gd`

**Interfaces:**

- Consumes: the canonical definition returned by DraftService.
- Produces: `selection_resolved(definition: Dictionary = {}) -> CommandResult`.
- Preserves: existing no-argument test and call behavior.

- [ ] **Step 1: Write failing selection-writeback tests**

Add tests that open a valid Offer and call:

```gdscript
var definition := {
	"id": "frozen_burst",
	"category": "item",
	"archetype": "time_stop_burst",
	"effects": {"time_stop_duration_bonus": 0.75},
}
var result = orchestrator.selection_resolved(definition)
suite.assert_true(result.ok, "canonical item selection resolves")
suite.assert_true(orchestrator.state.build_state.items.has("frozen_burst"), "item is written to authoritative build")
suite.assert_equal(orchestrator.state.build_state.dominant_archetype, "time_stop_burst", "selection updates dominant archetype")
```

Also assert:

- blessing, curse, and talent definitions use the matching `record_*` method;
- `{id = "decline_contract", category = "contract"}` advances without recording a curse;
- missing ID, unknown category, or a non-decline contract returns `INVALID_ARGUMENT` and leaves phase, Offer, consumed ledger, and Build unchanged;
- resolving the same Offer a second time returns `ALREADY_CONSUMED` and does not duplicate Build history;
- the existing empty-definition call still resolves for compatibility tests.

- [ ] **Step 2: Run the focused test and confirm red**

Run:

```bash
godot --headless --path . \
  --scene res://tests/unit/application/run_orchestrator_test.tscn \
  --log-file /tmp/planewalker_wave3a_orchestrator_red.log
```

Expected: exit non-zero because `selection_resolved()` does not accept or record a definition.

- [ ] **Step 3: Implement validate-before-consume writeback**

Use this ordering so invalid content cannot close an Offer and duplicate-ledger corruption cannot write Build data:

```gdscript
func selection_resolved(definition: Dictionary = {}):
	if state.phase != RunPhaseScript.Value.SELECTION_ACTIVE:
		return _reject_phase()
	var definition_validation = _validate_selected_definition(definition)
	if not definition_validation.ok:
		return definition_validation
	var offer_id := str(state.open_offer.get("offer_id", ""))
	if not state.mark_offer_consumed(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", state.revision, {"offer_id": offer_id})
	_record_selected_definition(definition)
	state.open_offer = {}
	return _accept_phase(RunPhaseScript.Value.ROOM_TRANSITION)
```

Validation rules:

```gdscript
func _validate_selected_definition(definition: Dictionary):
	if definition.is_empty():
		return CommandResultScript.success(state.revision)
	var content_id := str(definition.get("id", ""))
	var category := str(definition.get("category", ""))
	if content_id.is_empty():
		return CommandResultScript.failure(&"INVALID_ARGUMENT", state.revision, {"field": "definition.id"})
	if category not in ["item", "blessing", "curse", "talent", "contract"]:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", state.revision, {"field": "definition.category"})
	if category == "contract" and content_id != "decline_contract":
		return CommandResultScript.failure(&"INVALID_ARGUMENT", state.revision, {"field": "definition.id"})
	return CommandResultScript.success(state.revision)
```

Recording rules:

```gdscript
match str(definition.get("category", "")):
	"item":
		state.build_state.record_item(definition)
	"blessing":
		state.build_state.record_blessing(definition)
	"curse":
		state.build_state.record_curse(definition)
	"talent":
		state.build_state.record_talent(definition)
```

- [ ] **Step 4: Run application regression tests**

Run:

```bash
godot --headless --path . --scene res://tests/unit/application/run_orchestrator_test.tscn --log-file /tmp/planewalker_wave3a_orchestrator_green.log
godot --headless --path . --scene res://tests/unit/application/run_state_test.tscn --log-file /tmp/planewalker_wave3a_run_state.log
godot --headless --path . --scene res://tests/unit/application/contracts_test.tscn --log-file /tmp/planewalker_wave3a_contracts.log
```

Expected: all exit `0`.

- [ ] **Step 5: Commit Lane A writeback**

```bash
git add scripts/application/run_orchestrator.gd tests/unit/application/run_orchestrator_test.gd
git commit -m "feat: record canonical run selections"
```

---

### Task 2: Build the pure RunRuntimeFacade

**Files:**

- Create: `scripts/application/run_runtime_facade.gd`
- Create: `tests/unit/application/run_runtime_facade_test.gd`
- Create: `tests/unit/application/run_runtime_facade_test.tscn`

**Interfaces:**

- Consumes: ContentRegistry, M1RoomPlan, RunDirector, DraftService, RunOrchestrator.
- Produces the frozen command API:

```gdscript
func boot(manifest_path: String = "res://data/content_manifest.json")
func start_run(config: Dictionary, run_id: String)
func enter_current_room()
func complete_current_room()
func submit_selection(offer_id: String, option_id: String, revision: int)
func complete_transition()
func player_died(context: Dictionary = {})
func boss_defeated(context: Dictionary = {})
func pause_run()
func resume_run()
func snapshot() -> Dictionary
func current_room_definition() -> Dictionary
```

- [ ] **Step 1: Write failing facade tests**

The tests use the real project manifest and fixed seed `20260929`. Cover:

```gdscript
var facade = RunRuntimeFacadeScript.new()
suite.assert_true(facade.boot().ok, "manifest boots")
suite.assert_true(facade.start_run({"seed": 20260929}, "wave3a-run").ok, "run starts")
suite.assert_true(facade.enter_current_room().ok, "room one enters")
var completion = facade.complete_current_room()
suite.assert_true(completion.ok, "room one completes")
var offer: Dictionary = completion.context["offer"]
suite.assert_equal(offer["category"], "item", "room one opens starter item offer")
```

Continue through rooms 1–4 and assert:

- room 1 is starter, room 2 reinforcement, room 3 talent, room 4 contract;
- selecting a room-1 starter writes it to `snapshot()["build"]`;
- room 2 excludes the owned starter and includes the selected dominant-route payoff;
- forged Offer ID returns `OFFER_CLOSED`, forged revision returns `STALE_REVISION`, and forged option returns `OPTION_NOT_FOUND`;
- the second submit of a committed Offer returns `ALREADY_CONSUMED`;
- decline contract records no curse;
- accepted curse records exactly one curse;
- room 5 uses `BOSS_ACTIVE`, and `boss_defeated()` enters VICTORY without an Offer;
- DEFEAT rejects late completion and selection;
- pause/resume changes only `suspended` and revision;
- every returned context dictionary is a deep copy.

- [ ] **Step 2: Run the focused test and confirm red**

Run:

```bash
godot --headless --path . \
  --scene res://tests/unit/application/run_runtime_facade_test.tscn \
  --log-file /tmp/planewalker_wave3a_facade_red.log
```

Expected: parse failure because the facade file does not exist.

- [ ] **Step 3: Implement boot and lifecycle commands**

The facade owns fresh objects per boot:

```gdscript
func boot(manifest_path: String = DEFAULT_MANIFEST_PATH):
	_registry = ContentRegistryScript.new()
	_director = RunDirectorScript.new()
	_draft = DraftServiceScript.new()
	_orchestrator = RunOrchestratorScript.new()
	var report = _registry.load_manifest(manifest_path)
	if report.has_blocking_errors():
		return CommandResultScript.failure(&"CONTENT_NOT_AVAILABLE", 0, {"errors": report.blocking_errors})
	_director.configure_from_definitions(M1RoomPlanScript.definitions())
	var hub_result = _orchestrator.enter_hub()
	_booted = hub_result.ok
	return hub_result
```

Starting prepares room one in one command boundary:

```gdscript
func start_run(config: Dictionary, run_id: String):
	if not _booted:
		return CommandResultScript.failure(&"INVALID_PHASE", 0, {"operation": "start_run"})
	_draft.reset()
	var started = _orchestrator.start_run(config, run_id)
	if not started.ok:
		return started
	return _orchestrator.preparation_completed()
```

- [ ] **Step 4: Implement canonical room completion and selection**

Normal completion sequence:

```gdscript
func complete_current_room():
	var room := current_room_definition()
	if str(room.get("type", "")) == "boss":
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "complete_current_room"})
	var cleared = _orchestrator.room_cleared()
	if not cleared.ok:
		return cleared
	var created = _draft.create_offer(_registry, _orchestrator.state.snapshot(), room)
	if not created.ok:
		return created
	var offer: Dictionary = created.context["offer"]
	var opened = _orchestrator.open_selection(offer)
	if not opened.ok:
		return opened
	return CommandResultScript.success(opened.new_revision, {"offer": offer})
```

Atomic submit sequence:

```gdscript
func submit_selection(offer_id: String, option_id: String, revision: int):
	if _orchestrator.state.has_consumed_offer(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", _revision(), {"offer_id": offer_id})
	if _orchestrator.state.phase != RunPhaseScript.Value.SELECTION_ACTIVE:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var canonical: Dictionary = _orchestrator.state.open_offer
	if str(canonical.get("offer_id", "")) != offer_id:
		return CommandResultScript.failure(&"OFFER_CLOSED", _revision(), {"offer_id": offer_id})
	if int(canonical.get("revision", -1)) != revision:
		return CommandResultScript.failure(&"STALE_REVISION", _revision())
	var resolved = _draft.resolve_option(canonical, StringName(option_id))
	if not resolved.ok:
		return resolved
	var definition: Dictionary = resolved.context["definition"]
	var committed = _orchestrator.selection_resolved(definition)
	if not committed.ok:
		return committed
	_draft.close_offer(offer_id)
	return CommandResultScript.success(committed.new_revision, {"definition": definition, "offer_id": offer_id})
```

- [ ] **Step 5: Run facade and Wave 2 domain tests**

Run:

```bash
godot --headless --path . --scene res://tests/unit/application/run_runtime_facade_test.tscn --log-file /tmp/planewalker_wave3a_facade_green.log
godot --headless --path . --scene res://tests/unit/rewards/draft_service_test.tscn --log-file /tmp/planewalker_wave3a_draft.log
godot --headless --path . --scene res://tests/unit/dungeon/m1_room_plan_test.tscn --log-file /tmp/planewalker_wave3a_rooms.log
godot --headless --path . --scene res://tests/contract/content_schema/content_registry_test.tscn --log-file /tmp/planewalker_wave3a_registry.log
```

Expected: all exit `0`.

- [ ] **Step 6: Commit the facade**

```bash
git add scripts/application/run_runtime_facade.gd tests/unit/application/run_runtime_facade_test.gd tests/unit/application/run_runtime_facade_test.tscn
git commit -m "feat: add authoritative M1 runtime facade"
```

---

### Task 3: Bridge the real scene to ChoicePanel exactly once

**Files:**

- Create: `scripts/application/legacy_run_adapter.gd`
- Create: `tests/integration/application/legacy_run_adapter_test.gd`
- Create: `tests/integration/application/legacy_run_adapter_test.tscn`

**Interfaces:**

- Consumes: typed EventBus lifecycle signals, GameState compatibility APIs, Player `apply_reward()`, RunRuntimeFacade, ChoicePanelV2.
- Produces: a default-off scene adapter with no API dependency from UI to GameState.

- [ ] **Step 1: Write failing adapter integration tests**

Build the test scene with a fake room root containing `Player`, `RewardSelection`, `CurseSelection`, and `EventSelection` nodes. Assert:

- `enabled = false` creates no panel, removes no legacy node, and ignores lifecycle signals;
- invalid manifest keeps V2 inactive and legacy nodes intact;
- valid manifest creates one CanvasLayer and one ChoicePanel, then disables and frees the three legacy selection nodes before a run starts;
- run start plus room start enters COMBAT_ACTIVE;
- room clear opens exactly one Offer and disables Player processing;
- one valid click applies Player effects once, mirrors the correct category to GameState once, closes the panel, restores Player processing, completes transition, and emits one `reward_selected` signal;
- a duplicate click or replayed intent changes none of those counts;
- forged ID/revision/option keeps the panel open and re-enables buttons through `show_rejection()`;
- decline contract advances without adding a curse;
- Boss room clear ends the run without `reward_selected`;
- DEFEAT makes a late room-clear or selection callback inert;
- pause/resume edges update Facade suspended state without changing phase.

- [ ] **Step 2: Run the focused test and confirm red**

Run:

```bash
godot --headless --path . \
  --scene res://tests/integration/application/legacy_run_adapter_test.tscn \
  --log-file /tmp/planewalker_wave3a_adapter_red.log
```

Expected: parse failure because `legacy_run_adapter.gd` does not exist.

- [ ] **Step 3: Implement fail-safe activation**

The adapter starts disabled and activates only after a successful boot:

```gdscript
@export var enabled: bool = false
@export var room_controller_path: NodePath
@export_file("*.json") var manifest_path := "res://data/content_manifest.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not enabled:
		return
	_room_controller = get_node_or_null(room_controller_path)
	_facade = RunRuntimeFacadeScript.new()
	var booted = _facade.boot(manifest_path)
	if not booted.ok:
		return
	_create_choice_layer()
	_disable_legacy_selection_views()
	_connect_runtime_signals()
	_active = true
```

Create the UI under a dedicated CanvasLayer:

```gdscript
_choice_layer = CanvasLayer.new()
_choice_layer.layer = 20
add_child(_choice_layer)
_choice_panel = ChoicePanelScene.instantiate()
_choice_layer.add_child(_choice_panel)
_choice_panel.option_chosen.connect(_on_option_chosen)
```

- [ ] **Step 4: Implement lifecycle and category projection**

On `run_started`, boot a fresh facade and start with the existing run seed:

```gdscript
var config := {
	"schema_version": 1,
	"milestone": "M1",
	"character_id": str(run_data.get("character_id", "wanderer")),
	"weapon_id": str(run_data.get("weapon_id", "sword")),
	"enabled_time_skills": ["time_stop", "time_rewind"],
	"difficulty": str(run_data.get("difficulty", "normal")),
	"seed": int(GameState.run_seed),
}
var run_id := "m1-%d-%d" % [int(GameState.run_seed), _run_serial]
```

After `submit_selection()` succeeds:

```gdscript
var definition: Dictionary = result.context["definition"]
if str(definition.get("id", "")) != "decline_contract":
	_player.apply_reward(definition)
match str(definition.get("category", "")):
	"item": GameState.add_run_reward(definition)
	"blessing": GameState.add_run_blessing(definition)
	"curse": GameState.add_run_curse(definition)
	"talent": GameState.add_run_talent(definition)
_choice_panel.close_panel()
_set_selection_safety(false)
var transitioned = _facade.complete_transition()
if transitioned.ok:
	EventBus.reward_selected.emit(definition)
```

Do not call `player.apply_curse()`: it writes GameState and publishes a second event.

- [ ] **Step 5: Implement selection safety and terminal guards**

Selection safety stores and restores the Player process mode and clears hostile transient nodes:

```gdscript
func _set_selection_safety(active: bool) -> void:
	if active:
		_player_process_mode = _player.process_mode
		_player.process_mode = Node.PROCESS_MODE_DISABLED
		for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
			if node != _player and not node.is_in_group("enemies"):
				node.queue_free()
		for node: Node in get_tree().get_nodes_in_group("boss_hazards"):
			node.queue_free()
		GameState.set_phase(GameState.GamePhase.SELECTION)
	else:
		_player.process_mode = _player_process_mode
```

Every lifecycle callback begins with `_active`, current Facade phase, run ID, and terminal checks. The adapter observes `SceneTree.paused` edges but never changes `SceneTree.paused` itself.

- [ ] **Step 6: Run adapter, ChoicePanel, and legacy smoke tests**

Run:

```bash
godot --headless --path . --scene res://tests/integration/application/legacy_run_adapter_test.tscn --log-file /tmp/planewalker_wave3a_adapter_green.log
godot --headless --path . --scene res://tests/ui/choice_panel_v2_scene_test.tscn --log-file /tmp/planewalker_wave3a_choice.log
godot --headless --path . --scene res://tests/reward_system_smoke.tscn --log-file /tmp/planewalker_wave3a_legacy_smoke.log
```

Expected: all exit `0`; the legacy smoke may retain its pre-existing ObjectDB leak warning.

- [ ] **Step 7: Commit the adapter**

```bash
git add scripts/application/legacy_run_adapter.gd tests/integration/application/legacy_run_adapter_test.gd tests/integration/application/legacy_run_adapter_test.tscn
git commit -m "feat: bridge M1 runtime to unified choices"
```

---

### Task 4: Enable the adapter in the clean main scene

**Files:**

- Modify: `scenes/main.tscn`
- Create: `tests/smoke/m1_runtime_smoke_test.gd`
- Create: `tests/smoke/m1_runtime_smoke_test.tscn`

**Interfaces:**

- Consumes: `LegacyRunAdapter.enabled`, `room_controller_path`, and the existing Main scene node names.
- Produces: the real M1 room order and fixed-seed five-room runtime smoke.

- [ ] **Step 1: Write the failing main-scene smoke**

The smoke instantiates `scenes/main.tscn`, starts a fixed-seed run, and drives room lifecycle facts without waiting for combat AI. Assert:

- `RuntimeV2Adapter` exists and is active;
- main scene room overrides are `event_rooms = []`, `elite_rooms = [4]`, `curse_offer_rooms = []`;
- legacy selection nodes are removed only after adapter boot;
- rooms 1–4 open starter, reinforcement, talent, and contract Offers;
- one option is submitted in each room and exactly four compatibility `reward_selected` facts occur;
- room 5 enters BOSS_ACTIVE and ends in VICTORY with zero Boss Offer;
- final authoritative snapshot has current room 5, four consumed Offer IDs, and a non-empty Build;
- GameState and Facade agree on selected item/blessing-or-item/talent/curse counts;
- the test exits with no new pending-signal or ObjectDB leak warning from V2 nodes.

- [ ] **Step 2: Run the smoke and confirm red**

Run:

```bash
godot --headless --path . \
  --scene res://tests/smoke/m1_runtime_smoke_test.tscn \
  --log-file /tmp/planewalker_wave3a_m1_smoke_red.log
```

Expected: failure because Main has no RuntimeV2Adapter.

- [ ] **Step 3: Add the minimal main-scene cutover**

Add one ext_resource and one node:

```ini
[ext_resource type="Script" path="res://scripts/application/legacy_run_adapter.gd" id="5_runtime_adapter"]

[node name="RuntimeV2Adapter" type="Node" parent="."]
process_mode = 3
script = ExtResource("5_runtime_adapter")
enabled = true
room_controller_path = NodePath("../CombatRoom01")
```

Override only the instantiated room configuration:

```ini
[node name="CombatRoom01" parent="." instance=ExtResource("2_combat_room")]
auto_start = false
event_rooms = Array[int]([])
elite_rooms = Array[int]([4])
curse_offer_rooms = Array[int]([])
```

Do not edit `combat_room_01.tscn`, so direct legacy smoke loading remains unchanged.

- [ ] **Step 4: Run the real-scene and full regression gates**

Run:

```bash
godot --headless --editor --path . --quit --log-file /tmp/planewalker_wave3a_import.log
godot --headless --path . --scene res://tests/smoke/m1_runtime_smoke_test.tscn --log-file /tmp/planewalker_wave3a_m1_smoke_green.log
godot --headless --path . --scene res://tests/unit/application/run_runtime_facade_test.tscn --log-file /tmp/planewalker_wave3a_facade_final.log
godot --headless --path . --scene res://tests/integration/application/legacy_run_adapter_test.tscn --log-file /tmp/planewalker_wave3a_adapter_final.log
godot --headless --path . --scene res://tests/ui/choice_panel_v2_scene_test.tscn --log-file /tmp/planewalker_wave3a_choice_final.log
godot --headless --path . --scene res://tests/reward_system_smoke.tscn --log-file /tmp/planewalker_wave3a_legacy_final.log
```

Then run every repository test scene discovered by:

```bash
rg --files tests | rg '_test\.tscn$|smoke\.tscn$' | sort
```

Expected: every scene exits `0`.

- [ ] **Step 5: Verify workspace isolation**

Run:

```bash
git diff --check
git status --short
```

Only `scenes/main.tscn` may be changed from the pre-existing clean files. The user's content JSON, localization, project settings, main script, RoomController, legacy UI, reward pools, and legacy smoke source must remain untouched.

- [ ] **Step 6: Commit scene cutover and smoke**

```bash
git add scenes/main.tscn tests/smoke/m1_runtime_smoke_test.gd tests/smoke/m1_runtime_smoke_test.tscn
git commit -m "feat: enable authoritative M1 runtime"
```

---

## Completion Gate

Wave 3A is complete when:

- the main scene uses the exact M1 five-room sequence;
- ContentRegistry and DraftService boot through one runtime facade;
- rooms 1–4 display the unified ChoicePanel and room 5 displays no reward;
- RunState Build writeback feeds owned-ID and dominant-archetype drafting;
- UI cannot apply a definition before command success;
- one Offer cannot apply twice under double click, replay, forged payload, stale revision, late callback, pause, death, or terminal state;
- selection disables Player processing and removes hostile transient hazards;
- manifest failure safely preserves the legacy selection path;
- the user's dirty files remain unmodified by Wave 3A;
- all repository tests exit `0`.

## Deferred to Wave 3B

- PlayerActionState integration with PlayerController and SwordWeapon.
- One frame clock for windup, active, recovery, cancel, dash, and time cast.
- Rewind safe-action hooks on PlayerController.
- Real RunViewState projection into CombatHudV2 and localization of its remaining labels.
- Enemy melee telegraphs and recovery windows.
- Elite time-stop resistance.
- Boss action mutual exclusion and resisted-time-stop correction.
- Pixel-perfect 640×360 main-scene cutover and integer scaling.
