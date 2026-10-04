extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Runtime := preload("res://scripts/dungeon/room_runtime.gd")
const Result := preload("res://scripts/application/command_result.gd")


class EventFacade extends RefCounted:
	var phase := "open"
	var revision := 1
	var completions: Array[Dictionary] = []
	var continuation: Dictionary = {}

	func current_room_definition() -> Dictionary:
		return {"id": "actual_event_node", "type": "event", "runtime_mode": "launch"}

	func enter_current_room() -> RefCounted:
		return Result.success(revision)

	func open_current_event(_context: Dictionary) -> RefCounted:
		return Result.success(revision, {"view_state": event_view_state(), "continuation": {}})

	func snapshot() -> Dictionary:
		return {"revision": revision}

	func event_view_state() -> Dictionary:
		return {"phase": phase, "pending_kind": "encounter" if phase == "pending_encounter" else ""}

	func _current_event_continuation() -> Dictionary:
		return continuation.duplicate(true)

	func event_encounter_definition(profile_id: String) -> Dictionary:
		return {"id": "concrete_recipe", "waves": []} if profile_id == "authored_profile" else {}

	func complete_current_event_encounter(continuation_id: String, success: bool, context: Dictionary, expected_revision: int) -> RefCounted:
		if continuation_id != "original_continuation" or context.get("encounter_id") != "authored_profile" or expected_revision != revision:
			return Result.failure(&"INVALID_ARGUMENT", revision)
		completions.append({"success": success, "context": context.duplicate(true)})
		phase = "resolved"
		continuation.clear()
		revision += 1
		return Result.success(revision, {"view_state": event_view_state(), "continuation": {}})


class EventRunner extends Node:
	signal encounter_completed(encounter_id: StringName)
	signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)
	var state: Dictionary = {"encounter_id": "", "active": false, "alive_count": 0, "pending_spawn_count": 0, "failure": {}}
	var reject_start := false
	var starts := 0

	func start_encounter(definition: Dictionary, _seed: int, _room_number: int) -> void:
		starts += 1
		state.encounter_id = definition.id
		state.active = not reject_start
		state.alive_count = 1 if state.active else 0
		state.failure = {"code": "START_REJECTED"} if reject_start else {}

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func is_active() -> bool:
		return state.active

	func cancel() -> void:
		state.active = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	for success: bool in [true, false]:
		var facade := EventFacade.new()
		var runner := EventRunner.new()
		var runtime := Runtime.new()
		add_child(runner)
		add_child(runtime)
		runtime.configure(facade, RefCounted.new(), [], 6, runner)
		suite.assert_true(runtime.begin_current_room().ok, "event room opens through its authority")
		var continuation := {"kind": "encounter", "continuation_id": "original_continuation", "encounter_id": "authored_profile"}
		facade.phase = "pending_encounter"
		facade.continuation = continuation.duplicate(true)
		var pending: RefCounted = Result.success(facade.revision, {"view_state": facade.event_view_state(), "continuation": continuation})
		suite.assert_true(runtime.sync_event_result(pending), "event starts concrete recipe while preserving original continuation")
		suite.assert_true(runtime.sync_event_result(pending), "same accepted continuation synchronizes without restarting")
		suite.assert_equal(runner.starts, 1, "accepted continuation owns one Runner start")
		for forged_phase: String in ["resolved", "dismissed", "open"]:
			suite.assert_true(not runtime.sync_event_result(Result.success(facade.revision, {
				"view_state": {"phase": forged_phase, "pending_kind": ""}, "continuation": {},
			})), "uncommitted " + forged_phase + " view cannot tear down the native event encounter")
			suite.assert_true(runner.is_active() and runtime.snapshot().event_continuation == continuation, "forged terminal view preserves active Runner and continuation")
		suite.assert_true(not runtime.sync_event_result(Result.success(facade.revision - 1, {
			"view_state": facade.event_view_state(), "continuation": continuation,
		})), "stale accepted view cannot synchronize current event state")
		var foreign := continuation.duplicate()
		foreign.continuation_id = "foreign_continuation"
		suite.assert_true(not runtime.sync_event_result(Result.success(facade.revision, {"view_state": facade.event_view_state(), "continuation": foreign})), "active Runner cannot be rebound to a foreign continuation")
		runner.encounter_completed.emit(&"concrete_recipe")
		runner.encounter_failed.emit(&"concrete_recipe", &"FORGED", {})
		suite.assert_equal(facade.completions.size(), 0, "active completion and failure signals cannot settle the event")
		runner.state.active = false
		runner.state.alive_count = 0
		runner.encounter_completed.emit(&"authored_profile")
		suite.assert_equal(facade.completions.size(), 0, "profile ID cannot impersonate the concrete settled recipe")
		if success:
			runner.encounter_failed.emit(&"concrete_recipe", &"FORGED", {})
			suite.assert_equal(facade.completions.size(), 0, "failure requires an actual settled Runner failure")
			runner.encounter_completed.emit(&"concrete_recipe")
		else:
			runner.state.failure = {"code": "SPAWN_REJECTED"}
			runner.encounter_completed.emit(&"concrete_recipe")
			suite.assert_equal(facade.completions.size(), 0, "failed Runner cannot publish a victorious event outcome")
			runner.encounter_failed.emit(&"concrete_recipe", &"SPAWN_REJECTED", {"spawn_id": "physical_spawn"})
		suite.assert_equal(facade.completions.size(), 1, "settled concrete identity submits exactly one original continuation")
		if facade.completions.size() == 1:
			suite.assert_equal(facade.completions[0].success, success, "event authority receives the actual Runner outcome")
		runner.encounter_completed.emit(&"concrete_recipe")
		runner.encounter_failed.emit(&"concrete_recipe", &"DUPLICATE", {})
		suite.assert_equal(facade.completions.size(), 1, "duplicate settled signals cannot repeat event consequences")
		runtime.free()
		runner.free()
	var rejected_facade := EventFacade.new()
	var rejected_runner := EventRunner.new()
	var rejected_runtime := Runtime.new()
	add_child(rejected_runner)
	add_child(rejected_runtime)
	rejected_runtime.configure(rejected_facade, RefCounted.new(), [], 6, rejected_runner)
	rejected_runtime.begin_current_room()
	rejected_facade.phase = "pending_encounter"
	rejected_facade.continuation = {"kind": "encounter", "continuation_id": "original_continuation", "encounter_id": "authored_profile"}
	rejected_runner.reject_start = true
	suite.assert_true(not rejected_runtime.sync_event_result(Result.success(1, {
		"view_state": rejected_facade.event_view_state(),
		"continuation": {"kind": "encounter", "continuation_id": "original_continuation", "encounter_id": "authored_profile"},
	})), "synchronous rejected Runner start cannot report a successful event start")
	suite.assert_equal(rejected_runtime.snapshot().event_continuation, {}, "rejected Runner start restores previous RoomRuntime continuation")
	rejected_runtime.free()
	rejected_runner.free()
	suite.finish(get_tree())
