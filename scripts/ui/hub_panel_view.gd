class_name HubPanelView
extends "res://scripts/ui/dungeon_panel_view.gd"

signal command_requested(command: Dictionary, revision: int)
signal tutorial_requested
signal boss_rush_requested(config: Dictionary)
signal daily_boss_requested
signal authored_challenges_requested
signal replay_library_requested
signal endless_requested(config: Dictionary)
signal platform_requested
signal challenge_rewards_requested

const Contract := preload("res://scripts/ui/contracts/hub_view_state.gd")
const ShareCodec := preload("res://scripts/progression/build_share_codec.gd")
const CosmeticsPanel := preload("res://scripts/ui/hub_cosmetics_panel.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const Page := preload("res://scripts/ui/hub_pages/hub_page_layout.gd")
const BRANCH_LABELS := {"W": "UI_LAUNCH_WEAPON_LABEL", "C": "UI_LAUNCH_CHARACTER_LABEL", "L": "UI_FINISH_VITALS", "F": "HUB_FUNCTION_FORGE", "P": "UI_FINISH_EXPLORATION"}
const BRANCH_ART := {"W": ["weapons", "sword"], "C": ["time_abilities", "stop"], "L": ["items", "rewind_salve"], "F": ["weapons", "gauntlets"], "P": ["time_abilities", "rift"]}

var _selectors: Dictionary = {}
var _build_name: LineEdit
var _share_code: LineEdit
var _share_draft := ""
var _name_draft := ""


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
	_share_code = null
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
			var lesson := Page.section(rows_container, tr("UI_TUTORIAL_TITLE"), Art.icon(&"mode_art", &"training"))
			lesson.name = "TrainingLesson"
			Page.relocate_row(_add_action("tutorial", tr("UI_TUTORIAL_TITLE"), "", true, "", func(): tutorial_requested.emit()), lesson)
		"merchant":
			_render_providers()
	_render_dialogue()


func _render_nodes() -> void:
	var branches := Page.grid("CouncilBranches")
	rows_container.add_child(branches)
	var sections := {}
	var names := {}
	for row: Dictionary in _state.nodes:
		names[row.id] = tr(str(row.name_key))
	for row: Dictionary in _state.nodes:
		var branch := str(row.branch)
		if not sections.has(branch):
			var identity: Array = BRANCH_ART[branch]
			sections[branch] = Page.section(branches, tr(BRANCH_LABELS[branch]), Art.icon(StringName(identity[0]), StringName(identity[1])))
		var description := tr(str(row.description_key))
		if not row.prerequisites.is_empty():
			var prerequisites := PackedStringArray()
			for prerequisite: String in row.prerequisites:
				prerequisites.append(str(names.get(prerequisite, prerequisite)))
			description += "\n" + tr("UI_FINISH_REQUIRES_FMT") % ", ".join(prerequisites)
		var state_label := tr("UI_FINISH_UNLOCKED") if row.owned else _cost(row.cost)
		var action := _add_action(str(row.id), "%s  %s" % [tr(str(row.name_key)), state_label], description, bool(row.available), str(row.reason_key), _emit_operation.bind("meta_unlock", {"node_id": row.id}))
		Page.relocate_row(action, sections[branch])
		if row.owned:
			action.add_theme_color_override("font_disabled_color", Color("79baa1"))


func _render_loadout() -> void:
	var selected: Dictionary = _state.loadout.selected
	var loadout := VBoxContainer.new()
	loadout.name = "GatewayLoadout"
	loadout.add_theme_constant_override("separation", 8)
	rows_container.add_child(loadout)
	var roster := Page.grid("CharacterRoster", 5)
	loadout.add_child(roster)
	for index: int in range(_state.loadout.characters.size()):
		var row: Dictionary = _state.loadout.characters[index]
		var character := VBoxContainer.new()
		character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		character.add_theme_constant_override("separation", 2)
		roster.add_child(character)
		var portrait := Art.image(Art.actor(str(row.id)), 48, "CharacterPortrait")
		portrait.set_meta("actor_id", row.id)
		portrait.modulate = Color.WHITE if row.available else Color(0.35, 0.39, 0.36)
		character.add_child(portrait)
		var choose := Button.new()
		choose.text = tr(str(row.name_key))
		choose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choose.add_theme_font_size_override("font_size", 11)
		choose.custom_minimum_size = Vector2(0, 28)
		choose.disabled = not row.available or not _state.launch_available
		choose.tooltip_text = tr(str(row.reason_key)) if not row.available else ""
		choose.set_meta("action_id", "select_character:" + str(row.id))
		choose.set_meta("available", not choose.disabled)
		choose.pressed.connect(_choose_character.bind(index, _epoch))
		character.add_child(choose)
		_actions.append(choose)
		if row.id == selected.character_id:
			choose.add_theme_color_override("font_color", Color("e5bd69"))
	var preparation := HBoxContainer.new()
	preparation.add_theme_constant_override("separation", 16)
	loadout.add_child(preparation)
	preparation.add_child(Art.image(Art.actor(str(selected.character_id)), 96, "SelectedCharacterPreview"))
	var selectors := VBoxContainer.new()
	selectors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_theme_constant_override("separation", 4)
	preparation.add_child(selectors)
	_add_selector("character_id", tr("UI_LAUNCH_CHARACTER_LABEL"), _state.loadout.characters, str(selected.character_id), selectors)
	_add_selector("weapon_id", tr("UI_LAUNCH_WEAPON_LABEL"), _state.loadout.weapons, str(selected.weapon_id), selectors)
	var selected_pair := ""
	for row: Dictionary in _state.loadout.time_pairs:
		if row.ability_ids == selected.enabled_time_skills:
			selected_pair = str(row.id)
	_add_selector("time_pair", tr("UI_LAUNCH_TIME_PAIR_LABEL"), _state.loadout.time_pairs, selected_pair, selectors)
	_add_kit_strip(loadout, selected.character_id, selected.weapon_id, selected.enabled_time_skills, false)
	var modes := Page.grid("ExpeditionModes")
	loadout.add_child(modes)
	var boss_rush := _add_action("boss_rush", tr("UI_MODE_BOSS_RUSH"), "", bool(_state.launch_available), str(_state.launch_reason_key) if not _state.launch_available else "", func(): boss_rush_requested.emit(_state.loadout.selected.duplicate(true)))
	var endless := _add_action("endless", tr("UI_MODE_ENDLESS"), "", bool(_state.launch_available), str(_state.launch_reason_key) if not _state.launch_available else "", func(): endless_requested.emit(_state.loadout.selected.duplicate(true)))
	var daily := _add_action("daily_boss", tr("UI_DAILY_TITLE"), "", bool(_state.launch_available), str(_state.launch_reason_key) if not _state.launch_available else "", func(): daily_boss_requested.emit())
	var authored := _add_action("authored_challenges", tr("UI_AUTHORED_TITLE"), "", bool(_state.launch_available), str(_state.launch_reason_key) if not _state.launch_available else "", func(): authored_challenges_requested.emit())
	for action: Button in [boss_rush, endless, daily, authored]:
		Art.button_icon(action, Art.icon(&"mode_art", StringName(action.get_meta("action_id"))))
		Page.relocate_row(action, modes)
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
	if not str(_state.run_id).is_empty():
		var resume := Button.new()
		resume.name = "ResumeButton"
		resume.text = tr("UI_RESUME")
		resume.custom_minimum_size = Vector2(64, 25)
		resume.add_theme_font_size_override("font_size", 12)
		resume.disabled = not bool(_state.resume_available)
		resume.tooltip_text = tr(str(_state.resume_reason_key)) if resume.disabled else ""
		resume.set_meta("action_id", "resume")
		resume.set_meta("available", _state.resume_available)
		resume.pressed.connect(_activate_action.bind(resume, _emit_operation.bind("resume", {}), _epoch))
		footer.add_child(resume)
		footer.move_child(resume, 1)
		_actions.append(resume)


func _add_selector(field: String, label: String, rows: Array, selected_id: String, destination: VBoxContainer) -> void:
	var heading := Page.label(label, 11)
	heading.name = field + "Label"
	destination.add_child(heading)
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
	destination.add_child(option)
	_selectors[field] = option
	option.disabled = not bool(_state.launch_available)
	option.item_selected.connect(_selection_changed.bind(_epoch))
	option.gui_input.connect(_selector_input.bind(option, _epoch))


func _choose_character(index: int, source_epoch: int) -> void:
	if source_epoch != _epoch or _submitted or not visible or not _selectors.has("character_id"):
		return
	var option: OptionButton = _selectors.character_id
	if index < 0 or index >= option.item_count or option.disabled or option.is_item_disabled(index):
		return
	option.select(index)
	_selection_changed(index, source_epoch)


func _add_kit_strip(parent: Control, character_id: String, weapon_id: String, abilities: Array, include_character: bool = true) -> void:
	var strip := HBoxContainer.new()
	strip.name = "EquippedKit"
	strip.add_theme_constant_override("separation", 8)
	parent.add_child(strip)
	if include_character:
		strip.add_child(Art.image(Art.actor(character_id), 48))
	strip.add_child(Art.image(Art.icon(&"weapons", StringName(weapon_id)), 32, "EquippedWeapon"))
	for ability: String in abilities:
		strip.add_child(Art.image(Art.icon(&"time_abilities", StringName(ability)), 32, "EquippedTimeSlot"))
	var caption := Page.label(tr("WEAPON_%s_NAME" % weapon_id.to_upper()) + " / " + tr("UI_TIME_PAIR_FMT") % [tr("TIME_ABILITY_%s_NAME" % str(abilities[0]).to_upper()), tr("TIME_ABILITY_%s_NAME" % str(abilities[1]).to_upper())], 11)
	strip.add_child(caption)


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
	var weapons := Page.grid("ForgeWeapons")
	rows_container.add_child(weapons)
	for row: Dictionary in _state.forge.weapons:
		var weapon := Page.section(weapons, tr(str(row.name_key)), Art.icon(&"weapons", StringName(row.id)), "+%d  /  +%d%%" % [int(row.level), roundi(float(row.attack_bonus) * 100)])
		var pips := HBoxContainer.new()
		pips.name = "UpgradePips"
		pips.add_theme_constant_override("separation", 4)
		weapon.add_child(pips)
		for level: int in range(5):
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(20, 4)
			pip.color = Color("e5bd69") if level < int(row.level) else Color("697771")
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(pip)
		var upgrade: Dictionary = row.upgrade
		Page.relocate_row(_add_action("upgrade:" + str(row.id), "%s  %s" % [tr("UI_HUB_UPGRADE"), _cost(upgrade.cost)], "", bool(upgrade.available), str(upgrade.reason_key), _emit_operation.bind("forge_upgrade", {"weapon_id": row.id})), weapon)
		for enchantment: Dictionary in row.enchantments:
			var preference: Array = row.enchant_preferences.duplicate()
			if bool(enchantment.selected):
				preference.erase(enchantment.id)
			else:
				preference.append(enchantment.id)
			_add_preference("enchant:" + str(row.id) + ":" + str(enchantment.id), "%s  %s" % [tr(str(enchantment.name_key)), _cost(enchantment.cost)], enchantment, _emit_operation.bind("enchant_preference", {"weapon_id": row.id, "enchantment_ids": preference}))
			rows_container.get_child(-1).reparent(weapon, false)
		for payment: Dictionary in row.temper_options:
			Page.relocate_row(_add_action("temper:" + str(row.id) + ":" + str(payment.currency), "%s  %s" % [tr("UI_HUB_VOID_TEMPER"), _cost(payment.cost)], "", bool(payment.available), str(payment.reason_key), _emit_operation.bind("void_temper", {"weapon_id": row.id, "payment_currency": payment.currency})), weapon)


func _render_builds() -> void:
	var saved_builds := VBoxContainer.new()
	saved_builds.name = "SavedBuilds"
	saved_builds.add_theme_constant_override("separation", 8)
	rows_container.add_child(saved_builds)
	var selected: Dictionary = _state.loadout.selected
	_add_kit_strip(saved_builds, selected.character_id, selected.weapon_id, selected.enabled_time_skills)
	_build_name = LineEdit.new()
	_build_name.name = "BuildName"
	_build_name.placeholder_text = tr("UI_HUB_BUILD_NAME")
	_build_name.max_length = 64
	_build_name.text = _name_draft
	_build_name.custom_minimum_size = Vector2(0, 29)
	saved_builds.add_child(_build_name)
	_build_name.text_changed.connect(func(value: String): _name_draft = value)
	Page.relocate_row(_add_action("build_save", tr("UI_HUB_BUILD_SAVE"), "", bool(_state.loadout.build_save.available), str(_state.loadout.build_save.reason_key), _save_build), saved_builds)
	_share_code = LineEdit.new()
	_share_code.name = "ShareCode"
	_share_code.placeholder_text = tr("UI_SHARE_CODE")
	_share_code.max_length = ShareCodec.MAX_CODE_LENGTH
	_share_code.custom_minimum_size = Vector2(0, 29)
	_share_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_code.text = _share_draft
	saved_builds.add_child(_share_code)
	_share_code.text_changed.connect(func(value: String): _share_draft = value)
	var sharing := Page.grid("SharingTools")
	saved_builds.add_child(sharing)
	Page.relocate_row(_add_action("build_import", tr("UI_SHARE_IMPORT"), "", true, "", _import_share), sharing)
	var clipboard := DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	var reason := "" if clipboard else "UI_SHARE_CLIPBOARD_UNAVAILABLE"
	Page.relocate_row(_add_action("share_copy", tr("UI_SHARE_COPY"), "", clipboard, reason, _copy_share), sharing)
	Page.relocate_row(_add_action("share_paste", tr("UI_SHARE_PASTE"), "", clipboard, reason, _paste_share), sharing)
	for row: Dictionary in _state.builds:
		var build := Page.section(saved_builds, str(row.name), Art.actor(str(row.character_id)))
		_add_kit_strip(build, row.character_id, row.weapon_id, row.time_abilities, false)
		Page.relocate_row(_add_action("build_select:" + str(row.id), str(row.name), "%s / %s" % [tr("CHARACTER_%s_NAME" % str(row.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(row.weapon_id).to_upper())], bool(row.available), str(row.reason_key), _emit_operation.bind("build_select", {"build_id": row.id})), build)
		var tools := Page.grid("BuildTools")
		build.add_child(tools)
		Page.relocate_row(_add_action("build_export:" + str(row.id), tr("UI_SHARE_EXPORT"), "", bool(row.available), str(row.reason_key), _emit_operation.bind("build_export", {"build_id": row.id})), tools)
		Page.relocate_row(_add_action("build_remove:" + str(row.id), tr("UI_HUB_BUILD_REMOVE"), "", bool(row.remove.available), str(row.remove.reason_key), _emit_operation.bind("build_remove", {"build_id": row.id})), tools)


func show_share_code(code: String) -> void:
	if _state.get("function_id") != "meditation" or not is_instance_valid(_share_code) or not ShareCodec.decode(code).ok:
		return
	_share_draft = code
	_share_code.text = code
	_share_code.select_all()
	call_deferred("_focus_share", _epoch)


func _import_share() -> void:
	_share_draft = _share_code.text
	_emit_operation("build_import", {"command_id": "hub:%d:%d:build_import" % [int(_state.revision), int(_state.epoch)], "share_code": _share_draft})


func _copy_share() -> void:
	if not ShareCodec.decode(_share_code.text).ok:
		show_rejection("UI_SHARE_INVALID")
		return
	DisplayServer.clipboard_set(_share_code.text)
	_finish_clipboard_action()


func _paste_share() -> void:
	var pasted := DisplayServer.clipboard_get()
	if pasted.length() > ShareCodec.MAX_CODE_LENGTH:
		show_rejection("UI_SHARE_INVALID")
		return
	_share_draft = pasted
	_share_code.text = _share_draft
	_finish_clipboard_action()


func _finish_clipboard_action() -> void:
	_submitted = false
	for control: Control in _actions:
		(control as Button).disabled = not bool(control.get_meta("available", false))
	FocusCoordinator.link_ring(_focus_controls(), false)
	_share_code.grab_focus()


func _focus_share(source_epoch: int) -> void:
	await get_tree().process_frame
	if source_epoch == _epoch and visible and is_instance_valid(_share_code) and FocusCoordinator.active_scope() == self:
		_share_code.grab_focus()
		scroll.ensure_control_visible(_share_code)


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
	_name_draft = _build_name.text
	if _build_name.text.strip_edges().is_empty():
		show_rejection("UI_HUB_BUILD_NAME")
		return
	var selected: Dictionary = _state.loadout.selected
	_emit_operation("build_save", {"build": {"id": "build-%d-%d" % [int(_state.revision), int(_state.epoch)], "name": _build_name.text.strip_edges(), "character_id": selected.character_id, "weapon_id": selected.weapon_id, "time_abilities": selected.enabled_time_skills.duplicate()}})


func _render_collection(kind: String) -> void:
	if kind == "archive":
		_add_action("replay_library", tr("UI_REPLAY_LIBRARY"), "", true, "", func(): replay_library_requested.emit())
	if kind == "gallery":
		_add_action("challenge_rewards", tr("UI_CHALLENGE_REWARDS"), "", true, "", func(): challenge_rewards_requested.emit())
	var header_art := Art.icon(&"items", &"chronal_battery") if kind == "gallery" else Art.icon(&"time_abilities", &"rewind" if kind == "archive" else &"rift")
	var collection := Page.section(rows_container, title_label.text, header_art)
	var grid := Page.grid("CollectionGrid", 3)
	collection.add_child(grid)
	var rows: Array = _state.collections[kind]
	if rows.is_empty():
		collection.add_child(Page.label(tr("UI_HUB_EMPTY")))
	for row: Dictionary in rows:
		var tile := VBoxContainer.new()
		tile.name = "Collection_" + str(row.id)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_constant_override("separation", 4)
		grid.add_child(tile)
		var texture := Art.icon(&"items", StringName(row.id)) if kind == "gallery" else header_art
		var image := Art.image(texture, 32)
		image.modulate = Color.WHITE if row.owned else Color(0.28, 0.34, 0.30)
		tile.add_child(image)
		tile.add_child(Page.label(tr(str(row.name_key))))
		var ownership := Page.label(tr("UI_HUB_OWNED" if row.owned else "UI_HUB_LOCKED"), 11)
		ownership.add_theme_color_override("font_color", Color("79baa1") if row.owned else Color("abb8ac"))
		tile.add_child(ownership)
	if kind == "gallery":
		var cosmetics := CosmeticsPanel.new()
		rows_container.add_child(cosmetics)
		if cosmetics.configure(_state.cosmetics, _emit_operation, _activate_action, _epoch):
			_actions.append_array(cosmetics.action_buttons())
		else:
			cosmetics.queue_free()
	if kind == "mirror":
		_add_action("platform", tr("UI_PLATFORM_TITLE"), "", true, "", func(): platform_requested.emit())
		_render_providers()


func _render_providers() -> void:
	var providers := Page.section(rows_container, tr("UI_PLATFORM_TITLE"), Art.icon(&"mode_art", &"daily_boss"))
	providers.name = "ProviderRecords"
	for row: Dictionary in _state.providers:
		_add_text(tr("UI_COMMUNITY_LOCAL_RECORDS" if row.id == "leaderboard" and row.available else "UI_HUB_PROVIDER_" + str(row.id).to_upper()))
		var refresh := _add_action("provider_refresh:" + str(row.id), tr("UI_COMMUNITY_REFRESH"), "", true, "", _emit_operation.bind("provider_refresh", {"provider_id": row.id}))
		Art.button_icon(refresh, Art.icon(&"time_abilities", &"rewind"))
		if not row.available:
			_add_text(tr(str(row.reason_key)))
		elif row.entries.is_empty():
			_add_text(tr("UI_COMMUNITY_EMPTY"))
		for entry: Dictionary in row.entries:
			var record := HBoxContainer.new()
			record.set_meta("provider_record", row.id)
			record.add_theme_constant_override("separation", 12)
			rows_container.add_child(record)
			record.add_child(Page.label(str(entry.name)))
			var score := Page.label(str(int(entry.score)))
			score.theme_type_variation = &"CounterLabel"
			score.custom_minimum_size = Vector2(72, 0)
			score.size_flags_horizontal = Control.SIZE_SHRINK_END
			score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			record.add_child(score)


func focus_provider_result(id: String) -> void:
	_focus_provider_result.call_deferred(id, int(_state.epoch))


func _focus_provider_result(id: String, epoch: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or not visible or epoch != int(_state.epoch):
		return
	var panel_epoch := _epoch
	for action: Control in _actions:
		if action.get_meta("action_id", "") == "provider_refresh:" + id:
			action.grab_focus()
			await get_tree().process_frame
			if not is_inside_tree() or not visible or panel_epoch != _epoch or epoch != int(_state.epoch) or not is_instance_valid(action):
				return
			for row: Control in rows_container.get_children():
				if row.get_meta("provider_record", "") == id:
					scroll.ensure_control_visible(row)
					return
			scroll.ensure_control_visible(action)
			return


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
	if operation in ["meta_unlock", "forge_upgrade", "enchant_preference", "void_temper", "build_save", "build_remove", "narrative_dialogue", "cosmetic_claim", "cosmetic_equip"]:
		prepared.command_id = "hub:%d:%d:%s" % [int(_state.revision), int(_state.epoch), operation]
		prepared.kind = operation
	command_requested.emit({"epoch": _state.epoch, "function_id": _state.function_id, "operation": operation, "payload": prepared}, int(_state.revision))


func _cost(value: Dictionary) -> String:
	return tr("UI_HUB_CURRENCIES_FMT") % [int(value.get("chronos_shards", 0)), int(value.get("existential_imprints", 0))]


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	var actions := super._focus_controls()
	if _state.get("function_id") == "gateway":
		for action: Control in actions.duplicate():
			if str(action.get_meta("action_id", "")).begins_with("select_character:"):
				controls.append(action)
				actions.erase(action)
	for option: OptionButton in _selectors.values():
		if not option.disabled:
			controls.append(option)
	if is_instance_valid(_build_name):
		controls.append(_build_name)
		for control: Control in actions:
			if control.get_meta("action_id", "") == "build_save":
				controls.append(control)
				actions.erase(control)
				break
	if is_instance_valid(_share_code):
		controls.append(_share_code)
	controls.append_array(actions)
	return controls


func _clear_rows() -> void:
	for child: Node in footer.get_children():
		if child != back_button:
			footer.remove_child(child)
			child.queue_free()
	super._clear_rows()
