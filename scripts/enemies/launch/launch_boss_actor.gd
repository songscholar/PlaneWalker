class_name LaunchBossActor
extends "res://scripts/enemies/launch/launch_hostile_actor.gd"

const BossRuntime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const BossStatus := preload("res://scripts/enemies/launch/boss_elemental_status_runtime.gd")
const Construct := preload("res://scripts/enemies/launch/launch_boss_construct.gd")
const Wall := preload("res://scripts/enemies/launch/launch_boss_wall.gd")
const Calculator := preload("res://scripts/combat/damage_calculator.gd")
var _exposure_replay_authority: RefCounted


func _create_launch_runtime() -> RefCounted:
	return BossRuntime.new()


func _create_launch_status_runtime() -> RefCounted:
	return BossStatus.new()


func _ready() -> void:
	super._ready()
	add_to_group("bosses")
	var watch_shape := get_node_or_null("WatchHurtbox/CollisionShape2D") as CollisionShape2D
	if watch_shape != null and watch_shape.shape != null:
		watch_shape.shape = watch_shape.shape.duplicate()


func _native_geometry_matches_definition() -> bool:
	if not super._native_geometry_matches_definition():
		return false
	if _launch_definition.get("id", "") == "ruin_king":
		var arena := get_node_or_null("ArenaConstructs")
		var state: Dictionary = native_arena_snapshot()
		if arena == null or state.is_empty() or arena.get_child_count() != 4 + state.walls.size():
			return false
		for index: int in range(4):
			var cover := arena.get_child(index)
			if not cover is Construct or not cover.native_geometry_matches(state.covers[index], _native_arena_origin(), bool(state.terminal)):
				return false
		for index: int in range(state.walls.size()):
			var wall := arena.get_child(index + 4)
			if not wall is Wall or not wall.native_geometry_matches(state.walls[index], _native_arena_origin(), bool(state.terminal)):
				return false
		for claim: Dictionary in state.wall_claims:
			if _room_motion.is_empty() or claim.bounds != _room_motion.bounds:
				return false
	if _launch_definition.get("id", "") != "time_sovereign":
		return true
	var watch := get_node_or_null("WatchHurtbox") as Area2D
	var shape := get_node_or_null("WatchHurtbox/CollisionShape2D") as CollisionShape2D
	var primary := get_node("Hurtbox") as Area2D
	return watch != null and shape != null and shape.shape is CircleShape2D and not shape.disabled and watch.transform == Transform2D.IDENTITY and shape.transform == Transform2D.IDENTITY and shape.shape.radius == float(_launch_definition.collision_radius_px) and watch.collision_layer == (0 if _launch_runtime.snapshot().terminal else 4) and watch.collision_mask == 0 and primary.collision_layer == 0


func _restore_actor_state(value: Dictionary) -> bool:
	if not super._restore_actor_state(value):
		return false
	_refresh_control_visual()
	return true


func prepare_launch_frame(frame: int, observations: Dictionary) -> Dictionary:
	if _launch_definition.get("id", "") in ["time_sovereign", "ruin_king"] and not _native_geometry_matches_definition():
		return _launch_failure("boss_native_geometry")
	var result := super.prepare_launch_frame(frame, observations)
	if not result.ok or _launch_definition.get("id", "") != "ruin_king":
		return result
	for request: Dictionary in result.ticket.batch.effect_requests:
		if request.get("handler_id") != "wall":
			continue
		var preview := BossRuntime.new()
		preview.configure(_launch_definition, _launch_identity)
		if _room_motion.is_empty() or not preview.restore_snapshot(result.ticket.after.runtime):
			return _launch_failure("wall_admission")
		if not _wall_static_placement_valid(preview.snapshot().action):
			var cancelled: Dictionary = preview.cancel_action(&"wall_outside_safe_room_placement")
			if not cancelled.ok:
				return _launch_failure("wall_declined_admission")
			result.ticket.batch.effect_requests = []
			result.ticket.batch.phase = "IDLE"
			result.ticket.batch.retired_generations.append_array(cancelled.retired_generations)
		elif not preview.accept_arena_wall_request(request, _room_motion.bounds).ok:
			return _launch_failure("wall_admission")
		result.ticket.after.runtime = preview.snapshot()
	for request: Dictionary in result.ticket.batch.mechanism_requests:
		if request.get("kind", "") == "boss_aftershock":
			if _room_motion.is_empty():
				return _launch_failure("aftershock_room_bounds")
			request["bounds"] = _room_motion.bounds.duplicate(true)
		elif request.get("kind", "") == "boss_wall_collapse":
			if _room_motion.is_empty():
				return _launch_failure("wall_collapse_room_bounds")
			request.position = _point(_native_arena_origin() + _vector(request.position))
			request["bounds"] = _room_motion.bounds.duplicate(true)
	result.batch = result.ticket.batch.duplicate(true)
	_prepared_launch_frame = result.ticket.duplicate(true)
	var target: Variant = result.ticket.collision_target
	if target is Construct and target.get_parent() == get_node("ArenaConstructs") and result.ticket.after.runtime.action.action_id == "guardian_charge" and result.ticket.after.runtime.action.phase == "ACTIVE":
		var preview := BossRuntime.new()
		preview.configure(_launch_definition, _launch_identity)
		if not preview.restore_snapshot(result.ticket.after.runtime):
			return _launch_failure("charge_cover_checkpoint")
		var impact: Dictionary = preview.accept_arena_charge_impact(str(target.native_construct_snapshot().id))
		if not impact.ok:
			return _launch_failure("charge_cover_impact")
		result.ticket.after.runtime = preview.snapshot()
		result.ticket.batch.hit_facts = []
		result.ticket.batch.phase = "IDLE"
		result.ticket.batch.retired_generations.append_array(impact.retired_generations)
		result.batch = result.ticket.batch.duplicate(true)
		_prepared_launch_frame = result.ticket.duplicate(true)
	return result


func _native_action_activation_blocked(frame: int, observations: Dictionary) -> bool:
	if _launch_definition.get("id", "") != "ruin_king":
		return false
	var action: Dictionary = _launch_runtime.snapshot().action
	if action.action_id != "guardian_wall" or action.phase != "WARNING" or frame - int(action.commit_frame) - int(action.paused_frames) < 55:
		return false
	if _room_motion.is_empty():
		return true
	if not _wall_static_placement_valid(action):
		return false
	for fact: Dictionary in action.committed_geometry:
		var origin := _vector(fact.origin)
		var direction := _vector(fact.aim_direction)
		var center := origin + direction * 32.0
		for subject: Dictionary in [{"position": observations.source_position, "radius": float(_launch_definition.collision_radius_px)}, {"position": observations.target_position, "radius": 14.0}]:
			var offset := (_vector(subject.position) - center).rotated(-direction.angle())
			var closest := Vector2(clampf(offset.x, -32.0, 32.0), clampf(offset.y, -6.0, 6.0))
			if offset.distance_to(closest) <= float(subject.radius) + 0.5:
				return true
	return false


func _wall_static_placement_valid(action: Dictionary) -> bool:
	if _room_motion.is_empty():
		return false
	var bounds := _motion_bounds()
	var retreat := _vector(action.committed_origin) - _vector(action.committed_aim) * (float(_launch_definition.collision_radius_px) + 7.0)
	if not _within_bounds(retreat, bounds, float(_launch_definition.collision_radius_px)):
		return false
	for fact: Dictionary in action.committed_geometry:
		var origin := _vector(fact.origin)
		var endpoint := origin + _vector(fact.aim_direction) * float(fact.length)
		if not _within_bounds(origin, bounds, 6.0) or not _within_bounds(endpoint, bounds, 6.0):
			return false
	return true


func configure_launch_room_motion(room: Node2D, template: Dictionary) -> Dictionary:
	var result := super.configure_launch_room_motion(room, template)
	if result.ok:
		_refresh_native_arena()
	return result


func _refresh_control_visual() -> void:
	_refresh_native_arena()
	var state: Dictionary = _launch_runtime.snapshot()
	var watch := get_node_or_null("WatchHurtbox") as Area2D
	if watch != null and not state.is_empty():
		watch.present(native_watch_snapshot())
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if state.is_empty() or sprite == null or not sprite.has_method("configure"):
		return
	if not sprite.configure(str(_launch_definition.id)):
		return
	var pose: StringName = &"idle"
	match state.action.phase:
		"WARNING": pose = &"cast"
		"ACTIVE": pose = &"attack"
		"RECOVERY": pose = &"idle"
	if state.terminal:
		pose = &"death"
	var facing := Vector2.RIGHT if state.action.committed_aim.is_empty() else _vector(state.action.committed_aim)
	sprite.present(pose, facing, float(state.runtime_frame) / 60.0, false, false)
	sprite.modulate = Color(0.55, 0.95, 1.0) if _launch_runtime.is_exposed() else Color.WHITE


func native_arena_snapshot() -> Dictionary:
	return _launch_runtime.arena_snapshot()


func _native_arena_origin() -> Vector2:
	return Vector2(float(_room_motion.bounds.x), float(_room_motion.bounds.y)) if not _room_motion.is_empty() else Vector2.ZERO


func _refresh_native_arena() -> void:
	var state := native_arena_snapshot()
	if state.is_empty():
		return
	var arena := get_node_or_null("ArenaConstructs")
	if arena == null:
		arena = Node2D.new()
		arena.name = "ArenaConstructs"
		add_child(arena)
		for cover: Dictionary in state.covers:
			var body := Construct.new()
			body.name = "Cover%d" % int(cover.slot)
			body.configure(self, str(cover.id))
			arena.add_child(body)
	var replace_walls := false
	for index: int in range(mini(state.walls.size(), arena.get_child_count() - 4)):
		if arena.get_child(index + 4).native_construct_snapshot().get("id") != state.walls[index].id:
			replace_walls = true
	while arena.get_child_count() > (4 if replace_walls else 4 + state.walls.size()):
		var surplus := arena.get_child(arena.get_child_count() - 1)
		arena.remove_child(surplus)
		surplus.queue_free()
	for index: int in range(4):
		arena.get_child(index).present(state.covers[index], _native_arena_origin(), bool(state.terminal))
	for index: int in range(state.walls.size()):
		var wall: Node2D
		if arena.get_child_count() <= index + 4:
			wall = Wall.new()
			wall.name = "Wall%d" % index
			wall.configure(self, str(state.walls[index].id))
			arena.add_child(wall)
		else:
			wall = arena.get_child(index + 4)
		wall.present(state.walls[index], _native_arena_origin(), bool(state.terminal))


func prepared_launch_wall_effect_allowed(request: Dictionary) -> bool:
	if _prepared_launch_frame.is_empty() or request.get("handler_id") != "wall" or not _prepared_launch_frame.batch.effect_requests.has(request) or _room_motion.is_empty():
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime.arena_state
	for claim: Dictionary in state.wall_claims:
		if claim.attack_generation == request.attack_generation and claim.runtime_frame == request.runtime_frame and claim.geometry == request.geometry and claim.bounds == _room_motion.bounds:
			return true
	return false


func prepared_launch_wall_collapse_allowed(request: Dictionary) -> bool:
	if _prepared_launch_frame.is_empty() or _room_motion.is_empty() or request.get("kind") != "boss_wall_collapse" or not _prepared_launch_frame.batch.mechanism_requests.has(request) or request.get("bounds") != _room_motion.bounds or not request.get("parameters") is Dictionary or not Contract.exact_fields(request.parameters, ["warning_frames", "damage", "radius"]) or request.parameters.warning_frames != 40 or request.parameters.radius != 24.0 or not Contract.number_in_range(request.parameters.damage, 6.4, 12.0):
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime.arena_state
	if state.terminal:
		return false
	for wall: Dictionary in state.walls:
		if wall.id == request.get("wall_id"):
			return not wall.broken and wall.expired and request.runtime_frame == int(wall.spawn_frame) + 600 and request.attack_generation == int(wall.attack_generation) + int(wall.slot) and request.position == _point(_native_arena_origin() + _vector(wall.position))
	return false


func receive_native_construct_hit(id: String, damage_info: RefCounted) -> float:
	if damage_info == null or native_arena_snapshot().is_empty() or not _native_geometry_matches_definition():
		return 0.0
	var attacker: Node = damage_info.attacker
	var run := StringName(str(_launch_identity.run_id))
	if not is_instance_valid(attacker) or not attacker is PlayerController or attacker.current_run_id() != run or damage_info.run_id not in [run, &"runtime"]:
		return 0.0
	var amount: float = Calculator.critical_amount(damage_info, float(damage_info.amount))
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var frame: int = health.frame_signal_transaction_runtime_frame()
	var result: Dictionary = _launch_runtime.accept_arena_damage_fact({"fact_id": (_damage_identity(damage_info) + ":" + id).sha256_text(), "run_id": str(run), "owner_source_id": str(hostile_source_id), "construct_id": id, "runtime_frame": _hostile_runtime_frame() if frame < 0 else frame, "amount": amount})
	if not result.ok:
		return 0.0
	_refresh_native_arena()
	return float(result.amount)


func prepared_launch_hit_blocked_by_cover(hit: Dictionary, target: Node2D) -> bool:
	if _launch_definition.get("id", "") != "ruin_king" or _prepared_launch_frame.is_empty() or not _prepared_launch_frame.batch.hit_facts.has(hit) or hit.action_id != "guardian_rift_beam" or not _native_geometry_matches_definition() or not is_instance_valid(target):
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime.arena_state
	var origin := _vector(hit.geometry[0].origin)
	var endpoint := target.global_position
	var length := origin.distance_to(endpoint)
	if length <= 0.0:
		return false
	var direction := origin.direction_to(endpoint)
	for cover: Dictionary in state.covers:
		if cover.broken or state.terminal:
			continue
		var center := _native_arena_origin() + _vector(cover.position)
		var along := (center - origin).dot(direction)
		if along > 0.0 and along < length and Geometry2D.get_closest_point_to_segment(center, origin, endpoint).distance_to(center) <= float(cover.radius_px):
			return true
	return false


func prepared_launch_arena_payload_allowed(request: Dictionary) -> bool:
	return not _prepared_launch_frame.is_empty() and _launch_definition.get("id", "") == "ruin_king" and request.get("kind", "") == "boss_aftershock" and _prepared_launch_frame.batch.mechanism_requests.has(request) and not _prepared_launch_frame.after.runtime.terminal and not _room_motion.is_empty() and request.get("bounds") == _room_motion.bounds


func prepared_launch_arena_payloads_retired() -> bool:
	if _prepared_launch_frame.is_empty():
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime
	return bool(state.terminal) or state.mechanism_state.phase_index > 0 and int(state.mechanism_state.phase_transition_until_frame) >= int(_prepared_launch_frame.runtime_frame)


func normalize_native_cold_snapshot(value: Dictionary) -> Dictionary:
	if not value.get("actor") is Dictionary or not value.actor.get("runtime") is Dictionary:
		return {}
	var normalized: Dictionary = _launch_runtime.normalize_native_snapshot(value.actor.runtime)
	if normalized.is_empty() or not _launch_runtime.can_restore_native_snapshot(normalized):
		return {}
	var result := value.duplicate(true)
	result.actor.runtime = normalized
	return result


func _cold_actor_state(value: Dictionary, source_resolver: Callable) -> Dictionary:
	var state := super._cold_actor_state(value, source_resolver)
	if state.is_empty():
		return {}
	state.runtime = _launch_runtime.normalize_native_snapshot(state.runtime)
	return state if not state.runtime.is_empty() and _launch_runtime.can_restore_native_snapshot(state.runtime) else {}


func native_watch_snapshot() -> Dictionary:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty() or _launch_definition.get("id", "") != "time_sovereign":
		return {}
	var rewind: Dictionary = state.mechanism_state.rewind
	var active: bool = state.action.phase == "WARNING" and state.action.action_id == "traitor_self_rewind" and not rewind.is_empty() and not rewind.consumed
	var broken: bool = not rewind.is_empty() and rewind.cancelled and float(rewind.weakpoint_damage) >= float(_launch_definition.mechanisms.rewind_interrupt_damage)
	return {"owner_source_id": str(hostile_source_id), "runtime_frame": int(state.runtime_frame), "hittable": not state.terminal and health != null and not health.dead, "cast_generation": int(rewind.attack_generation) if active else 0, "maximum_hp": float(_launch_definition.mechanisms.rewind_interrupt_damage), "current_hp": 0.0 if broken else float(_launch_definition.mechanisms.rewind_interrupt_damage) - (float(rewind.weakpoint_damage) if active else 0.0)}


func receive_native_watch_hit(damage_info: RefCounted) -> float:
	if damage_info == null or _launch_definition.get("id", "") != "time_sovereign" or not native_watch_snapshot().hittable:
		return 0.0
	var run := StringName(str(_launch_identity.run_id))
	if damage_info.run_id != run:
		var attacker: Node = damage_info.attacker
		if damage_info.run_id != &"runtime" or not is_instance_valid(attacker) or not attacker is PlayerController or attacker.current_run_id() != run:
			return 0.0
	var state: Dictionary = _launch_runtime.snapshot()
	var id := _damage_identity(damage_info)
	if state.mechanism_state.damage_claims.has(id):
		return 0.0
	return health.take_damage(damage_info)


func apply_weapon_hit_control(damage_info: RefCounted, final_amount: float) -> bool:
	var before: Dictionary = _launch_runtime.snapshot()
	var accepted := super.apply_weapon_hit_control(damage_info, final_amount)
	if damage_info == null or before.is_empty() or _launch_definition.get("id", "") != "time_sovereign":
		return accepted
	var after: Dictionary = _launch_runtime.snapshot()
	var id := _damage_identity(damage_info)
	var rewind: Dictionary = before.mechanism_state.rewind
	# Group-targeted spells and physical watch collisions settle one body identity.
	if not before.mechanism_state.damage_claims.has(id) and after.mechanism_state.damage_claims.has(id) and before.action.phase == "WARNING" and before.action.action_id == "traitor_self_rewind" and not rewind.is_empty() and not rewind.consumed:
		var frame: int = health.frame_signal_transaction_runtime_frame()
		var result: Dictionary = _launch_runtime.accept_weakpoint_damage_fact({"fact_id": id, "runtime_frame": _hostile_runtime_frame() if frame < 0 else frame, "attack_generation": int(rewind.attack_generation), "amount": final_amount})
		if result.ok and _hostile_threat_registry != null:
			for generation: int in result.retired_generations:
				_hostile_threat_registry.retire(hostile_source_id, generation)
	_refresh_control_visual()
	return accepted


static func _damage_identity(damage_info: RefCounted) -> String:
	var info: Dictionary = damage_info.snapshot()
	return JSON.stringify([info.run_id, info.target_id, info.hostile_source_id, info.attack_generation, info.hit_index]).sha256_text()


func _on_died(killer: Variant) -> void:
	super._on_died(killer)
	if not _death_receipt.is_empty():
		remove_from_group("bosses")


func apply_weapon_control_conversion(source_id: StringName, recovery_frames: int, exposure_frames: int, poise_damage: float) -> bool:
	var accepted: bool = _launch_runtime.apply_weapon_control_conversion(str(source_id), recovery_frames, exposure_frames, poise_damage)
	if accepted:
		_refresh_control_visual()
	return accepted


func extend_character_boss_exposure(stop_generation: int, frames: int) -> bool:
	var accepted: bool = _launch_runtime.extend_character_boss_exposure(stop_generation, frames)
	if accepted:
		_refresh_control_visual()
	return accepted


func character_boss_exposure_identity() -> Dictionary:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty():
		return {}
	var identity: Dictionary = {}
	for field: String in ["run_id", "room_id", "encounter_id", "encounter_spawn_id", "encounter_enemy_id"]:
		var value := str(get_meta(field, "")).strip_edges()
		if value.is_empty() or value.length() > 128:
			return {}
		identity[field] = value
	identity.hostile_source_id = str(hostile_source_id)
	identity.hostile_next_generation_floor = int(state.action.next_generation_floor)
	identity.committed_attack_generation = int(state.action.geometry_generations[0]) if not state.action.geometry_generations.is_empty() else 0
	return identity


func character_boss_exposure_snapshot() -> Dictionary:
	return _launch_runtime.character_boss_exposure_snapshot(character_boss_exposure_identity())


func can_restore_character_boss_exposure_snapshot(value: Dictionary) -> bool:
	return _launch_runtime.can_restore_character_boss_exposure(value, character_boss_exposure_identity())


func restore_character_boss_exposure_snapshot(value: Dictionary) -> bool:
	var restored: bool = _launch_runtime.restore_character_boss_exposure(value, character_boss_exposure_identity())
	if restored:
		_refresh_control_visual()
	return restored


func configure_character_boss_exposure_replay_authority(authority: RefCounted) -> bool:
	if authority == null or _exposure_replay_authority != null and _exposure_replay_authority != authority:
		return false
	_exposure_replay_authority = authority
	return true


func can_restore_character_boss_exposure_replay_snapshot(value: Dictionary, authority: RefCounted) -> bool:
	return authority != null and authority == _exposure_replay_authority and _launch_runtime.can_restore_character_boss_exposure(value, character_boss_exposure_identity(), true)


func restore_character_boss_exposure_replay_snapshot(value: Dictionary, authority: RefCounted) -> bool:
	if not can_restore_character_boss_exposure_replay_snapshot(value, authority):
		return false
	var restored: bool = _launch_runtime.restore_character_boss_exposure(value, character_boss_exposure_identity(), true)
	if restored:
		_refresh_control_visual()
	return restored


func get_boss_ui_snapshot() -> Dictionary:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty() or health == null:
		return {}
	var action: Dictionary = _launch_runtime._action_definition(str(state.action.action_id))
	var remaining := 0
	if not action.is_empty():
		var elapsed := int(state.runtime_frame) - int(state.action.commit_frame) - int(state.action.paused_frames)
		remaining = int(action.warning_frames) - elapsed if state.action.phase == "WARNING" else int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) - elapsed
		remaining = maxi(0, remaining) + int(state.mechanism_state.delay_remaining_frames)
	var label := "NONE" if action.is_empty() else str(action.handler_id).to_upper()
	return {"action": label, "phase": "WINDUP" if state.action.phase == "WARNING" else str(state.action.phase), "remaining": float(remaining) / 60.0, "boss_phase": int(state.mechanism_state.phase_index) + 1, "exposed": _launch_runtime.is_exposed(), "name": tr("BOSS_%s_NAME" % str(_launch_definition.id).to_upper()), "phase_total": _launch_definition.phases.size(), "current_hp": float(health.current_hp), "maximum_hp": float(health.max_hp), "enraged": bool(state.mechanism_state.enraged)}


func apply_elemental_status(effect_id: StringName, source_id: StringName, generation: int, duration_frames: int, magnitude: float = 1.0, tick_interval_frames: int = 30, attack_speed_multiplier: float = -1.0, damage_source: Node = null, damage_attacker: Node = null) -> bool:
	if effect_id in [&"freeze", &"blind"] and not has_elemental_status(effect_id, source_id, generation):
		if not elemental_status_runtime._is_valid_application(effect_id, source_id, generation, duration_frames, magnitude, tick_interval_frames, attack_speed_multiplier):
			return false
		var material := "%s|%s|%d" % [str(effect_id), str(source_id), generation]
		if not apply_weapon_control_conversion(StringName("staff_conversion:" + material.sha256_text().substr(0, 40)), 12 if effect_id == &"freeze" else 8, 0, 0.0):
			return false
	return super.apply_elemental_status(effect_id, source_id, generation, duration_frames, magnitude, tick_interval_frames, attack_speed_multiplier, damage_source, damage_attacker)


func _resolve_weapon_hit_control(effect: Dictionary, damage_info: RefCounted, final_amount: float) -> bool:
	if str(effect.get("kind", "")) != "launch":
		return super._resolve_weapon_hit_control(effect, damage_info, final_amount)
	if damage_info == null or str(effect.get("conversion_id", "")) != "gauntlets_poised_launch" or not damage_info.tags.has("weapon:gauntlets") or typeof(effect.get("airborne")) != TYPE_BOOL or effect.airborne or str(effect.get("active_attack_policy", "")) != "preserve_committed" or typeof(effect.get("interrupt_active_attack")) != TYPE_BOOL or effect.interrupt_active_attack:
		return false
	if not effect.get("allowed_states") is Array or not Contract.number_in_range(effect.get("poise_damage"), 0.000001, 1000000.0) or not Contract.number_in_range(effect.get("boss_poise_multiplier"), 1.40, 1.40) or not Contract.number_in_range(effect.get("displacement_pixels", 0.0), 0.0, 1000000.0):
		return false
	var phase: String = _launch_runtime.snapshot().action.phase
	var conversion_state := "EXPOSED" if _launch_runtime.is_exposed() and phase != "WARNING" else "WINDUP" if phase == "WARNING" else phase
	if conversion_state not in effect.allowed_states:
		return false
	var source := str(effect.get("source_id", "gauntlets_poised_launch:%d:%d" % [int(damage_info.action_token), int(damage_info.source_generation)]))
	return apply_weapon_control_conversion(StringName(source), 0, 0, float(effect.poise_damage) * 1.40)
