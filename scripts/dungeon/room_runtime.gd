class_name RoomRuntime
extends Node

signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
signal spawn_requested(spawn_definition: Dictionary)
signal room_started(room_id: StringName, revision: int)
signal room_cleared(room_id: StringName, revision: int)
signal terminal_committed(context: Dictionary, revision: int)
signal runtime_failed(context: Dictionary)

const CommandResultScript := preload("res://scripts/application/command_result.gd")

var _facade: RefCounted
var _catalog: RefCounted
var _run_seed: int = 0
var _runner: Node
var _room_active: bool = false
var _room_terminal: bool = false
var _failure: Dictionary = {}
var _current_room: Dictionary = {}
var _current_room_id: StringName = &""


func configure(
	facade: RefCounted,
	encounter_catalog: RefCounted,
	_room_definitions: Array[Dictionary],
	run_seed: int,
	encounter_runner: Node
) -> void:
	_disconnect_runner()
	_facade = facade
	_catalog = encounter_catalog
	_run_seed = run_seed
	_runner = encounter_runner
	_room_active = false
	_room_terminal = false
	_failure.clear()
	_current_room.clear()
	_current_room_id = &""
	_connect_runner()


func begin_current_room() -> Variant:
	if _facade == null or _catalog == null or _runner == null:
		return _failure_result(&"RUNTIME_NOT_CONFIGURED", {"operation": "begin_current_room"})
	if _room_active:
		return _failure_result(&"INVALID_PHASE", {"operation": "begin_current_room"})
	var room_value: Variant = _facade.call("current_room_definition")
	if not room_value is Dictionary or (room_value as Dictionary).is_empty():
		return _failure_result(&"ROOM_NOT_AVAILABLE", {"operation": "begin_current_room"})
	var next_room := (room_value as Dictionary).duplicate(true)
	var next_room_id := _room_id(next_room)
	if _room_terminal:
		if not _failure.is_empty() or next_room_id == _current_room_id:
			return _failure_result(&"TERMINAL_STATE", {"operation": "begin_current_room"})
		_room_terminal = false
		_current_room.clear()
		_current_room_id = &""
	_current_room = next_room
	_current_room_id = next_room_id
	var entered: Variant = _facade.call("enter_current_room")
	if not _result_ok(entered):
		_current_room.clear()
		_current_room_id = &""
		return entered
	_room_active = true
	_room_terminal = false
	room_started.emit(_current_room_id, _result_revision(entered))

	var room_type := str(_current_room.get("type", "combat"))
	if room_type == "event":
		_complete_current_room()
		return entered

	var encounter_id := str(_current_room.get("encounter_id", ""))
	var room_number := int(_current_room.get("room_number", 0))
	var encounter_value: Variant = _catalog.call(
		"encounter_definition",
		encounter_id,
		_run_seed,
		room_number
	)
	if not encounter_value is Dictionary or (encounter_value as Dictionary).is_empty():
		_fail_runtime(&"ENCOUNTER_NOT_AVAILABLE", {
			"room_id": str(_current_room_id),
			"encounter_id": encounter_id,
		})
		return _failure_result(&"CONTENT_NOT_AVAILABLE", {"encounter_id": encounter_id})
	_runner.call("start_encounter", (encounter_value as Dictionary).duplicate(true), _run_seed, room_number)
	return entered


func register_spawned(entity: Node, spawn_definition: Dictionary = {}) -> bool:
	if not _can_delegate_spawn():
		return false
	return bool(_runner.call("register_spawned", entity, spawn_definition.duplicate(true)))


func reject_spawn(spawn_definition: Dictionary, reason: StringName) -> bool:
	if not _can_delegate_spawn():
		return false
	return bool(_runner.call("reject_spawn", spawn_definition.duplicate(true), reason))


func report_player_died(killer: Variant = null) -> Variant:
	if _facade == null:
		return _failure_result(&"RUNTIME_NOT_CONFIGURED", {"operation": "report_player_died"})
	if _room_terminal:
		return _failure_result(&"TERMINAL_STATE", {"operation": "report_player_died"})
	var context := {
		"result": "death",
		"room_id": str(_current_room_id),
		"current_room": int(_current_room.get("room_number", 0)),
		"killer": killer,
	}
	var result: Variant = _facade.call("player_died", context)
	if not _result_ok(result):
		return result
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	terminal_committed.emit(context.duplicate(true), _result_revision(result))
	return result


func report_entity_died(entity: Node) -> bool:
	if not _can_delegate_spawn() or entity == null or not is_instance_valid(entity):
		return false
	return bool(_runner.call("notify_entity_defeated", entity))


func snapshot() -> Dictionary:
	return {
		"configured": _facade != null and _catalog != null and _runner != null,
		"room_active": _room_active,
		"room_terminal": _room_terminal,
		"room_id": str(_current_room_id),
		"room_definition": _current_room.duplicate(true),
		"run_seed": _run_seed,
		"failure": _failure.duplicate(true),
		"runner": _runner.call("snapshot") if _runner != null and _runner.has_method("snapshot") else {},
	}


func _connect_runner() -> void:
	if _runner == null:
		return
	if _runner.has_signal("spawn_warning_requested") and not _runner.spawn_warning_requested.is_connected(_on_spawn_warning_requested):
		_runner.spawn_warning_requested.connect(_on_spawn_warning_requested)
	if _runner.has_signal("spawn_requested") and not _runner.spawn_requested.is_connected(_on_spawn_requested):
		_runner.spawn_requested.connect(_on_spawn_requested)
	if _runner.has_signal("encounter_completed") and not _runner.encounter_completed.is_connected(_on_encounter_completed):
		_runner.encounter_completed.connect(_on_encounter_completed)
	if _runner.has_signal("encounter_failed") and not _runner.encounter_failed.is_connected(_on_encounter_failed):
		_runner.encounter_failed.connect(_on_encounter_failed)


func _disconnect_runner() -> void:
	if _runner == null or not is_instance_valid(_runner):
		return
	if _runner.has_signal("spawn_warning_requested") and _runner.spawn_warning_requested.is_connected(_on_spawn_warning_requested):
		_runner.spawn_warning_requested.disconnect(_on_spawn_warning_requested)
	if _runner.has_signal("spawn_requested") and _runner.spawn_requested.is_connected(_on_spawn_requested):
		_runner.spawn_requested.disconnect(_on_spawn_requested)
	if _runner.has_signal("encounter_completed") and _runner.encounter_completed.is_connected(_on_encounter_completed):
		_runner.encounter_completed.disconnect(_on_encounter_completed)
	if _runner.has_signal("encounter_failed") and _runner.encounter_failed.is_connected(_on_encounter_failed):
		_runner.encounter_failed.disconnect(_on_encounter_failed)


func _on_spawn_warning_requested(spawn_definition: Dictionary, duration: float) -> void:
	if _room_active and not _room_terminal:
		spawn_warning_requested.emit(spawn_definition.duplicate(true), duration)


func _on_spawn_requested(spawn_definition: Dictionary) -> void:
	if _room_active and not _room_terminal:
		spawn_requested.emit(spawn_definition.duplicate(true))


func _on_encounter_completed(encounter_id: StringName) -> void:
	if not _room_active or _room_terminal:
		return
	var expected := str(_current_room.get("encounter_id", ""))
	if not expected.is_empty() and str(encounter_id) != expected:
		return
	_complete_current_room()


func _on_encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary) -> void:
	if not _room_active or _room_terminal:
		return
	_fail_runtime(reason, {
		"room_id": str(_current_room_id),
		"encounter_id": str(encounter_id),
		"runner_context": context.duplicate(true),
	})


func _complete_current_room() -> Variant:
	if not _room_active or _room_terminal:
		return _failure_result(&"TERMINAL_STATE", {"operation": "complete_current_room"})
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	var room_type := str(_current_room.get("type", "combat"))
	var result: Variant
	var terminal_context: Dictionary = {}
	if room_type == "boss":
		terminal_context = {
			"result": "victory",
			"room_id": str(_current_room_id),
			"current_room": int(_current_room.get("room_number", 0)),
		}
		result = _facade.call("boss_defeated", terminal_context)
	else:
		result = _facade.call("complete_current_room")
	if _result_ok(result):
		var revision := _result_revision(result)
		room_cleared.emit(_current_room_id, revision)
		if not terminal_context.is_empty():
			terminal_committed.emit(terminal_context.duplicate(true), revision)
	else:
		_failure = {
			"reason": "ROOM_COMMAND_REJECTED",
			"room_id": str(_current_room_id),
			"code": str(result.get("code")) if result != null else "INVALID_RESULT",
		}
		runtime_failed.emit(_failure.duplicate(true))
	return result


func _fail_runtime(reason: StringName, context: Dictionary) -> void:
	if _room_terminal or not _failure.is_empty():
		return
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	_failure = {
		"result": "runtime_error",
		"runtime_error_code": str(reason),
		"runtime_error_context": context.duplicate(true),
		"room_id": str(_current_room_id),
		"current_room": int(_current_room.get("room_number", 0)),
	}
	if _facade != null and _facade.has_method("player_died"):
		_facade.call("player_died", _failure.duplicate(true))
	runtime_failed.emit(_failure.duplicate(true))


func _can_delegate_spawn() -> bool:
	return (
		_room_active
		and not _room_terminal
		and _runner != null
		and is_instance_valid(_runner)
		and bool(_runner.call("is_active"))
	)


func _cancel_runner() -> void:
	if _runner != null and is_instance_valid(_runner) and _runner.has_method("cancel"):
		_runner.call("cancel")


func _room_id(room_definition: Dictionary) -> StringName:
	var explicit_id := str(room_definition.get("id", ""))
	if not explicit_id.is_empty():
		return StringName(explicit_id)
	return StringName("room_%02d" % int(room_definition.get("room_number", 0)))


func _failure_result(code: StringName, context: Dictionary = {}) -> Variant:
	return CommandResultScript.failure(code, _current_revision(), context)


func _current_revision() -> int:
	if _facade == null or not _facade.has_method("snapshot"):
		return 0
	var state_value: Variant = _facade.call("snapshot")
	if not state_value is Dictionary:
		return 0
	return int((state_value as Dictionary).get("revision", 0))


func _result_ok(result: Variant) -> bool:
	return result != null and bool(result.get("ok"))


func _result_revision(result: Variant) -> int:
	if result == null:
		return _current_revision()
	return int(result.get("new_revision"))
