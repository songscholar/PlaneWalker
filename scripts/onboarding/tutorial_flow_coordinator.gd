class_name TutorialFlowCoordinator
extends Node

signal training_requested(task_id: StringName, expected_revision: int)
signal observation_rejected(code: StringName)

const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Host := preload("res://scripts/application/run_runtime_host.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const Remap := preload("res://scripts/input/input_remap_service.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Model := preload("res://scripts/onboarding/tutorial_view_model.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const PanelScene := preload("res://scenes/ui/tutorial_panel.tscn")
const HintScene := preload("res://scenes/ui/tutorial_hint_presenter.tscn")
const ACTIVE_PHASES := [Phase.Value.ROOM_ACTIVE, Phase.Value.COMBAT_ACTIVE, Phase.Value.BOSS_ACTIVE]

var _service: RefCounted
var _host: Node
var _player: Node
var _input: RefCounted
var _model: RefCounted
var _panel: Control
var _hint: Control
var _adapter: RefCounted
var _run: RefCounted
var _launch: Dictionary = {}
var _generation := 0
var _binding_epoch := 0
var _command_sequence := 0
var _profile_id := ""
var _family := "keyboard_mouse"
var _processing := false
var _recovery_pending := false
var _pause_owned := false
var _pause_run: RefCounted
var _pause_player_id := 0
var _pause_generation := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "TutorialLayer"
	layer.layer = 42
	add_child(layer)
	_hint = HintScene.instantiate()
	layer.add_child(_hint)
	_hint.process_mode = Node.PROCESS_MODE_PAUSABLE
	_panel = PanelScene.instantiate()
	layer.add_child(_panel)
	_panel.close_requested.connect(_on_close)
	_panel.lesson_skip_requested.connect(_on_skip)
	_panel.hint_suppression_requested.connect(_on_suppress)
	_panel.training_requested.connect(_on_training)
	_panel.guided_mode_requested.connect(_on_guided)


func configure(registry: RefCounted, service: RefCounted, host: Node, player: Node, remap: RefCounted) -> Dictionary:
	if _service != null:
		return Candidate.success() if _service == service and _host == host and _player == player and _input == remap else Candidate.failure(&"ALREADY_CONFIGURED")
	if not is_node_ready() or not registry is Registry or not service is Service or not host is Host or not player is Player or not remap is Remap or not is_instance_valid(host) or not is_instance_valid(player) or host.get("_player") != player or host.content_registry() != registry:
		return Candidate.failure(&"TUTORIAL_FLOW_CONFIGURATION_INVALID")
	var catalog := Factory.from_registry(registry)
	if not catalog.ok or service.snapshot().get("catalog_fingerprint") != catalog.context.catalog.fingerprint():
		return Candidate.failure(&"TUTORIAL_FLOW_CONFIGURATION_INVALID")
	var entries: Array = registry.get_catalog_entries(&"tutorial_definition", &"LAUNCH")
	var model := Model.new()
	var projected := model.configure(entries, catalog.context.catalog, remap)
	if not projected.ok:
		return projected
	var enabled: Dictionary = service.enable_tutorial(entries)
	if not enabled.ok:
		return enabled
	_service = service
	_host = host
	_player = player
	_input = remap
	_model = model
	_profile_id = str(service.get("_profile_id"))
	_input.bindings_changed.connect(_on_bindings_changed)
	return Candidate.success()


func bind_active_run(player: Node = null) -> Dictionary:
	if _service == null or _processing:
		return Candidate.failure(&"NOT_CONFIGURED" if _service == null else &"BUSY")
	if _recovery_pending:
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING")
	if player != null:
		if not player is Player or not is_instance_valid(_host) or _host.get("_player") != player:
			return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
		_player = player
	retire_active_run()
	if not is_instance_valid(_host) or not is_instance_valid(_player) or _host.get("_player") != _player:
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	var run: RefCounted = _host.native_run_state()
	var bound: Dictionary = _service.bind_tutorial_run(run, _player)
	if not bound.ok:
		return bound
	_accept_binding(run, bound.context.adapter)
	return Candidate.success()


func recover_active_run() -> Dictionary:
	if _service == null or _processing or not _participants_current():
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	_hint.clear_context()
	var epoch := _binding_epoch
	var restored: Dictionary = _service.restore_tutorial_run()
	if not restored.ok:
		return restored
	if epoch != _binding_epoch or not _participants_current():
		return Candidate.failure(&"TUTORIAL_CONTEXT_CHANGED")
	_accept_binding(_run, restored.context.adapter)
	return Candidate.success()


func retire_active_run() -> void:
	_binding_epoch += 1
	if _hint != null:
		_hint.clear_context()
	if _service != null and _adapter != null and _service.get("_tutorial_adapter") == _adapter:
		_service.retire_tutorial_run()
	_adapter = null
	_run = null
	_launch.clear()
	_generation = 0
	_recovery_pending = false


func review_panel() -> Control:
	return _panel


func hint_presenter() -> Control:
	return _hint


func open_review(family: String = "") -> Dictionary:
	if _service == null or family not in ["", "keyboard_mouse", "controller"]:
		return Candidate.failure(&"TUTORIAL_VIEW_INVALID")
	if not family.is_empty():
		_family = family
	if not _panel.visible and not get_tree().paused:
		var state: Dictionary = _host.runtime_snapshot()
		if not _service.snapshot().active_launch_receipt.is_empty() and not state.get("suspended", false) and not Phase.is_terminal(int(state.get("phase", -1))):
			var paused = _host.pause_run()
			if not paused.ok:
				return Candidate.failure(paused.code)
			_pause_owned = true
			_pause_run = _host.native_run_state()
			_pause_player_id = _player.get_instance_id()
			_pause_generation = _player.owner_character_generation()
			get_tree().paused = true
	_hint.clear_context()
	var refreshed := _refresh_review()
	if not refreshed.ok:
		close()
	return refreshed


func close() -> void:
	_panel.close_panel()
	if _pause_owned and is_instance_valid(_host) and is_instance_valid(_player) and _host.native_run_state() == _pause_run and _host.get("_player") == _player and _player.get_instance_id() == _pause_player_id and _player.owner_character_generation() == _pause_generation and not Phase.is_terminal(int(_host.runtime_snapshot().get("phase", -1))):
		var resumed = _host.resume_run()
		if resumed.ok:
			get_tree().paused = false
	_pause_owned = false
	_pause_run = null


func handle_input(event: InputEvent) -> bool:
	if _service == null or event.is_echo():
		return false
	var cancel: bool = event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if _panel.visible and cancel:
		close()
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		if _panel.visible:
			close()
			return true
		return open_review("keyboard_mouse").ok
	if _panel.visible and event is InputEventJoypadButton and _family != "controller":
		_family = "controller"
		_refresh_review()
	return false


func process_pending_observations() -> Dictionary:
	if _processing:
		return Candidate.failure(&"BUSY")
	if _adapter == null:
		return Candidate.success({"consumed": false})
	if _recovery_pending and _participants_current():
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING")
	if not _binding_current():
		retire_active_run()
		return Candidate.failure(&"TUTORIAL_CONTEXT_CHANGED")
	if not _observation_active() or _adapter.pending_observations().is_empty():
		return Candidate.success({"consumed": false})
	var epoch := _binding_epoch
	var adapter := _adapter
	_processing = true
	var result: Dictionary = _service.observe_tutorial(adapter, int(_service.snapshot().revision))
	_processing = false
	if epoch != _binding_epoch or adapter != _adapter or not _participants_current():
		retire_active_run()
		return Candidate.failure(&"TUTORIAL_CONTEXT_CHANGED")
	if not result.ok:
		if result.code == &"NATIVE_PUBLICATION_PENDING":
			_recovery_pending = true
			_hint.clear_context()
		elif not _binding_current():
			retire_active_run()
		observation_rejected.emit(result.code)
		return result
	if not _binding_current():
		retire_active_run()
		return Candidate.failure(&"TUTORIAL_CONTEXT_CHANGED")
	if _observation_active():
		for authored: Dictionary in result.context.get("hints", []):
			var projected: Dictionary = _model.project_hint(authored, int(_service.snapshot().revision), str(_launch.run_id), _family, _first_ability())
			if projected.ok:
				_hint.render_saved_hint(projected.context.view_state)
	return Candidate.success({"consumed": true})


func _process(_delta: float) -> void:
	process_pending_observations()
	if _hint != null:
		_hint.set_physics_process(_adapter != null and _binding_current() and _observation_active())


func _accept_binding(run: RefCounted, adapter: RefCounted) -> void:
	_binding_epoch += 1
	_run = run
	_adapter = adapter
	_launch = _service.snapshot().active_launch_receipt.duplicate(true)
	_generation = _player.owner_character_generation()
	_recovery_pending = false


func _participants_current() -> bool:
	return _run != null and is_instance_valid(_host) and is_instance_valid(_player) and _host.is_inside_tree() and _player.is_inside_tree() and _host.get("_player") == _player and _host.native_run_state() == _run and _player.owner_character_generation() == _generation and str(_player.current_run_id()) == str(_launch.get("run_id", "")) and _run.run_id == _launch.get("run_id") and _service.snapshot().active_launch_receipt == _launch


func _binding_current() -> bool:
	return _adapter != null and _participants_current() and _adapter.is_live_binding() and _service.get("_tutorial_adapter") == _adapter


func _observation_active() -> bool:
	return not get_tree().paused and not _panel.visible and not _run.suspended and _run.phase in ACTIVE_PHASES and not _player.health.dead


func _first_ability() -> String:
	var launch: Dictionary = _service.snapshot().active_launch_receipt
	return str(launch.time_abilities[0]) if not launch.is_empty() else "stop"


func _refresh_review() -> Dictionary:
	var projected: Dictionary = _model.project(_service.snapshot(), _profile_id, _family, _first_ability(), false, false)
	if not projected.ok:
		return projected
	var rendered = _panel.render(projected.context.view_state)
	return Candidate.success() if rendered.ok else Candidate.failure(rendered.code)


func _execute_command(command: Dictionary, revision: int) -> void:
	if not _panel.visible or int(_panel.view_state().revision) != revision or _processing:
		return
	_command_sequence += 1
	command.command_id = "tutorial-ui-%s-%s-%s" % [get_instance_id(), revision, _command_sequence]
	_processing = true
	var result: Dictionary = _service.execute_tutorial(command, revision)
	_processing = false
	if result.ok:
		if _service.snapshot().tutorial_state.suppressed:
			_hint.clear_context()
		_refresh_review()
	else:
		_panel.show_rejection("UI_TUTORIAL_RETRY")


func _on_skip(id: StringName, revision: int) -> void:
	_execute_command({"kind": "tutorial_skip", "lesson_id": str(id)}, revision)


func _on_suppress(suppressed: bool, revision: int) -> void:
	_execute_command({"kind": "tutorial_suppress", "suppressed": suppressed}, revision)


func _on_training(id: StringName, revision: int) -> void:
	if _panel.visible and _panel.view_state().training_available and _service.snapshot().revision == revision:
		training_requested.emit(id, revision)


func _on_guided(_enabled: bool, _revision: int) -> void:
	_panel.show_rejection("UI_TUTORIAL_RETRY")


func _on_close(_revision: int) -> void:
	close()


func _on_bindings_changed(_action: StringName) -> void:
	if _panel.visible:
		_refresh_review()
	_hint.clear_context()


func _exit_tree() -> void:
	if _input != null and _input.bindings_changed.is_connected(_on_bindings_changed):
		_input.bindings_changed.disconnect(_on_bindings_changed)
	retire_active_run()
