class_name LaunchHostileActor
extends "res://scripts/enemies/enemy_base.gd"

const LaunchRuntime := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const LaunchStatus := preload("res://scripts/enemies/launch/launch_elemental_status_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const FRAME_TICKET_FIELDS: Array[String] = ["ticket_id", "hostile_source_id", "runtime_frame", "before", "after", "batch", "health_before"]
const ACTOR_STATE_FIELDS: Array[String] = ["runtime", "status", "position", "knockback", "weakpoint_sequence", "stop_sequence", "weapon_claims", "weapon_claim_order", "blind_sequence", "action_credit", "death_receipt", "weapon_metadata"]
const WEAPON_METADATA_FIELDS: Array[String] = ["bow_time_erosion_sources", "elemental_status_seed_initialized", "elemental_status_seed_material", "planewalker_replay_external_fact_claims"]

signal hostile_final_death(source_id: StringName, receipt_id: String)

var _launch_runtime: RefCounted = LaunchRuntime.new()
var _launch_definition: Dictionary = {}
var _launch_identity: Dictionary = {}
var _prepared_launch_frame: Dictionary = {}
var _prepared_frame_committed := false
var _next_launch_ticket_id := 1
var _action_credit := 0.0
var _death_receipt := ""


func _init() -> void:
	elemental_status_runtime = LaunchStatus.new()


func _ready() -> void:
	super._ready()
	visual.visible = false
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	_refresh_control_visual()


func configure_launch_definition(definition: Dictionary, context: Dictionary) -> Dictionary:
	if not _prepared_launch_frame.is_empty() or health == null:
		return _launch_failure("not_ready_or_busy")
	var candidate: RefCounted = LaunchRuntime.new()
	var configured: Dictionary = candidate.configure(definition, context)
	if not configured.ok:
		return configured
	if not health.configure_run(StringName(context.run_id)):
		return _launch_failure("health_run")
	_launch_runtime = candidate
	_launch_definition = definition.duplicate(true)
	_launch_identity = context.duplicate(true)
	configure_hostile_identity(StringName(context.hostile_source_id), int(context.next_generation_floor))
	max_hp = float(definition.max_hp)
	move_speed = float(definition.move_speed)
	defense = float(definition.defense)
	health.max_hp = max_hp
	health.defense = defense
	health.current_hp = max_hp
	health.dead = false
	configure_elemental_status_seed(int(context.seed), 0.40, 0.40)
	_action_credit = 0.0
	_death_receipt = ""
	_refresh_control_visual()
	return {"ok": true, "snapshot": launch_runtime_snapshot()}


func launch_runtime_snapshot() -> Dictionary:
	return {"runtime": _launch_runtime.snapshot(), "elemental_status": elemental_status_runtime.snapshot(), "health": health.runtime_state_snapshot() if health != null else {}, "position": _point(global_position), "action_credit": _action_credit, "death_receipt": _death_receipt}


func project_runtime_snapshot(value: Dictionary) -> bool:
	if value != launch_runtime_snapshot():
		return false
	_refresh_control_visual()
	return true


func prepare_launch_frame(frame: int, observations: Dictionary) -> Dictionary:
	if _launch_definition.is_empty() or not _prepared_launch_frame.is_empty() or _launch_runtime.snapshot().terminal:
		return _launch_failure("unavailable")
	if not Contract.exact_fields(observations, HostileActionCoordinator.CONTEXT_FIELDS) or not Contract.valid_point(observations.source_position) or not _vector(observations.source_position).is_equal_approx(global_position):
		return _launch_failure("source_position")
	var before := _actor_state()
	var preview: RefCounted = LaunchRuntime.new()
	preview.configure(_launch_definition, _launch_identity)
	if not preview.restore_snapshot(before.runtime):
		return _launch_failure("runtime_checkpoint")
	var status_preview: RefCounted = LaunchStatus.new()
	if not status_preview.restore_transaction_snapshot(before.status):
		return _launch_failure("status_checkpoint")
	var next_credit := _action_credit
	var externally_paused: bool = status_preview.is_frozen()
	if not externally_paused and not preview.control_modifiers().action_paused:
		next_credit += minf(1.0, float(status_preview.attack_speed_multiplier()))
		externally_paused = next_credit < 1.0
		if not externally_paused:
			next_credit -= 1.0
	var lethal_pending: bool = health.dead
	var motion: Dictionary = preview.motion_for_frame(frame, observations)
	if not motion.ok:
		return motion
	var displacement := _vector(motion.displacement) * float(status_preview.slow_multiplier())
	if lethal_pending or externally_paused or motion.action_paused:
		displacement = Vector2.ZERO
	else:
		displacement += _knockback_velocity / 60.0
	var predicted := global_position
	if not displacement.is_zero_approx():
		var collision := move_and_collide(displacement, true)
		predicted += collision.get_travel() if collision != null else displacement
	var committed_observations := observations.duplicate(true)
	committed_observations.source_position = _point(predicted)
	var batch: Dictionary = preview.advance_frame(frame, committed_observations, not lethal_pending, externally_paused or lethal_pending)
	if not batch.ok:
		return batch
	var status_events: Dictionary = {"burn_ticks": []}
	if lethal_pending:
		var cancelled: Dictionary = preview.cancel(&"death")
		batch.retired_generations = cancelled.retired_generations
		batch.threat_extensions = []
		batch.threat_facts = []
		batch.hit_facts = []
		batch.effect_requests = []
		batch.phase = "IDLE"
		status_preview.reset_runtime_state()
		next_credit = 0.0
	else:
		status_events = status_preview.advance_frame()
		if preview.snapshot().terminal:
			status_preview.reset_runtime_state()
			status_events.burn_ticks = []
			next_credit = 0.0
	batch["status_tick_requests"] = status_events.burn_ticks.duplicate(true)
	var after := before.duplicate(true)
	after.runtime = preview.snapshot()
	after.status = status_preview.transaction_snapshot()
	after.position = _point(predicted)
	after.knockback = _point(_knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() / 60.0))
	after.action_credit = next_credit
	var ticket := {"ticket_id": _next_launch_ticket_id, "hostile_source_id": str(hostile_source_id), "runtime_frame": frame, "before": before, "after": after, "batch": batch, "health_before": health.runtime_state_snapshot()}
	_next_launch_ticket_id += 1
	_prepared_launch_frame = ticket.duplicate(true)
	_prepared_frame_committed = false
	return {"ok": true, "ticket": ticket.duplicate(true), "batch": batch.duplicate(true)}


func can_commit_launch_frame(ticket: Dictionary) -> bool:
	return _ticket_matches(ticket) and not _prepared_frame_committed and _actor_state() == ticket.before and health.runtime_state_snapshot() == ticket.health_before and _can_restore_actor_state(ticket.after)


func commit_launch_frame(ticket: Dictionary) -> bool:
	if not can_commit_launch_frame(ticket) or not _restore_actor_state(ticket.after):
		return false
	_prepared_frame_committed = true
	return true


func rollback_launch_frame(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket):
		return false
	if _prepared_frame_committed and not _restore_actor_state(ticket.before):
		return false
	_prepared_launch_frame.clear()
	_prepared_frame_committed = false
	_refresh_control_visual()
	return true


func can_publish_launch_frame(ticket: Dictionary) -> bool:
	return _ticket_matches(ticket) and _prepared_frame_committed


func publish_launch_frame(ticket: Dictionary) -> bool:
	if not can_publish_launch_frame(ticket):
		return false
	_prepared_launch_frame.clear()
	_prepared_frame_committed = false
	_refresh_control_visual()
	return true


func prepared_launch_frame_batch() -> Dictionary:
	return (_prepared_launch_frame.get("batch", {}) as Dictionary).duplicate(true)


func prepared_launch_frame_position() -> Vector2:
	return _vector(_prepared_launch_frame.after.position) if not _prepared_launch_frame.is_empty() else global_position


func prepared_launch_frame_consumes_actor() -> bool:
	return not _prepared_launch_frame.is_empty() and _launch_definition.runtime_kind == "ruins_wraith" and bool(_prepared_launch_frame.after.runtime.terminal) and bool(_prepared_launch_frame.after.runtime.mechanism_state.detonation_consumed) and _prepared_launch_frame.batch.mechanism_requests.size() == 1


func launch_transaction_snapshot() -> Dictionary:
	if _launch_definition.is_empty():
		return {}
	return {"schema_version": 1, "hostile_source_id": str(hostile_source_id), "actor": _actor_state(), "health": health.transaction_snapshot()}


func can_restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	return Contract.exact_fields(value, ["schema_version", "hostile_source_id", "actor", "health"]) and typeof(value.schema_version) == TYPE_INT and value.schema_version == 1 and value.hostile_source_id == str(hostile_source_id) and value.actor is Dictionary and _can_restore_actor_state(value.actor) and value.health is Dictionary and bool(health.call("_valid_health_transaction_snapshot", value.health))


func restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	if not can_restore_launch_transaction_snapshot(value):
		return false
	if not health.restore_transaction_snapshot(value.health) or not _restore_actor_state(value.actor):
		return false
	_prepared_launch_frame.clear()
	_prepared_frame_committed = false
	_hostile_identity_active = not bool(value.actor.runtime.terminal)
	if health.is_alive() and _hostile_identity_active:
		add_to_group("enemies")
		add_to_group("time_stoppable")
	else:
		remove_from_group("enemies")
		remove_from_group("time_stoppable")
	_refresh_control_visual()
	return true


func discard_launch_transaction_snapshot(value: Dictionary) -> bool:
	return can_restore_launch_transaction_snapshot(value) and health.discard_transaction_snapshot(value.health)


func apply_time_stop(duration: float) -> void:
	_time_stop_token_sequence += 1
	apply_time_stop_source(StringName("launch_stop:%d" % _time_stop_token_sequence), duration)


func apply_time_stop_source(source_id: StringName, duration: float) -> void:
	var frames := _seconds_to_frames(duration)
	if frames > 0:
		_launch_runtime.add_control_source(str(source_id), "stop", frames, 1.0)
	_refresh_control_visual()


func clear_time_stop_source(source_id: StringName) -> void:
	_launch_runtime.clear_control_source(str(source_id))
	_refresh_control_visual()


func is_time_stopped() -> bool:
	return _launch_runtime.control_modifiers().action_paused


func apply_time_rift(source_id: StringName, slow_multiplier: float) -> void:
	_launch_runtime.add_control_source(str(source_id), "rift", Contract.MAX_FRAME, slow_multiplier)


func clear_time_rift(source_id: StringName) -> void:
	_launch_runtime.clear_control_source(str(source_id))


func is_time_rifted() -> bool:
	return float(_launch_runtime.control_modifiers().movement_multiplier) < 1.0


func apply_weakpoint(duration: float, damage_bonus: float) -> void:
	var frames := _seconds_to_frames(duration)
	if frames <= 0:
		return
	_weakpoint_token += 1
	_launch_runtime.add_control_source("launch_weakpoint:%d" % _weakpoint_token, "weakpoint", frames, damage_bonus)


func get_weakpoint_damage_bonus(damage_info: RefCounted) -> float:
	if damage_info == null or not (damage_info.tags.has("attack:heavy") or damage_info.tags.has("attack:finisher")):
		return 0.0
	return float(_launch_runtime.control_modifiers().weakpoint_bonus)


func apply_damage_vulnerability(source_id: StringName, duration_frames: int, damage_taken_bonus: float) -> bool:
	return _launch_runtime.add_control_source(str(source_id), "vulnerability", duration_frames, damage_taken_bonus)


func clear_damage_vulnerability_source(source_id: StringName) -> bool:
	return _launch_runtime.clear_control_source(str(source_id))


func get_damage_taken_multiplier() -> float:
	return minf(3.0, (float(_launch_runtime.control_modifiers().damage_taken_multiplier) + elemental_status_runtime.shock_damage_bonus()) * _launch_runtime.species_damage_taken_multiplier())


func apply_weapon_hit_control(damage_info: RefCounted, final_amount: float) -> bool:
	var staged := false
	if not _launch_definition.is_empty() and damage_info != null and is_finite(final_amount) and final_amount > 0.0:
		var info: Dictionary = damage_info.snapshot()
		var frame: int = health.frame_signal_transaction_runtime_frame()
		if frame < 0:
			frame = _hostile_runtime_frame()
		var identity := JSON.stringify([info.run_id, info.target_id, info.hostile_source_id, info.attack_generation, info.hit_index])
		var result: Dictionary = _launch_runtime.accept_damage_fact({"fact_id": identity.sha256_text(), "runtime_frame": frame, "target_source_id": str(hostile_source_id), "amount": final_amount, "hp_after": health.current_hp})
		staged = result.ok
		if result.ok and _hostile_threat_registry != null:
			for generation: int in result.retired_generations:
				_hostile_threat_registry.retire(hostile_source_id, generation)
	return super.apply_weapon_hit_control(damage_info, final_amount) or staged


func cancel_active_attack() -> void:
	if not _launch_runtime.snapshot().is_empty() and not _launch_runtime.snapshot().terminal:
		_launch_runtime.cancel_action(&"interrupted")
	if _hostile_threat_registry != null:
		_hostile_threat_registry.retire_source(hostile_source_id)


func _hostile_runtime_frame() -> int:
	return int(_launch_runtime.snapshot().get("runtime_frame", 0))


func _on_damaged(_amount: float, _current_hp: float) -> void:
	_refresh_control_visual()


func _on_died(_killer: Variant) -> void:
	if not _death_receipt.is_empty():
		return
	cancel_active_attack()
	_launch_runtime.cancel(&"death")
	clear_weapon_hit_control_state(&"death")
	reset_elemental_statuses()
	_hostile_identity_active = false
	remove_from_group("enemies")
	remove_from_group("time_stoppable")
	_death_receipt = "hostile_defeat:%s" % (str(_launch_identity.get("run_id", "")) + "|" + str(hostile_source_id)).sha256_text().substr(0, 40)
	_refresh_control_visual()
	var retirement := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	retirement.tween_interval(0.2)
	retirement.tween_callback(queue_free)
	hostile_final_death.emit(hostile_source_id, _death_receipt)


func _refresh_control_visual() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty():
		return
	match state.action.phase:
		"WARNING": sprite.frame = 1
		"ACTIVE": sprite.frame = 2
		"RECOVERY": sprite.frame = 3
		_: sprite.frame = 0
	sprite.modulate = Color(0.55, 0.95, 1.0) if is_time_stopped() or is_elementally_frozen() else Color.WHITE
	if state.terminal:
		sprite.modulate = Color(0.45, 0.45, 0.45)


func _actor_state() -> Dictionary:
	var metadata: Dictionary = {}
	for field: String in WEAPON_METADATA_FIELDS:
		if has_meta(field):
			var value: Variant = get_meta(field)
			metadata[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return {"runtime": _launch_runtime.snapshot(), "status": elemental_status_runtime.transaction_snapshot(), "position": _point(global_position), "knockback": _point(_knockback_velocity), "weakpoint_sequence": _weakpoint_token, "stop_sequence": _time_stop_token_sequence, "weapon_claims": _weapon_hit_control_claims.duplicate(true), "weapon_claim_order": _weapon_hit_control_claim_order.duplicate(), "blind_sequence": _elemental_blind_action_sequence, "action_credit": _action_credit, "death_receipt": _death_receipt, "weapon_metadata": metadata}


func _can_restore_actor_state(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, ACTOR_STATE_FIELDS) or not value.runtime is Dictionary or not _launch_runtime.can_restore_snapshot(value.runtime) or not value.status is Dictionary or not elemental_status_runtime.can_restore_transaction_snapshot(value.status):
		return false
	if not Contract.valid_point(value.position) or not Contract.valid_point(value.knockback) or not Contract.number_in_range(value.action_credit, 0.0, 1.0) or typeof(value.death_receipt) != TYPE_STRING:
		return false
	if not value.weapon_metadata is Dictionary:
		return false
	for field: Variant in value.weapon_metadata:
		if typeof(field) != TYPE_STRING or field not in WEAPON_METADATA_FIELDS:
			return false
		var metadata_value: Variant = value.weapon_metadata[field]
		if field == "elemental_status_seed_initialized" and typeof(metadata_value) != TYPE_INT:
			return false
		if field == "elemental_status_seed_material" and typeof(metadata_value) != TYPE_STRING:
			return false
		if field in ["bow_time_erosion_sources", "planewalker_replay_external_fact_claims"] and not metadata_value is Dictionary:
			return false
	for field: String in ["weakpoint_sequence", "stop_sequence", "blind_sequence"]:
		if typeof(value[field]) != TYPE_INT or int(value[field]) < 0:
			return false
	if not value.weapon_claims is Dictionary or not value.weapon_claim_order is Array or value.weapon_claim_order.size() > MAX_WEAPON_HIT_CONTROL_CLAIMS or value.weapon_claims.size() != value.weapon_claim_order.size():
		return false
	var seen: Dictionary = {}
	for token: Variant in value.weapon_claim_order:
		if typeof(token) != TYPE_INT or token <= 0 or seen.has(token) or value.weapon_claims.get(token) != true:
			return false
		seen[token] = true
	return true


func _restore_actor_state(value: Dictionary) -> bool:
	if not _can_restore_actor_state(value):
		return false
	_launch_runtime.restore_snapshot(value.runtime)
	elemental_status_runtime.restore_transaction_snapshot(value.status)
	global_position = _vector(value.position)
	_knockback_velocity = _vector(value.knockback)
	_weakpoint_token = value.weakpoint_sequence
	_time_stop_token_sequence = value.stop_sequence
	_weapon_hit_control_claims = value.weapon_claims.duplicate(true)
	_weapon_hit_control_claim_order.assign(value.weapon_claim_order)
	_elemental_blind_action_sequence = value.blind_sequence
	_action_credit = float(value.action_credit)
	_death_receipt = value.death_receipt
	for field: String in WEAPON_METADATA_FIELDS:
		if value.weapon_metadata.has(field):
			var metadata_value: Variant = value.weapon_metadata[field]
			set_meta(field, metadata_value.duplicate(true) if metadata_value is Dictionary else metadata_value)
		elif has_meta(field):
			remove_meta(field)
	return true


func _ticket_matches(ticket: Dictionary) -> bool:
	return Contract.exact_fields(ticket, FRAME_TICKET_FIELDS) and not _prepared_launch_frame.is_empty() and ticket == _prepared_launch_frame


static func _seconds_to_frames(value: float) -> int:
	return ceili(value * 60.0) if is_finite(value) and value > 0.0 and value <= 600.0 else 0


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _launch_failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_ACTOR_INVALID", "context": {"field": field}}
