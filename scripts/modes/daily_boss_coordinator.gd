extends Node2D

signal closed

const Flow := preload("res://scripts/modes/native_daily_boss_flow.gd")
const PanelScript := preload("res://scripts/modes/daily_boss_panel_view.gd")

var _flow: Node2D
var _registry: RefCounted
var _panel: Control
var _hud: Control
var _timer: Label
var _health: Label
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
	_timer.name = "DailyTimer"
	_timer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer.add_theme_font_size_override("font_size", 12)
	row.add_child(_timer)
	var pause := Button.new()
	pause.text = tr("UI_MODE_PAUSE")
	pause.pressed.connect(_pause)
	row.add_child(pause)
	_health = Label.new()
	_health.name = "DailyHealth"
	_health.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_health.add_theme_font_size_override("font_size", 12)
	layout.add_child(_health)
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
	_timer.text = "%s / %d / %.2fs" % [tr("UI_DAILY_TITLE"), int(active.attempt), float(active.elapsed_frames) / 60.0]
	if player != null and boss != null:
		_health.text = "HP %d/%d / %s %d/%d" % [int(player.health.current_hp), int(player.health.max_hp), tr("BOSS_%s_NAME" % str(active.definition.boss_id).to_upper()), int(boss.health.current_hp), int(boss.health.max_hp)]


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
