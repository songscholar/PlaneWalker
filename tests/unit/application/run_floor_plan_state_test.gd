extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")

const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const LAUNCH_FIELDS: Array[String] = [
	"current_floor_index",
	"floor_plan",
	"completed_floor_ids",
	"run_economy",
	"seen_event_ids",
	"merchant_state",
	"floor_rule_state",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var floors: Array = _load_json_array(FLOOR_PATH)
	var templates: Array = _load_json_array(TEMPLATE_PATH)
	suite.assert_equal(floors.size(), 5, "state fixture exposes five floors")
	suite.assert_equal(templates.size(), 30, "state fixture exposes thirty room templates")
	if floors.size() != 5 or templates.size() != 30:
		suite.finish(get_tree())
		return
	_test_empty_launch_domain(suite)
	_test_strict_restore_cross_field_invariants(suite, floors[0], templates)
	_test_floor_plan_transaction(suite, floors[0], templates)
	_test_death_compensates_pending_route(suite, floors[0], templates)
	_test_death_route_rollback_failure_is_integrity_failure(suite, floors[0], templates)
	_test_m1_compatibility_boundary(suite, floors[0], templates)
	suite.finish(get_tree())


func _test_empty_launch_domain(suite) -> void:
	var orchestrator = _started_orchestrator("LAUNCH", "run-floor-state-empty")
	var snapshot: Dictionary = orchestrator.snapshot()
	for field: String in LAUNCH_FIELDS:
		suite.assert_true(snapshot.has(field), "Launch snapshot owns %s" % field)
	suite.assert_equal(snapshot.get("current_floor_index"), -1, "Launch starts before floor zero")
	suite.assert_equal(snapshot.get("floor_plan"), {}, "Launch starts without an invented FloorPlan")
	suite.assert_equal(snapshot.get("completed_floor_ids"), [], "Launch starts without completed floors")
	suite.assert_equal(snapshot.get("run_economy"), {}, "P14C leaves economy authority empty")
	suite.assert_equal(snapshot.get("seen_event_ids"), [], "Launch starts without seen events")
	suite.assert_equal(snapshot.get("merchant_state"), {}, "P14C leaves merchant authority empty")
	suite.assert_equal(snapshot.get("floor_rule_state"), {}, "P14C leaves floor-rule authority empty")


func _test_strict_restore_cross_field_invariants(
	suite,
	floor: Dictionary,
	templates: Array
) -> void:
	var empty = _started_orchestrator("LAUNCH", "run-floor-restore-empty")
	var canonical_empty: Dictionary = empty.floor_transaction_snapshot()
	suite.assert_true(
		empty.can_restore_floor_transaction_snapshot(canonical_empty),
		"canonical pre-floor Launch transaction is restorable"
	)
	var forged_empty_cases: Array[Dictionary] = [
		{"field": "current_floor", "value": 2, "label": "pre-floor current_floor drift"},
		{"field": "current_room", "value": 1, "label": "pre-floor current_room drift"},
		{"field": "room_total", "value": 6, "label": "pre-floor room_total drift"},
		{"field": "completed_floor_ids", "value": ["floor_ruins_of_remnant"], "label": "pre-floor completed prefix drift"},
		{"field": "run_economy", "value": {"gold": 1}, "label": "pre-floor economy drift"},
		{"field": "seen_event_ids", "value": ["event_cursed_pool"], "label": "pre-floor event drift"},
		{"field": "merchant_state", "value": {"merchant": true}, "label": "pre-floor merchant drift"},
		{"field": "floor_rule_state", "value": {"rule": true}, "label": "pre-floor rule drift"},
		{"field": "floor_definition", "value": floor.duplicate(true), "label": "pre-floor definition drift"},
		{"field": "room_templates", "value": [templates[0]], "label": "pre-floor template drift"},
		{"field": "phase", "value": RunPhaseScript.Value.HUB, "label": "pre-floor hub phase drift"},
		{"field": "phase", "value": RunPhaseScript.Value.VICTORY, "label": "pre-floor terminal phase drift"},
	]
	for case: Dictionary in forged_empty_cases:
		var forged := canonical_empty.duplicate(true)
		forged[str(case["field"])] = case["value"]
		_assert_floor_restore_rejected(suite, empty, forged, str(case["label"]))

	for milestone: String in ["M1", "CURRENT", "NEXT"]:
		var legacy = _started_orchestrator(
			milestone, "run-floor-restore-%s" % milestone.to_lower()
		)
		var legacy_snapshot: Dictionary = legacy.floor_transaction_snapshot()
		suite.assert_true(
			not legacy.can_restore_floor_transaction_snapshot(legacy_snapshot),
			"%s rejects a shape-valid floor transaction snapshot" % milestone
		)
		suite.assert_true(
			not legacy.restore_floor_transaction_snapshot(legacy_snapshot),
			"%s cannot restore Launch floor authority" % milestone
		)

	var active = _started_orchestrator("LAUNCH", "run-floor-restore-active")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "strict restore fixture generates")
		return
	active.start_floor(generated["plan"], floor, templates, active.revision())
	var canonical_active: Dictionary = active.floor_transaction_snapshot()
	suite.assert_true(
		active.can_restore_floor_transaction_snapshot(canonical_active),
		"canonical active-floor transaction is restorable"
	)
	var seed_drift := canonical_active.duplicate(true)
	seed_drift["run_seed"] = int(seed_drift["run_seed"]) + 1
	_assert_floor_restore_rejected(suite, active, seed_drift, "transaction seed drift")
	var room_total_drift := canonical_active.duplicate(true)
	room_total_drift["room_total"] = int(room_total_drift["room_total"]) + 1
	_assert_floor_restore_rejected(suite, active, room_total_drift, "room_total authority drift")
	var completed_identity_drift := canonical_active.duplicate(true)
	completed_identity_drift["completed_floor_ids"] = ["floor_void_forest"]
	_assert_floor_restore_rejected(suite, active, completed_identity_drift, "completed floor identity drift")
	var completed_too_early := canonical_active.duplicate(true)
	completed_too_early["completed_floor_ids"] = [str(floor["id"])]
	_assert_floor_restore_rejected(suite, active, completed_too_early, "uncleared current floor completion drift")
	for invalid_phase: int in [
		RunPhaseScript.Value.HUB,
		RunPhaseScript.Value.COMBAT_ACTIVE,
		RunPhaseScript.Value.ROOM_ENTERING,
		RunPhaseScript.Value.ROOM_TRANSITION,
		RunPhaseScript.Value.DEFEAT,
	]:
		var phase_drift := canonical_active.duplicate(true)
		phase_drift["phase"] = invalid_phase
		_assert_floor_restore_rejected(
			suite,
			active,
			phase_drift,
			"entry phase drift %d" % invalid_phase
		)

	var mismatched_state = _started_orchestrator("LAUNCH", "run-floor-restore-state-seed")
	var state: RefCounted = mismatched_state.get("_state")
	state.set("run_seed", 20261002)
	var mismatched_seed_snapshot: Dictionary = mismatched_state.floor_transaction_snapshot()
	suite.assert_true(
		not mismatched_state.can_restore_floor_transaction_snapshot(mismatched_seed_snapshot),
		"RunState seed drift from config.seed rejects restore"
	)


func _test_floor_plan_transaction(suite, floor: Dictionary, templates: Array) -> void:
	var orchestrator = _started_orchestrator("LAUNCH", "run-floor-state-transaction")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	suite.assert_true(bool(generated.get("ok", false)), "transaction fixture generates a FloorPlan")
	if not bool(generated.get("ok", false)):
		return
	var plan: Dictionary = generated["plan"]
	var stale_start = orchestrator.start_floor(plan, floor, templates, orchestrator.revision() - 1)
	suite.assert_equal(stale_start.code, &"STALE_REVISION", "stale floor start is rejected")
	var before_start: Dictionary = orchestrator.snapshot()
	var started = orchestrator.start_floor(plan, floor, templates, orchestrator.revision())
	suite.assert_true(started.ok, "valid FloorPlan starts")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_ACTIVE, "floor entry staging becomes active")
	var start_snapshot: Dictionary = orchestrator.snapshot()
	suite.assert_equal(start_snapshot.get("current_floor_index"), 0, "floor index is zero based")
	suite.assert_equal(start_snapshot.get("current_floor"), 1, "legacy floor adapter remains one based")
	suite.assert_equal(start_snapshot.get("current_room"), 0, "entry staging is not an actionable room")
	suite.assert_equal(start_snapshot.get("room_total"), int(floor["route_room_min"]), "room total follows floor authority")
	suite.assert_equal(start_snapshot.get("floor_plan"), plan, "RunState owns the generated plan snapshot")
	suite.assert_true(start_snapshot != before_start, "accepted floor start mutates authority")

	var exposed: Dictionary = orchestrator.snapshot()
	exposed["floor_plan"]["current_node_id"] = "forged"
	exposed["completed_floor_ids"].append("forged")
	suite.assert_equal(orchestrator.snapshot().get("floor_plan"), plan, "public FloorPlan snapshot is isolated")
	suite.assert_equal(orchestrator.snapshot().get("completed_floor_ids"), [], "public floor history is isolated")

	var initial: Dictionary = orchestrator.snapshot()
	var edge: Dictionary = _first_outgoing_edge(initial["floor_plan"])
	suite.assert_true(not edge.is_empty(), "entry exposes a route choice")
	if edge.is_empty():
		return
	var stale_route = orchestrator.begin_route_transition(
		StringName(str(edge["id"])), orchestrator.revision() - 1
	)
	suite.assert_equal(stale_route.code, &"STALE_REVISION", "stale route selection is rejected")
	suite.assert_equal(orchestrator.snapshot(), initial, "stale route selection is atomic")

	var transaction_before: Dictionary = orchestrator.floor_transaction_snapshot()
	var begun = orchestrator.select_route(StringName(str(edge["id"])), orchestrator.revision())
	suite.assert_true(begun.ok, "select_route begins a staged route transaction")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_TRANSITION, "route staging owns the transition phase")
	var transaction_id := str(begun.context.get("transition_id", ""))
	suite.assert_true(not transaction_id.is_empty(), "route staging returns a stable transaction id")
	suite.assert_equal(
		orchestrator.snapshot().get("floor_plan", {}).get("current_node_id"),
		edge.get("destination_node_id"),
		"staged selection advances the authoritative node"
	)
	suite.assert_equal(orchestrator.snapshot().get("current_room"), 1, "first selected node is room one")
	var duplicate_before: Dictionary = orchestrator.snapshot()
	var duplicate = orchestrator.begin_route_transition(
		StringName(str(edge["id"])), orchestrator.revision()
	)
	suite.assert_equal(duplicate.code, &"INVALID_PHASE", "a pending route transaction rejects a second begin")
	suite.assert_equal(orchestrator.snapshot(), duplicate_before, "duplicate begin cannot mutate authority")

	var wrong_rollback = orchestrator.rollback_route_transition("wrong", orchestrator.revision())
	suite.assert_equal(wrong_rollback.code, &"INVALID_ARGUMENT", "wrong rollback token is rejected")
	suite.assert_equal(orchestrator.snapshot(), duplicate_before, "wrong rollback token preserves authority")
	var rolled_back = orchestrator.rollback_route_transition(transaction_id, orchestrator.revision())
	suite.assert_true(rolled_back.ok, "scene failure can compensate a staged route")
	suite.assert_equal(orchestrator.floor_transaction_snapshot(), transaction_before, "rollback restores exact floor authority")

	var begun_again = orchestrator.begin_route_transition(
		StringName(str(edge["id"])), orchestrator.revision()
	)
	suite.assert_true(begun_again.ok, "route can be retried after exact rollback")
	transaction_id = str(begun_again.context.get("transition_id", ""))
	var before_wrong_finalize: Dictionary = orchestrator.snapshot()
	var wrong_finalize = orchestrator.finalize_route_transition("wrong", orchestrator.revision())
	suite.assert_equal(wrong_finalize.code, &"INVALID_ARGUMENT", "wrong finalize token is rejected")
	suite.assert_equal(orchestrator.snapshot(), before_wrong_finalize, "wrong finalize token preserves authority")
	var finalized = orchestrator.finalize_route_transition(transaction_id, orchestrator.revision())
	suite.assert_true(finalized.ok, "validated scene transition finalizes")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_ENTERING, "finalized route enters the selected node")

	var node_id := str(orchestrator.snapshot().get("floor_plan", {}).get("current_node_id", ""))
	var wrong_entry = orchestrator.enter_floor_node("wrong", orchestrator.revision())
	suite.assert_equal(wrong_entry.code, &"INVALID_ARGUMENT", "wrong node entry is rejected")
	var entered = orchestrator.enter_floor_node(node_id, orchestrator.revision())
	suite.assert_true(entered.ok, "selected node enters")
	var node: Dictionary = _node_by_id(orchestrator.snapshot()["floor_plan"], node_id)
	suite.assert_equal(orchestrator.phase(), _active_phase(str(node["room_type"])), "room type selects the active phase")
	var before_wrong_clear: Dictionary = orchestrator.snapshot()
	var wrong_clear = orchestrator.complete_floor_node("wrong", orchestrator.revision())
	suite.assert_equal(wrong_clear.code, &"INVALID_ARGUMENT", "wrong node completion is rejected")
	suite.assert_equal(orchestrator.snapshot(), before_wrong_clear, "wrong node completion is atomic")
	var cleared = orchestrator.complete_floor_node(node_id, orchestrator.revision())
	suite.assert_true(cleared.ok, "current node completes")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_RESOLVING, "completed node opens route resolution")
	suite.assert_equal(
		_node_by_id(orchestrator.snapshot()["floor_plan"], node_id).get("cleared"),
		true,
		"completed node is sealed in the FloorPlan"
	)

	var strict_snapshot: Dictionary = orchestrator.floor_transaction_snapshot()
	var forged := strict_snapshot.duplicate(true)
	forged["unknown"] = true
	suite.assert_true(not orchestrator.restore_floor_transaction_snapshot(forged), "transaction restore rejects extra fields")
	suite.assert_equal(orchestrator.floor_transaction_snapshot(), strict_snapshot, "rejected transaction restore is atomic")


func _test_m1_compatibility_boundary(suite, floor: Dictionary, templates: Array) -> void:
	var orchestrator = _started_orchestrator("M1", "run-floor-state-m1")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "M1 boundary fixture generates")
		return
	var before: Dictionary = orchestrator.snapshot()
	var rejected = orchestrator.start_floor(
		generated["plan"], floor, templates, orchestrator.revision()
	)
	suite.assert_equal(rejected.code, &"INVALID_ARGUMENT", "M1 cannot reinterpret its five rooms as a FloorPlan")
	suite.assert_equal(orchestrator.snapshot(), before, "rejected M1 FloorPlan leaves authority exact")
	suite.assert_equal(before.get("current_floor_index"), -1, "M1 exposes the empty compatibility floor index")
	suite.assert_equal(before.get("floor_plan"), {}, "M1 exposes no FloorPlan")
	suite.assert_true(orchestrator.preparation_completed().ok, "M1 preparation flow remains accepted")
	suite.assert_true(orchestrator.room_entered(false).ok, "M1 room flow remains accepted")


func _assert_floor_restore_rejected(
	suite,
	orchestrator,
	forged: Dictionary,
	label: String
) -> void:
	var before: Dictionary = orchestrator.floor_transaction_snapshot()
	suite.assert_true(
		not orchestrator.can_restore_floor_transaction_snapshot(forged),
		"%s cannot validate" % label
	)
	suite.assert_true(
		not orchestrator.restore_floor_transaction_snapshot(forged),
		"%s cannot restore" % label
	)
	suite.assert_equal(
		orchestrator.floor_transaction_snapshot(),
		before,
		"%s rejection is atomic" % label
	)


func _test_death_compensates_pending_route(
	suite,
	floor: Dictionary,
	templates: Array
) -> void:
	var orchestrator = _started_orchestrator("LAUNCH", "run-floor-state-death")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "death compensation fixture generates")
		return
	orchestrator.start_floor(generated["plan"], floor, templates, orchestrator.revision())
	var before_begin: Dictionary = orchestrator.snapshot()
	var before_revision: int = int(orchestrator.revision())
	var edge: Dictionary = _first_outgoing_edge(before_begin["floor_plan"])
	var begun = orchestrator.begin_route_transition(
		StringName(str(edge.get("id", ""))), before_revision
	)
	suite.assert_true(begun.ok, "death compensation fixture stages a route")
	suite.assert_true(
		orchestrator.snapshot().get("floor_plan") != before_begin.get("floor_plan"),
		"staged route advances authority before compensation"
	)
	var died = orchestrator.player_died({"result": "death", "source": "staged_route"})
	suite.assert_true(died.ok, "death compensates the pending route before committing defeat")
	var after: Dictionary = orchestrator.snapshot()
	suite.assert_equal(after.get("phase"), RunPhaseScript.Value.DEFEAT, "compensated death enters Defeat")
	suite.assert_equal(after.get("floor_plan"), before_begin.get("floor_plan"), "death restores the pre-begin FloorPlan")
	suite.assert_equal(after.get("current_room"), before_begin.get("current_room"), "death restores the pre-begin room cursor")
	suite.assert_equal(after.get("current_floor_index"), before_begin.get("current_floor_index"), "death preserves the active floor identity")
	suite.assert_equal(after.get("revision"), before_revision + 1, "only the death command advances revision once")
	suite.assert_equal(after.get("result", {}).get("source"), "staged_route", "death context commits after compensation")
	suite.assert_equal(
		orchestrator.get("_pending_route_transition"),
		{},
		"committed death owns no pending route transaction"
	)


func _test_death_route_rollback_failure_is_integrity_failure(
	suite,
	floor: Dictionary,
	templates: Array
) -> void:
	var orchestrator = _started_orchestrator("LAUNCH", "run-floor-state-death-integrity")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "death integrity fixture generates")
		return
	orchestrator.start_floor(generated["plan"], floor, templates, orchestrator.revision())
	var edge: Dictionary = _first_outgoing_edge(orchestrator.snapshot()["floor_plan"])
	var begun = orchestrator.begin_route_transition(
		StringName(str(edge.get("id", ""))), orchestrator.revision()
	)
	suite.assert_true(begun.ok, "death integrity fixture stages a route")
	var pending: Dictionary = orchestrator.get("_pending_route_transition")
	var broken_before: Dictionary = (pending.get("before", {}) as Dictionary).duplicate(true)
	broken_before["unknown"] = true
	pending["before"] = broken_before
	var staged: Dictionary = orchestrator.snapshot()
	var result = orchestrator.player_died({"result": "death"})
	suite.assert_equal(result.code, &"INTEGRITY_FAILURE", "failed death compensation reports integrity failure")
	suite.assert_equal(result.context.get("stage"), "route_transition_death_rollback", "integrity failure identifies death rollback")
	suite.assert_equal(orchestrator.snapshot(), staged, "failed compensation cannot commit Defeat or mutate staged authority")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_TRANSITION, "failed compensation keeps the pending transition phase")
	suite.assert_equal(
		str((orchestrator.get("_pending_route_transition") as Dictionary).get("transition_id", "")),
		str(begun.context.get("transition_id", "")),
		"failed compensation retains the pending transaction for recovery"
	)


func _started_orchestrator(milestone: String, run_id: String):
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(milestone), run_id)
	return orchestrator


func _config(milestone: String) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}


func _first_outgoing_edge(plan: Dictionary) -> Dictionary:
	var source_id := str(plan.get("current_node_id", ""))
	for edge_value: Variant in plan.get("edges", []):
		var edge: Dictionary = edge_value
		if str(edge.get("source_node_id", "")) == source_id and not bool(edge.get("locked", false)):
			return edge.duplicate(true)
	return {}


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		var node: Dictionary = node_value
		if str(node.get("id", "")) == node_id:
			return node.duplicate(true)
	return {}


func _active_phase(room_type: String) -> int:
	if room_type == "boss":
		return RunPhaseScript.Value.BOSS_ACTIVE
	if room_type == "combat" or room_type == "elite":
		return RunPhaseScript.Value.COMBAT_ACTIVE
	return RunPhaseScript.Value.ROOM_ACTIVE


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []
