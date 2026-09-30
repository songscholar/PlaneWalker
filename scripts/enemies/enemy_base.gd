class_name EnemyBase
extends CharacterBody2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const ElementalStatusRuntimeScript := preload("res://scripts/combat/elemental_status_runtime.gd")
const ELEMENTAL_STATUS_SEED_INITIALIZED_META := &"elemental_status_seed_initialized"
const ELEMENTAL_STATUS_SEED_MATERIAL_META := &"elemental_status_seed_material"
const MAX_WEAPON_HIT_CONTROL_CLAIMS := 256

enum AttackPhase {
	READY,
	WINDUP,
	RECOVERY,
}

signal attack_phase_changed(phase: AttackPhase)

@export var max_hp: float = 60.0
@export var attack: float = 10.0
@export var defense: float = 0.0
@export var move_speed: float = 120.0
@export var attack_range: float = 36.0
@export var attack_cooldown: float = 1.0
@export var attack_windup: float = 0.30
@export var attack_recovery: float = 0.30
@export_range(0.0, 1.0, 0.05) var elite_time_stop_multiplier: float = 0.5

@onready var health: Node = $HealthComponent
@onready var visual: Polygon2D = $Visual

var target: Node2D
var _attack_cooldown_remaining: float = 0.0
var _time_stopped: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO
var _rift_slow_multiplier: float = 1.0
var _rift_slow_sources: Dictionary = {}
var _is_elite: bool = false
var _weakpoint_damage_bonus: float = 0.0
var _weakpoint_token: int = 0
var _attack_phase: AttackPhase = AttackPhase.READY
var _attack_phase_remaining: float = 0.0
var _committed_attack_direction: Vector2 = Vector2.RIGHT
var _time_stop_token_sequence: int = 0
var _time_stop_sources: Dictionary = {}
var _damage_vulnerability_sources: Dictionary = {}
var _damage_action_sequence: int = 0
var _weapon_hit_control_claims: Dictionary = {}
var _weapon_hit_control_claim_order: Array[int] = []
var elemental_status_runtime: RefCounted = ElementalStatusRuntimeScript.new()
var _elemental_blind_action_sequence: int = 0

const KNOCKBACK_DECAY := 10.0


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("time_stoppable")
	health.max_hp = max_hp
	health.defense = defense
	health.current_hp = max_hp
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	target = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	_tick_damage_vulnerability_sources()
	if not health.is_alive():
		return
	if _time_stopped or is_elementally_frozen():
		velocity = Vector2.ZERO
		move_and_slide()
		_tick_elemental_status_runtime()
		return
	var action_delta: float = delta * float(elemental_status_runtime.attack_speed_multiplier())
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - action_delta)
	_tick_additional_action_timers(action_delta)
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node2D
	if target == null:
		_tick_elemental_status_runtime()
		return
	_tick_attack_phase(action_delta)
	if is_attack_locked():
		velocity = _knockback_velocity
		move_and_slide()
		_tick_elemental_status_runtime()
		return
	_tick_ai(action_delta)
	_tick_elemental_status_runtime()


func _tick_ai(_delta: float) -> void:
	pass


func _tick_additional_action_timers(_delta: float) -> void:
	pass


func _move_toward_target(speed_multiplier: float = 1.0) -> void:
	var direction := global_position.direction_to(target.global_position)
	velocity = direction * _current_move_speed() * speed_multiplier + _knockback_velocity
	move_and_slide()


func _current_move_speed() -> float:
	return move_speed * _rift_slow_multiplier * elemental_status_runtime.slow_multiplier()


func _try_begin_primary_attack() -> bool:
	if _attack_phase != AttackPhase.READY or _attack_cooldown_remaining > 0.0:
		return false
	if target == null or not is_instance_valid(target):
		return false
	_committed_attack_direction = global_position.direction_to(target.global_position)
	_set_attack_phase(AttackPhase.WINDUP, attack_windup)
	velocity = Vector2.ZERO
	return true


func _tick_attack_phase(delta: float) -> void:
	if _attack_phase == AttackPhase.READY:
		return
	_attack_phase_remaining = maxf(0.0, _attack_phase_remaining - delta)
	_on_attack_phase_clock_updated()
	if _attack_phase_remaining > 0.0:
		return
	if _attack_phase == AttackPhase.WINDUP:
		if not _should_elemental_blind_miss():
			_resolve_primary_attack()
		_attack_cooldown_remaining = attack_cooldown
		_set_attack_phase(AttackPhase.RECOVERY, _active_attack_recovery_duration())
		return
	_set_attack_phase(AttackPhase.READY)
	_on_attack_sequence_completed()


func _active_attack_recovery_duration() -> float:
	return attack_recovery


func _on_attack_phase_clock_updated() -> void:
	pass


func _on_attack_sequence_completed() -> void:
	pass


func _on_attack_runtime_cancelled() -> void:
	pass


func _on_elite_modifier_applied() -> void:
	pass


func _resolve_primary_attack() -> void:
	_deal_melee_damage()


func _deal_melee_damage() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return
	if not target.has_node("HealthComponent"):
		return
	var damage_info := _damage_info_from_plan(
		attack,
		DamageInfoScript.DamageType.PHYSICAL,
		target,
		&"melee",
		["enemy:melee"],
		_committed_attack_direction * 180.0,
		self,
		self
	)
	if damage_info == null:
		return
	target.get_node("HealthComponent").take_damage(damage_info)


func _try_melee_attack() -> void:
	# Chrono Warden owns a separate Boss action clock. Preserve its legacy melee
	# endpoint until that clock resolves the hit explicitly.
	if is_in_group("bosses"):
		if target == null or not is_instance_valid(target):
			return
		if _attack_cooldown_remaining > 0.0:
			return
		_committed_attack_direction = global_position.direction_to(target.global_position)
		_attack_cooldown_remaining = attack_cooldown
		_deal_melee_damage()
		return
	_try_begin_primary_attack()


func attack_phase() -> AttackPhase:
	return _attack_phase


func is_attack_locked() -> bool:
	return _attack_phase != AttackPhase.READY


func _set_attack_phase(next_phase: AttackPhase, duration: float = 0.0) -> void:
	if _attack_phase == next_phase:
		return
	_attack_phase = next_phase
	_attack_phase_remaining = maxf(0.0, duration)
	attack_phase_changed.emit(_attack_phase)
	_refresh_control_visual()


func _refresh_control_visual() -> void:
	if visual == null:
		return
	if _time_stopped:
		visual.modulate = Color(0.55, 0.9, 1.0, 1.0)
		return
	if is_elementally_frozen():
		visual.modulate = Color(0.65, 0.82, 1.0, 1.0)
		return
	match _attack_phase:
		AttackPhase.WINDUP:
			visual.modulate = Color(1.0, 0.78, 0.36, 1.0)
		AttackPhase.RECOVERY:
			visual.modulate = Color(0.62, 0.66, 0.72, 1.0)
		_:
			visual.modulate = Color.WHITE


func _on_damaged(_amount: float, _current_hp: float) -> void:
	visual.color = Color(1.0, 0.45, 0.35)
	await get_tree().create_timer(0.08).timeout
	if health.is_alive():
		_restore_visual_color()


func _on_died(_killer: Variant) -> void:
	remove_from_group("enemies")
	_damage_vulnerability_sources.clear()
	clear_weapon_hit_control_state(&"death")
	reset_elemental_statuses()
	cancel_active_attack()
	visual.color = Color(0.25, 0.25, 0.28)
	set_physics_process(false)
	await get_tree().create_timer(0.2).timeout
	queue_free()


func _restore_visual_color() -> void:
	visual.color = Color(0.9, 0.35, 0.3)


func cancel_active_attack() -> void:
	_attack_phase_remaining = 0.0
	_set_attack_phase(AttackPhase.READY)
	_on_attack_runtime_cancelled()


func apply_knockback(knockback: Vector2) -> void:
	_knockback_velocity += knockback


func apply_weapon_hit_control(damage_info: RefCounted, final_amount: float) -> bool:
	if (
		damage_info == null
		or not is_finite(final_amount)
		or final_amount <= 0.0
		or health == null
		or not health.is_alive()
	):
		return false
	var action_token_value: Variant = damage_info.get("action_token")
	var source_generation_value: Variant = damage_info.get("source_generation")
	var effect_value: Variant = damage_info.get("control_effect")
	if (
		typeof(action_token_value) != TYPE_INT
		or int(action_token_value) <= 0
		or typeof(source_generation_value) != TYPE_INT
		or int(source_generation_value) != int(action_token_value)
		or not effect_value is Dictionary
		or (effect_value as Dictionary).is_empty()
	):
		return false
	var action_token := int(action_token_value)
	if _weapon_hit_control_claims.has(action_token):
		return false
	var effect := (effect_value as Dictionary).duplicate(true)
	if not _resolve_weapon_hit_control(effect, damage_info, final_amount):
		return false
	_record_weapon_hit_control_claim(action_token)
	return true


func _resolve_weapon_hit_control(
	effect: Dictionary,
	_damage_info: RefCounted,
	_final_amount: float
) -> bool:
	if str(effect.get("kind", "")) != "launch":
		return false
	var displacement_value: Variant = effect.get("displacement_pixels", 0.0)
	return (
		typeof(displacement_value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(displacement_value))
		and float(displacement_value) >= 0.0
	)


func _record_weapon_hit_control_claim(action_token: int) -> void:
	while _weapon_hit_control_claim_order.size() >= MAX_WEAPON_HIT_CONTROL_CLAIMS:
		var expired_token: int = _weapon_hit_control_claim_order.pop_front()
		_weapon_hit_control_claims.erase(expired_token)
	_weapon_hit_control_claims[action_token] = true
	_weapon_hit_control_claim_order.append(action_token)


func clear_weapon_hit_control_state(_reason: StringName = &"reset") -> void:
	_weapon_hit_control_claims.clear()
	_weapon_hit_control_claim_order.clear()


func get_weapon_hit_control_snapshot_for_test() -> Dictionary:
	return {
		"claim_count": _weapon_hit_control_claims.size(),
		"claim_capacity": MAX_WEAPON_HIT_CONTROL_CLAIMS,
	}


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stop_token_sequence += 1
	var source_id := StringName("legacy_time_stop_%d_%d" % [get_instance_id(), _time_stop_token_sequence])
	apply_time_stop_source(source_id, duration)
	if not _is_elite or elite_time_stop_multiplier >= 1.0:
		get_tree().create_timer(duration, false).timeout.connect(clear_time_stop_source.bind(source_id))


func apply_time_stop_source(source_id: StringName, duration: float) -> void:
	if source_id == &"" or duration <= 0.0 or _time_stop_sources.has(source_id):
		return
	_time_stop_sources[source_id] = true
	_recompute_time_stop()
	if _is_elite and elite_time_stop_multiplier < 1.0:
		var resisted_duration := duration * clampf(elite_time_stop_multiplier, 0.0, 1.0)
		if resisted_duration <= 0.0:
			clear_time_stop_source(source_id)
		else:
			get_tree().create_timer(resisted_duration, false).timeout.connect(clear_time_stop_source.bind(source_id))


func clear_time_stop_source(source_id: StringName) -> void:
	_time_stop_sources.erase(source_id)
	_recompute_time_stop()


func _recompute_time_stop() -> void:
	_time_stopped = not _time_stop_sources.is_empty()
	_refresh_control_visual()


func is_time_stopped() -> bool:
	return _time_stopped


func apply_weakpoint(duration: float, damage_bonus: float) -> void:
	if duration <= 0.0 or damage_bonus <= 0.0:
		return
	_weakpoint_token += 1
	var token := _weakpoint_token
	_weakpoint_damage_bonus = maxf(_weakpoint_damage_bonus, damage_bonus)
	await get_tree().create_timer(duration).timeout
	if token == _weakpoint_token:
		_weakpoint_damage_bonus = 0.0


func get_weakpoint_damage_bonus(damage_info: RefCounted) -> float:
	if _weakpoint_damage_bonus <= 0.0:
		return 0.0
	if damage_info.tags.has("attack:heavy") or damage_info.tags.has("attack:finisher"):
		return _weakpoint_damage_bonus
	return 0.0


func apply_damage_vulnerability(
	source_id: StringName,
	duration_frames: int,
	damage_taken_bonus: float
) -> bool:
	if (
		source_id == &""
		or duration_frames <= 0
		or not is_finite(damage_taken_bonus)
		or damage_taken_bonus <= 0.0
		or damage_taken_bonus > 2.0
		or _damage_vulnerability_sources.has(source_id)
	):
		return false
	_damage_vulnerability_sources[source_id] = {
		"remaining_frames": duration_frames,
		"damage_taken_bonus": damage_taken_bonus,
	}
	return true


func clear_damage_vulnerability_source(source_id: StringName) -> bool:
	if source_id == &"" or not _damage_vulnerability_sources.has(source_id):
		return false
	_damage_vulnerability_sources.erase(source_id)
	return true


func get_damage_taken_multiplier() -> float:
	var total_bonus := 0.0
	for source_value: Variant in _damage_vulnerability_sources.values():
		if source_value is Dictionary:
			total_bonus += float((source_value as Dictionary).get("damage_taken_bonus", 0.0))
	total_bonus += elemental_status_runtime.shock_damage_bonus()
	return clampf(1.0 + total_bonus, 1.0, 3.0)


func get_damage_taken_multiplier_for(damage_info: RefCounted) -> float:
	var base_multiplier := get_damage_taken_multiplier()
	if damage_info == null or int(damage_info.damage_type) != DamageInfoScript.DamageType.TIME:
		return base_multiplier
	var sources_value: Variant = get_meta("bow_time_erosion_sources", {})
	if not sources_value is Dictionary:
		return base_multiplier
	var erosion_multiplier := 1.0
	for source_value: Variant in (sources_value as Dictionary).values():
		if not source_value is Dictionary:
			continue
		var source := source_value as Dictionary
		if source.size() != 2 or not source.has("stacks") or not source.has("time_damage_taken_per_stack"):
			continue
		var stacks_value: Variant = source["stacks"]
		var per_stack_value: Variant = source["time_damage_taken_per_stack"]
		if typeof(stacks_value) != TYPE_INT or int(stacks_value) < 0:
			continue
		if typeof(per_stack_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var per_stack := float(per_stack_value)
		if not is_finite(per_stack) or per_stack < 0.0 or per_stack > 1.0:
			continue
		erosion_multiplier *= 1.0 + float(int(stacks_value)) * per_stack
		if not is_finite(erosion_multiplier):
			return base_multiplier
	return base_multiplier * erosion_multiplier


func apply_elemental_status(
	effect_id: StringName,
	source_id: StringName,
	generation: int,
	duration_frames: int,
	magnitude: float = 1.0,
	tick_interval_frames: int = 30,
	attack_speed_multiplier: float = -1.0,
	damage_source: Node = null,
	damage_attacker: Node = null
) -> bool:
	var applied: bool = elemental_status_runtime.apply_status(
		effect_id,
		source_id,
		generation,
		duration_frames,
		magnitude,
		tick_interval_frames,
		attack_speed_multiplier,
		damage_source,
		damage_attacker
	)
	if applied:
		_refresh_control_visual()
	return applied


func clear_elemental_status(effect_id: StringName, source_id: StringName, generation: int) -> bool:
	var removed: bool = elemental_status_runtime.remove_status(effect_id, source_id, generation)
	if removed:
		_refresh_control_visual()
	return removed


func clear_owned_elemental_statuses(source_id: StringName, generation: int = -1) -> int:
	var removed: int = elemental_status_runtime.clear_owned(source_id, generation)
	if removed > 0:
		_refresh_control_visual()
	return removed


func clear_elemental_statuses(_reason: StringName = &"clear") -> int:
	var removed: int = elemental_status_runtime.clear_all()
	if removed > 0:
		_refresh_control_visual()
	return removed


func reset_elemental_statuses() -> void:
	elemental_status_runtime.reset_runtime_state()
	_elemental_blind_action_sequence = 0
	if has_meta(ELEMENTAL_STATUS_SEED_INITIALIZED_META):
		remove_meta(ELEMENTAL_STATUS_SEED_INITIALIZED_META)
	if has_meta(ELEMENTAL_STATUS_SEED_MATERIAL_META):
		remove_meta(ELEMENTAL_STATUS_SEED_MATERIAL_META)
	_refresh_control_visual()


func configure_elemental_status_seed(
	deterministic_seed: int,
	slow_floor_multiplier: float = 0.30,
	attack_slow_floor_multiplier: float = -1.0
) -> void:
	elemental_status_runtime.configure(
		deterministic_seed,
		slow_floor_multiplier,
		attack_slow_floor_multiplier
	)


func has_elemental_status(effect_id: StringName, source_id: StringName, generation: int) -> bool:
	return elemental_status_runtime.has_status(effect_id, source_id, generation)


func is_elementally_frozen() -> bool:
	return elemental_status_runtime.is_frozen()


func elemental_status_snapshot() -> Dictionary:
	return elemental_status_runtime.snapshot()


func _tick_elemental_status_runtime() -> void:
	var events: Dictionary = elemental_status_runtime.advance_frame()
	for tick_value: Variant in events.get("burn_ticks", []):
		if not health.is_alive() or not tick_value is Dictionary:
			break
		var tick := tick_value as Dictionary
		var tick_damage := float(tick.get("damage", 0.0))
		if tick_damage <= 0.0:
			continue
		var damage_source := _live_node_or_null(tick.get("damage_source"))
		var damage_attacker := _live_node_or_null(tick.get("damage_attacker"))
		var damage_info := _damage_info_from_plan(
			tick_damage,
			DamageInfoScript.DamageType.FIRE,
			self,
			StringName("burn:%s:%d" % [str(tick.get("source_id", "")), int(tick.get("generation", 0))]),
			[
			"weapon:staff",
			"element:fire",
			"status:burn",
			"status_source:%s" % str(tick.get("source_id", "")),
			"status_generation:%d" % int(tick.get("generation", -1)),
			],
			Vector2.ZERO,
			damage_source,
			damage_attacker,
			false
		)
		if damage_info == null:
			continue
		health.take_damage(damage_info)
	if not (events.get("expired", []) as Array).is_empty():
		_refresh_control_visual()


func _live_node_or_null(value: Variant) -> Node:
	if value is Node and is_instance_valid(value):
		return value as Node
	return null


func _damage_info_from_plan(
	amount: float,
	damage_type: int,
	damage_target: Node,
	channel: StringName,
	tags: Array[String],
	knockback: Vector2,
	damage_source: Node,
	damage_attacker: Node,
	can_crit: bool = true
) -> RefCounted:
	_damage_action_sequence += 1
	var source_id := _stable_damage_identity(self, "enemy")
	return DamageInfoScript.from_plan({
		"run_id": _damage_run_id(),
		"target_id": _stable_damage_identity(damage_target, "pending_target"),
		"hostile_source_id": StringName("%s:%s" % [str(source_id), str(channel)]),
		"attack_generation": _damage_action_sequence,
		"action_token": _damage_action_sequence,
		"amount": amount,
		"damage_type": damage_type,
		"source": damage_source,
		"attacker": damage_attacker,
		"can_crit": can_crit,
		"knockback": knockback,
		"tags": tags,
	})


func _damage_run_id() -> StringName:
	for key: StringName in [&"run_id", &"authoritative_run_id"]:
		if has_meta(key):
			var value := str(get_meta(key)).strip_edges()
			if not value.is_empty():
				return StringName(value)
	return &"runtime"


func _stable_damage_identity(node: Node, fallback: String) -> StringName:
	if node != null and is_instance_valid(node):
		for key: StringName in [&"stable_target_id", &"stable_target_key", &"encounter_spawn_id"]:
			if node.has_meta(key):
				var value := str(node.get_meta(key)).strip_edges()
				if not value.is_empty():
					return StringName(value)
		var node_name := str(node.name).strip_edges()
		if not node_name.is_empty() and not node_name.begins_with("@"):
			return StringName(node_name)
	return StringName(fallback)


func _should_elemental_blind_miss() -> bool:
	var action_sequence := _elemental_blind_action_sequence
	_elemental_blind_action_sequence += 1
	return elemental_status_runtime.should_blind_miss(action_sequence)


func _exit_tree() -> void:
	elemental_status_runtime.clear_all()


func _tick_damage_vulnerability_sources() -> void:
	for source_id: Variant in _damage_vulnerability_sources.keys():
		var source_value: Variant = _damage_vulnerability_sources.get(source_id)
		if not source_value is Dictionary:
			_damage_vulnerability_sources.erase(source_id)
			continue
		var remaining := int((source_value as Dictionary).get("remaining_frames", 0)) - 1
		if remaining <= 0:
			_damage_vulnerability_sources.erase(source_id)
		else:
			(source_value as Dictionary)["remaining_frames"] = remaining


func apply_time_rift(source_id: StringName, slow_multiplier: float) -> void:
	_rift_slow_sources[source_id] = clampf(slow_multiplier, 0.1, 1.0)
	_recompute_rift_slow()


func clear_time_rift(source_id: StringName) -> void:
	_rift_slow_sources.erase(source_id)
	_recompute_rift_slow()


func is_time_rifted() -> bool:
	return not _rift_slow_sources.is_empty()


func _recompute_rift_slow() -> void:
	_rift_slow_multiplier = 1.0
	for source_multiplier: Variant in _rift_slow_sources.values():
		_rift_slow_multiplier = minf(_rift_slow_multiplier, float(source_multiplier))


func apply_elite_modifier(hp_multiplier: float = 1.8, attack_multiplier: float = 1.25, speed_multiplier: float = 1.08) -> void:
	if _is_elite:
		return
	_is_elite = true
	add_to_group("elite_enemies")
	max_hp *= hp_multiplier
	attack *= attack_multiplier
	move_speed *= speed_multiplier
	health.max_hp = max_hp
	health.current_hp = max_hp
	visual.scale *= 1.15
	_restore_visual_color()
	_on_elite_modifier_applied()
