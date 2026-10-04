class_name TrainingFlowCoordinator
extends Node2D

signal closed

const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Flow := preload("res://scripts/training/native_training_flow.gd")
const Arena := preload("res://scripts/training/training_arena.gd")
const PanelScript := preload("res://scripts/training/training_panel_view.gd")

var _registry: RefCounted
var _service: RefCounted
var _flow: Node2D
var _arena: Node2D
var _panel: Control
var _camera: Camera2D
var _layer: CanvasLayer
var _request: Dictionary = {}
var _active := false
var _busy := false
var _practicing := false
var _rejection: StringName = &""


func configure(registry: RefCounted, service: RefCounted) -> Dictionary:
	if _registry != null or not is_inside_tree():
		return Candidate.failure(&"TRAINING_CONFIGURATION_INVALID")
	var flow := Flow.new()
	add_child(flow)
	var configured := flow.configure(registry, service, Callable(self, "_create_boss"))
	if not configured.ok:
		remove_child(flow)
		flow.queue_free()
		return configured
	_registry = registry
	_service = service
	_flow = flow
	_flow.observation_rejected.connect(_on_rejection)
	_flow.observations_saved.connect(_on_observations_saved)
	_arena = Arena.new()
	_arena.name = "TrainingArena"
	add_child(_arena)
	_arena.visible = false
	_camera = Camera2D.new()
	_camera.name = "TrainingCamera"
	_camera.position = Vector2(320, 180)
	_camera.enabled = false
	add_child(_camera)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_panel = PanelScript.new()
	_layer.add_child(_panel)
	if not _panel.configure(registry):
		return Candidate.failure(&"TRAINING_CONFIGURATION_INVALID")
	_panel.selection_requested.connect(_select)
	_panel.play_requested.connect(_toggle_practice)
	_panel.reset_requested.connect(_reset)
	_panel.back_requested.connect(close)
	_panel.visible = false
	return Candidate.success()


func open(task_id: String = "") -> Dictionary:
	if get_tree().paused:
		return Candidate.failure(&"TRAINING_PAUSED")
	if _registry == null or _active or _busy:
		return Candidate.failure(&"TRAINING_CONFIGURATION_INVALID")
	var request := {"task_id": "T-01" if task_id.is_empty() else task_id, "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var result: Dictionary = _flow.start(request)
	if not result.ok:
		return result
	_request = request
	_rejection = &""
	_active = true
	_arena.visible = true
	_camera.enabled = true
	_camera.make_current()
	_panel.visible = true
	_panel.select_request(_request)
	_place_attempt()
	_set_practicing(false)
	FocusCoordinator.open_scope(_panel, _panel.selector("task_id"))
	_project()
	return Candidate.success()


func close() -> Dictionary:
	if not _active:
		return Candidate.success()
	if get_tree().paused:
		return Candidate.failure(&"TRAINING_PAUSED")
	if _busy:
		return Candidate.failure(&"BUSY")
	_busy = true
	var drained: Dictionary = _flow.prepare_retirement()
	if not drained.ok:
		_busy = false
		_on_rejection(drained.code)
		return drained
	_set_practicing(false)
	_flow.close()
	_arena.retire_attempt()
	_finish_close()
	return Candidate.success()


func _finish_close() -> void:
	_camera.enabled = false
	_panel.visible = false
	_arena.visible = false
	FocusCoordinator.close_scope(_panel)
	_request.clear()
	_rejection = &""
	_active = false
	_busy = false
	closed.emit()


func is_training_active() -> bool:
	return _active


func training_player() -> Node2D:
	return _flow.training_player() if _flow != null else null


func training_panel() -> Control:
	return _panel


func training_arena() -> Node2D:
	return _arena


func _select(request: Dictionary) -> void:
	if get_tree().paused:
		_panel.select_request(_request)
		return
	if not _active or _busy:
		return
	_busy = true
	var drained: Dictionary = _flow.prepare_retirement()
	if not drained.ok:
		_panel.select_request(_request)
		_busy = false
		_on_rejection(drained.code)
		return
	var previous := _request.duplicate(true)
	_set_practicing(false)
	_flow.close()
	_arena.retire_attempt()
	var started: Dictionary = _flow.start(request)
	if not started.ok:
		started = _flow.start(previous)
		request = previous
		_rejection = &"TRAINING_CONFIGURATION_INVALID"
	else:
		_rejection = &""
	if started.ok:
		_request = request.duplicate(true)
		_panel.select_request(_request)
		_place_attempt()
	else:
		_finish_close()
		return
	_busy = false
	_project()


func _reset() -> void:
	if not _active or _busy or get_tree().paused:
		return
	_busy = true
	var result: Dictionary = _flow.reset_attempt()
	if result.ok:
		_rejection = &""
		_place_attempt()
		_set_practicing(false)
	else:
		_on_rejection(result.code)
	_busy = false
	_project()


func _place_attempt() -> void:
	var player := training_player()
	player.global_position = global_position + Arena.PLAYER_ENTRY
	if _request.task_id != "T-05":
		_arena.begin_attempt(player, _request)


func _create_boss(player: Node2D, request: Dictionary) -> Node2D:
	player.global_position = global_position + Arena.PLAYER_ENTRY
	return _arena.begin_attempt(player, request)


func _toggle_practice() -> void:
	if _active and not _busy:
		_set_practicing(not _practicing)
		if _practicing:
			get_viewport().gui_release_focus()
		else:
			_panel.play_button().grab_focus()


func _set_practicing(value: bool) -> void:
	_practicing = value
	var player := training_player()
	if is_instance_valid(player):
		player.set_physics_process(value)
	var target: Node2D = _arena.native_target() if _arena != null else null
	if is_instance_valid(target):
		target.set_physics_process(value)
	if is_instance_valid(_panel):
		_panel.set_practicing(value)


func _project() -> void:
	var player := training_player()
	if not _active or not is_instance_valid(player):
		return
	var energy: Dictionary = player.time_manager.resource_state(&"time_energy")
	_panel.project(_service.tutorial_progress_view(), _request, Vector2(player.health.current_hp, player.health.max_hp), Vector2(float(energy.get("current", 0.0)), float(energy.get("maximum", 0.0))), _rejection)


func _on_rejection(code: StringName) -> void:
	_rejection = code
	_project()


func _on_observations_saved() -> void:
	_rejection = &""
	_project()


func _process(_delta: float) -> void:
	if _active:
		_project()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not event.is_action_pressed("ui_cancel"):
		return
	if _practicing:
		_set_practicing(false)
		_panel.play_button().grab_focus()
	else:
		close()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _flow != null:
		_flow.close()
	if _arena != null:
		_arena.retire_attempt()
	if _panel != null:
		FocusCoordinator.close_scope(_panel)
