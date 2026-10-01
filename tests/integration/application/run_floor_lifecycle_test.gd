extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")

const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


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
	orchestrator.start_run({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}, run_id)
	return orchestrator


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
