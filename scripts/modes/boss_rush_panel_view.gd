extends "res://scripts/ui/dungeon_panel_view.gd"

signal action_requested(id: String)

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")


func _validate(value: Dictionary):
	if not Catalog.exact_fields(value, ["run_id", "revision", "request", "session", "active", "paused", "pending", "save_error"]) or not value.run_id is String or not Catalog.bounded_int(value.revision, 0, Catalog.MAX_VALUE) or not value.request is Dictionary or not value.session is Dictionary or not value.active is bool or not value.paused is bool or not value.pending is bool or not value.save_error is String:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(value.revision))


func _render_state() -> void:
	title_label.text = tr("UI_MODE_BOSS_RUSH")
	var session: Dictionary = _state.session
	var request: Dictionary = _state.request
	summary_label.text = _loadout_label(session.request if _state.active else request)
	if session.status != "IDLE":
		if not _state.active:
			_add_text(tr("UI_MODE_SAVED_LOADOUT_FMT") % _loadout_label(session.request))
		_add_text(tr("UI_MODE_STATUS_" + str(session.status)))
		_add_text(tr("UI_MODE_PROGRESS_FMT") % [session.completed_stages.size(), 5, float(session.elapsed_frames) / 60.0])
		_add_text(tr("UI_MODE_CONTINUED" if session.continued else "UI_MODE_FRESH"))
		if session.request.accessibility_assists.damage_received_multiplier != 1.0 or session.request.accessibility_assists.enemy_telegraph_scale != 1.0:
			_add_text(tr("UI_MODE_ASSISTED"))
	for row: Dictionary in session.completed_stages:
		_add_text("%s / %.2fs" % [tr("BOSS_%s_NAME" % str(row.boss_id).to_upper()), float(row.frames) / 60.0])
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
		_action("next", "UI_MODE_NEXT_BOSS")
	else:
		if not _state.active and session.status in ["ACTIVE", "STAGE_CLEAR"]:
			_action("continue", "UI_MODE_CONTINUE")
		_action("start", "UI_MODE_START")
	back_button.disabled = _state.pending


func _action(id: String, key: String) -> void:
	_add_action(id, tr(key), "", true, "", func(): action_requested.emit(id))


func _loadout_label(request: Dictionary) -> String:
	return "%s / %s" % [tr("CHARACTER_%s_NAME" % str(request.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(request.weapon_id).to_upper())]
