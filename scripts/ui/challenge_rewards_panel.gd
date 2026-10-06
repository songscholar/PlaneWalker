extends "res://scripts/ui/dungeon_panel_view.gd"

const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
var _service: RefCounted
var _synchronize: Callable
var _view_epoch := 0


func configure(service: RefCounted, synchronize: Callable) -> bool:
	if not is_node_ready() or _service != null or not service is Service or not synchronize.is_valid():
		return false
	_service = service
	_synchronize = synchronize
	return true


func open() -> Dictionary:
	if _service == null:
		return {"ok": false, "code": &"NOT_CONFIGURED"}
	var synchronized: Dictionary = _synchronize.call()
	_view_epoch += 1
	var result = render({"run_id": "challenge-rewards", "revision": int(_service.snapshot().revision), "epoch": _view_epoch, "model": _service.challenge_reward_view()})
	if result.ok and not synchronized.ok:
		show_rejection("UI_HUB_SAVE_RETRY")
	return {"ok": result.ok, "code": result.code}


func _validate(value: Dictionary):
	if _service == null or value.size() != 4 or value.get("run_id") != "challenge-rewards" or value.get("epoch") != _view_epoch or not value.get("revision") is int or value.revision != int(_service.snapshot().revision) or not Rules.same(value.get("model"), _service.challenge_reward_view()):
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(value.revision)


func _render_state() -> void:
	title_label.text = tr("UI_CHALLENGE_REWARDS")
	summary_label.text = ""
	if _state.model.rows.is_empty():
		_add_text(tr("UI_HUB_EMPTY"))
	for row: Dictionary in _state.model.rows:
		var line := HBoxContainer.new()
		line.name = "ChallengeRewardRow_" + str(row.id)
		line.add_theme_constant_override("separation", 8)
		line.custom_minimum_size = Vector2(0, 29)
		rows_container.add_child(line)
		var texture := Art.icon(&"challenge_rewards", StringName(row.id))
		line.add_child(Art.image(texture, 32, "ChallengeRewardArtwork"))
		if not row.tint.is_empty():
			var swatch := ColorRect.new()
			swatch.color = Color(row.tint[0], row.tint[1], row.tint[2], row.tint[3])
			swatch.custom_minimum_size = Vector2(20, 20)
			swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(swatch)
		var toggle := CheckBox.new()
		toggle.name = "Reward_" + str(row.id)
		toggle.text = tr(str(row.name_key))
		toggle.button_pressed = row.equipped
		toggle.custom_minimum_size = Vector2(0, 29)
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toggle.add_theme_font_size_override("font_size", 12)
		toggle.set_meta("action_id", "reward:" + str(row.id))
		toggle.set_meta("available", true)
		toggle.pressed.connect(_activate_action.bind(toggle, _equip.bind(str(row.id), not row.equipped, int(_state.revision)), _epoch))
		line.add_child(toggle)
		_actions.append(toggle)
		for field: String in row.effects:
			_add_text(tr("UI_CHALLENGE_" + field.to_upper() + "_FMT") % roundi((float(row.effects[field]) - 1.0) * 100.0))
	var synchronize := _add_action("synchronize", tr("UI_COMMUNITY_REFRESH"), "", true, "", open)
	Art.button_icon(synchronize, Art.icon(&"controls", &"refresh"))


func _equip(id: String, equipped: bool, revision: int) -> void:
	var result: Dictionary = _service.equip_challenge_reward(id, equipped, revision)
	if result.ok:
		GameState.refresh_profile_state()
		open()
	else:
		show_rejection("UI_HUB_SAVE_RETRY")


func handle_input(event: InputEvent) -> bool:
	if not visible or FocusCoordinator.active_scope() != self:
		return false
	if event.is_action_pressed("ui_cancel"):
		_request_close()
		return true
	var controls := _focus_controls()
	var owner := get_viewport().gui_get_focus_owner()
	var direction := 1 if event.is_action_pressed("ui_down") else (-1 if event.is_action_pressed("ui_up") else 0)
	if direction != 0 and not controls.is_empty():
		controls[posmod(controls.find(owner) + direction, controls.size())].grab_focus()
		return true
	if event.is_action_pressed("ui_accept") and owner is Button and not owner.disabled:
		owner.pressed.emit()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()
