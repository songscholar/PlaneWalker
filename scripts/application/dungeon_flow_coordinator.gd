class_name DungeonFlowCoordinator
extends Node

const Projector := preload("res://scripts/application/run_view_state_projector.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const PANEL_SCENES := {
	"route": preload("res://scenes/ui/route_choice_panel.tscn"),
	"map": preload("res://scenes/ui/dungeon_map_panel.tscn"),
	"merchant": preload("res://scenes/ui/merchant_panel.tscn"),
	"event": preload("res://scenes/ui/dungeon_event_panel.tscn"),
	"interaction": preload("res://scenes/ui/room_interaction_panel.tscn"),
	"transition": preload("res://scenes/ui/floor_transition_panel.tscn"),
}

@export var runtime_host_path: NodePath

var _host: Node
var _projector: RefCounted = Projector.new()
var _layer: CanvasLayer
var _panels: Dictionary = {}
var _active_panel: Control
var _map_button: Button
var _last_stamp := ""
var _closed_stamp := ""
var _map_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_host = get_node_or_null(runtime_host_path)
	_layer = CanvasLayer.new()
	_layer.name = "DungeonLayer"
	_layer.layer = 37
	add_child(_layer)
	for key: String in PANEL_SCENES:
		var panel := (PANEL_SCENES[key] as PackedScene).instantiate() as Control
		_layer.add_child(panel)
		panel.connect("close_requested", _on_panel_close.bind(key))
		_panels[key] = panel
	_panels["route"].connect("route_requested", _on_route)
	_panels["merchant"].connect("merchant_action_requested", _on_merchant_action)
	_panels["merchant"].connect("leave_requested", _on_merchant_leave)
	_panels["event"].connect("event_option_requested", _on_event_option)
	_panels["event"].connect("event_reward_requested", _on_event_reward)
	_panels["event"].connect("dismiss_requested", _on_event_dismiss)
	_panels["interaction"].connect("room_choice_requested", _on_room_choice)
	_panels["transition"].connect("floor_transition_requested", _on_floor_transition)
	_map_button = Button.new()
	_map_button.name = "MapButton"
	_map_button.text = tr("UI_DUNGEON_MAP")
	_map_button.tooltip_text = tr("UI_DUNGEON_MAP")
	_map_button.position = Vector2(526, 6)
	_map_button.size = Vector2(106, 25)
	_map_button.add_theme_font_size_override("font_size", 11)
	_map_button.focus_mode = Control.FOCUS_ALL
	_map_button.pressed.connect(open_map)
	_layer.add_child(_map_button)
	_map_button.visible = false


func _process(_delta: float) -> void:
	if _host == null or get_tree().paused:
		return
	var state: Dictionary = _host.call("runtime_snapshot")
	var stamp := _state_stamp(state)
	if stamp != _last_stamp:
		refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _map_button != null:
		_map_button.text = tr("UI_DUNGEON_MAP")
		_map_button.tooltip_text = tr("UI_DUNGEON_MAP")


func active_panel() -> Control:
	return _active_panel if _active_panel != null and _active_panel.visible else null


func refresh(force: bool = false) -> void:
	if _host == null:
		return
	var context: Dictionary = _host.call("dungeon_ui_context")
	var state := context.get("state", {}) as Dictionary
	var stamp := _state_stamp(state)
	_last_stamp = stamp
	var enabled := not context.is_empty() and not Phase.is_terminal(int(state.get("phase", -1)))
	_map_button.visible = enabled and _active_panel == null
	if not enabled:
		_close_panels()
		return
	if not force and stamp == _closed_stamp:
		return
	if int(state.get("phase", -1)) == Phase.Value.SELECTION_ACTIVE:
		_close_panels()
		return
	if _map_open:
		_show_map(context)
		return
	var phase := int(state.get("phase", -1))
	var plan := state.get("floor_plan", {}) as Dictionary
	if phase == Phase.Value.RUN_PREPARING:
		_show("transition", _projector.call("project_floor_transition", state, context["floors"]))
		return
	if str(plan.get("current_node_id", "")) == "entry" or phase == Phase.Value.ROOM_RESOLVING:
		_show("route", _project_map(context))
		return
	var room := context.get("room", {}) as Dictionary
	match str(room.get("room_type", "")):
		"shop":
			_show("merchant", _projector.call("project_merchant", state, context["merchant"], context["content"], context["merchant_services"]))
		"event":
			var event := context.get("event", {}) as Dictionary
			if str(event.get("phase", "")) == "pending_encounter":
				_close_panels()
				return
			_show("event", _projector.call("project_dungeon_event", state, event, context["event_reward"]))
		"treasure", "rest":
			_show("interaction", _projector.call("project_room_interaction", state, context["interaction"]))
		_:
			_close_panels()


func open_map() -> bool:
	if _host == null or get_tree().paused:
		return false
	var context: Dictionary = _host.call("dungeon_ui_context")
	if context.is_empty() or int(context["state"].get("phase", -1)) == Phase.Value.SELECTION_ACTIVE:
		return false
	if Phase.is_terminal(int(context["state"].get("phase", -1))):
		return false
	_map_open = true
	_closed_stamp = ""
	_show_map(context)
	return active_panel() == _panels["map"]


func handle_input(event: InputEvent) -> bool:
	if _host == null or get_tree().paused or event.is_echo():
		return false
	var state: Dictionary = _host.call("runtime_snapshot")
	if str(state.get("config", {}).get("milestone", "")) not in ["LAUNCH", "EXPANSION"]:
		return false
	if event.is_action_pressed("ui_cancel") and active_panel() != null:
		_active_panel.call("_request_close")
		return true
	var map_pressed: bool = event is InputEventKey and event.pressed and event.keycode == KEY_TAB
	map_pressed = map_pressed or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK)
	if map_pressed:
		if _map_open and active_panel() != null:
			_active_panel.call("_request_close")
			return true
		return open_map()
	if event.is_action_pressed("interact") and active_panel() == null:
		_closed_stamp = ""
		refresh(true)
		return active_panel() != null
	return false


func _show_map(context: Dictionary) -> void:
	_show("map", _project_map(context))


func _project_map(context: Dictionary) -> Variant:
	var state := context["state"] as Dictionary
	var floor_id := str(state["floor_plan"].get("floor_id", ""))
	var floor: Dictionary = {}
	for definition: Dictionary in context["floors"]:
		if str(definition["id"]) == floor_id:
			floor = definition
			break
	return _projector.call("project_dungeon_map", state, context["routes"], floor)


func _show(key: String, result: Variant) -> void:
	if result == null or not bool(result.get("ok")):
		_close_panels()
		return
	var panel := _panels[key] as Control
	if _active_panel != panel:
		_close_panels(false)
	var rendered: Variant = panel.call("render", result.context["view_state"])
	if rendered == null or not bool(rendered.get("ok")):
		_close_panels()
		return
	_active_panel = panel
	_map_button.visible = false
	_host.call("set_dungeon_selection_safety", true)


func _close_panels(release_safety: bool = true) -> void:
	for panel: Control in _panels.values():
		panel.call("close_panel")
	_active_panel = null
	_map_button.visible = false
	if _host != null:
		var context: Dictionary = _host.call("dungeon_ui_context")
		var phase := int(context.get("state", {}).get("phase", -1))
		_map_button.visible = not context.is_empty() and not Phase.is_terminal(phase) and phase != Phase.Value.SELECTION_ACTIVE
		if release_safety:
			_host.call("set_dungeon_selection_safety", false)


func _on_panel_close(_revision: int, key: String) -> void:
	_active_panel = null
	_host.call("set_dungeon_selection_safety", false)
	if key == "map":
		_map_open = false
		_closed_stamp = ""
		refresh(true)
		return
	_closed_stamp = _last_stamp
	_map_button.visible = true


func _on_route(edge_id: StringName, revision: int) -> void:
	_handle_result(_host.call("select_route", edge_id, revision))


func _on_merchant_action(action_id: StringName, target_id: StringName, revision: int) -> void:
	_handle_result(_host.call("merchant_action", action_id, target_id, revision))


func _on_merchant_leave(revision: int) -> void:
	_handle_result(_host.call("leave_merchant", revision))


func _on_event_option(_event_id: StringName, option_id: StringName, revision: int) -> void:
	_handle_result(_host.call("choose_event_option", option_id, revision))


func _on_event_reward(option_id: StringName, revision: int) -> void:
	_handle_result(_host.call("submit_event_reward", option_id, revision))


func _on_event_dismiss(_event_id: StringName, revision: int) -> void:
	_handle_result(_host.call("dismiss_event", revision))


func _on_room_choice(choice_id: StringName, revision: int) -> void:
	_handle_result(_host.call("resolve_room_interaction", choice_id, revision))


func _on_floor_transition(revision: int) -> void:
	_handle_result(_host.call("start_next_floor", revision))


func _handle_result(result: Variant) -> void:
	if result != null and bool(result.get("ok")):
		_closed_stamp = ""
		refresh(true)
		return
	if active_panel() != null:
		_active_panel.call("show_rejection", "UI_DUNGEON_COMMAND_REJECTED")


func _state_stamp(state: Dictionary) -> String:
	return "%s:%d:%d:%s" % [
		str(state.get("run_id", "")), int(state.get("revision", -1)),
		int(state.get("phase", -1)), str(state.get("floor_plan", {}).get("current_node_id", "")),
	]
