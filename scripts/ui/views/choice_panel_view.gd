class_name ChoicePanelView
extends Control

signal option_chosen(offer_id: String, option_id: String, revision: int)

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")

const CARD_MINIMUM_SIZE := Vector2.ZERO

@onready var panel_root: PanelContainer = $SafeArea/Center/PanelRoot
@onready var title_label: Label = $SafeArea/Center/PanelRoot/Content/TitleLabel
@onready var error_label: Label = $SafeArea/Center/PanelRoot/Content/ErrorLabel
@onready var options_container: HBoxContainer = $SafeArea/Center/PanelRoot/Content/OptionsContainer
@onready var replacement_panel: PanelContainer = $SafeArea/Center/PanelRoot/Content/ReplacementPanel
@onready var replacement_label: Label = $SafeArea/Center/PanelRoot/Content/ReplacementPanel/Layout/ReplacementLabel
@onready var replacement_cancel_button: Button = $SafeArea/Center/PanelRoot/Content/ReplacementPanel/Layout/Actions/CancelButton
@onready var replacement_confirm_button: Button = $SafeArea/Center/PanelRoot/Content/ReplacementPanel/Layout/Actions/ConfirmButton

var _current_offer: Dictionary = {}
var _current_offer_id: String = ""
var _current_revision: int = -1
var _submitted: bool = false
var _pending_replacement_option_id: String = ""
var _pending_replacement_button: Button
var _error_key := ""


func _ready() -> void:
	theme = load("res://assets/production/ui/plane_walker_theme.tres") as Theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frame := get_theme_stylebox("panel", "PanelContainer").duplicate() as StyleBox
	frame.content_margin_left = 16
	frame.content_margin_right = 16
	panel_root.add_theme_stylebox_override("panel", frame)
	visible = false
	error_label.visible = false
	replacement_panel.visible = false
	replacement_cancel_button.pressed.connect(_on_replacement_cancelled)
	replacement_confirm_button.pressed.connect(_on_replacement_confirmed)
	resized.connect(_fit_panel)
	_fit_panel()


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
	_reset_replacement_confirmation()
	_clear_options()
	title_label.text = tr(str(_current_offer["title_key"]))
	error_label.text = ""
	error_label.visible = false
	_error_key = ""
	for option_value: Variant in _current_offer["options"]:
		_add_option_button(option_value as Dictionary, str(_current_offer["category"]))
	var accessibility_nodes := get_tree().get_nodes_in_group("accessibility_runtime")
	if not accessibility_nodes.is_empty():
		(accessibility_nodes[0] as Node).call("apply_to_tree", self)
	visible = true
	var buttons := _option_buttons()
	FocusCoordinator.link_ring(buttons, true)
	if not buttons.is_empty():
		FocusCoordinator.open_scope(self, buttons[0])
	return CommandResultScript.success(revision)


func _fit_panel() -> void:
	if not is_instance_valid(panel_root):
		return
	var available := Vector2(maxf(0, size.x - 32), maxf(0, size.y - 32))
	var extent := Vector2(minf(616, available.x), minf(440, available.y))
	panel_root.custom_minimum_size = extent
	panel_root.size = extent
	panel_root.position = (available - extent) / 2


func show_rejection(message_key: String) -> void:
	if _current_offer.is_empty():
		return
	_submitted = false
	_reset_replacement_confirmation()
	_error_key = message_key
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
	_reset_replacement_confirmation()
	error_label.text = ""
	error_label.visible = false
	_error_key = ""
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
	button.set_meta(
		"active_item",
		(option.get("active_item", {}) as Dictionary).duplicate(true)
		if option.get("active_item") is Dictionary
		else {}
	)
	_apply_card_style(button, tone)
	button.pressed.connect(_on_option_pressed.bind(_current_offer_id, option_id, _current_revision))
	options_container.add_child(button)
	_add_card_content(button, option, tone, category)
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
	if _option_requires_replacement(option_id):
		_show_replacement_confirmation(option_id)
		return
	_submit_option(option_id)


func _submit_option(option_id: String) -> void:
	_submitted = true
	_set_buttons_disabled(true)
	replacement_cancel_button.disabled = true
	replacement_confirm_button.disabled = true
	option_chosen.emit(_current_offer_id, option_id, _current_revision)


func _show_replacement_confirmation(option_id: String) -> void:
	var option := _current_offer_option(option_id)
	var active_value: Variant = option.get("active_item", {})
	if not active_value is Dictionary:
		return
	_pending_replacement_option_id = option_id
	_pending_replacement_button = _button_for_option(option_id)
	_set_buttons_disabled(true)
	options_container.visible = false
	replacement_panel.visible = true
	replacement_cancel_button.disabled = false
	replacement_confirm_button.disabled = false
	_refresh_replacement_text(option)
	var controls: Array[Control] = [
		replacement_cancel_button,
		replacement_confirm_button,
	]
	FocusCoordinator.link_ring(controls, true)
	FocusCoordinator.recover(self, replacement_cancel_button)


func _refresh_replacement_text(option: Dictionary) -> void:
	var active := option.get("active_item", {}) as Dictionary
	replacement_cancel_button.text = tr("UI_BACK")
	replacement_confirm_button.text = tr(str(option.get("name_key", "")))
	replacement_label.text = "%s  →  %s" % [
		tr(str(active.get("equipped_name_key", active.get("equipped_content_id", "")))),
		tr(str(option.get("name_key", option.get("option_id", "")))),
	]


func _on_replacement_cancelled() -> void:
	if _pending_replacement_option_id.is_empty() or _submitted:
		return
	var fallback := _pending_replacement_button
	_reset_replacement_confirmation()
	var buttons := _option_buttons()
	FocusCoordinator.link_ring(buttons, true)
	if fallback != null and is_instance_valid(fallback):
		FocusCoordinator.recover(self, fallback)


func _on_replacement_confirmed() -> void:
	if _pending_replacement_option_id.is_empty() or _submitted:
		return
	_submit_option(_pending_replacement_option_id)


func _reset_replacement_confirmation() -> void:
	_pending_replacement_option_id = ""
	_pending_replacement_button = null
	replacement_panel.visible = false
	options_container.visible = true
	replacement_cancel_button.disabled = false
	replacement_confirm_button.disabled = false
	_set_buttons_disabled(false)


func _unhandled_input(event: InputEvent) -> void:
	if (
		visible
		and replacement_panel.visible
		and event.is_action_pressed("ui_cancel")
	):
		_on_replacement_cancelled()
		get_viewport().set_input_as_handled()


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


func _add_card_content(button: Button, option: Dictionary, tone: String, category: String) -> void:
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
	var texture := Art.icon(&"controls", &"decline_contract") if str(option.option_id) == "decline_contract" else Art.content(str(option.content_id), category)
	content.add_child(Art.image(texture, 48, "ChoiceArtwork"))
	var scroll := ScrollContainer.new()
	scroll.name = "DetailsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	content.add_child(scroll)
	var details := VBoxContainer.new()
	details.name = "Details"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 5)
	scroll.add_child(details)
	button.gui_input.connect(_scroll_details.bind(button, scroll, _current_offer_id, _current_revision))

	var name_label := _card_label("NameLabel", tr(str(option["name_key"])), 15, colors["font"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(name_label)

	var meta_label := _card_label(
		"MetaLabel",
		"%s / %s" % [tr("RARITY_" + str(option["rarity"]).to_upper()), tr(str(option["role_key"]))],
		11,
		colors["border"]
	)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(meta_label)

	var archetype_label := _card_label(
		"ArchetypeLabel",
		tr(str(option["archetype_key"])),
		10,
		Color(0.62, 0.7, 0.78, 1.0)
	)
	archetype_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(archetype_label)

	var active_value: Variant = option.get("active_item", {})
	var active := active_value as Dictionary if active_value is Dictionary else {}
	var mode_label := _card_label(
		"ModeLabel",
		tr("INPUT_ACTION_ACTIVE_ITEM") if not active.is_empty() else "",
		10,
		colors["font"]
	)
	mode_label.visible = not active.is_empty()
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(mode_label)

	var cooldown_frames := int(active.get("cooldown_frames", 0))
	var cooldown_label := _card_label(
		"CooldownLabel",
		tr("HUD_WEAPON_COOLDOWN_FMT") % (float(cooldown_frames) / 60.0)
		if cooldown_frames > 0
		else "",
		10,
		colors["border"]
	)
	cooldown_label.visible = cooldown_frames > 0
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(cooldown_label)

	var description_label := _card_label(
		"DescriptionLabel",
		tr(str(option["description_key"])),
		12,
		Color(0.9, 0.93, 0.96, 1.0)
	)
	details.add_child(description_label)

	var effect_lines: Array[String] = []
	for effect_key: Variant in option["effect_summary_keys"]:
		effect_lines.append(tr(str(effect_key)))
	var effect_label := _card_label("EffectLabel", "\n".join(effect_lines), 11, colors["font"])
	effect_label.visible = not effect_lines.is_empty()
	details.add_child(effect_label)


func _scroll_details(event: InputEvent, button: Button, scroll: ScrollContainer, offer_id: String, revision: int) -> void:
	if _submitted or offer_id != _current_offer_id or revision != _current_revision:
		return
	if event.is_action_pressed("ui_up"):
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 48)
		button.accept_event()
	elif event.is_action_pressed("ui_down"):
		scroll.scroll_vertical += 48
		button.accept_event()


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


func _current_offer_option(option_id: String) -> Dictionary:
	for option: Dictionary in _current_offer.get("options", []):
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _option_requires_replacement(option_id: String) -> bool:
	var option := _current_offer_option(option_id)
	var active_value: Variant = option.get("active_item", {})
	return (
		active_value is Dictionary
		and bool((active_value as Dictionary).get("replacement_required", false))
	)


func _button_for_option(option_id: String) -> Button:
	for child: Node in options_container.get_children():
		if child is Button and str((child as Button).get_meta("option_id", "")) == option_id:
			return child as Button
	return null


func _choice_tone(option: Dictionary, category: String) -> String:
	if str(option["option_id"]) == "decline_contract" or str(option["role_key"]) == "ROLE_SAFE":
		return "safe"
	if category == "contract" or str(option["role_key"]) == "ROLE_RISK":
		return "risk"
	return "time"


func _apply_card_style(button: Button, tone: String) -> void:
	var colors := _tone_colors(tone)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var frame := get_theme_stylebox(state, "Button").duplicate() as StyleBox
		frame.content_margin_left = 0
		frame.content_margin_right = 0
		frame.content_margin_top = 0
		frame.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, frame)
	button.add_theme_color_override("font_color", colors["font"])
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.48, 0.5, 0.54, 1.0))
	button.add_theme_font_size_override("font_size", 13)


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


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready() or _current_offer.is_empty():
		return
	title_label.text = tr(str(_current_offer.title_key))
	error_label.text = tr(_error_key) if not _error_key.is_empty() else ""
	for button: Button in options_container.get_children():
		var option := _current_offer_option(str(button.get_meta("option_id")))
		var active := option.get("active_item", {}) as Dictionary
		var effects: PackedStringArray = []
		for key: String in option.effect_summary_keys:
			effects.append(tr(key))
		var values := {
			"NameLabel": tr(str(option.name_key)),
			"MetaLabel": "%s / %s" % [tr("RARITY_" + str(option.rarity).to_upper()), tr(str(option.role_key))],
			"ArchetypeLabel": tr(str(option.archetype_key)),
			"DescriptionLabel": tr(str(option.description_key)),
			"ModeLabel": tr("INPUT_ACTION_ACTIVE_ITEM") if not active.is_empty() else "",
			"CooldownLabel": tr("HUD_WEAPON_COOLDOWN_FMT") % (float(active.get("cooldown_frames", 0)) / 60.0) if int(active.get("cooldown_frames", 0)) > 0 else "",
			"EffectLabel": "\n".join(effects),
		}
		for label_name: String in values:
			var label := button.find_child(label_name, true, false) as Label
			if label != null:
				label.text = values[label_name]
	if not _pending_replacement_option_id.is_empty():
		_refresh_replacement_text(_current_offer_option(_pending_replacement_option_id))
