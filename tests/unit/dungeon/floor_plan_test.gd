extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RewardPolicyProtocolScript := preload("res://scripts/dungeon/reward_policy_protocol.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var floors: Array = _load_json_array("res://data/content_packs/base/content/floors.json")
	var templates: Array = _load_json_array("res://data/content_packs/base/content/room_templates.json")
	var policy_ids: Dictionary = {}
	suite.assert_equal(
		RewardPolicyProtocolScript.actionable_room_types(),
		["combat", "elite", "treasure", "shop", "event", "boss", "rest"],
		"reward policy protocol covers every actionable room type"
	)
	for room_type: String in RewardPolicyProtocolScript.actionable_room_types():
		var policy_id := RewardPolicyProtocolScript.policy_id_for(room_type)
		suite.assert_true(not policy_id.is_empty(), "%s owns a stable reward policy" % room_type)
		suite.assert_true(not policy_ids.has(policy_id), "%s reward policy is unique" % room_type)
		suite.assert_true(RewardPolicyProtocolScript.matches(room_type, policy_id), "%s reward policy round-trips" % room_type)
		policy_ids[policy_id] = true
	suite.assert_equal(RewardPolicyProtocolScript.policy_id_for("entry"), "", "entry owns no reward policy")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floors[0], templates)
	suite.assert_true(bool(generated.get("ok", false)), "FloorPlan fixture generates")
	if not bool(generated.get("ok", false)):
		suite.finish(get_tree())
		return
	var pristine: Dictionary = generated["plan"]
	var floor_plan = FloorPlanScript.new()
	suite.assert_equal(
		FloorPlanScript.new().configure(pristine).get("code"),
		&"FLOOR_PLAN_INVALID",
		"restored plans require explicit content authority"
	)
	suite.assert_true(
		bool(floor_plan.configure(pristine, floors[0], templates).get("ok", false)),
		"valid generated plan configures with caller authority"
	)
	suite.assert_equal(floor_plan.snapshot(), pristine, "configured snapshot is lossless")
	var exposed: Dictionary = floor_plan.snapshot()
	exposed["nodes"][0]["id"] = "mutated"
	suite.assert_equal(floor_plan.snapshot(), pristine, "snapshot is immutable to callers")

	_assert_rejected_mutation(suite, pristine, floors[0], templates, "cycle", func(plan: Dictionary) -> void:
		plan["edges"][0]["destination_node_id"] = plan["edges"][0]["source_node_id"]
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "backward edge", func(plan: Dictionary) -> void:
		var source_edge: Dictionary = plan["edges"][-1]
		source_edge["source_node_id"] = "boss"
		source_edge["destination_node_id"] = "entry"
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "orphan node", func(plan: Dictionary) -> void:
		var orphan_id := str(plan["edges"][0]["destination_node_id"])
		plan["edges"] = (plan["edges"] as Array).filter(
			func(edge: Variant): return str((edge as Dictionary)["destination_node_id"]) != orphan_id
		)
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "duplicate node id", func(plan: Dictionary) -> void:
		plan["nodes"][1]["id"] = plan["nodes"][2]["id"]
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "duplicate edge id", func(plan: Dictionary) -> void:
		plan["edges"][1]["id"] = plan["edges"][0]["id"]
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "unknown template", func(plan: Dictionary) -> void:
		plan["nodes"][1]["template_id"] = "room_unknown"
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "incompatible known template", func(plan: Dictionary) -> void:
		plan["nodes"][1]["template_id"] = "room_combat_void_grove"
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "locked current exits", func(plan: Dictionary) -> void:
		for edge_value: Variant in plan["edges"]:
			var edge: Dictionary = edge_value
			if str(edge["source_node_id"]) == str(plan["current_node_id"]):
				edge["locked"] = true
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "sibling template duplicate", func(plan: Dictionary) -> void:
		var sibling_pair := _first_sibling_pair(plan)
		var source: Dictionary = sibling_pair[0]
		var duplicate: Dictionary = sibling_pair[1]
		duplicate["template_id"] = source["template_id"]
		_update_route_summaries(plan, str(duplicate["id"]), duplicate)
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "adjacent branch layers", func(plan: Dictionary) -> void:
		_force_adjacent_branch_layers(plan, floors[0], templates)
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "unknown reward policy", func(plan: Dictionary) -> void:
		plan["nodes"][1]["reward_policy_id"] = "reward_policy_unknown_v1"
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "mismatched reward policy", func(plan: Dictionary) -> void:
		var node: Dictionary = plan["nodes"][1]
		for room_type: String in RewardPolicyProtocolScript.actionable_room_types():
			if room_type != str(node["room_type"]):
				node["reward_policy_id"] = RewardPolicyProtocolScript.policy_id_for(room_type)
				break
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "entry completion flags", func(plan: Dictionary) -> void:
		plan["nodes"][0]["cleared"] = false
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "unvisited node forged cleared", func(plan: Dictionary) -> void:
		plan["nodes"][1]["cleared"] = true
	)
	_assert_rejected_mutation(suite, pristine, floors[0], templates, "Boss semantic swap", func(plan: Dictionary) -> void:
		var boss: Dictionary = plan["nodes"].filter(
			func(node: Variant): return str((node as Dictionary)["id"]) == str(plan["boss_node_id"])
		)[0]
		var pre_boss: Dictionary = {}
		for candidate_layer: int in range(int(boss["layer"]) - 1, 0, -1):
			var layer_nodes: Array = plan["nodes"].filter(
				func(node: Variant): return int((node as Dictionary)["layer"]) == candidate_layer
			)
			if layer_nodes.size() == 1:
				pre_boss = layer_nodes[0]
				break
		for field: String in ["room_type", "template_id", "encounter_id", "event_id", "merchant_id", "reward_policy_id"]:
			var temporary: Variant = pre_boss[field]
			pre_boss[field] = boss[field]
			boss[field] = temporary
		for edge_value: Variant in plan["edges"]:
			var edge: Dictionary = edge_value
			var destination_id := str(edge["destination_node_id"])
			if destination_id == str(pre_boss["id"]):
				edge["route_summary_facts"] = {
					"room_type": str(pre_boss["room_type"]),
					"template_id": str(pre_boss["template_id"]),
				}
			elif destination_id == str(boss["id"]):
				edge["route_summary_facts"] = {
					"room_type": str(boss["room_type"]),
					"template_id": str(boss["template_id"]),
				}
	)
	var mismatched_digest := pristine.duplicate(true)
	mismatched_digest["generation_digest"] = "0".repeat(64)
	var digest_plan = FloorPlanScript.new()
	suite.assert_equal(digest_plan.configure(mismatched_digest, floors[0], templates).get("code"), &"FLOOR_PLAN_INVALID", "digest drift is rejected")

	var drifted_templates := templates.duplicate(true)
	var referenced_template_id := str((pristine["nodes"][1] as Dictionary)["template_id"])
	for template_value: Variant in drifted_templates:
		var template: Dictionary = template_value
		if str(template["id"]) == referenced_template_id:
			template["floor_ids"] = ["floor_void_forest"]
			template["supported_environment_rule_ids"] = ["rule_void_spores"]
			break
	var authority_drift = FloorPlanScript.new()
	suite.assert_equal(
		authority_drift.configure(pristine, floors[0], drifted_templates).get("code"),
		&"FLOOR_PLAN_INVALID",
		"plan restore rejects drifted caller template authority"
	)
	var history_plan = FloorPlanScript.new()
	suite.assert_true(
		bool(history_plan.configure(pristine, floors[0], templates).get("ok", false)),
		"history fixture configures"
	)
	for step: int in range(2):
		var history_snapshot: Dictionary = history_plan.snapshot()
		if step > 0:
			for node_value: Variant in history_snapshot["nodes"]:
				var node: Dictionary = node_value
				if str(node["id"]) == str(history_snapshot["current_node_id"]):
					node["cleared"] = true
			suite.assert_true(
				bool(history_plan.configure(history_snapshot, floors[0], templates).get("ok", false)),
				"history fixture clears the current room before advancing"
			)
			history_snapshot = history_plan.snapshot()
		var history_edges: Array = (history_snapshot["edges"] as Array).filter(
			func(edge: Variant): return str((edge as Dictionary)["source_node_id"]) == str(history_snapshot["current_node_id"])
		)
		suite.assert_true(
			bool(history_plan.select_edge(StringName((history_edges[0] as Dictionary)["id"]), step).get("ok", false)),
			"history fixture advances"
		)
	var forged_history := history_plan.snapshot()
	var historical_node_id := str((forged_history["visited_node_ids"] as Array)[-2])
	for node_value: Variant in forged_history["nodes"]:
		var node: Dictionary = node_value
		if str(node["id"]) == historical_node_id:
			node["cleared"] = false
	var rejected_history = FloorPlanScript.new()
	suite.assert_equal(
		rejected_history.configure(forged_history, floors[0], templates).get("code"),
		&"FLOOR_PLAN_INVALID",
		"restore rejects an uncleared historical route node"
	)
	suite.assert_equal(rejected_history.snapshot(), {}, "uncleared history restore stays atomic")
	var cleared_current := history_plan.snapshot()
	for node_value: Variant in cleared_current["nodes"]:
		var node: Dictionary = node_value
		if str(node["id"]) == str(cleared_current["current_node_id"]):
			node["cleared"] = true
	suite.assert_true(
		bool(FloorPlanScript.new().configure(cleared_current, floors[0], templates).get("ok", false)),
		"current route node may already be cleared"
	)

	var initial_snapshot: Dictionary = floor_plan.snapshot()
	var outgoing_edges: Array = (initial_snapshot["edges"] as Array).filter(
		func(edge: Variant): return str((edge as Dictionary)["source_node_id"]) == str(initial_snapshot["current_node_id"])
	)
	var route_revision := 0
	while outgoing_edges.size() == 1:
		var current_node: Dictionary = (initial_snapshot["nodes"] as Array).filter(
			func(node: Variant): return str((node as Dictionary)["id"]) == str(initial_snapshot["current_node_id"])
		)[0]
		if not bool(current_node["cleared"]):
			var cleared_snapshot := initial_snapshot.duplicate(true)
			for node_value: Variant in cleared_snapshot["nodes"]:
				var node: Dictionary = node_value
				if str(node["id"]) == str(cleared_snapshot["current_node_id"]):
					node["cleared"] = true
			suite.assert_true(
				bool(floor_plan.configure(cleared_snapshot, floors[0], templates).get("ok", false)),
				"fixture clears a room before leaving it"
			)
			initial_snapshot = floor_plan.snapshot()
		var advance_edge: Dictionary = outgoing_edges[0]
		var advance_result: Dictionary = floor_plan.select_edge(StringName(advance_edge["id"]), route_revision)
		suite.assert_true(bool(advance_result.get("ok", false)), "fixture advances to its first route choice")
		route_revision += 1
		initial_snapshot = floor_plan.snapshot()
		outgoing_edges = (initial_snapshot["edges"] as Array).filter(
			func(edge: Variant): return str((edge as Dictionary)["source_node_id"]) == str(initial_snapshot["current_node_id"])
		)
	suite.assert_true(outgoing_edges.size() >= 2, "fixture exposes a route choice")
	var branch_source: Dictionary = (initial_snapshot["nodes"] as Array).filter(
		func(node: Variant): return str((node as Dictionary)["id"]) == str(initial_snapshot["current_node_id"])
	)[0]
	if not bool(branch_source["cleared"]):
		var cleared_branch_source := initial_snapshot.duplicate(true)
		for node_value: Variant in cleared_branch_source["nodes"]:
			var node: Dictionary = node_value
			if str(node["id"]) == str(cleared_branch_source["current_node_id"]):
				node["cleared"] = true
		suite.assert_true(
			bool(floor_plan.configure(cleared_branch_source, floors[0], templates).get("ok", false)),
			"fixture clears the branch source before selecting a route"
		)
		initial_snapshot = floor_plan.snapshot()
		outgoing_edges = (initial_snapshot["edges"] as Array).filter(
			func(edge: Variant): return str((edge as Dictionary)["source_node_id"]) == str(initial_snapshot["current_node_id"])
		)
	var selected_edge: Dictionary = outgoing_edges[0]
	var stale: Dictionary = floor_plan.select_edge(StringName(selected_edge["id"]), route_revision + 99)
	suite.assert_equal(stale.get("code"), &"STALE_REVISION", "stale selection is rejected")
	suite.assert_equal(floor_plan.snapshot(), initial_snapshot, "stale selection is atomic")
	var selected: Dictionary = floor_plan.select_edge(StringName(selected_edge["id"]), route_revision)
	suite.assert_true(bool(selected.get("ok", false)), "canonical outgoing edge selects")
	suite.assert_equal(selected.get("new_revision"), route_revision + 1, "successful selection increments revision")
	suite.assert_equal(str(selected.get("node_id", "")), str(selected_edge["destination_node_id"]), "successful selection advances current node")
	var after_selection: Dictionary = floor_plan.snapshot()
	suite.assert_true((after_selection["selected_edge_ids"] as Array).has(str(selected_edge["id"])), "selection records edge")
	for sibling_value: Variant in outgoing_edges.slice(1):
		var sibling: Dictionary = sibling_value
		suite.assert_true((after_selection["abandoned_node_ids"] as Array).has(str(sibling["destination_node_id"])), "selection abandons sibling destination")
	var before_repeat: Dictionary = floor_plan.snapshot()
	var repeated: Dictionary = floor_plan.select_edge(StringName(selected_edge["id"]), route_revision + 1)
	suite.assert_equal(repeated.get("code"), &"ROUTE_SELECTION_INVALID", "repeated selection is rejected")
	suite.assert_equal(floor_plan.snapshot(), before_repeat, "repeated selection is atomic")

	var sibling_not_abandoned := after_selection.duplicate(true)
	sibling_not_abandoned["abandoned_node_ids"] = []
	var invalid_selected_state = FloorPlanScript.new()
	suite.assert_equal(
		invalid_selected_state.configure(sibling_not_abandoned, floors[0], templates).get("code"),
		&"FLOOR_PLAN_INVALID",
		"selected route with live sibling is rejected"
	)
	var selected_locked := after_selection.duplicate(true)
	for edge_value: Variant in selected_locked["edges"]:
		var edge: Dictionary = edge_value
		if (selected_locked["selected_edge_ids"] as Array).has(str(edge["id"])):
			edge["locked"] = true
	selected_locked["generation_digest"] = FloorPlanScript.compute_generation_digest(selected_locked)
	var selected_locked_plan = FloorPlanScript.new()
	suite.assert_equal(
		selected_locked_plan.configure(selected_locked, floors[0], templates).get("code"),
		&"FLOOR_PLAN_INVALID",
		"import rejects a selected edge that is locked"
	)
	suite.assert_equal(selected_locked_plan.snapshot(), {}, "locked selected-edge import stays atomic")
	suite.finish(get_tree())


func _assert_rejected_mutation(
	suite,
	pristine: Dictionary,
	floor: Dictionary,
	templates: Array,
	label: String,
	mutate: Callable
) -> void:
	var candidate := pristine.duplicate(true)
	mutate.call(candidate)
	if label != "unknown template":
		candidate["generation_digest"] = FloorPlanScript.compute_generation_digest(candidate)
	var floor_plan = FloorPlanScript.new()
	var result: Dictionary = floor_plan.configure(candidate, floor, templates)
	suite.assert_equal(result.get("code"), &"FLOOR_PLAN_INVALID", "%s is rejected" % label)
	var expected_reason_by_label := {
		"locked current exits": "unsupported",
		"sibling template duplicate": "sibling_template_repetition",
		"adjacent branch layers": "adjacent_branch_layers",
		"unknown reward policy": "mismatch",
		"mismatched reward policy": "mismatch",
		"entry completion flags": "entry_state_invalid",
		"unvisited node forged cleared": "unvisited_node_cleared",
	}
	if expected_reason_by_label.has(label):
		suite.assert_equal(
			result.get("context", {}).get("reason"),
			expected_reason_by_label[label],
			"%s fails for its frozen invariant" % label
		)
	suite.assert_equal(floor_plan.snapshot(), {}, "%s does not retain invalid state" % label)


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _first_sibling_pair(plan: Dictionary) -> Array[Dictionary]:
	var nodes_by_layer: Dictionary = {}
	for node_value: Variant in plan["nodes"]:
		var node: Dictionary = node_value
		var layer := int(node["layer"])
		if not nodes_by_layer.has(layer):
			nodes_by_layer[layer] = []
		(nodes_by_layer[layer] as Array).append(node)
	for layer_value: Variant in nodes_by_layer.keys():
		var layer_nodes: Array = nodes_by_layer[layer_value]
		if layer_nodes.size() > 1:
			return [layer_nodes[0], layer_nodes[1]]
	return []


func _force_adjacent_branch_layers(
	plan: Dictionary,
	floor: Dictionary,
	templates: Array
) -> void:
	var nodes_by_layer: Dictionary = {}
	for node_value: Variant in plan["nodes"]:
		var node: Dictionary = node_value
		var layer := int(node["layer"])
		if not nodes_by_layer.has(layer):
			nodes_by_layer[layer] = []
		(nodes_by_layer[layer] as Array).append(node)
	var branch_layers: Array[int] = []
	for layer_value: Variant in nodes_by_layer.keys():
		var layer := int(layer_value)
		if layer > 0 and layer < int(plan["nodes"][-1]["layer"]) and (nodes_by_layer[layer] as Array).size() > 1:
			branch_layers.append(layer)
	branch_layers.sort()
	var anchor_layer := branch_layers[0]
	var target_layer := anchor_layer + 1
	if target_layer >= int(plan["nodes"][-1]["layer"]) or (nodes_by_layer[target_layer] as Array).size() != 1:
		target_layer = anchor_layer - 1
	var donor_layer := anchor_layer
	if (nodes_by_layer[anchor_layer] as Array).size() < 3:
		donor_layer = branch_layers[1]
	var donor_nodes: Array = nodes_by_layer[donor_layer]
	var donor: Dictionary = donor_nodes[-1]
	var target: Dictionary = (nodes_by_layer[target_layer] as Array)[0]
	var excluded_templates: Dictionary = {str(target["template_id"]): true}
	for neighbor_layer: int in [target_layer - 1, target_layer + 1]:
		for neighbor_value: Variant in nodes_by_layer.get(neighbor_layer, []):
			excluded_templates[str((neighbor_value as Dictionary)["template_id"])] = true
	var replacement_template_id := ""
	for template_value: Variant in templates:
		var template: Dictionary = template_value
		if (
			str(template["room_type"]) == str(target["room_type"])
			and (template["floor_ids"] as Array).has(str(floor["id"]))
			and (template["supported_environment_rule_ids"] as Array).has(str(floor["environment_rule_id"]))
			and not excluded_templates.has(str(template["id"]))
		):
			replacement_template_id = str(template["id"])
			break
	donor["layer"] = target_layer
	for field: String in ["room_type", "encounter_id", "event_id", "merchant_id", "reward_policy_id"]:
		donor[field] = target[field]
	donor["template_id"] = replacement_template_id
	donor["revealed"] = false
	donor["visited"] = false
	donor["cleared"] = false
	_rebuild_edges(plan)


func _rebuild_edges(plan: Dictionary) -> void:
	var nodes_by_layer: Dictionary = {}
	var final_layer := 0
	for node_value: Variant in plan["nodes"]:
		var node: Dictionary = node_value
		var layer := int(node["layer"])
		final_layer = maxi(final_layer, layer)
		if not nodes_by_layer.has(layer):
			nodes_by_layer[layer] = []
		(nodes_by_layer[layer] as Array).append(node)
	var edges: Array[Dictionary] = []
	for layer: int in range(final_layer):
		var sources: Array = nodes_by_layer[layer]
		var destinations: Array = nodes_by_layer[layer + 1]
		destinations.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["id"]) < str(b["id"]))
		for source_value: Variant in sources:
			var source: Dictionary = source_value
			for choice_order: int in range(destinations.size()):
				var destination: Dictionary = destinations[choice_order]
				edges.append({
					"id": "edge_%s__%s" % [str(source["id"]), str(destination["id"])],
					"source_node_id": str(source["id"]),
					"destination_node_id": str(destination["id"]),
					"choice_order": choice_order,
					"locked": false,
					"route_summary_facts": {
						"room_type": str(destination["room_type"]),
						"template_id": str(destination["template_id"]),
					},
				})
	plan["edges"] = edges


func _update_route_summaries(plan: Dictionary, node_id: String, node: Dictionary) -> void:
	for edge_value: Variant in plan["edges"]:
		var edge: Dictionary = edge_value
		if str(edge["destination_node_id"]) == node_id:
			edge["route_summary_facts"] = {
				"room_type": str(node["room_type"]),
				"template_id": str(node["template_id"]),
			}
