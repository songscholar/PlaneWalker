class_name AccessibilitySettingsPanel
extends Control

const KIND_SLIDER := "slider"
const KIND_TOGGLE := "toggle"
const KIND_OPTION := "option"

const SETTING_DEFINITIONS := [
	{
		"id": "master_volume",
		"section": "UI_ACCESSIBILITY_AUDIO",
		"label": "UI_MASTER_VOLUME",
		"kind": KIND_SLIDER,
		"default": 0.85,
	},
	{
		"id": "music_volume",
		"section": "UI_ACCESSIBILITY_AUDIO",
		"label": "UI_MUSIC_VOLUME",
		"kind": KIND_SLIDER,
		"default": 0.8,
	},
	{
		"id": "sfx_volume",
		"section": "UI_ACCESSIBILITY_AUDIO",
		"label": "UI_SFX_VOLUME",
		"kind": KIND_SLIDER,
		"default": 0.9,
	},
	{
		"id": "dialogue_volume",
		"section": "UI_ACCESSIBILITY_AUDIO",
		"label": "UI_DIALOGUE_VOLUME",
		"kind": KIND_SLIDER,
		"default": 0.9,
	},
	{
		"id": "master_muted",
		"section": "UI_ACCESSIBILITY_AUDIO",
		"label": "UI_MUTE",
		"kind": KIND_TOGGLE,
		"default": false,
	},
	{
		"id": "camera_shake_enabled",
		"section": "UI_ACCESSIBILITY_VISUALS",
		"label": "UI_CAMERA_SHAKE",
		"kind": KIND_TOGGLE,
		"default": true,
	},
	{
		"id": "hit_flash_enabled",
		"section": "UI_ACCESSIBILITY_VISUALS",
		"label": "UI_HIT_FLASH",
		"kind": KIND_TOGGLE,
		"default": true,
	},
	{
		"id": "reduced_motion",
		"section": "UI_ACCESSIBILITY_VISUALS",
		"label": "UI_REDUCED_MOTION",
		"kind": KIND_TOGGLE,
		"default": false,
	},
	{
		"id": "high_contrast_danger",
		"section": "UI_ACCESSIBILITY_VISUALS",
		"label": "UI_HIGH_CONTRAST_DANGER",
		"kind": KIND_TOGGLE,
		"default": false,
	},
	{
		"id": "text_scale",
		"section": "UI_ACCESSIBILITY_READABILITY",
		"label": "UI_TEXT_SCALE",
		"kind": KIND_OPTION,
		"default": 1.0,
		"options": [
			["UI_SCALE_100", 1.0],
			["UI_SCALE_125", 1.25],
			["UI_SCALE_150", 1.5],
		],
	},
	{
		"id": "subtitles_enabled",
		"section": "UI_ACCESSIBILITY_READABILITY",
		"label": "UI_SUBTITLES",
		"kind": KIND_TOGGLE,
		"default": true,
	},
	{
		"id": "subtitle_scale",
		"section": "UI_ACCESSIBILITY_READABILITY",
		"label": "UI_SUBTITLE_SCALE",
		"kind": KIND_OPTION,
		"default": 1.0,
		"options": [
			["UI_SCALE_100", 1.0],
			["UI_SCALE_125", 1.25],
			["UI_SCALE_150", 1.5],
		],
	},
	{
		"id": "ranged_charge_mode",
		"section": "UI_ACCESSIBILITY_CONTROLS",
		"label": "UI_RANGED_CHARGE_MODE",
		"kind": KIND_OPTION,
		"default": "hold",
		"options": [
			["UI_RANGED_HOLD", "hold"],
			["UI_RANGED_TOGGLE", "toggle"],
		],
	},
	{
		"id": "damage_received_multiplier",
		"section": "UI_ACCESSIBILITY_ASSISTS",
		"label": "UI_DAMAGE_RECEIVED",
		"kind": KIND_OPTION,
		"default": 1.0,
		"options": [
			["UI_DAMAGE_100", 1.0],
			["UI_DAMAGE_80", 0.8],
			["UI_DAMAGE_60", 0.6],
		],
	},
	{
		"id": "enemy_telegraph_scale",
		"section": "UI_ACCESSIBILITY_ASSISTS",
		"label": "UI_TELEGRAPH_SCALE",
		"kind": KIND_OPTION,
		"default": 1.0,
		"options": [
			["UI_SCALE_100", 1.0],
			["UI_SCALE_125", 1.25],
			["UI_SCALE_150", 1.5],
		],
	},
]

@onready var title_label: Label = $SafeArea/PanelRoot/Layout/TitleLabel
@onready var assist_explanation: Label = $SafeArea/PanelRoot/Layout/AssistExplanation
@onready var scroll: ScrollContainer = $SafeArea/PanelRoot/Layout/Scroll
@onready var rows_container: VBoxContainer = $SafeArea/PanelRoot/Layout/Scroll/Rows
@onready var back_button: Button = $SafeArea/PanelRoot/Layout/Footer/BackButton

var _restore_focus: Control
var _setting_controls: Dictionary = {}
var _slider_value_labels: Dictionary = {}
var _focus_controls: Array[Control] = []
var _refreshing := false


func configure(restore_focus: Control = null) -> void:
	_restore_focus = restore_focus


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	title_label.text = tr("UI_ACCESSIBILITY_SETTINGS")
	assist_explanation.text = tr("UI_ACCESSIBILITY_ASSIST_EXPLANATION")
	back_button.text = tr("UI_BACK")
	back_button.focus_mode = Control.FOCUS_ALL
	back_button.pressed.connect(close_panel)
	_apply_button_style(back_button)
	_build_rows()
	if not GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.disconnect(_on_setting_changed)


func open_panel(restore_focus: Control = null) -> void:
	if restore_focus != null:
		_restore_focus = restore_focus
	if _restore_focus != null and _restore_focus.is_inside_tree() and _restore_focus.is_visible_in_tree():
		_restore_focus.grab_focus()
	visible = true
	_refresh_controls()
	FocusCoordinator.link_ring(_focus_controls, false)
	if not _focus_controls.is_empty():
		FocusCoordinator.open_scope(self, _focus_controls[0])


func close_panel() -> void:
	FocusCoordinator.close_scope(self)
	visible = false


func get_setting_control(setting_id: String) -> Control:
	return _setting_controls.get(setting_id) as Control


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()


func _build_rows() -> void:
	_setting_controls.clear()
	_slider_value_labels.clear()
	_focus_controls.clear()
	var current_section := ""
	for definition: Dictionary in SETTING_DEFINITIONS:
		var section_key := str(definition["section"])
		if section_key != current_section:
			current_section = section_key
			rows_container.add_child(_section_label(section_key))
		var setting_id := str(definition["id"])
		var row := _setting_row(definition)
		rows_container.add_child(row)
		var control := row.get_node("SettingControl") as Control
		_setting_controls[setting_id] = control
		_focus_controls.append(control)
	_focus_controls.append(back_button)
	_refresh_controls()


func _section_label(localization_key: String) -> Label:
	var label := Label.new()
	label.name = "Section_%s" % localization_key.trim_prefix("UI_ACCESSIBILITY_").to_pascal_case()
	label.custom_minimum_size = Vector2(0.0, 19.0)
	label.text = tr(localization_key)
	label.add_theme_color_override("font_color", Color("8ceaff"))
	label.add_theme_font_size_override("font_size", 12)
	return label


func _setting_row(definition: Dictionary) -> HBoxContainer:
	var setting_id := str(definition["id"])
	var row := HBoxContainer.new()
	row.name = "Row_%s" % setting_id
	row.custom_minimum_size = Vector2(0.0, 29.0)
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.name = "SettingLabel"
	label.custom_minimum_size = Vector2(248.0, 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = tr(str(definition["label"]))
	label.add_theme_color_override("font_color", Color("c7d9e2"))
	label.add_theme_font_size_override("font_size", 11)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var control: Control
	match str(definition["kind"]):
		KIND_SLIDER:
			control = _volume_slider(setting_id)
			var value_label := Label.new()
			value_label.name = "ValueLabel"
			value_label.custom_minimum_size = Vector2(42.0, 0.0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			value_label.add_theme_color_override("font_color", Color("9db8c5"))
			value_label.add_theme_font_size_override("font_size", 10)
			_slider_value_labels[setting_id] = value_label
			(control as HSlider).value_changed.connect(_on_volume_changed.bind(setting_id, value_label))
			row.add_child(control)
			row.add_child(value_label)
		KIND_TOGGLE:
			control = _toggle_control()
			(control as CheckButton).toggled.connect(_on_toggle_changed.bind(setting_id))
			row.add_child(control)
		KIND_OPTION:
			control = _option_control(definition.get("options", []))
			(control as OptionButton).item_selected.connect(_on_option_selected.bind(setting_id, control))
			row.add_child(control)
		_:
			control = Control.new()
			row.add_child(control)
	control.name = "SettingControl"
	control.set_meta("setting_id", setting_id)
	control.focus_entered.connect(_on_control_focused.bind(control))
	return row


func _volume_slider(_setting_id: String) -> HSlider:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(224.0, 24.0)
	slider.focus_mode = Control.FOCUS_ALL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.add_theme_stylebox_override("focus", _focus_style())
	return slider


func _toggle_control() -> CheckButton:
	var toggle := CheckButton.new()
	toggle.custom_minimum_size = Vector2(274.0, 24.0)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_button_style(toggle)
	return toggle


func _option_control(options: Array) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(274.0, 24.0)
	option.focus_mode = Control.FOCUS_ALL
	option.add_theme_font_size_override("font_size", 10)
	_apply_button_style(option)
	for entry: Array in options:
		option.add_item(tr(str(entry[0])))
		option.set_item_metadata(option.item_count - 1, entry[1])
	return option


func _refresh_controls() -> void:
	_refreshing = true
	for definition: Dictionary in SETTING_DEFINITIONS:
		var setting_id := str(definition["id"])
		var control := _setting_controls.get(setting_id) as Control
		if control == null:
			continue
		var value: Variant = GameState.get_setting(setting_id, definition["default"])
		match str(definition["kind"]):
			KIND_SLIDER:
				(control as HSlider).value = float(value) * 100.0
				_update_volume_label(_slider_value_labels.get(setting_id) as Label, float(value))
			KIND_TOGGLE:
				(control as CheckButton).button_pressed = bool(value)
			KIND_OPTION:
				_select_option_value(control as OptionButton, value)
	_refreshing = false


func _select_option_value(option: OptionButton, value: Variant) -> void:
	for index: int in range(option.item_count):
		if _values_equal(option.get_item_metadata(index), value):
			option.select(index)
			return


func _values_equal(left: Variant, right: Variant) -> bool:
	if left is float or left is int:
		if right is float or right is int:
			return is_equal_approx(float(left), float(right))
	return left == right


func _on_volume_changed(percent: float, setting_id: String, value_label: Label) -> void:
	var normalized := snappedf(percent / 100.0, 0.01)
	_update_volume_label(value_label, normalized)
	if not _refreshing:
		_persist_setting(setting_id, normalized)


func _on_toggle_changed(enabled: bool, setting_id: String) -> void:
	if not _refreshing:
		_persist_setting(setting_id, enabled)


func _on_option_selected(index: int, setting_id: String, option: OptionButton) -> void:
	if _refreshing or index < 0 or index >= option.item_count:
		return
	_persist_setting(setting_id, option.get_item_metadata(index))


func _persist_setting(setting_id: String, value: Variant) -> void:
	if not GameState.set_setting(setting_id, value):
		_refresh_controls()


func _on_setting_changed(_setting_id: StringName, _value: Variant) -> void:
	_refresh_controls()


func _update_volume_label(label: Label, value: float) -> void:
	if label != null:
		label.text = "%d%%" % roundi(value * 100.0)


func _on_control_focused(control: Control) -> void:
	scroll.call_deferred("ensure_control_visible", control)


func _apply_button_style(button: BaseButton) -> void:
	button.add_theme_stylebox_override("normal", _button_style(Color("07121a"), Color("246279")))
	button.add_theme_stylebox_override("hover", _button_style(Color("092534"), Color("23b8e3")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("0b3446"), Color("8ceaff")))
	button.add_theme_stylebox_override("focus", _focus_style())
	button.add_theme_color_override("font_color", Color("bcefff"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)


func _focus_style() -> StyleBoxFlat:
	return _button_style(Color("102c39"), Color("ffd166"), 3)


func _button_style(background: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	return style
