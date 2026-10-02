extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const RunRuntimeHostScript := preload("res://scripts/application/run_runtime_host.gd")

const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


class RouteLifecycleRecorder:
	extends RefCounted

	var run_started_events: Array[Dictionary] = []
	var route_events: Array[Dictionary] = []
	var room_started_events: Array[Dictionary] = []
	var room_cleared_events: Array[Dictionary] = []
	var floor_started_events: Array[Dictionary] = []
	var floor_completed_events: Array[Dictionary] = []

	func record_run_started(run_id: String, snapshot: Dictionary) -> void:
		run_started_events.append({"run_id": run_id, "snapshot": snapshot.duplicate(true)})

	func record_route_selected(
		run_id: String,
		floor_id: StringName,
		edge_id: StringName,
		node_id: StringName,
		revision: int
	) -> void:
		route_events.append({
			"run_id": run_id,
			"floor_id": str(floor_id),
			"edge_id": str(edge_id),
			"node_id": str(node_id),
			"revision": revision,
		})

	func record_room_started(run_id: String, room_id: StringName, revision: int) -> void:
		room_started_events.append({
			"run_id": run_id,
			"room_id": str(room_id),
			"revision": revision,
		})

	func record_room_cleared(run_id: String, room_id: StringName, revision: int) -> void:
		room_cleared_events.append({
			"run_id": run_id,
			"room_id": str(room_id),
			"revision": revision,
		})

	func record_floor_started(
		run_id: String, floor_id: StringName, floor_index: int, revision: int
	) -> void:
		floor_started_events.append({
			"run_id": run_id,
			"floor_id": str(floor_id),
			"floor_index": floor_index,
			"revision": revision,
		})

	func record_floor_completed(
		run_id: String, floor_id: StringName, floor_index: int, revision: int
	) -> void:
		floor_completed_events.append({
			"run_id": run_id,
			"floor_id": str(floor_id),
			"floor_index": floor_index,
			"revision": revision,
		})


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var floors: Array = _load_json_array(FLOOR_PATH)
	var templates: Array = _load_json_array(TEMPLATE_PATH)
	if floors.size() != 5 or templates.size() != 30:
		suite.assert_true(false, "five-floor lifecycle fixtures are complete")
		suite.finish(get_tree())
		return
	_test_five_floor_progression(suite, floors, templates)
	_test_first_boss_is_not_victory(suite, floors[0], templates)
	_test_event_bus_floor_signal_contract(suite)
	_test_runtime_host_launch_start_failure_is_atomic(suite)
	_test_runtime_host_route_transaction_and_publication(suite)
	suite.finish(get_tree())


func _test_five_floor_progression(suite, floors: Array, templates: Array) -> void:
	var orchestrator = _started_launch("run-five-floor-lifecycle")
	for floor_index: int in range(floors.size()):
		var floor: Dictionary = floors[floor_index]
		var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
			20261001, floor, templates
		)
		suite.assert_true(bool(generated.get("ok", false)), "floor %d generates" % (floor_index + 1))
		if not bool(generated.get("ok", false)):
			return
		var started = orchestrator.start_floor(
			generated["plan"], floor, templates, orchestrator.revision()
		)
		suite.assert_true(started.ok, "floor %d starts" % (floor_index + 1))
		if not started.ok:
			return
		while str(orchestrator.snapshot()["floor_plan"]["current_node_id"]) != "boss":
			if not _advance_one_node(suite, orchestrator, "floor %d" % (floor_index + 1)):
				return
		var boss_id := str(orchestrator.snapshot()["floor_plan"]["current_node_id"])
		var entered = orchestrator.enter_floor_node(boss_id, orchestrator.revision())
		suite.assert_true(entered.ok, "floor %d Boss enters" % (floor_index + 1))
		suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.BOSS_ACTIVE, "floor %d owns Boss phase" % (floor_index + 1))
		var cleared = orchestrator.complete_floor_node(boss_id, orchestrator.revision())
		suite.assert_true(cleared.ok, "floor %d Boss clears" % (floor_index + 1))
		var completed = orchestrator.complete_floor(
			{"result": "victory", "floor_id": str(floor["id"])},
			orchestrator.revision()
		)
		suite.assert_true(completed.ok, "floor %d completion commits" % (floor_index + 1))
		var snapshot: Dictionary = orchestrator.snapshot()
		suite.assert_equal(
			(snapshot["completed_floor_ids"] as Array).size(),
			floor_index + 1,
			"floor completion appends one history entry"
		)
		if floor_index < 4:
			suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.RUN_PREPARING, "non-final Boss returns to floor preparation")
			suite.assert_true(not orchestrator.is_terminal(), "non-final Boss is not Victory")
		else:
			suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.VICTORY, "fifth Boss enters Victory")
			suite.assert_true(orchestrator.is_terminal(), "fifth Boss is terminal")
			suite.assert_equal(snapshot["result"].get("result"), "victory", "final victory context is retained")


func _test_first_boss_is_not_victory(suite, floor: Dictionary, templates: Array) -> void:
	var orchestrator = _started_launch("run-first-boss-convenience")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "Boss convenience fixture generates")
		return
	orchestrator.start_floor(generated["plan"], floor, templates, orchestrator.revision())
	while str(orchestrator.snapshot()["floor_plan"]["current_node_id"]) != "boss":
		if not _advance_one_node(suite, orchestrator, "Boss convenience"):
			return
	var boss_id := str(orchestrator.snapshot()["floor_plan"]["current_node_id"])
	orchestrator.enter_floor_node(boss_id, orchestrator.revision())
	var defeated = orchestrator.boss_defeated({"result": "victory"})
	suite.assert_true(defeated.ok, "Launch Boss convenience command commits")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.RUN_PREPARING, "first Boss convenience command is not Victory")
	suite.assert_equal(orchestrator.snapshot()["completed_floor_ids"], [str(floor["id"])], "Boss convenience completes exactly one floor")


func _test_event_bus_floor_signal_contract(suite) -> void:
	var signatures: Dictionary = {}
	for signal_definition: Dictionary in EventBus.get_signal_list():
		signatures[str(signal_definition.get("name", ""))] = signal_definition.get("args", [])
	for signal_name: String in ["route_selected", "floor_started", "floor_completed"]:
		suite.assert_true(signatures.has(signal_name), "EventBus declares typed %s" % signal_name)
		if signatures.has(signal_name):
			suite.assert_true((signatures[signal_name] as Array).size() >= 3, "%s carries run identity, payload, and revision" % signal_name)


func _test_runtime_host_route_transaction_and_publication(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "Launch runtime facade boots")
	if not booted.ok:
		return
	var run_id := "run-launch-route-runtime"
	var started = facade.start_run(_launch_config(), run_id)
	suite.assert_true(started.ok, "Launch runtime facade starts from canonical registry definitions")
	if not started.ok:
		return

	var host := RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_active_run_id", run_id)
	host.set("_published_run_id", run_id)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)

	var choices: Array[Dictionary] = host.call("route_choices")
	suite.assert_true(not choices.is_empty(), "Launch floor entry exposes a route choice")
	if choices.is_empty():
		_disconnect_route_recorder(recorder)
		host.free()
		return
	var first_edge_id := StringName(str(choices[0].get("edge_id", "")))
	var before_failure: Dictionary = facade.snapshot()
	suite.assert_true(
		host.call("configure_route_scene_adapter", func(_target: Dictionary, _context: Dictionary): return false),
		"Host accepts a rejecting route scene adapter"
	)
	var failed = host.call("select_route", first_edge_id)
	suite.assert_true(not failed.ok, "scene adapter rejection fails the route transition")
	suite.assert_equal(str(failed.code), "COMMIT_FAILED", "scene adapter rejection returns the stable failure code")
	suite.assert_equal(facade.snapshot(), before_failure, "scene adapter rejection restores the exact authoritative snapshot")
	suite.assert_equal(recorder.route_events.size(), 0, "rejected scene transition publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "rejected scene transition publishes no room-start fact")
	suite.assert_equal(recorder.room_cleared_events.size(), 0, "rejected scene transition publishes no room-clear fact")
	suite.assert_equal(recorder.floor_completed_events.size(), 0, "rejected scene transition publishes no floor-complete fact")
	var before_finalize_failure: Dictionary = facade.snapshot()
	var revision_changing_adapter := func(_target: Dictionary, _context: Dictionary): return facade.pause_run().ok
	suite.assert_true(
		host.call("configure_route_scene_adapter", revision_changing_adapter),
		"Host accepts a revision-changing route scene adapter"
	)
	var finalize_failed = host.call("select_route", first_edge_id)
	suite.assert_true(not finalize_failed.ok, "stale route finalization fails closed")
	suite.assert_equal(str(finalize_failed.code), "STALE_REVISION", "stale route finalization preserves its diagnostic")
	suite.assert_equal(facade.snapshot(), before_finalize_failure, "stale route finalization restores the exact authoritative snapshot")
	suite.assert_equal(recorder.route_events.size(), 0, "stale route finalization publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "stale route finalization publishes no room-start fact")

	suite.assert_true(
		host.call("configure_route_scene_adapter", func(_target: Dictionary, _context: Dictionary): return true),
		"Host accepts a successful route scene adapter"
	)
	host.call("_publish_floor_started_once", facade.snapshot())
	host.call("_publish_floor_started_once", facade.snapshot())
	suite.assert_equal(recorder.floor_started_events.size(), 1, "floor start publishes exactly once")

	while (facade.snapshot().get("completed_floor_ids", []) as Array).is_empty():
		choices = host.call("route_choices")
		suite.assert_true(not choices.is_empty(), "active Launch node exposes the next route choice")
		if choices.is_empty():
			break
		var edge_id := StringName(str(choices[0].get("edge_id", "")))
		var route_count_before := recorder.route_events.size()
		var room_start_count_before := recorder.room_started_events.size()
		var selected = host.call("select_route", edge_id)
		suite.assert_true(selected.ok, "successful route transition commits")
		if not selected.ok:
			break
		suite.assert_equal(recorder.route_events.size(), route_count_before + 1, "route selection publishes one route fact")
		suite.assert_equal(recorder.room_started_events.size(), room_start_count_before + 1, "route selection publishes one room-start fact")
		var room: Dictionary = facade.current_room_definition()
		var completed = facade.complete_current_room()
		suite.assert_true(completed.ok, "selected Launch room completes through the facade")
		if not completed.ok:
			break
		host.call(
			"_on_room_cleared",
			StringName(str(room.get("node_id", ""))),
			int(completed.new_revision)
		)

	var final_snapshot: Dictionary = facade.snapshot()
	suite.assert_equal((final_snapshot.get("completed_floor_ids", []) as Array).size(), 1, "first Launch floor completes once")
	suite.assert_equal(recorder.route_events.size(), recorder.room_started_events.size(), "every committed route publishes one room start")
	suite.assert_equal(recorder.route_events.size(), recorder.room_cleared_events.size(), "every entered room publishes one room clear")
	suite.assert_equal(recorder.floor_completed_events.size(), 1, "floor completion publishes exactly once")
	host.call("_publish_floor_completed_if_new", final_snapshot, int(final_snapshot.get("revision", 0)))
	suite.assert_equal(recorder.floor_completed_events.size(), 1, "duplicate floor-completion publication is suppressed")

	_disconnect_route_recorder(recorder)
	host.free()


func _test_runtime_host_launch_start_failure_is_atomic(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "atomic Launch start fixture boots")
	if not booted.ok:
		return
	var registry: RefCounted = facade.content_registry()
	var definitions: Dictionary = (registry.get("_definitions") as Dictionary).duplicate(true)
	definitions.erase("floor_throne_of_void")
	registry.set("_definitions", definitions)
	var before: Dictionary = facade.snapshot()

	var host := RunRuntimeHostScript.new()
	add_child(host)
	var dummy_controller := Node.new()
	var dummy_player := Node.new()
	host.add_child(dummy_controller)
	host.add_child(dummy_player)
	host.set("_active", true)
	host.set("_room_controller", dummy_controller)
	host.set("_player", dummy_player)
	host.set("_facade", facade)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)
	var failed = host.call("start_run", _launch_config())
	suite.assert_true(not failed.ok, "incomplete Launch content rejects run start")
	suite.assert_equal(facade.snapshot(), before, "rejected Launch start preserves the exact Hub snapshot")
	suite.assert_equal(recorder.run_started_events.size(), 0, "rejected Launch start publishes no run fact")
	suite.assert_equal(recorder.floor_started_events.size(), 0, "rejected Launch start publishes no floor fact")
	suite.assert_equal(recorder.route_events.size(), 0, "rejected Launch start publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "rejected Launch start publishes no room fact")

	_disconnect_route_recorder(recorder)
	host.free()


func _advance_one_node(suite, orchestrator, label: String) -> bool:
	var plan: Dictionary = orchestrator.snapshot()["floor_plan"]
	var edge := _first_outgoing_edge(plan)
	if edge.is_empty():
		suite.assert_true(false, "%s current node exposes an outgoing edge" % label)
		return false
	var begun = orchestrator.begin_route_transition(
		StringName(str(edge["id"])), orchestrator.revision()
	)
	if not begun.ok:
		suite.assert_true(false, "%s route begin succeeds" % label)
		return false
	var finalized = orchestrator.finalize_route_transition(
		str(begun.context.get("transition_id", "")), orchestrator.revision()
	)
	if not finalized.ok:
		suite.assert_true(false, "%s route finalize succeeds" % label)
		return false
	var node_id := str(orchestrator.snapshot()["floor_plan"]["current_node_id"])
	if node_id == "boss":
		return true
	var entered = orchestrator.enter_floor_node(node_id, orchestrator.revision())
	if not entered.ok:
		suite.assert_true(false, "%s node enters" % label)
		return false
	var completed = orchestrator.complete_floor_node(node_id, orchestrator.revision())
	if not completed.ok:
		suite.assert_true(false, "%s node completes" % label)
		return false
	return true


func _started_launch(run_id: String):
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_launch_config(), run_id)
	return orchestrator


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}


func _connect_route_recorder(recorder: RouteLifecycleRecorder) -> void:
	EventBus.run_started.connect(recorder.record_run_started)
	EventBus.route_selected.connect(recorder.record_route_selected)
	EventBus.room_started.connect(recorder.record_room_started)
	EventBus.room_cleared.connect(recorder.record_room_cleared)
	EventBus.floor_started.connect(recorder.record_floor_started)
	EventBus.floor_completed.connect(recorder.record_floor_completed)


func _disconnect_route_recorder(recorder: RouteLifecycleRecorder) -> void:
	if EventBus.run_started.is_connected(recorder.record_run_started):
		EventBus.run_started.disconnect(recorder.record_run_started)
	if EventBus.route_selected.is_connected(recorder.record_route_selected):
		EventBus.route_selected.disconnect(recorder.record_route_selected)
	if EventBus.room_started.is_connected(recorder.record_room_started):
		EventBus.room_started.disconnect(recorder.record_room_started)
	if EventBus.room_cleared.is_connected(recorder.record_room_cleared):
		EventBus.room_cleared.disconnect(recorder.record_room_cleared)
	if EventBus.floor_started.is_connected(recorder.record_floor_started):
		EventBus.floor_started.disconnect(recorder.record_floor_started)
	if EventBus.floor_completed.is_connected(recorder.record_floor_completed):
		EventBus.floor_completed.disconnect(recorder.record_floor_completed)


func _first_outgoing_edge(plan: Dictionary) -> Dictionary:
	var source_id := str(plan.get("current_node_id", ""))
	for edge_value: Variant in plan.get("edges", []):
		var edge: Dictionary = edge_value
		if str(edge.get("source_node_id", "")) == source_id and not bool(edge.get("locked", false)):
			return edge.duplicate(true)
	return {}


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []
