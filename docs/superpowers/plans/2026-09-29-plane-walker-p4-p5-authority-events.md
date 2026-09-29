# Plane Walker P4/P5 Authority and Event Publication Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: P4/P5 runtime authority and event-publication execution plan
- Applies To: RunState ownership, RoomRuntime lifecycle, RunRuntimeHost cutover, legacy mirror retirement, and typed exactly-once gameplay facts
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Exit Gate: RunOrchestrator and RoomRuntime are the sole run/room writers, legacy mirrors and generic EventBus paths are retired, exactly-once facts pass focused tests, and `./tools/validate_project.sh` passes

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven development, TDD, focused reviews, and the repository validation entrypoint. Each task is an independently reviewable commit; do not combine tasks or stage unrelated shared-worktree changes.

**Goal:** Make `RunOrchestrator` the sole writer of one authoritative `RunState`, make `RoomRuntime` the sole room-lifecycle coordinator, retire `GameState` run mirrors and `LegacyRunAdapter`, and publish every gameplay fact exactly once through typed signals without breaking the five-room M1 runtime.

**Architecture:** Commands flow from `Main` and UI into `RunRuntimeHost`, then into `RunRuntimeFacade`, `RoomRuntime`, and `RunOrchestrator`. `RunOrchestrator` owns the only mutable `RunState`; all other systems receive deep-copied snapshots. `RoomRuntime` owns room entry, encounter completion, room clear, player death, and runtime failure coordination while `RoomController` performs scene-node spawning and cleanup. `EventBus` becomes an outbound observation boundary only: successful commands publish typed facts once, and subscribers never advance domain state.

**Tech Stack:** Godot 4.6.1, GDScript 2.0, native typed signals, existing `CommandResult`, `RunState`, `RunOrchestrator`, `RunRuntimeFacade`, `EncounterRunner`, `ContentRegistry`, `DraftService`, serial headless scene tests, and `./tools/validate_project.sh`.

## Global Constraints

- Preserve the canonical five-room M1 plan, encounter seed determinism, selection idempotency, build writeback, Boss victory path, player-death path, pause overlay, telemetry, Pixel Proxy, combat feedback, and localization behavior.
- `RunOrchestrator` is the only production code allowed to change run phase or revision after initial object construction.
- Runtime systems may read only deep-copied snapshots; they must not retain a mutable `RunState` reference.
- `RoomRuntime` may submit commands to `RunRuntimeFacade`; `RoomController`, UI, presentation, and EventBus subscribers may not submit phase transitions indirectly.
- Gameplay facts are emitted only after a successful authoritative command. Rejected, stale, duplicate, failed, and terminal commands emit no gameplay fact.
- Gameplay event payloads must not expose mutable authoritative objects.
- Preserve `GameState` setting APIs until SaveService composition replaces them; remove only its run-domain fields and methods in this plan.
- Do not retain `allow_legacy_runtime`, adapter fallback, hidden dual-write, or generic string-event compatibility after Task 7.
- Every task starts with a failing focused test, ends with focused green tests, scans logs, and creates one precise commit.
- Never use `git add .`; stage only the files listed in that task.
- Keep the working tree recoverable. If a command may have partially written generated artifacts, inspect `git status --short` before proceeding.
- The final repository gate must report no new script error, invalid call, missing resource, ObjectDB leak, or RID leak.

## Current Baseline and Failure Inventory

The implementation begins from the following known baseline:

- `RunOrchestrator.state` is publicly reachable and mutable.
- `RunState.reset()` writes phase independently of `RunOrchestrator`.
- `GameState` mirrors phase, floor, room, seed, timer, current run, terminal result, and build state.
- `Main`, `RoomController`, `LegacyRunAdapter`, and three legacy selection views write run phase or room progression.
- `scenes/main.tscn` enables `RuntimeV2Adapter`.
- `scenes/rooms/combat_room_01.tscn` embeds legacy HUD, reward, curse, and event views and defaults `allow_legacy_runtime` to true.
- Production code contains 30 typed EventBus emissions, 29 generic `EventBus.publish()` calls, 31 typed connections, and no generic `subscribe()` consumer.
- `tests/smoke/m1_runtime_smoke_test.gd`, `tests/contract/presentation/pixel_canvas_test.gd`, and `tests/integration/application/legacy_run_adapter_test.gd` explicitly depend on the adapter.

## Frozen Interfaces

The seven tasks use these exact public interfaces.

### RunOrchestrator

```gdscript
func snapshot() -> Dictionary
func revision() -> int
func phase() -> int
func is_terminal() -> bool
func has_consumed_offer(offer_id: String) -> bool
```

`RunOrchestrator` stores the authoritative object in `var _state: RefCounted`. No public `state` property remains.

### RunState snapshot additions

```gdscript
{
	"schema_version": 1,
	"run_id": String,
	"revision": int,
	"phase": int,
	"suspended": bool,
	"run_seed": int,
	"current_floor": int,
	"current_room": int,
	"room_total": int,
	"run_time_ms": int,
	"resources": Dictionary,
	"stats": Dictionary,
	"events": Array,
	"build": Dictionary,
	"open_offer": Dictionary,
	"consumed_offer_ids": Array,
	"result": Dictionary,
	"config": Dictionary,
}
```

### RoomRuntime

```gdscript
signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
signal spawn_requested(spawn_definition: Dictionary)
signal room_started(room_id: StringName, revision: int)
signal room_cleared(room_id: StringName, revision: int)
signal runtime_failed(context: Dictionary)

func configure(
	facade: RefCounted,
	encounter_catalog: RefCounted,
	room_definitions: Array[Dictionary],
	run_seed: int,
	encounter_runner: Node
)
func begin_current_room() -> Variant
func register_spawned(entity: Node, spawn_definition: Dictionary = {}) -> bool
func reject_spawn(spawn_definition: Dictionary, reason: StringName) -> bool
func report_player_died(killer: Variant = null) -> Variant
func snapshot() -> Dictionary
```

### RunRuntimeHost

```gdscript
func start_run(config: Dictionary) -> Variant
func pause_run() -> Variant
func resume_run() -> Variant
func runtime_snapshot() -> Dictionary
func room_plan() -> Array[Dictionary]
func encounter_catalog() -> RefCounted
```

### Lifecycle EventBus signals

```gdscript
signal run_started(run_id: String, snapshot: Dictionary)
signal room_started(run_id: String, room_id: StringName, revision: int)
signal room_cleared(run_id: String, room_id: StringName, revision: int)
signal reward_selected(run_id: String, definition: Dictionary, revision: int)
signal run_ended(run_id: String, result: Dictionary, revision: int)
```

### Combat EventBus signals that require context

```gdscript
signal player_dashed(context: Dictionary)
signal player_attacked(weapon_id: StringName, context: Dictionary)
signal enemy_spawned(enemy: Node, context: Dictionary)
signal time_skill_started(skill_id: StringName, context: Dictionary)
signal time_skill_ended(skill_id: StringName, context: Dictionary)
```

Existing damage and death signal argument order remains unchanged.

---

### Task 1: Encapsulate the Authoritative RunState

**Files:**

- Modify: `scripts/application/run_state.gd`
- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `tests/unit/application/run_state_test.gd`
- Modify: `tests/unit/application/run_orchestrator_test.gd`
- Modify: `tests/unit/application/run_runtime_facade_test.gd`
- Create: `tests/contract/application/run_state_snapshot_contract_test.gd`
- Create: `tests/contract/application/run_state_snapshot_contract_test.tscn`

**Interfaces:**

- Consumes: existing RunConfig validation, CommandResult codes, RunBuildState behavior, SelectionOffer validation, and existing phase enum values.
- Produces: private `_state`, deep-copied `snapshot()`, query methods frozen above, and snapshot fields for floor/resources/stats/events.

- [ ] **Step 1: Write the failing snapshot and ownership contract**

Create the contract scene and cover these exact behaviors:

```gdscript
extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = TestSuiteScript.new()
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(), "authority-contract")
	var first := orchestrator.snapshot()
	first["phase"] = 999
	first["resources"]["chronos_shards"] = 999
	first["stats"]["kills"] = 999
	first["events"].append({"id": "forged"})
	first["build"]["items"].append("forged")
	var second := orchestrator.snapshot()
	suite.assert_true(not "state" in orchestrator, "orchestrator exposes no mutable state property")
	suite.assert_true(second["phase"] != 999, "snapshot phase is isolated")
	suite.assert_equal(second["resources"], {}, "snapshot resources are isolated")
	suite.assert_equal(second["stats"], {"kills": 0}, "snapshot stats are isolated")
	suite.assert_equal(second["events"], [], "snapshot events are isolated")
	suite.assert_equal(second["build"]["items"], [], "snapshot build is isolated")
	suite.finish(get_tree())

func _config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": 123,
	}
```

- [ ] **Step 2: Run the test and confirm the red state**

```bash
./tools/run_tests.sh --filter run_state_snapshot_contract
```

Expected: FAIL because `state` is public and the new snapshot fields/query methods do not exist.

- [ ] **Step 3: Add the authoritative fields and remove phase mutation from reset**

In `RunState`, add `current_floor`, `resources`, `stats`, and `events`. Rename reset to `reset_domain()` and reset all run data except phase and revision. The initial declaration may remain `BOOT`; after construction, only RunOrchestrator assigns phase.

```gdscript
func reset_domain(p_config: Dictionary, p_run_id: String) -> void:
	config = RunConfigScript.normalized(p_config)
	run_id = p_run_id
	suspended = false
	run_seed = int(config["seed"])
	current_floor = 1
	current_room = 0
	room_total = 5
	run_time_ms = 0
	resources = {}
	stats = {"kills": 0}
	events = []
	build_state.reset()
	open_offer = {}
	consumed_offer_ids = {}
	result = {}
```

- [ ] **Step 4: Encapsulate `_state` and migrate Facade reads to snapshots**

Add the frozen query methods. `RunRuntimeFacade` must use `snapshot()` for every validation and lookup instead of `_orchestrator.state`. Do not cache a snapshot across a successful command.

```gdscript
func snapshot() -> Dictionary:
	return _state.snapshot().duplicate(true)

func revision() -> int:
	return _state.revision

func phase() -> int:
	return _state.phase

func is_terminal() -> bool:
	return _state.is_terminal()

func has_consumed_offer(offer_id: String) -> bool:
	return _state.has_consumed_offer(offer_id)
```

- [ ] **Step 5: Update existing tests to use snapshots and queries**

Replace direct `orchestrator.state` assertions with one freshly acquired snapshot per assertion group. Preserve every legal, invalid, stale, duplicate, terminal, and pause assertion.

- [ ] **Step 6: Run focused tests and scan the phase writers**

```bash
./tools/run_tests.sh --filter run_state
./tools/run_tests.sh --filter run_orchestrator
./tools/run_tests.sh --filter run_runtime_facade
rg -n '\.phase\s*=' scripts/application
```

Expected: all focused tests PASS; after initial RunState declaration, production phase assignment appears only in `run_orchestrator.gd`.

- [ ] **Step 7: Commit the authority boundary**

```bash
git add -- scripts/application/run_state.gd scripts/application/run_orchestrator.gd scripts/application/run_runtime_facade.gd tests/unit/application/run_state_test.gd tests/unit/application/run_orchestrator_test.gd tests/unit/application/run_runtime_facade_test.gd tests/contract/application/run_state_snapshot_contract_test.gd tests/contract/application/run_state_snapshot_contract_test.tscn
git diff --cached --check
git commit -m "refactor(runtime): encapsulate authoritative run state"
```

---

### Task 2: Add RoomRuntime as the Room-Lifecycle Authority

**Files:**

- Create: `scripts/dungeon/room_runtime.gd`
- Create: `tests/unit/dungeon/room_runtime_test.gd`
- Create: `tests/unit/dungeon/room_runtime_test.tscn`
- Modify: `scripts/dungeon/room_controller.gd`
- Modify: `scripts/dungeon/encounter_runner.gd`
- Modify: `scripts/dungeon/run_director.gd`
- Modify: `scripts/application/run_runtime_facade.gd`

**Interfaces:**

- Consumes: RunRuntimeFacade commands, authoritative room plan, EncounterCatalog, EncounterRunner signals, and RoomController spawn acknowledgements.
- Produces: the frozen RoomRuntime API and signals; RoomController becomes a node-operation adapter with no phase, room, or terminal writes.

- [ ] **Step 1: Write the failing RoomRuntime state-machine test**

The test must use a facade spy with call counters and cover:

```gdscript
func _test_room_clear_is_idempotent(suite) -> void:
	var runtime = RoomRuntimeScript.new()
	var facade = FacadeSpy.new()
	var runner = EncounterRunnerScript.new()
	add_child(runner)
	runtime.configure(facade, CatalogSpy.new(), _room_definitions(), 123, runner)
	suite.assert_true(runtime.begin_current_room().ok, "room begins through facade")
	runner.encounter_completed.emit(&"combat_intro")
	runner.encounter_completed.emit(&"combat_intro")
	suite.assert_equal(facade.complete_room_calls, 1, "duplicate completion submits one command")
	runtime.free()
	runner.free()
```

Add cases for event room, Boss room, late summon, rejected spawn, player death, runtime failure, duplicate clear, and terminal rejection.

- [ ] **Step 2: Run the test and confirm the red state**

```bash
./tools/run_tests.sh --filter room_runtime
```

Expected: FAIL because `room_runtime.gd` does not exist.

- [ ] **Step 3: Implement RoomRuntime with explicit state**

RoomRuntime owns these internal fields and never reads GameState:

```gdscript
var _facade: RefCounted
var _catalog: RefCounted
var _definitions: Array[Dictionary] = []
var _run_seed: int = 0
var _runner: Node
var _room_active: bool = false
var _room_terminal: bool = false
var _failure: Dictionary = {}
```

`begin_current_room()` obtains `facade.current_room_definition()`, calls `facade.enter_current_room()`, emits `room_started` only on success, and starts the authoritative encounter. Completion calls `complete_current_room()` for non-Boss rooms and `boss_defeated()` for Boss rooms exactly once.

- [ ] **Step 4: Reduce RoomController to scene operations**

RoomController retains spawn points, warning visuals, scene instantiation, entity cleanup, and player lookup. Move room numbering, phase transitions, terminal decisions, clear idempotency, and authored-runtime failure policy into RoomRuntime. Route successful spawn acknowledgements back through `RoomRuntime.register_spawned()`.

- [ ] **Step 5: Run focused encounter and room tests**

```bash
./tools/run_tests.sh --filter room_runtime
./tools/run_tests.sh --filter encounter_runner
./tools/run_tests.sh --filter encounter_catalog
rg -n 'GameState\.(phase|current_room|set_phase|end_run|fail_run)' scripts/dungeon/room_controller.gd scripts/dungeon/encounter_runner.gd scripts/dungeon/room_runtime.gd
```

Expected: tests PASS; the final `rg` returns no result.

- [ ] **Step 6: Commit RoomRuntime separately**

```bash
git add -- scripts/dungeon/room_runtime.gd scripts/dungeon/room_controller.gd scripts/dungeon/encounter_runner.gd scripts/dungeon/run_director.gd scripts/application/run_runtime_facade.gd tests/unit/dungeon/room_runtime_test.gd tests/unit/dungeon/room_runtime_test.tscn
git diff --cached --check
git commit -m "feat(runtime): add authoritative room runtime"
```

---

### Task 3: Replace LegacyRunAdapter with RunRuntimeHost

**Files:**

- Create: `scripts/application/run_runtime_host.gd`
- Create: `tests/integration/application/run_runtime_host_test.gd`
- Create: `tests/integration/application/run_runtime_host_test.tscn`
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`
- Modify: `scenes/rooms/combat_room_01.tscn`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `tests/smoke/m1_runtime_smoke_test.gd`
- Modify: `tests/contract/presentation/pixel_canvas_test.gd`

**Interfaces:**

- Consumes: RunRuntimeFacade, RoomRuntime, CombatHudV2, ChoicePanelV2, Player reward application, pause intents, and the existing main scene.
- Produces: the frozen RunRuntimeHost API; the main scene contains exactly one runtime owner and no enabled adapter.

- [ ] **Step 1: Write the failing host integration test**

Assert that one start intent produces one run and that the host owns the shared plan/catalog:

```gdscript
func _test_main_uses_one_runtime_host(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var host := main.get_node_or_null("RunRuntimeHost")
	suite.assert_true(host != null, "main provides RunRuntimeHost")
	suite.assert_true(main.get_node_or_null("RuntimeV2Adapter") == null, "main has no legacy adapter node")
	var started = host.start_run(_config())
	suite.assert_true(started.ok, "host starts one run")
	var snapshot: Dictionary = host.runtime_snapshot()
	suite.assert_true(not str(snapshot["run_id"]).is_empty(), "host exposes authoritative run id")
	suite.assert_equal(host.room_plan().size(), 5, "host owns the five-room plan")
	main.queue_free()
```

- [ ] **Step 2: Run the test and confirm the red state**

```bash
./tools/run_tests.sh --filter run_runtime_host
```

Expected: FAIL because the host and node do not exist.

- [ ] **Step 3: Implement host composition and direct intents**

`RunRuntimeHost._ready()` boots one facade, creates/configures one RoomRuntime, creates V2 HUD/choice layers, and connects RoomRuntime signals. `start_run()` generates one run ID, calls facade start, configures the authored runtime, then begins the current room. Main calls the host for start/pause/resume and reads `runtime_snapshot()` for status text.

- [ ] **Step 4: Switch the main scene without deleting adapter source yet**

Remove the `RuntimeV2Adapter` node and ext resource from `scenes/main.tscn`. Add `RunRuntimeHost` and its room-controller path. Keep `legacy_run_adapter.gd` on disk until Task 4 so the cutover remains reversible at one commit boundary.

- [ ] **Step 5: Update M1 and pixel contracts to address the host**

Replace adapter lookups with `RunRuntimeHost`. Preserve assertions for five rooms, shared EncounterCatalog, authored runtime enabled, Pixel Canvas camera, V2 HUD, and V2 choice panel.

- [ ] **Step 6: Run host, M1, and presentation gates**

```bash
./tools/run_tests.sh --filter run_runtime_host
./tools/run_tests.sh --filter m1_runtime_smoke
./tools/run_tests.sh --filter pixel_canvas
```

Expected: all PASS; M1 completes five rooms without `allow_legacy_runtime_fallback`.

- [ ] **Step 7: Commit the host cutover**

```bash
git add -- scripts/application/run_runtime_host.gd scenes/main.tscn scripts/main.gd scenes/rooms/combat_room_01.tscn scripts/application/run_runtime_facade.gd tests/integration/application/run_runtime_host_test.gd tests/integration/application/run_runtime_host_test.tscn tests/smoke/m1_runtime_smoke_test.gd tests/contract/presentation/pixel_canvas_test.gd
git diff --cached --check
git commit -m "refactor(runtime): replace legacy adapter host"
```

---

### Task 4: Retire GameState Run Mirrors and Legacy Runtime UI

**Files:**

- Delete: `scripts/application/legacy_run_adapter.gd`
- Delete: `tests/integration/application/legacy_run_adapter_test.gd`
- Delete: `tests/integration/application/legacy_run_adapter_test.tscn`
- Delete: `scripts/ui/reward_selection.gd`
- Delete: `scripts/ui/curse_selection.gd`
- Delete: `scripts/ui/event_selection.gd`
- Delete: `scripts/ui/combat_hud.gd`
- Modify: `autoload/game_state.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/dungeon/room_controller.gd`
- Modify: `scenes/rooms/combat_room_01.tscn`
- Modify: `tests/reward_system_smoke.gd`
- Modify: `tests/smoke/m1_runtime_smoke_test.gd`
- Modify: `tests/contract/presentation/pixel_canvas_test.gd`
- Create: `tests/contract/application/run_authority_contract_test.gd`
- Create: `tests/contract/application/run_authority_contract_test.tscn`

**Interfaces:**

- Consumes: Task 3 RunRuntimeHost and V2 UI, RunState snapshot, Player.apply_reward, and retained GameState setting methods.
- Produces: zero GameState run fields/methods, zero legacy nodes/scripts, and a source contract that prevents reintroduction.

- [ ] **Step 1: Write the failing source-authority contract**

The test reads production files and rejects exact forbidden patterns:

```gdscript
const FORBIDDEN := [
	"GameState.phase",
	"GameState.current_floor",
	"GameState.current_room",
	"GameState.run_seed",
	"GameState.run_timer",
	"GameState.current_run",
	"GameState.build_state",
	"GameState.set_phase",
	"GameState.start_run",
	"GameState.end_run",
	"GameState.fail_run",
	"LegacyRunAdapter",
	"allow_legacy_runtime = true",
]
```

Scan `autoload/`, `scripts/`, and production scenes, excluding test files and historical documentation. Report the exact path and forbidden token in each assertion label.

- [ ] **Step 2: Run the contract and confirm the red state**

```bash
./tools/run_tests.sh --filter run_authority_contract
```

Expected: FAIL with matches in GameState, Main, RoomController, PlayerController, legacy UI, adapter, and room scene.

- [ ] **Step 3: Reduce GameState to settings/profile compatibility**

Retain only `setting_changed`, `save_path`, `persistent`, `set_setting`, `get_setting`, `load_persistent`, `save_persistent`, `reset_persistent_data`, default-setting merge, and profile-summary helpers still required before SaveService composition. Remove every live-run field and mutation method.

- [ ] **Step 4: Remove mirror writeback and legacy scene nodes**

Player reward application changes Player components only. Run build history is already committed by RunOrchestrator. Remove legacy selection and HUD ext resources/nodes from `combat_room_01.tscn`, remove `allow_legacy_runtime`, and keep only CombatHudV2/ChoicePanelV2 created by the host.

- [ ] **Step 5: Migrate legacy smoke assertions to snapshots**

Replace GameState phase/room/build assertions in `reward_system_smoke.gd` with host/facade snapshots. Preserve direct combat, reward-effect, pause/settings, event-room, elite-room, Boss, death, and localization coverage.

- [ ] **Step 6: Run authority and M1 regression gates**

```bash
./tools/run_tests.sh --filter run_authority_contract
./tools/run_tests.sh --filter reward_system_smoke
./tools/run_tests.sh --filter m1_runtime_smoke
./tools/run_tests.sh --filter pixel_canvas
```

Expected: all PASS; the authority scan has zero forbidden matches.

- [ ] **Step 7: Commit mirror retirement precisely**

```bash
git add -- autoload/game_state.gd scripts/application/legacy_run_adapter.gd tests/integration/application/legacy_run_adapter_test.gd tests/integration/application/legacy_run_adapter_test.tscn scripts/ui/reward_selection.gd scripts/ui/curse_selection.gd scripts/ui/event_selection.gd scripts/ui/combat_hud.gd scripts/main.gd scripts/player/player_controller.gd scripts/dungeon/room_controller.gd scenes/rooms/combat_room_01.tscn tests/reward_system_smoke.gd tests/smoke/m1_runtime_smoke_test.gd tests/contract/presentation/pixel_canvas_test.gd tests/contract/application/run_authority_contract_test.gd tests/contract/application/run_authority_contract_test.tscn
git diff --cached --check
git commit -m "refactor(runtime): retire mirrored run state"
```

---

### Task 5: Publish Run-Lifecycle Facts Exactly Once

**Files:**

- Modify: `autoload/event_bus.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `scripts/dungeon/room_runtime.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/ui/run_end_overlay.gd`
- Modify: `autoload/combat_feedback.gd`
- Create: `tests/contract/events/run_lifecycle_publication_test.gd`
- Create: `tests/contract/events/run_lifecycle_publication_test.tscn`

**Interfaces:**

- Consumes: successful CommandResult transitions and the frozen lifecycle signal signatures.
- Produces: one lifecycle fact per successful command; state-changing systems use direct commands rather than EventBus subscriptions.

- [ ] **Step 1: Write the failing publication-count contract**

Use a recorder with one method per typed signal. Drive a full five-room run and assert:

```gdscript
suite.assert_equal(recorder.run_started_count, 1, "run starts once")
suite.assert_equal(recorder.room_started_count, 5, "five rooms start once each")
suite.assert_equal(recorder.room_cleared_ids.size(), 5, "five rooms clear once each")
suite.assert_equal(recorder.reward_selected_count, 4, "four successful offers publish once")
suite.assert_equal(recorder.run_ended_count, 1, "run ends once")
suite.assert_equal(recorder.duplicate_event_ids(), [], "lifecycle event ids are unique")
```

Add rejected stale selection, duplicate room clear, duplicate terminal command, and failed start cases; their counters must remain unchanged.

- [ ] **Step 2: Run the test and confirm the red state**

```bash
./tools/run_tests.sh --filter run_lifecycle_publication
```

Expected: FAIL because current lifecycle signatures differ and old code pairs typed emit with generic publish.

- [ ] **Step 3: Freeze lifecycle signatures and publishers**

Update EventBus to the frozen typed lifecycle signatures. RunRuntimeHost publishes `run_started`, `room_started`, `room_cleared`, `reward_selected`, and `run_ended` after successful authoritative commands. Event payload dictionaries are deep copies before emission.

- [ ] **Step 4: Convert consumers to the new signatures**

Main, RunEndOverlay, and CombatFeedback accept run ID/revision arguments and remain read-only. RunRuntimeHost and RoomRuntime do not subscribe to lifecycle EventBus signals for domain transitions.

- [ ] **Step 5: Run lifecycle and M1 tests**

```bash
./tools/run_tests.sh --filter run_lifecycle_publication
./tools/run_tests.sh --filter run_runtime_host
./tools/run_tests.sh --filter m1_runtime_smoke
```

Expected: all PASS; rejected commands add no facts.

- [ ] **Step 6: Commit lifecycle publication separately**

```bash
git add -- autoload/event_bus.gd scripts/application/run_runtime_host.gd scripts/application/run_orchestrator.gd scripts/dungeon/room_runtime.gd scripts/main.gd scripts/ui/run_end_overlay.gd autoload/combat_feedback.gd tests/contract/events/run_lifecycle_publication_test.gd tests/contract/events/run_lifecycle_publication_test.tscn
git diff --cached --check
git commit -m "refactor(events): publish lifecycle facts once"
```

---

### Task 6: Publish Combat, Spawn, and Time Facts Exactly Once

**Files:**

- Modify: `autoload/event_bus.gd`
- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/combat/sword_weapon.gd`
- Modify: `scripts/combat/bow_weapon.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/time_rift.gd`
- Modify: `scripts/dungeon/room_controller.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Modify: `scripts/dungeon/encounter_runner.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/ui/floating_text_layer.gd`
- Create: `tests/contract/events/combat_event_publication_test.gd`
- Create: `tests/contract/events/combat_event_publication_test.tscn`

**Interfaces:**

- Consumes: existing damage/death signals and frozen context-bearing combat/time signals.
- Produces: exactly one typed fact for each committed attack, dash, spawn, damage application, death, curse selection, and time-skill lifecycle transition.

- [ ] **Step 1: Write the failing combat publication contract**

Cover exact counts and rejection behavior:

```gdscript
suite.assert_equal(recorder.damage_about_count, 1, "one hit announces one pending damage")
suite.assert_equal(recorder.damage_applied_count, 1, "one hit applies damage once")
suite.assert_equal(recorder.hit_confirmed_count, 1, "one hit confirms once")
suite.assert_equal(recorder.entity_died_count, 1, "lethal hit publishes one death")
suite.assert_equal(recorder.spawned_instance_ids.size(), _unique_count(recorder.spawned_instance_ids), "each entity spawns once")
suite.assert_equal(recorder.time_started[&"time_stop"], 1, "successful Time Stop starts once")
suite.assert_equal(recorder.time_ended[&"time_stop"], 1, "successful Time Stop ends once")
suite.assert_equal(recorder.rejected_skill_events, 0, "rejected skills publish nothing")

func _unique_count(values: Array[int]) -> int:
	var seen: Dictionary = {}
	for value: int in values:
		seen[value] = true
	return seen.size()
```

Use the exact dictionary-backed helper above for duplicate-ID checks.

- [ ] **Step 2: Run the test and confirm the red state**

```bash
./tools/run_tests.sh --filter combat_event_publication
```

Expected: FAIL because context-bearing signatures do not exist and generic publish calls remain.

- [ ] **Step 3: Extend typed signal context without changing gameplay decisions**

Use these context contents:

```gdscript
player_attacked.emit(&"sword", {})
player_attacked.emit(&"bow", {"charge": charge_ratio})
player_dashed.emit({})
enemy_spawned.emit(enemy, {"boss": is_boss, "summoned": is_summoned})
time_skill_started.emit(skill_id, {"position": position_value})
time_skill_ended.emit(skill_id, {})
```

Omit keys that do not apply instead of inventing null sentinel values.

- [ ] **Step 4: Remove paired generic publication from all listed producers**

Keep one typed emit at the current successful commit point. Do not move attack events to input-press time, death events before HealthComponent terminal state, spawn events before EncounterRunner acknowledgement, or time end events before the effect actually terminates.

- [ ] **Step 5: Update read-only consumers and run focused tests**

```bash
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter encounter_runner
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter time_stop
./tools/run_tests.sh --filter combat_feedback_runtime
```

Expected: all PASS; each entity instance ID is registered once and each time lifecycle remains paired.

- [ ] **Step 6: Commit combat publication separately**

```bash
git add -- autoload/event_bus.gd scripts/combat/health_component.gd scripts/combat/sword_weapon.gd scripts/combat/bow_weapon.gd scripts/player/player_controller.gd scripts/time_system/time_manager.gd scripts/time_system/time_rift.gd scripts/dungeon/room_controller.gd scripts/enemies/boss_chrono_warden.gd scripts/dungeon/encounter_runner.gd autoload/combat_feedback.gd scripts/ui/floating_text_layer.gd tests/contract/events/combat_event_publication_test.gd tests/contract/events/combat_event_publication_test.tscn
git diff --cached --check
git commit -m "refactor(events): publish combat facts once"
```

---

### Task 7: Remove Generic EventBus and Certify P4/P5

**Files:**

- Modify: `autoload/event_bus.gd`
- Modify: `tools/validate_project.sh`
- Modify: `tools/test_ci_contract.sh`
- Modify: `tests/smoke/m1_runtime_smoke_test.gd`
- Modify: `tests/reward_system_smoke.gd`
- Create: `tests/contract/events/event_bus_source_contract_test.gd`
- Create: `tests/contract/events/event_bus_source_contract_test.tscn`

**Interfaces:**

- Consumes: Tasks 4–6 authority and typed-signal contracts.
- Produces: EventBus containing signals only, zero generic publication API, a repository source gate, and final P4/P5 evidence through existing validation logs.

- [ ] **Step 1: Write the failing EventBus source contract**

Scan `autoload/` and `scripts/` for these forbidden tokens:

```gdscript
const FORBIDDEN := [
	"EventBus.publish(",
	"EventBus.publish_deferred(",
	"EventBus.subscribe(",
	"EventBus.unsubscribe(",
	"var _handlers",
	"var _deferred_events",
	"func publish(",
	"func publish_deferred(",
	"func subscribe(",
	"func unsubscribe(",
]
```

Also scan for state-changing EventBus consumers. The following production files must contain no `EventBus.*.connect` call after Task 4:

```text
scripts/application/run_orchestrator.gd
scripts/application/run_runtime_facade.gd
scripts/application/run_runtime_host.gd
scripts/dungeon/room_runtime.gd
```

- [ ] **Step 2: Run the source test and confirm the red state**

```bash
./tools/run_tests.sh --filter event_bus_source_contract
```

Expected: FAIL on the generic compatibility definitions in `autoload/event_bus.gd`.

- [ ] **Step 3: Delete the generic compatibility implementation**

Remove StringName event constants, `_handlers`, `_deferred_events`, `subscribe`, `unsubscribe`, `publish`, `publish_deferred`, and EventBus `_process()`. EventBus retains only the typed signal declarations used by Tasks 5 and 6.

- [ ] **Step 4: Add source-contract execution to project validation**

The scene is already auto-discovered by `run_tests.sh`. Extend `test_ci_contract.sh` to assert that the validation entrypoint still runs all discovered scene tests and that no skip/filter excludes event contracts. Do not create a separate partial validation path.

- [ ] **Step 5: Run static zero-result checks**

```bash
rg -n 'EventBus\.(publish|publish_deferred|subscribe|unsubscribe)' autoload scripts
rg -n '_handlers|_deferred_events' autoload/event_bus.gd
rg -n 'GameState\.(phase|current_floor|current_room|run_seed|run_timer|current_run|build_state|set_phase|start_run|end_run|fail_run)' scripts autoload
rg -n 'LegacyRunAdapter|allow_legacy_runtime' scripts scenes
```

Expected: all four commands return no matches and exit with ripgrep's no-match status.

- [ ] **Step 6: Run final P4/P5 focused and repository gates**

```bash
./tools/run_tests.sh --filter event_bus_source_contract
./tools/run_tests.sh --filter run_authority_contract
./tools/run_tests.sh --filter run_lifecycle_publication
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter m1_runtime_smoke
./tools/run_tests.sh --filter reward_system_smoke
./tools/validate_project.sh
```

Expected:

- every focused test passes;
- the five-room M1 flow starts and ends once;
- four successful selection facts are published once each;
- Boss victory and player death are terminal and idempotent;
- no legacy fallback is executed;
- no generic event API remains;
- project validation reports no new script error, invalid call, missing resource, ObjectDB leak, or RID leak.

- [ ] **Step 7: Review the complete cutover diff**

```bash
git diff --check HEAD~6..HEAD
git status --short
```

Expected: no whitespace error; only Task 7 files are unstaged before its commit; prior six task commits remain independently reversible.

- [ ] **Step 8: Commit final EventBus removal and certification**

```bash
git add -- autoload/event_bus.gd tools/validate_project.sh tools/test_ci_contract.sh tests/smoke/m1_runtime_smoke_test.gd tests/reward_system_smoke.gd tests/contract/events/event_bus_source_contract_test.gd tests/contract/events/event_bus_source_contract_test.tscn
git diff --cached --check
git commit -m "refactor(events): remove generic event bus"
```

---

## Parallel Execution Boundaries

- Tasks 1–4 are sequential and share ownership of RunState, Facade, Main, RoomController, and the M1 smoke path.
- After Task 4, Tasks 5 and 6 may run in parallel only if `autoload/event_bus.gd` has one integration owner. Task 5 owns lifecycle signatures and Task 6 owns combat/time signatures.
- `scripts/dungeon/room_controller.gd` belongs to Task 6 during the parallel phase; Task 5 must not edit it.
- `scripts/application/run_runtime_host.gd` belongs to Task 5 during the parallel phase; Task 6 must not edit it.
- Task 7 starts only after both event commits are integrated and the working tree is clean.

## P4 Completion Gate

P4 is complete only when:

- one RunState owns run identity, seed, floor, room, build, resources, stats/events, selection, result, suspended state, and revision;
- RunOrchestrator is the sole phase/revision writer after construction;
- RoomRuntime is the sole room-lifecycle coordinator;
- GameState contains no run-domain mirror;
- Main, RoomController, Player, UI, and EventBus subscribers do not write phase or room progression;
- LegacyRunAdapter, legacy selection views, legacy HUD, and legacy-runtime flags are absent;
- five-room M1, reward effects, death, Boss victory, pause, telemetry, and presentation regressions pass.

## P5 Completion Gate

P5 is complete only when:

- every gameplay fact uses one typed signal emission;
- rejected commands emit no fact;
- generic publish/subscribe APIs and storage are absent;
- EventBus has no domain-state-changing subscriber;
- full M1 lifecycle counts are exact and duplicate-free;
- combat/time/spawn event counts are exact and preserve feedback and encounter registration;
- `./tools/validate_project.sh` passes with strict log scanning.

## Self-Review Checklist

- All P4 write authorities identified by the audit map to Tasks 1–4.
- All 29 generic publication sites map to Tasks 5–7.
- Main scene, room scene, adapter tests, M1 smoke, pixel contract, and reward smoke have explicit migration steps.
- Frozen interfaces use one name and signature throughout the plan.
- Every task has a red command, green command, expected outcome, and precise commit command.
- No plan step authorizes a legacy fallback or hidden mirrored state.
- External publication, remote push, signing, and human evidence are outside this implementation plan.
