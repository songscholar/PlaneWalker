class_name NativeLaunchEncounterDriver
extends Node

const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Ledger := preload("res://scripts/dungeon/launch_encounter_frame_authority.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Controller := preload("res://scripts/dungeon/room_controller.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Semantics := preload("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
const Debris := preload("res://scripts/enemies/launch/ruin_debris_runtime.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const COLD_FIELDS := ["schema_version", "definition", "encounter", "effects", "actors", "threats", "run_seed", "last_flushed_frame"]

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
	if _effects != null:
		_effects.dispose_native_effects()
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
	var frame: int = int(_encounter.snapshot().last_runtime_frame)
	var source_id: String = str(_controller.hostile_source_id_for_spawn({"run_id": str(_player.current_run_id())}, StringName(_encounter.snapshot().identity.room_id), StringName(_definition.id), spawn, 0))
	var identity := {"run_id": str(_player.current_run_id()), "hostile_source_id": source_id, "next_generation_floor": 1, "runtime_frame": frame, "seed": _run_seed}
	var marker: Node2D = _scene.get_node_or_null("EncounterAnchors/" + str(spawn.spawn_slot_id)) as Node2D
	if marker == null:
		return false
	var actor := _instantiate_actor(spawn, identity, marker.global_position + Vector2(float(spawn.spawn_offset.x), float(spawn.spawn_offset.y)))
	if actor == null:
		return false
	if not _bridge.register_actor(actor) or not _encounter.register_spawned(str(spawn.id), source_id):
		actor.queue_free()
		return false
	_actors[source_id] = actor
	actor.hostile_final_death.connect(_on_actor_final_death)
	var definition: Dictionary = _facade.encounter_catalog().enemy_definition(str(spawn.enemy_id))
	EventBus.enemy_spawned.emit(actor, {"boss": definition.category == "boss_definition", "summoned": false})
	return true


func _instantiate_actor(spawn: Dictionary, identity: Dictionary, position: Vector2, legacy_affixes: bool = false, affix_revision: int = 3) -> Node2D:
	var definition: Dictionary = _facade.encounter_catalog().enemy_definition(str(spawn.enemy_id))
	var resource: Resource = load(str(definition.get("scene", ""))) if ResourceLoader.exists(str(definition.get("scene", ""))) else null
	var marker: Node2D = _scene.get_node_or_null("EncounterAnchors/" + str(spawn.spawn_slot_id)) as Node2D
	if not resource is PackedScene or marker == null:
		return null
	var parser: RefCounted = Boss.new() if definition.get("category") == "boss_definition" else Enemy.new()
	var source: Dictionary = {}
	for field: String in Boss.FIELDS if definition.get("category") == "boss_definition" else Enemy.FIELDS:
		if not definition.has(field):
			return null
		source[field] = definition[field]
	if not parser.configure(source).ok:
		return null
	var projection: Dictionary = parser.runtime_projection() if definition.category == "boss_definition" else parser.runtime_projection("elite" if spawn.elite else "enemy")
	var instance := (resource as PackedScene).instantiate()
	if not instance is Node2D:
		instance.free()
		return null
	var actor := instance as Node2D
	if not actor.has_method("configure_launch_definition") or not actor.has_method("configure_launch_room_motion") or not actor.has_signal("hostile_final_death"):
		actor.free()
		return null
	actor.set_meta("encounter_enemy_id", str(spawn.enemy_id))
	actor.set_meta("encounter_spawn_id", str(spawn.id))
	actor.set_meta("encounter_affix_ids", spawn.affix_ids.duplicate())
	_controller._configure_hostile_run_metadata(actor, {"run_id": str(_player.current_run_id())})
	actor.set_meta("encounter_id", StringName(_definition.id))
	actor.set_meta("room_id", StringName(_encounter.snapshot().identity.room_id))
	_controller.get_node("Enemies").add_child(actor)
	actor.global_position = position
	if spawn.elite and not legacy_affixes:
		var affixes: Array = []
		for affix_id: String in spawn.affix_ids:
			affixes.append(_facade.encounter_catalog().affix_definition(affix_id))
		if not actor.has_method("configure_launch_affixes") or not actor.configure_launch_affixes(affixes, Ids.FLOOR_IDS.find(str(_definition.floor_id)) + 1, affix_revision).ok:
			actor.free()
			return null
	if not actor.configure_launch_definition(projection, identity).ok or not actor.configure_launch_room_motion(_scene, _template).ok or not _controller._configure_character_boss_exposure_participant(actor):
		actor.free()
		return null
	return actor


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


func cold_snapshot() -> Dictionary:
	if not is_active() or not _boundary_ready() or _bridge.frame_transaction_is_active() or not _retired_sources.is_empty() or _last_flushed_frame != int(_player.priority_arbitration_snapshot().frame):
		return {}
	var actors: Dictionary = {}
	for source: String in _actors:
		var actor: Node = _actors[source]
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.has_method("native_cold_snapshot"):
			return {}
		var state: Dictionary = actor.native_cold_snapshot(Callable(self, "_cold_source_binding"))
		if state.is_empty():
			return {}
		actors[source] = state
	var value := {"schema_version": 1, "definition": _definition.duplicate(true), "encounter": _encounter.snapshot(), "effects": _effects.launch_transaction_snapshot(), "actors": actors, "threats": _controller.hostile_threat_registry().snapshot(), "run_seed": _run_seed, "last_flushed_frame": _last_flushed_frame}
	return value if validate_cold_snapshot(value, str(_player.current_run_id()), str(_encounter.snapshot().identity.room_id), _last_flushed_frame) else {}


static func validate_cold_snapshot(value: Dictionary, run_id: String, room_id: String, frame: int) -> bool:
	if not Contract.exact_fields(value, COLD_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or not value.definition is Dictionary or not value.encounter is Dictionary or not value.effects is Dictionary or not value.actors is Dictionary or not value.threats is Array or not Contract.integer_in_range(value.run_seed, -2147483648, 2147483647) or value.last_flushed_frame != frame or not Replay.replay_value_is_safe(value):
		return false
	var state: Dictionary = value.encounter
	if not state.get("identity") is Dictionary or state.identity.get("run_id") != run_id or state.identity.get("room_id") != room_id or state.get("last_runtime_frame") != frame or state.get("status") not in Encounter.LIVE_STATUSES or not state.get("roster") is Dictionary or state.roster.size() != value.actors.size() or not state.get("pending_spawns") is Dictionary or not state.pending_spawns.is_empty():
		return false
	var runtime := Encounter.new()
	if not runtime.configure(value.definition, state.identity).ok or not runtime.restore_snapshot(state):
		return false
	var effects := Effects.new()
	if not effects.configure(run_id, int(state.identity.runtime_frame)) or not effects.can_restore_launch_transaction_snapshot(value.effects) or value.effects.runtime_frame != frame:
		return false
	if value.effects.payloads.get("schema_version") == 2:
		var debris_state: Dictionary = value.effects.payloads.arena_debris
		var debris := Debris.new()
		if not debris.configure(run_id, int(debris_state.initial_frame), debris_state.recipe) or not debris.can_restore_snapshot(debris_state, true):
			return false
	var registry := Registry.new()
	var sources: Dictionary = {}
	var ruin_sources: Dictionary = {}
	for wave: Dictionary in value.definition.waves:
		for spawn: Dictionary in wave.spawns:
			var source := str(Controller.hostile_source_id_for_spawn({"run_id": run_id}, StringName(room_id), StringName(value.definition.id), spawn, 0))
			sources[source] = true
			if spawn.enemy_id == "ruin_king":
				ruin_sources[source] = true
	for debris: Dictionary in value.effects.payloads.get("arena_debris", {}).get("rows", []):
		if not ruin_sources.has(debris.event.source_id):
			return false
	for source: String in value.effects.payloads.get("arena_debris", {}).get("retirements", {}):
		if not ruin_sources.has(source):
			return false
	var payload_facts := Registry.new()
	for payload: Dictionary in value.effects.payloads.projectiles + value.effects.payloads.zones:
		if not sources.has(payload.definition.source_id) or payload.definition.has("debris_recipe") and not ruin_sources.has(payload.definition.source_id):
			return false
		if payload.phase not in ["PENDING", "DORMANT"]:
			sources[payload.id] = true
			if not payload_facts.register_fact(Effects._payload_threat_fact(payload, frame)):
				return false
	for zone: Dictionary in value.effects.semantics.zones:
		if not sources.has(zone.source_id):
			return false
		if zone.phase != "PENDING":
			sources[zone.id] = true
	for fact: Dictionary in Semantics.new().threat_facts_for_snapshot(value.effects.semantics):
		if not payload_facts.register_fact(fact):
			return false
	for row: Variant in value.threats:
		if not row is Dictionary or not sources.has(str(row.get("hostile_source_id", ""))) or not registry.register_fact(row):
			return false
	for fact: Dictionary in payload_facts.snapshot():
		if registry.fact_snapshot(fact.hostile_source_id, fact.attack_generation) != fact:
			return false
	for source: Variant in value.actors:
		var actor: Variant = value.actors[source]
		if not source is String or not actor is Dictionary or not Contract.exact_fields(actor, ["schema_version", "definition_id", "identity", "actor", "health"]) or actor.schema_version != 1 or not actor.health is Dictionary or not state.roster.has(source) or not actor.get("identity") is Dictionary or not actor.get("actor") is Dictionary or not actor.actor.get("runtime") is Dictionary or not Contract.valid_point(actor.actor.get("position")):
			return false
		var spawn := _cold_spawn(value.definition, str(state.roster[source].spawn_id))
		var expected := str(Controller.hostile_source_id_for_spawn({"run_id": run_id}, StringName(room_id), StringName(value.definition.id), spawn, 0))
		if spawn.is_empty() or expected != source or actor.get("definition_id") != spawn.enemy_id or actor.identity.get("hostile_source_id") != source or actor.identity.get("run_id") != run_id or actor.identity.get("seed") != value.run_seed or actor.actor.runtime.get("identity") != actor.identity or actor.actor.runtime.get("runtime_frame") != frame or actor.actor.runtime.get("terminal") != false or actor.health.get("dead") != false:
			return false
		if not actor.actor.runtime.get("mechanism_state") is Dictionary:
			return false
		for field: String in ["hp_after", "hp_current"]:
			if actor.actor.runtime.mechanism_state.has(field) and actor.actor.runtime.mechanism_state[field] != actor.health.get("current_hp"):
				return false
		var action: Variant = actor.actor.runtime.get("action")
		if not action is Dictionary or not action.get("committed_geometry") is Array:
			return false
		var expected_facts := Registry.new()
		for candidate: Variant in action.committed_geometry:
			if not candidate is Dictionary or not expected_facts.register_fact(Actions.native_threat_fact(candidate)):
				return false
		for fact: Dictionary in expected_facts.snapshot():
			if registry.fact_snapshot(fact.hostile_source_id, fact.attack_generation) != fact:
				return false
		for fact: Dictionary in registry.snapshot():
			if str(fact.hostile_source_id) == source and int(fact.active_through_frame) >= frame and expected_facts.fact_snapshot(fact.hostile_source_id, fact.attack_generation).is_empty() and action.get("action_id") != "traitor_self_rewind":
				return false
	return registry.snapshot() == value.threats


func restore_cold_snapshot(value: Dictionary) -> bool:
	if _encounter != null or _flushing or not is_instance_valid(_player) or _facade == null or not _scene_resolver.is_valid():
		return false
	var target: Dictionary = _facade.current_room_restore_target()
	var scene_value: Variant = _scene_resolver.call()
	var frame: int = int(_player.priority_arbitration_snapshot().frame)
	if target.is_empty() or not scene_value is Node2D or not validate_cold_snapshot(value, str(_player.current_run_id()), str(target.node_id), frame):
		return false
	var expected: Dictionary = _facade.event_encounter_definition(str(_facade.call("_current_event_continuation").get("encounter_id", ""))) if target.room_type == "event" else _facade.current_encounter_definition()
	if value.definition != expected or value.run_seed != int(_facade.snapshot().run_seed):
		return false
	var original_threats: Array = _controller.hostile_threat_registry().snapshot()
	_scene = scene_value
	_template = target.template.duplicate(true)
	_definition = value.definition.duplicate(true)
	_run_seed = int(value.run_seed)
	_last_flushed_frame = frame
	_encounter = Encounter.new()
	_encounter.configure(_definition, value.encounter.identity)
	_encounter.restore_snapshot(value.encounter)
	_payload_root = Node2D.new()
	_payload_root.name = "NativeLaunchHostilePayloads"
	_controller.add_child(_payload_root)
	_effects = Effects.new()
	if not _effects.configure(str(_player.current_run_id()), int(value.encounter.identity.runtime_frame)) or not _effects.configure_native_payloads(_payload_root):
		return _reject_cold_restore(original_threats)
	for source: String in value.actors:
		var saved: Dictionary = value.actors[source]
		var spawn := _cold_spawn(_definition, str(value.encounter.roster[source].spawn_id))
		# Closed V1 actors carry no compiler binding; their original digest must still match.
		var affix_revision: int = saved.actor.get("affixes", {}).get("native_revision", 1)
		var actor := _instantiate_actor(spawn, saved.identity, Vector2(float(saved.actor.position.x), float(saved.actor.position.y)), spawn.elite and not saved.actor.has("affixes"), affix_revision)
		if actor == null:
			return _reject_cold_restore(original_threats)
		_actors[source] = actor
	var saved_registry := Registry.new()
	for retained: Dictionary in value.threats:
		saved_registry.register_fact(retained)
	for source: String in _actors:
		var actor: Node = _actors[source]
		if not actor.restore_native_cold_snapshot(value.actors[source], Callable(self, "_resolve_cold_source")):
			return _reject_cold_restore(original_threats)
		var expected_registry := Registry.new()
		for fact: Dictionary in actor.native_cold_threat_facts():
			if not expected_registry.register_fact(fact) or saved_registry.fact_snapshot(fact.hostile_source_id, fact.attack_generation) != fact:
				return _reject_cold_restore(original_threats)
		for fact: Dictionary in saved_registry.snapshot():
			if str(fact.hostile_source_id) == source and int(fact.active_through_frame) >= frame and expected_registry.fact_snapshot(fact.hostile_source_id, fact.attack_generation) != fact:
				return _reject_cold_restore(original_threats)
		actor.hostile_final_death.connect(_on_actor_final_death)
	if not _effects.bind_native_targets(_actors, {"player:1": _player}) or not _effects.restore_launch_transaction_snapshot(value.effects):
		return _reject_cold_restore(original_threats)
	_ledger = Ledger.new()
	_bridge = ProductionBridge.new()
	_bridge.native_boundary_ready = Callable(self, "_boundary_ready")
	if not _ledger.configure(_encounter, _effects) or not _bridge.configure(_player, _controller.hostile_threat_registry(), _actors.values(), _effects) or not _bridge.configure_encounter_authority(_ledger) or not _bridge._restore_registry(value.threats):
		return _reject_cold_restore(original_threats)
	_ledger.encounter_frame_observed.connect(_on_encounter_observed)
	if not matches_cold_snapshot(value) or not _player.configure_hostile_frame_participant(_bridge):
		return _reject_cold_restore(original_threats)
	return true


func matches_cold_snapshot(value: Dictionary) -> bool:
	if not value.get("actors") is Dictionary or value.actors.size() != _actors.size():
		return false
	var normalized := value.duplicate(true)
	for source: String in _actors:
		if not value.actors.has(source):
			return false
		var actor: Node = _actors[source]
		if actor.has_method("normalize_native_cold_snapshot"):
			var candidate: Dictionary = actor.normalize_native_cold_snapshot(value.actors[source])
			if candidate.is_empty():
				return false
			normalized.actors[source] = candidate
	return cold_snapshot() == normalized


func discard_cold_restore() -> bool:
	if _flushing or _bridge != null and _bridge.frame_transaction_is_active():
		return false
	_reject_cold_restore(_controller.hostile_threat_registry().snapshot())
	return not has_native_state()


func _reject_cold_restore(original_threats: Array) -> bool:
	var actors := _actors.values()
	var payload_root := _payload_root
	_clear_native()
	for actor: Node in actors:
		if is_instance_valid(actor):
			actor.free()
	if is_instance_valid(payload_root):
		payload_root.free()
	var registry: RefCounted = _controller.hostile_threat_registry()
	registry.clear()
	for row: Dictionary in original_threats:
		registry.register_fact(row)
	return false


static func _cold_spawn(definition: Dictionary, spawn_id: String) -> Dictionary:
	for wave: Dictionary in definition.get("waves", []):
		for spawn: Dictionary in wave.spawns:
			if spawn.id == spawn_id:
				return spawn.duplicate(true)
	return {}


func _cold_source_binding(source: Node) -> Dictionary:
	if not is_instance_valid(source):
		return {}
	for id: String in _actors:
		if _actors[id] == source:
			return {"kind": "hostile", "id": id}
	if source == _player:
		return {"kind": "player"}
	if _player.is_ancestor_of(source):
		var path := str(_player.get_path_to(source))
		if not path.contains("@") and not path.contains(".."):
			return {"kind": "player_path", "path": path}
	return {}


func _resolve_cold_source(binding: Dictionary) -> Node:
	if binding.get("kind") == "player" and binding.size() == 1:
		return _player
	if binding.get("kind") == "hostile" and binding.size() == 2 and binding.get("id") is String:
		return _actors.get(binding.id)
	if binding.get("kind") == "player_path" and binding.size() == 2 and binding.get("path") is String and not binding.path.is_empty() and not binding.path.begins_with("/") and not binding.path.contains("..") and not binding.path.contains("@"):
		return _player.get_node_or_null(binding.path)
	return null
