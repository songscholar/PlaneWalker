class_name FloorPlanGenerator
extends RefCounted

const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const RoomTemplateDefinitionScript := preload("res://scripts/dungeon/room_template_definition.gd")
const RewardPolicyProtocolScript := preload("res://scripts/dungeon/reward_policy_protocol.gd")

const MAX_ATTEMPTS := 8


func generate(run_seed: int, floor_definition: Dictionary, room_templates: Array) -> Dictionary:
	var floor_id := str(floor_definition.get("id", ""))
	var floor_result: Dictionary = FloorDefinitionScript.new().configure(floor_definition)
	if not bool(floor_result.get("ok", false)):
		return _generation_failure(
			run_seed,
			floor_id,
			floor_result.get("context", {"field": "floor_definition", "reason": "invalid"})
		)
	var floor: Dictionary = (floor_result.get("definition", {}) as Dictionary).duplicate(true)
	var templates_result := _normalize_templates(room_templates)
	if not bool(templates_result.get("ok", false)):
		return _generation_failure(
			run_seed,
			floor_id,
			templates_result.get("context", {"field": "room_templates", "reason": "invalid"})
		)
	var templates: Array = templates_result["templates"]
	var last_error: Dictionary = {"field": "floor_definition", "reason": "invalid"}
	for attempt: int in range(MAX_ATTEMPTS):
		var candidate_result := _generate_attempt(
			run_seed,
			floor,
			templates,
			attempt
		)
		if not bool(candidate_result.get("ok", false)):
			last_error = candidate_result.get("context", last_error)
			continue
		var plan: Dictionary = candidate_result["plan"]
		var floor_plan = FloorPlanScript.new()
		var configured: Dictionary = floor_plan.configure(plan, floor, templates)
		if bool(configured.get("ok", false)):
			return {
				"ok": true,
				"plan": floor_plan.snapshot(),
				"context": {"attempt": attempt + 1},
			}
		last_error = configured.get("context", last_error)
	return _generation_failure(run_seed, floor_id, last_error)


func _generation_failure(run_seed: int, floor_id: String, last_error: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": &"FLOOR_PLAN_GENERATION_FAILED",
		"context": {
			"run_seed": run_seed,
			"floor_id": floor_id,
			"attempts": MAX_ATTEMPTS,
			"last_error": last_error.duplicate(true),
		},
	}


func _generate_attempt(
	run_seed: int,
	floor: Dictionary,
	room_templates: Array,
	attempt: int
) -> Dictionary:
	var floor_id := str(floor["id"])
	var route_length := int(floor["route_room_min"])
	var target_nodes := int(floor["graph_node_min"])
	var compatible_by_type := _compatible_templates_by_type(floor, room_templates)
	var route_types := _route_types(run_seed, floor, compatible_by_type, attempt)
	if route_types.size() != route_length:
		return {"ok": false, "context": {"field": "route_types", "reason": "budget_unreachable"}}
	for room_type: String in route_types:
		if not compatible_by_type.has(room_type) or (compatible_by_type[room_type] as Array).is_empty():
			return {"ok": false, "context": {"field": "room_templates", "reason": "missing_compatible_%s" % room_type}}
	var widths := _layer_widths(
		run_seed,
		floor_id,
		route_types,
		compatible_by_type,
		target_nodes,
		attempt
	)
	if widths.is_empty():
		return {"ok": false, "context": {"field": "topology", "reason": "budget_unreachable"}}

	var nodes: Array[Dictionary] = [_entry_node()]
	var layer_node_ids: Array[Array] = [["entry"]]
	var previous_template_ids: Array[String] = []
	for layer_index: int in range(route_length):
		var layer := layer_index + 1
		var room_type: String = route_types[layer_index]
		if room_type == "boss":
			var boss_node_result := _build_node(
				run_seed, floor, compatible_by_type, "boss", layer, room_type,
				previous_template_ids, [], attempt
			)
			if not bool(boss_node_result.get("ok", false)):
				return boss_node_result
			var boss_node: Dictionary = boss_node_result["node"]
			nodes.append(boss_node)
			layer_node_ids.append(["boss"])
			previous_template_ids = [str(boss_node["template_id"])]
			continue
		var layer_ids: Array[String] = []
		var layer_template_ids: Array[String] = []
		for branch_index: int in range(widths[layer_index]):
			var node_id := "layer_%02d_%s" % [layer, String.chr(97 + branch_index)]
			var node_result := _build_node(
				run_seed, floor, compatible_by_type, node_id, layer, room_type,
				previous_template_ids, layer_template_ids, attempt
			)
			if not bool(node_result.get("ok", false)):
				return node_result
			var node: Dictionary = node_result["node"]
			nodes.append(node)
			layer_ids.append(node_id)
			layer_template_ids.append(str(node["template_id"]))
		layer_node_ids.append(layer_ids)
		previous_template_ids = layer_template_ids

	var edges: Array[Dictionary] = []
	for layer_index: int in range(layer_node_ids.size() - 1):
		var source_ids: Array = layer_node_ids[layer_index]
		var destination_ids: Array = layer_node_ids[layer_index + 1]
		for source_id_value: Variant in source_ids:
			var source_id := str(source_id_value)
			for choice_order: int in range(destination_ids.size()):
				var destination_id := str(destination_ids[choice_order])
				var destination := _node_by_id(nodes, destination_id)
				edges.append({
					"id": "edge_%s__%s" % [source_id, destination_id],
					"source_node_id": source_id,
					"destination_node_id": destination_id,
					"choice_order": choice_order,
					"locked": false,
					"route_summary_facts": {
						"room_type": str(destination["room_type"]),
						"template_id": str(destination["template_id"]),
					},
				})
	var plan := {
		"schema_version": FloorPlanScript.SCHEMA_VERSION,
		"generator_version": FloorPlanScript.GENERATOR_VERSION,
		"run_seed": run_seed,
		"floor_id": floor_id,
		"floor_index": int(floor["order"]) - 1,
		"entry_node_id": "entry",
		"boss_node_id": "boss",
		"current_node_id": "entry",
		"nodes": nodes,
		"edges": edges,
		"selected_edge_ids": [],
		"visited_node_ids": ["entry"],
		"abandoned_node_ids": [],
		"generation_digest": "",
		"revision": 0,
	}
	plan["generation_digest"] = FloorPlanScript.compute_generation_digest(plan)
	return {"ok": true, "plan": plan, "context": {}}


func _layer_widths(
	run_seed: int,
	floor_id: String,
	route_types: Array[String],
	compatible_by_type: Dictionary,
	target_nodes: int,
	attempt: int
) -> Array[int]:
	var extra := target_nodes - (route_types.size() + 1)
	if extra < 0:
		return []
	return _search_layer_widths(
		run_seed,
		floor_id,
		route_types,
		compatible_by_type,
		attempt,
		0,
		extra,
		[]
	)


func _search_layer_widths(
	run_seed: int,
	floor_id: String,
	route_types: Array[String],
	compatible_by_type: Dictionary,
	attempt: int,
	layer_index: int,
	remaining_extra: int,
	widths: Array[int]
) -> Array[int]:
	if layer_index >= route_types.size() - 1:
		if remaining_extra == 0:
			return widths
		var no_widths: Array[int] = []
		return no_widths
	var room_type := route_types[layer_index]
	var template_count := (compatible_by_type.get(room_type, []) as Array).size()
	var previous_width := widths[-1] if not widths.is_empty() else 1
	var maximum_width := mini(3, template_count)
	if previous_width > 1:
		maximum_width = 1
	if layer_index > 0 and route_types[layer_index - 1] == room_type:
		maximum_width = mini(maximum_width, template_count - previous_width)
	if maximum_width < 1:
		var no_capacity: Array[int] = []
		return no_capacity
	var options: Array[int] = []
	for width: int in range(1, maximum_width + 1):
		if width - 1 <= remaining_extra:
			options.append(width)
	options.sort_custom(
		func(a: int, b: int) -> bool:
			var node_id := StringName("layer_%02d" % (layer_index + 1))
			var a_seed := SeedServiceScript.derive_node_seed(
				run_seed, StringName(floor_id), node_id, &"topology_width", attempt * 4 + a
			)
			var b_seed := SeedServiceScript.derive_node_seed(
				run_seed, StringName(floor_id), node_id, &"topology_width", attempt * 4 + b
			)
			return a > b if a_seed == b_seed else a_seed < b_seed
	)
	for width: int in options:
		var candidate: Array[int] = []
		candidate.assign(widths)
		candidate.append(width)
		var result := _search_layer_widths(
			run_seed,
			floor_id,
			route_types,
			compatible_by_type,
			attempt,
			layer_index + 1,
			remaining_extra - (width - 1),
			candidate
		)
		if not result.is_empty():
			return result
	var no_solution: Array[int] = []
	return no_solution


func _route_types(
	run_seed: int,
	floor: Dictionary,
	compatible_by_type: Dictionary,
	attempt: int
) -> Array[String]:
	var floor_id := str(floor["id"])
	var route_length := int(floor["route_room_min"])
	if route_length < 2 or not _room_type_available("boss", floor, compatible_by_type):
		return []
	var slots: Array[String] = []
	for _index: int in range(route_length):
		slots.append("")
	slots[route_length - 1] = "boss"
	var budgets: Dictionary = floor["required_room_budgets"]
	var rest_count := int(budgets["rest_min"])
	if rest_count < 0 or rest_count > 1:
		return []
	if rest_count == 1:
		var rest_index := route_length - 3
		if rest_index < 0 or not _room_type_available("rest", floor, compatible_by_type):
			return []
		slots[rest_index] = "rest"

	var required_types: Array[String] = []
	for _event_index: int in range(int(budgets["event_min"])):
		required_types.append("event")
	for _shop_index: int in range(int(budgets["shop_min"])):
		required_types.append("shop")
	for _treasure_index: int in range(int(budgets["treasure_min"])):
		required_types.append("treasure")
	var economy_extra := maxi(
		0,
		int(budgets["shop_or_treasure_min"])
			- int(budgets["shop_min"])
			- int(budgets["treasure_min"])
	)
	for economy_index: int in range(economy_extra):
		var economy_choices: Array[String] = []
		for room_type: String in ["shop", "treasure"]:
			if _room_type_available(room_type, floor, compatible_by_type):
				economy_choices.append(room_type)
		if economy_choices.is_empty():
			return []
		economy_choices.sort_custom(
			func(a: String, b: String) -> bool:
				var a_seed := SeedServiceScript.derive_node_seed(
					run_seed, StringName(floor_id), &"route_budget", StringName("economy_%s" % a), attempt + economy_index
				)
				var b_seed := SeedServiceScript.derive_node_seed(
					run_seed, StringName(floor_id), &"route_budget", StringName("economy_%s" % b), attempt + economy_index
				)
				return a < b if a_seed == b_seed else a_seed < b_seed
		)
		required_types.append(economy_choices[0])

	for room_type: String in required_types:
		if not _room_type_available(room_type, floor, compatible_by_type):
			return []
	required_types.sort_custom(
		func(a: String, b: String) -> bool:
			var a_seed := SeedServiceScript.derive_node_seed(
				run_seed, StringName(floor_id), &"route_budget", StringName("required_%s" % a), attempt
			)
			var b_seed := SeedServiceScript.derive_node_seed(
				run_seed, StringName(floor_id), &"route_budget", StringName("required_%s" % b), attempt
			)
			return a < b if a_seed == b_seed else a_seed < b_seed
	)
	var available_positions: Array[int] = []
	for position: int in range(route_length - 1):
		if slots[position].is_empty():
			available_positions.append(position)
	if required_types.size() > available_positions.size():
		return []
	for token_index: int in range(required_types.size()):
		var ideal := float(token_index + 1) * float(route_length - 1) / float(required_types.size() + 1)
		available_positions.sort_custom(
			func(a: int, b: int) -> bool:
				var a_distance := absf(float(a) - ideal)
				var b_distance := absf(float(b) - ideal)
				if not is_equal_approx(a_distance, b_distance):
					return a_distance < b_distance
				var a_seed := SeedServiceScript.derive_node_seed(
					run_seed, StringName(floor_id), StringName("layer_%02d" % (a + 1)), &"route_slot", attempt
				)
				var b_seed := SeedServiceScript.derive_node_seed(
					run_seed, StringName(floor_id), StringName("layer_%02d" % (b + 1)), &"route_slot", attempt
				)
				return a < b if a_seed == b_seed else a_seed < b_seed
		)
		var selected_position: int = available_positions.pop_front()
		slots[selected_position] = required_types[token_index]

	var combat_streak := 0
	for position: int in range(route_length - 1):
		if not slots[position].is_empty():
			combat_streak = 0
			continue
		if combat_streak >= 3:
			return []
		var combat_choices: Array[String] = []
		for room_type: String in ["combat", "elite"]:
			if not _room_type_available(room_type, floor, compatible_by_type):
				continue
			if (
				position > 0
				and slots[position - 1] == room_type
				and (compatible_by_type[room_type] as Array).size() < 2
			):
				continue
			combat_choices.append(room_type)
		if combat_choices.is_empty():
			return []
		combat_choices.sort_custom(
			func(a: String, b: String) -> bool:
				var node_id := StringName("layer_%02d" % (position + 1))
				var a_seed := SeedServiceScript.derive_node_seed(
					run_seed, StringName(floor_id), node_id, StringName("route_type_%s" % a), attempt
				)
				var b_seed := SeedServiceScript.derive_node_seed(
					run_seed, StringName(floor_id), node_id, StringName("route_type_%s" % b), attempt
				)
				return a < b if a_seed == b_seed else a_seed < b_seed
		)
		slots[position] = combat_choices[0]
		combat_streak += 1
	return slots if _route_types_match_budgets(slots, budgets) else []


func _room_type_available(
	room_type: String,
	floor: Dictionary,
	compatible_by_type: Dictionary
) -> bool:
	if not (floor["allowed_room_types"] as Array).has(room_type):
		return false
	if not compatible_by_type.has(room_type) or (compatible_by_type[room_type] as Array).is_empty():
		return false
	if room_type == "event":
		return not (floor["event_ids"] as Array).is_empty()
	if room_type == "shop":
		return not (floor["merchant_ids"] as Array).is_empty()
	if room_type == "boss":
		for template_value: Variant in compatible_by_type["boss"]:
			if str((template_value as Dictionary)["id"]) == str(floor["boss_room_template_id"]):
				return true
		return false
	return true


func _route_types_match_budgets(route_types: Array[String], budgets: Dictionary) -> bool:
	if route_types.count("boss") != int(budgets["boss_count"]):
		return false
	if route_types.count("event") < int(budgets["event_min"]):
		return false
	if route_types.count("shop") < int(budgets["shop_min"]):
		return false
	if route_types.count("treasure") < int(budgets["treasure_min"]):
		return false
	if route_types.count("shop") + route_types.count("treasure") < int(budgets["shop_or_treasure_min"]):
		return false
	if route_types.count("rest") != int(budgets["rest_min"]):
		return false
	var combat_streak := 0
	for room_type: String in route_types:
		if room_type == "combat" or room_type == "elite":
			combat_streak += 1
			if combat_streak > 3:
				return false
		else:
			combat_streak = 0
	return true


func _compatible_templates_by_type(floor: Dictionary, room_templates: Array) -> Dictionary:
	var compatible: Dictionary = {}
	var floor_id := str(floor.get("id", ""))
	var environment_rule_id := str(floor.get("environment_rule_id", ""))
	for template_value: Variant in room_templates:
		if not template_value is Dictionary:
			continue
		var template: Dictionary = template_value
		if (
			typeof(template.get("id")) != TYPE_STRING
			or typeof(template.get("room_type")) != TYPE_STRING
			or not template.get("floor_ids", []) is Array
			or not template.get("supported_environment_rule_ids", []) is Array
			or not (template.get("floor_ids", []) as Array).has(floor_id)
			or not (template.get("supported_environment_rule_ids", []) as Array).has(environment_rule_id)
		):
			continue
		var room_type := str(template["room_type"])
		if not compatible.has(room_type):
			compatible[room_type] = []
		(compatible[room_type] as Array).append(template.duplicate(true))
	for room_type_value: Variant in compatible.keys():
		(compatible[room_type_value] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary): return str(a["id"]) < str(b["id"])
		)
	return compatible


func _build_node(
	run_seed: int,
	floor: Dictionary,
	compatible_by_type: Dictionary,
	node_id: String,
	layer: int,
	room_type: String,
	previous_template_ids: Array[String],
	layer_template_ids: Array[String],
	attempt: int
) -> Dictionary:
	var candidates: Array = (compatible_by_type.get(room_type, []) as Array).filter(
		func(template: Variant):
			var template_id := str((template as Dictionary).get("id", ""))
			return not previous_template_ids.has(template_id)
	)
	if room_type == "boss":
		candidates = candidates.filter(
			func(template: Variant): return str((template as Dictionary).get("id", "")) == str(floor["boss_room_template_id"])
		)
	var unused_candidates: Array = candidates.filter(
		func(template: Variant): return not layer_template_ids.has(str((template as Dictionary).get("id", "")))
	)
	candidates = unused_candidates
	if candidates.is_empty():
		return {"ok": false, "context": {"field": node_id, "reason": "no_compatible_template"}}
	var floor_id := str(floor["id"])
	var template_seed := SeedServiceScript.derive_node_seed(
		run_seed, StringName(floor_id), StringName(node_id), &"room_template", attempt
	)
	var template: Dictionary = candidates[posmod(template_seed, candidates.size())]
	var event_id := ""
	if room_type == "event":
		var event_ids: Array = floor["event_ids"]
		var event_seed := SeedServiceScript.derive_node_seed(
			run_seed, StringName(floor_id), StringName(node_id), &"event_reference", attempt
		)
		event_id = str(event_ids[posmod(event_seed, event_ids.size())])
	var merchant_id := ""
	if room_type == "shop":
		var merchant_ids: Array = floor["merchant_ids"]
		var merchant_seed := SeedServiceScript.derive_node_seed(
			run_seed, StringName(floor_id), StringName(node_id), &"merchant_reference", attempt
		)
		merchant_id = str(merchant_ids[posmod(merchant_seed, merchant_ids.size())])
	var encounter_id := ""
	if room_type == "combat" or room_type == "elite":
		encounter_id = str(floor["encounter_profile_id"])
	elif room_type == "boss":
		encounter_id = str(floor["boss_encounter_id"])
	var reward_policy_id := RewardPolicyProtocolScript.policy_id_for(room_type)
	if reward_policy_id.is_empty():
		return {"ok": false, "context": {"field": node_id, "reason": "unknown_reward_policy"}}
	return {
		"ok": true,
		"node": {
			"id": node_id,
			"layer": layer,
			"room_type": room_type,
			"template_id": str(template["id"]),
			"encounter_id": encounter_id,
			"event_id": event_id,
			"merchant_id": merchant_id,
			"reward_policy_id": reward_policy_id,
			"seed_channel_suffix": node_id,
			"revealed": false,
			"visited": false,
			"cleared": false,
		},
		"context": {},
	}


func _entry_node() -> Dictionary:
	return {
		"id": "entry",
		"layer": 0,
		"room_type": "entry",
		"template_id": "",
		"encounter_id": "",
		"event_id": "",
		"merchant_id": "",
		"reward_policy_id": "",
		"seed_channel_suffix": "entry",
		"revealed": true,
		"visited": true,
		"cleared": true,
	}


func _node_by_id(nodes: Array[Dictionary], node_id: String) -> Dictionary:
	for node: Dictionary in nodes:
		if str(node["id"]) == node_id:
			return node
	return {}


func _normalize_templates(room_templates: Array) -> Dictionary:
	var normalized: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range(room_templates.size()):
		var template_value: Variant = room_templates[index]
		if not template_value is Dictionary:
			return {
				"ok": false,
				"context": {"field": "room_templates[%d]" % index, "reason": "expected_dictionary"},
			}
		var template_result: Dictionary = RoomTemplateDefinitionScript.new().configure(template_value)
		if not bool(template_result.get("ok", false)):
			return {
				"ok": false,
				"context": template_result.get(
					"context",
					{"field": "room_templates[%d]" % index, "reason": "invalid"}
				),
			}
		var template: Dictionary = template_result["definition"]
		var template_id := str(template["id"])
		if seen.has(template_id):
			return {
				"ok": false,
				"context": {"field": "room_templates[%d].id" % index, "reason": "duplicate"},
			}
		seen[template_id] = true
		normalized.append(template.duplicate(true))
	return {"ok": true, "templates": normalized, "context": {}}
