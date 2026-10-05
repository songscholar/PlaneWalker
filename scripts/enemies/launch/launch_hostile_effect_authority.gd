class_name LaunchHostileEffectAuthority
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Payloads := preload("res://scripts/enemies/launch/launch_hostile_payload_authority.gd")
const Semantics := preload("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
const Summons := preload("res://scripts/enemies/launch/launch_summon_authority.gd")
const CONTEXT_FIELDS: Array[String] = ["run_id", "runtime_frame", "threat_registry", "actors", "targets"]
const TICKET_FIELDS: Array[String] = ["ticket_id", "run_id", "runtime_frame", "before", "after", "registry_before", "registry_after", "registry_operations", "damage_records", "health_records", "source_batches", "actors", "targets", "threat_registry", "payload_ticket", "semantic_ticket", "summon_ticket"]
const MAX_CLAIMS := 4096

var _state: Dictionary = {}
var _pending: Dictionary = {}
var _next_ticket_id := 1
var _committed := false
var _publishing := false
var _owned_signals: Array[Dictionary] = []
var _payloads: RefCounted = Payloads.new()
var _semantics: RefCounted = Semantics.new()
var _summons: RefCounted = Summons.new()
var _owned_void_resources: Array[Dictionary] = []


func configure(run_id: String, runtime_frame: int = 0) -> bool:
	if not _pending.is_empty() or _publishing or not _stable_id(run_id) or runtime_frame < 0 or not _payloads.configure(run_id, runtime_frame) or not _semantics.configure(run_id, runtime_frame) or not _summons.configure(run_id, runtime_frame):
		return false
	_state = {"schema_version": 2, "run_id": run_id, "runtime_frame": runtime_frame, "claims": []}
	return true


func snapshot() -> Dictionary:
	var result := _state.duplicate(true)
	if not result.is_empty():
		result["payloads"] = _payloads.snapshot()
		result["semantics"] = _semantics.snapshot()
		result["summons"] = _summons.snapshot()
	return result


func configure_native_payloads(root: Node2D) -> bool:
	return not _state.is_empty() and _pending.is_empty() and _payloads.configure_native_root(root) and _semantics.configure_native_root(root) and _summons.configure_native_root(root)


func summon_snapshot() -> Dictionary:
	return _summons.snapshot()


func native_summon_actors() -> Dictionary:
	return _summons.native_actors()


func configure_native_summon_room(room: Node2D, template: Dictionary) -> bool:
	return not _state.is_empty() and _pending.is_empty() and _summons.configure_native_room(room, template)


func restore_native_summon_snapshot(value: Dictionary) -> bool:
	return not _state.is_empty() and _pending.is_empty() and not _publishing and _summons.restore_snapshot(value)


func capture_native_terminal_split(owner: Node2D, receipt: String, targets: Dictionary) -> bool:
	return not _state.is_empty() and _pending.is_empty() and not _publishing and _summons.capture_native_terminal_split(owner, receipt, targets)


func payload_snapshot() -> Dictionary:
	return _payloads.snapshot()


func native_payload_nodes() -> Array[Node2D]:
	return _payloads.native_nodes()


func native_debris_nodes() -> Array[Node2D]:
	return _payloads.native_debris_nodes()


func arena_debris_active_count() -> int:
	return _payloads.debris_active_count()


func semantic_snapshot() -> Dictionary:
	return _semantics.snapshot()


func native_semantic_nodes() -> Array[Node2D]:
	return _semantics.native_nodes()


func bind_native_targets(actors: Dictionary, targets: Dictionary) -> bool:
	return not _state.is_empty() and _pending.is_empty() and not _publishing and _semantics.bind_native_targets(actors, targets) and _summons.bind_native_targets(actors)


func dispose_native_effects() -> bool:
	return not _state.is_empty() and _pending.is_empty() and not _publishing and _semantics.dispose_native_effects() and _summons.dispose_native_effects()


func work_snapshot() -> Dictionary:
	return _work_snapshot(snapshot()) if not _state.is_empty() else {}


func prepared_work_transition(ticket: Dictionary) -> Dictionary:
	return {"before": _work_snapshot(ticket.before), "after": _work_snapshot(ticket.after)} if _ticket_matches(ticket) and not _publishing else {}


func prepared_payload_transition(ticket: Dictionary) -> Dictionary:
	if not _ticket_matches(ticket) or _publishing:
		return {}
	return {"before": ticket.payload_ticket.before.duplicate(true), "after": ticket.payload_ticket.after.duplicate(true)}


func launch_transaction_snapshot() -> Dictionary:
	return snapshot() if _pending.is_empty() and not _publishing else {}


func can_restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	value = normalize_transaction_snapshot(value)
	if value.is_empty() or not Contract.exact_fields(value, ["schema_version", "run_id", "runtime_frame", "claims", "payloads", "semantics", "summons"]) or value.schema_version != 2 or value.run_id != _state.run_id or typeof(value.runtime_frame) != TYPE_INT or not value.claims is Array or value.claims.size() > MAX_CLAIMS or not value.payloads is Dictionary or not _payloads.can_restore_transaction_snapshot(value.payloads) or not value.semantics is Dictionary or not _semantics.can_restore_transaction_snapshot(value.semantics) or not value.summons is Dictionary or not _summons.can_restore_snapshot(value.summons):
		return false
	var seen: Dictionary = {}
	for claim: Variant in value.claims:
		if typeof(claim) != TYPE_STRING or claim.length() != 64 or not claim.is_valid_hex_number(false) or seen.has(claim):
			return false
		seen[claim] = true
	return value.runtime_frame == value.payloads.runtime_frame and value.runtime_frame == value.semantics.runtime_frame and value.runtime_frame == value.summons.runtime_frame and _payload_active_zone_count(value.payloads) + _semantics.active_zone_count_for_snapshot(value.semantics, int(value.runtime_frame)) <= 12


static func normalize_transaction_snapshot(value: Dictionary) -> Dictionary:
	if typeof(value.get("schema_version")) != TYPE_INT:
		return {}
	if value.schema_version == 2:
		return value.duplicate(true)
	if value.schema_version != 1 or not Contract.exact_fields(value, ["schema_version", "run_id", "runtime_frame", "claims", "payloads", "semantics"]) or not value.semantics is Dictionary or not value.semantics.has("initial_frame"):
		return {}
	var migrated := value.duplicate(true)
	migrated.schema_version = 2
	migrated["summons"] = {"schema_version": 1, "run_id": value.run_id, "initial_frame": value.semantics.initial_frame, "runtime_frame": value.runtime_frame, "claims": [], "rows": []}
	return migrated


func restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	value = normalize_transaction_snapshot(value)
	if not _pending.is_empty() or _publishing or not can_restore_launch_transaction_snapshot(value):
		return false
	var before := snapshot()
	if not _payloads.restore_transaction_snapshot(value.payloads):
		return false
	if not _semantics.restore_transaction_snapshot(value.semantics):
		_payloads.restore_transaction_snapshot(before.payloads)
		return false
	if not _summons.restore_snapshot(value.summons):
		_semantics.restore_transaction_snapshot(before.semantics)
		_payloads.restore_transaction_snapshot(before.payloads)
		return false
	_state = value.duplicate(true)
	return true


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
	for source: Variant in context.actors:
		if context.targets.has(source) and context.targets[source] != context.actors[source]:
			return _failure("native_target_identity")
	var registry_before: Array = registry.snapshot()
	var projected: RefCounted = Registry.new()
	if not _install_registry(projected, registry_before):
		return _failure("registry_snapshot")
	var next := snapshot()
	next.runtime_frame = context.runtime_frame
	var operations: Array[Dictionary] = []
	var damages: Array[Dictionary] = []
	var forest_health: Array[Dictionary] = []
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
			if not request is Dictionary or request.get("handler_id", "") not in Contract.handler_ids() or str(request.get("hostile_source_id", "")) != source:
				return _failure("unimplemented_effect_handler")
		if not batch.get("mechanism_requests", []) is Array or batch.get("mechanism_requests", []).size() > 128:
			return _failure("mechanism_requests")
		for mechanism: Variant in batch.get("mechanism_requests", []):
			if not mechanism is Dictionary:
				return _failure("mechanism_request")
			if mechanism.get("kind", "") != "consume_actor":
				continue
			var prepared := _prepare_consumption(mechanism, source, actor, context, next)
			if not prepared.ok:
				return prepared
			damages.append(prepared.record)
		for hit: Variant in batch.hit_facts:
			if hit is Dictionary and hit.get("handler_id", "") not in ["melee", "charge"]:
				continue
			var prepared := _prepare_hit(hit, source, actor, context, next)
			if not prepared.ok:
				return prepared
			if hit.action_id == "matriarch_drain_roots":
				var drain := _prepare_forest_drain(hit, actor, prepared.record)
				if not drain.ok:
					return drain
				forest_health.append(drain.record)
			if hit.action_id == "forge_hammer_slam":
				prepared.record["forge_slam"] = {"owner": actor, "hit": hit.duplicate(true)}
			damages.append(prepared.record)
		for request: Dictionary in batch.get("mechanism_requests", []):
			if request.get("kind") == "void_shard_pickup":
				if damages.any(func(row: Dictionary): return row.has("void_pickup") and row.void_pickup.target_id == request.target_id):
					continue
				var pickup := _prepare_void_pickup(request, actor, context, next)
				if not pickup.ok:
					return pickup
				if not pickup.record.is_empty():
					damages.append(pickup.record)
				continue
			if request.get("kind") not in ["forge_burn_tick", "void_burn_tick"]:
				continue
			var sealed: bool = actor.has_method("prepared_launch_void_mechanism_allowed") and actor.prepared_launch_void_mechanism_allowed(request) if request.kind == "void_burn_tick" else actor.has_method("prepared_launch_forge_mechanism_allowed") and actor.prepared_launch_forge_mechanism_allowed(request)
			if not sealed:
				return _failure("forge_burn_seal")
			var tick: Dictionary = request.request.duplicate(true) if request.kind == "void_burn_tick" else request.duplicate(true)
			if tick.has("kind"):
				tick.erase("kind")
			var prepared := _prepare_payload_damage(tick, context, next)
			if not prepared.ok:
				return prepared
			damages.append(prepared.record)
		for tick: Variant in batch.status_tick_requests:
			var prepared := _prepare_status_tick(tick, source, actor, context, next)
			if not prepared.ok:
				return prepared
			damages.append(prepared.record)
	var retired_children: Array[String] = _summons.retired_owner_child_sources(context.actors)
	var payload_prepared: Dictionary = _payloads.prepare_payloads(batches, context, _semantics.active_zone_count_for_snapshot(next.semantics, int(context.runtime_frame)), retired_children)
	if not payload_prepared.ok:
		return payload_prepared
	for request: Dictionary in payload_prepared.damage_requests:
		var prepared := _prepare_payload_damage(request, context, next)
		if not prepared.ok:
			_payloads.rollback(payload_prepared.ticket)
			return prepared
		damages.append(prepared.record)
	next.payloads = payload_prepared.ticket.after.duplicate(true)
	if not _prepare_payload_registry(payload_prepared.ticket.before, payload_prepared.ticket.after, projected, operations):
		_payloads.rollback(payload_prepared.ticket)
		return _failure("payload_threat_registry")
	var semantic_prepared: Dictionary = _semantics.prepare_effects(batches, context, _payload_active_zone_count(payload_prepared.ticket.after), retired_children)
	if not semantic_prepared.ok:
		_payloads.rollback(payload_prepared.ticket)
		return semantic_prepared
	for request: Dictionary in semantic_prepared.damage_requests:
		var prepared := _prepare_payload_damage(request, context, next)
		if not prepared.ok:
			_semantics.rollback(semantic_prepared.ticket)
			_payloads.rollback(payload_prepared.ticket)
			return prepared
		damages.append(prepared.record)
	var health_records: Array[Dictionary] = forest_health
	for wrapper: Dictionary in batches:
		for request: Dictionary in wrapper.batch.get("mechanism_requests", []):
			if request.get("kind") == "void_p3_player_heal":
				var void_heal := _prepare_void_player_heal(request, context, next)
				if not void_heal.ok:
					_semantics.rollback(semantic_prepared.ticket)
					_payloads.rollback(payload_prepared.ticket)
					return void_heal
				if not void_heal.record.is_empty():
					health_records.append(void_heal.record)
				continue
			if request.get("kind") != "forest_flower":
				continue
			var prepared := _prepare_forest_flower(request, context, next)
			if not prepared.ok:
				_semantics.rollback(semantic_prepared.ticket)
				_payloads.rollback(payload_prepared.ticket)
				return prepared
			health_records.append(prepared.record)
	for request: Dictionary in semantic_prepared.health_requests:
		var prepared := _prepare_health_gain(request, context, next)
		if not prepared.ok:
			_semantics.rollback(semantic_prepared.ticket)
			_payloads.rollback(payload_prepared.ticket)
			return prepared
		health_records.append(prepared.record)
	for wrapper: Dictionary in batches:
		var heal: Variant = wrapper.batch.get("affix_heal", {"healed_amount": 0.0, "hp_after": 0.0})
		if not heal is Dictionary or not Contract.exact_fields(heal, ["healed_amount", "hp_after"]) or not Contract.number_in_range(heal.healed_amount, 0.0, 1000000.0) or not Contract.number_in_range(heal.hp_after, 0.0, 1000000.0):
			_semantics.rollback(semantic_prepared.ticket)
			_payloads.rollback(payload_prepared.ticket)
			return _failure("affix_health_plan")
		if float(heal.healed_amount) <= 0.0:
			continue
		var request := {"kind": "affix_regeneration", "hostile_source_id": wrapper.hostile_source_id, "attack_generation": int(context.runtime_frame), "hit_index": 0, "target_id": wrapper.hostile_source_id, "runtime_frame": int(context.runtime_frame), "amount": heal.healed_amount}
		var prepared := _prepare_health_gain(request, context, next)
		if not prepared.ok:
			_semantics.rollback(semantic_prepared.ticket)
			_payloads.rollback(payload_prepared.ticket)
			return prepared
		health_records.append(prepared.record)
	next.semantics = semantic_prepared.ticket.after.duplicate(true)
	if not _prepare_semantic_registry(semantic_prepared.ticket.before, semantic_prepared.ticket.after, projected, operations):
		_semantics.rollback(semantic_prepared.ticket)
		_payloads.rollback(payload_prepared.ticket)
		return _failure("semantic_threat_registry")
	while next.claims.size() > MAX_CLAIMS:
		next.claims.pop_front()
	var summon_prepared: Dictionary = _summons.prepare(batches, context)
	if not summon_prepared.ok:
		_semantics.rollback(semantic_prepared.ticket)
		_payloads.rollback(payload_prepared.ticket)
		return summon_prepared
	next.summons = summon_prepared.ticket.after.duplicate(true)
	var ticket := {"ticket_id": _next_ticket_id, "run_id": context.run_id, "runtime_frame": context.runtime_frame, "before": snapshot(), "after": next, "registry_before": registry_before, "registry_after": projected.snapshot(), "registry_operations": operations, "damage_records": damages, "health_records": health_records, "source_batches": batches.duplicate(true), "actors": context.actors.duplicate(), "targets": context.targets.duplicate(), "threat_registry": registry, "payload_ticket": payload_prepared.ticket, "semantic_ticket": semantic_prepared.ticket, "summon_ticket": summon_prepared.ticket}
	_next_ticket_id += 1
	_pending = ticket.duplicate(true)
	_committed = false
	_owned_signals.clear()
	return {"ok": true, "ticket": ticket.duplicate(true)}


func can_commit_effects(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or _committed or _publishing or snapshot() != ticket.before or ticket.threat_registry.snapshot() != ticket.registry_before or not _payloads.can_commit(ticket.payload_ticket) or not _semantics.can_commit(ticket.semantic_ticket) or not _summons.can_commit(ticket.summon_ticket):
		return false
	for wrapper: Dictionary in ticket.source_batches:
		var actor: Node = ticket.actors[wrapper.hostile_source_id]
		if not is_instance_valid(actor) or actor.prepared_launch_frame_batch() != wrapper.batch:
			return false
	for record: Dictionary in ticket.damage_records + ticket.health_records:
		if not is_instance_valid(record.target) or not is_instance_valid(record.health) or not _target_position_matches(record, ticket.runtime_frame) or _health_observation(record.health) != record.health_before:
			return false
		if record.has("void_pickup") and record.resource_manager.resource_state(&"time_energy") != record.resource_before:
			return false
	return true


func commit_effects(ticket: Dictionary) -> Dictionary:
	if not can_commit_effects(ticket):
		return _failure("stale_commit")
	var seen_health: Dictionary = {}
	for record: Dictionary in ticket.damage_records + ticket.health_records:
		var health: Node = record.health
		if (record.get("info") == null and not record.has("consumption_amount") and not record.has("health_amount")) or seen_health.has(health):
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
	if not _payloads.commit(ticket.payload_ticket):
		return _failure("native_payload_commit")
	if not _semantics.commit(ticket.semantic_ticket):
		return _failure("native_semantic_commit")
	if not _summons.commit(ticket.summon_ticket):
		return _failure("native_summon_commit")
	var resolutions: Array = []
	for record: Dictionary in ticket.damage_records:
		if record.has("void_pickup"):
			var buffered: bool = not (record.resource_manager.get("_active_frame_signal_transaction") as Dictionary).is_empty()
			if not record.void_owner.settle_native_void_pickup(self, record):
				return _failure("void_pickup_receipt")
			_owned_void_resources.append({"manager": record.resource_manager, "buffered": buffered, "before": record.resource_before, "after": record.resource_manager.resource_state(&"time_energy")})
			continue
		if record.has("consumption_amount"):
			var consumed: float = record.health.lose_health(record.consumption_amount, record.target)
			if not is_equal_approx(consumed, float(record.consumption_amount)) or not record.health.dead:
				return _failure("health_consumption")
			continue
		if record.info == null:
			if record.has("forest_drain") and not _settle_forest_drain(record, 0.0, int(ticket.runtime_frame)):
				return _failure("forest_drain_receipt")
			continue
		var hp_before := float(record.health.current_hp)
		var resolution: RefCounted = record.health.resolve_and_apply_damage(record.info)
		if resolution == null:
			return _failure("health_resolution")
		resolutions.append(resolution.snapshot())
		if record.has("forest_drain") and not _settle_forest_drain(record, maxf(0.0, hp_before - float(record.health.current_hp)), int(ticket.runtime_frame)):
			return _failure("forest_drain_receipt")
		if record.has("forge_slam") and not record.forge_slam.owner.settle_native_forge_slam(record.forge_slam.hit, record.target, maxf(0.0, hp_before - float(record.health.current_hp))):
			return _failure("forge_burn_receipt")
		if record.has("void_damage") and not record.void_owner.settle_native_void_damage(self, record, maxf(0.0, hp_before - float(record.health.current_hp))):
			return _failure("void_damage_receipt")
	for record: Dictionary in ticket.health_records:
		if record.get("forest_drain_reservation", false):
			continue
		var amount: float = minf(record.health_amount, maxf(0.0, float(record.health.max_hp) - float(record.health.current_hp)))
		if amount <= 0.0 or record.health.dead:
			if record.has("void_player_heal") and not record.void_owner.settle_native_void_heal(record.void_player_heal, record.target, 0.0):
				return _failure("void_player_heal_receipt")
			if record.get("affix_health_gain", false) and not record.target.settle_launch_affix_heal(int(ticket.runtime_frame), record.health_amount, 0.0):
				return _failure("affix_health_settlement")
			continue
		var healed: float = record.health.heal(amount / float(record.health.healing_multiplier))
		if not is_equal_approx(healed, amount):
			return _failure("health_gain")
		var fact := {"fact_id": record.health_fact_id, "runtime_frame": int(ticket.runtime_frame), "target_source_id": record.target_id, "amount": healed, "hp_after": float(record.health.current_hp)}
		if record.has("void_player_heal"):
			if not record.void_owner.settle_native_void_heal(record.void_player_heal, record.target, healed):
				return _failure("void_player_heal_receipt")
		elif record.has("forest_flower"):
			if not record.forest_owner.settle_native_forest_flower(record.forest_flower, healed):
				return _failure("forest_flower_receipt")
		elif not bool(record.target.accept_launch_health_fact(fact)):
			return _failure("health_gain_receipt")
		if record.get("affix_health_gain", false) and not record.target.settle_launch_affix_heal(int(ticket.runtime_frame), record.health_amount, healed):
			return _failure("affix_health_settlement")
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
	for record: Dictionary in ticket.damage_records:
		if record.has("void_pickup"):
			ok = record.resource_manager.restore_resource_state(&"time_energy", record.resource_before, false) and ok
	_owned_void_resources.clear()
	for owned: Dictionary in _owned_signals:
		if owned.publication.is_empty():
			ok = bool(owned.health.rollback_frame_signal_transaction(owned.ticket)) and ok
		else:
			ok = bool(owned.health.discard_finalized_frame_signal_publication(owned.publication)) and ok
	if not _install_registry(ticket.threat_registry, ticket.registry_before):
		ok = false
	ok = _payloads.rollback(ticket.payload_ticket) and ok
	ok = _semantics.rollback(ticket.semantic_ticket) and ok
	ok = _summons.rollback(ticket.summon_ticket) and ok
	_state = ticket.before.duplicate(true)
	_pending.clear()
	_owned_signals.clear()
	_committed = false
	return ok


func can_publish_effects(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or not _committed or _publishing or not _payloads.can_publish(ticket.payload_ticket) or not _semantics.can_publish(ticket.semantic_ticket) or not _summons.can_publish(ticket.summon_ticket):
		return false
	for owned: Dictionary in _owned_signals:
		if not is_instance_valid(owned.health) or not bool(owned.health.call("_finalized_frame_signal_publication_matches", owned.publication)):
			return false
	for owned: Dictionary in _owned_void_resources:
		if not is_instance_valid(owned.manager) or owned.manager.resource_state(&"time_energy") != owned.after:
			return false
	return true


func publish_effects(ticket: Dictionary) -> bool:
	if not can_publish_effects(ticket):
		return false
	var publications := _owned_signals.duplicate(true)
	var resources := _owned_void_resources.duplicate(true)
	if not _payloads.publish(ticket.payload_ticket) or not _semantics.publish(ticket.semantic_ticket) or not _summons.publish(ticket.summon_ticket):
		return false
	_publishing = true
	_pending.clear()
	_owned_void_resources.clear()
	_owned_signals.clear()
	_committed = false
	for owned: Dictionary in publications:
		owned.health.publish_prepared_frame_signals()
	for owned: Dictionary in resources:
		if not owned.buffered and owned.before.current != owned.after.current:
			owned.manager.energy_changed.emit(float(owned.after.current), float(owned.after.maximum))
	_publishing = false
	return true


func _prepare_payload_damage(request: Dictionary, context: Dictionary, next: Dictionary) -> Dictionary:
	if not context.targets.has(request.target_id) and not context.actors.has(request.target_id):
		return _failure("payload_damage_target")
	var target: Node2D = context.targets.get(request.target_id, context.actors.get(request.target_id))
	var record := _target_record(target)
	if record.is_empty():
		return _failure("payload_health")
	if context.actors.has(request.target_id):
		record["target_position_after"] = target.prepared_launch_frame_position()
	var claim := _claim(context.run_id, request.target_id, request.payload_id, request.attack_generation, request.hit_index)
	if next.claims.has(claim):
		return _failure("duplicate_payload_damage")
	next.claims.append(claim)
	var info := Damage.from_plan({"run_id": context.run_id, "target_id": request.target_id, "hostile_source_id": request.payload_id, "attack_generation": request.attack_generation, "hit_index": request.hit_index, "action_token": request.attack_generation, "amount": request.damage, "damage_type": Contract.DAMAGE_TYPES.find(request.damage_type), "source": null, "attacker": null, "can_crit": false, "knockback": Vector2.ZERO, "tags": ["enemy:launch", "enemy:payload"], "source_generation": request.attack_generation})
	if info == null:
		return _failure("payload_damage_plan")
	record["info"] = info
	if not str(request.payload_id).begins_with("void-burn:") and context.actors.has(request.hostile_source_id):
		_attach_void_damage(record, context.actors[request.hostile_source_id], request, claim)
	return {"ok": true, "record": record}


func owns_void_damage_record(owner: Node2D, record: Dictionary) -> bool:
	return not _pending.is_empty() and not _publishing and record.get("void_owner") == owner and _pending.damage_records.has(record) and record.has("void_damage")


func owns_void_pickup_record(owner: Node2D, record: Dictionary) -> bool:
	return not _pending.is_empty() and not _publishing and record.get("void_owner") == owner and _pending.damage_records.has(record) and record.has("void_pickup") and owner.prepared_launch_void_mechanism_allowed(record.void_pickup)


func _prepare_void_pickup(request: Dictionary, actor: Node2D, context: Dictionary, next: Dictionary) -> Dictionary:
	if not Contract.exact_fields(request, ["kind", "run_id", "hostile_source_id", "runtime_frame", "pickup_id", "target_id", "position", "amount"]) or not actor.has_method("prepared_launch_void_mechanism_allowed") or not actor.prepared_launch_void_mechanism_allowed(request) or not context.targets.has(request.target_id):
		return _failure("void_pickup_seal")
	var target: Node2D = context.targets[request.target_id]
	var record := _target_record(target)
	if record.is_empty() or not target is PlayerController:
		return _failure("void_pickup_target")
	if record.health_before.runtime.dead:
		return {"ok": true, "record": {}}
	var claim := _claim(context.run_id, request.target_id, "void-pickup:%s:%s" % [request.hostile_source_id, request.pickup_id], int(actor.get("_launch_identity").next_generation_floor), 0)
	if next.claims.has(claim):
		return _failure("void_pickup_duplicate")
	next.claims.append(claim)
	record["info"] = null
	record["void_owner"] = actor
	record["void_pickup"] = request.duplicate(true)
	record["resource_manager"] = target.time_manager
	record["resource_before"] = target.time_manager.resource_state(&"time_energy")
	record["resource_fact_id"] = "void-energy:" + claim.substr(0, 40)
	return {"ok": true, "record": record}


func _attach_void_damage(record: Dictionary, actor: Node2D, request: Dictionary, claim: String) -> void:
	if actor.get("_launch_definition").get("id") != "void_throne" or not record.target is PlayerController or not actor.has_method("native_void_auxiliary_snapshot"):
		return
	var action: String = actor.get("_launch_runtime").void_action_for_generation(int(request.attack_generation))
	if action.is_empty() and not actor.get("_prepared_launch_frame").is_empty():
		for cast: Dictionary in actor.get("_prepared_launch_frame").after.runtime.void_auxiliary.casts:
			if cast.geometry.any(func(row: Dictionary): return row.attack_generation == request.attack_generation):
				action = str(cast.action_id)
	if action in ["voidking_scepter_strike", "voidking_void_bolt", "voidking_void_grasp", "voidking_devour"]:
		record["void_owner"] = actor
		record["void_damage"] = {"fact_id": "void-health:" + claim.substr(0, 40), "attack_generation": int(request.attack_generation), "hit_index": int(request.hit_index), "target_id": str(request.target_id), "runtime_frame": int(request.runtime_frame)}


func _prepare_health_gain(request: Dictionary, context: Dictionary, next: Dictionary) -> Dictionary:
	if not Contract.exact_fields(request, ["kind", "hostile_source_id", "attack_generation", "hit_index", "target_id", "runtime_frame", "amount"]) or request.kind not in ["heal", "restore_hp", "affix_regeneration"] or not context.actors.has(request.hostile_source_id) or not context.actors.has(request.target_id) or request.runtime_frame != context.runtime_frame or not Contract.integer_in_range(request.attack_generation, 1, 2147483646) or not Contract.integer_in_range(request.hit_index, 0, 63) or not Contract.number_in_range(request.amount, 0.000001, 1000000.0):
		return _failure("health_gain_request")
	var target: Node2D = context.actors[request.target_id]
	var record := _target_record(target)
	if record.is_empty() or not target.has_method("accept_launch_health_fact") or record.health_before.runtime.dead or not Contract.number_in_range(record.health.healing_multiplier, 0.000001, 1000000.0):
		return _failure("health_gain_target")
	if request.kind == "affix_regeneration" and not target.has_method("settle_launch_affix_heal"):
		return _failure("affix_health_target")
	var claim := _claim(context.run_id, request.target_id, "health:%s:%s" % [request.hostile_source_id, request.kind], request.attack_generation, request.hit_index)
	if next.claims.has(claim):
		return _failure("duplicate_health_gain")
	next.claims.append(claim)
	record["target_position_after"] = target.prepared_launch_frame_position()
	record["target_id"] = request.target_id
	record["health_amount"] = float(request.amount)
	record["health_fact_id"] = "hostile-health:%s" % claim.substr(0, 40)
	record["affix_health_gain"] = request.kind == "affix_regeneration"
	return {"ok": true, "record": record}


func _prepare_void_player_heal(request: Dictionary, context: Dictionary, next: Dictionary) -> Dictionary:
	if not Contract.exact_fields(request, ["kind", "run_id", "hostile_source_id", "runtime_frame", "attack_generation", "hit_index", "target_id", "fraction"]) or request.kind != "void_p3_player_heal" or request.run_id != context.run_id or request.runtime_frame != context.runtime_frame or request.fraction != 0.3 or request.hit_index != 63 or not context.actors.has(request.hostile_source_id) or not context.targets.has(request.target_id):
		return _failure("void_player_heal_request")
	var owner: Node2D = context.actors[request.hostile_source_id]
	if not owner.has_method("prepared_launch_void_heal_allowed") or not owner.prepared_launch_void_heal_allowed(request):
		return _failure("void_player_heal_seal")
	var target: Node2D = context.targets[request.target_id]
	var record := _target_record(target)
	if record.is_empty() or not target is PlayerController or not Contract.number_in_range(record.health.healing_multiplier, 0.000001, 1000000.0):
		return _failure("void_player_heal_target")
	var claim := _claim(context.run_id, request.target_id, "void-p3-heal:%s" % request.hostile_source_id, int(request.attack_generation), int(request.hit_index))
	if next.claims.has(claim):
		return _failure("void_player_heal_duplicate")
	next.claims.append(claim)
	record["target_id"] = request.target_id
	record["health_amount"] = 0.0 if record.health_before.runtime.dead else float(record.health.max_hp) * 0.3
	record["health_fact_id"] = "hostile-health:%s" % claim.substr(0, 40)
	record["void_owner"] = owner
	record["void_player_heal"] = request.duplicate(true)
	return {"ok": true, "record": record}


func _prepare_forest_flower(request: Dictionary, context: Dictionary, next: Dictionary) -> Dictionary:
	if not Contract.exact_fields(request, ["kind", "run_id", "hostile_source_id", "runtime_frame", "attack_generation", "hit_index", "construct_id", "target_id", "amount"]) or request.run_id != context.run_id or request.runtime_frame != context.runtime_frame or request.amount != 20.0 or not context.actors.has(request.hostile_source_id) or not context.targets.has(request.target_id):
		return _failure("forest_flower_request")
	var owner: Node2D = context.actors[request.hostile_source_id]
	if not owner.has_method("prepared_launch_forest_mechanism_allowed") or not owner.prepared_launch_forest_mechanism_allowed(request):
		return _failure("forest_flower_seal")
	var target: Node2D = context.targets[request.target_id]
	var record := _target_record(target)
	if record.is_empty() or not target is PlayerController or record.health_before.runtime.dead or not Contract.number_in_range(record.health.healing_multiplier, 0.000001, 1000000.0):
		return _failure("forest_flower_target")
	var claim := _claim(context.run_id, request.target_id, "flower:%s:%s" % [request.hostile_source_id, request.construct_id], int(request.attack_generation), int(request.hit_index))
	if next.claims.has(claim):
		return _failure("forest_flower_duplicate")
	next.claims.append(claim)
	record["target_id"] = request.target_id
	record["health_amount"] = 20.0
	record["health_fact_id"] = "hostile-health:%s" % claim.substr(0, 40)
	record["forest_owner"] = owner
	record["forest_flower"] = request.duplicate(true)
	return {"ok": true, "record": record}


func _prepare_forest_drain(hit: Dictionary, owner: Node2D, damage_record: Dictionary) -> Dictionary:
	if not damage_record.target is PlayerController or not owner.has_method("native_forest_drain_allowance") or not owner.has_method("settle_native_forest_drain"):
		return _failure("forest_drain_source")
	var record := _target_record(owner)
	if record.is_empty() or record.health_before.runtime.dead or not Contract.number_in_range(record.health.healing_multiplier, 0.000001, 1000000.0):
		return _failure("forest_drain_health")
	var id := "forest-drain:%s" % _claim(str(hit.run_id), str(hit.target_id), str(hit.hostile_source_id), int(hit.attack_generation), int(hit.hit_index)).substr(0, 40)
	damage_record["forest_drain"] = {"owner": owner, "health": record.health, "id": id, "generation": int(hit.attack_generation), "index": int(hit.hit_index)}
	record["target_position_after"] = owner.prepared_launch_frame_position()
	record["health_amount"] = 0.0
	record["forest_drain_reservation"] = true
	return {"ok": true, "record": record}


func _settle_forest_drain(record: Dictionary, loss: float, frame: int) -> bool:
	var drain: Dictionary = record.forest_drain
	var allowed: float = minf(float(drain.owner.native_forest_drain_allowance(drain.generation, loss)), maxf(0.0, float(drain.health.max_hp) - float(drain.health.current_hp)))
	var healed := 0.0
	if allowed > 0.0 and not drain.health.dead:
		healed = float(drain.health.heal(allowed / float(drain.health.healing_multiplier)))
		if not is_equal_approx(healed, allowed) or not drain.owner.accept_launch_health_fact({"fact_id": str(drain.id) + ":heal", "runtime_frame": frame, "target_source_id": str(drain.owner.hostile_source_id), "amount": healed, "hp_after": float(drain.health.current_hp)}):
			return false
	return drain.owner.settle_native_forest_drain(str(drain.id), int(drain.generation), int(drain.index), frame, loss, healed)


func _prepare_semantic_registry(before: Dictionary, after: Dictionary, registry: RefCounted, operations: Array[Dictionary]) -> bool:
	var before_rows: Dictionary = {}
	var after_rows: Dictionary = {}
	for fact: Dictionary in _semantics.threat_facts_for_snapshot(before):
		before_rows[str(fact.hostile_source_id)] = fact
	for fact: Dictionary in _semantics.threat_facts_for_snapshot(after):
		after_rows[str(fact.hostile_source_id)] = fact
	for id: String in before_rows:
		if not after_rows.has(id) or before_rows[id] != after_rows[id]:
			if not registry.retire(StringName(id), 1):
				return false
			operations.append({"kind": "retire", "source": id, "generation": 1})
	for id: String in after_rows:
		if not before_rows.has(id) or before_rows[id] != after_rows[id]:
			if not registry.register_fact(after_rows[id]):
				return false
			operations.append({"kind": "register", "fact": after_rows[id]})
	return true


static func _prepare_payload_registry(before: Dictionary, after: Dictionary, registry: RefCounted, operations: Array[Dictionary]) -> bool:
	var before_rows: Dictionary = {}
	var after_rows: Dictionary = {}
	for row: Dictionary in before.projectiles + before.zones:
		if row.phase not in ["PENDING", "DORMANT"]:
			before_rows[row.id] = row
	for row: Dictionary in after.projectiles + after.zones:
		if row.phase not in ["PENDING", "DORMANT"]:
			after_rows[row.id] = row
	for id: String in before_rows:
		if not after_rows.has(id):
			if not registry.retire(StringName(id), 1):
				return false
			operations.append({"kind": "retire", "source": id, "generation": 1})
	for id: String in after_rows:
		var next := _payload_threat_fact(after_rows[id], int(after.runtime_frame))
		if not before_rows.has(id):
			if not registry.register_fact(next):
				return false
			operations.append({"kind": "register", "fact": next})
		else:
			var previous := _payload_threat_fact(before_rows[id], int(before.runtime_frame))
			if next.active_through_frame != previous.active_through_frame:
				if not registry.extend_fact_through(StringName(id), 1, previous.active_through_frame, next.active_through_frame):
					return false
				operations.append({"kind": "extend", "extension": {"hostile_source_id": id, "attack_generation": 1, "expected_through_frame": previous.active_through_frame, "new_through_frame": next.active_through_frame}})
	return true


static func _payload_threat_fact(row: Dictionary, frame: int) -> Dictionary:
	var definition: Dictionary = row.definition
	var projectile: bool = definition.kind == "projectile"
	var origin: Dictionary = definition.origin if projectile else definition.position
	return {"hostile_source_id": StringName(row.id), "attack_generation": 1, "shape": &"line" if projectile else &"circle", "origin": _vector(origin), "aim_direction": _vector(definition.direction) if projectile else Vector2.RIGHT, "target_point": _vector(origin), "summon_slots": [], "radius": definition.radius, "length": definition.range_px if projectile else 0.0, "active_from_frame": int(row.activated_frame) + int(definition.get("delay_frames", 0)) if definition.kind == "boss_aftershock" else definition.reserved_frame, "active_through_frame": frame + int(definition.lifetime_frames) + int(definition.get("warning_frames", 0)) + int(definition.get("delay_frames", 0)) - int(row.age)}


func _work_snapshot(value: Dictionary) -> Dictionary:
	var records: Dictionary = _semantics.work_records_for_snapshot(value.semantics)
	for row: Dictionary in value.payloads.projectiles + value.payloads.zones:
		records[row.id] = {"kind": "projectile" if row.definition.kind == "projectile" else "zone", "owner_source_id": row.definition.source_id, "phase": "PENDING" if row.phase == "PENDING" else "ACTIVE"}
	for row: Dictionary in value.payloads.get("arena_debris", {}).get("rows", []):
		var phase: String = row.phase
		# Weapon facts precede this frame's ledger preparation and remain prior work until acceptance.
		if phase == "BROKEN":
			for fact: Dictionary in value.payloads.arena_debris.damage_claims:
				if fact.construct_id == row.id and fact.runtime_frame > value.runtime_frame:
					phase = "ACTIVE"
		if phase in ["ACTIVE", "PENDING"]:
			records["debris_" + str(row.id).sha256_text().substr(0, 57)] = {"kind": "construct", "owner_source_id": row.event.source_id, "phase": phase}
	var child_owners := {}
	for row: Dictionary in value.summons.rows:
		child_owners[row.id] = row.parent_source_id
	for id: String in records:
		if child_owners.has(records[id].owner_source_id):
			records[id].owner_source_id = child_owners[records[id].owner_source_id]
	records.merge(Summons.work_records(value.summons))
	return {"run_id": value.run_id, "runtime_frame": value.runtime_frame, "records": records}


static func _payload_active_zone_count(value: Dictionary) -> int:
	var count := 0
	for row: Dictionary in value.zones:
		count += int(row.phase != "PENDING")
	return count


func _prepare_hit(value: Variant, source: String, actor: Node2D, context: Dictionary, next: Dictionary) -> Dictionary:
	if not value is Dictionary or not Contract.exact_fields(value, ["run_id", "hostile_source_id", "attack_generation", "hit_index", "runtime_frame", "target_id", "action_id", "damage", "damage_type", "handler_id", "geometry", "parameters"]):
		return _failure("hit_fields")
	var hit := value as Dictionary
	if hit.run_id != context.run_id or str(hit.hostile_source_id) != source or hit.runtime_frame != context.runtime_frame or hit.handler_id not in ["melee", "charge"] or hit.damage_type not in Contract.DAMAGE_TYPES or not context.targets.has(hit.target_id) or not hit.geometry is Array or hit.geometry.is_empty():
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
	if hit.handler_id == "charge":
		if not actor.has_method("prepared_launch_frame_contacts_target"):
			return _failure("unsealed_charge_contact")
		if not bool(actor.prepared_launch_frame_contacts_target(target)) or not envelope.contains_point(target.global_position, context.runtime_frame):
			record["info"] = null
			return {"ok": true, "record": record}
	var claim := _claim(context.run_id, str(hit.target_id), source, int(hit.attack_generation), int(hit.hit_index))
	if next.claims.has(claim):
		if hit.handler_id == "charge":
			record["info"] = null
			return {"ok": true, "record": record}
		return _failure("duplicate_hit")
	next.claims.append(claim)
	var info: RefCounted
	if envelope.contains_point(target.global_position, context.runtime_frame):
		if actor.has_method("prepared_launch_hit_blocked_by_cover") and actor.prepared_launch_hit_blocked_by_cover(hit, target):
			record["info"] = null
			return {"ok": true, "record": record}
		var primitive: Dictionary = hit.geometry[0]
		var direction := _vector(primitive.origin).direction_to(_vector(primitive.target_point))
		if direction.is_zero_approx():
			direction = _vector(primitive.aim_direction)
		info = Damage.from_plan({"run_id": context.run_id, "target_id": hit.target_id, "hostile_source_id": source, "attack_generation": hit.attack_generation, "hit_index": hit.hit_index, "action_token": hit.attack_generation, "amount": hit.damage, "damage_type": Contract.DAMAGE_TYPES.find(hit.damage_type), "source": actor, "attacker": actor, "can_crit": false, "knockback": direction * float(hit.parameters.knockback_px), "tags": ["enemy:launch", "enemy:%s" % hit.handler_id], "source_generation": hit.attack_generation})
		if info == null:
			return _failure("damage_plan")
	record["info"] = info
	_attach_void_damage(record, actor, hit, claim)
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


func _prepare_consumption(value: Variant, source: String, actor: Node2D, context: Dictionary, next: Dictionary) -> Dictionary:
	if not value is Dictionary or not Contract.exact_fields(value, ["kind", "run_id", "hostile_source_id", "runtime_frame", "action_id", "attack_generation", "hit_index"]):
		return _failure("unimplemented_mechanism_handler")
	if value.kind != "consume_actor" or value.run_id != context.run_id or value.hostile_source_id != source or typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame != context.runtime_frame or not Contract.valid_id(value.action_id) or typeof(value.attack_generation) != TYPE_INT or not Contract.integer_in_range(value.attack_generation, 1, 2147483646) or typeof(value.hit_index) != TYPE_INT or value.hit_index != 63 or not actor.has_method("prepared_launch_frame_consumes_actor") or not bool(actor.prepared_launch_frame_consumes_actor()):
		return _failure("unsealed_consumption")
	var record := _target_record(actor)
	if record.is_empty() or record.health_before.runtime.dead or not Contract.number_in_range(record.health_before.runtime.current_hp, 0.000001, 1000000.0):
		return _failure("consumption_target")
	var claim := _claim(context.run_id, source, source, value.attack_generation, value.hit_index)
	if next.claims.has(claim):
		return _failure("duplicate_consumption")
	next.claims.append(claim)
	record["target_position_after"] = actor.prepared_launch_frame_position()
	record["info"] = null
	record["consumption_amount"] = float(record.health_before.runtime.current_hp)
	return {"ok": true, "record": record}


func _target_record(target: Variant) -> Dictionary:
	if not target is Node2D or not is_instance_valid(target) or not target.has_node("HealthComponent"):
		return {}
	var health: Node = target.get_node("HealthComponent")
	if not health.has_method("resolve_and_apply_damage") or str(health.irreversible_run_id()) != _state.run_id:
		return {}
	return {"target": target, "health": health, "target_position": target.global_position, "health_before": _health_observation(health)}


static func _health_observation(health: Node) -> Dictionary:
	return {"runtime": health.runtime_state_snapshot(), "defense": health.defense, "invulnerable": health.invulnerable, "accessibility_multiplier": health.damage_received_multiplier, "healing_multiplier": health.healing_multiplier, "max_hp": health.max_hp}


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
