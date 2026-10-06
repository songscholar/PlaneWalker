extends Node2D

signal closed

const Flow := preload("res://scripts/modes/native_authored_challenge_flow.gd")
const PanelScript := preload("res://scripts/modes/authored_challenge_panel_view.gd")
const HudScene := preload("res://scenes/ui/modes/mode_combat_hud.tscn")
const HudProjector := preload("res://scripts/ui/style/mode_combat_hud_projector.gd")

var _flow: Node2D
var _registry: RefCounted
var _panel: Control
var _hud: Control
var _hud_projector := HudProjector.new()
var _hud_revision := 0
var _open := false
var _revision := 0
var _selected_id := "sword_timer"


func configure(registry: RefCounted, service: RefCounted, root_path: String) -> Dictionary:
	if _flow != null or not is_inside_tree():
		return _failure(&"AUTHORED_CONFIGURATION_INVALID")
	var flow := Flow.new()
	add_child(flow)
	var result: Dictionary = flow.configure(registry, service, root_path)
	if not result.ok:
		flow.queue_free()
		return result
	_flow = flow
	_registry = registry
	_flow.state_changed.connect(_project)
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
	_panel.set_selected.connect(select_set)
	_panel.close_requested.connect(func(_version: int): return_to_hub())
	for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
		runtime.apply_to_tree(_hud)
	return _success()


func open() -> Dictionary:
	if _flow == null or _open:
		return _failure(&"AUTHORED_COMMAND_INVALID")
	_open = true
	_project()
	return _success()


func is_open() -> bool:
	return _open


func runtime() -> Node2D:
	return _flow


func panel() -> Control:
	return _panel


func select_set(id: String) -> Dictionary:
	if not _open or not _flow.snapshot().active.is_empty() or _flow.has_pending_save():
		return _failure(&"AUTHORED_COMMAND_INVALID")
	for definition: Dictionary in _flow.preview().sets:
		if definition.id == id:
			_selected_id = id
			_project()
			return _success()
	return _failure(&"AUTHORED_COMMAND_INVALID")


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if event.is_action_pressed("pause"):
		if _flow.is_paused() and _flow.is_active() and _flow.snapshot().active.status == "ACTIVE" and not _flow.has_pending_save():
			_action("resume")
		elif not _panel.visible:
			_pause()
	return true


func return_to_hub() -> Dictionary:
	if not _open or _flow.has_pending_save():
		return _failure(&"AUTHORED_RETRY_INVALID")
	if _flow.is_active():
		var result: Dictionary = _flow.save_and_return()
		if not result.ok:
			_project()
		return result
	_finish_close()
	return _success()


func _finish_close() -> void:
	_open = false
	_panel.close_panel()
	_hud.visible = false
	closed.emit()


func _pause() -> void:
	if _open and _flow.is_active():
		_flow.set_paused(true)
		_project()


func _action(id: String) -> void:
	var result: Dictionary
	match id:
		"start": result = _flow.start(_selected_id)
		"continue": result = _flow.continue_session()
		"next": result = _flow.next_stage()
		"resume":
			_flow.set_paused(false)
			result = _success()
		"retry": result = _flow.retry_save()
		"reload": result = _flow.reload_saved_session()
		"native_retry": result = _flow.retry_native()
		"abandon": result = _flow.abandon()
		_: result = _failure(&"AUTHORED_COMMAND_INVALID")
	_project()
	if not result.ok:
		_panel.show_rejection("UI_" + str(result.code) if str(result.code).begins_with("AUTHORED_") else "UI_MODE_SAVE_PENDING")


func _project() -> void:
	if not _open:
		return
	var preview: Dictionary = _flow.preview()
	var playing: bool = preview.native_active and not preview.paused and not preview.pending and preview.active.status == "ACTIVE"
	_hud.visible = playing
	if playing:
		_panel.close_panel()
		get_viewport().gui_release_focus()
		return
	if not preview.active.is_empty():
		_selected_id = str(preview.active.set_id)
	_revision += 1
	var names := {}
	for definition: Dictionary in preview.sets:
		for id: String in definition.item_ids + [definition.blessing_id, definition.curse_id]:
			names[id] = _registry.get_content(StringName(id)).name_key
	_panel.render({"run_id": "authored-trial-menu", "revision": _revision, "selected_id": _selected_id, "preview": preview, "content_names": names})


func _process(_delta: float) -> void:
	if not _open or not _hud.visible:
		return
	var active: Dictionary = _flow.snapshot().active
	if active.is_empty():
		return
	var player: Node = _flow.current_player()
	var boss: Node = _flow.current_boss()
	if player == null:
		return
	var facts := {}
	if boss != null:
		var source: Dictionary = boss.get_boss_ui_snapshot()
		var id: String = _flow.preview().current_boss_id
		facts = {"boss_id": id, "name_key": "BOSS_%s_NAME" % id.to_upper(), "hp": source.current_hp, "max_hp": source.maximum_hp, "phase_index": source.boss_phase, "phase_total": source.phase_total}
	_hud_revision += 1
	var projected := _hud_projector.project("authored", {"run_id": str(active.run_id), "revision": _hud_revision, "stage_index": int(active.stage_index), "stage_total": 3, "elapsed_frames": int(active.elapsed_frames), "suspended": _flow.is_paused()}, player.get_player_ui_snapshot(), facts)
	if projected.ok:
		_hud.render(projected.context.view_state)


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
