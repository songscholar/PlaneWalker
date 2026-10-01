extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")

const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var floors: Array = _load_json_array(FLOOR_PATH)
	var templates: Array = _load_json_array(TEMPLATE_PATH)
	suite.assert_equal(floors.size(), 5, "generator fixture exposes five floors")
	suite.assert_equal(templates.size(), 30, "generator fixture exposes thirty room templates")

	var generator = FloorPlanGeneratorScript.new()
	for floor_value: Variant in floors:
		var floor: Dictionary = floor_value
		for run_seed: int in range(20261001, 20261031):
			var first: Dictionary = generator.generate(run_seed, floor, templates)
			var repeated: Dictionary = generator.generate(run_seed, floor, templates)
			var label := "%s seed %d" % [str(floor["id"]), run_seed]
			suite.assert_true(bool(first.get("ok", false)), "%s generates" % label)
			if not bool(first.get("ok", false)):
				continue
			suite.assert_equal(first, repeated, "%s is byte-identical on repeat" % label)
			var plan: Dictionary = first.get("plan", {})
			_assert_plan_invariants(suite, plan, floor, templates, label)

	var missing_boss_templates := templates.filter(
		func(template: Variant) -> bool:
			return str((template as Dictionary).get("id", "")) != "room_boss_ruin_king"
	)
	var failed: Dictionary = generator.generate(20261001, floors[0], missing_boss_templates)
	suite.assert_equal(failed.get("ok"), false, "generation fails closed without the floor Boss template")
	suite.assert_equal(failed.get("code"), &"FLOOR_PLAN_GENERATION_FAILED", "generation failure has stable code")
	suite.assert_equal(failed.get("context", {}).get("attempts"), 8, "generation failure reports bounded attempts")
	var duplicate_templates: Array = templates.duplicate(true)
	duplicate_templates.append((templates[0] as Dictionary).duplicate(true))
	var duplicate_failure: Dictionary = generator.generate(20261001, floors[0], duplicate_templates)
	suite.assert_equal(duplicate_failure.get("ok"), false, "duplicate template authority fails closed")
	suite.assert_equal(duplicate_failure.get("code"), &"FLOOR_PLAN_GENERATION_FAILED", "duplicate authority keeps stable failure code")
	var mutated_floor: Dictionary = (floors[0] as Dictionary).duplicate(true)
	mutated_floor["required_room_budgets"]["event_min"] = 2
	var authority_driven: Dictionary = generator.generate(20261001, mutated_floor, templates)
	suite.assert_equal(authority_driven.get("ok"), false, "generator rejects drift from FloorDefinition authority")
	suite.assert_equal(authority_driven.get("code"), &"FLOOR_PLAN_GENERATION_FAILED", "authority drift fails closed")

	var capacity_templates: Array = []
	var kept_combat := false
	for template_value: Variant in templates:
		var template: Dictionary = template_value
		if str(template["room_type"]) == "combat":
			if kept_combat or not (template["floor_ids"] as Array).has("floor_ruins_of_remnant"):
				continue
			kept_combat = true
		capacity_templates.append(template.duplicate(true))
	var capacity_result: Dictionary = generator.generate(20261001, floors[0], capacity_templates)
	suite.assert_true(bool(capacity_result.get("ok", false)), "topology moves branches away from one-template room types")
	if bool(capacity_result.get("ok", false)):
		var layer_templates: Dictionary = {}
		for node_value: Variant in capacity_result.get("plan", {}).get("nodes", []):
			var node: Dictionary = node_value
			var layer := int(node["layer"])
			if not layer_templates.has(layer):
				layer_templates[layer] = []
			(layer_templates[layer] as Array).append(str(node["template_id"]))
		for values_value: Variant in layer_templates.values():
			var values: Array = values_value
			var unique: Dictionary = {}
			for template_id_value: Variant in values:
				unique[str(template_id_value)] = true
			suite.assert_equal(unique.size(), values.size(), "siblings never exceed authoritative template capacity")
	suite.finish(get_tree())


func _assert_plan_invariants(
	suite,
	plan: Dictionary,
	floor: Dictionary,
	templates: Array,
	label: String
) -> void:
	var configured = FloorPlanScript.new()
	suite.assert_true(bool(configured.configure(plan, floor, templates).get("ok", false)), "%s validates as FloorPlan" % label)
	suite.assert_equal(plan.get("schema_version"), 1, "%s seals schema version" % label)
	suite.assert_equal(plan.get("generator_version"), "floor_plan_v1", "%s seals generator version" % label)
	suite.assert_equal(plan.get("floor_id"), floor.get("id"), "%s keeps floor identity" % label)
	suite.assert_equal((plan.get("nodes", []) as Array).size(), int(floor["graph_node_min"]), "%s keeps exact graph budget" % label)
	suite.assert_equal(plan.get("entry_node_id"), "entry", "%s owns one entry" % label)
	suite.assert_equal(plan.get("boss_node_id"), "boss", "%s owns one Boss" % label)
	suite.assert_equal(
		(plan.get("nodes", []) as Array).filter(func(node: Variant): return str((node as Dictionary).get("room_type", "")) == "boss").size(),
		1,
		"%s has exactly one Boss node" % label
	)
	suite.assert_equal(str(plan.get("generation_digest", "")).length(), 64, "%s digest is SHA-256" % label)
	suite.assert_equal(
		plan.get("generation_digest"),
		FloorPlanScript.compute_generation_digest(plan),
		"%s digest matches canonical generation data" % label
	)

	var nodes_by_id: Dictionary = {}
	for node_value: Variant in plan.get("nodes", []):
		var node: Dictionary = node_value
		nodes_by_id[str(node["id"])] = node
	var outgoing: Dictionary = {}
	var reachable: Dictionary = {"entry": true}
	for edge_value: Variant in plan.get("edges", []):
		var edge: Dictionary = edge_value
		var source_id := str(edge["source_node_id"])
		var destination_id := str(edge["destination_node_id"])
		suite.assert_equal(
			int((nodes_by_id[destination_id] as Dictionary)["layer"]),
			int((nodes_by_id[source_id] as Dictionary)["layer"]) + 1,
			"%s edges advance exactly one layer" % label
		)
		if not outgoing.has(source_id):
			outgoing[source_id] = []
		(outgoing[source_id] as Array).append(destination_id)
	var ordered_nodes: Array = (plan.get("nodes", []) as Array).duplicate()
	ordered_nodes.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["layer"]) < int(b["layer"]))
	for node_value: Variant in ordered_nodes:
		var node: Dictionary = node_value
		var node_id := str(node["id"])
		if node_id == "entry":
			continue
		for source_id_value: Variant in outgoing.keys():
			var source_id := str(source_id_value)
			if reachable.has(source_id) and (outgoing[source_id] as Array).has(node_id):
				reachable[node_id] = true
				break
	suite.assert_equal(reachable.size(), nodes_by_id.size(), "%s has no orphan nodes" % label)

	for source_id_value: Variant in outgoing.keys():
		var choice_count := (outgoing[source_id_value] as Array).size()
		suite.assert_true(choice_count >= 1 and choice_count <= 3, "%s exposes at most three route choices" % label)
		if choice_count > 1:
			suite.assert_true(choice_count == 2 or choice_count == 3, "%s branch layers expose two or three choices" % label)
	var widths_by_layer: Dictionary = {}
	for node_value: Variant in plan.get("nodes", []):
		var node: Dictionary = node_value
		var layer := int(node["layer"])
		widths_by_layer[layer] = int(widths_by_layer.get(layer, 0)) + 1
	for layer: int in range(1, int(floor["route_room_min"])):
		if int(widths_by_layer.get(layer, 0)) > 1:
			suite.assert_equal(
				int(widths_by_layer.get(layer + 1, 0)),
				1,
				"%s merges each branch before another branch" % label
			)

	var paths: Array[Array] = []
	_collect_paths("entry", "boss", outgoing, [], paths)
	suite.assert_true(not paths.is_empty(), "%s reaches Boss" % label)
	var expected_length := int(floor["route_room_min"])
	var template_by_id: Dictionary = {}
	for template_value: Variant in templates:
		var template: Dictionary = template_value
		template_by_id[str(template["id"])] = template
	for path: Array in paths:
		suite.assert_equal(path.size() - 1, expected_length, "%s keeps equal actionable path length" % label)
		var types: Array[String] = []
		var previous_template_id := ""
		var consecutive_combat := 0
		var max_consecutive_combat := 0
		for path_node_id_value: Variant in path.slice(1):
			var path_node_id := str(path_node_id_value)
			var node: Dictionary = nodes_by_id[path_node_id]
			var room_type := str(node["room_type"])
			types.append(room_type)
			if room_type == "combat" or room_type == "elite":
				consecutive_combat += 1
				max_consecutive_combat = maxi(max_consecutive_combat, consecutive_combat)
			else:
				consecutive_combat = 0
			var template_id := str(node["template_id"])
			suite.assert_true(template_by_id.has(template_id), "%s references known templates" % label)
			if template_by_id.has(template_id):
				var template: Dictionary = template_by_id[template_id]
				suite.assert_equal(template.get("room_type"), room_type, "%s template type matches node" % label)
				suite.assert_true((template.get("floor_ids", []) as Array).has(floor["id"]), "%s template supports floor" % label)
				suite.assert_true((template.get("supported_environment_rule_ids", []) as Array).has(floor["environment_rule_id"]), "%s template supports floor rule" % label)
			if not previous_template_id.is_empty():
				suite.assert_true(template_id != previous_template_id, "%s avoids immediate template repetition" % label)
			previous_template_id = template_id
		suite.assert_true(max_consecutive_combat <= 3, "%s limits combat streaks" % label)
		var budgets: Dictionary = floor["required_room_budgets"]
		suite.assert_equal(types.count("boss"), 1, "%s path owns one Boss" % label)
		suite.assert_true(types.count("event") >= int(budgets["event_min"]), "%s path meets event budget" % label)
		suite.assert_true(types.count("shop") >= int(budgets["shop_min"]), "%s path meets shop budget" % label)
		suite.assert_true(types.count("treasure") >= int(budgets["treasure_min"]), "%s path meets treasure budget" % label)
		suite.assert_true(types.count("shop") + types.count("treasure") >= int(budgets["shop_or_treasure_min"]), "%s path meets economy-room budget" % label)
		suite.assert_equal(types.count("rest"), int(budgets["rest_min"]), "%s path meets rest budget" % label)
		if int(budgets["rest_min"]) == 1:
			suite.assert_equal(types.find("rest"), expected_length - 3, "%s places rest two actionable rooms before Boss" % label)


func _collect_paths(
	node_id: String,
	boss_node_id: String,
	outgoing: Dictionary,
	prefix: Array,
	paths: Array[Array]
) -> void:
	var next_prefix := prefix.duplicate()
	next_prefix.append(node_id)
	if node_id == boss_node_id:
		paths.append(next_prefix)
		return
	for destination_value: Variant in outgoing.get(node_id, []):
		_collect_paths(str(destination_value), boss_node_id, outgoing, next_prefix, paths)


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []
