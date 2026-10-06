extends Node2D

signal closed

const Flow := preload("res://scripts/modes/native_daily_boss_flow.gd")
const PanelScript := preload("res://scripts/modes/daily_boss_panel_view.gd")
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


func configure(registry: RefCounted, service: RefCounted, root_path: String, clock: Callable = Callable()) -> Dictionary:
	if _flow != null or not is_inside_tree():
		return _failure(&"DAILY_CONFIGURATION_INVALID")
	var flow := Flow.new()
	add_child(flow)
	var result: Dictionary = flow.configure(registry, service, root_path, clock)
	if not result.ok:
		flow.queue_free()
		return result
	_flow = flow
	_registry = registry
	_flow.state_changed.connect(_project)
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
	_panel.close_requested.connect(func(_version: int): return_to_hub())
	for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
		runtime.apply_to_tree(_hud)
	return _success()


func open() -> Dictionary:
	if _flow == null or _open:
		return _failure(&"DAILY_COMMAND_INVALID")
	_open = true
	_project()
	return _success()


func is_open() -> bool:
	return _open


func runtime() -> Node2D:
	return _flow


func panel() -> Control:
	return _panel


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if event.is_action_pressed("pause"):
		if _flow.is_paused() and _flow.is_active() and not _flow.has_pending_save():
			_action("resume")
		elif not _panel.visible:
			_pause()
	return true


func return_to_hub() -> Dictionary:
	if not _open or _flow.has_pending_save():
		return _failure(&"DAILY_RETRY_INVALID")
	if not _flow.snapshot().active.is_empty():
		var result: Dictionary = _flow.abandon()
		if not result.ok:
			_project()
			return result
	_open = false
	_panel.close_panel()
	_hud.visible = false
	closed.emit()
	return _success()


func _pause() -> void:
	if _open and _flow.is_active():
		_flow.set_paused(true)
		_project()


func _action(id: String) -> void:
	var result: Dictionary
	match id:
		"start":
			result = _flow.start()
		"resume":
			_flow.set_paused(false)
			result = _success()
		"retry":
			result = _flow.retry_save()
		"reload":
			result = _flow.reload_saved_session()
		"native_retry":
			result = _flow.retry_native()
		"abandon":
			result = _flow.abandon()
		_:
			result = _flow.purchase_reward(id.substr(9)) if id.begins_with("exchange:") else _failure(&"DAILY_COMMAND_INVALID")
	_project()
	if not result.ok:
		_panel.show_rejection("UI_" + str(result.code) if str(result.code).begins_with("DAILY_") else "UI_MODE_SAVE_PENDING")


func _project() -> void:
	if not _open:
		return
	var preview: Dictionary = _flow.preview()
	var playing: bool = preview.native_active and not preview.paused and not preview.pending
	_hud.visible = playing
	if playing:
		_panel.close_panel()
		get_viewport().gui_release_focus()
		return
	_revision += 1
	var condition_keys := {}
	var names := {}
	var definition: Dictionary = preview.definition
	if not definition.is_empty():
		for id: String in definition.condition_ids:
			condition_keys[id] = _flow.condition_key(id)
		for id: String in definition.item_ids + [definition.blessing_id, definition.curse_id]:
			names[id] = _registry.get_content(StringName(id)).name_key
	_panel.render({"run_id": "daily-boss-menu", "revision": _revision, "preview": preview, "condition_keys": condition_keys, "content_names": names})


func _process(_delta: float) -> void:
	if not _open:
		return
	var preview: Dictionary = _flow.preview()
	if _panel.visible:
		_panel.update_countdown(int(preview.remaining_seconds))
	if not _hud.visible:
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
		var id: String = active.definition.boss_id
		facts = {"boss_id": id, "name_key": "BOSS_%s_NAME" % id.to_upper(), "hp": source.current_hp, "max_hp": source.maximum_hp, "phase_index": source.boss_phase, "phase_total": source.phase_total}
	_hud_revision += 1
	var projected := _hud_projector.project("daily", {"run_id": str(active.run_id), "revision": _hud_revision, "stage_index": 0, "stage_total": 1, "elapsed_frames": int(active.elapsed_frames), "suspended": _flow.is_paused()}, player.get_player_ui_snapshot(), facts)
	if projected.ok:
		_hud.render(projected.context.view_state)


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
