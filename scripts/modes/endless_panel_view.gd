extends "res://scripts/ui/dungeon_panel_view.gd"

signal action_requested(id: String)
const Endless := preload("res://scripts/modes/endless_session.gd")
const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Request := preload("res://scripts/modes/boss_rush_catalog.gd")


func _validate(value: Dictionary):
	if not Meta.exact_fields(value, ["run_id", "revision", "owner", "request", "session", "active", "paused", "pending", "save_error"]) or not value.run_id is String or not Meta.bounded_int(value.revision, 0, Meta.MAX_VALUE) or not value.owner is String or not Request.valid_request(value.request) or not Endless.valid(value.session, value.owner) or not value.active is bool or not value.paused is bool or not value.pending is bool or not value.save_error is String:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(value.revision))


func _render_state() -> void:
	title_label.text = tr("UI_MODE_ENDLESS")
	var state: Dictionary = _state.session
	var request: Dictionary = state.request if _state.active else _state.request
	summary_label.text = "%s / %s" % [tr("CHARACTER_%s_NAME" % str(request.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(request.weapon_id).to_upper())]
	if state.status != "IDLE":
		_add_text(tr("UI_MODE_STATUS_" + str(state.status)))
		_add_text(tr("UI_ENDLESS_PROGRESS_FMT") % [int(state.cycle_index) + 1, (int(state.cycle_index) + (1 if state.status == "CYCLE_CLEAR" else 0)) * 5, float(state.elapsed_frames) / 60.0])
		var scaling := Endless.scaling(int(state.cycle_index))
		_add_text(tr("UI_ENDLESS_SCALING_FMT") % [float(scaling.hp_multiplier), float(scaling.damage_multiplier)])
		_add_text(tr("UI_MODE_CONTINUED" if state.continued else "UI_MODE_FRESH"))
		if state.request.accessibility_assists.damage_received_multiplier != 1.0 or state.request.accessibility_assists.enemy_telegraph_scale != 1.0:
			_add_text(tr("UI_MODE_ASSISTED"))
	if _state.pending:
		_add_text(tr("UI_MODE_STALE" if _state.save_error == "ENDLESS_STALE_PRIMARY" else "UI_MODE_SAVE_PENDING"))
		_command("reload" if _state.save_error == "ENDLESS_STALE_PRIMARY" else "retry", "UI_MODE_RELOAD" if _state.save_error == "ENDLESS_STALE_PRIMARY" else "UI_MODE_RETRY_SAVE")
	elif _state.active and state.status == "ACTIVE":
		_command("resume", "UI_MODE_RESUME")
	elif state.status == "CYCLE_CLEAR":
		_command("next" if _state.active else "continue", "UI_ENDLESS_NEXT_CYCLE")
	else:
		if not _state.active and state.status in ["STARTING", "ACTIVE"]:
			_command("continue", "UI_MODE_CONTINUE")
		_command("start", "UI_MODE_START")
	back_button.disabled = _state.pending


func _command(id: String, key: String) -> void:
	_add_action(id, tr(key), "", true, "", func(): action_requested.emit(id))


func _request_close() -> void:
	if not back_button.disabled:
		super._request_close()
