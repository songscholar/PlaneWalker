extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")

const SEAL_PATH := "res://scripts/replay/run_dungeon_replay_seal.gd"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


class DriftRegistry:
	extends RefCounted

	var base: RefCounted
	var floors_override: Array[Dictionary] = []
	var room_overrides: Dictionary = {}
	var event_overrides: Dictionary = {}
	var packs_override: Array[Dictionary] = []

	func _init(p_base: RefCounted) -> void:
		base = p_base

	func active_packs() -> Array[Dictionary]:
		return packs_override.duplicate(true) if not packs_override.is_empty() else base.call("active_packs")

	func resolve_room_template(content_id: StringName) -> Dictionary:
		var key := str(content_id)
		return (
			(room_overrides[key] as Dictionary).duplicate(true)
			if room_overrides.has(key)
			else base.call("resolve_room_template", content_id)
		)

	func resolve_dungeon_event(content_id: StringName) -> Dictionary:
		var key := str(content_id)
		return (
			(event_overrides[key] as Dictionary).duplicate(true)
			if event_overrides.has(key)
			else base.call("resolve_dungeon_event", content_id)
		)

	func get_floor_definitions(availability: StringName = &"") -> Array[Dictionary]:
		if not floors_override.is_empty():
			return floors_override.duplicate(true)
		return base.call("get_floor_definitions", availability)

	func get_by_category(
		category: StringName,
		availability: StringName = &""
	) -> Array[Dictionary]:
		return base.call("get_by_category", category, availability)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	suite.assert_true(FileAccess.file_exists(SEAL_PATH), "dungeon Replay seal authority exists")
	var seal_script: Variant = load(SEAL_PATH) if FileAccess.file_exists(SEAL_PATH) else null
	suite.assert_true(seal_script != null, "dungeon Replay seal authority loads")
	if seal_script == null:
		suite.finish(get_tree())
		return

	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"LAUNCH"
	)
	suite.assert_true(not report.has_blocking_errors(), "dungeon Replay fixture loads Base Pack")
	if report.has_blocking_errors():
		suite.finish(get_tree())
		return

	var floors: Array = _load_json_array(FLOOR_PATH)
	var templates: Array = _load_json_array(TEMPLATE_PATH)
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floors[0], templates)
	suite.assert_true(bool(generated.get("ok", false)), "dungeon Replay fixture generates a plan")
	if not bool(generated.get("ok", false)):
		suite.finish(get_tree())
		return

	var floor_plan = FloorPlanScript.new()
	suite.assert_true(
		bool(floor_plan.configure(generated["plan"], floors[0], templates).get("ok", false)),
		"dungeon Replay fixture configures FloorPlan"
	)
	var selected_event_node := false
	while floor_plan.snapshot().get("current_node_id") != floor_plan.snapshot().get("boss_node_id"):
		var before_selection: Dictionary = floor_plan.snapshot()
		var next_edge: Dictionary = _first_open_edge(before_selection)
		var selected: Dictionary = floor_plan.select_edge(
			StringName(str(next_edge.get("id", ""))), floor_plan.revision()
		)
		suite.assert_true(bool(selected.get("ok", false)), "dungeon Replay fixture advances its route")
		if not bool(selected.get("ok", false)):
			break
		var selected_node: Dictionary = _node_by_id(
			floor_plan.snapshot(), str(floor_plan.snapshot().get("current_node_id", ""))
		)
		var cleared_plan: Dictionary = floor_plan.snapshot()
		for node_value: Variant in cleared_plan.get("nodes", []):
			var node := node_value as Dictionary
			if str(node.get("id", "")) == str(cleared_plan.get("current_node_id", "")):
				node["cleared"] = true
				break
		suite.assert_true(
			bool(floor_plan.configure(cleared_plan, floors[0], templates).get("ok", false)),
			"dungeon Replay fixture seals each cleared historical room"
		)
		if str(selected_node.get("room_type", "")) == "event":
			selected_event_node = true
			break
	suite.assert_true(selected_event_node, "dungeon Replay fixture reaches an event on its route")
	var plan: Dictionary = floor_plan.snapshot()
	var route_prefix: Array = plan.get("selected_edge_ids", []).duplicate(true)
	var room_facts: Array = _room_fact_inputs_for_plan(plan)
	var economy_ledger: Array = [
		{"transaction_id": "tx_reward_0001", "operation": "gold_delta", "amount": 12, "revision": 1},
	]
	var seal: RefCounted = seal_script.new()
	var event_resolutions: Array = _event_resolutions_for_plan(seal, registry, plan)
	var floor_transitions: Array = [
		{
			"sequence": 0,
			"from_floor_id": "",
			"to_floor_id": str(plan["floor_id"]),
			"completed_plan_digest": "",
		},
	]
	var snapshot: Dictionary = seal.call(
		"capture",
		registry,
		plan,
		route_prefix,
		room_facts,
		economy_ledger,
		event_resolutions,
		floor_transitions
	)
	if snapshot.is_empty():
		suite.assert_true(false, "canonical dungeon Replay snapshot captures")
		suite.finish(get_tree())
		return
	suite.assert_equal(snapshot.get("schema_id"), "planewalker.run_dungeon_replay", "seal owns schema id")
	suite.assert_equal(snapshot.get("schema_version"), 1, "seal owns schema version")
	suite.assert_equal(snapshot.get("generator_version"), "floor_plan_v1", "seal owns generator version")
	suite.assert_equal(snapshot.get("plan_digest"), plan.get("generation_digest"), "seal owns plan digest")
	suite.assert_equal(snapshot.get("route_prefix"), route_prefix, "seal owns route prefix")
	suite.assert_equal(
		(snapshot.get("room_facts", []) as Array).size(),
		room_facts.size(),
		"seal owns the complete canonical room-fact log"
	)
	suite.assert_equal(str(snapshot.get("economy_ledger_digest", "")).length(), 64, "seal owns economy digest")
	suite.assert_equal(str(snapshot.get("event_resolution_digest", "")).length(), 64, "seal owns event digest")
	suite.assert_equal(snapshot.get("floor_transitions"), floor_transitions, "seal owns floor transitions")
	suite.assert_equal(str(snapshot.get("snapshot_digest", "")).length(), 64, "seal authenticates historical bytes")

	var valid: Dictionary = seal.call(
		"validate", snapshot, registry, plan, economy_ledger, event_resolutions
	)
	suite.assert_true(bool(valid.get("ok", false)), "valid dungeon Replay seal verifies")
	suite.assert_equal(valid.get("snapshot"), snapshot, "validation returns byte-identical historical snapshot")

	var forged_plan := _resigned_plan_with_reordered_siblings(plan)
	suite.assert_true(not forged_plan.is_empty(), "forged-plan fixture can alter canonical generation bytes")
	if not forged_plan.is_empty():
		var resigned_plan_snapshot := snapshot.duplicate(true)
		resigned_plan_snapshot["plan_digest"] = str(forged_plan["generation_digest"])
		resigned_plan_snapshot["snapshot_digest"] = seal.call(
			"snapshot_digest", resigned_plan_snapshot
		)
		_assert_rejected(
			suite, seal, resigned_plan_snapshot, registry, forged_plan,
			economy_ledger, event_resolutions, &"PLAN_DIGEST_MISMATCH",
			"re-signed non-canonical plan"
		)
		suite.assert_equal(
			seal.call(
				"capture", registry, forged_plan, route_prefix, room_facts,
				economy_ledger, event_resolutions, floor_transitions
			),
			{},
			"capture rejects a self-consistent but non-canonical generated plan"
		)

	var floor_authority_drift = DriftRegistry.new(registry)
	floor_authority_drift.floors_override = registry.get_floor_definitions(&"LAUNCH")
	floor_authority_drift.floors_override[0]["boss_encounter_id"] = (
		"boss_encounter_forged_adapter_v1"
	)
	_assert_rejected(
		suite, seal, snapshot, floor_authority_drift, plan,
		economy_ledger, event_resolutions, &"PLAN_DIGEST_MISMATCH",
		"registry floor authority drift"
	)

	var deleted_room_fact := snapshot.duplicate(true)
	(deleted_room_fact["room_facts"] as Array).remove_at(
		(deleted_room_fact["room_facts"] as Array).size() - 1
	)
	deleted_room_fact["snapshot_digest"] = seal.call("snapshot_digest", deleted_room_fact)
	_assert_rejected(
		suite, seal, deleted_room_fact, registry, plan, economy_ledger, event_resolutions,
		&"ROOM_FACT_INVALID", "re-signed missing room fact"
	)

	var reordered_room_facts := snapshot.duplicate(true)
	var reordered_facts := reordered_room_facts["room_facts"] as Array
	if reordered_facts.size() >= 2:
		var first_fact: Variant = reordered_facts[0]
		reordered_facts[0] = reordered_facts[1]
		reordered_facts[1] = first_fact
		reordered_room_facts["snapshot_digest"] = seal.call(
			"snapshot_digest", reordered_room_facts
		)
		_assert_rejected(
			suite, seal, reordered_room_facts, registry, plan,
			economy_ledger, event_resolutions, &"ROOM_FACT_INVALID",
			"re-signed reordered room facts"
		)

	var replaced_room_fact := snapshot.duplicate(true)
	(replaced_room_fact["room_facts"] as Array)[0]["node_id"] = "boss"
	replaced_room_fact["snapshot_digest"] = seal.call(
		"snapshot_digest", replaced_room_fact
	)
	_assert_rejected(
		suite, seal, replaced_room_fact, registry, plan,
		economy_ledger, event_resolutions, &"ROOM_FACT_INVALID",
		"re-signed room fact outside the selected route order"
	)

	var uncleared_plan := _with_current_node_cleared(plan, false)
	_assert_rejected(
		suite, seal, snapshot, registry, uncleared_plan, economy_ledger, event_resolutions,
		&"ROOM_FACT_INVALID", "room clear fact contradicts current FloorPlan state"
	)

	var forged_transition := snapshot.duplicate(true)
	(forged_transition["floor_transitions"] as Array)[0]["to_floor_id"] = "floor_forged"
	forged_transition["snapshot_digest"] = seal.call("snapshot_digest", forged_transition)
	_assert_rejected(
		suite, seal, forged_transition, registry, plan, economy_ledger, event_resolutions,
		&"FLOOR_TRANSITION_INVALID", "re-signed fictional floor transition"
	)
	var missing_transition := snapshot.duplicate(true)
	(missing_transition["floor_transitions"] as Array).clear()
	missing_transition["snapshot_digest"] = seal.call(
		"snapshot_digest", missing_transition
	)
	_assert_rejected(
		suite, seal, missing_transition, registry, plan,
		economy_ledger, event_resolutions, &"FLOOR_TRANSITION_INVALID",
		"re-signed transition chain deletion"
	)

	_test_later_floor_transition_authority(
		suite, seal, registry, floors, templates, economy_ledger
	)

	var duplicate_economy := economy_ledger.duplicate(true)
	duplicate_economy.append(duplicate_economy[0].duplicate(true))
	duplicate_economy[1]["revision"] = 2
	var duplicate_economy_snapshot := snapshot.duplicate(true)
	duplicate_economy_snapshot["economy_ledger_digest"] = ReplayRecorderScript.value_digest(
		duplicate_economy
	)
	duplicate_economy_snapshot["snapshot_digest"] = seal.call(
		"snapshot_digest", duplicate_economy_snapshot
	)
	_assert_rejected(
		suite, seal, duplicate_economy_snapshot, registry, plan,
		duplicate_economy, event_resolutions, &"ECONOMY_LEDGER_INVALID",
		"duplicate economy transaction id"
	)
	var invalid_economy := economy_ledger.duplicate(true)
	invalid_economy[0]["operation"] = "mint_everything"
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			invalid_economy, event_resolutions, floor_transitions
		),
		{},
		"capture rejects unsupported economy operations"
	)
	var extra_field_economy := economy_ledger.duplicate(true)
	extra_field_economy[0]["memo"] = "forged"
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			extra_field_economy, event_resolutions, floor_transitions
		),
		{},
		"capture rejects economy entries outside the closed field set"
	)
	var zero_amount_economy := economy_ledger.duplicate(true)
	zero_amount_economy[0]["amount"] = 0
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			zero_amount_economy, event_resolutions, floor_transitions
		),
		{},
		"capture rejects zero-value economy transactions"
	)
	var skipped_revision_economy := economy_ledger.duplicate(true)
	skipped_revision_economy[0]["revision"] = 2
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			skipped_revision_economy, event_resolutions, floor_transitions
		),
		{},
		"capture rejects non-contiguous economy revisions"
	)

	if not event_resolutions.is_empty():
		var duplicate_events := event_resolutions.duplicate(true)
		duplicate_events.append(duplicate_events[0].duplicate(true))
		duplicate_events[1]["sequence"] = 1
		suite.assert_equal(
			seal.call(
				"capture", registry, plan, route_prefix, room_facts,
				economy_ledger, duplicate_events, floor_transitions
			),
			{},
			"capture rejects duplicate event resolutions"
		)
		var wrong_event_node := event_resolutions.duplicate(true)
		wrong_event_node[0]["node_id"] = "boss"
		suite.assert_equal(
			seal.call(
				"capture", registry, plan, route_prefix, room_facts,
				economy_ledger, wrong_event_node, floor_transitions
			),
			{},
			"capture rejects event resolutions outside the cleared route node"
		)

	var unauthenticated := snapshot.duplicate(true)
	unauthenticated["route_prefix"] = ["forged_edge"]
	var unauthenticated_result: Dictionary = seal.call(
		"validate", unauthenticated, registry, plan, economy_ledger, event_resolutions
	)
	suite.assert_equal(
		unauthenticated_result.get("code"),
		&"SNAPSHOT_DIGEST_MISMATCH",
		"historical bytes authenticate before semantic normalization"
	)

	var invalid_route := snapshot.duplicate(true)
	invalid_route["route_prefix"] = ["forged_edge"]
	invalid_route["snapshot_digest"] = seal.call("snapshot_digest", invalid_route)
	_assert_rejected(
		suite, seal, invalid_route, registry, plan, economy_ledger, event_resolutions,
		&"ROUTE_PREFIX_INVALID", "invalid route prefix"
	)

	var unknown_generator := snapshot.duplicate(true)
	unknown_generator["generator_version"] = "floor_plan_v999"
	unknown_generator["snapshot_digest"] = seal.call("snapshot_digest", unknown_generator)
	_assert_rejected(
		suite, seal, unknown_generator, registry, plan, economy_ledger, event_resolutions,
		&"GENERATOR_VERSION_UNSUPPORTED", "unknown generator"
	)

	var changed_plan := plan.duplicate(true)
	changed_plan["generation_digest"] = "0".repeat(64)
	_assert_rejected(
		suite, seal, snapshot, registry, changed_plan, economy_ledger, event_resolutions,
		&"PLAN_DIGEST_MISMATCH", "plan digest drift"
	)

	var changed_economy := economy_ledger.duplicate(true)
	changed_economy[0]["amount"] = 13
	_assert_rejected(
		suite, seal, snapshot, registry, plan, changed_economy, event_resolutions,
		&"ECONOMY_LEDGER_DRIFT", "economy prefix drift"
	)

	if not event_resolutions.is_empty():
		var changed_events := event_resolutions.duplicate(true)
		changed_events[0]["outcome_id"] = "forged_outcome"
		_assert_rejected(
			suite, seal, snapshot, registry, plan, economy_ledger, changed_events,
			&"EVENT_RESOLUTION_INVALID", "event outcome authority drift"
		)
		var event_definition_drift = DriftRegistry.new(registry)
		var event_id := str(event_resolutions[0].get("event_id", ""))
		var changed_event: Dictionary = registry.resolve_dungeon_event(
			StringName(event_id)
		)
		changed_event["options"][0]["consequences"] = [
			{"operation": "gold_delta", "amount": 999},
		]
		event_definition_drift.event_overrides[event_id] = changed_event
		_assert_rejected(
			suite, seal, snapshot, event_definition_drift, plan,
			economy_ledger, event_resolutions, &"EVENT_RESOLUTION_INVALID",
			"event consequence definition drift"
		)

	var fingerprint_drift = DriftRegistry.new(registry)
	fingerprint_drift.packs_override = registry.active_packs()
	fingerprint_drift.packs_override[0]["fingerprint_sha256"] = "0".repeat(64)
	_assert_rejected(
		suite, seal, snapshot, fingerprint_drift, plan, economy_ledger, event_resolutions,
		&"CONTENT_FINGERPRINT_MISMATCH", "content fingerprint drift"
	)

	var first_room_fact := (snapshot.get("room_facts", []) as Array)[0] as Dictionary
	var room_drift = DriftRegistry.new(registry)
	var room_id := str(first_room_fact.get("template_id", ""))
	var changed_room: Dictionary = registry.resolve_room_template(StringName(room_id))
	changed_room["description_key"] = "ROOM_DESCRIPTION_FORGED"
	room_drift.room_overrides[room_id] = changed_room
	_assert_rejected(
		suite, seal, snapshot, room_drift, plan, economy_ledger, event_resolutions,
		&"ROOM_DEFINITION_DRIFT", "room definition drift"
	)

	suite.finish(get_tree())


func _assert_rejected(
	suite,
	seal: RefCounted,
	snapshot: Dictionary,
	registry: Variant,
	plan: Dictionary,
	economy_ledger: Array,
	event_resolutions: Array,
	expected_code: StringName,
	label: String
) -> void:
	var result: Dictionary = seal.call(
		"validate", snapshot, registry, plan, economy_ledger, event_resolutions
	)
	suite.assert_equal(result.get("ok"), false, "%s fails closed" % label)
	suite.assert_equal(result.get("code"), expected_code, "%s reports stable code" % label)


func _test_later_floor_transition_authority(
	suite,
	seal: RefCounted,
	registry: RefCounted,
	floors: Array,
	templates: Array,
	economy_ledger: Array
) -> void:
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261001, floors[1], templates
	)
	suite.assert_true(bool(generated.get("ok", false)), "later-floor Replay fixture generates")
	if not bool(generated.get("ok", false)):
		return
	var prior: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261001, floors[0], templates
	)
	if not bool(prior.get("ok", false)):
		suite.assert_true(false, "later-floor prior plan generates")
		return
	var later_plan: Dictionary = generated["plan"]
	var transitions: Array = [
		{
			"sequence": 0,
			"from_floor_id": "",
			"to_floor_id": str(floors[0]["id"]),
			"completed_plan_digest": "",
		},
		{
			"sequence": 1,
			"from_floor_id": str(floors[0]["id"]),
			"to_floor_id": str(floors[1]["id"]),
			"completed_plan_digest": str(prior["plan"]["generation_digest"]),
		},
	]
	var later_snapshot: Dictionary = seal.call(
		"capture", registry, later_plan, [], [], economy_ledger, [], transitions
	)
	suite.assert_true(not later_snapshot.is_empty(), "later-floor canonical transition chain captures")
	if later_snapshot.is_empty():
		return
	var valid: Dictionary = seal.call(
		"validate", later_snapshot, registry, later_plan, economy_ledger, []
	)
	suite.assert_true(bool(valid.get("ok", false)), "later-floor canonical transition chain validates")
	var forged := later_snapshot.duplicate(true)
	forged["floor_transitions"][1]["completed_plan_digest"] = "0".repeat(64)
	forged["snapshot_digest"] = seal.call("snapshot_digest", forged)
	_assert_rejected(
		suite, seal, forged, registry, later_plan, economy_ledger, [],
		&"FLOOR_TRANSITION_INVALID", "re-signed prior floor digest drift"
	)


func _first_open_edge(plan: Dictionary) -> Dictionary:
	for edge_value: Variant in plan.get("edges", []):
		if edge_value is Dictionary and str((edge_value as Dictionary).get("source_node_id", "")) == str(plan.get("current_node_id", "")):
			return (edge_value as Dictionary).duplicate(true)
	return {}


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("id", "")) == node_id:
			return (node_value as Dictionary).duplicate(true)
	return {}


func _event_resolutions_for_plan(
	seal: RefCounted,
	registry: RefCounted,
	plan: Dictionary
) -> Array:
	var result: Array[Dictionary] = []
	for node_id: String in _route_node_ids(plan):
		var node: Dictionary = _node_by_id(plan, node_id)
		var event_id := str(node.get("event_id", ""))
		if event_id.is_empty() or not bool(node.get("cleared", false)):
			continue
		var definition: Dictionary = registry.resolve_dungeon_event(StringName(event_id))
		var options := definition.get("options", []) as Array
		if options.is_empty():
			return []
		var option_id := str((options[0] as Dictionary).get("id", ""))
		result.append({
			"event_id": event_id,
			"node_id": node_id,
			"option_id": option_id,
			"outcome_id": seal.call(
				"expected_event_outcome_id", definition, node_id, option_id
			),
			"sequence": result.size(),
		})
	return result


func _room_fact_inputs_for_plan(plan: Dictionary) -> Array:
	var result: Array[Dictionary] = []
	for node_id: String in _route_node_ids(plan):
		var node := _node_by_id(plan, node_id)
		result.append({
			"node_id": node_id,
			"fact_type": "room_entered",
			"sequence": result.size(),
		})
		if bool(node.get("cleared", false)):
			result.append({
				"node_id": node_id,
				"fact_type": "room_cleared",
				"sequence": result.size(),
			})
	return result


func _route_node_ids(plan: Dictionary) -> Array[String]:
	var edges_by_id: Dictionary = {}
	for edge_value: Variant in plan.get("edges", []):
		if edge_value is Dictionary:
			edges_by_id[str((edge_value as Dictionary).get("id", ""))] = edge_value
	var result: Array[String] = []
	for edge_id_value: Variant in plan.get("selected_edge_ids", []):
		var edge_id := str(edge_id_value)
		if not edges_by_id.has(edge_id):
			return []
		result.append(str((edges_by_id[edge_id] as Dictionary).get("destination_node_id", "")))
	return result


func _with_current_node_cleared(plan: Dictionary, cleared: bool) -> Dictionary:
	var result := plan.duplicate(true)
	for node_value: Variant in result.get("nodes", []):
		if (
			node_value is Dictionary
			and str((node_value as Dictionary).get("id", "")) == str(result.get("current_node_id", ""))
		):
			(node_value as Dictionary)["cleared"] = cleared
			break
	return result


func _resigned_plan_with_reordered_siblings(plan: Dictionary) -> Dictionary:
	var result := plan.duplicate(true)
	var nodes := result.get("nodes", []) as Array
	for left_index: int in range(nodes.size()):
		var left := nodes[left_index] as Dictionary
		for right_index: int in range(left_index + 1, nodes.size()):
			var right := nodes[right_index] as Dictionary
			if int(left.get("layer", -1)) != int(right.get("layer", -2)):
				continue
			var swap_value: Variant = nodes[left_index]
			nodes[left_index] = nodes[right_index]
			nodes[right_index] = swap_value
			result["generation_digest"] = FloorPlanScript.compute_generation_digest(result)
			return result
	return {}


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Array if value is Array else []
