extends Node2D

signal closed

const Flow := preload("res://scripts/modes/native_authored_challenge_flow.gd")
const PanelScript := preload("res://scripts/modes/authored_challenge_panel_view.gd")

var _flow: Node2D
var _registry: RefCounted
var _panel: Control
var _hud: Control
var _timer: Label
var _health: Label
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
	_hud = MarginContainer.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for side: String in ["left", "right", "top", "bottom"]:
		_hud.add_theme_constant_override("margin_" + side, 12)
	layer.add_child(_hud)
	var layout := VBoxContainer.new()
	_hud.add_child(layout)
	var row := HBoxContainer.new()
	layout.add_child(row)
	_timer = Label.new()
	_timer.name = "AuthoredTimer"
	_timer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer.add_theme_font_size_override("font_size", 12)
	row.add_child(_timer)
	var pause := Button.new()
	pause.text = tr("UI_MODE_PAUSE")
	pause.pressed.connect(_pause)
	row.add_child(pause)
	_health = Label.new()
	_health.name = "AuthoredHealth"
	_health.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_health.add_theme_font_size_override("font_size", 12)
	layout.add_child(_health)
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
	_timer.text = tr("UI_AUTHORED_STAGE_FMT") % [int(active.stage_index) + 1, float(active.elapsed_frames) / 60.0, int(active.damage_events)]
	if player != null and boss != null:
		_health.text = "HP %d/%d / %s %d/%d" % [int(player.health.current_hp), int(player.health.max_hp), tr("BOSS_%s_NAME" % str(_flow.preview().current_boss_id).to_upper()), int(boss.health.current_hp), int(boss.health.max_hp)]


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
