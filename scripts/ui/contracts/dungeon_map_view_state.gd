class_name DungeonMapViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const Floors := preload("res://scripts/dungeon/floor_definition.gd")
const SCHEMA_VERSION := 1
const FIELDS := ["schema_version", "revision", "run_id", "floor_id", "floor_index", "floor_name_key", "gold", "current_node_id", "boss_distance", "nodes", "edges", "routes"]
const NODE_FIELDS := ["id", "layer", "room_type", "name_key", "revealed", "visited", "cleared", "current"]
const EDGE_FIELDS := ["id", "source_node_id", "destination_node_id", "selected"]
const ROUTE_FIELDS := ["edge_id", "node_id", "choice_order", "room_type", "name_key", "available", "disabled_reason_key"]
const ROOM_TYPES := ["entry", "unknown", "combat", "elite", "treasure", "shop", "event", "boss", "rest"]


static func validate(value: Variant):
	if not Rules.header(value, FIELDS):
		return Rules.reject(value, "root")
	var state := value as Dictionary
	if not Floors.FLOOR_IDS.has(state["floor_id"]) or not Rules.integer(state["floor_index"]) or int(state["floor_index"]) != Floors.FLOOR_IDS.find(state["floor_id"]) or not Rules.key(state["floor_name_key"]):
		return Rules.reject(value, "floor")
	for field: String in ["gold", "boss_distance"]:
		if not Rules.integer(state[field]) or int(state[field]) < 0:
			return Rules.reject(value, field)
	for field: String in ["nodes", "edges", "routes"]:
		if not state[field] is Array or state[field].size() > 256:
			return Rules.reject(value, field)
	var nodes: Dictionary = {}
	var current_count := 0
	for node_value: Variant in state["nodes"]:
		if not Rules.exact(node_value, NODE_FIELDS):
			return Rules.reject(value, "nodes")
		var node := node_value as Dictionary
		if not Rules.identifier(node["id"]) or nodes.has(node["id"]) or not Rules.integer(node["layer"]) or int(node["layer"]) < 0 or not _room_copy(node):
			return Rules.reject(value, "nodes.identity")
		for field: String in ["revealed", "visited", "cleared", "current"]:
			if typeof(node[field]) != TYPE_BOOL:
				return Rules.reject(value, "nodes.%s" % field)
		if (node["visited"] and not node["revealed"]) or (node["cleared"] and not node["visited"]) or (node["current"] and (node["id"] != state["current_node_id"] or not node["visited"])):
			return Rules.reject(value, "nodes.knowledge")
		if not node["revealed"] and (node["room_type"] != "unknown" or node["name_key"] != "UI_ROOM_UNKNOWN"):
			return Rules.reject(value, "nodes.hidden")
		current_count += int(node["current"])
		nodes[node["id"]] = node
	if current_count != 1 or not nodes.has(state["current_node_id"]) or not nodes.has("entry") or not nodes.has("boss") or nodes["entry"]["layer"] != 0:
		return Rules.reject(value, "current_node_id")
	var edges: Dictionary = {}
	var pairs: Dictionary = {}
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	var selected_by_source: Dictionary = {}
	for edge_value: Variant in state["edges"]:
		if not Rules.exact(edge_value, EDGE_FIELDS):
			return Rules.reject(value, "edges")
		var edge := edge_value as Dictionary
		if not Rules.identifier(edge["id"]) or edges.has(edge["id"]) or not nodes.has(edge["source_node_id"]) or not nodes.has(edge["destination_node_id"]) or typeof(edge["selected"]) != TYPE_BOOL:
			return Rules.reject(value, "edges.identity")
		var pair := "%s:%s" % [edge["source_node_id"], edge["destination_node_id"]]
		if pairs.has(pair) or int(nodes[edge["destination_node_id"]]["layer"]) != int(nodes[edge["source_node_id"]]["layer"]) + 1:
			return Rules.reject(value, "edges.topology")
		pairs[pair] = true
		edges[edge["id"]] = edge
		if not outgoing.has(edge["source_node_id"]):
			outgoing[edge["source_node_id"]] = []
		if not incoming.has(edge["destination_node_id"]):
			incoming[edge["destination_node_id"]] = []
		(outgoing[edge["source_node_id"]] as Array).append(edge["destination_node_id"])
		(incoming[edge["destination_node_id"]] as Array).append(edge["source_node_id"])
		if edge["selected"]:
			if selected_by_source.has(edge["source_node_id"]) or not nodes[edge["source_node_id"]]["visited"] or not nodes[edge["destination_node_id"]]["visited"]:
				return Rules.reject(value, "edges.selected")
			selected_by_source[edge["source_node_id"]] = edge["destination_node_id"]
	if _reachable("entry", outgoing).size() != nodes.size() or _reachable("boss", incoming).size() != nodes.size():
		return Rules.reject(value, "edges.unreachable")
	var cursor := "entry"
	var traversed := 0
	while selected_by_source.has(cursor):
		cursor = str(selected_by_source[cursor])
		traversed += 1
	if cursor != state["current_node_id"] or traversed != selected_by_source.size():
		return Rules.reject(value, "edges.selected_path")
	var routes: Dictionary = {}
	var orders: Dictionary = {}
	for route_value: Variant in state["routes"]:
		if not Rules.exact(route_value, ROUTE_FIELDS):
			return Rules.reject(value, "routes")
		var route := route_value as Dictionary
		if not edges.has(route["edge_id"]) or routes.has(route["edge_id"]) or not nodes.has(route["node_id"]) or not Rules.integer(route["choice_order"]) or int(route["choice_order"]) < 0 or orders.has(route["choice_order"]) or not _room_copy(route) or not Rules.availability(route):
			return Rules.reject(value, "routes.identity")
		var edge := edges[route["edge_id"]] as Dictionary
		var node := nodes[route["node_id"]] as Dictionary
		if edge["source_node_id"] != state["current_node_id"] or edge["destination_node_id"] != route["node_id"] or edge["selected"] or route["room_type"] != node["room_type"] or route["name_key"] != node["name_key"]:
			return Rules.reject(value, "routes.knowledge")
		routes[route["edge_id"]] = true
		orders[route["choice_order"]] = true
	return Rules.accept(state)


static func copy_of(value: Dictionary) -> Dictionary:
	return value.duplicate(true) if validate(value).ok else {}


static func _room_copy(value: Dictionary) -> bool:
	return ROOM_TYPES.has(value.get("room_type")) and Rules.key(value.get("name_key")) and str(value["name_key"]) == ("UI_ROOM_UNKNOWN" if value["room_type"] == "unknown" else "ROOM_TYPE_%s" % str(value["room_type"]).to_upper())


static func _reachable(start: String, adjacency: Dictionary) -> Dictionary:
	var reached := {start: true}
	var pending: Array[String] = [start]
	while not pending.is_empty():
		var current := pending.pop_back() as String
		for destination: Variant in adjacency.get(current, []):
			if not reached.has(destination):
				reached[destination] = true
				pending.append(str(destination))
	return reached
