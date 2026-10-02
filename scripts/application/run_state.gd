class_name RunState
extends RefCounted

const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")

const REWARD_REPLAY_MILESTONES: Array[String] = ["LAUNCH", "EXPANSION"]

var run_id: String = ""
var revision: int = 0
var phase: int = RunPhaseScript.Value.BOOT
var suspended: bool = false
var run_seed: int = 0
var current_floor: int = 1
var current_room: int = 0
var room_total: int = 5
var run_time_ms: int = 0
var _run_time_fraction_ms: float = 0.0
var resources: Dictionary = {}
var stats: Dictionary = {"kills": 0}
var events: Array = []
var build_state: RefCounted
var open_offer: Dictionary = {}
var consumed_offer_ids: Dictionary = {}
var result: Dictionary = {}
var config: Dictionary = {}
var current_floor_index: int = -1
var floor_plan: Dictionary = {}
var completed_floor_ids: Array[String] = []
var run_economy: Dictionary = {}
var seen_event_ids: Array[String] = []
var merchant_state: Dictionary = {}
var floor_rule_state: Dictionary = {}

var _floor_definition: Dictionary = {}
var _room_templates: Array = []

const SELECTION_TRANSACTION_FIELDS: Array[String] = [
	"schema_version",
	"revision",
	"phase",
	"suspended",
	"current_room",
	"open_offer",
	"consumed_offer_ids",
	"build",
]
const FLOOR_TRANSACTION_FIELDS: Array[String] = [
	"schema_version",
	"revision",
	"phase",
	"suspended",
	"run_seed",
	"current_floor",
	"current_room",
	"room_total",
	"current_floor_index",
	"floor_plan",
	"completed_floor_ids",
	"run_economy",
	"seen_event_ids",
	"merchant_state",
	"floor_rule_state",
	"floor_definition",
	"room_templates",
]
const FLOOR_RULE_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"rule_id",
	"configured",
	"room_id",
	"room_seed",
	"zones",
	"safe_zone_ids",
	"runtime_frame",
	"phase",
	"cycle_index",
	"active_zone_id",
	"revision",
	"reduced_motion",
	"hit_flash_enabled",
]


func _init() -> void:
	build_state = RunBuildStateScript.new()


func reset_domain(p_config: Dictionary, p_run_id: String) -> void:
	config = RunConfigScript.normalized(p_config)
	run_id = p_run_id
	suspended = false
	run_seed = int(config["seed"])
	current_floor = 1
	current_room = 0
	room_total = 5
	run_time_ms = 0
	_run_time_fraction_ms = 0.0
	resources = {}
	stats = {"kills": 0}
	events = []
	if build_state == null:
		build_state = RunBuildStateScript.new()
	build_state.reset(str(config["milestone"]))
	open_offer = {}
	consumed_offer_ids = {}
	result = {}
	current_floor_index = -1
	floor_plan = {}
	completed_floor_ids = []
	run_economy = {}
	seen_event_ids = []
	merchant_state = {}
	floor_rule_state = {}
	_floor_definition = {}
	_room_templates = []


func advance_revision() -> int:
	revision += 1
	return revision


func advance_time(delta_seconds: float) -> int:
	var total_ms := _run_time_fraction_ms + maxf(0.0, delta_seconds) * 1000.0
	var whole_ms := int(floor(total_ms + 0.000001))
	_run_time_fraction_ms = total_ms - float(whole_ms)
	run_time_ms += whole_ms
	return whole_ms


func is_terminal() -> bool:
	return RunPhaseScript.is_terminal(phase)


func has_consumed_offer(offer_id: String) -> bool:
	return consumed_offer_ids.has(offer_id)


func mark_offer_consumed(offer_id: String) -> bool:
	if offer_id.is_empty() or has_consumed_offer(offer_id):
		return false
	consumed_offer_ids[offer_id] = true
	return true


func selection_transaction_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"revision": revision,
		"phase": phase,
		"suspended": suspended,
		"current_room": current_room,
		"open_offer": open_offer.duplicate(true),
		"consumed_offer_ids": consumed_offer_ids.duplicate(true),
		"build": build_state.transaction_snapshot(),
	}


func can_restore_selection_transaction_snapshot(value: Dictionary) -> bool:
	if value.size() != SELECTION_TRANSACTION_FIELDS.size():
		return false
	for field: String in SELECTION_TRANSACTION_FIELDS:
		if not value.has(field):
			return false
	return (
		typeof(value["schema_version"]) == TYPE_INT
		and int(value["schema_version"]) == 1
		and typeof(value["revision"]) == TYPE_INT
		and int(value["revision"]) >= 0
		and typeof(value["phase"]) == TYPE_INT
		and typeof(value["suspended"]) == TYPE_BOOL
		and typeof(value["current_room"]) == TYPE_INT
		and int(value["current_room"]) > 0
		and value["open_offer"] is Dictionary
		and value["consumed_offer_ids"] is Dictionary
		and value["build"] is Dictionary
		and build_state.can_restore_transaction_snapshot(value["build"] as Dictionary)
	)


func restore_selection_transaction_snapshot(value: Dictionary) -> bool:
	if not can_restore_selection_transaction_snapshot(value):
		return false
	if not build_state.restore_transaction_snapshot(value["build"] as Dictionary):
		return false
	revision = int(value["revision"])
	phase = int(value["phase"])
	suspended = bool(value["suspended"])
	current_room = int(value["current_room"])
	open_offer = (value["open_offer"] as Dictionary).duplicate(true)
	consumed_offer_ids = (value["consumed_offer_ids"] as Dictionary).duplicate(true)
	return selection_transaction_snapshot() == value


func has_active_floor_plan() -> bool:
	return not floor_plan.is_empty()


func is_launch_floor_mode() -> bool:
	return str(config.get("milestone", "")) in ["LAUNCH", "EXPANSION"]


func configure_floor_plan(
	value: Dictionary,
	floor_definition: Dictionary,
	room_templates: Array
) -> Dictionary:
	if not is_launch_floor_mode():
		return {
			"ok": false,
			"code": &"INVALID_ARGUMENT",
			"context": {"field": "config.milestone", "reason": "floor_plan_not_supported"},
		}
	var candidate = FloorPlanScript.new()
	var configured: Dictionary = candidate.configure(value, floor_definition, room_templates)
	if not bool(configured.get("ok", false)):
		return {
			"ok": false,
			"code": &"INVALID_ARGUMENT",
			"context": configured.get("context", {"field": "floor_plan", "reason": "invalid"}),
		}
	var accepted: Dictionary = candidate.snapshot()
	if int(accepted.get("run_seed", 0)) != run_seed:
		return {
			"ok": false,
			"code": &"INVALID_ARGUMENT",
			"context": {"field": "floor_plan.run_seed", "reason": "run_seed_mismatch"},
		}
	floor_plan = accepted
	_floor_definition = floor_definition.duplicate(true)
	_room_templates = room_templates.duplicate(true)
	current_floor_index = int(floor_plan["floor_index"])
	current_floor = current_floor_index + 1
	current_room = (floor_plan["selected_edge_ids"] as Array).size()
	room_total = int(floor_definition.get("route_room_min", 0))
	floor_rule_state = {}
	return {"ok": true, "plan": floor_plan.duplicate(true), "context": {}}


func current_floor_node() -> Dictionary:
	var current_node_id := str(floor_plan.get("current_node_id", ""))
	for node_value: Variant in floor_plan.get("nodes", []):
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		if str(node.get("id", "")) == current_node_id:
			return node.duplicate(true)
	return {}


func select_floor_edge(edge_id: StringName) -> Dictionary:
	var candidate = _configured_floor_plan(floor_plan, _floor_definition, _room_templates)
	if candidate == null:
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "context": {"field": "floor_plan"}}
	var current_node := current_floor_node()
	if current_node.is_empty() or not bool(current_node.get("cleared", false)):
		return {
			"ok": false,
			"code": &"INVALID_PHASE",
			"context": {"operation": "select_route", "reason": "current_node_not_cleared"},
		}
	var selected: Dictionary = candidate.select_edge(edge_id, candidate.revision())
	if not bool(selected.get("ok", false)):
		return selected.duplicate(true)
	floor_plan = candidate.snapshot()
	current_room = (floor_plan["selected_edge_ids"] as Array).size()
	floor_rule_state = {}
	return {
		"ok": true,
		"new_revision": int(selected.get("new_revision", -1)),
		"node_id": StringName(str(selected.get("node_id", ""))),
		"plan": floor_plan.duplicate(true),
	}


func can_commit_floor_rule_state(value: Dictionary) -> bool:
	var current_node := current_floor_node()
	return (
		not current_node.is_empty()
		and not bool(current_node.get("cleared", false))
		and _floor_rule_state_matches_context(
			value, floor_plan, _floor_definition, current_node, phase
		)
	)


func commit_floor_rule_state(value: Dictionary) -> bool:
	if not can_commit_floor_rule_state(value):
		return false
	floor_rule_state = value.duplicate(true)
	return true


func clear_floor_rule_state() -> void:
	floor_rule_state = {}


func complete_current_floor_node(node_id: String) -> Dictionary:
	var node := current_floor_node()
	if (
		node.is_empty()
		or node_id.is_empty()
		or node_id != str(node.get("id", ""))
		or node_id == str(floor_plan.get("entry_node_id", "entry"))
		or not bool(node.get("visited", false))
		or bool(node.get("cleared", false))
	):
		return {
			"ok": false,
			"code": &"INVALID_ARGUMENT",
			"context": {"field": "node_id", "node_id": node_id},
		}
	var candidate_snapshot := floor_plan.duplicate(true)
	for node_value: Variant in candidate_snapshot["nodes"]:
		var candidate_node: Dictionary = node_value
		if str(candidate_node.get("id", "")) == node_id:
			candidate_node["cleared"] = true
			break
	var candidate = _configured_floor_plan(
		candidate_snapshot, _floor_definition, _room_templates
	)
	if candidate == null:
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "context": {"field": "floor_plan"}}
	floor_plan = candidate.snapshot()
	return {"ok": true, "node": current_floor_node(), "plan": floor_plan.duplicate(true)}


func append_completed_floor() -> bool:
	if floor_plan.is_empty():
		return false
	var floor_id := str(floor_plan.get("floor_id", ""))
	if (
		floor_id.is_empty()
		or completed_floor_ids.has(floor_id)
		or completed_floor_ids.size() != current_floor_index
	):
		return false
	completed_floor_ids.append(floor_id)
	floor_rule_state = {}
	return true


func floor_transaction_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"revision": revision,
		"phase": phase,
		"suspended": suspended,
		"run_seed": run_seed,
		"current_floor": current_floor,
		"current_room": current_room,
		"room_total": room_total,
		"current_floor_index": current_floor_index,
		"floor_plan": floor_plan.duplicate(true),
		"completed_floor_ids": completed_floor_ids.duplicate(),
		"run_economy": run_economy.duplicate(true),
		"seen_event_ids": seen_event_ids.duplicate(),
		"merchant_state": merchant_state.duplicate(true),
		"floor_rule_state": floor_rule_state.duplicate(true),
		"floor_definition": _floor_definition.duplicate(true),
		"room_templates": _room_templates.duplicate(true),
	}


func can_restore_floor_transaction_snapshot(value: Dictionary) -> bool:
	if not is_launch_floor_mode():
		return false
	if value.size() != FLOOR_TRANSACTION_FIELDS.size():
		return false
	for field: String in FLOOR_TRANSACTION_FIELDS:
		if not value.has(field):
			return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != 1
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
		or typeof(value["phase"]) != TYPE_INT
		or typeof(value["suspended"]) != TYPE_BOOL
		or typeof(value["run_seed"]) != TYPE_INT
		or typeof(value["current_floor"]) != TYPE_INT
		or int(value["current_floor"]) < 0
		or typeof(value["current_room"]) != TYPE_INT
		or int(value["current_room"]) < 0
		or typeof(value["room_total"]) != TYPE_INT
		or int(value["room_total"]) < 0
		or typeof(value["current_floor_index"]) != TYPE_INT
		or int(value["current_floor_index"]) < -1
		or not value["floor_plan"] is Dictionary
		or not value["completed_floor_ids"] is Array
		or not value["run_economy"] is Dictionary
		or not value["seen_event_ids"] is Array
		or not value["merchant_state"] is Dictionary
		or not value["floor_rule_state"] is Dictionary
		or not value["floor_definition"] is Dictionary
		or not value["room_templates"] is Array
	):
		return false
	if not _is_unique_string_array(value["completed_floor_ids"]):
		return false
	if not _is_unique_string_array(value["seen_event_ids"]):
		return false
	if (
		typeof(config.get("seed")) != TYPE_INT
		or int(value["run_seed"]) != run_seed
		or int(value["run_seed"]) != int(config["seed"])
	):
		return false
	var plan: Dictionary = value["floor_plan"]
	var floor_definition: Dictionary = value["floor_definition"]
	var room_templates: Array = value["room_templates"]
	var floor_index := int(value["current_floor_index"])
	if plan.is_empty():
		return (
			floor_index == -1
			and int(value["current_floor"]) == 1
			and int(value["current_room"]) == 0
			and int(value["room_total"]) == 5
			and int(value["phase"]) == RunPhaseScript.Value.RUN_PREPARING
			and (value["completed_floor_ids"] as Array).is_empty()
			and (value["run_economy"] as Dictionary).is_empty()
			and (value["seen_event_ids"] as Array).is_empty()
			and (value["merchant_state"] as Dictionary).is_empty()
			and (value["floor_rule_state"] as Dictionary).is_empty()
			and floor_definition.is_empty()
			and room_templates.is_empty()
		)
	if floor_index < 0 or floor_index >= FloorDefinitionScript.FLOOR_IDS.size():
		return false
	if int(value["current_floor"]) != floor_index + 1:
		return false
	if int(plan.get("floor_index", -1)) != floor_index:
		return false
	if int(plan.get("run_seed", 0)) != int(value["run_seed"]):
		return false
	if int(value["current_room"]) != (plan.get("selected_edge_ids", []) as Array).size():
		return false
	var floor_parser = FloorDefinitionScript.new()
	var floor_result: Dictionary = floor_parser.configure(floor_definition)
	if not bool(floor_result.get("ok", false)):
		return false
	var normalized_floor: Dictionary = floor_result["definition"]
	if (
		int(normalized_floor.get("order", 0)) - 1 != floor_index
		or str(normalized_floor.get("id", "")) != str(plan.get("floor_id", ""))
		or str(plan.get("floor_id", "")) != FloorDefinitionScript.FLOOR_IDS[floor_index]
	):
		return false
	var configured_plan = _configured_floor_plan(plan, floor_definition, room_templates)
	if configured_plan == null:
		return false
	var boss_node := _plan_node_by_id(plan, str(plan.get("boss_node_id", "")))
	if (
		boss_node.is_empty()
		or int(value["room_total"]) != int(normalized_floor.get("route_room_min", 0))
		or int(value["room_total"]) != int(boss_node.get("layer", -1))
	):
		return false
	var prior_completed: Array[String] = []
	for index: int in range(floor_index):
		prior_completed.append(FloorDefinitionScript.FLOOR_IDS[index])
	var current_completed := prior_completed.duplicate()
	current_completed.append(FloorDefinitionScript.FLOOR_IDS[floor_index])
	var completed: Array = value["completed_floor_ids"]
	if completed != prior_completed and completed != current_completed:
		return false
	var current_node := _plan_node_by_id(plan, str(plan.get("current_node_id", "")))
	if current_node.is_empty():
		return false
	var floor_rule_value := value["floor_rule_state"] as Dictionary
	if not floor_rule_value.is_empty() and not _floor_rule_state_matches_context(
		floor_rule_value,
		plan,
		floor_definition,
		current_node,
		int(value["phase"])
	):
		return false
	if completed == current_completed:
		if (
			str(current_node.get("id", "")) != str(plan.get("boss_node_id", ""))
			or not bool(boss_node.get("cleared", false))
			or not floor_rule_value.is_empty()
		):
			return false
		var expected_completed_phase := (
			RunPhaseScript.Value.VICTORY
			if floor_index == FloorDefinitionScript.FLOOR_IDS.size() - 1
			else RunPhaseScript.Value.RUN_PREPARING
		)
		return int(value["phase"]) == expected_completed_phase
	return _active_floor_phase_is_valid(int(value["phase"]), plan, current_node)


func restore_floor_transaction_snapshot(value: Dictionary) -> bool:
	if not can_restore_floor_transaction_snapshot(value):
		return false
	revision = int(value["revision"])
	phase = int(value["phase"])
	suspended = bool(value["suspended"])
	run_seed = int(value["run_seed"])
	current_floor = int(value["current_floor"])
	current_room = int(value["current_room"])
	room_total = int(value["room_total"])
	current_floor_index = int(value["current_floor_index"])
	floor_plan = (value["floor_plan"] as Dictionary).duplicate(true)
	completed_floor_ids.assign(value["completed_floor_ids"] as Array)
	run_economy = (value["run_economy"] as Dictionary).duplicate(true)
	seen_event_ids.assign(value["seen_event_ids"] as Array)
	merchant_state = (value["merchant_state"] as Dictionary).duplicate(true)
	floor_rule_state = (value["floor_rule_state"] as Dictionary).duplicate(true)
	_floor_definition = (value["floor_definition"] as Dictionary).duplicate(true)
	_room_templates = (value["room_templates"] as Array).duplicate(true)
	return floor_transaction_snapshot() == value


func reward_replay_build_snapshot() -> Dictionary:
	if not REWARD_REPLAY_MILESTONES.has(str(config.get("milestone", ""))):
		return {}
	return build_state.transaction_snapshot().duplicate(true)


func can_restore_reward_replay_build_snapshot(value: Dictionary) -> bool:
	var milestone := str(config.get("milestone", ""))
	return (
		REWARD_REPLAY_MILESTONES.has(milestone)
		and str(value.get("milestone", "")) == milestone
		and build_state.can_restore_transaction_snapshot(value)
	)


func restore_reward_replay_build_snapshot(value: Dictionary) -> bool:
	if not can_restore_reward_replay_build_snapshot(value):
		return false
	var before: Dictionary = build_state.transaction_snapshot()
	if (
		build_state.restore_transaction_snapshot(value)
		and build_state.transaction_snapshot() == value
	):
		return true
	if not build_state.restore_transaction_snapshot(before):
		push_error("RunState failed to roll back a rejected reward Replay checkpoint")
	return false


func snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": run_id,
		"revision": revision,
		"phase": phase,
		"suspended": suspended,
		"run_seed": run_seed,
		"current_floor": current_floor,
		"current_room": current_room,
		"room_total": room_total,
		"run_time_ms": run_time_ms,
		"resources": resources.duplicate(true),
		"stats": stats.duplicate(true),
		"events": events.duplicate(true),
		"build": build_state.to_dictionary().duplicate(true),
		"open_offer": open_offer.duplicate(true),
		"consumed_offer_ids": consumed_offer_ids.keys().duplicate(),
		"result": result.duplicate(true),
		"config": config.duplicate(true),
		"current_floor_index": current_floor_index,
		"floor_plan": floor_plan.duplicate(true),
		"completed_floor_ids": completed_floor_ids.duplicate(),
		"run_economy": run_economy.duplicate(true),
		"seen_event_ids": seen_event_ids.duplicate(),
		"merchant_state": merchant_state.duplicate(true),
		"floor_rule_state": floor_rule_state.duplicate(true),
	}


func _configured_floor_plan(
	source: Dictionary,
	floor_definition: Dictionary,
	room_templates: Array
):
	if source.is_empty() or floor_definition.is_empty() or room_templates.is_empty():
		return null
	var candidate = FloorPlanScript.new()
	var configured: Dictionary = candidate.configure(source, floor_definition, room_templates)
	return candidate if bool(configured.get("ok", false)) else null


func _is_unique_string_array(value: Array) -> bool:
	var seen: Dictionary = {}
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or str(entry).is_empty() or seen.has(str(entry)):
			return false
		seen[str(entry)] = true
	return true


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _floor_rule_state_matches_context(
	value: Dictionary,
	plan: Dictionary,
	floor_definition: Dictionary,
	current_node: Dictionary,
	candidate_phase: int
) -> bool:
	if (
		not _has_exact_fields(value, FLOOR_RULE_SNAPSHOT_FIELDS)
		or str(current_node.get("id", "")) == str(plan.get("entry_node_id", "entry"))
		or candidate_phase not in [
			_active_phase_for_room_type(str(current_node.get("room_type", ""))),
			RunPhaseScript.Value.ROOM_RESOLVING,
		]
	):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != 1
		or typeof(value["rule_id"]) != TYPE_STRING
		or str(value["rule_id"]) != str(floor_definition.get("environment_rule_id", ""))
		or typeof(value["configured"]) != TYPE_BOOL
		or not bool(value["configured"])
		or typeof(value["room_id"]) != TYPE_STRING
		or str(value["room_id"]) != str(current_node.get("id", ""))
		or typeof(value["room_seed"]) != TYPE_INT
		or not value["zones"] is Array
		or not value["safe_zone_ids"] is Array
		or (value["zones"] as Array).is_empty()
		or (value["safe_zone_ids"] as Array).is_empty()
		or typeof(value["runtime_frame"]) != TYPE_INT
		or int(value["runtime_frame"]) < -1
		or typeof(value["phase"]) != TYPE_STRING
		or str(value["phase"]) not in ["idle", "warning", "active", "recovery", "completed"]
		or typeof(value["cycle_index"]) != TYPE_INT
		or typeof(value["active_zone_id"]) != TYPE_STRING
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
		or typeof(value["reduced_motion"]) != TYPE_BOOL
		or typeof(value["hit_flash_enabled"]) != TYPE_BOOL
	):
		return false
	var zone_ids: Dictionary = {}
	for zone_value: Variant in value["zones"] as Array:
		if not zone_value is Dictionary:
			return false
		var zone := zone_value as Dictionary
		if not _has_exact_fields(zone, ["id", "bounds"]):
			return false
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty() or zone_ids.has(zone_id) or not zone.get("bounds") is Dictionary:
			return false
		zone_ids[zone_id] = true
	var safe_ids: Dictionary = {}
	for safe_value: Variant in value["safe_zone_ids"] as Array:
		if typeof(safe_value) != TYPE_STRING:
			return false
		var safe_id := str(safe_value)
		if not zone_ids.has(safe_id) or safe_ids.has(safe_id):
			return false
		safe_ids[safe_id] = true
	if safe_ids.size() >= zone_ids.size():
		return false
	if int(value["runtime_frame"]) == -1:
		return (
			str(value["phase"]) == "idle"
			and int(value["cycle_index"]) == -1
			and str(value["active_zone_id"]).is_empty()
			and int(value["revision"]) == 0
		)
	return str(value["phase"]) != "idle" and int(value["revision"]) > 0


func _active_floor_phase_is_valid(
	candidate_phase: int,
	plan: Dictionary,
	current_node: Dictionary
) -> bool:
	var node_id := str(current_node.get("id", ""))
	if node_id == str(plan.get("entry_node_id", "")):
		return (
			bool(current_node.get("cleared", false))
			and candidate_phase == RunPhaseScript.Value.ROOM_ACTIVE
		)
	if bool(current_node.get("cleared", false)):
		return candidate_phase == RunPhaseScript.Value.ROOM_RESOLVING
	if candidate_phase == RunPhaseScript.Value.ROOM_ENTERING:
		return true
	var room_type := str(current_node.get("room_type", ""))
	if room_type == "boss":
		return candidate_phase == RunPhaseScript.Value.BOSS_ACTIVE
	if room_type == "combat" or room_type == "elite":
		return candidate_phase == RunPhaseScript.Value.COMBAT_ACTIVE
	return candidate_phase == RunPhaseScript.Value.ROOM_ACTIVE


func _active_phase_for_room_type(room_type: String) -> int:
	if room_type == "boss":
		return RunPhaseScript.Value.BOSS_ACTIVE
	if room_type == "combat" or room_type == "elite":
		return RunPhaseScript.Value.COMBAT_ACTIVE
	return RunPhaseScript.Value.ROOM_ACTIVE


func _plan_node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	if node_id.is_empty():
		return {}
	for node_value: Variant in plan.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("id", "")) == node_id:
			return (node_value as Dictionary).duplicate(true)
	return {}
