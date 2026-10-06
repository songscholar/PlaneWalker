class_name NarrativePanelView
extends "res://scripts/ui/dungeon_panel_view.gd"

signal action_requested(action_id: String, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/narrative_view_state.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")


func _ready() -> void:
	super._ready()
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll.gui_input.connect(_scroll_narrative)
	Art.button_icon(back_button, Art.icon(&"controls", &"back"))


func _validate(value: Dictionary):
	return Contract.validate(value)


func _render_state() -> void:
	title_label.text = tr(_state.title_key)
	summary_label.text = ""
	summary_label.visible = false
	back_button.visible = _state.close_available
	if _state.mode == "dialogue":
		rows_container.add_child(Art.image(Art.icon(&"npc_portraits", StringName(_state.subject_id)), 72, "NarrativePortrait"))
	elif _state.mode == "choice":
		var npc_id := _choice_npc(str(_state.subject_id))
		if not npc_id.is_empty():
			rows_container.add_child(Art.image(Art.icon(&"npc_portraits", StringName(npc_id)), 72, "NarrativePortrait"))
	elif _state.mode == "credits":
		var image := Art.image(Art.icon(&"ending_art", StringName(_state.subject_id)), 144, "EndingArtwork")
		image.custom_minimum_size = Vector2(256, 144)
		rows_container.add_child(image)
	elif _state.mode == "story":
		rows_container.add_child(Art.image(Art.icon(&"room_types", &"event"), 48, "StoryArtwork"))
	if not str(_state.text_key).is_empty():
		_add_text(tr(_state.text_key), "NarrativeText")
	var rendered_nodes: Array[String] = []
	for row: Dictionary in _state.rows:
		var description := tr(row.text_key) if not str(row.text_key).is_empty() else ""
		if row.missing_count > 0:
			description = "%s: %d" % [tr("UI_NARRATIVE_NEEDS"), row.missing_count]
		if _state.mode == "dialogue" and not str(row.text_key).is_empty():
			if not rendered_nodes.has(str(row.node_id)):
				_add_text(tr(row.text_key), "NarrativeText_" + str(row.node_id))
				rendered_nodes.append(str(row.node_id))
			description = ""
		var button := _add_action(str(row.action_id), tr(row.name_key), description, row.available, "", action_requested.emit.bind(str(row.action_id), int(_state.revision)))
		if _state.mode == "ending":
			_ending_row(button, row)
		elif row.available:
			Art.button_icon(button, Art.icon(&"controls", &"play"))
		else:
			Art.button_icon(button, Art.icon(&"room_types", &"unknown"))


func _ending_row(button: Button, row: Dictionary) -> void:
	var content := button.get_parent() as VBoxContainer
	var composition := HBoxContainer.new()
	composition.add_theme_constant_override("separation", 12)
	rows_container.add_child(composition)
	var revealed := str(row.name_key) != "UI_NARRATIVE_NEEDS" and not str(row.text_key).is_empty()
	var texture := Art.icon(&"ending_art", StringName(row.choice_id)) if revealed else Art.icon(&"room_types", &"unknown")
	var image := Art.image(texture, 72, "EndingArtwork_" + str(row.choice_id))
	image.custom_minimum_size = Vector2(128, 72)
	composition.add_child(image)
	content.reparent(composition)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _choice_npc(subject: String) -> String:
	for npc_id: String in ["nemesis", "vera"]:
		for sequence in range(1, 6):
			if subject == "choice_%s_%d" % [npc_id, sequence]:
				return npc_id
	return ""


func _scroll_narrative(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") and scroll.scroll_vertical > 0:
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 48)
		scroll.accept_event()
	elif event.is_action_pressed("ui_down") and scroll.scroll_vertical + scroll.size.y < scroll.get_v_scroll_bar().max_value:
		scroll.scroll_vertical += 48
		scroll.accept_event()


func _request_close() -> void:
	if not _state.get("close_available", false):
		return
	super._request_close()


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for control: Control in _actions:
		if not (control as Button).disabled:
			controls.append(control)
	controls.append(scroll)
	if back_button.visible:
		controls.append(back_button)
	return controls
