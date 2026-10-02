extends Node

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const RoomRuntimeScript := preload("res://scripts/dungeon/room_runtime.gd")
const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


class EventFacadeSpy:
	extends RefCounted

	var room_definition: Dictionary = {}
	var state: Dictionary = {"revision": 10, "phase": 4}
	var view: Dictionary = {}
	var continuation: Dictionary = {}
	var open_calls := 0
	var reward_calls := 0
	var encounter_calls := 0
	var dismiss_calls := 0
	var complete_room_calls := 0
	var last_encounter_call: Dictionary = {}

	func current_room_definition() -> Dictionary:
		return room_definition.duplicate(true)

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func enter_current_room():
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]))

	func open_current_event(_runtime_context: Dictionary = {}):
		open_calls += 1
		state["revision"] = int(state["revision"]) + 1
		return _success_with_event_context()

	func event_view_state() -> Dictionary:
		return view.duplicate(true)

	func choose_current_event_option(_option_id: StringName, expected_revision: int):
		if expected_revision != int(state["revision"]):
			return CommandResultScript.failure(&"STALE_REVISION", int(state["revision"]))
		state["revision"] = int(state["revision"]) + 1
		return _success_with_event_context()

	func complete_current_event_reward(
		continuation_id: String,
		_result: Dictionary,
		expected_revision: int
	):
		reward_calls += 1
		if expected_revision != int(state["revision"]):
			return CommandResultScript.failure(&"STALE_REVISION", int(state["revision"]))
		if continuation_id != str(continuation.get("continuation_id", "")):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", int(state["revision"]))
		state["revision"] = int(state["revision"]) + 1
		view["phase"] = "resolved"
		view["pending_kind"] = ""
		continuation.clear()
		return _success_with_event_context()

	func complete_current_event_encounter(
		continuation_id: String,
		success: bool,
		context: Dictionary,
		expected_revision: int
	):
		encounter_calls += 1
		last_encounter_call = {
			"continuation_id": continuation_id,
			"success": success,
			"context": context.duplicate(true),
			"expected_revision": expected_revision,
		}
		if expected_revision != int(state["revision"]):
			return CommandResultScript.failure(&"STALE_REVISION", int(state["revision"]))
		if continuation_id != str(continuation.get("continuation_id", "")):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", int(state["revision"]))
		state["revision"] = int(state["revision"]) + 1
		view["phase"] = "resolved"
		view["pending_kind"] = ""
		continuation.clear()
		return _success_with_event_context()

	func dismiss_current_event(expected_revision: int):
		dismiss_calls += 1
		if expected_revision != int(state["revision"]):
			return CommandResultScript.failure(&"STALE_REVISION", int(state["revision"]))
		if str(view.get("phase", "")) != "resolved":
			return CommandResultScript.failure(&"INVALID_PHASE", int(state["revision"]))
		state["revision"] = int(state["revision"]) + 1
		view["phase"] = "dismissed"
		return _success_with_event_context()

	func complete_current_room():
		complete_room_calls += 1
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]))

	func player_died(context: Dictionary = {}):
		state["revision"] = int(state["revision"]) + 1
		return CommandResultScript.success(int(state["revision"]), context)

	func _success_with_event_context():
		var context := {"view_state": view.duplicate(true)}
		if not continuation.is_empty():
			context["continuation"] = continuation.duplicate(true)
		return CommandResultScript.success(int(state["revision"]), context)


class EventCatalogSpy:
	extends RefCounted

	func encounter_definition(encounter_id: String, _run_seed: int, _room_number: int) -> Dictionary:
		if encounter_id.is_empty():
			return {}
		return {
			"id": encounter_id,
			"waves": [{"id": "wave", "delay_seconds": 0.0, "telegraph_seconds": 0.0, "spawns": []}],
		}


class EventRunnerSpy:
	extends Node

	signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
	signal spawn_requested(spawn_definition: Dictionary)
	signal encounter_completed(encounter_id: StringName)
	signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)

	var start_calls := 0
	var cancel_calls := 0
	var active := false
	var encounter_id := ""

	func start_encounter(encounter: Dictionary, _run_seed: int, _room_number: int) -> void:
		start_calls += 1
		active = true
		encounter_id = str(encounter.get("id", ""))

	func cancel() -> void:
		cancel_calls += 1
		active = false

	func is_active() -> bool:
		return active

	func snapshot() -> Dictionary:
		return {"active": active, "encounter_id": encounter_id}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_director_event_overlay_preserves_floor_plan(suite)
	_test_pending_reward_requires_dismiss_before_clear(suite)
	_test_pending_encounter_uses_authenticated_completion(suite)
	_test_pending_encounter_failure_uses_authenticated_completion(suite)
	_test_room_started_ownership_is_configurable(suite)
	suite.finish(get_tree())


func _test_director_event_overlay_preserves_floor_plan(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": BASE_PACK_PATH, "required": true}], "0.4.0-dev", &"LAUNCH"
	)
	suite.assert_true(not report.has_blocking_errors(), "real Base Pack registry activates")
	if report.has_blocking_errors():
		return
	var floors := _load_json_array(FLOOR_PATH)
	var templates := _load_json_array(TEMPLATE_PATH)
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261002, floors[0], templates
	)
	suite.assert_true(bool(generated.get("ok", false)), "real floor fixture generates")
	if not bool(generated.get("ok", false)):
		return
	var plan: Dictionary = generated["plan"]
	var plan_before := plan.duplicate(true)
	var digest_before := str(plan["generation_digest"])
	var event_node := _first_node_of_type(plan, "event")
	var combat_node := _first_node_of_type(plan, "combat")
	suite.assert_true(not event_node.is_empty(), "generated floor contains an event node")
	suite.assert_true(not combat_node.is_empty(), "generated floor contains a combat node")
	if event_node.is_empty() or combat_node.is_empty():
		return

	var director = RunDirectorScript.new()
	suite.assert_true(director.configure_launch_plan(plan, registry), "director configures real generated floor")
	var node_id := str(event_node["id"])
	var primary_event_id := str(event_node["event_id"])
	var selected_event_id := (
		"event_lost_journal" if primary_event_id != "event_lost_journal" else "event_chronal_altar"
	)
	suite.assert_true(not director.overlay_event_assignment("", selected_event_id), "empty node ID is rejected")
	suite.assert_true(not director.overlay_event_assignment(node_id, ""), "empty event ID is rejected")
	suite.assert_true(
		not director.overlay_event_assignment(str(combat_node["id"]), selected_event_id),
		"non-event node cannot receive an event overlay"
	)
	suite.assert_true(
		director.overlay_event_assignment(node_id, selected_event_id),
		"selected event overlays the event runtime definition"
	)
	var overlaid := director.room_definition_for_node(StringName(node_id))
	suite.assert_equal(overlaid.get("event_id"), selected_event_id, "runtime cache exposes selected event")
	var sequence_definition := _sequence_definition(director.room_sequence, node_id)
	suite.assert_equal(sequence_definition.get("event_id"), selected_event_id, "room sequence exposes selected event")
	suite.assert_equal(plan, plan_before, "event overlay never mutates the authoritative FloorPlan")
	suite.assert_equal(plan.get("generation_digest"), digest_before, "stored generation digest is unchanged")
	suite.assert_equal(
		FloorPlanScript.compute_generation_digest(plan),
		digest_before,
		"generation digest still matches canonical FloorPlan data"
	)

	var restored_director = RunDirectorScript.new()
	suite.assert_true(restored_director.configure_launch_plan(plan, registry), "restore path rebuilds primary definitions")
	suite.assert_equal(
		restored_director.room_definition_for_node(StringName(node_id)).get("event_id"),
		primary_event_id,
		"fresh director starts from immutable primary candidate"
	)
	suite.assert_true(
		restored_director.overlay_event_assignment(node_id, selected_event_id),
		"upper layer can replay the saved selected-event overlay"
	)
	suite.assert_equal(
		restored_director.room_definition_for_node(StringName(node_id)),
		overlaid,
		"replayed overlay rebuilds the exact runtime definition"
	)
	director.free()
	restored_director.free()


func _test_pending_reward_requires_dismiss_before_clear(suite) -> void:
	var facade := _event_facade("pending_reward", {
		"kind": "reward",
		"continuation_id": "event_reward_tx_reward",
		"pool_id": "pool_launch_event_reward",
		"count": 2,
	})
	var fixture := _event_fixture(facade, true)
	var runtime: Node = fixture["runtime"]
	var runner: EventRunnerSpy = fixture["runner"]
	var started: Array[int] = []
	runtime.room_started.connect(func(_room_id: StringName, revision: int): started.append(revision))
	suite.assert_true(runtime.begin_current_room().ok, "Launch event opens through Facade")
	suite.assert_equal(facade.open_calls, 1, "event opens exactly once")
	suite.assert_equal(started.size(), 1, "runtime-owned room start emits once")
	suite.assert_equal(runner.start_calls, 0, "pending reward starts no encounter")
	suite.assert_true(bool(runtime.snapshot()["room_active"]), "pending reward keeps room active")

	var early_clear = runtime.complete_current_room()
	suite.assert_true(not early_clear.ok, "pending reward cannot clear event room")
	suite.assert_equal(facade.complete_room_calls, 0, "early clear reaches no room command")
	var wrong = runtime.complete_current_event_reward("event_reward_wrong", {"reward_id": "item_wrong"})
	suite.assert_true(not wrong.ok, "wrong reward continuation is rejected")
	suite.assert_equal(facade.reward_calls, 0, "wrong reward token never reaches Facade")
	suite.assert_true(bool(runtime.snapshot()["room_active"]), "wrong reward token keeps room active")

	var rewarded = runtime.complete_current_event_reward(
		"event_reward_tx_reward", {"reward_id": "item_hourglass"}
	)
	suite.assert_true(rewarded.ok, "matching reward continuation resolves")
	suite.assert_equal(facade.reward_calls, 1, "matching reward calls Facade once")
	suite.assert_equal(runtime.event_view_state().get("phase"), "resolved", "reward result remains visible")
	suite.assert_true(not runtime.complete_current_room().ok, "resolved result still cannot clear before dismissal")
	suite.assert_true(runtime.dismiss_current_event().ok, "resolved result dismisses through Facade")
	suite.assert_equal(runtime.event_view_state().get("phase"), "dismissed", "dismissed phase is authoritative")
	suite.assert_true(runtime.complete_current_room().ok, "dismissed event room clears")
	suite.assert_equal(facade.complete_room_calls, 1, "dismissed event submits one room completion")
	suite.assert_true(not bool(runtime.snapshot()["room_active"]), "cleared event room is no longer active")
	_free_fixture(fixture)


func _test_pending_encounter_uses_authenticated_completion(suite) -> void:
	var facade := _event_facade("pending_encounter", {
		"kind": "encounter",
		"continuation_id": "event_encounter_tx_guardian",
		"encounter_id": "encounter_profile_forest_adapter_v1",
	})
	var fixture := _event_fixture(facade, true)
	var runtime: Node = fixture["runtime"]
	var runner: EventRunnerSpy = fixture["runner"]
	suite.assert_true(runtime.begin_current_room().ok, "pending encounter event opens")
	suite.assert_equal(runner.start_calls, 1, "authenticated pending encounter starts runner once")
	suite.assert_equal(runner.encounter_id, "encounter_profile_forest_adapter_v1", "runner receives authored encounter")

	runner.encounter_completed.emit(&"encounter_profile_ruins_adapter_v1")
	suite.assert_equal(facade.encounter_calls, 0, "wrong encounter ID cannot consume continuation")
	suite.assert_equal(facade.complete_room_calls, 0, "wrong encounter ID cannot clear room")
	suite.assert_true(bool(runtime.snapshot()["room_active"]), "wrong encounter ID keeps event active")

	runner.encounter_completed.emit(&"encounter_profile_forest_adapter_v1")
	suite.assert_equal(facade.encounter_calls, 1, "matching encounter completes through Facade")
	suite.assert_equal(
		facade.last_encounter_call.get("continuation_id"),
		"event_encounter_tx_guardian",
		"runner completion uses authenticated continuation token"
	)
	suite.assert_equal(facade.complete_room_calls, 0, "encounter completion does not directly clear event room")
	suite.assert_equal(runtime.event_view_state().get("phase"), "resolved", "encounter completion retains result")
	suite.assert_true(bool(runtime.snapshot()["room_active"]), "resolved encounter keeps room active")
	suite.assert_true(runtime.dismiss_current_event().ok, "encounter result dismisses")
	suite.assert_true(runtime.complete_current_room().ok, "dismissed encounter event clears explicitly")
	suite.assert_equal(facade.complete_room_calls, 1, "encounter event clears once")
	_free_fixture(fixture)


func _test_pending_encounter_failure_uses_authenticated_completion(suite) -> void:
	var facade := _event_facade("pending_encounter", {
		"kind": "encounter",
		"continuation_id": "event_encounter_tx_failure",
		"encounter_id": "encounter_profile_forest_adapter_v1",
	})
	var fixture := _event_fixture(facade, true)
	var runtime: Node = fixture["runtime"]
	var runner: EventRunnerSpy = fixture["runner"]
	suite.assert_true(runtime.begin_current_room().ok, "failed encounter fixture opens")
	runner.encounter_failed.emit(
		&"encounter_profile_forest_adapter_v1",
		&"PLAYER_DEFEATED",
		{"wave_id": "wave_failure"}
	)
	suite.assert_equal(facade.encounter_calls, 1, "failed encounter completes through Facade once")
	suite.assert_equal(facade.last_encounter_call.get("success"), false, "failure preserves success=false")
	suite.assert_equal(
		facade.last_encounter_call.get("continuation_id"),
		"event_encounter_tx_failure",
		"failure uses the authenticated continuation"
	)
	var failure_context := facade.last_encounter_call.get("context", {}) as Dictionary
	suite.assert_equal(failure_context.get("reason"), "PLAYER_DEFEATED", "failure reason reaches Facade")
	suite.assert_equal(failure_context.get("wave_id"), "wave_failure", "failure context reaches Facade")
	suite.assert_equal(runtime.event_view_state().get("phase"), "resolved", "failed encounter retains result")
	suite.assert_true(bool(runtime.snapshot()["room_active"]), "failed encounter does not clear room")
	_free_fixture(fixture)


func _test_room_started_ownership_is_configurable(suite) -> void:
	var facade := _event_facade("open", {})
	var fixture := _event_fixture(facade, false)
	var runtime: Node = fixture["runtime"]
	var started: Array[int] = []
	runtime.room_started.connect(func(_room_id: StringName, revision: int): started.append(revision))
	suite.assert_true(runtime.begin_current_room().ok, "host-owned event room opens")
	suite.assert_equal(started.size(), 0, "disabled RoomRuntime ownership emits no duplicate room-start fact")
	suite.assert_true(bool(runtime.snapshot()["room_active"]), "ownership configuration does not change room activity")
	_free_fixture(fixture)


func _event_fixture(facade: EventFacadeSpy, emit_room_started: bool) -> Dictionary:
	var runner := EventRunnerSpy.new()
	add_child(runner)
	var runtime = RoomRuntimeScript.new()
	add_child(runtime)
	runtime.configure(facade, EventCatalogSpy.new(), [facade.room_definition], 20261002, runner, emit_room_started)
	return {"facade": facade, "runner": runner, "runtime": runtime}


func _event_facade(phase: String, continuation: Dictionary) -> EventFacadeSpy:
	var facade := EventFacadeSpy.new()
	facade.room_definition = {
		"id": "layer_02_event_a",
		"node_id": "layer_02_event_a",
		"floor_id": "floor_ruins_of_remnant",
		"floor_index": 0,
		"room_number": 2,
		"type": "event",
		"room_type": "event",
		"event_id": "event_chronal_altar",
		"runtime_mode": "launch",
	}
	facade.view = {
		"phase": phase,
		"event_id": "event_chronal_altar",
		"name_key": "EVENT_CHRONAL_ALTAR_NAME",
		"description_key": "EVENT_CHRONAL_ALTAR_DESCRIPTION",
		"prompt_key": "EVENT_CHRONAL_ALTAR_PROMPT",
		"options": [],
		"revision": 1,
		"result_key": "",
		"pending_kind": str(continuation.get("kind", "")),
	}
	facade.continuation = continuation.duplicate(true)
	return facade


func _free_fixture(fixture: Dictionary) -> void:
	(fixture["runtime"] as Node).queue_free()
	(fixture["runner"] as Node).queue_free()


func _first_node_of_type(plan: Dictionary, room_type: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("room_type", "")) == room_type:
			return (node_value as Dictionary).duplicate(true)
	return {}


func _sequence_definition(sequence: Array[Dictionary], node_id: String) -> Dictionary:
	for definition: Dictionary in sequence:
		if str(definition.get("node_id", "")) == node_id:
			return definition.duplicate(true)
	return {}


func _load_json_array(path: String) -> Array:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Array else []
