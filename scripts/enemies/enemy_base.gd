class_name EnemyBase
extends CharacterBody2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

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
var _rift_slow_sources: int = 0
var _is_elite: bool = false
var _weakpoint_damage_bonus: float = 0.0
var _weakpoint_token: int = 0
var _attack_phase: AttackPhase = AttackPhase.READY
var _attack_phase_remaining: float = 0.0
var _committed_attack_direction: Vector2 = Vector2.RIGHT
var _time_stop_token_sequence: int = 0
var _active_time_stop_tokens: Dictionary = {}

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
	if not health.is_alive():
		return
	if _time_stopped:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	_tick_additional_action_timers(delta)
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node2D
	if target == null:
		return
	_tick_attack_phase(delta)
	if is_attack_locked():
		velocity = _knockback_velocity
		move_and_slide()
		return
	_tick_ai(delta)


func _tick_ai(_delta: float) -> void:
	pass


func _tick_additional_action_timers(_delta: float) -> void:
	pass


func _move_toward_target(speed_multiplier: float = 1.0) -> void:
	var direction := global_position.direction_to(target.global_position)
	velocity = direction * _current_move_speed() * speed_multiplier + _knockback_velocity
	move_and_slide()


func _current_move_speed() -> float:
	return move_speed * _rift_slow_multiplier


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
	var damage_info := DamageInfoScript.new(attack, DamageInfoScript.DamageType.PHYSICAL, self, self)
	damage_info.tags = ["enemy:melee"]
	damage_info.knockback = _committed_attack_direction * 180.0
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


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stop_token_sequence += 1
	var token := _time_stop_token_sequence
	_active_time_stop_tokens[token] = true
	_time_stopped = true
	_refresh_control_visual()
	var effective_duration := duration * (elite_time_stop_multiplier if _is_elite else 1.0)
	await get_tree().create_timer(effective_duration).timeout
	_active_time_stop_tokens.erase(token)
	_time_stopped = not _active_time_stop_tokens.is_empty()
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


func apply_time_rift(slow_multiplier: float) -> void:
	_rift_slow_sources += 1
	_rift_slow_multiplier = minf(_rift_slow_multiplier, clampf(slow_multiplier, 0.1, 1.0))


func clear_time_rift() -> void:
	_rift_slow_sources = maxi(0, _rift_slow_sources - 1)
	if _rift_slow_sources == 0:
		_rift_slow_multiplier = 1.0


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
