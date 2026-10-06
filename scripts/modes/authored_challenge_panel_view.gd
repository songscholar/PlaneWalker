extends "res://scripts/ui/components/mode_panel_view.gd"

signal action_requested(id: String)
signal set_selected(id: String)

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Catalog := preload("res://scripts/modes/authored_challenge_catalog.gd")
const Session := preload("res://scripts/modes/authored_challenge_session.gd")
const Rush := preload("res://scripts/modes/boss_rush_catalog.gd")
var selector: OptionButton
var _commands: GridContainer


func _build_layout() -> void:
	super._build_layout()
	var layout := scroll.get_parent()
	selector = OptionButton.new()
	selector.name = "ChallengeSelector"
	selector.custom_minimum_size = Vector2(0, 29)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.focus_mode = Control.FOCUS_ALL
	selector.add_theme_font_size_override("font_size", 12)
	selector.item_selected.connect(func(index: int):
		if visible and not selector.disabled and not _submitted and index >= 0 and index < selector.item_count:
			set_selected.emit(str(selector.get_item_metadata(index))))
	layout.add_child(selector)
	layout.move_child(selector, scroll.get_index())
	_commands = _mode_commands
	_commands.name = "AuthoredCommands"


func render(state: Dictionary):
	var result = super.render(state)
	if result.ok:
		_update_return()
	return result


func _validate(value: Dictionary):
	if not Meta.exact_fields(value, ["run_id", "revision", "selected_id", "preview", "content_names"]) or not value.run_id is String or not Meta.bounded_int(value.revision, 0, Meta.MAX_VALUE) or not value.selected_id is String or not value.content_names is Dictionary or not Meta.exact_fields(value.preview, ["sets", "active", "history", "best", "native_active", "paused", "pending", "native_retry", "save_error", "start_reason", "current_boss_id"]):
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	var preview: Dictionary = value.preview
	if not preview.sets is Array or preview.sets.size() != 5 or not preview.active is Dictionary or not preview.history is Dictionary or not preview.best is Dictionary or preview.history.size() > 5 or preview.best.size() > 5:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	for field: String in ["native_active", "paused", "pending", "native_retry"]:
		if not preview[field] is bool:
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	for field: String in ["save_error", "start_reason", "current_boss_id"]:
		if not preview[field] is String:
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	if not preview.current_boss_id.is_empty() and preview.current_boss_id not in Rush.BOSSES:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	var sets := {}
	for row: Variant in preview.sets:
		if not _valid_set(row, value.content_names) or sets.has(row.id):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
		sets[row.id] = true
	if not sets.has(value.selected_id) or not preview.active.is_empty() and not _valid_display_record(preview.active, sets, true):
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	for id: Variant in preview.history:
		if not id is String or not sets.has(id) or not preview.history[id] is Array or preview.history[id].is_empty() or preview.history[id].size() > 10:
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
		for row: Variant in preview.history[id]:
			if not _valid_display_record(row, sets, false) or row.set_id != id:
				return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	for id: Variant in preview.best:
		var row: Variant = preview.best[id]
		if not id is String or not sets.has(id) or not _valid_display_record(row, sets, false) or row.set_id != id or row.status != "VICTORY" or row.continued:
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(value.revision))


func _valid_set(value: Variant, names: Dictionary) -> bool:
	if not Meta.exact_fields(value, Catalog.SET_FIELDS) or not value.id is String or value.id.is_empty() or not value.name_key is String or not Meta.bounded_int(value.seed, 0, Meta.MAX_VALUE) or value.weapon_id not in Meta.WEAPON_IDS or not Catalog.valid_objective(value.objective) or not value.time_abilities is Array or value.time_abilities.size() != 2 or value.time_abilities[0] not in Meta.TIME_IDS or value.time_abilities[1] not in Meta.TIME_IDS or value.time_abilities[0] == value.time_abilities[1] or not value.item_ids is Array or value.item_ids.size() != 3 or not value.boss_ids is Array or value.boss_ids.size() != 3:
		return false
	for id: Variant in value.boss_ids:
		if not id is String or id not in Rush.BOSSES:
			return false
	for id: Variant in value.item_ids + [value.blessing_id, value.curse_id]:
		if not id is String or not names.get(id) is String or str(names[id]).is_empty():
			return false
	return true


func _valid_display_record(value: Variant, sets: Dictionary, active: bool) -> bool:
	if not Meta.exact_fields(value, Session.ACTIVE_FIELDS if active else Session.RESULT_FIELDS) or not value.set_id is String or not sets.has(value.set_id) or not value.run_id is String or not Meta.bounded_int(value.sequence, 1, Meta.MAX_VALUE) or not Session.valid_metrics(value) or not value.stages is Array or value.stages.size() > 3:
		return false
	if active:
		return value.status in ["ACTIVE", "STAGE_CLEAR"] and Meta.bounded_int(value.stage_index, 0, 2) and Meta.bounded_int(value.stage_frames, 0, Meta.MAX_VALUE) and Meta.bounded_int(value.stage_damage_events, 0, Meta.MAX_VALUE)
	return value.status in ["VICTORY", "OBJECTIVE_FAILED", "DEFEAT", "ABANDON"] and Meta.bounded_int(value.remaining_hp_milli, 0, 100000) and value.terminal_digest is String


func _render_state() -> void:
	title_label.text = tr("UI_AUTHORED_TITLE")
	var preview: Dictionary = _state.preview
	var definition: Dictionary = {}
	selector.clear()
	for row: Dictionary in preview.sets:
		selector.add_item(tr(str(row.name_key)))
		selector.set_item_metadata(selector.item_count - 1, row.id)
		if row.id == _state.selected_id:
			definition = row
			selector.select(selector.item_count - 1)
	selector.disabled = not preview.active.is_empty() or preview.pending
	_mode_identity("authored_challenges")
	_loadout_art(definition, _state.content_names)
	_boss_track(definition.boss_ids, preview.active.stages.size() if not preview.active.is_empty() else 0, int(preview.active.stage_index) if not preview.active.is_empty() else 0)
	var objective: Dictionary = definition.objective
	var limit: float = float(objective.limit) / (60.0 if objective.kind in ["total_time", "stage_time"] else (1000.0 if objective.kind == "minimum_hp" else 1.0))
	summary_label.text = tr(str(objective.name_key)) if objective.kind == "no_damage" else tr(str(objective.name_key)) % limit
	_add_text(tr("UI_AUTHORED_BUILD_FMT") % [tr("WEAPON_%s_NAME" % str(definition.weapon_id).to_upper()), tr("INPUT_ACTION_TIME_" + str(definition.time_abilities[0]).to_upper()), tr("INPUT_ACTION_TIME_" + str(definition.time_abilities[1]).to_upper())])
	var bosses := PackedStringArray()
	for id: String in definition.boss_ids:
		bosses.append(tr("BOSS_%s_NAME" % id.to_upper()))
	_add_text(tr("UI_AUTHORED_ROUTE_FMT") % " / ".join(bosses))
	var items := PackedStringArray()
	for id: String in definition.item_ids:
		items.append(tr(str(_state.content_names[id])))
	_add_text(tr("UI_AUTHORED_ITEMS_FMT") % " / ".join(items))
	_add_text(tr("UI_AUTHORED_BLESSING_FMT") % tr(str(_state.content_names[definition.blessing_id])))
	_add_text(tr("UI_AUTHORED_CURSE_FMT") % tr(str(_state.content_names[definition.curse_id])))
	var active: Dictionary = preview.active
	if not active.is_empty():
		_add_text(tr("UI_AUTHORED_STAGE_FMT") % [int(active.stage_index) + 1, float(active.elapsed_frames) / 60.0, int(active.damage_events)])
		if active.continued:
			_add_text(tr("UI_AUTHORED_PRACTICE"))
	if preview.pending:
		_add_text(tr("UI_AUTHORED_STALE_PRIMARY" if preview.save_error == "AUTHORED_STALE_PRIMARY" else "UI_MODE_SAVE_PENDING"))
		_action("reload", "UI_MODE_RELOAD") if preview.save_error == "AUTHORED_STALE_PRIMARY" else _action("retry", "UI_MODE_RETRY_SAVE")
	elif preview.native_retry:
		_add_text(tr("UI_AUTHORED_NATIVE_INVALID"))
		_action("native_retry", "UI_DAILY_RETRY_ARENA")
		_action("abandon", "UI_AUTHORED_ABANDON")
	elif not active.is_empty():
		if preview.native_active:
			_action("next", "UI_MODE_NEXT_BOSS") if active.status == "STAGE_CLEAR" else _action("resume", "UI_MODE_RESUME")
		else:
			_add_text(tr("UI_AUTHORED_CONTINUE_NOTICE"))
			_action("continue", "UI_AUTHORED_CONTINUE")
		_action("abandon", "UI_AUTHORED_ABANDON")
	else:
		if not preview.start_reason.is_empty():
			_add_text(tr("UI_" + str(preview.start_reason)))
		_add_action("start", tr("UI_MODE_START"), "", preview.start_reason.is_empty(), "", func(): action_requested.emit("start"))
	if preview.best.has(definition.id):
		_add_text(tr("UI_AUTHORED_BEST_FMT") % _result_label(preview.best[definition.id]))
	var history: Array = preview.history.get(definition.id, [])
	if not history.is_empty():
		_add_text(tr("UI_AUTHORED_HISTORY"))
		for index: int in range(history.size() - 1, -1, -1):
			_record(_result_label(history[index]), Art.icon(&"weapons", StringName(definition.weapon_id)))
	back_button.disabled = preview.pending


func _action(id: String, key: String) -> void:
	_add_action(id, tr(key), "", true, "", func(): action_requested.emit(id))


func _result_label(value: Dictionary) -> String:
	return tr("UI_AUTHORED_RESULT_FMT") % [int(value.sequence), tr("UI_AUTHORED_RESULT_" + str(value.status)), float(value.elapsed_frames) / 60.0, int(value.damage_events), float(value.remaining_hp_milli) / 1000.0, tr("UI_AUTHORED_PRACTICE" if value.continued else "UI_AUTHORED_FRESH")]


func _clear_rows() -> void:
	if is_instance_valid(_commands):
		for row: Node in _commands.get_children():
			_commands.remove_child(row)
			row.queue_free()
	super._clear_rows()


func _focus_controls() -> Array[Control]:
	var controls := super._focus_controls()
	if not selector.disabled:
		controls.push_front(selector)
	return controls


func _request_close() -> void:
	if _state.is_empty() or _state.preview.pending:
		return
	super._request_close()


func _update_return() -> void:
	back_button.text = tr("UI_AUTHORED_SAVE_RETURN" if _state.preview.native_active else "UI_BACK")


func _unhandled_input(event: InputEvent) -> void:
	if visible and FocusCoordinator.active_scope() == self and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		_request_close()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _state.is_empty():
		_update_return()
