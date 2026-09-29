class_name EncounterRunner
extends Node

signal wave_started(wave_index: int, wave_id: StringName)
signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
signal spawn_requested(spawn_definition: Dictionary)
signal spawn_rejected(spawn_definition: Dictionary, reason: StringName)
signal encounter_completed(encounter_id: StringName)
signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)

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


func _ready() -> void:
	if not EventBus.enemy_spawned.is_connected(_on_enemy_spawned):
		EventBus.enemy_spawned.connect(_on_enemy_spawned)
	if not EventBus.entity_died.is_connected(_on_entity_died):
		EventBus.entity_died.connect(_on_entity_died)


func configure(enemies_root: Node) -> void:
	_enemies_root = enemies_root


func set_timing_override(seconds: float = -1.0) -> void:
	_timing_override_seconds = seconds if seconds >= 0.0 else -1.0


func start_encounter(encounter: Dictionary, _run_seed: int, _room_number: int) -> void:
	cancel()
	_generation += 1
	_encounter = encounter.duplicate(true)
	_wave_index = -1
	_active = not _encounter.is_empty()
	if not _active:
		_fail_encounter(&"EMPTY_ENCOUNTER", {})
		return
	_schedule_advance(_generation)


func cancel() -> void:
	_generation += 1
	_active = false
	_advance_scheduled = false
	_encounter.clear()
	_wave_index = -1
	_alive_instance_ids.clear()
	_pending_spawn_ids.clear()
	_last_failure.clear()


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
	return _alive_instance_ids.size()


func current_wave_index() -> int:
	return _wave_index


func is_active() -> bool:
	return _active


func snapshot() -> Dictionary:
	return {
		"encounter_id": str(_encounter.get("id", "")),
		"wave_index": _wave_index,
		"alive_count": alive_count(),
		"pending_spawn_count": _pending_spawn_ids.size(),
		"active": _active,
		"failure": _last_failure.duplicate(true),
	}


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
	var delay_seconds := (
		_timing_override_seconds
		if _timing_override_seconds >= 0.0
		else float(wave.get("delay_seconds", 0.0))
	)
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
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
	if telegraph_seconds > 0.0:
		await get_tree().create_timer(telegraph_seconds).timeout
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


func _on_enemy_spawned(enemy: Node) -> void:
	if not _active or enemy == null or not is_instance_valid(enemy):
		return
	if _enemies_root == null or (enemy != _enemies_root and not _enemies_root.is_ancestor_of(enemy)):
		return
	register_spawned(enemy)


func _on_entity_died(entity: Node, _killer: Variant) -> void:
	notify_entity_defeated(entity)
