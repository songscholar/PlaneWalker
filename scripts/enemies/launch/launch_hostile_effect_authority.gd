class_name LaunchHostileEffectAuthority
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const CONTEXT_FIELDS: Array[String] = ["run_id", "runtime_frame", "threat_registry", "actors", "targets"]
const TICKET_FIELDS: Array[String] = ["ticket_id", "run_id", "runtime_frame", "before", "after", "registry_before", "registry_after", "registry_operations", "damage_records", "source_batches", "actors", "targets", "threat_registry"]
const MAX_CLAIMS := 4096

var _state: Dictionary = {}
var _pending: Dictionary = {}
var _next_ticket_id := 1
var _committed := false
var _publishing := false
var _owned_signals: Array[Dictionary] = []


func configure(run_id: String, runtime_frame: int = 0) -> bool:
	if not _pending.is_empty() or _publishing or not _stable_id(run_id) or runtime_frame < 0:
		return false
	_state = {"schema_version": 1, "run_id": run_id, "runtime_frame": runtime_frame, "claims": []}
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func can_commit(ticket: Dictionary) -> bool:
	return can_commit_effects(ticket)


func commit(ticket: Dictionary) -> Dictionary:
	return commit_effects(ticket)


func rollback(ticket: Dictionary) -> bool:
	return rollback_effects(ticket)


func can_publish(ticket: Dictionary) -> bool:
	return can_publish_effects(ticket)


func publish_effect_observations(ticket: Dictionary) -> bool:
	return publish_effects(ticket)


func prepare_effects(batches: Array, context: Dictionary) -> Dictionary:
	if _state.is_empty() or not _pending.is_empty() or _publishing or not Contract.exact_fields(context, CONTEXT_FIELDS):
		return _failure("unavailable_or_context")
	if context.run_id != _state.run_id or typeof(context.runtime_frame) != TYPE_INT or context.runtime_frame != int(_state.runtime_frame) + 1:
		return _failure("runtime_frame")
	var registry: Variant = context.threat_registry
	if not registry is RefCounted or not registry.has_method("snapshot") or not registry.has_method("extend_fact_through") or not context.actors is Dictionary or not context.targets is Dictionary or batches.size() > 32:
		return _failure("native_authorities")
	var registry_before: Array = registry.snapshot()
	var projected: RefCounted = Registry.new()
	if not _install_registry(projected, registry_before):
		return _failure("registry_snapshot")
	var next := snapshot()
	next.runtime_frame = context.runtime_frame
	var operations: Array[Dictionary] = []
	var damages: Array[Dictionary] = []
	var previous_source := ""
	for candidate: Variant in batches:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, ["hostile_source_id", "batch"]):
			return _failure("batch_wrapper")
		var source: Variant = candidate.hostile_source_id
		if not _stable_id(source) or str(source) <= previous_source or not context.actors.has(source) or not candidate.batch is Dictionary:
			return _failure("batch_source")
		previous_source = source
		var actor: Variant = context.actors[source]
		if not actor is Node2D or not is_instance_valid(actor) or not actor.has_method("prepared_launch_frame_batch") or str(actor.get("hostile_source_id")) != source or actor.prepared_launch_frame_batch() != candidate.batch:
			return _failure("unsealed_actor_batch")
		var batch: Dictionary = candidate.batch
		if batch.get("runtime_frame", -1) != context.runtime_frame or not _valid_batch_arrays(batch):
			return _failure("batch_frame_or_arrays")
		for fact_value: Variant in batch.threat_facts:
			if not fact_value is Dictionary:
				return _failure("threat_fact")
			var fact := Actions.native_threat_fact(fact_value)
			if fact.is_empty() or str(fact.hostile_source_id) != source or not projected.register_fact(fact):
				return _failure("threat_registration")
			operations.append({"kind": "register", "fact": fact})
		for extension: Variant in batch.threat_extensions:
			if not extension is Dictionary or not Contract.exact_fields(extension, ["hostile_source_id", "attack_generation", "expected_through_frame", "new_through_frame"]) or str(extension.hostile_source_id) != source:
				return _failure("threat_extension")
			for field: String in ["attack_generation", "expected_through_frame", "new_through_frame"]:
				if typeof(extension[field]) != TYPE_INT:
					return _failure("threat_extension_integer")
			if not projected.extend_fact_through(StringName(source), extension.attack_generation, extension.expected_through_frame, extension.new_through_frame):
				return _failure("threat_extension_stale")
			operations.append({"kind": "extend", "extension": extension.duplicate(true)})
		for generation: Variant in batch.retired_generations:
			if typeof(generation) != TYPE_INT or generation <= 0 or not projected.retire(StringName(source), generation):
				return _failure("threat_retirement")
			operations.append({"kind": "retire", "source": source, "generation": generation})
		for request: Variant in batch.effect_requests:
			if not request is Dictionary or request.get("handler_id", "") != "melee" or str(request.get("hostile_source_id", "")) != source:
				return _failure("unimplemented_effect_handler")
		if not batch.get("mechanism_requests", []) is Array or not (batch.get("mechanism_requests", []) as Array).is_empty():
			return _failure("unimplemented_mechanism_handler")
		for hit: Variant in batch.hit_facts:
			var prepared := _prepare_hit(hit, source, actor, context, next)
			if not prepared.ok:
				return prepared
			damages.append(prepared.record)
		for tick: Variant in batch.status_tick_requests:
			var prepared := _prepare_status_tick(tick, source, actor, context, next)
			if not prepared.ok:
				return prepared
			damages.append(prepared.record)
	while next.claims.size() > MAX_CLAIMS:
		next.claims.pop_front()
	var ticket := {"ticket_id": _next_ticket_id, "run_id": context.run_id, "runtime_frame": context.runtime_frame, "before": snapshot(), "after": next, "registry_before": registry_before, "registry_after": projected.snapshot(), "registry_operations": operations, "damage_records": damages, "source_batches": batches.duplicate(true), "actors": context.actors.duplicate(), "targets": context.targets.duplicate(), "threat_registry": registry}
	_next_ticket_id += 1
	_pending = ticket.duplicate(true)
	_committed = false
	_owned_signals.clear()
	return {"ok": true, "ticket": ticket.duplicate(true)}


func can_commit_effects(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or _committed or _publishing or snapshot() != ticket.before or ticket.threat_registry.snapshot() != ticket.registry_before:
		return false
	for wrapper: Dictionary in ticket.source_batches:
		var actor: Node = ticket.actors[wrapper.hostile_source_id]
		if not is_instance_valid(actor) or actor.prepared_launch_frame_batch() != wrapper.batch:
			return false
	for record: Dictionary in ticket.damage_records:
		if not is_instance_valid(record.target) or not is_instance_valid(record.health) or not _target_position_matches(record, ticket.runtime_frame) or _health_observation(record.health) != record.health_before:
			return false
	return true


func commit_effects(ticket: Dictionary) -> Dictionary:
	if not can_commit_effects(ticket):
		return _failure("stale_commit")
	var seen_health: Dictionary = {}
	for record: Dictionary in ticket.damage_records:
		var health: Node = record.health
		if record.info == null or seen_health.has(health):
			continue
		seen_health[health] = true
		if not health.frame_signal_transaction_is_active():
			var signal_ticket: Dictionary = health.begin_frame_signal_transaction(ticket.runtime_frame)
			if signal_ticket.is_empty():
				return _failure("health_buffer_begin")
			_owned_signals.append({"health": health, "ticket": signal_ticket, "publication": {}})
	for operation: Dictionary in ticket.registry_operations:
		if not _apply_registry_operation(ticket.threat_registry, operation):
			return _failure("registry_commit")
	var resolutions: Array = []
	for record: Dictionary in ticket.damage_records:
		if record.info == null:
			continue
		var resolution: RefCounted = record.health.resolve_and_apply_damage(record.info)
		if resolution == null:
			return _failure("health_resolution")
		resolutions.append(resolution.snapshot())
	for owned: Dictionary in _owned_signals:
		var publication: Dictionary = owned.health.prepare_frame_signal_publication(owned.ticket)
		if publication.is_empty() or not owned.health.finalize_frame_signal_publication(publication):
			return _failure("health_publication")
		owned.publication = publication
	_state = ticket.after.duplicate(true)
	_committed = true
	return {"ok": true, "resolutions": resolutions}


func rollback_effects(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or _publishing:
		return false
	var ok := true
	for owned: Dictionary in _owned_signals:
		if owned.publication.is_empty():
			ok = bool(owned.health.rollback_frame_signal_transaction(owned.ticket)) and ok
		else:
			ok = bool(owned.health.discard_finalized_frame_signal_publication(owned.publication)) and ok
	if not _install_registry(ticket.threat_registry, ticket.registry_before):
		ok = false
	_state = ticket.before.duplicate(true)
	_pending.clear()
	_owned_signals.clear()
	_committed = false
	return ok


func can_publish_effects(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or not _committed or _publishing:
		return false
	for owned: Dictionary in _owned_signals:
		if not is_instance_valid(owned.health) or not bool(owned.health.call("_finalized_frame_signal_publication_matches", owned.publication)):
			return false
	return true


func publish_effects(ticket: Dictionary) -> bool:
	if not can_publish_effects(ticket):
		return false
	var publications := _owned_signals.duplicate(true)
	_publishing = true
	_pending.clear()
	_owned_signals.clear()
	_committed = false
	for owned: Dictionary in publications:
		owned.health.publish_prepared_frame_signals()
	_publishing = false
	return true


func _prepare_hit(value: Variant, source: String, actor: Node2D, context: Dictionary, next: Dictionary) -> Dictionary:
	if not value is Dictionary or not Contract.exact_fields(value, ["run_id", "hostile_source_id", "attack_generation", "hit_index", "runtime_frame", "target_id", "action_id", "damage", "damage_type", "handler_id", "geometry", "parameters"]):
		return _failure("hit_fields")
	var hit := value as Dictionary
	if hit.run_id != context.run_id or str(hit.hostile_source_id) != source or hit.runtime_frame != context.runtime_frame or hit.handler_id != "melee" or hit.damage_type not in Contract.DAMAGE_TYPES or not context.targets.has(hit.target_id) or not hit.geometry is Array or hit.geometry.is_empty():
		return _failure("hit_identity_or_handler")
	var target: Variant = context.targets[hit.target_id]
	var record := _target_record(target)
	if record.is_empty():
		return _failure("hit_target")
	var envelope: RefCounted = Registry.new()
	for primitive: Variant in hit.geometry:
		if not primitive is Dictionary:
			return _failure("hit_geometry")
		var fact := Actions.native_threat_fact(primitive)
		if fact.is_empty() or str(fact.hostile_source_id) != source or not envelope.register_fact(fact):
			return _failure("hit_geometry")
	var claim := _claim(context.run_id, str(hit.target_id), source, int(hit.attack_generation), int(hit.hit_index))
	if next.claims.has(claim):
		return _failure("duplicate_hit")
	next.claims.append(claim)
	var info: RefCounted
	if envelope.contains_point(target.global_position, context.runtime_frame):
		var primitive: Dictionary = hit.geometry[0]
		var direction := _vector(primitive.origin).direction_to(_vector(primitive.target_point))
		if direction.is_zero_approx():
			direction = _vector(primitive.aim_direction)
		info = Damage.from_plan({"run_id": context.run_id, "target_id": hit.target_id, "hostile_source_id": source, "attack_generation": hit.attack_generation, "hit_index": hit.hit_index, "action_token": hit.attack_generation, "amount": hit.damage, "damage_type": Contract.DAMAGE_TYPES.find(hit.damage_type), "source": actor, "attacker": actor, "can_crit": false, "knockback": direction * float(hit.parameters.knockback_px), "tags": ["enemy:launch", "enemy:melee"], "source_generation": hit.attack_generation})
		if info == null:
			return _failure("damage_plan")
	record["info"] = info
	return {"ok": true, "record": record}


func _prepare_status_tick(value: Variant, target_id: String, actor: Node2D, context: Dictionary, next: Dictionary) -> Dictionary:
	if not value is Dictionary or not Contract.exact_fields(value, ["effect_id", "source_id", "generation", "tick_index", "damage", "damage_source", "damage_attacker"]) or str(value.effect_id) != "burn":
		return _failure("status_tick")
	var tick := value as Dictionary
	var record := _target_record(actor)
	if record.is_empty() or not Contract.integer_in_range(tick.generation, 0, 2147483646) or not Contract.integer_in_range(tick.tick_index, 0, 2147483646) or not Contract.number_in_range(tick.damage, 0.000001, 1000000.0):
		return _failure("status_tick_value")
	record["target_position_after"] = actor.prepared_launch_frame_position()
	var damage_source_id := "status:%s" % ("%s|%d|burn" % [tick.source_id, tick.generation]).sha256_text().substr(0, 40)
	var generation := int(tick.generation) + 1
	var claim := _claim(context.run_id, target_id, damage_source_id, generation, int(tick.tick_index))
	if next.claims.has(claim):
		return _failure("duplicate_status_tick")
	next.claims.append(claim)
	var info := Damage.from_plan({"run_id": context.run_id, "target_id": target_id, "hostile_source_id": damage_source_id, "attack_generation": generation, "hit_index": tick.tick_index, "action_token": generation, "amount": tick.damage, "damage_type": Damage.DamageType.FIRE, "source": _live_node(tick.damage_source), "attacker": _live_node(tick.damage_attacker), "can_crit": false, "tags": ["weapon:staff", "element:fire", "status:burn", "status_source:%s" % tick.source_id, "status_generation:%d" % tick.generation], "source_generation": tick.generation})
	if info == null:
		return _failure("status_damage_plan")
	record["info"] = info
	return {"ok": true, "record": record}


func _target_record(target: Variant) -> Dictionary:
	if not target is Node2D or not is_instance_valid(target) or not target.has_node("HealthComponent"):
		return {}
	var health: Node = target.get_node("HealthComponent")
	if not health.has_method("resolve_and_apply_damage") or str(health.irreversible_run_id()) != _state.run_id:
		return {}
	return {"target": target, "health": health, "target_position": target.global_position, "health_before": _health_observation(health)}


static func _health_observation(health: Node) -> Dictionary:
	return {"runtime": health.runtime_state_snapshot(), "defense": health.defense, "invulnerable": health.invulnerable, "accessibility_multiplier": health.damage_received_multiplier}


static func _target_position_matches(record: Dictionary, runtime_frame: int) -> bool:
	var expected: Vector2 = record.target_position
	if record.has("target_position_after") and int(record.target.launch_runtime_snapshot().runtime.runtime_frame) == runtime_frame:
		expected = record.target_position_after
	return record.target.global_position == expected


static func _valid_batch_arrays(batch: Dictionary) -> bool:
	for field: String in ["threat_facts", "threat_extensions", "retired_generations", "hit_facts", "effect_requests", "status_tick_requests"]:
		if not batch.has(field) or not batch[field] is Array or batch[field].size() > 128:
			return false
	return true


static func _apply_registry_operation(registry: RefCounted, operation: Dictionary) -> bool:
	match operation.kind:
		"register": return registry.register_fact(operation.fact)
		"retire": return registry.retire(StringName(operation.source), int(operation.generation))
		"extend":
			var row: Dictionary = operation.extension
			return registry.extend_fact_through(StringName(row.hostile_source_id), row.attack_generation, row.expected_through_frame, row.new_through_frame)
	return false


static func _install_registry(registry: RefCounted, facts: Array) -> bool:
	registry.clear()
	for fact: Dictionary in facts:
		if not registry.register_fact(fact):
			return false
	return true


func _ticket_matches(ticket: Dictionary) -> bool:
	return Contract.exact_fields(ticket, TICKET_FIELDS) and not _pending.is_empty() and ticket == _pending


static func _claim(run_id: String, target_id: String, source: String, generation: int, hit_index: int) -> String:
	return JSON.stringify([run_id, target_id, source, generation, hit_index]).sha256_text()


static func _live_node(value: Variant) -> Node:
	return value as Node if is_instance_valid(value) and value is Node else null


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _stable_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value == value.strip_edges() and value.length() <= 64


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_EFFECT_INVALID", "context": {"field": field}}
