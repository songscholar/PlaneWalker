class_name LaunchHostileActor
extends "res://scripts/enemies/enemy_base.gd"

const LaunchRuntime := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const LaunchStatus := preload("res://scripts/enemies/launch/launch_elemental_status_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const RoomContract := preload("res://scripts/dungeon/room_scene_contract.gd")
const SummonContract := preload("res://scripts/enemies/launch/summon_definition.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const AffixProjection := preload("res://scripts/enemies/launch/launch_elite_affix_projection.gd")
const AffixRuntime := preload("res://scripts/enemies/launch/launch_elite_affix_runtime.gd")
const AffixCue := preload("res://scripts/enemies/launch/launch_elite_affix_cue.gd")
const Chaining := preload("res://scripts/enemies/launch/launch_elite_chaining_runtime.gd")
const SceneScope := preload("res://scripts/player/player_scene_scope.gd")
const TelegraphProjection := preload("res://scripts/enemies/launch/launch_hostile_telegraph_projection.gd")
const HoundSigil := preload("res://scripts/enemies/launch/launch_hound_sigil.gd")
const SigilDamage := preload("res://scripts/combat/damage_info.gd")
const SigilCalculator := preload("res://scripts/combat/damage_calculator.gd")
const PhaseShift := preload("res://scripts/enemies/launch/phase_ranger_shift_runtime.gd")
const PhaseArrival := preload("res://scripts/enemies/launch/phase_ranger_arrival_cue.gd")
const FRAME_TICKET_FIELDS: Array[String] = ["ticket_id", "hostile_source_id", "runtime_frame", "before", "after", "batch", "health_before", "collision_target"]
const ACTOR_STATE_FIELDS: Array[String] = ["runtime", "status", "position", "knockback", "weakpoint_sequence", "stop_sequence", "weapon_claims", "weapon_claim_order", "blind_sequence", "action_credit", "death_receipt", "weapon_metadata", "room_motion"]
const WEAPON_METADATA_FIELDS: Array[String] = ["bow_time_erosion_sources", "elemental_status_seed_initialized", "elemental_status_seed_material", "planewalker_replay_external_fact_claims"]

signal hostile_final_death(source_id: StringName, receipt_id: String)

var _launch_runtime: RefCounted = _create_launch_runtime()
var _body_preview_runtime: RefCounted
var _launch_definition: Dictionary = {}
var _launch_identity: Dictionary = {}
var _prepared_launch_frame: Dictionary = {}
var _prepared_frame_committed := false
var _next_launch_ticket_id := 1
var _action_credit := 0.0
var _death_receipt := ""
var _room_motion: Dictionary = {}
var _motion_room: Node2D
var _motion_room_transform := Transform2D.IDENTITY
var _motion_room_local_bounds := Rect2()
var _affix_projection: RefCounted
var _affix_configuration: Dictionary = {}
var _affix_runtime: RefCounted
var _shield_absorption_commit_fault_for_test := false
var _body_damage_commit_fault_for_test := false
var _sigil_terminal_damage: RefCounted
var _hound_construct_authority: WeakRef


func _init() -> void:
	elemental_status_runtime = _create_launch_status_runtime()


func _create_launch_runtime() -> RefCounted:
	return LaunchRuntime.new()


func _create_launch_status_runtime() -> RefCounted:
	return LaunchStatus.new()


func _ready() -> void:
	super._ready()
	visual.visible = false
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	_refresh_control_visual()


func owns_actor_presentation() -> bool:
	return true


func configure_launch_affixes(definitions: Array, floor_index: int, native_revision: int = AffixProjection.CURRENT_NATIVE_REVISION) -> Dictionary:
	if not _launch_definition.is_empty() or _affix_projection != null or not _prepared_launch_frame.is_empty():
		return _launch_failure("affix_configuration_busy")
	var candidate := AffixProjection.new()
	var accepted := candidate.configure(definitions, floor_index, native_revision)
	if not accepted.ok:
		return _launch_failure("affix_configuration")
	_affix_projection = candidate
	return {"ok": true}


func launch_affix_snapshot() -> Dictionary:
	return _affix_configuration.duplicate(true)


func launch_affix_runtime_snapshot() -> Dictionary:
	return _affix_runtime.snapshot() if _affix_runtime != null else {}


func configure_launch_definition(definition: Dictionary, context: Dictionary) -> Dictionary:
	if not _prepared_launch_frame.is_empty() or health == null or not _room_motion.is_empty():
		return _launch_failure("not_ready_or_busy")
	var affix_configuration := {}
	if _affix_projection != null:
		var projected: Dictionary = _affix_projection.project(definition)
		if not projected.ok:
			return _launch_failure("affix_projection")
		definition = projected.definition
		affix_configuration = projected.configuration
	var candidate: RefCounted = _create_launch_runtime()
	var configured: Dictionary = candidate.configure(definition, context)
	if not configured.ok:
		return configured
	var affix_runtime: RefCounted
	if affix_configuration.get("native_revision") in [2, 3, 4, 5, 6, 7, 8, 9, 10]:
		affix_runtime = AffixRuntime.new()
		if not affix_runtime.configure(affix_configuration, context, float(definition.max_hp)):
			return _launch_failure("affix_runtime")
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var hurt := get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D
	if body == null or hurt == null or not body.shape is CircleShape2D or not hurt.shape is CircleShape2D:
		return _launch_failure("body_shapes")
	if not health.configure_run(StringName(context.run_id)):
		return _launch_failure("health_run")
	_launch_runtime = candidate
	_body_preview_runtime = null
	_affix_configuration = affix_configuration
	_affix_runtime = affix_runtime
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
	body.shape = body.shape.duplicate()
	hurt.shape = hurt.shape.duplicate()
	(body.shape as CircleShape2D).radius = float(definition.collision_radius_px)
	(hurt.shape as CircleShape2D).radius = float(definition.collision_radius_px)
	configure_elemental_status_seed(int(context.seed), 0.40, 0.40)
	_action_credit = 0.0
	_death_receipt = ""
	_refresh_control_visual()
	return {"ok": true, "snapshot": launch_runtime_snapshot()}


func configure_launch_room_motion(room: Node2D, template: Dictionary) -> Dictionary:
	if _launch_definition.is_empty() or not _prepared_launch_frame.is_empty() or not _room_motion.is_empty() or int(_launch_runtime.snapshot().runtime_frame) != int(_launch_identity.runtime_frame):
		return _launch_failure("room_motion_busy")
	var verified: Dictionary = RoomContract.validate(room, template)
	if not verified.ok or not room.is_inside_tree() or not _translation_only(room.global_transform) or not _native_geometry_matches_definition() or collision_layer != 4 or not get_collision_mask_value(1):
		return _launch_failure("room_motion_contract")
	var local_bounds: Rect2 = verified.context.camera_bounds
	if _physical_camera_bounds(room) != local_bounds:
		return _launch_failure("room_motion_camera")
	var bounds := Rect2(local_bounds.position + room.global_position, local_bounds.size)
	var radius := float(_launch_definition.collision_radius_px)
	if bounds.size.x <= radius * 2.0 or bounds.size.y <= radius * 2.0 or not _within_bounds(global_position, bounds, radius):
		return _launch_failure("room_motion_position")
	_room_motion = {"room_id": str(verified.context.content_id), "bounds": {"x": bounds.position.x, "y": bounds.position.y, "width": bounds.size.x, "height": bounds.size.y}, "collision_radius_px": radius, "collision_layer": collision_layer, "collision_mask": collision_mask}
	_motion_room = room
	_motion_room_transform = room.global_transform
	_motion_room_local_bounds = local_bounds
	return {"ok": true, "room_motion": launch_room_motion_snapshot()}


func launch_room_motion_snapshot() -> Dictionary:
	return _room_motion.duplicate(true)


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
	if not _room_motion.is_empty() and (not _room_motion_is_valid() or not _within_bounds(global_position, _motion_bounds(), float(_launch_definition.collision_radius_px))):
		return _launch_failure("room_motion")
	if not Contract.exact_fields(observations, HostileActionCoordinator.CONTEXT_FIELDS) or not Contract.valid_point(observations.source_position) or not _vector(observations.source_position).is_equal_approx(global_position):
		return _launch_failure("source_position")
	var before := _actor_state()
	var preview: RefCounted = _create_launch_runtime()
	preview.configure(_launch_definition, _launch_identity)
	if not preview.restore_snapshot(before.runtime):
		return _launch_failure("runtime_checkpoint")
	var status_preview: RefCounted = _create_launch_status_runtime()
	if not status_preview.restore_transaction_snapshot(before.status):
		return _launch_failure("status_checkpoint")
	var next_credit := _action_credit
	var anchored_recovery: bool = _affix_runtime != null and _affix_runtime.is_anchor_recovering()
	var nullified_delay: bool = _affix_runtime != null and _affix_runtime.is_nullified_delayed(frame)
	var teleport_recovery: bool = _affix_runtime != null and _affix_runtime.teleport_blocks_actions()
	var externally_paused: bool = status_preview.is_frozen() or _native_action_activation_blocked(frame, observations) or anchored_recovery or nullified_delay or teleport_recovery
	if not externally_paused and not preview.control_modifiers().action_paused:
		next_credit += minf(1.0, float(status_preview.attack_speed_multiplier()))
		externally_paused = next_credit < 1.0
		if not externally_paused:
			next_credit -= 1.0
	var lethal_pending: bool = health.dead
	var motion: Dictionary = preview.motion_for_frame(frame, observations)
	if not motion.ok:
		return motion
	var phase_observation := {}
	var phase_relocation := {}
	var phase_paused := false
	var phase_blocks := false
	if _launch_definition.runtime_kind == "phase_ranger":
		phase_paused = lethal_pending or externally_paused or bool(motion.action_paused)
		phase_observation = _phase_frame_observation(before.runtime, phase_paused)
		var shifted: Dictionary = preview.phase_shift_for_frame(frame, phase_paused, phase_observation)
		if not shifted.ok:
			return shifted
		phase_relocation = shifted.relocation
		var action_busy: bool = before.runtime.action.phase != "IDLE" or phase_paused
		phase_blocks = PhaseShift.blocks_actions(before.runtime.mechanism_state.phase_shift, _launch_definition.mechanisms, action_busy) or PhaseShift.blocks_actions(shifted.state, _launch_definition.mechanisms, action_busy)
	var affix_after := {}
	var affix_heal := {"healed_amount": 0.0, "hp_after": health.current_hp}
	var teleport_relocation := {}
	if _affix_runtime != null:
		var affix_preview := AffixRuntime.new()
		if not affix_preview.configure(_affix_configuration, _launch_identity, max_hp) or not affix_preview.restore_snapshot(before.affix_runtime):
			return _launch_failure("affix_checkpoint")
		var affix_paused: bool = status_preview.is_frozen() or (externally_paused and not anchored_recovery and not teleport_recovery) or nullified_delay or bool(motion.action_paused) or phase_blocks
		var advanced: Dictionary = affix_preview.advance_frame(frame, health.current_hp, lethal_pending, affix_paused, health.healing_multiplier, _teleport_frame_observation(affix_preview, affix_paused), _point(global_position))
		if not advanced.ok:
			return _launch_failure("affix_frame")
		affix_after = affix_preview.snapshot()
		affix_heal = {"healed_amount": advanced.healed_amount, "hp_after": advanced.hp_after}
		teleport_relocation = advanced.teleport_relocation
	var relocation: bool = bool(motion.get("relocation", false))
	var displacement := _vector(motion.displacement) * (1.0 if relocation else float(status_preview.slow_multiplier()))
	if lethal_pending or externally_paused or motion.action_paused or phase_blocks:
		displacement = Vector2.ZERO
	else:
		displacement += _knockback_velocity / 60.0
	if not teleport_relocation.is_empty():
		relocation = true
		displacement = _vector(teleport_relocation) - global_position
	if not phase_relocation.is_empty():
		relocation = true
		displacement = _vector(phase_relocation) - global_position
	if not _room_motion.is_empty():
		displacement = _constrain_to_room(global_position + displacement) - global_position
	var predicted := global_position
	var collision_target: Node2D
	if not displacement.is_zero_approx():
		if relocation:
			var destination := global_position + displacement
			var arrival_transform := global_transform
			arrival_transform.origin = destination
			if _native_relocation_allowed(destination, observations) and not test_move(arrival_transform, Vector2.ZERO, null, 0.08, true):
				predicted = destination
		elif not _room_motion.is_empty() and bool(_launch_definition.mechanisms.get("internal_obstacle_passthrough", false)):
			predicted += displacement
		else:
			var collision := move_and_collide(displacement, true)
			predicted += collision.get_travel() if collision != null else displacement
			if collision != null and collision.get_collider() is Node2D:
				collision_target = collision.get_collider() as Node2D
	if not _room_motion.is_empty():
		predicted = _constrain_to_room(predicted)
	var committed_observations := observations.duplicate(true)
	committed_observations.source_position = _point(predicted)
	var batch: Dictionary
	if _launch_definition.runtime_kind == "phase_ranger":
		batch = preview.advance_phase_frame(frame, committed_observations, not lethal_pending, externally_paused or lethal_pending, phase_paused, phase_observation)
	else:
		batch = preview.advance_frame(frame, committed_observations, not lethal_pending, externally_paused or lethal_pending)
	if not batch.ok:
		return batch
	if batch.phase == "WARNING" and not _native_summon_warning_safe(preview.snapshot().action):
		var declined: Dictionary = preview.cancel_action(&"summon_frozen_slot_outside_safe_room")
		if not declined.ok:
			return _launch_failure("summon_warning_decline")
		batch.threat_facts = []
		batch.threat_extensions = []
		batch.retired_generations.append_array(declined.retired_generations)
		batch.phase = "IDLE"
	# A charge's frozen corridor warns its route; damage requires real body contact.
	var contact_fact: Dictionary = preview.charge_contact_fact(frame, str(observations.target_id))
	if not contact_fact.is_empty():
		batch.hit_facts = [contact_fact] if collision_target != null else []
	var status_events: Dictionary = {"burn_ticks": []}
	if lethal_pending:
		if _launch_definition.runtime_kind == "corrosive_moth":
			if _room_motion.is_empty():
				return _launch_failure("death_payload_room")
			var death_pool: Dictionary = preview.reserve_terminal_death_pool(_point(predicted), _room_motion.bounds)
			if death_pool.is_empty():
				return _launch_failure("death_payload_generation")
			batch.mechanism_requests = [death_pool]
		var cancelled: Dictionary = preview.cancel(&"death")
		if cancelled.ok:
			batch.retired_generations = cancelled.retired_generations
		else:
			batch.retired_generations = before.runtime.action.geometry_generations.duplicate()
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
	if _affix_runtime != null and preview.snapshot().terminal:
		var terminal_affix := AffixRuntime.new()
		terminal_affix.configure(_affix_configuration, _launch_identity, max_hp)
		terminal_affix.restore_snapshot(before.affix_runtime)
		terminal_affix.advance_frame(frame, health.current_hp, true, false, health.healing_multiplier)
		affix_after = terminal_affix.snapshot()
		affix_heal = {"healed_amount": 0.0, "hp_after": health.current_hp}
	batch["status_tick_requests"] = status_events.burn_ticks.duplicate(true)
	if _affix_runtime != null:
		batch["affix_heal"] = affix_heal
	var after := before.duplicate(true)
	after.runtime = preview.snapshot()
	after.status = status_preview.transaction_snapshot()
	after.position = _point(predicted)
	after.knockback = _point(_knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() / 60.0))
	after.action_credit = next_credit
	if _affix_runtime != null:
		after.affix_runtime = affix_after
	var ticket := {"ticket_id": _next_launch_ticket_id, "hostile_source_id": str(hostile_source_id), "runtime_frame": frame, "before": before, "after": after, "batch": batch, "health_before": health.runtime_state_snapshot(), "collision_target": collision_target}
	_next_launch_ticket_id += 1
	_prepared_launch_frame = ticket.duplicate(true)
	_prepared_frame_committed = false
	return {"ok": true, "ticket": ticket.duplicate(true), "batch": batch.duplicate(true)}


func _native_summon_warning_safe(action: Dictionary) -> bool:
	if _room_motion.is_empty() or not action.committed_geometry.any(func(row: Dictionary): return row.shape == "summon_slots"):
		return true
	var recipe := {}
	for candidate: Dictionary in _launch_definition.actions:
		if candidate.id == action.action_id and candidate.handler_id == "summon":
			recipe = candidate
			break
	var contract: Dictionary = SummonContract.CONTRACTS.get(recipe.get("parameters", {}).get("definition_id", ""), {})
	if contract.is_empty():
		return false
	var radius := float(contract.collision_radius_px)
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for geometry: Dictionary in action.committed_geometry:
		for slot: Dictionary in geometry.summon_slots:
			var point := _vector(slot)
			if not _within_bounds(point, _motion_bounds(), radius):
				return false
			query.transform = Transform2D(0.0, point)
			if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				return false
	return true


func _native_action_activation_blocked(_frame: int, _observations: Dictionary) -> bool:
	return false


func _native_relocation_allowed(_destination: Vector2, _observations: Dictionary) -> bool:
	return true


func _teleport_frame_observation(affix: RefCounted, paused: bool) -> Dictionary:
	if not affix.is_teleporting():
		return {}
	var landing := {}
	var allowed := false
	var state: Dictionary = affix.snapshot().teleporting
	if not paused and affix.teleport_reservation_due() and not _room_motion.is_empty():
		for offset: Vector2 in affix.teleport_candidate_offsets():
			var candidate := global_position + offset
			if _teleport_landing_safe(candidate):
				landing = _point(candidate)
				break
	elif not paused and state.phase == "DEPARTURE" and int(state.remaining_frames) == 1:
		var reservation: Dictionary = state.reservations.back()
		allowed = _vector(reservation.origin).is_equal_approx(global_position) and _teleport_landing_safe(_vector(reservation.landing))
	return {"source_position": _point(global_position), "landing_position": landing, "arrival_allowed": allowed}


func _teleport_landing_safe(destination: Vector2) -> bool:
	if _room_motion.is_empty() or not _room_motion_is_valid() or not _within_bounds(destination, _motion_bounds(), float(_launch_definition.collision_radius_px)):
		return false
	var arrival_transform := global_transform
	arrival_transform.origin = destination
	return not test_move(arrival_transform, Vector2.ZERO, null, 0.08, true)


func _teleport_candidate_remains_safe(ticket: Dictionary) -> bool:
	var state: Dictionary = ticket.get("after", {}).get("affix_runtime", {}).get("teleporting", {})
	if state.is_empty() or state.reservations.is_empty():
		return true
	var receipt: Dictionary = state.reservations.back()
	return receipt.outcome != "LANDED" or int(receipt.arrival_runtime_frame) != int(ticket.runtime_frame) or _teleport_landing_safe(_vector(receipt.landing))


func _phase_frame_observation(runtime: Dictionary, paused: bool) -> Dictionary:
	var landing := {}
	var allowed := false
	var state: Dictionary = runtime.mechanism_state.phase_shift
	if not paused and runtime.action.phase == "IDLE" and PhaseShift.reservation_due(state, _launch_definition.mechanisms):
		for offset: Vector2 in PhaseShift.candidate_offsets(state, _launch_identity, _launch_definition.mechanisms):
			var candidate := global_position + offset
			if _phase_landing_safe(candidate):
				landing = _point(candidate)
				break
	elif not paused and state.enabled and state.phase == "DEPARTURE" and int(state.remaining_frames) == 1:
		var reservation: Dictionary = state.reservations.back()
		allowed = _vector(reservation.origin).is_equal_approx(global_position) and _phase_landing_safe(_vector(reservation.landing))
	return {"source_position": _point(global_position), "landing_position": landing, "arrival_allowed": allowed}


func _phase_landing_safe(destination: Vector2) -> bool:
	if not _teleport_landing_safe(destination):
		return false
	var shape := CircleShape2D.new()
	shape.radius = float(_launch_definition.collision_radius_px)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, destination)
	query.collision_mask = 2 | 4
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _phase_candidate_remains_safe(ticket: Dictionary) -> bool:
	var state: Dictionary = ticket.get("after", {}).get("runtime", {}).get("mechanism_state", {}).get("phase_shift", {})
	if state.is_empty() or not state.enabled or state.reservations.is_empty():
		return true
	var receipt: Dictionary = state.reservations.back()
	return receipt.outcome != "LANDED" or int(receipt.arrival_runtime_frame) != int(ticket.runtime_frame) or _phase_landing_safe(_vector(receipt.landing))


func can_commit_launch_frame(ticket: Dictionary) -> bool:
	return _ticket_matches(ticket) and not _prepared_frame_committed and _actor_state() == ticket.before and health.runtime_state_snapshot() == ticket.health_before and _can_restore_actor_state(ticket.after) and _teleport_candidate_remains_safe(ticket) and _phase_candidate_remains_safe(ticket)


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
	return _ticket_matches(ticket) and _prepared_frame_committed and (_room_motion.is_empty() or (_room_motion_is_valid() and _within_bounds(global_position, _motion_bounds(), float(_launch_definition.collision_radius_px)))) and _teleport_candidate_remains_safe(ticket) and _phase_candidate_remains_safe(ticket)


func publish_launch_frame(ticket: Dictionary) -> bool:
	if not can_publish_launch_frame(ticket):
		return false
	_prepared_launch_frame.clear()
	_prepared_frame_committed = false
	_refresh_control_visual()
	return true


func prepared_launch_frame_batch() -> Dictionary:
	return (_prepared_launch_frame.get("batch", {}) as Dictionary).duplicate(true)


func prepared_launch_mirroring_reservation() -> Dictionary:
	if _prepared_launch_frame.is_empty() or _affix_runtime == null or not _affix_runtime.is_mirroring() or _prepared_launch_frame.after.runtime.terminal:
		return {}
	var before: Array = _prepared_launch_frame.before.affix_runtime.mirroring.reservations
	var after: Array = _prepared_launch_frame.after.affix_runtime.mirroring.reservations
	return after.back().duplicate(true) if after.size() == before.size() + 1 else {}


func launch_mirroring_reservations() -> Array:
	return _affix_runtime.snapshot().get("mirroring", {}).get("reservations", []).duplicate(true) if _affix_runtime != null else []


func native_splitting_configuration() -> Dictionary:
	return _affix_configuration.duplicate(true) if _affix_runtime != null and _affix_runtime.is_splitting() else {}


func prepared_launch_frame_position() -> Vector2:
	return _vector(_prepared_launch_frame.after.position) if not _prepared_launch_frame.is_empty() else global_position


func prepared_launch_frame_consumes_actor() -> bool:
	if _prepared_launch_frame.is_empty() or _launch_definition.runtime_kind not in ["ruins_wraith", "void_spore"] or not bool(_prepared_launch_frame.after.runtime.terminal):
		return false
	var mechanism: Dictionary = _prepared_launch_frame.after.runtime.mechanism_state
	return bool(mechanism.get("detonation_consumed", mechanism.get("burst_consumed", false))) and _prepared_launch_frame.batch.mechanism_requests.size() == 1


func prepared_launch_frame_contacts_target(target: Node2D) -> bool:
	return not _prepared_launch_frame.is_empty() and is_instance_valid(target) and _prepared_launch_frame.collision_target == target


func prepared_launch_payload_parameters() -> Dictionary:
	if _prepared_launch_frame.is_empty() or _launch_definition.runtime_kind != "corrosive_moth":
		return {}
	var result: Dictionary = _launch_definition.mechanisms.duplicate(true)
	if _launch_definition.has("mechanism_scaling"):
		result["mechanism_scaling"] = _launch_definition.mechanism_scaling.duplicate(true)
	return result


func prepared_launch_frame_reserves_death_pool() -> bool:
	return not _prepared_launch_frame.is_empty() and _launch_definition.runtime_kind == "corrosive_moth" and health.dead and bool(_prepared_launch_frame.after.runtime.terminal) and bool(_prepared_launch_frame.after.runtime.mechanism_state.death_pool_reserved) and _prepared_launch_frame.batch.mechanism_requests.size() == 1 and _prepared_launch_frame.batch.mechanism_requests[0].kind == "death_pool"


func launch_transaction_snapshot() -> Dictionary:
	if _launch_definition.is_empty():
		return {}
	return {"schema_version": 1, "hostile_source_id": str(hostile_source_id), "actor": _actor_state(), "health": health.transaction_snapshot()}


func can_restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, ["schema_version", "hostile_source_id", "actor", "health"]) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.hostile_source_id != str(hostile_source_id) or not value.actor is Dictionary or not _can_restore_actor_state(value.actor) or not value.health is Dictionary or not bool(health.call("_valid_health_transaction_snapshot", value.health)):
		return false
	return not (bool(value.actor.runtime.mechanism_state.get("detonation_consumed", false)) or bool(value.actor.runtime.mechanism_state.get("death_pool_reserved", false))) or bool(value.health.dead)


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
		if _affix_runtime != null and _affix_runtime.is_nullified():
			_affix_runtime.accept_nullified_stop(str(source_id))
		else:
			_launch_runtime.add_control_source(str(source_id), "stop", frames, 1.0)
	_refresh_control_visual()


func clear_time_stop_source(source_id: StringName) -> void:
	_launch_runtime.clear_control_source(str(source_id))
	if _affix_runtime != null:
		_affix_runtime.clear_nullified_stop(str(source_id))
	_refresh_control_visual()


func is_time_stopped() -> bool:
	return _launch_runtime.control_modifiers().action_paused or (_affix_runtime != null and _affix_runtime.is_nullified_delayed())


func apply_time_rift(source_id: StringName, slow_multiplier: float) -> void:
	if _affix_runtime != null and _affix_runtime.is_nullified() and Contract.number_in_range(slow_multiplier, 0.000001, 1.0):
		slow_multiplier = maxf(slow_multiplier, _affix_runtime.rift_movement_floor())
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
	if _sigil_terminal_damage != null:
		return 1.0
	var affix_bonus: float = _affix_runtime.nullified_damage_bonus() + _affix_runtime.shield_damage_bonus() if _affix_runtime != null else 0.0
	return minf(3.0, (float(_launch_runtime.control_modifiers().damage_taken_multiplier) + elemental_status_runtime.shock_damage_bonus() + affix_bonus) * _launch_runtime.species_damage_taken_multiplier() * float(_affix_configuration.get("damage_taken_multiplier", 1.0)))


func prepare_post_defense_absorption(damage_info: RefCounted, resolution: RefCounted) -> Dictionary:
	if damage_info == _sigil_terminal_damage:
		return {}
	if _affix_runtime == null or not _affix_runtime.is_shielded():
		return {}
	if damage_info == null or resolution == null or resolution.is_prevented():
		return {"ok": false}
	var source_player: Node = damage_info.attacker
	var current_component_identity: bool = int(_affix_configuration.native_revision) >= 7
	var owned_player_source: bool
	var valid_run: bool
	var valid_target: bool
	if current_component_identity:
		owned_player_source = is_instance_valid(source_player) and source_player is PlayerController and source_player.authenticates_native_damage_run(damage_info, self, StringName(str(_launch_identity.run_id)))
		valid_run = str(damage_info.run_id) == str(_launch_identity.run_id) or (damage_info.run_id in [&"legacy_run", &"runtime"] and owned_player_source)
		valid_target = damage_info.target_id == hostile_source_id or (has_meta("encounter_spawn_id") and str(damage_info.target_id) == str(get_meta("encounter_spawn_id")))
		if owned_player_source:
			valid_target = valid_target or damage_info.target_id == &"pending_target"
			for field: String in ["encounter_spawn_id", "spawn_id", "stable_target_id"]:
				if has_meta(field) and str(damage_info.target_id) == "target:" + str(get_meta(field)):
					valid_target = true
	else:
		owned_player_source = is_instance_valid(source_player) and source_player.is_in_group("player") and source_player.has_method("current_run_id") and str(source_player.current_run_id()) == str(_launch_identity.run_id)
		valid_run = str(damage_info.run_id) == str(_launch_identity.run_id) or (damage_info.run_id == &"legacy_run" and owned_player_source)
		valid_target = damage_info.target_id == hostile_source_id or (has_meta("encounter_spawn_id") and str(damage_info.target_id) == str(get_meta("encounter_spawn_id"))) or (damage_info.target_id == &"pending_target" and owned_player_source)
	if not valid_run or not valid_target:
		return {"ok": false}
	var frame: int = health.frame_signal_transaction_runtime_frame()
	if frame < 0:
		frame = _hostile_runtime_frame()
	var fact_identity := [str(_launch_identity.run_id), str(hostile_source_id), str(damage_info.hostile_source_id), int(damage_info.attack_generation), int(damage_info.hit_index)]
	if current_component_identity:
		fact_identity.append(int(damage_info.damage_type))
	var fact_id := JSON.stringify(fact_identity, "", false).sha256_text()
	return _affix_runtime.prepare_shield_absorption(frame, fact_id, float(resolution.finalized_damage()))


func commit_post_defense_absorption(damage_info: RefCounted, resolution: RefCounted, decision: Dictionary) -> bool:
	if _shield_absorption_commit_fault_for_test or not health.owns_post_defense_absorption_commit(damage_info, resolution, decision) or decision != prepare_post_defense_absorption(damage_info, resolution) or not _affix_runtime.restore_snapshot(decision.receipt.after):
		return false
	# Absorbed launch controls reach Anchor without manufacturing body damage facts.
	var anchor: Dictionary = _affix_runtime.snapshot().get("anchored", {})
	if float(decision.amount_after) == 0.0 and float(decision.absorbed) > 0.0 and not anchor.is_empty() and int(anchor.control_count) < Contract.MAX_FRAME and super.apply_weapon_hit_control(damage_info, float(decision.absorbed)):
		var frame: int = health.frame_signal_transaction_runtime_frame()
		_affix_runtime.accept_launch_control(_hostile_runtime_frame() if frame < 0 else frame)
	_refresh_control_visual()
	return true


func rollback_post_defense_absorption(damage_info: RefCounted, resolution: RefCounted, decision: Dictionary) -> bool:
	if not health.owns_post_defense_absorption_commit(damage_info, resolution, decision, true) or _affix_runtime == null or _affix_runtime.snapshot() != decision.receipt.after or not _affix_runtime.restore_snapshot(decision.receipt.before):
		return false
	_refresh_control_visual()
	return true


func apply_knockback(knockback: Vector2) -> void:
	var displacement: float = _affix_runtime.displacement_multiplier() if _affix_runtime != null else 1.0
	super.apply_knockback(knockback * displacement * (1.0 - float(_affix_configuration.get("knockback_resistance", 0.0))))


func prepare_hostile_lethal_transition(damage_info: RefCounted, final_amount: float) -> Dictionary:
	if damage_info == _sigil_terminal_damage:
		return {}
	if _launch_definition.get("runtime_kind", "") not in ["chrono_guard", "eternal_hound"]:
		return {}
	if not is_instance_valid(health) or health.dead or damage_info == null or not is_finite(final_amount) or final_amount < health.current_hp or not _launch_runtime.has_method("prepare_lethal_transition"):
		return {"ok": false}
	var lethal_frame: int = health.frame_signal_transaction_runtime_frame()
	if lethal_frame < 0:
		lethal_frame = int(_launch_runtime.snapshot().runtime_frame)
	var decision: Dictionary = _launch_runtime.prepare_lethal_transition(lethal_frame)
	if not decision.ok:
		return decision
	if not decision.final_death and _launch_definition.runtime_kind == "eternal_hound" and _hound_construct_authority != null:
		var authority: RefCounted = _hound_construct_authority.get_ref()
		if authority == null or authority.native_construct_count() >= 8:
			return {"ok": false}
	decision["owner_instance_id"] = get_instance_id()
	decision["health_instance_id"] = health.get_instance_id()
	decision["health_before"] = health.runtime_state_snapshot()
	decision["damage_digest"] = var_to_bytes(damage_info.snapshot()).hex_encode().sha256_text()
	return decision


func blocks_hostile_body_damage() -> bool:
	return _sigil_terminal_damage == null and _launch_definition.get("runtime_kind", "") == "eternal_hound" and int(_launch_runtime.snapshot().get("mechanism_state", {}).get("dormancy_remaining_frames", 0)) > 0


func bind_native_construct_budget(authority: RefCounted) -> bool:
	if authority == null or not authority.has_method("native_construct_count") or not authority.register_native_construct_owner(self):
		return false
	_hound_construct_authority = weakref(authority)
	return true


func native_weapon_target_is_active() -> bool:
	return _hostile_identity_active and not health.dead and not blocks_hostile_body_damage()


func receive_native_hound_sigil_hit(info: RefCounted) -> float:
	if info == null or not info.is_valid() or _launch_definition.get("id") != "eternal_hound" or _sigil_terminal_damage != null or not _native_geometry_matches_definition():
		return 0.0
	var attacker: Node = info.attacker
	if not attacker is PlayerController or not attacker.authenticates_native_damage_run(info, self, StringName(str(_launch_identity.run_id))):
		return 0.0
	var amount := SigilCalculator.critical_amount(info, float(info.amount))
	if not Contract.number_in_range(amount, 0.000001, 1000000.0):
		return 0.0
	var before: Dictionary = _launch_runtime.snapshot()
	var claim := JSON.stringify([str(_launch_identity.run_id), str(hostile_source_id), str(info.hostile_source_id), int(info.attack_generation), int(info.hit_index), int(info.damage_type)], "", false).sha256_text()
	var result: Dictionary = _launch_runtime.accept_sigil_damage(claim, amount)
	if not result.ok:
		return 0.0
	if result.final_death:
		# The construct settles one original-principal kill through sealed Health publication.
		var plan: Dictionary = info.snapshot()
		plan.amount = health.current_hp
		plan.target_id = str(hostile_source_id)
		plan.can_crit = false
		plan.control_effect = {}
		_sigil_terminal_damage = SigilDamage.from_plan(plan)
		health.take_damage(_sigil_terminal_damage)
		_sigil_terminal_damage = null
		if not health.dead:
			_launch_runtime.restore_snapshot(before)
			_refresh_control_visual()
			return 0.0
	_refresh_control_visual()
	return float(before.mechanism_state.sigil_hp) - float(result.sigil_hp)


func prepare_hostile_body_damage(info: RefCounted, amount: float, lethal: Dictionary) -> Dictionary:
	if info == _sigil_terminal_damage:
		return {}
	if _launch_definition.is_empty():
		return {}
	if info == null or not info.is_valid() or not Contract.number_in_range(amount, 0.000001, 1000000.0) or not _authenticates_native_body_damage(info):
		return {"ok": false}
	var before: Dictionary = _launch_runtime.snapshot()
	if before.terminal or (not _prepared_launch_frame.is_empty() and not _prepared_frame_committed) or before.mechanism_state.damage_claims.size() >= _native_body_claim_capacity():
		return {"ok": false}
	var expected_hp := float(before.mechanism_state.get("hp_after", before.mechanism_state.get("hp_current", -1.0)))
	if not is_equal_approx(expected_hp, health.current_hp) or _has_historical_body_claim(before, info):
		return {"ok": false}
	if _body_preview_runtime == null:
		var candidate := _create_launch_runtime()
		if not candidate.configure(_launch_definition, _launch_identity).ok:
			return {"ok": false}
		_body_preview_runtime = candidate
	var preview: RefCounted = _body_preview_runtime
	if not preview.restore_snapshot(before):
		return {"ok": false}
	var hp_after := maxf(0.0, health.current_hp - amount)
	if not lethal.is_empty():
		if lethal != prepare_hostile_lethal_transition(info, amount):
			return {"ok": false}
		var transition := lethal.duplicate(true)
		for field: String in ["owner_instance_id", "health_instance_id", "health_before", "damage_digest"]:
			transition.erase(field)
		if not preview.commit_lethal_transition(transition):
			return {"ok": false}
		hp_after = float(lethal.hp_after)
	var frame: int = health.frame_signal_transaction_runtime_frame()
	if frame < 0:
		frame = _hostile_runtime_frame()
	var fact := {"fact_id": _native_body_fact_id(info), "runtime_frame": frame, "target_source_id": str(hostile_source_id), "amount": amount, "hp_after": hp_after}
	var result: Dictionary = preview.accept_damage_fact(fact)
	if not result.ok:
		return {"ok": false}
	return {"ok": true, "hp_after": hp_after, "runtime_frame": frame, "before": before, "after": preview.snapshot(), "fact": fact, "result": result, "health_before": health.runtime_state_snapshot()}


func commit_hostile_body_damage(info: RefCounted, amount: float, lethal: Dictionary, decision: Dictionary) -> bool:
	if _body_damage_commit_fault_for_test or not health.owns_hostile_body_commit(info, amount, lethal, decision) or decision != prepare_hostile_body_damage(info, amount, lethal):
		return false
	if not lethal.is_empty():
		var transition := lethal.duplicate(true)
		for field: String in ["owner_instance_id", "health_instance_id", "health_before", "damage_digest"]:
			transition.erase(field)
		if not _launch_runtime.commit_lethal_transition(transition):
			return false
	if _launch_runtime.accept_damage_fact(decision.fact) != decision.result or _launch_runtime.snapshot() != decision.after:
		_launch_runtime.restore_snapshot(decision.before)
		return false
	return true


func rollback_hostile_body_damage(info: RefCounted, amount: float, lethal: Dictionary, decision: Dictionary) -> bool:
	return health.owns_hostile_body_commit(info, amount, lethal, decision, true) and _launch_runtime.snapshot() == decision.after and _launch_runtime.restore_snapshot(decision.before)


func _authenticates_native_body_damage(info: RefCounted) -> bool:
	if info.attacker is PlayerController:
		return _authenticates_chaining_player_hit(info)
	return not is_instance_valid(info.attacker) and not is_instance_valid(info.source) and str(info.run_id) == str(_launch_identity.run_id) and str(info.target_id) == str(hostile_source_id)


func _native_body_claim_capacity() -> int:
	return EnemyMechanismHandlers.MAX_DAMAGE_CLAIMS


func _native_body_fact_id(info: RefCounted) -> String:
	if not _affix_configuration.is_empty() and int(_affix_configuration.get("native_revision", 1)) < 7:
		return _historical_body_fact_id(info)
	return JSON.stringify(["native_body_v2", str(_launch_identity.run_id), str(hostile_source_id), str(info.hostile_source_id), int(info.attack_generation), int(info.hit_index), int(info.damage_type)]).sha256_text()


static func _historical_body_fact_id(info: RefCounted) -> String:
	return JSON.stringify([str(info.run_id), str(info.target_id), str(info.hostile_source_id), int(info.attack_generation), int(info.hit_index)]).sha256_text()


func _has_historical_body_claim(state: Dictionary, info: RefCounted) -> bool:
	var claims := {}
	for claim: String in state.mechanism_state.damage_claims:
		claims[claim] = true
	var runs: Array[String] = [str(info.run_id), str(_launch_identity.run_id), "runtime", "legacy_run"]
	var targets: Array[String] = [str(info.target_id), str(hostile_source_id), "pending_target"]
	for field: String in ["encounter_spawn_id", "spawn_id", "stable_target_id"]:
		if has_meta(field):
			targets.append(str(get_meta(field)))
			targets.append("target:" + str(get_meta(field)))
	# Historical components shared one identity; preserve that exclusion across aliases.
	for run: String in runs:
		for target: String in targets:
			var id := JSON.stringify([run, target, str(info.hostile_source_id), int(info.attack_generation), int(info.hit_index)]).sha256_text()
			if claims.has(id) or claims.has(id.sha256_text()):
				return true
	return false


func accept_launch_health_fact(fact: Dictionary) -> bool:
	var accepted: bool = is_instance_valid(health) and not health.dead and _launch_runtime.has_method("accept_health_fact") and fact.get("hp_after", -1.0) == health.current_hp and _launch_runtime.accept_health_fact(fact).ok
	if accepted:
		_refresh_hound_sigil()
	return accepted


func settle_launch_affix_heal(frame: int, planned: float, actual: float) -> bool:
	if _affix_runtime == null or _prepared_launch_frame.is_empty() or not _prepared_frame_committed or frame != int(_prepared_launch_frame.runtime_frame) or planned != float(_prepared_launch_frame.batch.affix_heal.healed_amount) or _affix_runtime.snapshot() != _prepared_launch_frame.after.affix_runtime:
		return false
	return _affix_runtime.settle_regeneration_heal(frame, planned, actual, _prepared_launch_frame.before.affix_runtime)


func commit_hostile_lethal_transition(damage_info: RefCounted, final_amount: float, decision: Dictionary) -> bool:
	if not is_instance_valid(health) or not health.owns_hostile_lethal_commit(damage_info, final_amount, decision) or decision != prepare_hostile_lethal_transition(damage_info, final_amount):
		return false
	var domain := decision.duplicate(true)
	for field: String in ["owner_instance_id", "health_instance_id", "health_before", "damage_digest"]:
		domain.erase(field)
	if not _launch_runtime.commit_lethal_transition(domain):
		return false
	if not decision.final_death and _hostile_threat_registry != null:
		_hostile_threat_registry.retire_source(hostile_source_id)
	return true


func apply_weapon_hit_control(damage_info: RefCounted, final_amount: float) -> bool:
	var staged := false
	var accepted_damage_frame := -1
	if not _launch_definition.is_empty() and damage_info != null and is_finite(final_amount) and final_amount > 0.0:
		var body: Dictionary = health.hostile_body_application(damage_info, final_amount)
		var frame: int = int(body.runtime_frame) if not body.is_empty() else health.frame_signal_transaction_runtime_frame()
		if frame < 0:
			frame = _hostile_runtime_frame()
		var result: Dictionary = body.result if not body.is_empty() else _launch_runtime.accept_damage_fact({"fact_id": _native_body_fact_id(damage_info), "runtime_frame": frame, "target_source_id": str(hostile_source_id), "amount": final_amount, "hp_after": health.current_hp})
		staged = result.ok
		if staged:
			accepted_damage_frame = frame
			if _affix_runtime != null and health.owns_weapon_hit_control_application(damage_info, final_amount) and _authenticates_chaining_player_hit(damage_info):
				var chaining_identity := JSON.stringify([str(_launch_identity.run_id), str(hostile_source_id), str(damage_info.hostile_source_id), int(damage_info.attack_generation), int(damage_info.hit_index), int(damage_info.damage_type)], "", false).sha256_text()
				_affix_runtime.accept_chaining_player_damage(frame, chaining_identity, _point(global_position))
		if result.ok and _affix_runtime != null and damage_info.tags.has("attack:heavy"):
			_affix_runtime.interrupt_regeneration(frame)
		if result.ok and _hostile_threat_registry != null:
			for generation: int in result.retired_generations:
				_hostile_threat_registry.retire(hostile_source_id, generation)
			if not body.is_empty() and _launch_definition.get("runtime_kind", "") in ["chrono_guard", "eternal_hound"] and final_amount >= float(body.health_before.current_hp) and health.current_hp > 0.0:
				_hostile_threat_registry.retire_source(hostile_source_id)
	var controlled := super.apply_weapon_hit_control(damage_info, final_amount)
	if controlled and staged and _affix_runtime != null:
		_affix_runtime.accept_launch_control(accepted_damage_frame)
	return controlled or staged


func _authenticates_chaining_player_hit(info: RefCounted) -> bool:
	var attacker: Node = info.attacker
	if not is_instance_valid(attacker) or not attacker is PlayerController or not attacker.authenticates_native_damage_run(info, self, StringName(str(_launch_identity.run_id))):
		return false
	if info.target_id == hostile_source_id or info.target_id == &"pending_target":
		return true
	for field: String in ["encounter_spawn_id", "spawn_id", "stable_target_id"]:
		if has_meta(field) and str(info.target_id) in [str(get_meta(field)), "target:" + str(get_meta(field))]:
			return true
	return false


func settle_launch_chaining(actors: Dictionary, frame: int, authority: RefCounted) -> bool:
	if _affix_runtime == null or _affix_runtime.pending_chaining_grants().is_empty():
		return true
	if not authority is HostileFrameBridge or not authority.owns_launch_chaining_context(self, actors, frame) or not _prepared_launch_frame.is_empty():
		return false
	for grant: Dictionary in _affix_runtime.pending_chaining_grants():
		var candidates: Array[Dictionary] = []
		var origin := _vector(grant.source_position)
		for id: String in actors:
			var ally: Variant = actors[id]
			if not ally is LaunchHostileActor or not is_instance_valid(ally) or ally == self or ally.is_queued_for_deletion() or not ally.is_inside_tree() or SceneScope.replay_world(ally) != SceneScope.replay_world(self):
				continue
			var state: Dictionary = ally.launch_runtime_snapshot()
			if state.runtime.identity.run_id != _launch_identity.run_id or state.runtime.terminal or not ally.health.is_alive() or int(state.runtime.runtime_frame) != frame - 1 or not ally.prepared_launch_frame_batch().is_empty():
				continue
			var distance: float = origin.distance_squared_to(ally.global_position)
			if distance <= pow(float(EliteAffixDefinition.PARAMETERS.chaining.recipient_radius_px), 2.0) and state.runtime.control.sources.size() < HostileControlRuntime.MAX_SOURCES:
				candidates.append({"id": id, "position": _point(ally.global_position), "distance": distance})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id if a.distance == b.distance else a.distance < b.distance)
		var recipients: Array[Dictionary] = []
		for index: int in range(mini(candidates.size(), int(EliteAffixDefinition.PARAMETERS.chaining.recipient_count_cap))):
			var row: Dictionary = candidates[index]
			var ally: Node2D = actors[row.id]
			if not ally.get("_launch_runtime").add_control_source(Chaining.control_id(str(grant.fact_id)), "attack_buff", int(EliteAffixDefinition.PARAMETERS.chaining.buff_frames), float(EliteAffixDefinition.PARAMETERS.chaining.attack_multiplier)):
				return false
			recipients.append({"id": row.id, "position": row.position})
		if not _affix_runtime.settle_chaining_grant(frame, str(grant.fact_id), recipients):
			return false
	return true


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
	if not is_instance_valid(health) or not health.dead or health.current_hp > 0.0 or not _death_receipt.is_empty():
		return
	cancel_active_attack()
	_launch_runtime.cancel(&"death")
	if _affix_runtime != null:
		_affix_runtime.cancel()
	clear_weapon_hit_control_state(&"death")
	reset_elemental_statuses()
	_hostile_identity_active = false
	remove_from_group("enemies")
	remove_from_group("time_stoppable")
	collision_layer = 0
	collision_mask = 0
	get_node("Hurtbox").collision_layer = 0
	_death_receipt = "hostile_defeat:%s" % (str(_launch_identity.get("run_id", "")) + "|" + str(hostile_source_id)).sha256_text().substr(0, 40)
	_refresh_control_visual()
	var retirement := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	retirement.tween_interval(0.2)
	retirement.tween_callback(queue_free)
	hostile_final_death.emit(hostile_source_id, _death_receipt)


func _refresh_control_visual() -> void:
	_refresh_hound_sigil()
	_refresh_phase_arrival()
	_refresh_launch_telegraphs()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.scale = Vector2.ONE * (1.15 if _launch_definition.get("actor_kind") == "elite" else 1.0)
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty():
		return
	if _launch_definition.get("id") == "eternal_hound":
		sprite.visible = int(state.mechanism_state.dormancy_remaining_frames) == 0
	match state.action.phase:
		"WARNING": sprite.frame = 1
		"ACTIVE": sprite.frame = 2
		"RECOVERY": sprite.frame = 3
		_: sprite.frame = 0
	sprite.modulate = Color(0.55, 0.95, 1.0) if is_time_stopped() or is_elementally_frozen() else Color.WHITE
	if state.terminal:
		sprite.modulate = Color(0.45, 0.45, 0.45)
	_refresh_affix_cue()


func _refresh_hound_sigil() -> void:
	if _launch_definition.get("id") != "eternal_hound":
		return
	var sigil := get_node_or_null("DormantSigil") as Node2D
	if sigil == null:
		sigil = HoundSigil.new()
		sigil.name = "DormantSigil"
		sigil.configure(self)
		add_child(sigil)
	sigil.present(_launch_runtime.snapshot())


func _refresh_phase_arrival() -> void:
	if _launch_definition.get("id") != "phase_ranger":
		return
	var cue := get_node_or_null("PhaseArrival") as Sprite2D
	if cue == null:
		cue = PhaseArrival.new()
		cue.name = "PhaseArrival"
		cue.configure()
		add_child(cue)
	cue.present(_launch_runtime.snapshot(), global_position)


func _refresh_launch_telegraphs() -> void:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty():
		return
	var phase: String = "TERMINAL" if state.terminal or state.action.action_id == "matriarch_root_sweep" else str(state.action.phase)
	TelegraphProjection.present(self, native_cold_threat_facts(), str(state.action.action_id), phase)


func _refresh_affix_cue() -> void:
	_refresh_teleport_cue()
	_refresh_shield_cue()
	_refresh_chaining_cue()
	_refresh_mirroring_cue()
	_refresh_splitting_cue()
	var cue := get_node_or_null("EliteAffixCue") as Node2D
	if _affix_runtime == null or not _affix_runtime.is_nullified():
		if cue != null:
			cue.visible = false
		return
	if cue == null:
		cue = AffixCue.new()
		cue.name = "EliteAffixCue"
		cue.z_index = 5
		add_child(cue)
	cue.position = Vector2(22, -32) if _affix_runtime.is_shielded() or _affix_runtime.is_mirroring() or _affix_runtime.chaining_phase() != "ABSENT" else (Vector2(-22, -32) if _affix_runtime.is_teleporting() else Vector2(0, -32))
	var phase := "READY"
	if _affix_runtime.snapshot().terminal:
		phase = "TERMINAL"
	elif _affix_runtime.is_nullified_delayed():
		phase = "DELAY"
	elif _affix_runtime.nullified_damage_bonus() > 0.0:
		phase = "EXPOSED"
	cue.project_nullified(phase, bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))


func _refresh_shield_cue() -> void:
	var cue := get_node_or_null("EliteShieldCue") as Node2D
	if _affix_runtime == null or not _affix_runtime.is_shielded():
		if cue != null:
			cue.visible = false
		return
	if cue == null:
		cue = AffixCue.new()
		cue.name = "EliteShieldCue"
		cue.z_index = 5
		add_child(cue)
	cue.position = Vector2(-22, -36) if _affix_runtime.is_nullified() or _affix_runtime.is_teleporting() or _affix_runtime.is_mirroring() or _affix_runtime.is_splitting() else Vector2(0, -32)
	var state: Dictionary = _affix_runtime.snapshot()
	var phase := "TERMINAL" if state.terminal else ("INTACT" if float(state.shielded.current_pool) > 0.0 else "BROKEN")
	cue.project_shielded(phase, float(state.shielded.current_pool) / (max_hp * 0.30), bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))


func _refresh_teleport_cue() -> void:
	var cue := get_node_or_null("EliteTeleportCue") as Node2D
	if _affix_runtime == null or not _affix_runtime.is_teleporting():
		if cue != null:
			cue.visible = false
		return
	if cue == null:
		cue = AffixCue.new()
		cue.name = "EliteTeleportCue"
		cue.z_index = 5
		add_child(cue)
	cue.position = Vector2(22, -32) if _affix_runtime.is_shielded() or _affix_runtime.is_nullified() or _affix_runtime.is_mirroring() or _affix_runtime.is_splitting() or _affix_runtime.chaining_phase() != "ABSENT" else Vector2(0, -32)
	var state: Dictionary = _affix_runtime.snapshot()
	var phase: String = "TERMINAL" if state.terminal else str(state.teleporting.phase)
	var offset := Vector2.ZERO
	if phase in ["DEPARTURE", "ARRIVAL"]:
		offset = _vector(state.teleporting.reservations.back().landing) - global_position - cue.position
	cue.project_teleporting(phase, offset, bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))


func _refresh_chaining_cue() -> void:
	var cue := get_node_or_null("EliteChainingCue") as Node2D
	var phase: String = "ABSENT" if _affix_runtime == null else _affix_runtime.chaining_phase()
	if phase == "ABSENT":
		if cue != null:
			cue.visible = false
		return
	if cue == null:
		cue = AffixCue.new()
		cue.name = "EliteChainingCue"
		cue.z_index = 5
		add_child(cue)
	cue.position = Vector2(-22, -32) if _affix_runtime.is_nullified() or _affix_runtime.is_teleporting() or _affix_runtime.is_mirroring() or _affix_runtime.is_splitting() else Vector2(0, -32)
	cue.project_chaining(phase, bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))


func _refresh_mirroring_cue() -> void:
	var cue := get_node_or_null("EliteMirroringCue") as Node2D
	var phase: String = "ABSENT" if _affix_runtime == null else _affix_runtime.mirroring_phase()
	if phase == "ABSENT":
		if cue != null:
			cue.visible = false
		return
	if cue == null:
		cue = AffixCue.new()
		cue.name = "EliteMirroringCue"
		cue.z_index = 5
		add_child(cue)
	cue.position = Vector2(22, -32) if _affix_runtime.is_shielded() or _affix_runtime.chaining_phase() != "ABSENT" else (Vector2(-22, -32) if _affix_runtime.is_nullified() or _affix_runtime.is_teleporting() else Vector2(0, -32))
	cue.project_mirroring(phase, bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))


func _refresh_splitting_cue() -> void:
	var cue := get_node_or_null("EliteSplittingCue") as Node2D
	if _affix_runtime == null or not _affix_runtime.is_splitting():
		if cue != null:
			cue.visible = false
		return
	if cue == null:
		cue = AffixCue.new()
		cue.name = "EliteSplittingCue"
		cue.z_index = 5
		add_child(cue)
	cue.position = Vector2(22, -32) if _affix_runtime.is_shielded() or _affix_runtime.chaining_phase() != "ABSENT" else (Vector2(-22, -32) if _affix_runtime.is_teleporting() else Vector2(0, -32))
	cue.project_splitting("TERMINAL" if _affix_runtime.snapshot().terminal else "READY", bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))


func _actor_state() -> Dictionary:
	var metadata: Dictionary = {}
	for field: String in WEAPON_METADATA_FIELDS:
		if has_meta(field):
			var value: Variant = get_meta(field)
			metadata[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	var state := {"runtime": _launch_runtime.snapshot(), "status": elemental_status_runtime.transaction_snapshot(), "position": _point(global_position), "knockback": _point(_knockback_velocity), "weakpoint_sequence": _weakpoint_token, "stop_sequence": _time_stop_token_sequence, "weapon_claims": _weapon_hit_control_claims.duplicate(true), "weapon_claim_order": _weapon_hit_control_claim_order.duplicate(), "blind_sequence": _elemental_blind_action_sequence, "action_credit": _action_credit, "death_receipt": _death_receipt, "weapon_metadata": metadata, "room_motion": launch_room_motion_snapshot()}
	if not _affix_configuration.is_empty():
		state["affixes"] = launch_affix_snapshot()
	if _affix_runtime != null:
		state["affix_runtime"] = launch_affix_runtime_snapshot()
	return state


func _can_restore_actor_state(value: Dictionary) -> bool:
	var fields: Array = ACTOR_STATE_FIELDS + ["affixes"] if not _affix_configuration.is_empty() else ACTOR_STATE_FIELDS
	if _affix_runtime != null:
		fields += ["affix_runtime"]
	if not Contract.exact_fields(value, fields) or not _affix_configuration.is_empty() and value.affixes != _affix_configuration or not value.runtime is Dictionary or not _launch_runtime.can_restore_snapshot(value.runtime) or not value.status is Dictionary or not elemental_status_runtime.can_restore_transaction_snapshot(value.status):
		return false
	if _affix_runtime != null and (not value.affix_runtime is Dictionary or not _affix_runtime.can_restore_snapshot(value.affix_runtime) or value.affix_runtime.runtime_frame != value.runtime.runtime_frame or value.affix_runtime.terminal != value.runtime.terminal):
		return false
	if not Contract.valid_point(value.position) or not Contract.valid_point(value.knockback) or not Contract.number_in_range(value.action_credit, 0.0, 1.0) or typeof(value.death_receipt) != TYPE_STRING:
		return false
	if value.room_motion != _room_motion or (not _room_motion.is_empty() and (not _room_motion_is_valid() or not _within_bounds(_vector(value.position), _motion_bounds(), float(_launch_definition.collision_radius_px)))):
		return false
	for reservation: Dictionary in value.get("affix_runtime", {}).get("teleporting", {}).get("reservations", []):
		if (_room_motion.is_empty() and not reservation.landing.is_empty()) or (not _room_motion.is_empty() and (not _within_bounds(_vector(reservation.origin), _motion_bounds(), float(_launch_definition.collision_radius_px)) or (not reservation.landing.is_empty() and not _within_bounds(_vector(reservation.landing), _motion_bounds(), float(_launch_definition.collision_radius_px))))):
			return false
	for reservation: Dictionary in value.runtime.mechanism_state.get("phase_shift", {}).get("reservations", []):
		if (_room_motion.is_empty() and not reservation.landing.is_empty()) or (not _room_motion.is_empty() and (not _within_bounds(_vector(reservation.origin), _motion_bounds(), float(_launch_definition.collision_radius_px)) or (not reservation.landing.is_empty() and not _within_bounds(_vector(reservation.landing), _motion_bounds(), float(_launch_definition.collision_radius_px))))):
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
	if _affix_runtime != null:
		_affix_runtime.restore_snapshot(value.affix_runtime)
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
	_refresh_hound_sigil()
	_refresh_phase_arrival()
	return true


func _ticket_matches(ticket: Dictionary) -> bool:
	return Contract.exact_fields(ticket, FRAME_TICKET_FIELDS) and not _prepared_launch_frame.is_empty() and ticket == _prepared_launch_frame


func _native_geometry_matches_definition() -> bool:
	if _launch_definition.get("id") == "eternal_hound":
		var sigil := get_node_or_null("DormantSigil")
		if sigil == null or not sigil.native_geometry_matches(_launch_runtime.snapshot()):
			return false
	if _launch_definition.get("id") == "phase_ranger":
		var cue := get_node_or_null("PhaseArrival")
		if cue == null or not cue.native_geometry_matches(_launch_runtime.snapshot(), global_position):
			return false
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var hurt := get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	return _translation_only(global_transform) and body != null and hurt != null and hurtbox != null and body.shape is CircleShape2D and hurt.shape is CircleShape2D and not body.disabled and not hurt.disabled and body.transform == Transform2D.IDENTITY and hurt.transform == Transform2D.IDENTITY and hurtbox.transform == Transform2D.IDENTITY and body.shape.radius == float(_launch_definition.collision_radius_px) and hurt.shape.radius == float(_launch_definition.collision_radius_px)


func _room_motion_is_valid() -> bool:
	var terminal_projection: bool = health.dead and bool(_launch_runtime.snapshot().terminal) and not _death_receipt.is_empty()
	var expected_layer: int = 0 if terminal_projection else int(_room_motion.collision_layer)
	var expected_mask: int = 0 if terminal_projection else int(_room_motion.collision_mask)
	return is_instance_valid(_motion_room) and _motion_room.is_inside_tree() and _motion_room.global_transform == _motion_room_transform and _physical_camera_bounds(_motion_room) == _motion_room_local_bounds and collision_layer == expected_layer and collision_mask == expected_mask and _native_geometry_matches_definition()


static func _physical_camera_bounds(room: Node2D) -> Rect2:
	var anchor := room.get_node_or_null("CameraBounds") as Area2D
	var collision := room.get_node_or_null("CameraBounds/CollisionShape2D") as CollisionShape2D
	if anchor == null or collision == null or not collision.shape is RectangleShape2D or not _translation_only(anchor.transform) or not _translation_only(collision.transform):
		return Rect2()
	var size: Vector2 = collision.shape.size
	return Rect2(anchor.position + collision.position - size * 0.5, size)


func _motion_bounds() -> Rect2:
	var bounds: Dictionary = _room_motion.bounds
	return Rect2(float(bounds.x), float(bounds.y), float(bounds.width), float(bounds.height))


func _constrain_to_room(position: Vector2) -> Vector2:
	var limits := _motion_bounds().grow(-float(_launch_definition.collision_radius_px))
	return Vector2(clampf(position.x, limits.position.x, limits.end.x), clampf(position.y, limits.position.y, limits.end.y))


static func _within_bounds(position: Vector2, bounds: Rect2, radius: float) -> bool:
	var limits := bounds.grow(-radius)
	return position.is_finite() and position.x >= limits.position.x and position.y >= limits.position.y and position.x <= limits.end.x and position.y <= limits.end.y


static func _translation_only(transform: Transform2D) -> bool:
	return transform.origin.is_finite() and transform.x == Vector2.RIGHT and transform.y == Vector2.DOWN


static func _seconds_to_frames(value: float) -> int:
	return ceili(value * 60.0) if is_finite(value) and value > 0.0 and value <= 600.0 else 0


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _launch_failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_ACTOR_INVALID", "context": {"field": field}}


func native_cold_snapshot(source_binding: Callable) -> Dictionary:
	if _launch_definition.is_empty() or not _prepared_launch_frame.is_empty() or _prepared_frame_committed or health == null or health.frame_signal_transaction_is_active() or health.hostile_body_application_is_active() or not source_binding.is_valid():
		return {}
	if _affix_runtime != null and not _affix_runtime.pending_chaining_grants().is_empty():
		return {}
	var state := _actor_state()
	for row: Dictionary in state.status.entries.values():
		for field: String in ["damage_source", "damage_attacker"]:
			if row[field] == null:
				continue
			var binding: Variant = source_binding.call(row[field])
			if not binding is Dictionary or binding.is_empty():
				return {}
			row[field] = binding.duplicate(true)
	return {"schema_version": 1, "definition_id": str(_launch_definition.id), "identity": _launch_identity.duplicate(true), "actor": state, "health": health.runtime_state_snapshot()}


func can_restore_native_cold_snapshot(value: Dictionary, source_resolver: Callable) -> bool:
	if not Contract.exact_fields(value, ["schema_version", "definition_id", "identity", "actor", "health"]) or value.schema_version != 1 or value.definition_id != _launch_definition.get("id") or value.identity != _launch_identity or not value.actor is Dictionary or not value.health is Dictionary or not _prepared_launch_frame.is_empty() or not source_resolver.is_valid():
		return false
	var state := _cold_actor_state(value.actor, source_resolver)
	if state.is_empty() or not _can_restore_actor_state(state) or not health.can_restore_replay_snapshot(value.health):
		return false
	var anchored: Dictionary = state.get("affix_runtime", {}).get("anchored", {})
	if not anchored.is_empty() and int(anchored.last_control_frame) > int(state.runtime.runtime_frame):
		return false
	for claim: Dictionary in state.get("affix_runtime", {}).get("shielded", {}).get("damage_claims", []):
		if int(claim.runtime_frame) > int(state.runtime.runtime_frame):
			return false
	for claim: Dictionary in state.get("affix_runtime", {}).get("chaining", {}).get("damage_claims", []):
		if int(claim.runtime_frame) > int(state.runtime.runtime_frame):
			return false
	for grant: Dictionary in state.get("affix_runtime", {}).get("chaining", {}).get("grants", []):
		if int(grant.settled_frame) == -1 or int(grant.settled_frame) > int(state.runtime.runtime_frame):
			return false
	if value.health.dead != state.runtime.terminal:
		return false
	for field: String in ["hp_after", "hp_current"]:
		if state.runtime.mechanism_state.has(field) and not is_equal_approx(float(state.runtime.mechanism_state[field]), float(value.health.current_hp)):
			return false
	return true


func native_cold_threat_facts() -> Array:
	var state: Dictionary = _launch_runtime.snapshot()
	var facts: Array = state.action.committed_geometry.duplicate(true)
	if state.action.action_id == "traitor_self_rewind" and not state.mechanism_state.rewind.is_empty():
		var action := {}
		for candidate: Dictionary in _launch_definition.actions + _launch_definition.get("time_responses", []):
			if candidate.id == state.action.action_id:
				action = candidate
		if action.is_empty():
			return []
		var landing: Dictionary = state.mechanism_state.rewind.landing
		facts = [{"hostile_source_id": state.identity.hostile_source_id, "attack_generation": state.action.geometry_generations[0], "shape": "circle", "origin": landing, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": landing, "summon_slots": [], "radius": 16.0, "length": 0.0, "active_from_frame": state.action.commit_frame, "active_through_frame": int(state.action.idle_through_frame) - int(action.idle_frames)}]
	var result: Array = []
	for fact: Dictionary in facts:
		result.append(Actions.native_threat_fact(fact))
	return result


func restore_native_cold_snapshot(value: Dictionary, source_resolver: Callable) -> bool:
	if not can_restore_native_cold_snapshot(value, source_resolver):
		return false
	var state := _cold_actor_state(value.actor, source_resolver)
	if not health.restore_irreversible_replay_snapshot(value.health.ledger) or not health.restore_replay_snapshot(value.health) or not _restore_actor_state(state):
		return false
	_hostile_identity_active = not bool(state.runtime.terminal)
	if health.is_alive() and _hostile_identity_active:
		add_to_group("enemies")
		add_to_group("time_stoppable")
	else:
		remove_from_group("enemies")
		remove_from_group("time_stoppable")
	_refresh_control_visual()
	return true


func normalize_native_cold_snapshot(value: Dictionary) -> Dictionary:
	if not value.get("actor") is Dictionary or not value.actor.get("runtime") is Dictionary:
		return {}
	var runtime: Dictionary = _launch_runtime.normalize_native_snapshot(value.actor.runtime) if _launch_runtime.has_method("normalize_native_snapshot") else value.actor.runtime
	if runtime.is_empty() or not _launch_runtime.can_restore_snapshot(runtime):
		return {}
	var normalized := value.duplicate(true)
	normalized.actor.runtime = runtime.duplicate(true)
	return normalized


func _cold_actor_state(value: Dictionary, source_resolver: Callable) -> Dictionary:
	if not value.get("status") is Dictionary or not value.status.get("entries") is Dictionary:
		return {}
	var state := value.duplicate(true)
	for candidate: Variant in state.status.entries.values():
		if not candidate is Dictionary:
			return {}
		for field: String in ["damage_source", "damage_attacker"]:
			if not candidate.has(field):
				return {}
			if candidate[field] == null:
				continue
			if not candidate[field] is Dictionary:
				return {}
			var source: Variant = source_resolver.call(candidate[field])
			if not source is Node or not is_instance_valid(source):
				return {}
			candidate[field] = source
	return state
