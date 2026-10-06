extends "res://scripts/ui/components/mode_panel_view.gd"

signal action_requested(id: String)

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Route := preload("res://scripts/modes/boss_rush_catalog.gd")


func _validate(value: Dictionary):
	var fields: Array = ["run_id", "revision", "request", "session", "active", "paused", "pending", "save_error"]
	if value.has("unlocked"):
		fields.append("unlocked")
	if not Catalog.exact_fields(value, fields) or not value.run_id is String or not Catalog.bounded_int(value.revision, 0, Catalog.MAX_VALUE) or not value.request is Dictionary or not value.session is Dictionary or not value.active is bool or not value.paused is bool or not value.pending is bool or not value.save_error is String or value.has("unlocked") and not value.unlocked is bool:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(value.revision))


func _render_state() -> void:
	title_label.text = tr("UI_MODE_BOSS_RUSH")
	var session: Dictionary = _state.session
	var request: Dictionary = _state.request
	summary_label.text = _loadout_label(session.request if _state.active else request)
	_mode_identity("boss_rush")
	_loadout_art(session.request if _state.active else request)
	_boss_track(Route.BOSSES, session.completed_stages.size(), int(session.stage_index))
	if not _state.get("unlocked", true):
		_add_text(tr("UI_RUSH_LOCKED"))
	if session.status != "IDLE":
		if not _state.active:
			_add_text(tr("UI_MODE_SAVED_LOADOUT_FMT") % _loadout_label(session.request))
		_add_text(tr("UI_MODE_STATUS_" + str(session.status)))
		_add_text(tr("UI_MODE_PROGRESS_FMT") % [session.completed_stages.size(), 5, float(session.elapsed_frames) / 60.0])
		_add_text(tr("UI_MODE_CONTINUED" if session.continued else "UI_MODE_FRESH"))
		if session.request.accessibility_assists.damage_received_multiplier != 1.0 or session.request.accessibility_assists.enemy_telegraph_scale != 1.0:
			_add_text(tr("UI_MODE_ASSISTED"))
	for row: Dictionary in session.completed_stages:
		_record("%s / %.2fs" % [tr("BOSS_%s_NAME" % str(row.boss_id).to_upper()), float(row.frames) / 60.0], Art.actor(str(row.boss_id)))
	if session.has("carried"):
		var carried: Dictionary = session.carried
		if not carried.portable.is_empty():
			_add_text(tr("UI_RUSH_BUILD_FMT") % [float(carried.portable.health.current_hp), float(carried.portable.health.max_hp), carried.gold, carried.item_ids.size(), carried.blessing_ids.size()])
		for id: String in carried.reward_ids:
			_add_text(tr("UI_RUSH_REWARD_" + id.to_upper()))
		for index: int in range(maxi(0, carried.history.size() - 10), carried.history.size()):
			var row: Dictionary = carried.history[index]
			_add_text(tr("UI_RUSH_HISTORY_FMT") % [row.sequence, float(row.elapsed_frames) / 60.0, 100.0 * float(row.remaining_hp) / float(row.maximum_hp), tr("WEAPON_%s_NAME" % str(row.request.weapon_id).to_upper())])
	if _state.pending:
		if _state.save_error == "CHALLENGE_STALE_PRIMARY":
			_add_text(tr("UI_MODE_STALE"))
			_action("reload", "UI_MODE_RELOAD")
		else:
			_add_text(tr("UI_MODE_SAVE_PENDING"))
			_action("retry", "UI_MODE_RETRY_SAVE")
	elif _state.active and session.status == "ACTIVE":
		_action("resume", "UI_MODE_RESUME")
	elif _state.active and session.status == "STAGE_CLEAR":
		if session.has("carried"):
			for index: int in range(session.carried.choices.size()):
				var row: Dictionary = session.carried.choices[index]
				var label := tr("UI_RUSH_FULL_RESTORE") if row.kind == "restore" else tr("UI_RUSH_CHOOSE_" + str(row.kind).to_upper()) + ": " + tr(str(row.id).to_upper() + "_NAME")
				var action_id := "choice_%d" % index
				var button := _add_action(action_id, label, "", true, "", func(): action_requested.emit(action_id))
				Art.button_icon(button, Art.icon(&"room_types", &"rest") if row.kind == "restore" else Art.content(str(row.id), str(row.kind)))
		else:
			_action("next", "UI_MODE_NEXT_BOSS")
	else:
		if not _state.active and session.status in ["ACTIVE", "STAGE_CLEAR"]:
			_action("continue", "UI_MODE_CONTINUE")
		if _state.get("unlocked", true):
			_action("start", "UI_MODE_START")
	back_button.disabled = _state.pending


func _action(id: String, key: String) -> void:
	_add_action(id, tr(key), "", true, "", func(): action_requested.emit(id))


func _loadout_label(request: Dictionary) -> String:
	return "%s / %s" % [tr("CHARACTER_%s_NAME" % str(request.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(request.weapon_id).to_upper())]
