class_name PauseMenu
extends CanvasLayer

signal resume_requested()
signal remap_requested()
signal accessibility_requested()

const InspectorScene := preload("res://scenes/ui/components/build_inspector.tscn")
const RunContract := preload("res://scripts/ui/contracts/run_view_state.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var resume_button: Button = $Panel/Margin/VBox/ResumeButton
@onready var settings_button: Button = $Panel/Margin/VBox/SettingsButton
@onready var remap_button: Button = $Panel/Margin/VBox/RemapButton
@onready var restart_button: Button = $Panel/Margin/VBox/RestartButton
@onready var quit_button: Button = $Panel/Margin/VBox/QuitButton

var build_button: Button
var _inspector: Control
var _build_state: Dictionary = {}


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layout := $Panel/Margin/VBox as VBoxContainer
	layout.add_theme_constant_override("separation", 4)
	var margin := $Panel/Margin as MarginContainer
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	title_label.add_theme_font_size_override("font_size", 16)
	build_button = Button.new()
	build_button.name = "BuildButton"
	build_button.focus_mode = Control.FOCUS_ALL
	build_button.disabled = true
	layout.add_child(build_button)
	layout.move_child(build_button, remap_button.get_index() + 1)
	build_button.pressed.connect(_open_build_inspector)
	for button: Button in [resume_button, settings_button, remap_button, build_button, restart_button, quit_button]:
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size = Vector2(0, 28)
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBox
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			button.add_theme_stylebox_override(state, style)
	Art.button_icon(resume_button, Art.icon(&"controls", &"play"))
	_inspector = InspectorScene.instantiate() as Control
	add_child(_inspector)
	_inspector.close_requested.connect(_on_build_closed)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	_refresh_text()
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	remap_button.pressed.connect(_on_remap_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_link_controls()


func _refresh_text() -> void:
	title_label.text = tr("UI_PAUSED")
	resume_button.text = tr("UI_RESUME")
	settings_button.text = tr("UI_ACCESSIBILITY_SETTINGS")
	remap_button.text = tr("UI_INPUT_REMAP")
	restart_button.text = tr("UI_RESTART_RUN")
	quit_button.text = tr("UI_QUIT")
	build_button.text = tr("UI_FINISH_BUILD_INSPECTOR")


func _link_controls() -> void:
	var controls: Array[Control] = [resume_button, settings_button, remap_button]
	if not build_button.disabled:
		controls.append(build_button)
	controls.append_array([restart_button, quit_button])
	FocusCoordinator.link_ring(
		controls,
		false
	)


func _fit_panel() -> void:
	var panel := $Panel as PanelContainer
	var available := get_viewport().get_visible_rect().size - Vector2(32, 32)
	var extent := Vector2(minf(360, available.x), minf(328, available.y))
	panel.custom_minimum_size = Vector2.ZERO
	panel.offset_left = -extent.x / 2
	panel.offset_top = -extent.y / 2
	panel.offset_right = extent.x / 2
	panel.offset_bottom = extent.y / 2


func configure_build_inspection(registry: RefCounted, state: Dictionary) -> Dictionary:
	var validation = RunContract.validate(state)
	if not validation.ok:
		_build_state.clear()
		build_button.disabled = true
		_link_controls()
		return {"ok": false, "code": validation.code, "context": validation.context.duplicate(true)}
	var configured: Dictionary = _inspector.call("configure", registry)
	if not configured.ok:
		return configured
	_build_state = state.duplicate(true)
	build_button.disabled = false
	_link_controls()
	return {"ok": true, "code": &"OK", "context": {}}


func _open_build_inspector() -> void:
	if not visible or build_button.disabled or _build_state.is_empty():
		return
	var result: Dictionary = _inspector.call("render_build", _build_state)
	if result.ok:
		$Panel.hide()


func _on_build_closed(_revision: int) -> void:
	$Panel.show()
	FocusCoordinator.recover(self, build_button)


func show_pause() -> void:
	$Panel.show()
	_refresh_text()
	visible = true
	FocusCoordinator.open_scope(self, resume_button)


func hide_pause() -> void:
	_inspector.call("close_panel")
	FocusCoordinator.close_scope(self)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and FocusCoordinator.active_scope() == self and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_settings_pressed() -> void:
	accessibility_requested.emit()


func _on_remap_pressed() -> void:
	remap_requested.emit()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()
