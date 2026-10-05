class_name HostileFrameBridge
extends RefCounted

const RegistryScript := preload("res://scripts/combat/hostile_threat_registry.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")

var _player: Node2D
var _registry: RefCounted
var _actors: Dictionary = {}
var _effects: RefCounted
var _encounter_authority: RefCounted
var _last_runtime_frame := -1
var _next_ticket_id := 1
var _active: Dictionary = {}
var _detached: Dictionary = {}
var _publishing := false


func configure(player: Node2D, registry: RefCounted, actors: Array, effects: RefCounted) -> bool:
	if not _active.is_empty() or not _detached.is_empty() or _publishing or not is_instance_valid(player) or registry == null or effects == null:
		return false
	if _encounter_authority != null and (player != _player or registry != _registry or effects != _effects):
		return false
	if not player.has_method("current_run_id") or str(player.call("current_run_id")).is_empty():
		return false
	for method: StringName in [&"snapshot", &"clear", &"register_fact"]:
		if not registry.has_method(method):
			return false
	for method: StringName in [&"prepare_effects", &"can_commit", &"commit", &"rollback", &"can_publish", &"publish_effect_observations"]:
		if not effects.has_method(method):
			return false
	var candidate: Dictionary = {}
	for value: Variant in actors:
		if not value is Node2D or not is_instance_valid(value):
			return false
		var actor := value as Node2D
		for method: StringName in [&"launch_runtime_snapshot", &"launch_transaction_snapshot", &"can_restore_launch_transaction_snapshot", &"restore_launch_transaction_snapshot", &"discard_launch_transaction_snapshot", &"prepare_launch_frame", &"can_commit_launch_frame", &"commit_launch_frame", &"can_publish_launch_frame", &"publish_launch_frame"]:
			if not actor.has_method(method):
				return false
		var state: Dictionary = actor.call("launch_runtime_snapshot")
		var source_id := str(actor.get("hostile_source_id"))
		if not _valid_runtime_id(source_id) or candidate.has(source_id) or state.is_empty() or str(state.runtime.identity.run_id) != str(player.call("current_run_id")) or (not bool(state.runtime.terminal) and int(state.runtime.runtime_frame) != int(player.get("_runtime_frame"))):
			return false
		var health := actor.get_node_or_null("HealthComponent")
		if health == null:
			return false
		for method: StringName in [&"begin_frame_signal_transaction", &"prepare_frame_signal_publication", &"finalize_frame_signal_publication", &"discard_finalized_frame_signal_publication", &"publish_prepared_frame_signals", &"rollback_frame_signal_transaction"]:
			if not health.has_method(method):
				return false
		candidate[source_id] = actor
	_player = player
	_registry = registry
	_actors = candidate
	_effects = effects
	_last_runtime_frame = int(player.get("_runtime_frame"))
	for actor: Node2D in _actors.values():
		if actor.has_method("configure_hostile_threat_authority") and not bool(actor.call("configure_hostile_threat_authority", registry, Callable(self, "_current_runtime_frame"))):
			return false
		if actor.has_method("bind_native_construct_budget") and effects.has_method("arena_debris_active_count") and not actor.bind_native_construct_budget(effects):
			return false
	return is_ready_for_frame(_last_runtime_frame + 1)


func register_actor(actor: Node2D) -> bool:
	if frame_transaction_is_active() or not is_instance_valid(_player) or not is_instance_valid(actor) or not actor.has_method("launch_runtime_snapshot"):
		return false
	var source_id := str(actor.get("hostile_source_id"))
	var state: Dictionary = actor.call("launch_runtime_snapshot")
	if not _valid_runtime_id(source_id) or _actors.has(source_id) or state.is_empty() or bool(state.runtime.terminal) or str(state.runtime.identity.run_id) != str(_player.call("current_run_id")) or int(state.runtime.runtime_frame) != _last_runtime_frame:
		return false
	var next_actors := _actors.values()
	next_actors.append(actor)
	return configure(_player, _registry, next_actors, _effects)


func configure_encounter_authority(authority: RefCounted) -> bool:
	if frame_transaction_is_active() or _encounter_authority != null or authority == null or not is_instance_valid(_player):
		return false
	for method: StringName in [&"owns_effects", &"is_ready_for_frame", &"launch_transaction_snapshot", &"restore_launch_transaction_snapshot", &"prepare_frame", &"can_commit", &"commit", &"rollback", &"can_publish", &"seal_frame_publication", &"publish_frame_observations"]:
		if not authority.has_method(method):
			return false
	if not authority.owns_effects(_effects, str(_player.call("current_run_id"))) or not authority.is_ready_for_frame(_last_runtime_frame + 1):
		return false
	_encounter_authority = authority
	return true


func retire_actor(source_id: String) -> bool:
	if frame_transaction_is_active() or not _actors.has(source_id):
		return false
	var actor: Node2D = _actors[source_id]
	if not is_instance_valid(actor) or not bool((actor.call("launch_runtime_snapshot") as Dictionary).runtime.terminal):
		return false
	_actors.erase(source_id)
	return true


func is_ready_for_frame(runtime_frame: int) -> bool:
	if not is_instance_valid(_player) or _registry == null or _effects == null or not _active.is_empty() or not _detached.is_empty() or _publishing or runtime_frame != _last_runtime_frame + 1:
		return false
	if _encounter_authority != null and not _encounter_authority.is_ready_for_frame(runtime_frame):
		return false
	for source_id: String in _sorted_sources():
		var actor: Node2D = _actors[source_id]
		if not is_instance_valid(actor):
			return false
		var state: Dictionary = actor.call("launch_runtime_snapshot")
		if state.is_empty() or str(state.runtime.identity.run_id) != str(_player.call("current_run_id")):
			return false
		if not bool(state.runtime.terminal) and int(state.runtime.runtime_frame) != _last_runtime_frame:
			return false
	return true


func frame_transaction_is_active() -> bool:
	return not _active.is_empty() or not _detached.is_empty() or _publishing


func begin_frame(runtime_frame: int) -> Dictionary:
	if not is_ready_for_frame(runtime_frame):
		return {}
	var ticket := {"owner_instance_id": get_instance_id(), "ticket_id": _next_ticket_id, "runtime_frame": runtime_frame}
	_next_ticket_id += 1
	_active = {"ticket": ticket.duplicate(true), "registry_before": _registry.call("snapshot"), "effects_checkpoint": {}, "encounter_checkpoint": {}, "encounter_ticket": {}, "records": [], "effect_ticket": {}, "prepared": false, "publication": {}, "finalized": false}
	# These checkpoints precede weapon/world hits, not merely hostile movement.
	if _encounter_authority != null:
		_active.encounter_checkpoint = _encounter_authority.launch_transaction_snapshot()
		if _active.encounter_checkpoint.is_empty():
			rollback_frame(ticket)
			return {}
	if _effects.has_method("launch_transaction_snapshot") and _effects.has_method("restore_launch_transaction_snapshot"):
		_active.effects_checkpoint = _effects.call("launch_transaction_snapshot")
		if _active.effects_checkpoint.is_empty():
			rollback_frame(ticket)
			return {}
	for source_id: String in _sorted_sources():
		var actor: Node2D = _actors[source_id]
		var state: Dictionary = actor.call("launch_runtime_snapshot")
		if bool(state.runtime.terminal):
			continue
		var checkpoint: Dictionary = actor.call("launch_transaction_snapshot")
		if checkpoint.is_empty():
			rollback_frame(ticket)
			return {}
		var health := actor.get_node("HealthComponent")
		var record := {"source_id": source_id, "actor": actor, "health": health, "checkpoint": checkpoint, "health_ticket": {}, "actor_ticket": {}, "health_publication": {}, "health_finalized": false}
		_active.records.append(record)
		var health_ticket: Dictionary = health.call("begin_frame_signal_transaction", runtime_frame)
		if health_ticket.is_empty():
			rollback_frame(ticket)
			return {}
		record.health_ticket = health_ticket
	return ticket.duplicate(true)


func prepare_frame(ticket: Dictionary) -> bool:
	if not _matches(ticket) or bool(_active.prepared):
		return false
	_active.prepared = true
	var batches: Array[Dictionary] = []
	var target_id := _player_target_id()
	# Grants enter recipient controls before this frame builds its attack facts.
	for record: Dictionary in _active.records:
		if record.actor.has_method("settle_launch_chaining") and not record.actor.settle_launch_chaining(_actors, int(ticket.runtime_frame), self):
			return false
	for record: Dictionary in _active.records:
		var actor: Node2D = record.actor
		if not is_instance_valid(actor):
			return false
		var facing := actor.global_position.direction_to(_player.global_position)
		if facing.is_zero_approx():
			facing = Vector2.RIGHT
		var result: Dictionary = actor.call("prepare_launch_frame", int(ticket.runtime_frame), {
			"runtime_frame": int(ticket.runtime_frame), "source_position": _point(actor.global_position),
			"target_position": _point(_player.global_position), "facing_direction": _point(facing), "target_id": target_id,
		})
		if not bool(result.get("ok", false)) or not result.get("ticket") is Dictionary or not result.get("batch") is Dictionary:
			return false
		record.actor_ticket = result.ticket.duplicate(true)
		batches.append({"hostile_source_id": record.source_id, "batch": result.batch.duplicate(true)})
	var context := {"run_id": str(_player.call("current_run_id")), "runtime_frame": int(ticket.runtime_frame), "threat_registry": _registry, "actors": _actors.duplicate(), "targets": {target_id: _player}}
	var prepared: Dictionary = _effects.call("prepare_effects", batches, context)
	if not bool(prepared.get("ok", false)) or not prepared.get("ticket") is Dictionary:
		return false
	_active.effect_ticket = prepared.ticket.duplicate(true)
	if not bool(_effects.call("can_commit", _active.effect_ticket)):
		return false
	if _encounter_authority != null:
		var encounter_prepared: Dictionary = _encounter_authority.prepare_frame(_active.effect_ticket)
		if not encounter_prepared.ok:
			return false
		_active.encounter_ticket = encounter_prepared.ticket.duplicate(true)
		if not _encounter_authority.can_commit(_active.encounter_ticket):
			return false
	for record: Dictionary in _active.records:
		if not bool(record.actor.call("can_commit_launch_frame", record.actor_ticket)):
			return false
	for record: Dictionary in _active.records:
		if not bool(record.actor.call("commit_launch_frame", record.actor_ticket)):
			return false
	var committed: Dictionary = _effects.call("commit", _active.effect_ticket)
	return bool(committed.get("ok", false)) and (_encounter_authority == null or _encounter_authority.commit(_active.encounter_ticket))


func owns_launch_chaining_context(actor: Node2D, actors: Dictionary, frame: int) -> bool:
	return not _active.is_empty() and bool(_active.prepared) and not _publishing and frame == int(_active.ticket.runtime_frame) and actors == _actors and _actors.get(str(actor.get("hostile_source_id"))) == actor and _active.effect_ticket.is_empty()


func prepare_frame_publication(ticket: Dictionary) -> Dictionary:
	if not _matches(ticket) or not bool(_active.prepared) or _active.effect_ticket.is_empty() or not bool(_effects.call("can_publish", _active.effect_ticket)):
		return {}
	if _encounter_authority != null and not _encounter_authority.can_publish(_active.encounter_ticket):
		return {}
	if not _active.publication.is_empty():
		return _active.publication.duplicate(true)
	var publications: Array[Dictionary] = []
	for record: Dictionary in _active.records:
		var publication: Dictionary = record.health.call("prepare_frame_signal_publication", record.health_ticket)
		if publication.is_empty() or not bool(record.actor.call("can_restore_launch_transaction_snapshot", record.checkpoint)) or not bool(record.actor.call("can_publish_launch_frame", record.actor_ticket)):
			return {}
		record.health_publication = publication.duplicate(true)
		publications.append({"hostile_source_id": record.source_id, "publication": publication.duplicate(true)})
	var result := {"owner_instance_id": get_instance_id(), "ticket": ticket.duplicate(true), "health_publications": publications}
	_active.publication = result.duplicate(true)
	return result.duplicate(true)


func finalize_frame_publication(publication: Dictionary) -> bool:
	if not _publication_matches(publication) or bool(_active.finalized):
		return false
	for record: Dictionary in _active.records:
		if not bool(record.health.call("finalize_frame_signal_publication", record.health_publication)):
			return false
		record.health_finalized = true
		if not bool(record.actor.call("publish_launch_frame", record.actor_ticket)):
			return false
	_active.finalized = true
	return true


func seal_frame_publication(publication: Dictionary) -> bool:
	if not _publication_matches(publication) or not bool(_active.finalized):
		return false
	if _encounter_authority != null and not _encounter_authority.can_publish(_active.encounter_ticket):
		return false
	for record: Dictionary in _active.records:
		if not bool(record.actor.call("can_restore_launch_transaction_snapshot", record.checkpoint)):
			return false
	for record: Dictionary in _active.records:
		if not bool(record.actor.call("discard_launch_transaction_snapshot", record.checkpoint)):
			return false
		if bool((record.actor.call("launch_runtime_snapshot") as Dictionary).runtime.terminal):
			_actors.erase(record.source_id)
	if _encounter_authority != null and not _encounter_authority.seal_frame_publication(_active.encounter_ticket):
		return false
	_last_runtime_frame = int(_active.ticket.runtime_frame)
	_detached = {"records": _active.records.duplicate(), "effect_ticket": _active.effect_ticket.duplicate(true), "encounter_ticket": _active.encounter_ticket.duplicate(true)}
	_active.clear()
	return true


func publish_prepared_frame() -> void:
	if _detached.is_empty() or _publishing:
		return
	var publication := _detached.duplicate()
	_detached.clear()
	_publishing = true
	if not bool(_effects.call("publish_effect_observations", publication.effect_ticket)):
		push_error("Sealed hostile effect publication failed closed")
	for record: Dictionary in publication.records:
		if is_instance_valid(record.health):
			record.health.call("publish_prepared_frame_signals")
	if _encounter_authority != null and not _encounter_authority.publish_frame_observations(publication.encounter_ticket):
		push_error("Sealed hostile encounter publication failed closed")
	_publishing = false


func rollback_frame(ticket: Dictionary) -> bool:
	if not _matches(ticket):
		return false
	var restored := true
	if _encounter_authority != null:
		if not _active.encounter_ticket.is_empty():
			restored = _encounter_authority.rollback(_active.encounter_ticket) and restored
		if not _active.encounter_checkpoint.is_empty():
			restored = _encounter_authority.restore_launch_transaction_snapshot(_active.encounter_checkpoint) and restored
	if not _active.effect_ticket.is_empty():
		restored = bool(_effects.call("rollback", _active.effect_ticket)) and restored
	if not _active.effects_checkpoint.is_empty():
		restored = bool(_effects.call("restore_launch_transaction_snapshot", _active.effects_checkpoint)) and restored
	for record: Dictionary in _active.records:
		if not is_instance_valid(record.actor) or not is_instance_valid(record.health):
			restored = false
			continue
		if bool(record.health_finalized):
			restored = bool(record.health.call("discard_finalized_frame_signal_publication", record.health_publication)) and restored
		elif not record.health_ticket.is_empty():
			restored = bool(record.health.call("rollback_frame_signal_transaction", record.health_ticket)) and restored
		restored = bool(record.actor.call("restore_launch_transaction_snapshot", record.checkpoint)) and restored
	restored = _restore_registry(_active.registry_before) and restored
	_active.clear()
	return restored


func _restore_registry(rows: Array) -> bool:
	var validated := RegistryScript.new()
	for row: Variant in rows:
		if not validated.register_fact(row):
			return false
	_registry.call("clear")
	for row: Dictionary in validated.snapshot():
		if not bool(_registry.call("register_fact", row)):
			return false
	return _registry.call("snapshot") == rows


func _matches(ticket: Dictionary) -> bool:
	return not _active.is_empty() and ticket == _active.ticket


func _publication_matches(publication: Dictionary) -> bool:
	return not _active.is_empty() and not _active.publication.is_empty() and publication == _active.publication


func _sorted_sources() -> Array:
	var sources := _actors.keys()
	sources.sort()
	return sources


func _player_target_id() -> String:
	for key: StringName in [&"stable_target_key", &"encounter_spawn_id"]:
		if _player.has_meta(key) and _valid_runtime_id(str(_player.get_meta(key))):
			return str(_player.get_meta(key))
	return "player:1"


func _current_runtime_frame() -> int:
	return int(_player.get("_runtime_frame")) if is_instance_valid(_player) else _last_runtime_frame


static func _valid_runtime_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code not in [45, 46, 58, 95]:
			return false
	return true


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
