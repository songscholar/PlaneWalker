class_name UiBuildInspector
extends "res://scripts/ui/dungeon_panel_view.gd"

const Contract := preload("res://scripts/ui/contracts/run_view_state.gd")
const Archetypes := preload("res://scripts/progression/archetype_profile.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const Facts := preload("res://scripts/ui/style/combat_hud_facts.gd")
const TimeIds := preload("res://scripts/time_system/time_ability_ids.gd")

var _registry: RefCounted


func _ready() -> void:
	super._ready()
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll.gui_input.connect(_scroll_input)


func configure(registry: RefCounted) -> Dictionary:
	if registry == null or not registry.has_method("get_content"):
		return {"ok": false, "code": &"INVALID_ARGUMENT", "context": {}}
	_registry = registry
	return {"ok": true, "code": &"OK", "context": {}}


func render_build(state: Dictionary) -> Dictionary:
	if _registry == null:
		return {"ok": false, "code": &"NOT_CONFIGURED", "context": {}}
	var result = render(state)
	return {"ok": result.ok, "code": result.code, "context": result.context.duplicate(true)}


func focus_controls() -> Array[Control]:
	return _focus_controls()


func _validate(state: Dictionary):
	return Contract.validate(state)


func _focus_controls() -> Array[Control]:
	return [scroll, back_button]


func _render_state() -> void:
	title_label.text = tr("UI_FINISH_BUILD_INSPECTOR")
	var seconds := int(_state.run_time_ms) / 1000
	summary_label.text = "%s / %s %02d:%02d" % [tr(_state.room.title_key), tr("UI_TIME"), seconds / 60, seconds % 60]
	_section(tr("UI_FINISH_EQUIPMENT"))
	var weapon := Facts.weapon(_state.weapon_state)
	_equipment(Art.icon(&"weapons", StringName(_state.weapon_state.weapon_id)), weapon.name, " / ".join([weapon.meter, weapon.status]))
	if _state.character_state is Dictionary:
		var character := Facts.character(_state.character_state)
		_equipment(Art.actor(str(_state.character_state.character_id)), character.name, " / ".join([character.meter, character.status, character.cooldown]))
	for slot: Dictionary in _state.player.time_slots:
		var status := tr("HUD_WEAPON_READY") if float(slot.cooldown) <= 0 else tr("HUD_WEAPON_COOLDOWN_FMT") % float(slot.cooldown)
		_equipment(Art.icon(&"time_abilities", StringName(slot.ability_id)), tr(TimeIds.localization_key(slot.ability_id)), status)
	if _state.active_item_state is Dictionary:
		var active := _state.active_item_state as Dictionary
		var status := tr("HUD_WEAPON_READY") if active.ready else tr("HUD_WEAPON_COOLDOWN_FMT") % (float(active.cooldown_current) / 60.0)
		_equipment(Art.content(active.content_id, "item"), tr(active.name_key), status)
	_section(tr("UI_FINISH_ARCHETYPES"))
	var scores := GridContainer.new()
	scores.name = "ArchetypeScores"
	scores.columns = 2
	scores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scores.add_theme_constant_override("h_separation", 16)
	rows_container.add_child(scores)
	for id: String in Archetypes.ARCHETYPE_IDS:
		var label := _label("%s: %d" % [tr("ARCHETYPE_" + id.to_upper() + "_NAME"), int(_state.build.archetype_scores.get(id, 0))], "ArchetypeScore_" + id, 11)
		if id == str(_state.build.dominant_archetype):
			label.add_theme_color_override("font_color", Color("e5bd69"))
		scores.add_child(label)
	for pool: String in ["items", "blessings", "curses", "talents"]:
		_section(tr("UI_" + pool.to_upper()))
		if (_state.build[pool] as Array).is_empty():
			_add_text("-")
		for id: String in _state.build[pool]:
			var definition: Dictionary = _registry.call("get_content", StringName(id))
			_content_row(id, definition)


func _section(text: String) -> void:
	if rows_container.get_child_count() > 0:
		rows_container.add_child(HSeparator.new())
	var label := _add_text(text)
	label.add_theme_color_override("font_color", Color("79baa1"))


func _equipment(texture: Texture2D, name_text: String, detail: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rows_container.add_child(row)
	row.add_child(Art.image(texture, 32))
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	description.add_child(_label(name_text, "EquipmentName", 12))
	description.add_child(_label(detail, "EquipmentState", 11))


func _content_row(id: String, definition: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "BuildContent_" + id
	row.add_theme_constant_override("separation", 8)
	rows_container.add_child(row)
	row.add_child(Art.image(Art.content(id, str(definition.get("category", ""))), 32))
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	description.add_child(_label(tr(str(definition.get("name_key", id))), "ContentName", 12))
	description.add_child(_label(tr(str(definition.get("description_key", ""))), "ContentDescription", 11))
	var rarity := str(definition.get("rarity", ""))
	if not rarity.is_empty():
		description.add_child(_label(tr("RARITY_" + rarity.to_upper()), "ContentRarity", 10))


func _scroll_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 48)
		scroll.accept_event()
	elif event.is_action_pressed("ui_down"):
		scroll.scroll_vertical += 48
		scroll.accept_event()
