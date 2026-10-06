extends "res://scripts/ui/dungeon_panel_view.gd"

const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const Track := preload("res://scenes/ui/modes/boss_track.tscn")
var _mode_art: TextureRect
var _mode_commands: GridContainer


func _build_layout() -> void:
	super._build_layout()
	var layout := scroll.get_parent()
	var heading := HBoxContainer.new()
	heading.name = "ModeHeader"
	heading.add_theme_constant_override("separation", 10)
	layout.add_child(heading)
	layout.move_child(heading, 0)
	_mode_art = Art.image(null, 40, "ModeArtwork")
	heading.add_child(_mode_art)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 2)
	heading.add_child(labels)
	title_label.reparent(labels, false)
	summary_label.reparent(labels, false)
	_mode_commands = GridContainer.new()
	_mode_commands.name = "ModeCommands"
	_mode_commands.columns = 2
	_mode_commands.add_theme_constant_override("h_separation", 6)
	_mode_commands.add_theme_constant_override("v_separation", 4)
	layout.add_child(_mode_commands)
	layout.move_child(_mode_commands, scroll.get_index())
	Art.button_icon(back_button, Art.icon(&"controls", &"back"))


func _mode_identity(id: String) -> void:
	_mode_art.texture = Art.icon(&"mode_art", StringName(id))


func _loadout_art(request: Dictionary, content_names: Dictionary = {}) -> void:
	var kit := HFlowContainer.new()
	kit.name = "ModeLoadout"
	kit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kit.add_theme_constant_override("h_separation", 10)
	kit.add_theme_constant_override("v_separation", 4)
	rows_container.add_child(kit)
	if request.has("character_id"):
		_kit_icon(kit, Art.actor(str(request.character_id)), tr("CHARACTER_%s_NAME" % str(request.character_id).to_upper()), "LoadoutCharacter", 40)
	_kit_icon(kit, Art.icon(&"weapons", StringName(request.weapon_id)), tr("WEAPON_%s_NAME" % str(request.weapon_id).to_upper()), "LoadoutWeapon")
	for id: String in request.get("time_abilities", []):
		_kit_icon(kit, Art.icon(&"time_abilities", StringName(id)), tr("INPUT_ACTION_TIME_" + id.to_upper()), "LoadoutTime_" + id)
	for id: String in request.get("item_ids", []):
		_kit_icon(kit, Art.content(id, "item"), tr(str(content_names.get(id, id.to_upper() + "_NAME"))), "LoadoutItem_" + id)
	for category: String in ["blessing", "curse"]:
		var id := str(request.get(category + "_id", ""))
		if not id.is_empty():
			_kit_icon(kit, Art.content(id, category), tr(str(content_names.get(id, id.to_upper() + "_NAME"))), "Loadout_" + category)


func _boss_track(ids: Array, completed: int = 0, current: int = 0) -> void:
	var track := Track.instantiate()
	rows_container.add_child(track)
	track.render_track(ids, completed, current)


func _kit_icon(parent: Control, texture: Texture2D, caption: String, node_name: String, extent: int = 32) -> void:
	var icon := Art.image(texture, extent, node_name)
	icon.tooltip_text = caption
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(icon)


func _record(text: String, texture: Texture2D, node_name: String = "ModeRecord") -> void:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 8)
	rows_container.add_child(row)
	row.add_child(Art.image(texture, 24, "RecordArtwork"))
	row.add_child(_label(text, "RecordFacts", 11))


func _add_action(identifier: String, text: String, description: String, available: bool, disabled_reason_key: String, callback: Callable) -> Button:
	var button := super._add_action(identifier, text, description, available, disabled_reason_key, callback)
	button.get_parent().reparent(_mode_commands, false)
	(button.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if identifier.begins_with("choice_"):
		button.name = "CarriedChoice_" + identifier.trim_prefix("choice_")
	return button


func _clear_rows() -> void:
	if is_instance_valid(_mode_commands):
		for row: Node in _mode_commands.get_children():
			_mode_commands.remove_child(row)
			row.queue_free()
	super._clear_rows()
