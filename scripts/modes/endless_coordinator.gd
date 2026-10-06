extends Node2D

signal closed
const Flow := preload("res://scripts/modes/native_endless_flow.gd")
const PanelScript := preload("res://scripts/modes/endless_panel_view.gd")
const Request := preload("res://scripts/modes/boss_rush_catalog.gd")
const HudScene := preload("res://scenes/ui/modes/mode_combat_hud.tscn")
const HudProjector := preload("res://scripts/ui/style/mode_combat_hud_projector.gd")
var _flow: Node2D
var _panel: Control
var _hud: Control
var _hud_projector := HudProjector.new()
var _hud_revision := 0
var _request: Dictionary = {}
var _owner := ""
var _open := false
var _revision := 0


func configure(registry: RefCounted, service: RefCounted, root_path: String) -> Dictionary:
	if _flow != null or not is_inside_tree():
		return _failure(&"ENDLESS_CONFIGURATION_INVALID")
	var flow := Flow.new()
	add_child(flow)
	var result: Dictionary = flow.configure(registry, service, root_path)
	if not result.ok:
		flow.queue_free()
		return result
	_flow = flow
	_owner = str(service.local_record_storage_identity().profile_id)
	_flow.state_changed.connect(_project)
	_flow.closed.connect(_finish_close)
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "EndlessHudLayer"
	hud_layer.layer = 10
	add_child(hud_layer)
	_hud = HudScene.instantiate()
	hud_layer.add_child(_hud)
	_hud.pause_requested.connect(_pause)
	_hud.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 51
	add_child(layer)
	_panel = PanelScript.new()
	layer.add_child(_panel)
	_panel.action_requested.connect(_action)
	_panel.close_requested.connect(func(_view_revision: int): return_to_hub())
	for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
		runtime.apply_to_tree(_hud)
	return _success()


func open(request: Dictionary) -> Dictionary:
	if _flow == null or _open or not Request.valid_request(request):
		return _failure(&"ENDLESS_CONFIGURATION_INVALID")
	_request = request.duplicate(true)
	_open = true
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
		if _flow.is_paused() and _flow.snapshot().status == "ACTIVE" and not _flow.has_pending_save():
			_action("resume")
		else:
			_pause()
		return true
	if _flow.dungeon_flow() != null and not _panel.visible:
		_flow.dungeon_flow().handle_input(event)
	return true


func return_to_hub() -> Dictionary:
	if not _open or _flow.has_pending_save():
		return _failure(&"ENDLESS_RETRY_INVALID")
	if _flow.is_active():
		return _flow.save_and_return()
	_finish_close()
	return _success()


func _finish_close() -> void:
	_open = false
	_panel.close_panel()
	_hud.visible = false
	closed.emit()


func _pause() -> void:
	if _open and _flow.is_active() and _flow.snapshot().status == "ACTIVE":
		_flow.set_paused(true)
		_project()


func _action(id: String) -> void:
	var result: Dictionary
	match id:
		"start":
			_flow.close()
			result = _flow.start(_request)
		"continue":
			result = _flow.continue_session()
		"resume":
			_flow.set_paused(false)
			result = _success()
		"next":
			result = _flow.next_cycle()
		"retry":
			result = _flow.retry_save()
		"reload":
			result = _flow.reload_saved_session()
		_:
			result = _failure(&"ENDLESS_COMMAND_INVALID")
	_project()
	if not result.ok and _panel.visible:
		_panel.show_rejection("UI_MODE_STALE" if result.code == &"ENDLESS_STALE_PRIMARY" else "UI_MODE_SAVE_PENDING")


func _project() -> void:
	if not _open or _flow == null:
		return
	var state: Dictionary = _flow.snapshot()
	var playing: bool = _flow.is_active() and state.status == "ACTIVE" and not _flow.is_paused() and not _flow.has_pending_save()
	_hud.visible = playing
	if playing:
		_panel.close_panel()
		_process(0.0)
		return
	_revision += 1
	_panel.render({"run_id": "endless-menu", "revision": _revision, "owner": _owner, "request": _request, "session": state, "active": _flow.is_active(), "paused": _flow.is_paused(), "pending": _flow.has_pending_save(), "save_error": str(_flow.save_error())})
	_panel.back_button.text = tr("UI_MODE_RETURN")


func _process(_delta: float) -> void:
	if not _open or not _hud.visible:
		return
	var state: Dictionary = _flow.snapshot()
	var host: Node = _flow.runtime_host()
	var run: Dictionary = host.runtime_snapshot() if host != null else {}
	var dungeon_hud := host.get_node_or_null("HudLayer") as CanvasLayer if host != null else null
	if dungeon_hud != null:
		dungeon_hud.visible = false
	var player: Node = _flow.current_player()
	if player == null or run.is_empty():
		return
	var floor_index: int = int(run.get("current_floor_index", 0))
	var boss: Variant = host._boss_ui_snapshot()
	var facts: Dictionary = boss.duplicate(true) if boss is Dictionary else {}
	if not facts.is_empty():
		var id: String = Request.BOSSES[clampi(floor_index, 0, 4)]
		facts.boss_id = id
		facts.name_key = "BOSS_%s_NAME" % id.to_upper()
	_hud_revision += 1
	var projected := _hud_projector.project("endless", {"run_id": str(state.run_id), "revision": _hud_revision, "stage_index": int(state.cycle_index) * 5 + floor_index, "stage_total": (int(state.cycle_index) + 1) * 5, "elapsed_frames": int(state.elapsed_frames), "suspended": _flow.is_paused()}, player.get_player_ui_snapshot(), facts)
	if projected.ok:
		_hud.render(projected.context.view_state)


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
