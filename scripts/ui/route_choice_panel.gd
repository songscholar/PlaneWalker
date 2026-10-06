class_name RouteChoicePanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal route_requested(edge_id: StringName, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/dungeon_map_view_state.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const MapView := preload("res://scripts/ui/dungeon_map_panel.gd")
const Page := preload("res://scripts/ui/hub_pages/hub_page_layout.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr("UI_ROUTE_CHOICE")
	summary_label.text = "%s  |  %s  |  %s" % [tr(_state["floor_name_key"]), tr("UI_GOLD_FMT") % int(_state["gold"]), tr("UI_BOSS_DISTANCE_FMT") % int(_state["boss_distance"])]
	var routes: Array = (_state["routes"] as Array).duplicate(true)
	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["choice_order"]) < int(b["choice_order"]))
	var graph := MapView.RouteGraph.new()
	graph.name = "RoutePreview"
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_child(graph)
	graph.configure(_state.nodes, _state.edges)
	for node_button: Button in graph._labels.values():
		node_button.focus_mode = Control.FOCUS_NONE
		node_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var destinations := Page.grid("RouteDestinations")
	rows_container.add_child(destinations)
	for route: Dictionary in routes:
		var action := _add_action(route["edge_id"], tr(route["name_key"]), "", route["available"], route["disabled_reason_key"], _request_route.bind(StringName(route["edge_id"]), int(_state["revision"])))
		Art.button_icon(action, Art.icon(&"room_types", StringName(route.room_type)))
		Page.relocate_row(action, destinations)


func _request_route(edge_id: StringName, revision: int) -> void:
	route_requested.emit(edge_id, revision)
