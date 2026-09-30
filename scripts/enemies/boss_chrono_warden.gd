extends "res://scripts/enemies/enemy_base.gd"
class_name BossChronoWarden

signal enemy_summoned(enemy: Node)

const FragmentScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const TimeCrackScript := preload("res://scripts/enemies/boss_time_crack.gd")
const STAFF_FREEZE_DELAY_FRAMES := 12
const STAFF_BLIND_DELAY_FRAMES := 8
const GAUNTLETS_CONVERSION_ID := "gauntlets_poised_launch"
const GAUNTLETS_POISE_MULTIPLIER := 1.4

enum BossAction { NONE, MELEE, SLAM, RADIAL, AIMED, SUMMON, TIME_CRACK }
enum BossActionPhase { IDLE, WINDUP, RECOVERY }

const ACTION_DEFINITIONS := {
	BossAction.MELEE: {
		"id": "MELEE",
		"windup": 0.32,
		"recovery": 0.38,
		"shape": "cone",
		"radius": 14.0,
		"length": 54.0,
	},
	BossAction.SLAM: {
		"id": "SLAM",
		"windup": 0.75,
		"recovery": 0.90,
		"shape": "circle",
		"radius": 72.0,
		"length": 0.0,
	},
	BossAction.RADIAL: {
		"id": "RADIAL",
		"windup": 0.62,
		"recovery": 0.52,
		"shape": "ring",
		"radius": 62.0,
		"length": 0.0,
	},
	BossAction.AIMED: {
		"id": "AIMED",
		"windup": 0.72,
		"recovery": 0.60,
		"shape": "line",
		"radius": 8.0,
		"length": 260.0,
	},
	BossAction.SUMMON: {
		"id": "SUMMON",
		"windup": 0.85,
		"recovery": 0.70,
		"shape": "summon_slots",
		"radius": 14.0,
		"length": 0.0,
	},
	BossAction.TIME_CRACK: {
		"id": "TIME_CRACK",
		"windup": 0.95,
		"recovery": 0.65,
		"shape": "target_circle",
		"radius": 50.0,
		"length": 0.0,
	},
}

@export var projectile_scene: PackedScene
@export var radial_projectile_count: int = 8
@export var exposed_defense_penalty: float = 3.0
@export var slam_radius: float = 72.0
@export var fragment_count: int = 2
@export var crack_arm_delay: float = 1.15
@export var weapon_poise_threshold: float = 100.0
@export var weapon_poise_recovery_bonus_frames: int = 30
@export var weapon_poise_decay_per_second: float = 8.0

@onready var combat_telegraph: Node2D = $CombatTelegraph2D

var _base_defense: float = 0.0
var _pattern_timer: float = 0.0
var _exposed: bool = false
var _phase: int = 1
var _aimed_burst_next: bool = false
var _special_index: int = 0
var _action: int = BossAction.NONE
var _action_phase: int = BossActionPhase.IDLE
var _action_time_remaining: float = 0.0
var _action_resolved: bool = false
var _committed_aim_direction := Vector2.RIGHT
var _committed_target_point := Vector2.ZERO
var _committed_summon_slots: Array[Vector2] = []
var _action_resolution_counts: Dictionary = {}
var _exposure_sources: Dictionary = {}
var _weapon_control_sources: Dictionary = {}
var _weapon_poise: float = 0.0
var slam_windup: float:
	get:
		return _action_windup(BossAction.SLAM)
var slam_recovery: float:
	get:
		return _action_recovery(BossAction.SLAM)
var _slam_timer: float:
	get:
		if _action == BossAction.SLAM and _action_phase == BossActionPhase.WINDUP:
			return _action_time_remaining
		return 0.0
var _slam_recovery_timer: float:
	get:
		if _action == BossAction.SLAM and _action_phase == BossActionPhase.RECOVERY:
			return _action_time_remaining
		return 0.0


func _ready() -> void:
	max_hp = 420.0
	attack = 16.0
	defense = 3.0
	move_speed = 78.0
	attack_range = 54.0
	attack_cooldown = 1.1
	_base_defense = defense
	super()
	add_to_group("bosses")
	health.damaged.connect(_on_boss_damaged)


func _tick_ai(delta: float) -> void:
	_update_phase()
	_weapon_poise = maxf(0.0, _weapon_poise - maxf(0.0, weapon_poise_decay_per_second) * delta)
	_pattern_timer = maxf(0.0, _pattern_timer - delta)
	if _tick_action(delta):
		_hold_position()
		return
	if _pattern_timer <= 0.0 and _run_next_pattern():
		_pattern_timer = _pattern_interval()
		return
	if global_position.distance_to(target.global_position) > attack_range:
		_move_toward_target(0.7)
	else:
		_hold_position()
		_try_start_action(BossAction.MELEE)


func _hold_position() -> void:
	velocity = _knockback_velocity
	move_and_slide()
	if _action_phase == BossActionPhase.WINDUP:
		combat_telegraph.update_origin_global(global_position)


func _run_next_pattern() -> bool:
	var pattern_slot := _special_index % 4
	var action := BossAction.NONE
	var toggles_aimed_burst := false
	match pattern_slot:
		0:
			action = BossAction.SLAM
		1:
			action = BossAction.SUMMON if _phase >= 2 else BossAction.RADIAL
		2:
			if _phase >= 2:
				action = BossAction.TIME_CRACK
			else:
				action = _next_burst_action()
				toggles_aimed_burst = true
		_:
			action = _next_burst_action()
			toggles_aimed_burst = true
	if not _try_start_action(action):
		return false
	_special_index += 1
	if toggles_aimed_burst:
		_aimed_burst_next = not _aimed_burst_next
	return true


func _next_burst_action() -> int:
	if _phase >= 2 and _aimed_burst_next:
		return BossAction.AIMED
	return BossAction.RADIAL


func _try_start_action(action: int) -> bool:
	if _action != BossAction.NONE or not ACTION_DEFINITIONS.has(action) or not _can_start_action(action):
		return false
	_action = action
	_action_phase = BossActionPhase.WINDUP
	_action_time_remaining = _action_windup(action)
	_action_resolved = false
	_capture_action_commitment()
	_show_action_telegraph()
	if action == BossAction.SLAM:
		visual.scale = Vector2(1.18, 1.18)
	_restore_visual_color()
	return true


func _can_start_action(action: int) -> bool:
	match action:
		BossAction.MELEE:
			return (
				_attack_cooldown_remaining <= 0.0
				and target != null
				and is_instance_valid(target)
				and global_position.distance_to(target.global_position) <= attack_range
				and target.has_node("HealthComponent")
			)
		BossAction.RADIAL, BossAction.AIMED:
			return projectile_scene != null
		BossAction.SUMMON, BossAction.TIME_CRACK:
			return get_parent() != null
		BossAction.SLAM:
			return true
	return false


func _tick_action(delta: float) -> bool:
	if _action == BossAction.NONE:
		return false
	_action_time_remaining = maxf(0.0, _action_time_remaining - delta)
	match _action_phase:
		BossActionPhase.WINDUP:
			combat_telegraph.set_remaining_time(_action_time_remaining)
			if _action_time_remaining <= 0.0:
				_resolve_action_once()
				combat_telegraph.clear_telegraph()
				_enter_action_recovery()
		BossActionPhase.RECOVERY:
			if _action_time_remaining <= 0.0:
				_complete_action()
	return true


func _resolve_action_once() -> void:
	if _action_resolved:
		return
	_action_resolved = true
	var action_id := _action_name(_action)
	_action_resolution_counts[action_id] = int(_action_resolution_counts.get(action_id, 0)) + 1
	_resolve_action()


func _resolve_action() -> void:
	match _action:
		BossAction.MELEE:
			_resolve_melee()
		BossAction.SLAM:
			_resolve_slam()
		BossAction.RADIAL:
			_fire_radial_burst()
		BossAction.AIMED:
			_fire_aimed_burst()
		BossAction.SUMMON:
			_summon_fragments()
		BossAction.TIME_CRACK:
			_create_time_crack()


func _enter_action_recovery() -> void:
	_action_phase = BossActionPhase.RECOVERY
	_action_time_remaining = _action_recovery(_action)
	if _action == BossAction.SLAM:
		visual.scale = Vector2.ONE
		_add_exposure_source(&"slam_recovery")
	if _action_time_remaining <= 0.0:
		_complete_action()
	else:
		_restore_visual_color()


func _complete_action() -> void:
	if _action == BossAction.SLAM:
		_remove_exposure_source(&"slam_recovery")
		visual.scale = Vector2.ONE
	_action = BossAction.NONE
	_action_phase = BossActionPhase.IDLE
	_action_time_remaining = 0.0
	_action_resolved = false
	_committed_aim_direction = Vector2.RIGHT
	_committed_target_point = global_position
	_committed_summon_slots.clear()
	combat_telegraph.clear_telegraph()
	_restore_visual_color()


func _action_windup(action: int) -> float:
	var definition: Dictionary = ACTION_DEFINITIONS.get(action, {})
	return float(definition.get("windup", 0.0))


func _action_recovery(action: int) -> float:
	var definition: Dictionary = ACTION_DEFINITIONS.get(action, {})
	return float(definition.get("recovery", 0.0))


func _capture_action_commitment() -> void:
	_committed_target_point = global_position
	if target != null and is_instance_valid(target):
		_committed_target_point = target.global_position
		_committed_aim_direction = global_position.direction_to(_committed_target_point)
	else:
		_committed_aim_direction = Vector2.RIGHT
	if _committed_aim_direction.is_zero_approx():
		_committed_aim_direction = Vector2.RIGHT
	_committed_summon_slots.clear()
	if _action == BossAction.SUMMON:
		for index: int in range(fragment_count):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / maxf(1.0, float(fragment_count)))
			_committed_summon_slots.append(global_position + direction * 86.0)


func _show_action_telegraph() -> void:
	var definition: Dictionary = ACTION_DEFINITIONS[_action]
	var radius := float(definition.get("radius", 0.0))
	var length := float(definition.get("length", 0.0))
	if _action == BossAction.MELEE:
		length = attack_range
	elif _action == BossAction.SLAM:
		radius = slam_radius
	elif _action == BossAction.TIME_CRACK:
		radius = 58.0 if _phase >= 3 else 50.0
	combat_telegraph.show_telegraph(
		str(definition["id"]),
		str(definition["shape"]),
		global_position,
		_committed_aim_direction,
		_committed_target_point,
		_committed_summon_slots,
		radius,
		length,
		_action_time_remaining
	)


func _update_phase() -> void:
	var hp_ratio: float = health.current_hp / maxf(1.0, health.max_hp)
	var next_phase := 1
	if hp_ratio <= 0.25:
		next_phase = 3
	elif hp_ratio <= 0.55:
		next_phase = 2
	if next_phase == _phase:
		return
	clear_elemental_statuses(&"boss_phase_transition")
	_clear_weapon_control_sources()
	_phase = next_phase
	radial_projectile_count = 10 if _phase == 2 else 12
	move_speed = 92.0 if _phase == 2 else 108.0
	_restore_visual_color()


func _pattern_interval() -> float:
	if _exposed:
		return 3.0
	if _phase == 3:
		return 1.55
	if _phase == 2:
		return 1.9
	return 2.4


func _fire_radial_burst() -> void:
	if projectile_scene == null:
		return
	for index: int in range(radial_projectile_count):
		var angle := TAU * float(index) / float(radial_projectile_count)
		var projectile := projectile_scene.instantiate()
		projectile.global_position = global_position + Vector2.RIGHT.rotated(angle) * 34.0
		projectile.direction = Vector2.RIGHT.rotated(angle)
		projectile.damage = attack * 0.65
		get_parent().add_child(projectile)


func _fire_aimed_burst() -> void:
	if projectile_scene == null:
		return
	var base_direction := _committed_aim_direction
	var spread := 0.18 if _phase == 2 else 0.28
	var shot_count := 3 if _phase == 2 else 5
	for index: int in range(shot_count):
		var centered_index := float(index) - float(shot_count - 1) * 0.5
		var projectile := projectile_scene.instantiate()
		projectile.global_position = global_position + base_direction * 34.0
		projectile.direction = base_direction.rotated(centered_index * spread)
		projectile.speed = 230.0 if _phase == 2 else 260.0
		projectile.damage = attack * 0.7
		get_parent().add_child(projectile)


func _start_slam() -> bool:
	return _try_start_action(BossAction.SLAM)


func _resolve_slam() -> void:
	if target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) <= slam_radius:
		var health_component := target.get_node_or_null("HealthComponent")
		if health_component != null:
			var damage_info := DamageInfoScript.new(attack * 1.6, DamageInfoScript.DamageType.PHYSICAL, self, self)
			damage_info.tags = ["boss:slam", "enemy:melee"]
			damage_info.knockback = _committed_aim_direction * 260.0
			health_component.take_damage(damage_info)


func _resolve_melee() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return
	var health_component := target.get_node_or_null("HealthComponent")
	if health_component == null:
		return
	_attack_cooldown_remaining = attack_cooldown
	var damage_info := DamageInfoScript.new(attack, DamageInfoScript.DamageType.PHYSICAL, self, self)
	damage_info.tags = ["enemy:melee", "boss:melee"]
	damage_info.knockback = _committed_aim_direction * 180.0
	health_component.take_damage(damage_info)


func _summon_fragments() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var summon_slots := _committed_summon_slots.duplicate()
	if summon_slots.is_empty():
		for index: int in range(fragment_count):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / maxf(1.0, float(fragment_count)))
			summon_slots.append(global_position + direction * 86.0)
	for index: int in range(summon_slots.size()):
		var fragment := FragmentScene.instantiate()
		parent.add_child(fragment)
		fragment.global_position = summon_slots[index]
		if fragment.has_method("apply_elite_modifier") and _phase >= 3:
			fragment.apply_elite_modifier(1.25, 1.1, 1.0)
		enemy_summoned.emit(fragment)
		if bool(fragment.get_meta("encounter_counted", false)):
			EventBus.enemy_spawned.emit(fragment, {"boss": false, "summoned": true})


func _create_time_crack() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	var crack := TimeCrackScript.new()
	crack.arm_delay = crack_arm_delay
	crack.radius = 58.0 if _phase >= 3 else 50.0
	crack.damage = attack * 1.15
	parent.add_child(crack)
	var crack_position := _committed_target_point
	if _action != BossAction.TIME_CRACK:
		crack_position = target.global_position if target != null and is_instance_valid(target) else global_position
	crack.global_position = crack_position
	return crack


func force_slam_for_test() -> void:
	_start_slam()


func force_summon_fragments_for_test() -> void:
	_summon_fragments()


func force_time_crack_for_test() -> Node:
	return _create_time_crack()


func force_action_for_test(action_name: String) -> bool:
	var action := _action_from_name(action_name)
	if action == BossAction.NONE:
		return false
	return _try_start_action(action)


func advance_action_for_test(delta: float) -> bool:
	return _tick_action(maxf(0.0, delta))


func get_action_definitions_for_test() -> Dictionary:
	var result := {}
	for action: int in ACTION_DEFINITIONS.keys():
		var definition: Dictionary = ACTION_DEFINITIONS[action]
		result[str(definition["id"])] = definition.duplicate(true)
	return result


func get_active_telegraph_snapshot_for_test() -> Dictionary:
	return combat_telegraph.get_snapshot()


func get_committed_action_snapshot_for_test() -> Dictionary:
	return {
		"action_id": _action_name(_action),
		"aim_direction": _committed_aim_direction,
		"target_point": _committed_target_point,
		"summon_slots": _committed_summon_slots.duplicate(),
	}


func get_action_resolution_count_for_test(action_name: String) -> int:
	return int(_action_resolution_counts.get(action_name, 0))


func _restore_visual_color() -> void:
	if _action == BossAction.SLAM and _action_phase == BossActionPhase.WINDUP:
		visual.color = Color(1.0, 0.72, 0.18)
	elif _exposed:
		visual.color = Color(0.3, 0.85, 1.0)
	elif _phase == 3:
		visual.color = Color(1.0, 0.1, 0.55)
	elif _phase == 2:
		visual.color = Color(1.0, 0.35, 0.25)
	else:
		visual.color = Color(0.95, 0.15, 0.35)


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stop_token_sequence += 1
	var source_id := StringName("legacy_time_stop_%d_%d" % [get_instance_id(), _time_stop_token_sequence])
	apply_time_stop_source(source_id, duration)
	get_tree().create_timer(duration, false).timeout.connect(clear_time_stop_source.bind(source_id))


func apply_time_stop_source(source_id: StringName, duration: float) -> void:
	if source_id == &"" or duration <= 0.0 or _time_stop_sources.has(source_id):
		return
	_time_stop_sources[source_id] = true
	var resisted_delay := minf(duration * 0.35, 1.1)
	match _action_phase:
		BossActionPhase.WINDUP:
			_action_time_remaining += resisted_delay
			combat_telegraph.set_remaining_time(_action_time_remaining)
		BossActionPhase.RECOVERY:
			_action_time_remaining += maxf(resisted_delay, 0.8)
		_:
			_pattern_timer += resisted_delay
	_add_exposure_source(source_id)


func clear_time_stop_source(source_id: StringName) -> void:
	if not _time_stop_sources.has(source_id):
		return
	_time_stop_sources.erase(source_id)
	_remove_exposure_source(source_id)


func get_boss_ui_snapshot() -> Dictionary:
	return {
		"action": _action_name(_action),
		"phase": _action_phase_name(_action_phase),
		"remaining": _action_time_remaining,
		"boss_phase": _phase,
		"exposed": _exposed,
	}


func _action_name(action: int) -> String:
	match action:
		BossAction.MELEE:
			return "MELEE"
		BossAction.SLAM:
			return "SLAM"
		BossAction.RADIAL:
			return "RADIAL"
		BossAction.AIMED:
			return "AIMED"
		BossAction.SUMMON:
			return "SUMMON"
		BossAction.TIME_CRACK:
			return "TIME_CRACK"
	return "NONE"


func _action_from_name(action_name: String) -> int:
	for action: int in ACTION_DEFINITIONS.keys():
		if str(ACTION_DEFINITIONS[action]["id"]) == action_name:
			return action
	return BossAction.NONE


func _action_phase_name(action_phase: int) -> String:
	match action_phase:
		BossActionPhase.WINDUP:
			return "WINDUP"
		BossActionPhase.RECOVERY:
			return "RECOVERY"
	return "IDLE"


func apply_time_rift(source_id: StringName, slow_multiplier: float) -> void:
	var source_was_active := _rift_slow_sources.has(source_id)
	super.apply_time_rift(source_id, slow_multiplier)
	if not source_was_active:
		_add_exposure_source(source_id)
	_pattern_timer = maxf(_pattern_timer, 1.2)


func clear_time_rift(source_id: StringName) -> void:
	var source_was_active := _rift_slow_sources.has(source_id)
	super.clear_time_rift(source_id)
	if source_was_active:
		_remove_exposure_source(source_id)


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
	if effect_id in [&"freeze", &"blind"] and not _can_convert_staff_control():
		return false
	var already_active := has_elemental_status(effect_id, source_id, generation)
	var applied := super.apply_elemental_status(
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
	if not applied or already_active:
		return applied
	match effect_id:
		&"freeze":
			_apply_staff_control_delay(STAFF_FREEZE_DELAY_FRAMES)
		&"blind":
			_apply_staff_control_delay(STAFF_BLIND_DELAY_FRAMES)
	return true


func is_elementally_frozen() -> bool:
	return false


func _can_convert_staff_control() -> bool:
	if _action_phase == BossActionPhase.WINDUP:
		return false
	return _action_phase == BossActionPhase.RECOVERY or _exposed


func _apply_staff_control_delay(delay_frames: int) -> void:
	var delay_seconds := maxf(0.0, float(delay_frames) / 60.0)
	if delay_seconds <= 0.0:
		return
	if _action != BossAction.NONE:
		_action_time_remaining += delay_seconds
		if _action_phase == BossActionPhase.WINDUP:
			combat_telegraph.set_remaining_time(_action_time_remaining)
		return
	_pattern_timer += delay_seconds


func apply_weapon_control_conversion(
	source_id: StringName,
	recovery_frames: int,
	exposure_frames: int,
	poise_damage: float
) -> bool:
	if (
		source_id == &""
		or _weapon_control_sources.has(source_id)
		or recovery_frames < 0
		or exposure_frames < 0
		or not is_finite(poise_damage)
		or poise_damage < 0.0
	):
		return false
	if _action_phase == BossActionPhase.WINDUP:
		return false
	if _action_phase != BossActionPhase.RECOVERY and not _exposed:
		return false
	_weapon_control_sources[source_id] = true
	if _action_phase == BossActionPhase.RECOVERY and recovery_frames > 0:
		_action_time_remaining += minf(float(recovery_frames) / 60.0, 1.5)
	if exposure_frames > 0:
		_add_exposure_source(source_id)
	var source_lifetime_frames := maxi(recovery_frames, exposure_frames)
	if source_lifetime_frames > 0:
		get_tree().create_timer(minf(float(source_lifetime_frames) / 60.0, 1.5), false).timeout.connect(
			_clear_weapon_control_source.bind(source_id)
		)
	_weapon_poise = minf(maxf(0.0, weapon_poise_threshold), _weapon_poise + poise_damage)
	if weapon_poise_threshold > 0.0 and _weapon_poise >= weapon_poise_threshold:
		_weapon_poise = 0.0
		if _action_phase == BossActionPhase.RECOVERY:
			_action_time_remaining += maxf(0.0, float(weapon_poise_recovery_bonus_frames) / 60.0)
	if source_lifetime_frames <= 0:
		_clear_weapon_control_source(source_id)
	return true


func _resolve_weapon_hit_control(
	effect: Dictionary,
	damage_info: RefCounted,
	_final_amount: float
) -> bool:
	if (
		str(effect.get("kind", "")) != "launch"
		or str(effect.get("conversion_id", "")) != GAUNTLETS_CONVERSION_ID
		or typeof(effect.get("airborne")) != TYPE_BOOL
		or bool(effect.get("airborne", true))
		or str(effect.get("active_attack_policy", "")) != "preserve_committed"
		or typeof(effect.get("interrupt_active_attack")) != TYPE_BOOL
		or bool(effect.get("interrupt_active_attack", true))
		or not damage_info.tags.has("weapon:gauntlets")
	):
		return false
	var allowed_states_value: Variant = effect.get("allowed_states", [])
	if not allowed_states_value is Array:
		return false
	var conversion_state := (
		"EXPOSED"
		if _exposed and _action_phase != BossActionPhase.WINDUP
		else _action_phase_name(_action_phase)
	)
	if conversion_state not in (allowed_states_value as Array):
		return false
	var poise_damage_value: Variant = effect.get("poise_damage")
	var multiplier_value: Variant = effect.get("boss_poise_multiplier")
	var displacement_value: Variant = effect.get("displacement_pixels", 0.0)
	if (
		typeof(poise_damage_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(poise_damage_value))
		or float(poise_damage_value) <= 0.0
		or typeof(multiplier_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(multiplier_value))
		or not is_equal_approx(float(multiplier_value), GAUNTLETS_POISE_MULTIPLIER)
		or typeof(displacement_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(displacement_value))
		or float(displacement_value) < 0.0
	):
		return false
	var action_token := int(damage_info.get("action_token"))
	var source_generation := int(damage_info.get("source_generation"))
	var source_id := StringName(str(effect.get(
		"source_id",
		"%s:%d:%d" % [GAUNTLETS_CONVERSION_ID, action_token, source_generation]
	)))
	if source_id == &"":
		return false
	return apply_weapon_control_conversion(
		source_id,
		0,
		0,
		float(poise_damage_value) * GAUNTLETS_POISE_MULTIPLIER
	)


func get_weapon_control_snapshot_for_test() -> Dictionary:
	var hit_control: Dictionary = get_weapon_hit_control_snapshot_for_test()
	return {
		"source_count": _weapon_control_sources.size(),
		"poise": _weapon_poise,
		"poise_threshold": weapon_poise_threshold,
		"hit_claim_count": int(hit_control.get("claim_count", 0)),
		"hit_claim_capacity": int(hit_control.get("claim_capacity", 0)),
		"airborne": false,
	}


func _clear_weapon_control_source(source_id: StringName) -> void:
	if not _weapon_control_sources.has(source_id):
		return
	_weapon_control_sources.erase(source_id)
	_remove_exposure_source(source_id)


func _clear_weapon_control_sources() -> void:
	for source_value: Variant in _weapon_control_sources.keys():
		_remove_exposure_source(StringName(str(source_value)))
	_weapon_control_sources.clear()
	_weapon_poise = 0.0


func clear_weapon_hit_control_state(reason: StringName = &"reset") -> void:
	super.clear_weapon_hit_control_state(reason)
	_clear_weapon_control_sources()


func _add_exposure_source(source_id: StringName) -> void:
	_exposure_sources[source_id] = int(_exposure_sources.get(source_id, 0)) + 1
	_refresh_exposed_state()


func _remove_exposure_source(source_id: StringName) -> void:
	if not _exposure_sources.has(source_id):
		return
	var remaining := int(_exposure_sources[source_id]) - 1
	if remaining <= 0:
		_exposure_sources.erase(source_id)
	else:
		_exposure_sources[source_id] = remaining
	_refresh_exposed_state()


func _refresh_exposed_state() -> void:
	_set_exposed(not _exposure_sources.is_empty())


func _set_exposed(value: bool) -> void:
	_exposed = value
	health.defense = maxf(0.0, _base_defense - exposed_defense_penalty) if _exposed else _base_defense
	_restore_visual_color()


func _on_boss_damaged(_amount: float, _current_hp: float) -> void:
	_update_phase()
