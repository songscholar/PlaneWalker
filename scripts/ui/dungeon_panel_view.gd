class_name DungeonPanelView
extends Control

signal close_requested(revision: int)
signal closed

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const PLANE_WALKER_THEME_PATH := "res://assets/production/ui/plane_walker_theme.tres"

var panel_root: PanelContainer
var title_label: Label
var summary_label: Label
var error_label: Label
var scroll: ScrollContainer
var rows_container: VBoxContainer
var footer: HBoxContainer
var back_button: Button
var _state: Dictionary = {}
var _actions: Array[Control] = []
var _submitted := false
var _epoch := 0
var _error_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = load(PLANE_WALKER_THEME_PATH) as Theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	resized.connect(_fit_panel)
	_fit_panel()
	visible = false


func render(state: Dictionary):
	var validation = _validate(state)
	if not validation.ok:
		return validation
	if not _state.is_empty() and state["run_id"] == _state["run_id"]:
		if int(state["revision"]) < int(_state["revision"]):
			return CommandResultScript.failure(&"STALE_REVISION", int(_state["revision"]))
		if state == _state and visible:
			return CommandResultScript.success(int(state["revision"]))
	_state = state.duplicate(true)
	_epoch += 1
	_submitted = false
	_clear_rows()
	error_label.text = ""
	error_label.visible = false
	_error_key = ""
	_render_state()
	_apply_accessibility()
	back_button.text = tr("UI_BACK")
	visible = true
	var controls := _focus_controls()
	FocusCoordinator.link_ring(controls, false)
	if FocusCoordinator.active_scope() == self:
		FocusCoordinator.recover(self, controls[0])
	else:
		FocusCoordinator.open_scope(self, controls[0])
	return CommandResultScript.success(int(_state["revision"]))


func set_view_state(state: Dictionary):
	return render(state)


func view_state() -> Dictionary:
	return _state.duplicate(true)


func action_controls() -> Array[Control]:
	if not _actions.is_empty():
		return _actions.duplicate()
	var controls: Array[Control] = [back_button]
	return controls


func close_panel() -> void:
	if not visible:
		return
	FocusCoordinator.close_scope(self)
	visible = false
	_epoch += 1
	_submitted = false
	closed.emit()


func show_rejection(message_key: String) -> void:
	if _state.is_empty():
		return
	_submitted = false
	_error_key = message_key
	error_label.text = tr(message_key)
	error_label.visible = true
	for control: Control in _actions:
		(control as Button).disabled = not bool(control.get_meta("available", false))
	var controls := _focus_controls()
	FocusCoordinator.link_ring(controls, false)
	FocusCoordinator.recover(self, controls[0])


func _validate(_state_value: Dictionary):
	return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)


func _apply_accessibility() -> void:
	var runtimes := get_tree().get_nodes_in_group("accessibility_runtime")
	if not runtimes.is_empty():
		(runtimes[0] as Node).call("apply_to_tree", self)


func _render_state() -> void:
	pass


func _build_layout() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.006, 0.012, 0.018, 0.9)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_area := MarginContainer.new()
	safe_area.name = "SafeArea"
	add_child(safe_area)
	safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		safe_area.add_theme_constant_override("margin_%s" % side, 16)
	var center := Control.new()
	center.name = "Center"
	safe_area.add_child(center)
	panel_root = PanelContainer.new()
	panel_root.name = "PanelRoot"
	center.add_child(panel_root)
	var style := panel_root.get_theme_stylebox("panel").duplicate() as StyleBox
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel_root.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	panel_root.add_child(layout)
	title_label = _label("", "TitleLabel", 16)
	title_label.theme_type_variation = &"DisplayLabel"
	title_label.add_theme_color_override("font_color", Color("edf0dc"))
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(title_label)
	summary_label = _label("", "SummaryLabel", 11)
	summary_label.add_theme_color_override("font_color", Color("abb8ac"))
	layout.add_child(summary_label)
	error_label = _label("", "ErrorLabel", 11)
	error_label.add_theme_color_override("font_color", Color("df9b65"))
	error_label.max_lines_visible = 2
	layout.add_child(error_label)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Keep the shell inside the safe area when enlarged text makes the row content tall.
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	rows_container = VBoxContainer.new()
	rows_container.name = "Rows"
	rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_container.custom_minimum_size = Vector2(0, 0)
	rows_container.add_theme_constant_override("separation", 6)
	scroll.add_child(rows_container)
	footer = HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(footer)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.custom_minimum_size = Vector2(96, 25)
	back_button.focus_mode = Control.FOCUS_ALL
	back_button.add_theme_font_size_override("font_size", 12)
	back_button.pressed.connect(_request_close)
	footer.add_child(back_button)


func _fit_panel() -> void:
	if is_instance_valid(panel_root):
		var available := Vector2(maxf(0, size.x - 32), maxf(0, size.y - 32))
		var extent := Vector2(minf(616, available.x), minf(560, available.y))
		panel_root.custom_minimum_size = extent
		panel_root.size = extent
		panel_root.position = (available - extent) / 2


func _label(text: String, node_name: String, font_size: int = 12) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _add_text(text: String, node_name: String = "Description") -> Label:
	var label := _label(text, node_name)
	rows_container.add_child(label)
	return label


func _add_action(
	identifier: String, text: String, description: String, available: bool,
	disabled_reason_key: String, callback: Callable
) -> Button:
	var row := VBoxContainer.new()
	row.name = "Row_%d" % _actions.size()
	row.add_theme_constant_override("separation", 3)
	rows_container.add_child(row)
	var button := Button.new()
	button.name = "Action_%d" % _actions.size()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 29)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not available
	button.set_meta("action_id", identifier)
	button.set_meta("available", available)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(_activate_action.bind(button, callback, _epoch))
	row.add_child(button)
	if not description.is_empty():
		row.add_child(_label(description, "Description", 11))
	if not disabled_reason_key.is_empty():
		var reason := _label(tr(disabled_reason_key), "DisabledReason_%d" % _actions.size(), 11)
		reason.add_theme_color_override("font_color", Color("ffd18c"))
		row.add_child(reason)
	_actions.append(button)
	return button


func _activate_action(button: Variant, callback: Callable, source_epoch: int) -> void:
	if source_epoch != _epoch or _submitted or not visible or not is_instance_valid(button) or not button is Button or button.disabled:
		return
	_submitted = true
	for control: Control in _actions:
		(control as Button).disabled = true
	callback.call()


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for control: Control in _actions:
		if not (control as Button).disabled:
			controls.append(control)
	controls.append(back_button)
	return controls


func _clear_rows() -> void:
	_actions.clear()
	for child: Node in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0


func _request_close() -> void:
	if not visible:
		return
	var revision := int(_state.get("revision", 0))
	close_panel()
	close_requested.emit(revision)


func _unhandled_input(event: InputEvent) -> void:
	if visible and FocusCoordinator.active_scope() == self and event.is_action_pressed("ui_cancel"):
		_request_close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _state.is_empty():
		var was_submitted := _submitted
		var vertical := scroll.scroll_vertical
		_epoch += 1
		_clear_rows()
		_render_state()
		_apply_accessibility()
		back_button.text = tr("UI_BACK")
		error_label.text = tr(_error_key) if not _error_key.is_empty() else ""
		_submitted = was_submitted
		if _submitted:
			for control: Control in _actions:
				(control as Button).disabled = true
		scroll.scroll_vertical = vertical
		if visible:
			var controls := _focus_controls()
			FocusCoordinator.link_ring(controls, false)
			FocusCoordinator.recover(self, controls[0])
