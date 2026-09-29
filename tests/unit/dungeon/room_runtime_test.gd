extends Node

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RoomRuntimeScript := preload("res://scripts/dungeon/room_runtime.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class FacadeSpy:
	extends RefCounted

	var room_definition: Dictionary = {}
	var state: Dictionary = {
		"run_id": "room-runtime-test",
		"revision": 4,
		"current_room": 1,
		"phase": 4,
	}
	var enter_room_calls: int = 0
	var complete_room_calls: int = 0
	var boss_defeated_calls: int = 0
	var player_died_calls: int = 0
	var reject_player_died: bool = false

	func current_room_definition() -> Dictionary:
		return room_definition.duplicate(true)

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func enter_current_room():
		enter_room_calls += 1
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]))

	func complete_current_room():
		complete_room_calls += 1
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]), {"offer": {"offer_id": "offer"}})

	func boss_defeated(context: Dictionary = {}):
		boss_defeated_calls += 1
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]), context)

	func player_died(context: Dictionary = {}):
		player_died_calls += 1
		if reject_player_died:
			return CommandResultScript.failure(&"INVALID_PHASE", int(state["revision"]), context)
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]), context)


class CatalogSpy:
	extends RefCounted

	func encounter_definition(encounter_id: String, _run_seed: int, _room_number: int) -> Dictionary:
		if encounter_id.is_empty():
			return {}
		return {
			"id": encounter_id,
			"waves": [{"id": "wave", "delay_seconds": 0.0, "telegraph_seconds": 0.0, "spawns": []}],
		}


class RunnerSpy:
	extends Node

	signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
	signal spawn_requested(spawn_definition: Dictionary)
	signal encounter_completed(encounter_id: StringName)
	signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)

	var start_calls: int = 0
	var register_calls: int = 0
	var reject_calls: int = 0
	var cancel_calls: int = 0
	var active: bool = false

	func start_encounter(_encounter: Dictionary, _run_seed: int, _room_number: int) -> void:
		start_calls += 1
		active = true

	func register_spawned(entity: Node, _spawn_definition: Dictionary = {}) -> bool:
		if not active or entity == null:
			return false
		register_calls += 1
		return true

	func reject_spawn(_spawn_definition: Dictionary, _reason: StringName) -> bool:
		if not active:
			return false
		reject_calls += 1
		return true

	func cancel() -> void:
		cancel_calls += 1
		active = false

	func is_active() -> bool:
		return active

	func snapshot() -> Dictionary:
		return {"active": active}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_room_clear_is_idempotent(suite)
	_test_boss_completion(suite)
	_test_event_room_completes_without_runner(suite)
	_test_spawn_and_failure_paths(suite)
	_test_player_death_is_idempotent(suite)
	_test_rejected_player_death_preserves_active_room(suite)
	_test_next_room_can_begin_after_selection_transition(suite)
	_test_facade_composes_the_authoritative_room_runtime(suite)
	_test_room_controller_contains_no_run_authority(suite)
	suite.finish(get_tree())


func _test_room_clear_is_idempotent(suite) -> void:
	var fixture := _fixture(_room(&"combat", "combat_intro", 1))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	var runner: Node = fixture["runner"]
	var cleared_revisions: Array[int] = []
	runtime.room_cleared.connect(func(_room_id: StringName, revision: int): cleared_revisions.append(revision))
	suite.assert_true(runtime.begin_current_room().ok, "room begins through facade")
	runner.encounter_completed.emit(&"combat_intro")
	runner.encounter_completed.emit(&"combat_intro")
	suite.assert_equal(facade.complete_room_calls, 1, "duplicate completion submits one command")
	suite.assert_equal(cleared_revisions.size(), 1, "duplicate completion emits one clear fact")
	_free_fixture(fixture)


func _test_boss_completion(suite) -> void:
	var fixture := _fixture(_room(&"boss", "chrono_warden", 5))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	var runner: Node = fixture["runner"]
	suite.assert_true(runtime.begin_current_room().ok, "boss room begins")
	runner.encounter_completed.emit(&"chrono_warden")
	suite.assert_equal(facade.boss_defeated_calls, 1, "boss completion submits the terminal command")
	suite.assert_equal(facade.complete_room_calls, 0, "boss completion never submits a normal clear")
	_free_fixture(fixture)


func _test_event_room_completes_without_runner(suite) -> void:
	var fixture := _fixture(_room(&"event", "", 2))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	var runner: Node = fixture["runner"]
	var result = runtime.begin_current_room()
	suite.assert_true(result.ok, "event room resolves through the room authority")
	suite.assert_equal(runner.start_calls, 0, "event room starts no encounter runner")
	suite.assert_equal(facade.complete_room_calls, 1, "event room submits one completion command")
	_free_fixture(fixture)


func _test_spawn_and_failure_paths(suite) -> void:
	var fixture := _fixture(_room(&"elite", "elite_test", 4))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	var runner: Node = fixture["runner"]
	var failures: Array[Dictionary] = []
	runtime.runtime_failed.connect(func(context: Dictionary): failures.append(context))
	runtime.begin_current_room()
	var enemy := Node2D.new()
	add_child(enemy)
	suite.assert_true(runtime.register_spawned(enemy, {"id": "spawn-1"}), "active encounter accepts a spawn acknowledgement")
	suite.assert_equal(runner.register_calls, 1, "spawn acknowledgement is delegated once")
	suite.assert_true(runtime.reject_spawn({"id": "spawn-2"}, &"TEST_REJECT"), "active encounter accepts a spawn rejection")
	runner.encounter_failed.emit(&"elite_test", &"SPAWN_REJECTED", {"spawn_id": "spawn-2"})
	suite.assert_equal(failures.size(), 1, "encounter failure is published once")
	suite.assert_equal(facade.player_died_calls, 1, "runtime failure terminates the authoritative run")
	suite.assert_true(not runtime.register_spawned(enemy, {"id": "late"}), "late summon is rejected after terminal failure")
	enemy.queue_free()
	_free_fixture(fixture)


func _test_player_death_is_idempotent(suite) -> void:
	var fixture := _fixture(_room(&"combat", "death_test", 1))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	runtime.begin_current_room()
	suite.assert_true(runtime.report_player_died("hazard").ok, "player death submits through the facade")
	suite.assert_true(not runtime.report_player_died("late").ok, "duplicate player death is rejected")
	suite.assert_equal(facade.player_died_calls, 1, "player death command is submitted once")
	_free_fixture(fixture)


func _test_rejected_player_death_preserves_active_room(suite) -> void:
	var fixture := _fixture(_room(&"combat", "death_rejected", 1))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	runtime.begin_current_room()
	(facade as FacadeSpy).reject_player_died = true
	var rejected = runtime.report_player_died("late")
	var state: Dictionary = runtime.snapshot()
	suite.assert_true(not rejected.ok, "rejected player death returns the authoritative failure")
	suite.assert_true(bool(state.get("room_active", false)), "rejected player death keeps the room active")
	suite.assert_true(not bool(state.get("room_terminal", true)), "rejected player death does not mark the room terminal")
	_free_fixture(fixture)


func _test_next_room_can_begin_after_selection_transition(suite) -> void:
	var fixture := _fixture(_room(&"combat", "room_one", 1))
	var runtime: Node = fixture["runtime"]
	var facade: RefCounted = fixture["facade"]
	var runner: Node = fixture["runner"]
	runtime.begin_current_room()
	runner.encounter_completed.emit(&"room_one")
	(facade as FacadeSpy).room_definition = _room(&"combat", "room_two", 2)
	(facade as FacadeSpy).state["current_room"] = 2
	var next_result = runtime.begin_current_room()
	suite.assert_true(next_result.ok, "a completed room does not make the runtime terminal for the next room")
	suite.assert_equal(runner.start_calls, 2, "the next authoritative room starts one new encounter")
	_free_fixture(fixture)


func _test_facade_composes_the_authoritative_room_runtime(suite) -> void:
	var facade := RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "real facade boots before room runtime composition")
	var started = facade.start_run({
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}, "room-runtime-integration")
	suite.assert_true(started.ok, "real facade starts before room runtime composition")
	suite.assert_true(facade.has_method("create_room_runtime"), "facade exposes one room-runtime composition seam")
	if not facade.has_method("create_room_runtime"):
		return
	var runner := RunnerSpy.new()
	add_child(runner)
	var runtime_value: Variant = facade.call("create_room_runtime", runner)
	suite.assert_true(runtime_value is Node, "facade creates the authoritative room runtime")
	if not runtime_value is Node:
		runner.queue_free()
		return
	var runtime := runtime_value as Node
	add_child(runtime)
	var runtime_snapshot: Dictionary = runtime.call("snapshot")
	suite.assert_true(bool(runtime_snapshot.get("configured", false)), "composed room runtime is configured")
	suite.assert_equal(int(runtime_snapshot.get("run_seed", 0)), 20260929, "composed room runtime shares the authoritative seed")
	var entered = runtime.call("begin_current_room")
	suite.assert_true(entered.ok, "composed room runtime enters through the real facade")
	suite.assert_equal(int(facade.snapshot().get("phase", -1)), RunPhaseScript.Value.COMBAT_ACTIVE, "room runtime owns the authoritative room-entry command")
	runtime.queue_free()
	runner.queue_free()


func _test_room_controller_contains_no_run_authority(suite) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/dungeon/room_controller.gd")
	suite.assert_true(not source.is_empty(), "room controller source is readable")
	suite.assert_true(not source.contains("GameState."), "room controller does not read or write the legacy run state")
	suite.assert_true(not source.contains("EventBus.room_started.emit"), "room controller does not publish room entry facts")
	suite.assert_true(not source.contains("EventBus.room_cleared.emit"), "room controller does not publish room clear facts")
	suite.assert_true(source.contains("_room_runtime.call(\"register_spawned\""), "room controller acknowledges scene spawns through RoomRuntime")


func _fixture(room_definition: Dictionary) -> Dictionary:
	var facade := FacadeSpy.new()
	facade.room_definition = room_definition
	facade.state["current_room"] = int(room_definition["room_number"])
	var runner := RunnerSpy.new()
	add_child(runner)
	var runtime = RoomRuntimeScript.new()
	add_child(runtime)
	runtime.configure(facade, CatalogSpy.new(), [room_definition], 123, runner)
	return {"facade": facade, "runner": runner, "runtime": runtime}


func _free_fixture(fixture: Dictionary) -> void:
	(fixture["runtime"] as Node).queue_free()
	(fixture["runner"] as Node).queue_free()


func _room(room_type: StringName, encounter_id: String, room_number: int) -> Dictionary:
	return {
		"room_number": room_number,
		"type": str(room_type),
		"encounter_id": encounter_id,
		"reward_kind": "none" if room_type == &"boss" else "starter",
	}
