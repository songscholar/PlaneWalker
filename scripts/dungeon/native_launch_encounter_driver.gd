class_name NativeLaunchEncounterDriver
extends Node

const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Ledger := preload("res://scripts/dungeon/launch_encounter_frame_authority.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")

class ProductionBridge extends "res://scripts/enemies/launch/hostile_frame_bridge.gd":
	var native_boundary_ready: Callable
	var _configuring_roster := false

	func register_actor(actor: Node2D) -> bool:
		_configuring_roster = true
		var accepted := super.register_actor(actor)
		_configuring_roster = false
		return accepted

	func is_ready_for_frame(frame: int) -> bool:
		return (_configuring_roster or not native_boundary_ready.is_valid() or native_boundary_ready.call()) and super.is_ready_for_frame(frame)

	func begin_frame(frame: int) -> Dictionary:
		if native_boundary_ready.is_valid() and not native_boundary_ready.call():
			return {}
		return super.begin_frame(frame)

var _runner: Node
var _controller: Node2D
var _facade: RefCounted
var _player: Node2D
var _scene_resolver: Callable
var _scene: Node2D
var _template: Dictionary = {}
var _definition: Dictionary = {}
var _encounter: RefCounted
var _effects: RefCounted
var _ledger: RefCounted
var _bridge: RefCounted
var _payload_root: Node2D
var _actors: Dictionary = {}
var _observations: Array[Dictionary] = []
var _retired_sources: Array[String] = []
var _failure: Dictionary = {}
var _flushing := false
var _cancel_pending := false
var _run_seed := 0
var _last_flushed_frame := -1


func configure(runner: Node, controller: Node2D, facade: RefCounted, player: Node2D, scene_resolver: Callable) -> bool:
	if not is_instance_valid(runner) or not is_instance_valid(controller) or facade == null or not is_instance_valid(player) or not scene_resolver.is_valid() or _flushing or _bridge != null and _bridge.frame_transaction_is_active():
		return false
	cancel()
	if is_instance_valid(_player) and _player.authoritative_frame_committed.is_connected(_on_player_frame_committed):
		_player.authoritative_frame_committed.disconnect(_on_player_frame_committed)
	_runner = runner
	_controller = controller
	_facade = facade
	_player = player
	_scene_resolver = scene_resolver
	_player.authoritative_frame_committed.connect(_on_player_frame_committed)
	return true


func start(encounter: Dictionary, seed: int, generation: int) -> bool:
	if _flushing or _bridge != null and _bridge.frame_transaction_is_active():
		return false
	cancel()
	if not is_instance_valid(_player) or not is_instance_valid(_controller) or _facade == null or not _scene_resolver.is_valid():
		return _fail(&"NATIVE_LAUNCH_BINDING_INVALID")
	var scene_value: Variant = _scene_resolver.call()
	var target: Dictionary = _facade.current_room_restore_target()
	if not scene_value is Node2D or target.is_empty() or not target.get("template") is Dictionary:
		return _fail(&"NATIVE_LAUNCH_SCENE_INVALID")
	_scene = scene_value
	_template = target.template.duplicate(true)
	_run_seed = seed
	var frame: int = int(_player.priority_arbitration_snapshot().frame)
	var identity := {"run_id": str(_player.current_run_id()), "room_id": str(target.node_id), "runtime_frame": frame, "encounter_generation": generation}
	var runtime := Encounter.new()
	var configured: Dictionary = runtime.configure(encounter, identity)
	if not configured.ok:
		return _fail(&"NATIVE_LAUNCH_DEFINITION_INVALID", configured.context)
	var payload_root := Node2D.new()
	payload_root.name = "NativeLaunchHostilePayloads"
	_controller.add_child(payload_root)
	var effects := Effects.new()
	if not effects.configure(identity.run_id, frame) or not effects.configure_native_payloads(payload_root):
		payload_root.queue_free()
		return _fail(&"NATIVE_LAUNCH_EFFECTS_INVALID")
	var ledger := Ledger.new()
	var bridge := ProductionBridge.new()
	bridge.native_boundary_ready = Callable(self, "_boundary_ready")
	if not ledger.configure(runtime, effects) or not bridge.configure(_player, _controller.hostile_threat_registry(), [], effects) or not bridge.configure_encounter_authority(ledger) or not _player.configure_hostile_frame_participant(bridge):
		payload_root.queue_free()
		return _fail(&"NATIVE_LAUNCH_FRAME_BINDING_INVALID")
	_definition = runtime.configured_encounter()
	_last_flushed_frame = frame
	_encounter = runtime
	_effects = effects
	_ledger = ledger
	_bridge = bridge
	_payload_root = payload_root
	_ledger.encounter_frame_observed.connect(_on_encounter_observed)
	return true


func cancel() -> void:
	if _flushing or _bridge != null and _bridge.frame_transaction_is_active():
		_cancel_pending = true
		return
	_clear_native()


func _exit_tree() -> void:
	if is_instance_valid(_player) and _player.authoritative_frame_committed.is_connected(_on_player_frame_committed):
		_player.authoritative_frame_committed.disconnect(_on_player_frame_committed)
	_clear_native()


func _clear_native() -> void:
	if _bridge != null and is_instance_valid(_player) and _player.get("_hostile_frame_participant") == _bridge:
		_player.configure_hostile_frame_participant(null)
	if _encounter != null:
		_encounter.cancel(&"native_room_teardown")
	for actor: Node in _actors.values():
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			actor.queue_free()
	if is_instance_valid(_payload_root) and not _payload_root.is_queued_for_deletion():
		_payload_root.queue_free()
	_actors.clear()
	_observations.clear()
	_retired_sources.clear()
	_definition.clear()
	_template.clear()
	_encounter = null
	_effects = null
	_ledger = null
	_bridge = null
	_payload_root = null
	_scene = null
	_cancel_pending = false
	_last_flushed_frame = -1
	_failure.clear()


func has_native_state() -> bool:
	return _encounter != null


func is_active() -> bool:
	return _encounter != null and _failure.is_empty() and _encounter.is_active()


func snapshot() -> Dictionary:
	if _encounter == null:
		return {}
	var actors: Dictionary = {}
	for source: String in _actors:
		var actor: Node = _actors[source]
		if not is_instance_valid(actor):
			return {}
		actors[source] = actor.launch_runtime_snapshot()
	return {"schema_version": 1, "definition": _definition.duplicate(true), "encounter": _encounter.snapshot(), "effects": _effects.snapshot(), "actors": actors, "failure": _failure.duplicate(true)}


func legacy_snapshot() -> Dictionary:
	var state: Dictionary = _encounter.snapshot() if _encounter != null else {}
	return {"encounter_id": str(_definition.get("id", "")), "wave_index": int(state.get("wave_index", -1)), "alive_count": state.get("roster", {}).size(), "pending_spawn_count": state.get("pending_spawns", {}).size(), "active": is_active(), "failure": _failure.duplicate(true)}


func native_scene() -> Node2D:
	return _scene


func spawn_actor(spawn: Dictionary) -> bool:
	if not _flushing or not is_active() or not _encounter.snapshot().pending_spawns.has(spawn.get("id", "")) or _encounter.snapshot().pending_spawns[spawn.id] != spawn:
		return false
	var definition: Dictionary = _facade.encounter_catalog().enemy_definition(str(spawn.enemy_id))
	var resource: Resource = load(str(definition.get("scene", ""))) if ResourceLoader.exists(str(definition.get("scene", ""))) else null
	var marker: Node2D = _scene.get_node_or_null("EncounterAnchors/" + str(spawn.spawn_slot_id)) as Node2D
	if not resource is PackedScene or marker == null:
		return false
	var parser: RefCounted = Boss.new() if definition.get("category") == "boss_definition" else Enemy.new()
	var source: Dictionary = {}
	for field: String in Boss.FIELDS if definition.get("category") == "boss_definition" else Enemy.FIELDS:
		if not definition.has(field):
			return false
		source[field] = definition[field]
	if not parser.configure(source).ok:
		return false
	var projection: Dictionary = parser.runtime_projection() if definition.category == "boss_definition" else parser.runtime_projection("elite" if spawn.elite else "enemy")
	var instance := (resource as PackedScene).instantiate()
	if not instance is Node2D:
		instance.free()
		return false
	var actor := instance as Node2D
	if not actor.has_method("configure_launch_definition") or not actor.has_method("configure_launch_room_motion") or not actor.has_signal("hostile_final_death"):
		actor.free()
		return false
	var frame: int = int(_encounter.snapshot().last_runtime_frame)
	var source_id: String = str(_controller.hostile_source_id_for_spawn({"run_id": str(_player.current_run_id())}, StringName(_encounter.snapshot().identity.room_id), StringName(_definition.id), spawn, 0))
	var identity := {"run_id": str(_player.current_run_id()), "hostile_source_id": source_id, "next_generation_floor": 1, "runtime_frame": frame, "seed": _run_seed}
	actor.set_meta("encounter_enemy_id", str(spawn.enemy_id))
	actor.set_meta("encounter_spawn_id", str(spawn.id))
	actor.set_meta("encounter_affix_ids", spawn.affix_ids.duplicate())
	_controller.get_node("Enemies").add_child(actor)
	actor.global_position = marker.global_position + Vector2(float(spawn.spawn_offset.x), float(spawn.spawn_offset.y))
	if not actor.configure_launch_definition(projection, identity).ok or not actor.configure_launch_room_motion(_scene, _template).ok or not _controller._configure_character_boss_exposure_participant(actor) or not _bridge.register_actor(actor) or not _encounter.register_spawned(str(spawn.id), source_id):
		actor.queue_free()
		return false
	_actors[source_id] = actor
	actor.hostile_final_death.connect(_on_actor_final_death)
	EventBus.enemy_spawned.emit(actor, {"boss": definition.category == "boss_definition", "summoned": false})
	return true


func reject_spawn(spawn: Dictionary, reason: StringName) -> bool:
	if _encounter == null or not _encounter.reject_spawn(str(spawn.get("id", "")), reason):
		return false
	_runner.spawn_rejected.emit(spawn.duplicate(true), reason)
	return _fail(&"SPAWN_REJECTED", {"spawn_id": str(spawn.get("id", "")), "rejection_reason": str(reason)})


func _on_actor_final_death(source: StringName, receipt: String) -> void:
	if _encounter == null or not _actors.has(str(source)):
		return
	var actor: Node2D = _actors[str(source)]
	if not is_instance_valid(actor):
		return
	var state: Dictionary = actor.launch_runtime_snapshot()
	var health: Node = actor.get_node_or_null("HealthComponent")
	var expected := "hostile_defeat:%s" % (str(_player.current_run_id()) + "|" + str(source)).sha256_text().substr(0, 40)
	if state.is_empty() or not is_instance_valid(health) or not health.dead or health.current_hp > 0.0 or not state.runtime.terminal or state.runtime.identity.run_id != str(_player.current_run_id()) or state.death_receipt != receipt or receipt != expected or state.runtime.runtime_frame != _encounter.snapshot().last_runtime_frame or not _encounter.notify_entity_defeated(str(source), receipt):
		return
	_actors.erase(str(source))
	_retired_sources.append(str(source))


func _on_encounter_observed(result: Dictionary) -> void:
	_observations.append(result.duplicate(true))


func _on_player_frame_committed(frame: int) -> void:
	if _encounter == null or _flushing or _bridge.frame_transaction_is_active() or frame <= _last_flushed_frame or frame != int(_player.priority_arbitration_snapshot().frame) or frame != int(_ledger.snapshot().runtime_frame) or _player.authoritative_frame_intents(frame).is_empty():
		return
	_last_flushed_frame = frame
	if _cancel_pending:
		_clear_native()
		return
	_flushing = true
	for source: String in _retired_sources:
		if _bridge.get("_actors").has(source):
			_bridge.retire_actor(source)
	_retired_sources.clear()
	var observed: Array[Dictionary] = _observations.duplicate(true)
	_observations.clear()
	for result: Dictionary in observed:
		if int(result.runtime_frame) != frame:
			_fail(&"NATIVE_LAUNCH_CLOCK_INVALID")
			break
		if not result.wave_started.is_empty():
			_runner.wave_started.emit(int(result.wave_started.wave_index), StringName(result.wave_started.wave_id))
			if _cancel_pending or not _failure.is_empty():
				break
		for warning: Dictionary in result.spawn_warnings:
			_runner.spawn_warning_requested.emit(warning.spawn_definition.duplicate(true), float(warning.warning_frames) / 60.0)
			if _cancel_pending or not _failure.is_empty():
				break
		if _cancel_pending or not _failure.is_empty():
			break
		for spawn: Dictionary in result.spawn_requests:
			_runner.spawn_requested.emit(spawn.duplicate(true))
			if _cancel_pending or not _failure.is_empty():
				break
			if _encounter.snapshot().pending_spawns.has(spawn.id):
				reject_spawn(spawn, &"SPAWN_REQUEST_UNACKNOWLEDGED")
				break
		if not result.encounter_completed.is_empty() and _failure.is_empty() and not _cancel_pending:
			_runner.encounter_completed.emit(StringName(result.encounter_completed))
	_flushing = false
	if _cancel_pending:
		_clear_native()


func _boundary_ready() -> bool:
	return not _flushing and not _cancel_pending and _failure.is_empty() and _observations.is_empty()


func _fail(code: StringName, context: Dictionary = {}) -> bool:
	if not _failure.is_empty():
		return false
	_failure = {"code": str(code), "context": context.duplicate(true)}
	if is_instance_valid(_player):
		_player.set_physics_process(false)
	if is_instance_valid(_runner):
		_runner.encounter_failed.emit(StringName(_definition.get("id", "")), code, context.duplicate(true))
	return false
