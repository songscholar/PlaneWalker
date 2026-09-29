class_name ChoicePanelView
extends Control

signal option_chosen(offer_id: String, option_id: String, revision: int)

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")

const CARD_MINIMUM_SIZE := Vector2(184.0, 200.0)

@onready var panel_root: PanelContainer = $SafeArea/Center/PanelRoot
@onready var title_label: Label = $SafeArea/Center/PanelRoot/Content/TitleLabel
@onready var error_label: Label = $SafeArea/Center/PanelRoot/Content/ErrorLabel
@onready var options_container: HBoxContainer = $SafeArea/Center/PanelRoot/Content/OptionsContainer

var _current_offer: Dictionary = {}
var _current_offer_id: String = ""
var _current_revision: int = -1
var _submitted: bool = false


func _ready() -> void:
	visible = false
	error_label.visible = false


func render(offer: Dictionary):
	var validation = SelectionOfferScript.validate(offer)
	if not validation.ok:
		return validation

	var offer_id := str(offer["offer_id"])
	var revision := int(offer["revision"])
	if offer_id == _current_offer_id and revision <= _current_revision:
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_current_revision,
			{
				"offer_id": offer_id,
				"received_revision": revision,
				"last_revision": _current_revision,
			}
		)

	_current_offer = SelectionOfferScript.copy_of(offer)
	_current_offer_id = offer_id
	_current_revision = revision
	_submitted = false
	_clear_options()
	title_label.text = tr(str(_current_offer["title_key"]))
	error_label.text = ""
	error_label.visible = false
	for option_value: Variant in _current_offer["options"]:
		_add_option_button(option_value as Dictionary, str(_current_offer["category"]))
	visible = true
	var buttons := _option_buttons()
	FocusCoordinator.link_ring(buttons, true)
	if not buttons.is_empty():
		FocusCoordinator.open_scope(self, buttons[0])
	return CommandResultScript.success(revision)


func show_rejection(message_key: String) -> void:
	if _current_offer.is_empty():
		return
	_submitted = false
	error_label.text = tr(message_key)
	error_label.visible = true
	visible = true
	_set_buttons_disabled(false)
	var buttons := _option_buttons()
	if not buttons.is_empty():
		FocusCoordinator.recover(self, buttons[0])


func close_panel() -> void:
	FocusCoordinator.close_scope(self)
	visible = false
	_submitted = false
	_current_offer = {}
	error_label.text = ""
	error_label.visible = false
	_clear_options()


func _add_option_button(option: Dictionary, category: String) -> void:
	var button := Button.new()
	var option_id := str(option["option_id"])
	var tone := _choice_tone(option, category)
	button.name = _button_node_name(option_id)
	button.custom_minimum_size = CARD_MINIMUM_SIZE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("option_id", option_id)
	button.set_meta("content_id", str(option["content_id"]))
	button.set_meta("choice_tone", tone)
	_apply_card_style(button, tone)
	button.pressed.connect(_on_option_pressed.bind(_current_offer_id, option_id, _current_revision))
	options_container.add_child(button)
	_add_card_content(button, option, tone)
	var accessibility_nodes := get_tree().get_nodes_in_group("accessibility_runtime")
	if not accessibility_nodes.is_empty():
		(accessibility_nodes[0] as Node).call("apply_to_tree", button)


func _on_option_pressed(source_offer_id: String, option_id: String, source_revision: int) -> void:
	if _submitted or _current_offer.is_empty():
		return
	if source_offer_id != _current_offer_id or source_revision != _current_revision:
		return
	if not _current_offer_has_option(option_id):
		return
	_submitted = true
	_set_buttons_disabled(true)
	option_chosen.emit(_current_offer_id, option_id, _current_revision)


func _set_buttons_disabled(disabled: bool) -> void:
	for child: Node in options_container.get_children():
		if child is Button:
			(child as Button).disabled = disabled


func _option_buttons() -> Array[Control]:
	var buttons: Array[Control] = []
	for child: Node in options_container.get_children():
		if child is Button and not (child as Button).disabled:
			buttons.append(child as Control)
	return buttons


func _clear_options() -> void:
	for child: Node in options_container.get_children():
		options_container.remove_child(child)
		child.queue_free()


func _add_card_content(button: Button, option: Dictionary, tone: String) -> void:
	var colors := _tone_colors(tone)
	var content := VBoxContainer.new()
	content.name = "CardContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 5)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10.0
	content.offset_top = 9.0
	content.offset_right = -10.0
	content.offset_bottom = -9.0

	var name_label := _card_label("NameLabel", tr(str(option["name_key"])), 15, colors["font"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)

	var meta_label := _card_label(
		"MetaLabel",
		"%s  •  %s" % [tr(str(option["rarity"])).to_upper(), tr(str(option["role_key"]))],
		11,
		colors["border"]
	)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(meta_label)

	var description_label := _card_label(
		"DescriptionLabel",
		tr(str(option["description_key"])),
		12,
		Color(0.9, 0.93, 0.96, 1.0)
	)
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(description_label)

	var effect_lines: Array[String] = []
	for effect_key: Variant in option["effect_summary_keys"]:
		effect_lines.append(tr(str(effect_key)))
	var effect_label := _card_label("EffectLabel", "\n".join(effect_lines), 11, colors["font"])
	effect_label.visible = not effect_lines.is_empty()
	content.add_child(effect_label)


func _card_label(label_name: String, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _current_offer_has_option(option_id: String) -> bool:
	for option: Dictionary in _current_offer.get("options", []):
		if str(option.get("option_id", "")) == option_id:
			return true
	return false


func _choice_tone(option: Dictionary, category: String) -> String:
	if str(option["option_id"]) == "decline_contract" or str(option["role_key"]) == "ROLE_SAFE":
		return "safe"
	if category == "contract" or str(option["role_key"]) == "ROLE_RISK":
		return "risk"
	return "time"


func _apply_card_style(button: Button, tone: String) -> void:
	var colors := _tone_colors(tone)
	var normal := _card_style(colors["background"], colors["border"])
	var hover := _card_style(colors["hover"], colors["border"])
	var pressed := _card_style(colors["pressed"], colors["border"])
	var disabled := _card_style(colors["disabled"], colors["disabled_border"])
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover.duplicate(true))
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", colors["font"])
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.48, 0.5, 0.54, 1.0))
	button.add_theme_font_size_override("font_size", 13)


func _card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style


func _tone_colors(tone: String) -> Dictionary:
	match tone:
		"risk":
			return {
				"background": Color(0.12, 0.035, 0.025, 0.98),
				"hover": Color(0.2, 0.06, 0.025, 1.0),
				"pressed": Color(0.27, 0.075, 0.02, 1.0),
				"disabled": Color(0.055, 0.035, 0.035, 0.96),
				"border": Color(0.95, 0.28, 0.08, 1.0),
				"disabled_border": Color(0.3, 0.16, 0.14, 1.0),
				"font": Color(1.0, 0.78, 0.62, 1.0),
			}
		"safe":
			return {
				"background": Color(0.07, 0.075, 0.085, 0.98),
				"hover": Color(0.12, 0.13, 0.15, 1.0),
				"pressed": Color(0.16, 0.17, 0.19, 1.0),
				"disabled": Color(0.045, 0.047, 0.052, 0.96),
				"border": Color(0.52, 0.56, 0.62, 1.0),
				"disabled_border": Color(0.24, 0.26, 0.29, 1.0),
				"font": Color(0.86, 0.88, 0.92, 1.0),
			}
		_:
			return {
				"background": Color(0.025, 0.07, 0.1, 0.98),
				"hover": Color(0.035, 0.12, 0.17, 1.0),
				"pressed": Color(0.04, 0.16, 0.22, 1.0),
				"disabled": Color(0.025, 0.045, 0.055, 0.96),
				"border": Color(0.12, 0.72, 0.92, 1.0),
				"disabled_border": Color(0.12, 0.27, 0.33, 1.0),
				"font": Color(0.7, 0.94, 1.0, 1.0),
			}


func _button_node_name(option_id: String) -> String:
	var sanitized := option_id.replace("-", "_").replace(" ", "_")
	return "Option_%s" % sanitized
