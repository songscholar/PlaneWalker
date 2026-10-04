class_name RouteChoicePanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal route_requested(edge_id: StringName, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/dungeon_map_view_state.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr("UI_ROUTE_CHOICE")
	summary_label.text = "%s  |  %s  |  %s" % [tr(_state["floor_name_key"]), tr("UI_GOLD_FMT") % int(_state["gold"]), tr("UI_BOSS_DISTANCE_FMT") % int(_state["boss_distance"])]
	var routes: Array = (_state["routes"] as Array).duplicate(true)
	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["choice_order"]) < int(b["choice_order"]))
	for route: Dictionary in routes:
		_add_action(route["edge_id"], tr(route["name_key"]), "", route["available"], route["disabled_reason_key"], _request_route.bind(StringName(route["edge_id"]), int(_state["revision"])))


func _request_route(edge_id: StringName, revision: int) -> void:
	route_requested.emit(edge_id, revision)
