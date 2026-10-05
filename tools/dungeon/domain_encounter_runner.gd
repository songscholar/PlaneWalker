extends Node

signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
signal spawn_requested(spawn_definition: Dictionary)
signal encounter_completed(encounter_id: StringName)
signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)

const Core := preload("res://scripts/dungeon/launch_encounter_runtime.gd")

var _core := Core.new()
var _root: Node
var _run_id := ""
var _room_id := ""
var _generation := 0
var _encounter_id := ""
var _entities: Dictionary = {}
var _failure: Dictionary = {}


func configure(root: Node, run_id: String, room_id: String) -> void:
	_root = root
	_run_id = run_id
	_room_id = room_id


func start_encounter(definition: Dictionary, _seed: int, _room_number: int) -> void:
	cancel()
	_generation += 1
	_encounter_id = str(definition.get("id", ""))
	var configured := _core.configure(definition, {"run_id": _run_id, "room_id": _room_id, "runtime_frame": 0, "encounter_generation": _generation})
	if not configured.ok or not is_instance_valid(_root):
		_fail(&"DOMAIN_ENCOUNTER_CONFIGURATION_INVALID", configured)


func advance_domain_frame() -> Dictionary:
	var advanced := _core.advance_frame(int(_core.snapshot().get("last_runtime_frame", 0)) + 1)
	if not advanced.ok:
		return advanced
	for warning: Dictionary in advanced.spawn_warnings:
		spawn_warning_requested.emit(warning.spawn_definition.duplicate(true), float(warning.warning_frames) / 60.0)
	for spawn: Dictionary in advanced.spawn_requests:
		if not is_active():
			break
		spawn_requested.emit(spawn.duplicate(true))
	if not str(advanced.encounter_completed).is_empty():
		encounter_completed.emit(StringName(advanced.encounter_completed))
	return advanced


func register_spawned(entity: Node, definition: Dictionary) -> bool:
	if not is_active() or not is_instance_valid(entity) or not is_instance_valid(_root) or entity.is_queued_for_deletion() or not _root.is_ancestor_of(entity) or _entities.has(entity.get_instance_id()):
		return false
	var state := _core.snapshot()
	var spawn_id := str(definition.get("id", ""))
	if not state.pending_spawns.has(spawn_id) or state.pending_spawns[spawn_id] != definition:
		return false
	var source := "probe_" + ("%s:%s:%d:%s" % [_run_id, _room_id, _generation, spawn_id]).sha256_text().substr(0, 40)
	if not _core.register_spawned(spawn_id, source):
		return false
	_entities[entity.get_instance_id()] = {"entity": weakref(entity), "source": source}
	return true


func notify_entity_defeated(entity: Node) -> bool:
	if not is_instance_valid(entity) or not _entities.has(entity.get_instance_id()):
		return false
	var row: Dictionary = _entities[entity.get_instance_id()]
	if row.entity.get_ref() != entity or not _core.notify_entity_defeated(row.source, "defeat_" + str(row.source).sha256_text().substr(0, 40)):
		return false
	_entities.erase(entity.get_instance_id())
	return true


func reject_spawn(definition: Dictionary, reason: StringName) -> bool:
	var state := _core.snapshot()
	var spawn_id := str(definition.get("id", ""))
	if not state.get("pending_spawns", {}).has(spawn_id) or state.pending_spawns[spawn_id] != definition or not _core.reject_spawn(spawn_id, reason):
		return false
	_fail(&"SPAWN_REJECTED", {"spawn_id": spawn_id, "reason": reason})
	return true


func cancel() -> void:
	if not _core.snapshot().is_empty():
		_core.cancel(&"probe_cancelled")
	_entities.clear()
	_failure.clear()
	_encounter_id = ""


func is_active() -> bool:
	return _failure.is_empty() and _core.is_active()


func snapshot() -> Dictionary:
	var state := _core.snapshot()
	return {"encounter_id": _encounter_id, "wave_index": _core.current_wave_index(), "alive_count": _core.alive_count(), "pending_spawn_count": state.get("pending_spawns", {}).size(), "active": is_active(), "failure": _failure.duplicate(true), "domain": state}


func _fail(code: StringName, context: Dictionary) -> void:
	_failure = {"code": code, "context": context.duplicate(true)}
	encounter_failed.emit(StringName(_encounter_id), code, context.duplicate(true))
