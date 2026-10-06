class_name RunEndOverlay
extends CanvasLayer

signal hub_return_requested
const Phase := preload("res://scripts/application/run_phase.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")

@onready var panel: PanelContainer = $Panel
@onready var result_label: Label = $Panel/Margin/VBox/ResultLabel
@onready var restart_button: Button = $Panel/Margin/VBox/RestartButton
var _profile_return := false
var _host: Node
var _presented_run_id := ""
var _result: Dictionary = {}
var _save_pending := false
var _retry_only := false
var _title: Label
var _summary: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer


func _ready() -> void:
	_host = get_parent().get_node_or_null("RunRuntimeHost")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_graphical_layout()
	restart_button.text = tr("UI_RESTART_RUN")
	EventBus.run_ended.connect(_on_run_ended)
	restart_button.pressed.connect(_restart_run)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()


func _build_graphical_layout() -> void:
	var margin := $Panel/Margin as MarginContainer
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var layout := $Panel/Margin/VBox as VBoxContainer
	layout.add_theme_constant_override("separation", 6)
	result_label.hide()
	_title = _label("ResultTitle", 18)
	_title.theme_type_variation = &"DisplayLabel"
	layout.add_child(_title)
	layout.move_child(_title, restart_button.get_index())
	_summary = _label("ResultSummary", 11)
	layout.add_child(_summary)
	layout.move_child(_summary, restart_button.get_index())
	_scroll = ScrollContainer.new()
	_scroll.name = "ResultScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	_scroll.gui_input.connect(_scroll_history)
	layout.add_child(_scroll)
	layout.move_child(_scroll, restart_button.get_index())
	_rows = VBoxContainer.new()
	_rows.name = "ResultRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows)
	restart_button.custom_minimum_size = Vector2(0, 28)
	restart_button.add_theme_font_size_override("font_size", 12)
	Art.button_icon(restart_button, Art.icon(&"controls", &"back"))


func _fit_panel() -> void:
	var available := get_viewport().get_visible_rect().size - Vector2(32, 32)
	var extent := Vector2(minf(616, available.x), minf(560, available.y))
	panel.custom_minimum_size = Vector2.ZERO
	panel.offset_left = -extent.x / 2
	panel.offset_top = -extent.y / 2
	panel.offset_right = extent.x / 2
	panel.offset_bottom = extent.y / 2


func _label(label_name: String, font_size: int = 12) -> Label:
	var label := Label.new()
	label.name = label_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_run_ended(run_id: String, result: Dictionary, _revision: int) -> void:
	if _host != null:
		var native: Dictionary = _host.runtime_snapshot()
		if native.get("run_id") != run_id or not Phase.is_terminal(int(native.get("phase", -1))):
			return
	if _presented_run_id == run_id:
		return
	_presented_run_id = run_id
	_result = result.duplicate(true)
	_save_pending = false
	_retry_only = false
	_refresh_result()
	visible = true
	FocusCoordinator.link_ring([_scroll, restart_button], false)
	FocusCoordinator.open_scope(self, restart_button)


func _refresh_result() -> void:
	var result := _result
	var outcome := str(result.get("result", ""))
	var title := tr("UI_RUN_COMPLETE") if outcome in ["floor_cleared", "victory"] else tr("UI_RUN_FAILED")
	result_label.text = "%s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s" % [
		title,
		tr("UI_ROOM_REACHED"), result.get("current_room", result.get("rooms_cleared", 0)),
		tr("UI_ROOMS_CLEARED"), result.get("rooms_cleared", 0),
		tr("UI_KILLS"), result.get("kills", 0),
		tr("UI_TIME"), _format_time(float(result.get("run_time", 0.0))),
		tr("UI_ITEMS"), _names_for(result.get("rewards", [])),
		tr("UI_BLESSINGS"), _names_for(result.get("blessings", [])),
		tr("UI_TALENTS"), _names_for(result.get("talent_choices", [])),
		tr("UI_CURSES"), _names_for(result.get("curses", [])),
	]
	_title.text = title
	_title.add_theme_color_override("font_color", Color("79baa1") if outcome in ["floor_cleared", "victory"] else Color("f07065"))
	_summary.text = "%s: %d  /  %s: %d  /  %s %s  /  %s: %d" % [tr("UI_ROOM_REACHED"), int(result.get("current_room", 0)), tr("UI_ROOMS_CLEARED"), int(result.get("rooms_cleared", 0)), tr("UI_TIME"), _format_time(float(result.get("run_time", 0.0))), tr("UI_KILLS"), int(result.get("kills", 0))]
	if _retry_only:
		_title.text = tr("UI_RUN_COMPLETE")
		_summary.text = tr("UI_SETTLEMENT_RETRY")
	var position := _scroll.scroll_vertical
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not _retry_only:
		for pair: Array in [["rewards", "UI_ITEMS"], ["blessings", "UI_BLESSINGS"], ["talent_choices", "UI_TALENTS"], ["curses", "UI_CURSES"]]:
			var heading := _label("ResultPool_" + str(pair[0]), 12)
			heading.text = tr(str(pair[1]))
			heading.add_theme_color_override("font_color", Color("e5bd69"))
			_rows.add_child(heading)
			var entries: Array = result.get(pair[0], [])
			if entries.is_empty():
				var empty := _label("EmptyPool", 11)
				empty.text = "-"
				_rows.add_child(empty)
				continue
			var grid := GridContainer.new()
			grid.columns = 2
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 4)
			_rows.add_child(grid)
			for value: Variant in entries:
				var entry := value as Dictionary if value is Dictionary else {"id": str(value)}
				var row := HBoxContainer.new()
				row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_theme_constant_override("separation", 6)
				grid.add_child(row)
				row.add_child(Art.image(Art.content(str(entry.get("id", "")), str(entry.get("category", ""))), 24, "ResultContent_" + str(entry.get("id", ""))))
				var name_label := _label("ContentName", 11)
				name_label.text = tr(str(entry.get("name_key", entry.get("name", entry.get("id", "")))))
				row.add_child(name_label)
	_scroll.scroll_vertical = position
	_refresh_action()
	for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
		runtime.call("apply_to_tree", self)
		break
	_fit_panel()


func _restart_run() -> void:
	if _profile_return:
		hub_return_requested.emit()
		return
	FocusCoordinator.close_scope(self)
	get_tree().reload_current_scene()


func configure_profile_return(value: bool) -> void:
	_profile_return = value
	_refresh_action()


func _refresh_action() -> void:
	restart_button.text = tr("UI_RETRY") if _save_pending else tr("UI_RETURN_HUB" if _profile_return else "UI_RESTART_RUN")
	restart_button.tooltip_text = tr("UI_SETTLEMENT_RETRY") if _save_pending else ""
	Art.button_icon(restart_button, Art.icon(&"controls", &"restart" if _save_pending or not _profile_return else &"back"))


func show_save_pending() -> void:
	_save_pending = true
	_refresh_action()


func show_victory_save_retry() -> void:
	show_save_pending()
	_retry_only = true
	_refresh_result()
	result_label.text = tr("UI_SETTLEMENT_RETRY")
	visible = true
	FocusCoordinator.open_scope(self, restart_button)


func hide_overlay() -> void:
	FocusCoordinator.close_scope(self)
	visible = false
	_save_pending = false
	_retry_only = false
	restart_button.tooltip_text = ""
	configure_profile_return(_profile_return)


func _format_time(seconds: float) -> String:
	var total_seconds := maxi(0, roundi(seconds))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _names_for(entries: Array) -> String:
	if entries.is_empty():
		return "-"
	var names: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			var dict := entry as Dictionary
			names.append(tr(str(dict.get("name_key", dict.get("name", dict.get("id", "unknown"))))))
		else:
			names.append(str(entry))
	return ", ".join(names)


func _scroll_history(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") and _scroll.scroll_vertical > 0:
		_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - 48)
		_scroll.accept_event()
	elif event.is_action_pressed("ui_down") and _scroll.scroll_vertical + _scroll.size.y < _scroll.get_v_scroll_bar().max_value:
		_scroll.scroll_vertical += 48
		_scroll.accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_result()
