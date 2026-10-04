class_name HubPanelView
extends "res://scripts/ui/dungeon_panel_view.gd"

signal command_requested(command: Dictionary, revision: int)
signal tutorial_requested

const Contract := preload("res://scripts/ui/contracts/hub_view_state.gd")

var _selectors: Dictionary = {}
var _build_name: LineEdit


func _validate(value: Dictionary):
	return Contract.validate(value)


func show_rejection(message_key: String) -> void:
	super.show_rejection(message_key)
	for field: String in _selectors:
		var option: OptionButton = _selectors[field]
		for index: int in range(option.item_count):
			var row: Dictionary = option.get_item_metadata(index)
			if field == "time_pair" and row.ability_ids == _state.loadout.selected.enabled_time_skills or field != "time_pair" and row.id == _state.loadout.selected[field]:
				option.select(index)
				break


func _render_state() -> void:
	_selectors.clear()
	_build_name = null
	for row: Dictionary in _state.functions:
		if row.id == _state.function_id:
			title_label.text = tr(str(row.name_key))
	summary_label.text = tr("UI_HUB_CURRENCIES_FMT") % [int(_state.currencies.chronos_shards), int(_state.currencies.existential_imprints)]
	match str(_state.function_id):
		"council":
			_render_nodes()
		"gateway":
			_render_loadout()
		"forge":
			_render_forge()
		"meditation":
			_render_builds()
		"archive", "gallery", "mirror":
			_render_collection(str(_state.function_id))
		"training":
			_add_action("tutorial", tr("UI_TUTORIAL_TITLE"), "", true, "", func(): tutorial_requested.emit())
		"merchant":
			_render_providers()
	_render_dialogue()


func _render_nodes() -> void:
	for row: Dictionary in _state.nodes:
		var description := tr(str(row.description_key))
		if not row.prerequisites.is_empty():
			description += "\n" + ", ".join(row.prerequisites)
		_add_action(str(row.id), "%s  %s" % [tr(str(row.name_key)), _cost(row.cost)], description, bool(row.available), str(row.reason_key), _emit_operation.bind("meta_unlock", {"node_id": row.id}))


func _render_loadout() -> void:
	var selected: Dictionary = _state.loadout.selected
	_add_selector("character_id", tr("UI_LAUNCH_CHARACTER_LABEL"), _state.loadout.characters, str(selected.character_id))
	_add_selector("weapon_id", tr("UI_LAUNCH_WEAPON_LABEL"), _state.loadout.weapons, str(selected.weapon_id))
	var selected_pair := ""
	for row: Dictionary in _state.loadout.time_pairs:
		if row.ability_ids == selected.enabled_time_skills:
			selected_pair = str(row.id)
	_add_selector("time_pair", tr("UI_LAUNCH_TIME_PAIR_LABEL"), _state.loadout.time_pairs, selected_pair)
	var launch := Button.new()
	launch.name = "LaunchButton"
	launch.text = tr("UI_HUB_ENTER")
	launch.custom_minimum_size = Vector2(96, 25)
	launch.add_theme_font_size_override("font_size", 12)
	launch.disabled = not bool(_state.launch_available)
	launch.tooltip_text = tr(str(_state.launch_reason_key)) if launch.disabled else ""
	launch.set_meta("action_id", "launch")
	launch.set_meta("available", _state.launch_available)
	launch.pressed.connect(_activate_action.bind(launch, _emit_operation.bind("launch", {"seed": int(Time.get_unix_time_from_system())}), _epoch))
	footer.add_child(launch)
	footer.move_child(launch, 0)
	_actions.append(launch)


func _add_selector(field: String, label: String, rows: Array, selected_id: String) -> void:
	_add_text(label, field + "Label")
	var option := OptionButton.new()
	option.name = field
	option.custom_minimum_size = Vector2(0, 29)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 12)
	for row: Dictionary in rows:
		var text := tr(str(row.get("name_key", "")))
		if row.has("ability_ids"):
			text = tr("UI_TIME_PAIR_FMT") % [tr(str(row.name_keys[0])), tr(str(row.name_keys[1]))]
		option.add_item(text)
		var index := option.item_count - 1
		option.set_item_metadata(index, row.duplicate(true))
		option.set_item_disabled(index, not bool(row.get("available", true)))
		if row.id == selected_id:
			option.select(index)
	rows_container.add_child(option)
	_selectors[field] = option
	option.disabled = not bool(_state.launch_available)
	option.item_selected.connect(_selection_changed.bind(_epoch))
	option.gui_input.connect(_selector_input.bind(option, _epoch))


func _selection_changed(_index: int, source_epoch: int) -> void:
	if source_epoch != _epoch or not visible or _submitted or _selectors.size() != 3:
		return
	var character: Dictionary = _selectors.character_id.get_selected_metadata()
	var weapon: Dictionary = _selectors.weapon_id.get_selected_metadata()
	var pair: Dictionary = _selectors.time_pair.get_selected_metadata()
	_emit_operation("select_loadout", {"character_id": character.id, "weapon_id": weapon.id, "time_abilities": pair.ability_ids.duplicate(), "difficulty": _state.loadout.selected.difficulty})


func _selector_input(event: InputEvent, option: OptionButton, source_epoch: int) -> void:
	var direction := 1 if event.is_action_pressed("ui_right") else (-1 if event.is_action_pressed("ui_left") else 0)
	if direction == 0 or option.disabled or source_epoch != _epoch or not visible or _submitted:
		return
	for offset: int in range(1, option.item_count + 1):
		var index := posmod(option.selected + direction * offset, option.item_count)
		if not option.is_item_disabled(index):
			option.select(index)
			_selection_changed(index, _epoch)
			option.accept_event()
			return


func _render_forge() -> void:
	for row: Dictionary in _state.forge.weapons:
		_add_text("%s  +%d  (%d%%)" % [tr(str(row.name_key)), int(row.level), roundi(float(row.attack_bonus) * 100)], "Weapon")
		var upgrade: Dictionary = row.upgrade
		_add_action("upgrade:" + str(row.id), "%s  %s" % [tr("UI_HUB_UPGRADE"), _cost(upgrade.cost)], "", bool(upgrade.available), str(upgrade.reason_key), _emit_operation.bind("forge_upgrade", {"weapon_id": row.id}))
		for enchantment: Dictionary in row.enchantments:
			var preference: Array = row.enchant_preferences.duplicate()
			if bool(enchantment.selected):
				preference.erase(enchantment.id)
			else:
				preference.append(enchantment.id)
			_add_preference("enchant:" + str(row.id) + ":" + str(enchantment.id), "%s  %s" % [tr(str(enchantment.name_key)), _cost(enchantment.cost)], enchantment, _emit_operation.bind("enchant_preference", {"weapon_id": row.id, "enchantment_ids": preference}))
		for payment: Dictionary in row.temper_options:
			_add_action("temper:" + str(row.id) + ":" + str(payment.currency), "%s  %s" % [tr("UI_HUB_VOID_TEMPER"), _cost(payment.cost)], "", bool(payment.available), str(payment.reason_key), _emit_operation.bind("void_temper", {"weapon_id": row.id, "payment_currency": payment.currency}))


func _render_builds() -> void:
	_build_name = LineEdit.new()
	_build_name.name = "BuildName"
	_build_name.placeholder_text = tr("UI_HUB_BUILD_NAME")
	_build_name.max_length = 64
	_build_name.custom_minimum_size = Vector2(0, 29)
	rows_container.add_child(_build_name)
	_add_action("build_save", tr("UI_HUB_BUILD_SAVE"), "", bool(_state.loadout.build_save.available), str(_state.loadout.build_save.reason_key), _save_build)
	for row: Dictionary in _state.builds:
		_add_action("build_select:" + str(row.id), str(row.name), "%s / %s" % [tr("CHARACTER_%s_NAME" % str(row.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(row.weapon_id).to_upper())], bool(row.available), str(row.reason_key), _emit_operation.bind("build_select", {"build_id": row.id}))
		_add_action("build_remove:" + str(row.id), tr("UI_HUB_BUILD_REMOVE"), "", bool(row.remove.available), str(row.remove.reason_key), _emit_operation.bind("build_remove", {"build_id": row.id}))


func _add_preference(id: String, text: String, entry: Dictionary, callback: Callable) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = bool(entry.selected)
	checkbox.disabled = not bool(entry.available)
	checkbox.tooltip_text = tr(str(entry.reason_key)) if not entry.available else ""
	checkbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	checkbox.custom_minimum_size = Vector2(0, 29)
	checkbox.add_theme_font_size_override("font_size", 12)
	checkbox.set_meta("action_id", id)
	checkbox.set_meta("available", entry.available)
	checkbox.pressed.connect(_activate_action.bind(checkbox, callback, _epoch))
	rows_container.add_child(checkbox)
	_actions.append(checkbox)


func _save_build() -> void:
	if _build_name.text.strip_edges().is_empty():
		show_rejection("UI_HUB_BUILD_NAME")
		return
	var selected: Dictionary = _state.loadout.selected
	_emit_operation("build_save", {"build": {"id": "build-%d-%d" % [int(_state.revision), int(_state.epoch)], "name": _build_name.text.strip_edges(), "character_id": selected.character_id, "weapon_id": selected.weapon_id, "time_abilities": selected.enabled_time_skills.duplicate()}})


func _render_collection(kind: String) -> void:
	var rows: Array = _state.collections[kind]
	if rows.is_empty():
		_add_text(tr("UI_HUB_EMPTY"))
	for row: Dictionary in rows:
		_add_text("%s  %s" % [tr(str(row.name_key)), tr("UI_HUB_OWNED" if row.owned else "UI_HUB_LOCKED")])
	if kind == "mirror":
		_render_providers()


func _render_providers() -> void:
	for row: Dictionary in _state.providers:
		_add_text(tr("UI_HUB_PROVIDER_" + str(row.id).to_upper()))
		if not row.available:
			_add_text(tr(str(row.reason_key)))
		for entry: Dictionary in row.entries:
			_add_text("%s  %d" % [str(entry.name), int(entry.score)])


func _render_dialogue() -> void:
	var dialogue: Dictionary = _state.dialogue
	if str(dialogue.get("npc_id", "")).is_empty():
		return
	_add_text("%s  %s" % [tr("NPC_%s_NAME" % str(dialogue.npc_id).to_upper()), tr("UI_HUB_AFFINITY_FMT") % int(dialogue.affinity)], "NPC")
	for node: Dictionary in dialogue.nodes:
		_add_text(tr(str(node.text_key)), "Dialogue")
		for choice: Dictionary in node.choices:
			_add_action("dialogue:" + str(node.id) + ":" + str(choice.id), "%s  %s" % [tr(str(choice.text_key)), _cost(choice.cost)], "", bool(choice.available), str(choice.reason_key), _emit_operation.bind("narrative_dialogue", {"npc_id": dialogue.npc_id, "node_id": node.id, "choice_id": choice.id}))


func _emit_operation(operation: String, payload: Dictionary) -> void:
	var prepared := payload.duplicate(true)
	if operation in ["meta_unlock", "forge_upgrade", "enchant_preference", "void_temper", "build_save", "build_remove", "narrative_dialogue"]:
		prepared.command_id = "hub:%d:%d:%s" % [int(_state.revision), int(_state.epoch), operation]
		prepared.kind = operation
	command_requested.emit({"epoch": _state.epoch, "function_id": _state.function_id, "operation": operation, "payload": prepared}, int(_state.revision))


func _cost(value: Dictionary) -> String:
	return tr("UI_HUB_CURRENCIES_FMT") % [int(value.get("chronos_shards", 0)), int(value.get("existential_imprints", 0))]


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for option: OptionButton in _selectors.values():
		if not option.disabled:
			controls.append(option)
	if is_instance_valid(_build_name):
		controls.append(_build_name)
	controls.append_array(super._focus_controls())
	return controls


func _clear_rows() -> void:
	for child: Node in footer.get_children():
		if child != back_button:
			footer.remove_child(child)
			child.queue_free()
	super._clear_rows()
