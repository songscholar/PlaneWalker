extends "res://scripts/ui/dungeon_panel_view.gd"

signal action_requested(id: String)

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
var _countdown: Label
var _commands: VBoxContainer


func render(state: Dictionary):
	var result = super.render(state)
	if result.ok:
		_update_return_label()
	return result


func _build_layout() -> void:
	super._build_layout()
	_commands = VBoxContainer.new()
	_commands.name = "DailyCommands"
	_commands.add_theme_constant_override("separation", 3)
	var layout := scroll.get_parent()
	layout.add_child(_commands)
	layout.move_child(_commands, scroll.get_index())


func _add_action(identifier: String, text: String, description: String, available: bool, disabled_reason_key: String, callback: Callable) -> Button:
	var button := super._add_action(identifier, text, description, available, disabled_reason_key, callback)
	button.get_parent().reparent(_commands, false)
	return button


func _clear_rows() -> void:
	if is_instance_valid(_commands):
		for row: Node in _commands.get_children():
			_commands.remove_child(row)
			row.queue_free()
	super._clear_rows()


func _validate(value: Dictionary):
	if not Meta.exact_fields(value, ["run_id", "revision", "preview", "condition_keys", "content_names"]) or not value.run_id is String or not Meta.bounded_int(value.revision, 0, Meta.MAX_VALUE) or not value.preview is Dictionary or not value.condition_keys is Dictionary or not value.content_names is Dictionary:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(value.revision))


func _render_state() -> void:
	title_label.text = tr("UI_DAILY_TITLE")
	var preview: Dictionary = _state.preview
	var definition: Dictionary = preview.definition
	if definition.is_empty():
		summary_label.text = tr("UI_DAILY_CLOCK_INVALID")
		return
	summary_label.text = "%s / %s" % [definition.day_key, tr("BOSS_%s_NAME" % str(definition.boss_id).to_upper())]
	_countdown = _add_text("", "DailyCountdown")
	update_countdown(int(preview.remaining_seconds))
	_add_text(tr("UI_DAILY_ATTEMPTS_FMT") % preview.remaining_attempts)
	_add_text(tr("UI_DAILY_LOADOUT_FMT") % [tr("WEAPON_%s_NAME" % str(definition.weapon_id).to_upper()), tr("INPUT_ACTION_TIME_" + str(definition.time_abilities[0]).to_upper()), tr("INPUT_ACTION_TIME_" + str(definition.time_abilities[1]).to_upper())])
	var items := PackedStringArray()
	for id: String in definition.item_ids:
		items.append(tr(str(_state.content_names[id])))
	_add_text(tr("UI_DAILY_ITEMS_FMT") % " / ".join(items))
	_add_text(tr("UI_DAILY_BLESSING_FMT") % tr(str(_state.content_names[definition.blessing_id])))
	_add_text(tr("UI_DAILY_CURSE_FMT") % tr(str(_state.content_names[definition.curse_id])))
	for id: String in definition.condition_ids:
		_add_text(tr(str(_state.condition_keys[id])))
	if not preview.best.is_empty():
		_add_text(tr("UI_DAILY_BEST_FMT") % _result_label(preview.best))
	for result: Dictionary in preview.results:
		_add_text(tr("UI_DAILY_RESULT_FMT") % [int(result.attempt), _result_label(result)])
	if preview.pending:
		if preview.save_error == "DAILY_STALE_PRIMARY":
			_add_text(tr("UI_MODE_STALE"))
			_action("reload", "UI_MODE_RELOAD")
		else:
			_add_text(tr("UI_MODE_SAVE_PENDING"))
			_action("retry", "UI_MODE_RETRY_SAVE")
	elif preview.native_retry:
		_add_text(tr("UI_DAILY_NATIVE_RETRY"))
		_action("native_retry", "UI_DAILY_RETRY_ARENA")
	elif not preview.active.is_empty():
		if preview.native_active:
			_action("resume", "UI_MODE_RESUME")
		else:
			_add_text(tr("UI_DAILY_INTERRUPTED"))
		_action("abandon", "UI_DAILY_ABANDON")
	else:
		if not preview.available:
			_add_text(tr("UI_" + str(preview.reason)))
		_add_action("start", tr("UI_MODE_START"), "", preview.available, "", func(): action_requested.emit("start"))
	_add_text(tr("UI_DAILY_CALENDAR"))
	for future: Dictionary in preview.calendar:
		_add_text("%s / %s / %s" % [future.day_key, tr("BOSS_%s_NAME" % str(future.boss_id).to_upper()), tr("WEAPON_%s_NAME" % str(future.weapon_id).to_upper())])
	back_button.disabled = preview.pending


func update_countdown(seconds: int) -> void:
	if is_instance_valid(_countdown):
		_countdown.text = tr("UI_DAILY_RESET_FMT") % [seconds / 3600, (seconds / 60) % 60, seconds % 60]


func _update_return_label() -> void:
	back_button.text = tr("UI_DAILY_ABANDON_RETURN" if not _state.preview.active.is_empty() else "UI_BACK")


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _state.is_empty():
		_update_return_label()


func _action(id: String, key: String) -> void:
	_add_action(id, tr(key), "", true, "", func(): action_requested.emit(id))


func _result_label(value: Dictionary) -> String:
	return "%s / %.2fs / %.1f%% HP" % [tr("UI_DAILY_RESULT_" + str(value.status)), float(value.elapsed_frames) / 60.0, float(value.remaining_hp_milli) / 1000.0]
