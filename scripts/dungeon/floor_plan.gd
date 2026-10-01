class_name FloorPlan
extends RefCounted

const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const RoomTemplateDefinitionScript := preload("res://scripts/dungeon/room_template_definition.gd")
const RewardPolicyProtocolScript := preload("res://scripts/dungeon/reward_policy_protocol.gd")

const SCHEMA_VERSION := 1
const GENERATOR_VERSION := "floor_plan_v1"
const ROOT_FIELDS: Array[String] = [
	"schema_version", "generator_version", "run_seed", "floor_id", "floor_index",
	"entry_node_id", "boss_node_id", "current_node_id", "nodes", "edges",
	"selected_edge_ids", "visited_node_ids", "abandoned_node_ids",
	"generation_digest", "revision",
]
const NODE_FIELDS: Array[String] = [
	"id", "layer", "room_type", "template_id", "encounter_id", "event_id",
	"merchant_id", "reward_policy_id", "seed_channel_suffix", "revealed",
	"visited", "cleared",
]
const EDGE_FIELDS: Array[String] = [
	"id", "source_node_id", "destination_node_id", "choice_order", "locked",
	"route_summary_facts",
]
const ROUTE_SUMMARY_FIELDS: Array[String] = ["room_type", "template_id"]

var _snapshot: Dictionary = {}
var _floor_definition: Dictionary = {}
var _templates_by_id: Dictionary = {}


func configure(
	source: Dictionary,
	floor_definition: Dictionary = {},
	room_templates: Array = []
) -> Dictionary:
	_snapshot.clear()
	_floor_definition.clear()
	_templates_by_id.clear()
	var authority_result := _normalized_authority(floor_definition, room_templates)
	if not bool(authority_result.get("ok", false)):
		return {
			"ok": false,
			"code": &"FLOOR_PLAN_INVALID",
			"context": authority_result.get("context", _error("authority", "invalid")),
		}
	var normalized_floor: Dictionary = authority_result["floor"]
	var normalized_templates: Dictionary = authority_result["templates_by_id"]
	var error := _validation_error(source, normalized_floor, normalized_templates)
	if not error.is_empty():
		return {"ok": false, "code": &"FLOOR_PLAN_INVALID", "context": error}
	_snapshot = source.duplicate(true)
	_floor_definition = normalized_floor.duplicate(true)
	_templates_by_id = normalized_templates.duplicate(true)
	return {"ok": true, "plan": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func revision() -> int:
	return int(_snapshot.get("revision", -1))


func select_edge(edge_id: StringName, expected_revision: int) -> Dictionary:
	if _snapshot.is_empty() or _floor_definition.is_empty() or _templates_by_id.is_empty():
		return {"ok": false, "code": &"ROUTE_SELECTION_INVALID", "revision": -1}
	var current_revision := int(_snapshot["revision"])
	if expected_revision != current_revision:
		return {"ok": false, "code": &"STALE_REVISION", "revision": current_revision}
	var edge: Dictionary = {}
	for edge_value: Variant in _snapshot["edges"]:
		var candidate_edge: Dictionary = edge_value
		if str(candidate_edge["id"]) == str(edge_id):
			edge = candidate_edge
			break
	if (
		edge.is_empty()
		or str(edge["source_node_id"]) != str(_snapshot["current_node_id"])
		or bool(edge["locked"])
		or (_snapshot["selected_edge_ids"] as Array).has(str(edge_id))
		or (_snapshot["abandoned_node_ids"] as Array).has(str(edge["destination_node_id"]))
	):
		return {"ok": false, "code": &"ROUTE_SELECTION_INVALID", "revision": current_revision}

	var candidate := _snapshot.duplicate(true)
	(candidate["selected_edge_ids"] as Array).append(str(edge_id))
	candidate["current_node_id"] = str(edge["destination_node_id"])
	candidate["revision"] = current_revision + 1
	if not (candidate["visited_node_ids"] as Array).has(candidate["current_node_id"]):
		(candidate["visited_node_ids"] as Array).append(candidate["current_node_id"])
	for node_value: Variant in candidate["nodes"]:
		var node: Dictionary = node_value
		if str(node["id"]) == str(candidate["current_node_id"]):
			node["revealed"] = true
			node["visited"] = true
	candidate["abandoned_node_ids"] = _expected_abandoned_node_ids(candidate)
	var error := _validation_error(candidate, _floor_definition, _templates_by_id)
	if not error.is_empty():
		return {"ok": false, "code": &"ROUTE_SELECTION_INVALID", "revision": current_revision}
	_snapshot = candidate
	return {
		"ok": true,
		"new_revision": int(_snapshot["revision"]),
		"node_id": StringName(_snapshot["current_node_id"]),
	}


static func compute_generation_digest(plan: Dictionary) -> String:
	var nodes: Array[Dictionary] = []
	for node_value: Variant in plan.get("nodes", []):
		if not node_value is Dictionary:
			return ""
		var node: Dictionary = (node_value as Dictionary).duplicate(true)
		node.erase("revealed")
		node.erase("visited")
		node.erase("cleared")
		nodes.append(node)
	var edges: Array[Dictionary] = []
	for edge_value: Variant in plan.get("edges", []):
		if not edge_value is Dictionary:
			return ""
		edges.append((edge_value as Dictionary).duplicate(true))
	var generation_data := {
		"schema_version": plan.get("schema_version"),
		"generator_version": plan.get("generator_version"),
		"run_seed": plan.get("run_seed"),
		"floor_id": plan.get("floor_id"),
		"floor_index": plan.get("floor_index"),
		"entry_node_id": plan.get("entry_node_id"),
		"boss_node_id": plan.get("boss_node_id"),
		"nodes": nodes,
		"edges": edges,
	}
	var serialized := JSON.stringify(generation_data, "", true, true)
	return serialized.sha256_text() if not serialized.is_empty() else ""


func _normalized_authority(floor_definition: Dictionary, room_templates: Array) -> Dictionary:
	if floor_definition.is_empty():
		return {"ok": false, "context": _error("floor_definition", "required")}
	if room_templates.is_empty():
		return {"ok": false, "context": _error("room_templates", "required")}
	var floor_result: Dictionary = FloorDefinitionScript.new().configure(floor_definition)
	if not bool(floor_result.get("ok", false)):
		return {
			"ok": false,
			"context": floor_result.get("context", _error("floor_definition", "invalid")),
		}
	var templates_by_id: Dictionary = {}
	for index: int in range(room_templates.size()):
		var template_value: Variant = room_templates[index]
		if not template_value is Dictionary:
			return {
				"ok": false,
				"context": _error("room_templates[%d]" % index, "expected_dictionary"),
			}
		var template_result: Dictionary = RoomTemplateDefinitionScript.new().configure(template_value)
		if not bool(template_result.get("ok", false)):
			return {
				"ok": false,
				"context": template_result.get("context", _error("room_templates[%d]" % index, "invalid")),
			}
		var template: Dictionary = template_result["definition"]
		var template_id := str(template["id"])
		if templates_by_id.has(template_id):
			return {
				"ok": false,
				"context": _error("room_templates[%d].id" % index, "duplicate"),
			}
		templates_by_id[template_id] = template.duplicate(true)
	return {
		"ok": true,
		"floor": (floor_result["definition"] as Dictionary).duplicate(true),
		"templates_by_id": templates_by_id,
		"context": {},
	}


func _validation_error(
	plan: Dictionary,
	floor: Dictionary,
	templates_by_id: Dictionary
) -> Dictionary:
	var fields_error := _exact_fields_error(plan, ROOT_FIELDS, "plan")
	if not fields_error.is_empty():
		return fields_error
	if typeof(plan["schema_version"]) != TYPE_INT or int(plan["schema_version"]) != SCHEMA_VERSION:
		return _error("schema_version", "unsupported")
	if typeof(plan["generator_version"]) != TYPE_STRING or str(plan["generator_version"]) != GENERATOR_VERSION:
		return _error("generator_version", "unsupported")
	if typeof(plan["run_seed"]) != TYPE_INT:
		return _error("run_seed", "expected_integer")
	if typeof(plan["floor_id"]) != TYPE_STRING or str(plan["floor_id"]) != str(floor["id"]):
		return _error("floor_id", "authority_mismatch")
	var floor_id := str(plan["floor_id"])
	var route_length := int(floor["route_room_min"])
	if typeof(plan["floor_index"]) != TYPE_INT or int(plan["floor_index"]) != int(floor["order"]) - 1:
		return _error("floor_index", "floor_identity_mismatch")
	for field: String in ["entry_node_id", "boss_node_id", "current_node_id", "generation_digest"]:
		if typeof(plan[field]) != TYPE_STRING or str(plan[field]).is_empty():
			return _error(field, "expected_non_empty_string")
	if str(plan["entry_node_id"]) != "entry" or str(plan["boss_node_id"]) != "boss":
		return _error("entry_node_id", "canonical_ids_required")
	for field: String in ["nodes", "edges", "selected_edge_ids", "visited_node_ids", "abandoned_node_ids"]:
		if not plan[field] is Array:
			return _error(field, "expected_array")
	if typeof(plan["revision"]) != TYPE_INT or int(plan["revision"]) < 0:
		return _error("revision", "expected_non_negative_integer")
	if (plan["nodes"] as Array).size() != int(floor["graph_node_min"]):
		return _error("nodes", "graph_budget_mismatch")

	var nodes_by_id: Dictionary = {}
	var layer_nodes: Dictionary = {}
	for index: int in range((plan["nodes"] as Array).size()):
		var node_value: Variant = (plan["nodes"] as Array)[index]
		if not node_value is Dictionary:
			return _error("nodes[%d]" % index, "expected_dictionary")
		var node: Dictionary = node_value
		var node_error := _node_error(node, floor, templates_by_id, index)
		if not node_error.is_empty():
			return node_error
		var node_id := str(node["id"])
		if nodes_by_id.has(node_id):
			return _error("nodes[%d].id" % index, "duplicate")
		nodes_by_id[node_id] = node
		var layer := int(node["layer"])
		if not layer_nodes.has(layer):
			layer_nodes[layer] = []
		(layer_nodes[layer] as Array).append(node_id)
	if not nodes_by_id.has("entry") or not nodes_by_id.has("boss") or not nodes_by_id.has(str(plan["current_node_id"])):
		return _error("nodes", "required_node_missing")
	for layer: int in range(route_length + 1):
		if not layer_nodes.has(layer):
			return _error("nodes", "missing_layer")
	if (layer_nodes[0] as Array) != ["entry"]:
		return _error("nodes", "entry_layer_invalid")
	if (layer_nodes[route_length] as Array) != ["boss"]:
		return _error("nodes", "boss_layer_invalid")
	for layer: int in range(route_length + 1):
		var layer_node_ids: Array = layer_nodes[layer]
		var width := layer_node_ids.size()
		if width < 1 or width > 3:
			return _error("nodes", "layer_width_invalid")
		var layer_template_ids: Dictionary = {}
		for node_id_value: Variant in layer_node_ids:
			var template_id := str((nodes_by_id[str(node_id_value)] as Dictionary)["template_id"])
			if not template_id.is_empty() and layer_template_ids.has(template_id):
				return _error("nodes", "sibling_template_repetition")
			layer_template_ids[template_id] = true
		if width > 1:
			if layer == 0 or layer == route_length:
				return _error("nodes", "terminal_branch_invalid")
			if (layer_nodes[layer - 1] as Array).size() != 1 or (layer_nodes[layer + 1] as Array).size() != 1:
				return _error("nodes", "adjacent_branch_layers")
	var boss_count := 0
	for node_value: Variant in nodes_by_id.values():
		if str((node_value as Dictionary)["room_type"]) == "boss":
			boss_count += 1
	if boss_count != 1:
		return _error("nodes", "boss_identity_invalid")

	var edges_by_id: Dictionary = {}
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	for node_id_value: Variant in nodes_by_id.keys():
		outgoing[str(node_id_value)] = []
		incoming[str(node_id_value)] = []
	for index: int in range((plan["edges"] as Array).size()):
		var edge_value: Variant = (plan["edges"] as Array)[index]
		if not edge_value is Dictionary:
			return _error("edges[%d]" % index, "expected_dictionary")
		var edge: Dictionary = edge_value
		var edge_error := _edge_error(edge, nodes_by_id, index)
		if not edge_error.is_empty():
			return edge_error
		var edge_id := str(edge["id"])
		if edges_by_id.has(edge_id):
			return _error("edges[%d].id" % index, "duplicate")
		edges_by_id[edge_id] = edge
		(outgoing[str(edge["source_node_id"])] as Array).append(edge)
		(incoming[str(edge["destination_node_id"])] as Array).append(edge)
	if not (incoming["entry"] as Array).is_empty() or not (outgoing["boss"] as Array).is_empty():
		return _error("edges", "terminal_direction_invalid")
	for node_id_value: Variant in nodes_by_id.keys():
		var node_id := str(node_id_value)
		if node_id != "entry" and (incoming[node_id] as Array).is_empty():
			return _error("edges", "orphan_node")
		if node_id != "boss" and (outgoing[node_id] as Array).is_empty():
			return _error("edges", "dead_end_node")
		if (outgoing[node_id] as Array).size() > 3:
			return _error("edges", "too_many_choices")
		var orders: Array[int] = []
		for edge_value: Variant in outgoing[node_id]:
			orders.append(int((edge_value as Dictionary)["choice_order"]))
		orders.sort()
		for order_index: int in range(orders.size()):
			if orders[order_index] != order_index:
				return _error("edges", "choice_order_not_contiguous")

	var reachable := _reachable_nodes("entry", outgoing, false)
	if reachable.size() != nodes_by_id.size():
		return _error("edges", "unreachable_node")
	var reaches_boss := _reachable_nodes("boss", incoming, true)
	if reaches_boss.size() != nodes_by_id.size():
		return _error("edges", "node_cannot_reach_boss")
	var paths: Array[Array] = []
	_collect_paths("entry", "boss", outgoing, [], paths)
	if paths.is_empty():
		return _error("edges", "boss_unreachable")
	for path: Array in paths:
		var path_error := _path_error(path, nodes_by_id, floor)
		if not path_error.is_empty():
			return path_error

	var state_error := _state_error(plan, nodes_by_id, edges_by_id)
	if not state_error.is_empty():
		return state_error
	if str(plan["generation_digest"]) != compute_generation_digest(plan):
		return _error("generation_digest", "mismatch")
	return {}


func _node_error(
	node: Dictionary,
	floor: Dictionary,
	templates_by_id: Dictionary,
	index: int
) -> Dictionary:
	var field_prefix := "nodes[%d]" % index
	var fields_error := _exact_fields_error(node, NODE_FIELDS, field_prefix)
	if not fields_error.is_empty():
		return fields_error
	if typeof(node["id"]) != TYPE_STRING or not _valid_id(str(node["id"])):
		return _error("%s.id" % field_prefix, "invalid")
	if typeof(node["layer"]) != TYPE_INT:
		return _error("%s.layer" % field_prefix, "expected_integer")
	var node_id := str(node["id"])
	var layer := int(node["layer"])
	var route_length := int(floor["route_room_min"])
	if layer < 0 or layer > route_length:
		return _error("%s.layer" % field_prefix, "out_of_range")
	for field: String in ["room_type", "template_id", "encounter_id", "event_id", "merchant_id", "reward_policy_id", "seed_channel_suffix"]:
		if typeof(node[field]) != TYPE_STRING:
			return _error("%s.%s" % [field_prefix, field], "expected_string")
	for field: String in ["revealed", "visited", "cleared"]:
		if typeof(node[field]) != TYPE_BOOL:
			return _error("%s.%s" % [field_prefix, field], "expected_boolean")
	if node_id == "entry":
		if layer != 0 or str(node["room_type"]) != "entry":
			return _error(field_prefix, "entry_invalid")
		for field: String in ["template_id", "encounter_id", "event_id", "merchant_id", "reward_policy_id"]:
			if not str(node[field]).is_empty():
				return _error("%s.%s" % [field_prefix, field], "entry_field_must_be_empty")
		if not bool(node["revealed"]) or not bool(node["visited"]) or not bool(node["cleared"]):
			return _error(field_prefix, "entry_state_invalid")
		return {}
	var room_type := str(node["room_type"])
	if node_id == "boss":
		if layer != route_length or room_type != "boss":
			return _error(field_prefix, "boss_identity_invalid")
	elif room_type == "boss":
		return _error(field_prefix, "boss_identity_invalid")
	if node_id != "boss" and (layer == 0 or layer == route_length):
		return _error(field_prefix, "action_layer_invalid")
	if not (floor["allowed_room_types"] as Array).has(room_type):
		return _error("%s.room_type" % field_prefix, "unsupported")
	var template_id := str(node["template_id"])
	if not templates_by_id.has(template_id):
		return _error("%s.template_id" % field_prefix, "unknown")
	var template: Dictionary = templates_by_id[template_id]
	if str(template["room_type"]) != room_type:
		return _error("%s.template_id" % field_prefix, "unknown_or_type_mismatch")
	if not (template["floor_ids"] as Array).has(str(floor["id"])):
		return _error("%s.template_id" % field_prefix, "floor_incompatible")
	if not (template["supported_environment_rule_ids"] as Array).has(str(floor["environment_rule_id"])):
		return _error("%s.template_id" % field_prefix, "environment_incompatible")
	if not RewardPolicyProtocolScript.matches(room_type, str(node["reward_policy_id"])):
		return _error("%s.reward_policy_id" % field_prefix, "mismatch")
	if str(node["seed_channel_suffix"]) != node_id:
		return _error("%s.seed_channel_suffix" % field_prefix, "mismatch")
	var expected_encounter := ""
	if room_type == "combat" or room_type == "elite":
		expected_encounter = str(floor["encounter_profile_id"])
	elif room_type == "boss":
		expected_encounter = str(floor["boss_encounter_id"])
	if str(node["encounter_id"]) != expected_encounter:
		return _error("%s.encounter_id" % field_prefix, "mismatch")
	if room_type == "event":
		if not (floor["event_ids"] as Array).has(str(node["event_id"])):
			return _error("%s.event_id" % field_prefix, "unknown_or_incompatible")
	elif not str(node["event_id"]).is_empty():
		return _error("%s.event_id" % field_prefix, "unexpected")
	if room_type == "shop":
		if not (floor["merchant_ids"] as Array).has(str(node["merchant_id"])):
			return _error("%s.merchant_id" % field_prefix, "unknown_or_incompatible")
	elif not str(node["merchant_id"]).is_empty():
		return _error("%s.merchant_id" % field_prefix, "unexpected")
	if room_type == "boss":
		if template_id != str(floor["boss_room_template_id"]):
			return _error("%s.template_id" % field_prefix, "floor_boss_mismatch")
	elif (
		template_id == str(floor["boss_room_template_id"])
		or str(node["encounter_id"]) == str(floor["boss_encounter_id"])
	):
		return _error(field_prefix, "boss_authority_reserved")
	return {}


func _edge_error(edge: Dictionary, nodes_by_id: Dictionary, index: int) -> Dictionary:
	var field_prefix := "edges[%d]" % index
	var fields_error := _exact_fields_error(edge, EDGE_FIELDS, field_prefix)
	if not fields_error.is_empty():
		return fields_error
	for field: String in ["id", "source_node_id", "destination_node_id"]:
		if typeof(edge[field]) != TYPE_STRING or not _valid_id(str(edge[field])):
			return _error("%s.%s" % [field_prefix, field], "invalid")
	if not nodes_by_id.has(str(edge["source_node_id"])) or not nodes_by_id.has(str(edge["destination_node_id"])):
		return _error(field_prefix, "unknown_node")
	var source: Dictionary = nodes_by_id[str(edge["source_node_id"])]
	var destination: Dictionary = nodes_by_id[str(edge["destination_node_id"])]
	if int(destination["layer"]) != int(source["layer"]) + 1:
		return _error(field_prefix, "edge_must_advance_one_layer")
	if typeof(edge["choice_order"]) != TYPE_INT or int(edge["choice_order"]) < 0:
		return _error("%s.choice_order" % field_prefix, "invalid")
	if typeof(edge["locked"]) != TYPE_BOOL:
		return _error("%s.locked" % field_prefix, "expected_boolean")
	if bool(edge["locked"]):
		return _error("%s.locked" % field_prefix, "unsupported")
	if not edge["route_summary_facts"] is Dictionary:
		return _error("%s.route_summary_facts" % field_prefix, "expected_dictionary")
	var facts: Dictionary = edge["route_summary_facts"]
	var facts_error := _exact_fields_error(facts, ROUTE_SUMMARY_FIELDS, "%s.route_summary_facts" % field_prefix)
	if not facts_error.is_empty():
		return facts_error
	if str(facts.get("room_type", "")) != str(destination["room_type"]) or str(facts.get("template_id", "")) != str(destination["template_id"]):
		return _error("%s.route_summary_facts" % field_prefix, "destination_mismatch")
	return {}


func _path_error(path: Array, nodes_by_id: Dictionary, floor: Dictionary) -> Dictionary:
	var route_length := int(floor["route_room_min"])
	if path.size() - 1 != route_length:
		return _error("paths", "route_length_mismatch")
	var types: Array[String] = []
	var previous_template_id := ""
	var combat_streak := 0
	for path_index: int in range(1, path.size()):
		var node: Dictionary = nodes_by_id[str(path[path_index])]
		var room_type := str(node["room_type"])
		types.append(room_type)
		if room_type == "combat" or room_type == "elite":
			combat_streak += 1
			if combat_streak > 3:
				return _error("paths", "combat_streak_exceeded")
		else:
			combat_streak = 0
		var template_id := str(node["template_id"])
		if template_id == previous_template_id:
			return _error("paths", "immediate_template_repetition")
		previous_template_id = template_id
	var budgets: Dictionary = floor["required_room_budgets"]
	if types.count("boss") != int(budgets["boss_count"]):
		return _error("paths", "boss_budget_mismatch")
	if types.count("event") < int(budgets["event_min"]):
		return _error("paths", "event_budget_mismatch")
	if types.count("shop") < int(budgets["shop_min"]):
		return _error("paths", "shop_budget_mismatch")
	if types.count("treasure") < int(budgets["treasure_min"]):
		return _error("paths", "treasure_budget_mismatch")
	if types.count("shop") + types.count("treasure") < int(budgets["shop_or_treasure_min"]):
		return _error("paths", "economy_room_budget_mismatch")
	if types.count("rest") != int(budgets["rest_min"]):
		return _error("paths", "rest_budget_mismatch")
	if int(budgets["rest_min"]) == 1 and types.find("rest") != route_length - 3:
		return _error("paths", "rest_position_mismatch")
	return {}


func _state_error(plan: Dictionary, nodes_by_id: Dictionary, edges_by_id: Dictionary) -> Dictionary:
	var selected_result := _unique_known_strings(plan["selected_edge_ids"], edges_by_id, "selected_edge_ids")
	if not selected_result.is_empty():
		return selected_result
	var visited_result := _unique_known_strings(plan["visited_node_ids"], nodes_by_id, "visited_node_ids")
	if not visited_result.is_empty():
		return visited_result
	var abandoned_result := _unique_known_strings(plan["abandoned_node_ids"], nodes_by_id, "abandoned_node_ids")
	if not abandoned_result.is_empty():
		return abandoned_result
	var cursor := str(plan["entry_node_id"])
	var expected_visited: Array[String] = [cursor]
	for selected_id_value: Variant in plan["selected_edge_ids"]:
		var edge: Dictionary = edges_by_id[str(selected_id_value)]
		if bool(edge["locked"]):
			return _error("selected_edge_ids", "selected_edge_locked")
		if (
			(plan["abandoned_node_ids"] as Array).has(str(edge["source_node_id"]))
			or (plan["abandoned_node_ids"] as Array).has(str(edge["destination_node_id"]))
		):
			return _error("selected_edge_ids", "selected_edge_abandoned")
		if str(edge["source_node_id"]) != cursor:
			return _error("selected_edge_ids", "not_a_route_prefix")
		cursor = str(edge["destination_node_id"])
		expected_visited.append(cursor)
	if cursor != str(plan["current_node_id"]):
		return _error("current_node_id", "route_prefix_mismatch")
	if (plan["visited_node_ids"] as Array) != expected_visited:
		return _error("visited_node_ids", "route_prefix_mismatch")
	if int(plan["revision"]) != (plan["selected_edge_ids"] as Array).size():
		return _error("revision", "route_prefix_mismatch")
	var expected_abandoned := _expected_abandoned_node_ids(plan)
	if (plan["abandoned_node_ids"] as Array) != expected_abandoned:
		return _error("abandoned_node_ids", "route_prefix_mismatch")
	for node_id_value: Variant in nodes_by_id.keys():
		var node_id := str(node_id_value)
		var node: Dictionary = nodes_by_id[node_id]
		var expected_visit := expected_visited.has(node_id)
		if bool(node["visited"]) != expected_visit:
			return _error("nodes", "visited_flag_mismatch")
		if expected_visit and not bool(node["revealed"]):
			return _error("nodes", "visited_node_not_revealed")
		if node_id == str(plan["entry_node_id"]):
			continue
		if not expected_visit and bool(node["cleared"]):
			return _error("nodes", "unvisited_node_cleared")
		if expected_visit and node_id != cursor and not bool(node["cleared"]):
			return _error("nodes", "historical_node_not_cleared")
	return {}


func _expected_abandoned_node_ids(plan: Dictionary) -> Array[String]:
	var outgoing: Dictionary = {}
	for node_value: Variant in plan.get("nodes", []):
		outgoing[str((node_value as Dictionary)["id"])] = []
	for edge_value: Variant in plan.get("edges", []):
		var edge: Dictionary = edge_value
		(outgoing[str(edge["source_node_id"])] as Array).append(edge)
	var reachable := _reachable_nodes(str(plan.get("current_node_id", "")), outgoing, false)
	var visited: Array = plan.get("visited_node_ids", [])
	var abandoned: Array[String] = []
	for node_value: Variant in plan.get("nodes", []):
		var node_id := str((node_value as Dictionary)["id"])
		if not reachable.has(node_id) and not visited.has(node_id):
			abandoned.append(node_id)
	return abandoned


static func _reachable_nodes(start_id: String, adjacency: Dictionary, reverse: bool) -> Dictionary:
	var reached: Dictionary = {}
	var pending: Array[String] = [start_id]
	while not pending.is_empty():
		var node_id: String = pending.pop_front()
		if reached.has(node_id):
			continue
		reached[node_id] = true
		for edge_value: Variant in adjacency.get(node_id, []):
			var edge: Dictionary = edge_value
			var next_id := str(edge["source_node_id"] if reverse else edge["destination_node_id"])
			if not reached.has(next_id):
				pending.append(next_id)
	return reached


static func _collect_paths(
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
	for edge_value: Variant in outgoing.get(node_id, []):
		_collect_paths(
			str((edge_value as Dictionary)["destination_node_id"]),
			boss_node_id,
			outgoing,
			next_prefix,
			paths
		)


static func _unique_known_strings(value: Variant, known: Dictionary, field: String) -> Dictionary:
	if not value is Array:
		return _error(field, "expected_array")
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var item: Variant = (value as Array)[index]
		if typeof(item) != TYPE_STRING or not known.has(str(item)):
			return _error("%s[%d]" % [field, index], "unknown")
		if seen.has(str(item)):
			return _error("%s[%d]" % [field, index], "duplicate")
		seen[str(item)] = true
	return {}


static func _exact_fields_error(value: Dictionary, fields: Array[String], field: String) -> Dictionary:
	if value.size() != fields.size():
		return _error(field, "field_count_mismatch")
	for expected: String in fields:
		if not value.has(expected):
			return _error("%s.%s" % [field, expected], "missing")
	return {}


static func _valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	for character: String in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_.-":
			return false
	return true


static func _error(field: String, reason: String) -> Dictionary:
	return {"field": field, "reason": reason}
