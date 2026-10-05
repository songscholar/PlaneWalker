class_name EncounterRunner
extends Node

signal wave_started(wave_index: int, wave_id: StringName)
signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
signal spawn_requested(spawn_definition: Dictionary)
signal spawn_rejected(spawn_definition: Dictionary, reason: StringName)
signal encounter_completed(encounter_id: StringName)
signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)

const NativeLaunchDriver := preload("res://scripts/dungeon/native_launch_encounter_driver.gd")

var _native_launch_driver: Node
var _enemies_root: Node
var _encounter: Dictionary = {}
var _generation: int = 0
var _wave_index: int = -1
var _alive_instance_ids: Dictionary = {}
var _pending_spawn_ids: Dictionary = {}
var _active: bool = false
var _advance_scheduled: bool = false
var _last_failure: Dictionary = {}
var _timing_override_seconds: float = -1.0
var _phase_timer: Timer


func configure(enemies_root: Node) -> void:
	_enemies_root = enemies_root


func configure_native_launch(controller: Node2D, facade: RefCounted, player: Node2D, scene_resolver: Callable) -> bool:
	if _native_launch_driver == null:
		_native_launch_driver = NativeLaunchDriver.new()
		_native_launch_driver.name = "NativeLaunchEncounterDriver"
		add_child(_native_launch_driver)
	return _native_launch_driver.configure(self, controller, facade, player, scene_resolver)


func native_launch_snapshot() -> Dictionary:
	return _native_launch_driver.snapshot() if _native_launch_driver != null else {}


func native_launch_scene() -> Node2D:
	return _native_launch_driver.native_scene() if _native_launch_driver != null else null


func native_cold_snapshot() -> Dictionary:
	return _native_launch_driver.cold_snapshot() if _native_launch_driver != null else {}


func native_cold_snapshot_matches(value: Dictionary) -> bool:
	return _native_launch_driver != null and _native_launch_driver.matches_cold_snapshot(value)


func restore_native_cold_snapshot(value: Dictionary) -> bool:
	if _native_launch_driver == null or is_active() or not _encounter.is_empty() or not _native_launch_driver.restore_cold_snapshot(value):
		return false
	_generation = int(value.encounter.identity.encounter_generation)
	_encounter = value.definition.duplicate(true)
	return true


func checkpoint_restore_preimage() -> Dictionary:
	return {"runner": snapshot(), "generation": _generation} if not is_active() else {}


func discard_checkpoint_restore(value: Dictionary) -> bool:
	if value.size() != 2 or not value.get("runner") is Dictionary or not value.get("generation") is int or value.generation < 0:
		return false
	if _native_launch_driver != null and not _native_launch_driver.discard_cold_restore():
		return false
	cancel()
	if not restore_inactive_checkpoint(value.runner):
		return false
	_generation = value.generation
	return snapshot() == value.runner


func spawn_native_actor(spawn: Dictionary) -> bool:
	return _native_launch_driver != null and _native_launch_driver.spawn_actor(spawn)


func _has_native_state() -> bool:
	return _native_launch_driver != null and _native_launch_driver.has_native_state()


func set_timing_override(seconds: float = -1.0) -> void:
	_timing_override_seconds = seconds if seconds >= 0.0 else -1.0


func start_encounter(encounter: Dictionary, _run_seed: int, _room_number: int) -> void:
	cancel()
	_generation += 1
	_encounter = encounter.duplicate(true)
	if encounter.has("recipe_id") and encounter.has("floor_id"):
		if _native_launch_driver == null or not _native_launch_driver.start(encounter, _run_seed, _generation):
			if _native_launch_driver == null:
				_fail_encounter(&"NATIVE_LAUNCH_BINDING_INVALID", {})
		return
	_wave_index = -1
	_active = not _encounter.is_empty()
	if not _active:
		_fail_encounter(&"EMPTY_ENCOUNTER", {})
		return
	_schedule_advance(_generation)


func cancel() -> void:
	if _native_launch_driver != null:
		_native_launch_driver.cancel()
	_cancel_phase_timer()
	_generation += 1
	_active = false
	_advance_scheduled = false
	_encounter.clear()
	_wave_index = -1
	_alive_instance_ids.clear()
	_pending_spawn_ids.clear()
	_last_failure.clear()


func _exit_tree() -> void:
	_cancel_phase_timer()


func register_spawned(entity: Node, spawn_definition: Dictionary = {}) -> bool:
	if not _active or entity == null or not is_instance_valid(entity):
		return false
	if _enemies_root != null and entity != _enemies_root and not _enemies_root.is_ancestor_of(entity):
		return false
	var instance_id := entity.get_instance_id()
	if _alive_instance_ids.has(instance_id):
		return false
	var spawn_id := str(spawn_definition.get("id", ""))
	if not spawn_id.is_empty():
		_pending_spawn_ids.erase(spawn_id)
	entity.set_meta("encounter_generation", _generation)
	entity.set_meta("encounter_counted", true)
	_alive_instance_ids[instance_id] = true
	return true


func reject_spawn(spawn_definition: Dictionary, reason: StringName) -> bool:
	if _has_native_state():
		return _native_launch_driver.reject_spawn(spawn_definition, reason)
	if not _active:
		return false
	var spawn_id := str(spawn_definition.get("id", ""))
	if not spawn_id.is_empty():
		_pending_spawn_ids.erase(spawn_id)
	spawn_rejected.emit(spawn_definition.duplicate(true), reason)
	_fail_encounter(&"SPAWN_REJECTED", {
		"spawn_id": spawn_id,
		"rejection_reason": str(reason),
	})
	return true


func notify_entity_defeated(entity: Node) -> bool:
	if not _active or entity == null:
		return false
	var instance_id := entity.get_instance_id()
	if not _alive_instance_ids.has(instance_id):
		return false
	_alive_instance_ids.erase(instance_id)
	entity.set_meta("encounter_counted", false)
	_check_wave_completion()
	return true


func alive_count() -> int:
	if _has_native_state():
		return int(_native_launch_driver.legacy_snapshot().alive_count)
	return _alive_instance_ids.size()


func current_wave_index() -> int:
	if _has_native_state():
		return int(_native_launch_driver.legacy_snapshot().wave_index)
	return _wave_index


func is_active() -> bool:
	if _has_native_state():
		return _native_launch_driver.is_active()
	return _active


func snapshot() -> Dictionary:
	if _has_native_state():
		return _native_launch_driver.legacy_snapshot()
	return {
		"encounter_id": str(_encounter.get("id", "")),
		"wave_index": _wave_index,
		"alive_count": alive_count(),
		"pending_spawn_count": _pending_spawn_ids.size(),
		"active": _active,
		"failure": _last_failure.duplicate(true),
	}


func restore_inactive_checkpoint(value: Dictionary) -> bool:
	var fields := ["encounter_id", "wave_index", "alive_count", "pending_spawn_count", "active", "failure"]
	if value.size() != fields.size() or _active or not _alive_instance_ids.is_empty() or not _pending_spawn_ids.is_empty():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	if not value.encounter_id is String or not value.failure is Dictionary or value.active != false or value.alive_count != 0 or value.pending_spawn_count != 0 or typeof(value.wave_index) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.wave_index)) or float(value.wave_index) != floor(float(value.wave_index)) or int(value.wave_index) < -1:
		return false
	cancel()
	_encounter = {} if value.encounter_id.is_empty() else {"id": value.encounter_id}
	_wave_index = int(value.wave_index)
	_last_failure = value.failure.duplicate(true)
	return JSON.parse_string(JSON.stringify(snapshot(), "", true, true)) == JSON.parse_string(JSON.stringify(value, "", true, true))


func _schedule_advance(token: int) -> void:
	if not _active or _advance_scheduled:
		return
	_advance_scheduled = true
	call_deferred("_start_next_wave", token)


func _start_next_wave(token: int) -> void:
	_advance_scheduled = false
	if not _active or token != _generation:
		return
	if alive_count() > 0 or not _pending_spawn_ids.is_empty():
		return
	var waves: Array = _encounter.get("waves", [])
	_wave_index += 1
	if _wave_index >= waves.size():
		_complete_encounter()
		return
	var wave: Dictionary = waves[_wave_index]
	wave_started.emit(_wave_index, StringName(str(wave.get("id", ""))))
	if not _active or token != _generation:
		return
	var delay_seconds := (
		_timing_override_seconds
		if _timing_override_seconds >= 0.0
		else float(wave.get("delay_seconds", 0.0))
	)
	if delay_seconds > 0.0:
		_wait_for_phase(delay_seconds, _begin_wave_warning.bind(wave.duplicate(true), token))
	else:
		_begin_wave_warning(wave, token)


func _begin_wave_warning(wave: Dictionary, token: int) -> void:
	if not _active or token != _generation:
		return
	var telegraph_seconds := (
		_timing_override_seconds
		if _timing_override_seconds >= 0.0
		else float(wave.get("telegraph_seconds", 0.0))
	)
	var spawns: Array = wave.get("spawns", [])
	_pending_spawn_ids.clear()
	for spawn_value: Variant in spawns:
		var spawn: Dictionary = spawn_value
		_pending_spawn_ids[str(spawn.get("id", ""))] = true
		spawn_warning_requested.emit(spawn.duplicate(true), telegraph_seconds)
		if not _active or token != _generation:
			return
	if telegraph_seconds > 0.0:
		_wait_for_phase(telegraph_seconds, _spawn_wave.bind(spawns.duplicate(true), token))
	else:
		_spawn_wave(spawns, token)


func _spawn_wave(spawns: Array, token: int) -> void:
	if not _active or token != _generation:
		return
	for spawn_value: Variant in spawns:
		var spawn: Dictionary = spawn_value
		spawn_requested.emit(spawn.duplicate(true))
		if not _active or token != _generation:
			return
		var spawn_id := str(spawn.get("id", ""))
		if _pending_spawn_ids.has(spawn_id):
			reject_spawn(spawn, &"SPAWN_REQUEST_UNACKNOWLEDGED")
			return
	_check_wave_completion()


func _wait_for_phase(duration: float, continuation: Callable) -> void:
	_cancel_phase_timer()
	_phase_timer = Timer.new()
	_phase_timer.one_shot = true
	_phase_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(_phase_timer)
	_phase_timer.timeout.connect(_finish_phase.bind(_phase_timer, continuation), CONNECT_ONE_SHOT)
	_phase_timer.start(duration)


func _finish_phase(timer: Timer, continuation: Callable) -> void:
	if timer != _phase_timer:
		return
	_cancel_phase_timer()
	if continuation.is_valid():
		continuation.call()


func _cancel_phase_timer() -> void:
	if not is_instance_valid(_phase_timer):
		return
	_phase_timer.stop()
	if _phase_timer.get_parent() == self:
		remove_child(_phase_timer)
	_phase_timer.queue_free()
	_phase_timer = null


func _check_wave_completion() -> void:
	if not _active or alive_count() > 0 or not _pending_spawn_ids.is_empty():
		return
	_schedule_advance(_generation)


func _complete_encounter() -> void:
	if not _active:
		return
	var encounter_id := StringName(str(_encounter.get("id", "")))
	_active = false
	_advance_scheduled = false
	_pending_spawn_ids.clear()
	encounter_completed.emit(encounter_id)


func _fail_encounter(reason: StringName, context: Dictionary) -> void:
	_cancel_phase_timer()
	var encounter_id := StringName(str(_encounter.get("id", "")))
	_generation += 1
	_active = false
	_advance_scheduled = false
	_pending_spawn_ids.clear()
	_alive_instance_ids.clear()
	_last_failure = {
		"encounter_id": str(encounter_id),
		"reason": str(reason),
		"context": context.duplicate(true),
	}
	encounter_failed.emit(encounter_id, reason, context.duplicate(true))
