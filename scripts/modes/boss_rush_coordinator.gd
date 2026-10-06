extends Node2D

signal closed

const Flow := preload("res://scripts/modes/native_boss_rush_flow.gd")
const PanelScript := preload("res://scripts/modes/boss_rush_panel_view.gd")
const Catalog := preload("res://scripts/modes/boss_rush_catalog.gd")
const HudScene := preload("res://scenes/ui/modes/mode_combat_hud.tscn")
const HudProjector := preload("res://scripts/ui/style/mode_combat_hud_projector.gd")

var _flow: Node2D
var _panel: Control
var _hud: Control
var _hud_projector := HudProjector.new()
var _hud_revision := 0
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
	_hud = HudScene.instantiate()
	layer.add_child(_hud)
	_hud.pause_requested.connect(_pause)
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
	if player == null:
		return
	var facts := {}
	if boss != null:
		var source: Dictionary = boss.get_boss_ui_snapshot()
		var id: String = Catalog.BOSSES[int(state.stage_index)]
		facts = {"boss_id": id, "name_key": "BOSS_%s_NAME" % id.to_upper(), "hp": source.current_hp, "max_hp": source.maximum_hp, "phase_index": source.boss_phase, "phase_total": source.phase_total}
	_hud_revision += 1
	var projected := _hud_projector.project("boss_rush", {"run_id": str(state.run_id), "revision": _hud_revision, "stage_index": int(state.stage_index), "stage_total": 5, "elapsed_frames": int(state.elapsed_frames), "suspended": _paused}, player.get_player_ui_snapshot(), facts)
	if projected.ok:
		_hud.render(projected.context.view_state)


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
