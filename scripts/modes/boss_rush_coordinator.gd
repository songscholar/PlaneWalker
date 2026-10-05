extends Node2D

signal closed

const Flow := preload("res://scripts/modes/native_boss_rush_flow.gd")
const PanelScript := preload("res://scripts/modes/boss_rush_panel_view.gd")
const Catalog := preload("res://scripts/modes/boss_rush_catalog.gd")

var _flow: Node2D
var _panel: Control
var _hud: Control
var _label: Label
var _health: Label
var _request: Dictionary = {}
var _open := false
var _paused := false
var _view_revision := 0


func configure(registry: RefCounted, service: RefCounted, root_path: String, carried: bool = false) -> Dictionary:
	if _flow != null or not is_inside_tree():
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	var flow := Flow.new()
	add_child(flow)
	var result: Dictionary = flow.configure(registry, service, root_path, carried)
	if not result.ok:
		flow.queue_free()
		return result
	_flow = flow
	_flow.state_changed.connect(_project)
	_flow.save_rejected.connect(func(_code: StringName): _paused = true; _project())
	_flow.closed.connect(_finish_close)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_hud = MarginContainer.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for side: String in ["left", "right", "top", "bottom"]:
		_hud.add_theme_constant_override("margin_" + side, 12)
	layer.add_child(_hud)
	var layout := VBoxContainer.new()
	_hud.add_child(layout)
	var row := HBoxContainer.new()
	layout.add_child(row)
	_label = Label.new()
	_label.name = "ChallengeTimer"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", 12)
	row.add_child(_label)
	_health = Label.new()
	_health.name = "ChallengeHealth"
	_health.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health.add_theme_font_size_override("font_size", 12)
	layout.add_child(_health)
	var pause := Button.new()
	pause.name = "PauseButton"
	pause.text = tr("UI_MODE_PAUSE")
	pause.pressed.connect(_pause)
	row.add_child(pause)
	_hud.visible = false
	_panel = PanelScript.new()
	layer.add_child(_panel)
	_panel.action_requested.connect(_action)
	_panel.close_requested.connect(func(_revision: int): return_to_hub())
	for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
		runtime.apply_to_tree(_hud)
	return _success()


func open(request: Dictionary) -> Dictionary:
	if _flow == null or _open or not Catalog.valid_request(request):
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	_request = request.duplicate(true)
	_open = true
	_paused = false
	_project()
	return _success()


func is_open() -> bool:
	return _open


func panel() -> Control:
	return _panel


func runtime() -> Node2D:
	return _flow


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if event.is_action_pressed("pause"):
		if _paused and _flow.is_active() and _flow.snapshot().status == "ACTIVE" and not _flow.has_pending_save():
			_action("resume")
		elif not _panel.visible:
			_pause()
	return true


func return_to_hub() -> Dictionary:
	if not _open or _flow.has_pending_save():
		return _failure(&"CHALLENGE_RETRY_INVALID")
	if _flow.is_active():
		return _flow.save_and_return()
	_finish_close()
	return _success()


func _finish_close() -> void:
	_open = false
	_paused = false
	_panel.close_panel()
	_hud.visible = false
	closed.emit()


func _pause() -> void:
	if _open and _flow.is_active() and _flow.snapshot().status == "ACTIVE":
		_paused = true
		_flow.set_paused(true)
		_project()


func _action(id: String) -> void:
	var result: Dictionary
	match id:
		"start":
			_flow.close()
			_paused = false
			result = _flow.start(_request)
		"continue":
			_paused = false
			result = _flow.continue_session()
		"next":
			_paused = false
			result = _flow.next_stage()
		"resume":
			_paused = false
			_flow.set_paused(false)
			result = _success()
		"retry":
			_paused = false
			result = _flow.retry_save()
		"reload":
			_paused = false
			result = _flow.reload_saved_session()
		_:
			result = _flow.choose_reward(int(id.trim_prefix("choice_"))) if id in ["choice_0", "choice_1", "choice_2"] else _failure(&"CHALLENGE_COMMAND_INVALID")
	_project()
	if not result.ok:
		_panel.show_rejection("UI_MODE_STALE" if result.code == &"CHALLENGE_STALE_PRIMARY" else ("UI_MODE_NATIVE_RETRY" if result.code == &"CHALLENGE_NATIVE_INVALID" else "UI_MODE_SAVE_PENDING"))


func _project() -> void:
	if not _open or _flow == null:
		return
	var session: Dictionary = _flow.snapshot()
	var playing: bool = _flow.is_active() and session.status == "ACTIVE" and not _paused and not _flow.has_pending_save()
	_hud.visible = playing
	if playing:
		_panel.close_panel()
		get_viewport().gui_release_focus()
		return
	_view_revision += 1
	_panel.render({"run_id": "boss-rush-menu", "revision": _view_revision, "request": _request, "session": session, "active": _flow.is_active(), "paused": _paused, "pending": _flow.has_pending_save(), "save_error": str(_flow.save_error()), "unlocked": _flow.is_unlocked()})
	_panel.back_button.text = tr("UI_MODE_RETURN")


func _process(_delta: float) -> void:
	if not _open or not _hud.visible:
		return
	var state: Dictionary = _flow.snapshot()
	var player: Node = _flow.current_player()
	var boss: Node = _flow.current_boss()
	_label.text = "%s  %d/5  %.2fs" % [tr("UI_MODE_BOSS_RUSH"), int(state.stage_index) + 1, float(state.elapsed_frames) / 60.0]
	if player != null and boss != null:
		_health.text = "HP %d/%d  %s %d/%d" % [int(player.health.current_hp), int(player.health.max_hp), tr("BOSS_%s_NAME" % Catalog.BOSSES[int(state.stage_index)].to_upper()), int(boss.health.current_hp), int(boss.health.max_hp)]


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
