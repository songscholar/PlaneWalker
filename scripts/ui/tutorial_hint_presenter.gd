class_name TutorialHintPresenter
extends Control

const Contract := preload("res://scripts/ui/contracts/tutorial_view_state.gd")
const Text := preload("res://scripts/ui/tutorial_presentation_text.gd")
const Result := preload("res://scripts/application/command_result.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
var hint_panel: PanelContainer
var title_label: Label
var description_label: Label
var bindings_label: Label
var close_button: Button
var _state: Dictionary = {}
var _remaining_frames := 0


func _ready() -> void:
	theme = load("res://assets/production/ui/plane_walker_theme.tres") as Theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_bottom", 64)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	hint_panel = PanelContainer.new()
	hint_panel.name = "HintPanel"
	hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hint_panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 4)
	hint_panel.add_child(contents)
	var header := HBoxContainer.new()
	contents.add_child(header)
	header.add_child(Art.image(Art.icon(&"mode_art", &"training"), 24, "HintArtwork"))
	title_label = _label("TitleLabel", 13)
	header.add_child(title_label)
	close_button = Button.new()
	close_button.name = "CloseHint"
	close_button.icon = Art.icon(&"controls", &"back")
	close_button.expand_icon = true
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.add_theme_constant_override("icon_max_width", 16)
	close_button.custom_minimum_size = Vector2(28, 28)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(clear_context)
	header.add_child(close_button)
	description_label = _label("DescriptionLabel", 12)
	contents.add_child(description_label)
	bindings_label = _label("BindingsLabel", 11)
	contents.add_child(bindings_label)
	resized.connect(_fit_width)
	_fit_width()
	visible = false


func render_saved_hint(state: Dictionary):
	var validated = Contract.validate_hint(state)
	if not validated.ok:
		return validated
	if not _state.is_empty() and state.run_id == _state.run_id:
		if state.revision < _state.revision:
			return Result.failure(&"STALE_REVISION", int(_state.revision))
		if state == _state:
			return Result.success(int(_state.revision))
	_state = state.duplicate(true)
	_remaining_frames = int(state.display_frames)
	_render_text()
	visible = true
	return Result.success(int(state.revision))


func view_state() -> Dictionary:
	return _state.duplicate(true)


func clear_context() -> void:
	visible = false
	_remaining_frames = 0


func advance_display_frame() -> void:
	if not visible or get_tree().paused or _state.is_empty() or _state.style != "instant":
		return
	_remaining_frames -= 1
	if _remaining_frames <= 0:
		clear_context()


func _physics_process(_delta: float) -> void:
	advance_display_frame()


func _label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _fit_width() -> void:
	hint_panel.custom_minimum_size.x = minf(576.0, maxf(64.0, size.x - 32.0))


func _render_text() -> void:
	title_label.text = tr(_state.name_key)
	description_label.text = tr(_state.text_key)
	bindings_label.text = Text.bindings_text(_state.actions)
	bindings_label.visible = not bindings_label.text.is_empty()
	close_button.tooltip_text = tr("UI_BACK")
	for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
		runtime.apply_to_tree(self)
		break


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _state.is_empty():
		_render_text()
