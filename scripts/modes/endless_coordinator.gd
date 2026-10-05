extends Node2D

signal closed
const Flow := preload("res://scripts/modes/native_endless_flow.gd")
const PanelScript := preload("res://scripts/modes/endless_panel_view.gd")
const Request := preload("res://scripts/modes/boss_rush_catalog.gd")
var _flow: Node2D
var _panel: Control
var _hud: Control
var _label: Label
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
	var layer := CanvasLayer.new()
	layer.layer = 51
	add_child(layer)
	_hud = MarginContainer.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for side: String in ["left", "right", "top", "bottom"]:
		_hud.add_theme_constant_override("margin_" + side, 10)
	layer.add_child(_hud)
	var row := HBoxContainer.new()
	_hud.add_child(row)
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 11)
	row.add_child(_label)
	var pause := Button.new()
	pause.name = "EndlessPause"
	pause.text = tr("UI_MODE_PAUSE")
	pause.pressed.connect(_pause)
	row.add_child(pause)
	_hud.visible = false
	_panel = PanelScript.new()
	layer.add_child(_panel)
	_panel.action_requested.connect(_action)
	_panel.close_requested.connect(func(_view_revision: int): return_to_hub())
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
	_label.text = "%s  %d  %.2fs" % [tr("UI_MODE_ENDLESS"), int(state.cycle_index) * 5 + int(run.get("current_floor_index", 0)) + 1, float(state.elapsed_frames) / 60.0]


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
