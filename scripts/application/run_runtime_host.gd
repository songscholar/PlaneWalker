class_name RunRuntimeHost
extends Node

const ChoicePanelScene := preload("res://scenes/ui/choice_panel_v2.tscn")
const CombatHudScene := preload("res://scenes/ui/combat_hud_v2.tscn")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const RunViewStateProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")

const HUD_RENDER_INTERVAL := 0.1

@export var room_controller_path: NodePath
@export_file("*.json") var manifest_path: String = "res://data/content_packs/base/pack.json"

var _active: bool = false
var _facade: RefCounted
var _room_runtime: Node
var _room_controller: Node
var _player: Node
var _projector: RefCounted
var _hud_layer: CanvasLayer
var _choice_layer: CanvasLayer
var _choice_panel: Control
var _active_run_id: String = ""
var _ended_run_id: String = ""
var _run_serial: int = 0
var _hud_render_accumulator: float = 0.0
var _selection_safety_active: bool = false
var _player_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_room_controller = get_node_or_null(room_controller_path)
	if _room_controller == null:
		return
	_player = _room_controller.get_node_or_null("Player")
	if _player == null:
		return
	_facade = _boot_facade()
	if _facade == null:
		return
	_create_hud_layer()
	_create_choice_layer()
	_active = true


func _process(delta: float) -> void:
	if not _active or _facade == null or _active_run_id.is_empty():
		return
	_facade.call("advance_time", maxf(0.0, delta))
	_hud_render_accumulator += maxf(0.0, delta)
	if _hud_render_accumulator < HUD_RENDER_INTERVAL:
		return
	_hud_render_accumulator = fmod(_hud_render_accumulator, HUD_RENDER_INTERVAL)
	_render_live_hud()


func start_run(config: Dictionary) -> Variant:
	if not _active or _room_controller == null:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "start_run"})
	var normalized := RunConfigScript.normalized(config)
	var validation = RunConfigScript.validate(normalized)
	if not validation.ok:
		return validation
	var next_facade := _facade if _active_run_id.is_empty() else _boot_facade()
	if next_facade == null:
		return CommandResultScript.failure(&"CONTENT_NOT_AVAILABLE", _revision())
	_run_serial += 1
	var run_id := "run-%d-%d" % [int(normalized.get("seed", 0)), _run_serial]
	var started = next_facade.start_run(normalized, run_id)
	if not started.ok:
		return started

	_dispose_room_runtime()
	_facade = next_facade
	_active_run_id = run_id
	_ended_run_id = ""
	_hud_render_accumulator = 0.0
	_set_selection_safety(false)
	if _choice_panel != null:
		_choice_panel.close_panel()
	var start_snapshot := runtime_snapshot()
	EventBus.run_started.emit(run_id, start_snapshot.duplicate(true))

	var runner_value: Variant = _room_controller.call("encounter_runner")
	if not runner_value is Node:
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"has_runner": false})
	var runtime_value: Variant = _facade.call("create_room_runtime", runner_value)
	if not runtime_value is Node:
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"has_runtime": false})
	_room_runtime = runtime_value as Node
	_room_runtime.name = "RoomRuntime"
	add_child(_room_runtime)
	var configured := bool(_room_controller.call(
		"configure_authored_runtime",
		_room_runtime,
		_facade.call("encounter_catalog")
	))
	if not configured:
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"configured": false})
	_connect_room_runtime()
	var entered: Variant = _room_runtime.call("begin_current_room")
	if entered == null or not bool(entered.get("ok")):
		return entered
	return entered


func pause_run() -> Variant:
	if _facade == null:
		return CommandResultScript.failure(&"INVALID_PHASE", 0)
	return _facade.call("pause_run")


func resume_run() -> Variant:
	if _facade == null:
		return CommandResultScript.failure(&"INVALID_PHASE", 0)
	return _facade.call("resume_run")


func runtime_snapshot() -> Dictionary:
	if _facade == null:
		return {}
	return (_facade.call("snapshot") as Dictionary).duplicate(true)


func room_plan() -> Array[Dictionary]:
	if _facade == null:
		return []
	return _facade.call("room_plan")


func encounter_catalog() -> RefCounted:
	if _facade == null:
		return null
	return _facade.call("encounter_catalog")


func choice_panel() -> Control:
	return _choice_panel


func _boot_facade() -> RefCounted:
	var facade := RunRuntimeFacadeScript.new()
	var booted = facade.boot(manifest_path)
	return facade if booted.ok else null


func _create_hud_layer() -> void:
	var instance := CombatHudScene.instantiate()
	if not instance is CanvasLayer or not instance.has_method("render"):
		instance.free()
		return
	_projector = RunViewStateProjectorScript.new()
	_hud_layer = instance as CanvasLayer
	_hud_layer.name = "HudLayer"
	_hud_layer.layer = 10
	add_child(_hud_layer)


func _create_choice_layer() -> void:
	_choice_layer = CanvasLayer.new()
	_choice_layer.name = "ChoiceLayer"
	_choice_layer.layer = 20
	add_child(_choice_layer)
	_choice_panel = ChoicePanelScene.instantiate() as Control
	_choice_layer.add_child(_choice_panel)
	_choice_panel.option_chosen.connect(_on_option_chosen)


func _connect_room_runtime() -> void:
	if not _room_runtime.room_started.is_connected(_on_room_started):
		_room_runtime.room_started.connect(_on_room_started)
	if not _room_runtime.room_cleared.is_connected(_on_room_cleared):
		_room_runtime.room_cleared.connect(_on_room_cleared)
	if not _room_runtime.terminal_committed.is_connected(_on_terminal_committed):
		_room_runtime.terminal_committed.connect(_on_terminal_committed)
	if not _room_runtime.runtime_failed.is_connected(_on_runtime_failed):
		_room_runtime.runtime_failed.connect(_on_runtime_failed)


func _dispose_room_runtime() -> void:
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		_room_runtime = null
		return
	if _room_runtime.room_started.is_connected(_on_room_started):
		_room_runtime.room_started.disconnect(_on_room_started)
	if _room_runtime.room_cleared.is_connected(_on_room_cleared):
		_room_runtime.room_cleared.disconnect(_on_room_cleared)
	if _room_runtime.terminal_committed.is_connected(_on_terminal_committed):
		_room_runtime.terminal_committed.disconnect(_on_terminal_committed)
	if _room_runtime.runtime_failed.is_connected(_on_runtime_failed):
		_room_runtime.runtime_failed.disconnect(_on_runtime_failed)
	_room_runtime.queue_free()
	_room_runtime = null


func _on_room_started(active_room_id: StringName, revision: int) -> void:
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if run_id.is_empty() or run_id != _active_run_id:
		return
	EventBus.room_started.emit(run_id, active_room_id, revision)


func _on_room_cleared(active_room_id: StringName, revision: int) -> void:
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if run_id.is_empty() or run_id != _active_run_id:
		return
	EventBus.room_cleared.emit(run_id, active_room_id, revision)
	match int(state.get("phase", -1)):
		RunPhaseScript.Value.SELECTION_ACTIVE:
			_open_offer(state.get("open_offer", {}))


func _on_terminal_committed(context: Dictionary, _revision: int) -> void:
	_publish_terminal_result(context)


func _on_runtime_failed(context: Dictionary) -> void:
	if _choice_panel != null:
		_choice_panel.close_panel()
	_set_selection_safety(false)
	_publish_terminal_result(context)


func _open_offer(offer_value: Variant) -> void:
	if not offer_value is Dictionary or (offer_value as Dictionary).is_empty() or _choice_panel == null:
		return
	_set_selection_safety(true)
	var rendered = _choice_panel.render((offer_value as Dictionary).duplicate(true))
	if not rendered.ok:
		_set_selection_safety(false)


func _on_option_chosen(offer_id: String, option_id: String, revision: int) -> void:
	if _facade == null or _choice_panel == null or _player == null or not _player.has_method("apply_reward"):
		return
	var result = _facade.call("submit_selection", offer_id, option_id, revision)
	if not result.ok:
		_choice_panel.show_rejection(_rejection_message_key(result))
		return
	var definition: Dictionary = result.context.get("definition", {}).duplicate(true)
	var selection_revision := int(result.new_revision)
	var selection_state := runtime_snapshot()
	var run_id := str(selection_state.get("run_id", ""))
	if str(definition.get("id", "")) != "decline_contract":
		_player.call("apply_reward", definition)
	if not run_id.is_empty() and run_id == _active_run_id:
		EventBus.reward_selected.emit(run_id, definition.duplicate(true), selection_revision)
	var transitioned = _facade.call("complete_transition")
	if not transitioned.ok:
		_choice_panel.show_rejection(_rejection_message_key(transitioned))
		return
	_choice_panel.close_panel()
	_set_selection_safety(false)
	if _room_runtime != null and is_instance_valid(_room_runtime):
		_room_runtime.call_deferred("begin_current_room")


func _publish_terminal_result(authoritative_result: Dictionary) -> void:
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if run_id.is_empty() or run_id != _active_run_id or _ended_run_id == run_id:
		return
	var phase := int(state.get("phase", -1))
	if not RunPhaseScript.is_terminal(phase):
		return
	_ended_run_id = run_id
	var result := _terminal_result(state, authoritative_result)
	EventBus.run_ended.emit(run_id, result.duplicate(true), int(state.get("revision", 0)))


func _terminal_result(state: Dictionary, authoritative_result: Dictionary) -> Dictionary:
	var result_value: Variant = state.get("result", {})
	var result := (result_value as Dictionary).duplicate(true) if result_value is Dictionary else {}
	if result.is_empty():
		result = authoritative_result.duplicate(true)

	var phase := int(state.get("phase", -1))
	var outcome := str(result.get("result", ""))
	if phase == RunPhaseScript.Value.VICTORY or outcome == "victory":
		outcome = "floor_cleared"
	elif outcome.is_empty():
		outcome = "death" if phase == RunPhaseScript.Value.DEFEAT else "runtime_error"

	var current_room := int(state.get("current_room", 0))
	var rooms_cleared := current_room if phase == RunPhaseScript.Value.VICTORY else maxi(0, current_room - 1)
	var stats_value: Variant = state.get("stats", {})
	var stats: Dictionary = (stats_value as Dictionary).duplicate(true) if stats_value is Dictionary else {}
	var build_value: Variant = state.get("build", {})
	var build: Dictionary = (build_value as Dictionary).duplicate(true) if build_value is Dictionary else {}
	var categorized := _categorized_history(build)

	result["result"] = outcome
	result["floor"] = int(state.get("current_floor", 1))
	result["rooms_cleared"] = int(result.get("rooms_cleared", rooms_cleared))
	result["current_room"] = int(result.get("current_room", current_room))
	result["run_time"] = float(state.get("run_time_ms", 0)) / 1000.0
	result["kills"] = int(result.get("kills", stats.get("kills", 0)))
	result["stats"] = stats
	result["rewards"] = categorized["items"]
	result["blessings"] = categorized["blessings"]
	result["talent_choices"] = categorized["talents"]
	result["curses"] = categorized["curses"]
	result["run_id"] = str(state.get("run_id", ""))
	result["revision"] = int(state.get("revision", 0))
	return result


func _categorized_history(build: Dictionary) -> Dictionary:
	var categorized := {
		"items": [],
		"blessings": [],
		"curses": [],
		"talents": [],
	}
	var history_value: Variant = build.get("reward_history", [])
	if not history_value is Array:
		return categorized
	for entry_value: Variant in history_value:
		if not entry_value is Dictionary:
			continue
		var entry := (entry_value as Dictionary).duplicate(true)
		match str(entry.get("category", "")):
			"item":
				categorized["items"].append(entry)
			"blessing":
				categorized["blessings"].append(entry)
			"curse":
				categorized["curses"].append(entry)
			"talent":
				categorized["talents"].append(entry)
	return categorized


func _fail_start(code: StringName, context: Dictionary) -> Variant:
	var failure_context := {
		"result": "runtime_error",
		"runtime_error_code": str(code),
		"runtime_error_context": context.duplicate(true),
	}
	if _facade != null:
		_facade.call("player_died", failure_context)
	_dispose_room_runtime()
	if _choice_panel != null:
		_choice_panel.close_panel()
	_set_selection_safety(false)
	_publish_terminal_result(failure_context)
	return CommandResultScript.failure(code, _revision(), context)


func _set_selection_safety(active_selection: bool) -> void:
	if active_selection:
		if _selection_safety_active:
			return
		_selection_safety_active = true
		if _player != null and is_instance_valid(_player):
			if _player.has_method("cancel_transient_actions"):
				_player.call("cancel_transient_actions")
			_player_process_mode = _player.process_mode
			_player.process_mode = Node.PROCESS_MODE_DISABLED
		_clear_hostile_transients()
		return
	if not _selection_safety_active:
		return
	if _player != null and is_instance_valid(_player):
		_player.process_mode = _player_process_mode
	_selection_safety_active = false


func _clear_hostile_transients() -> void:
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node == _player or node.is_in_group("enemies"):
			continue
		if not node.is_queued_for_deletion():
			node.queue_free()
	for node: Node in get_tree().get_nodes_in_group("boss_hazards"):
		if not node.is_queued_for_deletion():
			node.queue_free()


func _render_live_hud() -> void:
	if _hud_layer == null or _projector == null or _facade == null:
		return
	var authoritative := runtime_snapshot()
	if str(authoritative.get("run_id", "")) != _active_run_id:
		return
	var room_definition := _facade.call("current_room_definition") as Dictionary
	var projected = _projector.project(
		authoritative,
		room_definition,
		_player_ui_snapshot(),
		_boss_ui_snapshot(),
		int(authoritative.get("run_time_ms", 0)),
		{"show_pause": get_tree().paused}
	)
	if projected.ok:
		_hud_layer.call("render", projected.context.get("view_state", {}))


func _player_ui_snapshot() -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {}
	if _player.has_method("get_player_ui_snapshot"):
		var provided: Variant = _player.call("get_player_ui_snapshot")
		return (provided as Dictionary).duplicate(true) if provided is Dictionary else {}
	return {}


func _boss_ui_snapshot() -> Variant:
	for candidate: Node in get_tree().get_nodes_in_group("bosses"):
		if not is_instance_valid(candidate) or not _room_controller.is_ancestor_of(candidate):
			continue
		var source: Dictionary = {}
		if candidate.has_method("get_boss_ui_snapshot"):
			var provided: Variant = candidate.call("get_boss_ui_snapshot")
			if provided is Dictionary:
				source = (provided as Dictionary).duplicate(true)
		var health := candidate.get_node_or_null("HealthComponent")
		if health == null and (not source.has("hp") or not source.has("max_hp")):
			return null
		var phase_total := maxi(1, int(source.get("phase_total", 3)))
		return {
			"boss_id": str(source.get("boss_id", "chrono_warden")),
			"name_key": str(source.get("name_key", "BOSS_NAME_CHRONO_WARDEN")),
			"hp": float(source.get("hp", health.current_hp if health != null else 0.0)),
			"max_hp": float(source.get("max_hp", health.max_hp if health != null else 1.0)),
			"phase_index": clampi(int(source.get("phase_index", source.get("boss_phase", 1))), 1, phase_total),
			"phase_total": phase_total,
		}
	return null


func _rejection_message_key(result: RefCounted) -> String:
	var message_key := str(result.message_key)
	return message_key if not message_key.is_empty() else "CHOICE_REJECTED"


func _revision() -> int:
	return int(runtime_snapshot().get("revision", 0))
