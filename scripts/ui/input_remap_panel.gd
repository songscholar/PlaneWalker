class_name InputRemapPanel
extends Control

signal capture_started(action: StringName, family: StringName)

const InputRemapServiceScript := preload("res://scripts/input/input_remap_service.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")

const FAMILY_KEYBOARD_MOUSE := &"keyboard_mouse"
const FAMILY_CONTROLLER := &"controller"
const CAPTURE_AXIS_THRESHOLD := 0.75

@onready var title_label: Label = $SafeArea/PanelRoot/Layout/TitleLabel
@onready var action_header: Label = $SafeArea/PanelRoot/Layout/ColumnHeaders/ActionHeader
@onready var keyboard_header: Label = $SafeArea/PanelRoot/Layout/ColumnHeaders/KeyboardHeader
@onready var controller_header: Label = $SafeArea/PanelRoot/Layout/ColumnHeaders/ControllerHeader
@onready var rows_container: VBoxContainer = $SafeArea/PanelRoot/Layout/Scroll/Rows
@onready var status_label: Label = $SafeArea/PanelRoot/Layout/StatusLabel
@onready var reset_all_button: Button = $SafeArea/PanelRoot/Layout/Footer/ResetAllButton
@onready var back_button: Button = $SafeArea/PanelRoot/Layout/Footer/BackButton
@onready var capture_overlay: Control = $CaptureOverlay
@onready var capture_prompt: Label = $CaptureOverlay/Center/CapturePanel/CaptureLayout/CapturePrompt
@onready var capture_cancel_label: Label = $CaptureOverlay/Center/CapturePanel/CaptureLayout/CancelLabel

var _service: RefCounted
var _restore_focus: Control
var _row_controls: Dictionary = {}
var _focus_controls: Array[Control] = []
var _capture_action: StringName = &""
var _capture_family: StringName = &""
var _capture_ready_frame: int = 0


func configure(remap_service: RefCounted, restore_focus: Control = null) -> void:
	_service = remap_service
	_restore_focus = restore_focus


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = load("res://assets/production/ui/plane_walker_theme.tres") as Theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shell := $SafeArea/PanelRoot as PanelContainer
	shell.remove_theme_stylebox_override("panel")
	shell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	($SafeArea/PanelRoot/Layout/Scroll as ScrollContainer).custom_minimum_size = Vector2.ZERO
	($SafeArea/PanelRoot/Layout/Scroll as ScrollContainer).follow_focus = true
	for header: Label in [action_header, keyboard_header, controller_header]:
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_header.custom_minimum_size.x = 0
	keyboard_header.custom_minimum_size.x = 120
	controller_header.custom_minimum_size.x = 112
	($SafeArea/PanelRoot/Layout/ColumnHeaders/ResetHeader as Control).custom_minimum_size.x = 28
	_device_header(keyboard_header, &"keyboard_mouse", "KeyboardMouseDeviceArtwork")
	_device_header(controller_header, &"controller", "ControllerDeviceArtwork")
	var capture_frame := $CaptureOverlay/Center/CapturePanel as PanelContainer
	capture_frame.remove_theme_stylebox_override("panel")
	capture_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resized.connect(_fit_panel)
	shell.minimum_size_changed.connect(_queue_fit)
	_fit_panel()
	visible = false
	title_label.text = tr("UI_INPUT_REMAP")
	title_label.add_theme_color_override("font_color", Color("edf0dc"))
	action_header.text = tr("UI_INPUT_ACTION")
	keyboard_header.text = tr("UI_BINDING_KEYBOARD_MOUSE")
	controller_header.text = tr("UI_BINDING_CONTROLLER")
	reset_all_button.text = tr("UI_RESET_ALL")
	back_button.text = tr("UI_BACK")
	capture_cancel_label.text = tr("UI_CAPTURE_CANCEL")
	reset_all_button.pressed.connect(_on_reset_all_pressed)
	back_button.pressed.connect(close_panel)
	_apply_button_style(reset_all_button)
	_apply_button_style(back_button)
	Art.button_icon(back_button, Art.icon(&"controls", &"back"))
	Art.button_icon(reset_all_button, Art.icon(&"controls", &"restart"))
	if _service == null:
		_service = InputRemapServiceScript.new()
		_service.call("configure")
		_service.call("load_or_defaults")
	if _service.has_signal("bindings_changed") and not _service.is_connected("bindings_changed", _on_bindings_changed):
		_service.connect("bindings_changed", _on_bindings_changed)
	_build_rows()
	capture_overlay.visible = false


func open_panel(restore_focus: Control = null) -> void:
	if restore_focus != null:
		_restore_focus = restore_focus
	if _restore_focus != null and _restore_focus.is_inside_tree() and _restore_focus.is_visible_in_tree():
		_restore_focus.grab_focus()
	visible = true
	status_label.text = ""
	_refresh_all_rows()
	FocusCoordinator.link_ring(_focus_controls, false)
	if not _focus_controls.is_empty():
		FocusCoordinator.open_scope(self, _focus_controls[0])


func close_panel() -> void:
	if _capture_is_active():
		_cancel_capture()
		return
	FocusCoordinator.close_scope(self)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture_is_active():
		if _is_cancel_event(event):
			get_viewport().set_input_as_handled()
			_cancel_capture()
			return
		if Engine.get_process_frames() < _capture_ready_frame:
			return
		var candidate := _capture_candidate(event)
		if candidate != null:
			get_viewport().set_input_as_handled()
			_apply_capture(candidate)
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()


func _build_rows() -> void:
	for child: Node in rows_container.get_children():
		child.queue_free()
	_row_controls.clear()
	_focus_controls.clear()
	for action: StringName in _remappable_actions():
		var row := HBoxContainer.new()
		row.name = "Row_%s" % str(action)
		row.custom_minimum_size = Vector2(0.0, 28.0)
		row.add_theme_constant_override("separation", 6)

		var action_label := Label.new()
		action_label.name = "ActionLabel"
		action_label.custom_minimum_size = Vector2.ZERO
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action_label.text = tr(_action_key(action))
		action_label.add_theme_font_size_override("font_size", 11)
		row.add_child(action_label)

		var keyboard_button := _binding_button("KeyboardMouseBinding", 120.0)
		keyboard_button.set_meta("action", action)
		keyboard_button.set_meta("family", FAMILY_KEYBOARD_MOUSE)
		keyboard_button.pressed.connect(_start_capture.bind(action, FAMILY_KEYBOARD_MOUSE))
		row.add_child(keyboard_button)

		var controller_button := _binding_button("ControllerBinding", 112.0)
		controller_button.set_meta("action", action)
		controller_button.set_meta("family", FAMILY_CONTROLLER)
		controller_button.pressed.connect(_start_capture.bind(action, FAMILY_CONTROLLER))
		row.add_child(controller_button)

		var reset_button := Button.new()
		reset_button.name = "ResetActionButton"
		reset_button.custom_minimum_size = Vector2(28.0, 28.0)
		reset_button.focus_mode = Control.FOCUS_ALL
		reset_button.tooltip_text = tr("UI_RESET_ACTION")
		reset_button.icon = Art.icon(&"controls", &"restart")
		reset_button.expand_icon = true
		reset_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset_button.add_theme_constant_override("icon_max_width", 16)
		reset_button.add_theme_font_size_override("font_size", 10)
		_apply_button_style(reset_button)
		reset_button.pressed.connect(_on_reset_action_pressed.bind(action))
		row.add_child(reset_button)

		rows_container.add_child(row)
		_row_controls[str(action)] = {
			"keyboard_mouse": keyboard_button,
			"controller": controller_button,
		}
		_focus_controls.append(keyboard_button)
		_focus_controls.append(controller_button)
		_focus_controls.append(reset_button)
		_refresh_row(action)
	_focus_controls.append(reset_all_button)
	_focus_controls.append(back_button)
	FocusCoordinator.link_ring(_focus_controls, false)


func _binding_button(button_name: String, width: float) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(width, 28.0)
	button.focus_mode = Control.FOCUS_ALL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 10)
	_apply_button_style(button)
	return button


func _device_header(header: Label, identity: StringName, image_name: String) -> void:
	var spacing := StyleBoxEmpty.new()
	spacing.content_margin_left = 20
	header.add_theme_stylebox_override("normal", spacing)
	var image := Art.image(Art.icon(&"controls", identity), 16, image_name)
	header.add_child(image)
	image.anchor_top = 0.5
	image.anchor_bottom = 0.5
	image.offset_top = -8
	image.offset_bottom = 8
	image.offset_right = 16


func _apply_button_style(button: Button) -> void:
	button.add_theme_color_override("font_color", Color("edf0dc"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)


func _queue_fit() -> void:
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	if not is_instance_valid(rows_container):
		return
	var available := Vector2(maxf(0, size.x - 32), maxf(0, size.y - 32))
	($SafeArea/PanelRoot as Control).custom_minimum_size = Vector2(minf(616, available.x), minf(560, available.y))
	($CaptureOverlay/Center/CapturePanel as Control).custom_minimum_size.x = minf(400, available.x)


func apply_accessibility_settings(_settings: Dictionary) -> void:
	_queue_fit()


func _start_capture(action: StringName, family: StringName) -> void:
	_capture_action = action
	_capture_family = family
	_capture_ready_frame = Engine.get_process_frames() + 1
	_refresh_capture_prompt()
	capture_overlay.visible = true
	status_label.text = ""
	capture_started.emit(action, family)


func _refresh_capture_prompt() -> void:
	var prompt_template := tr("UI_PRESS_INPUT")
	capture_prompt.text = (
		prompt_template % tr(_action_key(_capture_action))
		if prompt_template.contains("%s")
		else "%s: %s" % [prompt_template, tr(_action_key(_capture_action))]
	)


func _apply_capture(event: InputEvent) -> void:
	var result: Dictionary = _service.call("remap", _capture_action, _capture_family, event)
	if bool(result.get("ok", false)):
		status_label.text = tr("UI_BINDING_CONFLICT_SWAPPED") if result.get("code") == "SWAPPED" else ""
		_refresh_all_rows()
	else:
		status_label.text = tr("UI_BINDING_REJECTED")
	_cancel_capture()


func _cancel_capture() -> void:
	capture_overlay.visible = false
	_capture_action = &""
	_capture_family = &""
	_capture_ready_frame = 0
	var fallback := _first_binding_button()
	FocusCoordinator.recover(self, fallback)


func _capture_candidate(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key if key.pressed and not key.echo and key.physical_keycode != 0 else null
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse if mouse.pressed else null
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button if button.pressed else null
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return motion if absf(motion.axis_value) >= CAPTURE_AXIS_THRESHOLD else null
	return null


func _is_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	return event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B


func _on_reset_action_pressed(action: StringName) -> void:
	var result: Dictionary = _service.call("reset_action", action)
	status_label.text = "" if bool(result.get("ok", false)) else tr("UI_BINDING_REJECTED")
	_refresh_all_rows()


func _on_reset_all_pressed() -> void:
	var result: Dictionary = _service.call("reset_all")
	status_label.text = "" if bool(result.get("ok", false)) else tr("UI_BINDING_REJECTED")
	_refresh_all_rows()


func _on_bindings_changed(_action: StringName) -> void:
	_refresh_all_rows()


func _refresh_all_rows() -> void:
	for action: StringName in _remappable_actions():
		_refresh_row(action)


func _remappable_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for action_value: Variant in _service.call("remappable_actions"):
		actions.append(StringName(str(action_value)))
	return actions


func _refresh_row(action: StringName) -> void:
	if not _row_controls.has(str(action)):
		return
	var labels: Dictionary = _service.call("binding_labels", action)
	var controls: Dictionary = _row_controls[str(action)]
	(controls["keyboard_mouse"] as Button).text = _joined_labels(labels.get("keyboard_mouse", []))
	(controls["controller"] as Button).text = _joined_labels(labels.get("controller", []))


func _joined_labels(values: Array) -> String:
	var labels: Array[String] = []
	for value: Variant in values:
		labels.append(str(value))
	return " / ".join(labels)


func _first_binding_button() -> Control:
	return _focus_controls[0] if not _focus_controls.is_empty() else null


func _capture_is_active() -> bool:
	return not _capture_action.is_empty()


func _action_key(action: StringName) -> String:
	return "INPUT_ACTION_%s" % str(action).to_upper()


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	title_label.text = tr("UI_INPUT_REMAP")
	action_header.text = tr("UI_INPUT_ACTION")
	keyboard_header.text = tr("UI_BINDING_KEYBOARD_MOUSE")
	controller_header.text = tr("UI_BINDING_CONTROLLER")
	reset_all_button.text = tr("UI_RESET_ALL")
	back_button.text = tr("UI_BACK")
	capture_cancel_label.text = tr("UI_CAPTURE_CANCEL")
	for action: StringName in _remappable_actions():
		var row := rows_container.get_node("Row_" + str(action))
		(row.get_node("ActionLabel") as Label).text = tr(_action_key(action))
		(row.get_node("ResetActionButton") as Button).tooltip_text = tr("UI_RESET_ACTION")
	_refresh_all_rows()
	if _capture_is_active():
		_refresh_capture_prompt()
	_queue_fit()
