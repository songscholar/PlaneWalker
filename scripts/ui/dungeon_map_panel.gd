class_name DungeonMapPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

const Contract := preload("res://scripts/ui/contracts/dungeon_map_view_state.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")

class RouteGraph extends Control:
	const GraphArt := preload("res://scripts/ui/style/ui_artwork.gd")
	var nodes: Array = []
	var edges: Array = []
	var _labels: Dictionary = {}
	var _points: Dictionary = {}

	func configure(projected_nodes: Array, projected_edges: Array) -> void:
		nodes = projected_nodes.duplicate(true)
		edges = projected_edges.duplicate(true)
		var last_layer := 0
		for node: Dictionary in nodes:
			last_layer = maxi(last_layer, int(node["layer"]))
		custom_minimum_size = Vector2(0, (last_layer + 1) * 64)
		for node: Dictionary in nodes:
			var label := Button.new()
			label.tooltip_text = tr(node["name_key"])
			label.name = "MapNode_%s" % node["id"]
			label.focus_mode = Control.FOCUS_ALL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.clip_text = true
			label.add_theme_font_size_override("font_size", 10)
			label.set_meta("available", true)
			label.set_meta("room_type", node["room_type"])
			label.set_meta("action_id", "map_node:" + str(node["id"]))
			label.icon = GraphArt.icon(&"room_types", StringName(node["room_type"]))
			label.expand_icon = true
			label.add_theme_constant_override("icon_max_width", 24)
			label.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			label.focus_entered.connect(queue_redraw)
			label.focus_exited.connect(queue_redraw)
			var transparent := StyleBoxEmpty.new()
			for mode: String in ["normal", "hover", "pressed", "focus"]:
				label.add_theme_stylebox_override(mode, transparent)
			add_child(label)
			_labels[node["id"]] = label
		resized.connect(_layout_nodes)
		_layout_nodes()

	func _layout_nodes() -> void:
		var layers: Dictionary = {}
		for node: Dictionary in nodes:
			var layer := int(node["layer"])
			if not layers.has(layer):
				layers[layer] = []
			layers[layer].append(node)
		for layer: int in layers:
			var siblings: Array = layers[layer]
			for index: int in range(siblings.size()):
				var node: Dictionary = siblings[index]
				var point := Vector2(size.x * float(index + 1) / float(siblings.size() + 1), layer * 64 + 25)
				_points[node["id"]] = point
				var label := _labels[node["id"]] as Button
				label.position = point - Vector2(24, 24)
				label.size = Vector2(48, 48)
		queue_redraw()

	func _draw() -> void:
		for edge: Dictionary in edges:
			if not _points.has(edge["source_node_id"]) or not _points.has(edge["destination_node_id"]):
				continue
			var color := Color("61d5e7") if edge["selected"] else Color("697771")
			draw_line(_points[edge["source_node_id"]] + Vector2(0, 24), _points[edge["destination_node_id"]] - Vector2(0, 24), color, 2 if edge["selected"] else 1, false)
		for node: Dictionary in nodes:
			if not _points.has(node["id"]):
				continue
			var point: Vector2 = _points[node["id"]]
			var rectangle := Rect2(point - Vector2(24, 24), Vector2(48, 48))
			var focused := (_labels[node["id"]] as Button).has_focus()
			var color := Color("e5bd69") if focused else Color("61d5e7") if node["current"] else Color("79baa1") if node["cleared"] else Color("edf0dc") if node["revealed"] else Color("697771")
			draw_style_box(_node_style(color, bool(node["current"])), rectangle)

	func _node_style(color: Color, current: bool) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("111619")
		style.border_color = color
		style.set_border_width_all(2 if current else 1)
		style.set_corner_radius_all(2)
		return style


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr("UI_DUNGEON_MAP")
	summary_label.text = "%s  |  %s  |  %s" % [tr(_state["floor_name_key"]), tr("UI_GOLD_FMT") % int(_state["gold"]), tr("UI_BOSS_DISTANCE_FMT") % int(_state["boss_distance"])]
	var nodes: Array = (_state["nodes"] as Array).duplicate(true)
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["layer"]) < int(b["layer"]) if a["layer"] != b["layer"] else str(a["id"]) < str(b["id"]))
	var graph := RouteGraph.new()
	graph.name = "RouteGraph"
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_child(graph)
	graph.configure(nodes, _state["edges"])
	for node: Dictionary in nodes:
		_actions.append(graph._labels[node["id"]] as Control)
	for node: Dictionary in nodes:
		var layer := int(node["layer"])
		var status := "UI_ROUTE_CURRENT" if node["current"] else "UI_ROUTE_CLEARED" if node["cleared"] else "UI_ROUTE_VISITED" if node["visited"] else "UI_ROUTE_UNEXPLORED"
		_add_text("%s  |  %s  |  %s" % [tr("UI_MAP_LAYER_FMT") % layer, tr(node["name_key"]), tr(status)], "Node_%s" % node["id"])
