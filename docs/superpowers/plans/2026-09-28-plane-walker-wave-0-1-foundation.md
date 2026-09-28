# Plane Walker Wave 0/1 Foundation Implementation Plan

> **For agentic workers:** Execute each task with a red-green-refactor loop. Keep the existing `tests/reward_system_smoke.gd` intact as a regression gate. Work only in the file ownership assigned to the task.

**Goal:** Establish the frozen M1 contracts, authoritative run state machine, deterministic seed service, first contract-driven HUD, and three P0 combat correctness fixes without overwriting the user's current localization and UI work.

**Architecture:** New application and UI contract modules are introduced beside the existing playable MVP. The old `GameState`, room flow, reward screens, and total assembly scenes remain operational during this wave. New tests exercise the pure modules and isolated UI scene; runtime integration occurs only after the contracts pass independently.

**Tech Stack:** Godot 4.6.1, GDScript 2.0, native Godot scenes, JSON fixtures, headless scene tests.

## Global Constraints

- Preserve the full product vision; this wave only controls the enabled M1 subset.
- M1 remains a fixed five-room, 8–12 minute vertical slice.
- `RunOrchestrator` is the only new-code writer of `RunPhase`.
- UI consumes deep-copied ViewState and emits intent signals; it never mutates gameplay state.
- Rewind restores legal player position, facing, HP, and safe action state; it does not restore energy, cooldowns, inventory, rewards, enemies, or world state.
- Rewind settlement order is restore allowed state, pay energy and cooldown, apply curse cost, then apply build healing or shield.
- One projectile contact causes at most one damage application.
- Overlapping invulnerability lasts until the latest active expiry.
- New gameplay randomness derives from run seed plus channel, floor, room, and roll index.
- Existing modified files under `data/`, `scripts/ui/`, `scripts/rewards/`, `scripts/curses/`, `scripts/main.gd`, `project.godot`, and `tests/reward_system_smoke.gd` are user work and must not be overwritten.
- Baseline and every task gate use Godot 4.6.1 headless tests.

---

## File Ownership and Parallel Lanes

### Lane A: Application foundation

Owns:

- `scripts/application/`
- `scripts/core/seed_service.gd`
- `tests/unit/application/`
- `tests/unit/core/`
- `tests/support/`

Must not edit combat, UI, content JSON, `GameState`, EventBus, or assembly scenes.

### Lane B: Combat correctness

Owns:

- `scripts/combat/health_component.gd`
- `scripts/enemies/enemy_projectile.gd`
- `scripts/time_system/time_manager.gd`
- `scripts/time_system/rewind_recorder.gd`
- `tests/combat/`
- `tests/time/`

Must not edit player input, reward flow, UI, data, or assembly scenes.

### Lane C: Contract-driven UI

Owns:

- `scripts/ui/contracts/`
- `scripts/ui/fixtures/`
- `scripts/ui/views/`
- `scenes/ui/combat_hud_v2.tscn`
- `tests/ui/`
- `tests/fixtures/ui/`

Must not edit existing UI scripts, `main.tscn`, `combat_room_01.tscn`, `GameState`, combat, or reward pools.

### Integration owner

Owns plan/spec status, cross-lane review, full verification, and commits. No assembly-scene integration is authorized in this wave.

---

### Task 1: Add a reusable headless test harness

**Files:**

- Create: `tests/support/test_suite.gd`
- Create: `tests/unit/core/test_suite_test.gd`
- Create: `tests/unit/core/test_suite_test.tscn`

**Interfaces:**

- Produces: `TestSuite.assert_true(value, label)`, `assert_equal(actual, expected, label)`, `assert_close(actual, expected, label)`, and `finish(scene_tree)`.
- Consumes: only Godot core types.

- [ ] **Step 1: Write the harness self-test scene**

```gdscript
extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = TestSuiteScript.new()
	suite.assert_true(true, "true values pass")
	suite.assert_equal({"value": 3}, {"value": 3}, "dictionaries compare by value")
	suite.assert_close(0.3001, 0.3, "floats compare within tolerance", 0.001)
	suite.finish(get_tree())
```

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/unit/core/test_suite_test.gd" id="1"]

[node name="TestSuiteTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Run the self-test and verify it fails before the harness exists**

Run:

```bash
godot --headless --path . --scene res://tests/unit/core/test_suite_test.tscn
```

Expected: non-zero exit with a missing preload error for `tests/support/test_suite.gd`.

- [ ] **Step 3: Implement the harness**

```gdscript
class_name TestSuite
extends RefCounted

var failures: Array[String] = []

func assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label, "expected true")

func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail(label, "expected %s, got %s" % [str(expected), str(actual)])

func assert_close(actual: float, expected: float, label: String, tolerance: float = 0.001) -> void:
	if absf(actual - expected) > tolerance:
		_fail(label, "expected %.4f, got %.4f" % [expected, actual])

func finish(tree: SceneTree) -> void:
	if failures.is_empty():
		print("PASS: all assertions succeeded")
		tree.quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	tree.quit(1)

func _fail(label: String, detail: String) -> void:
	failures.append("%s: %s" % [label, detail])
```

- [ ] **Step 4: Run the self-test and existing smoke test**

Run:

```bash
godot --headless --path . --scene res://tests/unit/core/test_suite_test.tscn
godot --headless --path . --scene res://tests/reward_system_smoke.tscn
```

Expected: both exit `0`; the legacy smoke may still report its pre-existing ObjectDB leak warning.

- [ ] **Step 5: Commit only Task 1 files**

```bash
git add tests/support/test_suite.gd tests/unit/core/test_suite_test.gd tests/unit/core/test_suite_test.tscn
git commit -m "test: add isolated Godot test harness"
```

---

### Task 2: Freeze command, phase, run-config, and offer contracts

**Files:**

- Create: `scripts/application/command_result.gd`
- Create: `scripts/application/run_phase.gd`
- Create: `scripts/application/run_config.gd`
- Create: `scripts/application/selection_offer.gd`
- Create: `tests/unit/application/contracts_test.gd`
- Create: `tests/unit/application/contracts_test.tscn`

**Interfaces:**

- Produces: `CommandResult.success()`, `CommandResult.failure()`, `RunPhase.is_terminal()`, `RunConfig.validate()`, `RunConfig.normalized()`, `SelectionOffer.validate()`, and `SelectionOffer.copy_of()`.
- Consumes: `TestSuite` from Task 1.

- [ ] **Step 1: Write failing contract tests**

Tests must assert:

```gdscript
var success = CommandResultScript.success(4, {"offer_id": "run:1:item:4"})
suite.assert_true(success.ok, "success result is accepted")
suite.assert_equal(success.code, &"OK", "success code is stable")
suite.assert_equal(success.new_revision, 4, "success revision is retained")

var terminal = CommandResultScript.failure(&"TERMINAL_STATE", 9)
suite.assert_true(not terminal.ok, "failure result is rejected")
suite.assert_equal(terminal.code, &"TERMINAL_STATE", "failure code is retained")

suite.assert_true(RunPhaseScript.is_terminal(RunPhaseScript.Value.VICTORY), "victory is terminal")
suite.assert_true(RunPhaseScript.is_terminal(RunPhaseScript.Value.DEFEAT), "defeat is terminal")
suite.assert_true(not RunPhaseScript.is_terminal(RunPhaseScript.Value.COMBAT_ACTIVE), "combat is not terminal")

var config = {
	"schema_version": 1,
	"milestone": "M1",
	"character_id": "wanderer",
	"weapon_id": "sword",
	"enabled_time_skills": ["time_stop", "time_rewind"],
	"difficulty": "normal",
	"seed": 123456,
}
suite.assert_true(RunConfigScript.validate(config).ok, "M1 config validates")
suite.assert_equal(RunConfigScript.normalized(config)["seed"], 123456, "seed is normalized")

var offer = {
	"schema_version": 1,
	"offer_id": "run-1:room-01:item:1",
	"revision": 1,
	"category": "item",
	"title_key": "UI_CHOOSE_REWARD",
	"can_skip": false,
	"options": [{
		"option_id": "frozen_burst",
		"content_id": "frozen_burst",
		"name_key": "FROZEN_BURST_NAME",
		"description_key": "FROZEN_BURST_DESC",
		"archetype_key": "ARCHETYPE_TIME_STOP_BURST",
		"role_key": "ROLE_STARTER",
		"rarity": "common",
		"icon_id": "item_frozen_burst",
		"effect_summary_keys": ["EFFECT_TIME_STOP_DURATION"],
	}],
}
suite.assert_true(SelectionOfferScript.validate(offer).ok, "valid offer passes")
var copied = SelectionOfferScript.copy_of(offer)
copied["options"][0]["option_id"] = "changed"
suite.assert_equal(offer["options"][0]["option_id"], "frozen_burst", "offer copy is isolated")
```

Also reject unsupported schema versions, empty IDs, negative revisions, empty options, duplicate `option_id`, missing localization keys, and unknown standard error codes.

- [ ] **Step 2: Run the contract test and verify missing scripts fail**

Run:

```bash
godot --headless --path . --scene res://tests/unit/application/contracts_test.tscn
```

Expected: non-zero exit because application contract scripts do not exist.

- [ ] **Step 3: Implement minimal contract modules**

`CommandResult` stores `ok`, `code`, `message_key`, `context`, and `new_revision`. Its standard codes are:

```gdscript
const STANDARD_CODES: Array[StringName] = [
	&"OK",
	&"INVALID_PHASE",
	&"STALE_REVISION",
	&"OFFER_CLOSED",
	&"OPTION_NOT_FOUND",
	&"ALREADY_CONSUMED",
	&"TERMINAL_STATE",
	&"CONTENT_NOT_AVAILABLE",
	&"SAVE_FAILED",
	&"INVALID_ARGUMENT",
]
```

`RunPhase.Value` is exactly:

```gdscript
enum Value {
	BOOT,
	HUB,
	RUN_PREPARING,
	ROOM_ENTERING,
	COMBAT_ACTIVE,
	ROOM_RESOLVING,
	SELECTION_ACTIVE,
	ROOM_TRANSITION,
	BOSS_ACTIVE,
	VICTORY,
	DEFEAT,
}
```

`RunConfig.normalized()` applies only these defaults:

```gdscript
{
	"schema_version": 1,
	"milestone": "M1",
	"character_id": "wanderer",
	"weapon_id": "sword",
	"enabled_time_skills": ["time_stop", "time_rewind"],
	"difficulty": "normal",
	"seed": 0,
}
```

No contract module may reference Node, UI, `GameState`, EventBus, Player, or RewardPool.

- [ ] **Step 4: Run tests and scan forbidden dependencies**

Run:

```bash
godot --headless --path . --scene res://tests/unit/application/contracts_test.tscn
rg -n "GameState|EventBus|Player|RewardPool|NodePath" scripts/application
```

Expected: test exits `0`; dependency scan returns no matches.

- [ ] **Step 5: Commit only contract files**

```bash
git add scripts/application tests/unit/application/contracts_test.gd tests/unit/application/contracts_test.tscn
git commit -m "feat: freeze M1 application contracts"
```

---

### Task 3: Add deterministic SeedService, RunState, and RunOrchestrator

**Files:**

- Create: `scripts/core/seed_service.gd`
- Create: `scripts/application/run_state.gd`
- Create: `scripts/application/run_orchestrator.gd`
- Create: `tests/unit/core/seed_service_test.gd`
- Create: `tests/unit/core/seed_service_test.tscn`
- Create: `tests/unit/application/run_state_test.gd`
- Create: `tests/unit/application/run_state_test.tscn`
- Create: `tests/unit/application/run_orchestrator_test.gd`
- Create: `tests/unit/application/run_orchestrator_test.tscn`

**Interfaces:**

- Consumes: Task 2 contract modules and existing `RunBuildState`.
- Produces: deterministic seed derivation, deep-copied run snapshots, legal phase transitions, terminal-state rejection, and pause overlay state.

- [ ] **Step 1: Write SeedService tests**

Assert the following exact properties:

```gdscript
var a = SeedServiceScript.derive_seed(123, &"draft", 1, 2, 3)
var b = SeedServiceScript.derive_seed(123, &"draft", 1, 2, 3)
suite.assert_equal(a, b, "same seed inputs are deterministic")
suite.assert_true(a != SeedServiceScript.derive_seed(123, &"combat", 1, 2, 3), "channels are isolated")
suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 1, 2, 4), "roll indexes are isolated")
suite.assert_equal(
	SeedServiceScript.make_rng(123, &"draft", 1, 2, 3).randi(),
	SeedServiceScript.make_rng(123, &"draft", 1, 2, 3).randi(),
	"derived RNG streams reproduce"
)
```

Implementation must hash a stable string formed as:

```text
run_seed|channel|floor_index|room_index|roll_index
```

- [ ] **Step 2: Write RunState tests**

Cover reset isolation, revision increments, terminal detection, suspended state independent of phase, consumed offer idempotency, and snapshot deep-copy isolation.

The state owns:

```gdscript
var run_id: String = ""
var revision: int = 0
var phase: int = RunPhaseScript.Value.BOOT
var suspended: bool = false
var run_seed: int = 0
var current_room: int = 0
var room_total: int = 5
var run_time_ms: int = 0
var build_state: RefCounted
var open_offer: Dictionary = {}
var consumed_offer_ids: Dictionary = {}
var result: Dictionary = {}
```

`snapshot()` must include all fields and a deep copy of `build_state.to_dictionary()`.

- [ ] **Step 3: Write RunOrchestrator tests**

Test this full legal path:

```text
BOOT -> HUB -> RUN_PREPARING -> ROOM_ENTERING -> COMBAT_ACTIVE
-> ROOM_RESOLVING -> SELECTION_ACTIVE -> ROOM_TRANSITION
-> ROOM_ENTERING -> BOSS_ACTIVE -> VICTORY
```

Test these failures:

- `room_cleared()` from HUB returns `INVALID_PHASE` without revision change.
- `player_died()` after VICTORY returns `TERMINAL_STATE`.
- `boss_defeated()` enters VICTORY directly without opening a selection.
- `pause_run()` toggles only `suspended`; `phase` remains unchanged.
- Repeated `room_cleared()` accepts only the first call.

- [ ] **Step 4: Implement the minimal pure modules**

`RunOrchestrator` owns one `RunState` instance and exposes:

```gdscript
func enter_hub() -> CommandResult
func start_run(config: Dictionary, run_id: String) -> CommandResult
func preparation_completed() -> CommandResult
func room_entered(is_boss: bool) -> CommandResult
func room_cleared() -> CommandResult
func open_selection(offer: Dictionary) -> CommandResult
func selection_resolved() -> CommandResult
func transition_completed() -> CommandResult
func player_died(context: Dictionary = {}) -> CommandResult
func boss_defeated(context: Dictionary = {}) -> CommandResult
func pause_run() -> CommandResult
func resume_run() -> CommandResult
```

Every accepted command calls `state.advance_revision()` exactly once. Every rejected command leaves state unchanged.

- [ ] **Step 5: Run all application tests**

Run:

```bash
godot --headless --path . --scene res://tests/unit/core/seed_service_test.tscn
godot --headless --path . --scene res://tests/unit/application/run_state_test.tscn
godot --headless --path . --scene res://tests/unit/application/run_orchestrator_test.tscn
```

Expected: all three exit `0` with no script errors.

- [ ] **Step 6: Commit only Task 3 files**

```bash
git add scripts/core/seed_service.gd scripts/application/run_state.gd scripts/application/run_orchestrator.gd tests/unit/core/seed_service_test.gd tests/unit/core/seed_service_test.tscn tests/unit/application/run_state_test.gd tests/unit/application/run_state_test.tscn tests/unit/application/run_orchestrator_test.gd tests/unit/application/run_orchestrator_test.tscn
git commit -m "feat: add authoritative run state machine"
```

---

### Task 4: Fix the three P0 combat correctness defects

**Files:**

- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/enemies/enemy_projectile.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/rewind_recorder.gd`
- Create: `tests/combat/health_component_test.gd`
- Create: `tests/combat/health_component_test.tscn`
- Create: `tests/combat/enemy_projectile_test.gd`
- Create: `tests/combat/enemy_projectile_test.tscn`
- Create: `tests/time/rewind_transaction_test.gd`
- Create: `tests/time/rewind_transaction_test.tscn`

**Interfaces:**

- Produces: latest-expiry invulnerability, atomic projectile hit resolution, and transactional rewind.
- Preserves: all existing public methods used by scenes and legacy smoke tests.

- [ ] **Step 1: Write the overlapping-invulnerability test**

The test applies 0.10 seconds of invulnerability, waits 0.04 seconds, applies 0.20 seconds, verifies damage is rejected after the first expiry, then verifies damage is accepted after the latest expiry.

Implementation rule:

```gdscript
var _invulnerable_until_msec: int = 0

func apply_invulnerability(duration: float) -> void:
	var now := Time.get_ticks_msec()
	_invulnerable_until_msec = maxi(_invulnerable_until_msec, now + ceili(duration * 1000.0))
	invulnerable = true
	var token := _invulnerable_until_msec
	await get_tree().create_timer(duration).timeout
	if token == _invulnerable_until_msec and Time.get_ticks_msec() >= _invulnerable_until_msec:
		invulnerable = false
```

The final implementation may use a monotonic float clock instead, but the latest expiry must remain authoritative.

- [ ] **Step 2: Write the single-projectile-hit test**

Instantiate one projectile and a player with Hurtbox. Invoke both collision routes in the same physics frame. Assert HP changes once and the projectile sets `_resolved` before applying damage.

Implementation rule:

```gdscript
var _resolved: bool = false

func _try_hit_player(target: Node) -> void:
	if _resolved or target == null:
		return
	_resolved = true
	# Resolve the target's HealthComponent exactly once, then queue_free().
```

Both `_on_area_entered()` and `_on_body_entered()` call `_try_hit_player()`.

- [ ] **Step 3: Write the rewind transaction test**

Cover:

- Snapshot energy 90 and effective cost 45 ends at energy 45.
- Snapshot HP 80, self-damage 18, and build heal 28 settles in that order.
- Empty snapshot returns `false` without energy or cooldown changes.
- Successful rewind emits start/end once and enters cooldown once.
- Restored data excludes energy and cooldown.

Refactor `RewindRecorder` to expose:

```gdscript
func consume_oldest_snapshot() -> Dictionary
func restore_player_state(snapshot: Dictionary) -> bool
func clear_snapshots() -> void
```

Recorded snapshots keep `position`, `facing`, `velocity`, `hp`, and safe action data. They no longer store energy.

`TimeManager.try_rewind(recorder)` returns `bool` and settles:

```text
validate snapshot and affordability
consume and restore allowed player state
pay energy and start cooldown
apply rewind self-damage
apply rewind build healing
emit completed event
```

- [ ] **Step 4: Run focused tests before the legacy smoke**

Run:

```bash
godot --headless --path . --scene res://tests/combat/health_component_test.tscn
godot --headless --path . --scene res://tests/combat/enemy_projectile_test.tscn
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn
godot --headless --path . --scene res://tests/reward_system_smoke.tscn
```

Expected: all exit `0`; existing public call sites remain valid.

- [ ] **Step 5: Commit only combat P0 files**

```bash
git add scripts/combat/health_component.gd scripts/enemies/enemy_projectile.gd scripts/time_system/time_manager.gd scripts/time_system/rewind_recorder.gd tests/combat tests/time/rewind_transaction_test.gd tests/time/rewind_transaction_test.tscn
git commit -m "fix: enforce combat and rewind invariants"
```

---

### Task 5: Build the contract-driven HUD and fixtures

**Files:**

- Create: `scripts/ui/contracts/run_view_state.gd`
- Create: `scripts/ui/fixtures/run_view_state_fixtures.gd`
- Create: `scripts/ui/views/combat_hud_view.gd`
- Create: `scenes/ui/combat_hud_v2.tscn`
- Create: `tests/fixtures/ui/hud_combat.json`
- Create: `tests/fixtures/ui/hud_boss.json`
- Create: `tests/fixtures/ui/hud_low_hp.json`
- Create: `tests/ui/run_view_state_contract_test.gd`
- Create: `tests/ui/run_view_state_contract_test.tscn`
- Create: `tests/ui/combat_hud_v2_scene_test.gd`
- Create: `tests/ui/combat_hud_v2_scene_test.tscn`

**Interfaces:**

- Consumes: immutable dictionaries matching the approved `RunViewState` schema.
- Produces: `CombatHudView.render(view_state: Dictionary) -> CommandResult` and a standalone HUD scene that loads without Player, CombatRoom, or `GameState`.

- [ ] **Step 1: Write contract tests from JSON fixtures**

Each fixture contains:

```json
{
  "schema_version": 1,
  "revision": 1,
  "run_id": "fixture-run",
  "phase": "COMBAT_ACTIVE",
  "suspended": false,
  "run_time_ms": 60000,
  "room": {"index": 1, "total": 5, "type": "combat", "title_key": "ROOM_M1_01"},
  "player": {
    "hp": 160.0,
    "max_hp": 200.0,
    "energy": 72.0,
    "max_energy": 100.0,
    "action_state": "FREE",
    "cooldowns": {"time_stop": 0.0, "time_rewind": 4.5}
  },
  "build": {
    "items": [],
    "blessings": [],
    "curses": [],
    "talents": [],
    "dominant_archetype": "time_stop_burst",
    "archetype_scores": {"time_stop_burst": 1}
  },
  "selection": null,
  "boss": null,
  "result": null,
  "ui_flags": {"show_hud": true, "accept_gameplay_input": true, "show_pause": false}
}
```

Contract tests reject missing schema version, unsupported schema version, negative revision, empty run ID, HP above max HP, energy above max energy, room index outside total, and unknown phase. `copy_of()` must deep-copy nested arrays and dictionaries.

- [ ] **Step 2: Write the standalone HUD scene test**

The test instantiates `combat_hud_v2.tscn` without a Player node and renders combat, low-HP, and Boss fixtures. Assert:

- HP and energy bars receive current and maximum values.
- Room label shows `1 / 5`.
- Stop and rewind labels show ready/cooldown states.
- Low-HP indicator changes visibility from the fixture.
- Boss panel is hidden for combat and shown for Boss.
- Re-rendering the same or older revision is rejected with `STALE_REVISION`.
- Rendering does not change `GameState.phase` or any gameplay node.

- [ ] **Step 3: Implement a pure ViewState validator and fixture provider**

`RunViewState.validate(value)` returns `CommandResult`. `copy_of(value)` returns a deep copy only after validation. The fixture provider loads JSON through `FileAccess`, validates it, and returns the deep-copied dictionary.

No file under `scripts/ui/contracts`, `fixtures`, or `views` may reference:

```text
GameState
EventBus
PlayerController
HealthComponent
TimeManager
RewardPool
NodePath to gameplay entities
```

- [ ] **Step 4: Implement the pixel-safe HUD scene**

Use native `CanvasLayer`, `MarginContainer`, `VBoxContainer`, `HBoxContainer`, `ProgressBar`, and `Label` nodes. Anchor the root control to the full viewport. Use integer offsets and a restrained cyan/blue time palette; use red/orange only for danger. Do not add external art dependencies in this wave.

The view script exposes:

```gdscript
signal intent_emitted(intent: Dictionary)

func render(view_state: Dictionary) -> CommandResult:
	# Validate, reject stale revisions, and update only UI nodes.
```

The HUD is a display-only view in this task, so it does not emit gameplay intent yet.

- [ ] **Step 5: Run UI tests and dependency scan**

Run:

```bash
godot --headless --path . --scene res://tests/ui/run_view_state_contract_test.tscn
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn
rg -n "GameState|EventBus|PlayerController|HealthComponent|TimeManager|RewardPool" scripts/ui/contracts scripts/ui/fixtures scripts/ui/views
```

Expected: both tests exit `0`; scan returns no matches.

- [ ] **Step 6: Commit only new UI contract, fixture, scene, and test files**

```bash
git add scripts/ui/contracts scripts/ui/fixtures scripts/ui/views scenes/ui/combat_hud_v2.tscn tests/fixtures/ui tests/ui
git commit -m "feat: add contract-driven combat HUD"
```

---

### Task 6: Cross-lane verification and Wave 1 checkpoint

**Files:**

- Modify only if verification finds a defect in newly added files.
- Do not modify legacy assembly scenes or the user's uncommitted files.

- [ ] **Step 1: Run project import and script parsing**

Run:

```bash
godot --headless --editor --path . --quit
```

Expected: exit `0` with no parse or resource-load errors caused by new files.

- [ ] **Step 2: Run every new focused test**

Run:

```bash
godot --headless --path . --scene res://tests/unit/core/test_suite_test.tscn
godot --headless --path . --scene res://tests/unit/application/contracts_test.tscn
godot --headless --path . --scene res://tests/unit/core/seed_service_test.tscn
godot --headless --path . --scene res://tests/unit/application/run_state_test.tscn
godot --headless --path . --scene res://tests/unit/application/run_orchestrator_test.tscn
godot --headless --path . --scene res://tests/combat/health_component_test.tscn
godot --headless --path . --scene res://tests/combat/enemy_projectile_test.tscn
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn
godot --headless --path . --scene res://tests/ui/run_view_state_contract_test.tscn
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn
```

Expected: every command exits `0`.

- [ ] **Step 3: Run the legacy regression smoke**

Run:

```bash
godot --headless --path . --scene res://tests/reward_system_smoke.tscn
```

Expected: exit `0`. The pre-existing ObjectDB leak warning is recorded as a known baseline issue and is not expanded by new tests.

- [ ] **Step 4: Verify scope and workspace isolation**

Run:

```bash
git status --short
git diff --check
git diff --name-only HEAD
```

Expected: no user-modified legacy file changed because of Lane A or Lane C. Lane B changes only the four explicitly owned clean gameplay files and its new tests.

- [ ] **Step 5: Review completion criteria**

Wave 1 foundation is complete only when:

- Contracts reject invalid data and deep-copy valid data.
- Run phase transitions have one pure authority and terminal states are irreversible.
- Seed channels are deterministic and isolated.
- Rewind cannot refund its own energy cost or self-damage.
- Overlapping invulnerability cannot end early.
- Enemy projectiles cannot double-hit through body and Hurtbox callbacks.
- The new HUD renders from fixtures without Player, CombatRoom, `GameState`, or EventBus.
- Existing MVP smoke still passes.
- User localization and UI work remains untouched.

- [ ] **Step 6: Commit the checkpoint documentation only if it changed**

```bash
git add docs/superpowers/specs/2026-09-28-plane-walker-staged-development-design.md docs/superpowers/plans/2026-09-28-plane-walker-wave-0-1-foundation.md
git commit -m "docs: approve and plan Plane Walker foundation"
```

---

## Follow-on Plan Boundaries

This wave intentionally stops before legacy runtime integration. The next implementation plans are separate reviewable subprojects:

1. Run and Build integration: ContentRegistry, M1 room plan, DraftService, Offer idempotency, `GameState` compatibility adapter, and real five-room flow.
2. Combat feel: player action state, 8-frame input buffer, 12-frame combo queue, attack/dash cancellation, hitstun, defense/crit correction, enemy telegraphs, and Boss action mutual exclusion.
3. UI integration and pixel presentation: unified choice panel, pause/result views, runtime ViewState projector, intent router, pixel benchmark room, localization contract checks, and 640×360 integer-scaling integration.

Each follow-on plan must preserve the contracts established here and add its own independent headless test gate.
