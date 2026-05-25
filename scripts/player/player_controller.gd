class_name PlayerController
extends CharacterBody2D

const StatsResource := preload("res://scripts/core/stats.gd")

@export var stats: Resource

@onready var health: Node = $HealthComponent
@onready var sword_weapon: Node = $SwordWeapon
@onready var time_manager: Node = $TimeManager
@onready var rewind_recorder: Node = $RewindRecorder
@onready var visual: Polygon2D = $Visual

var _dash_time_remaining: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _last_move_direction: Vector2 = Vector2.RIGHT
var _dash_invulnerable_bonus: float = 0.0

const DASH_DURATION := 0.28
const DASH_COOLDOWN := 0.45
const DASH_SPEED := 520.0
const DASH_INVULNERABLE_TIME := 0.20
const KNOCKBACK_DECAY := 12.0
const BASE_COLOR := Color(0.2, 0.85, 0.95)


func _ready() -> void:
	add_to_group("player")
	if stats == null:
		stats = StatsResource.new()
	_apply_stats_to_components(true)
	health.damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_weapon_aim()
	_handle_attack_input()
	_handle_time_input()
	_handle_movement(delta)


func _update_timers(delta: float) -> void:
	_dash_time_remaining = maxf(0.0, _dash_time_remaining - delta)
	_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)


func _update_weapon_aim() -> void:
	var aim_direction := global_position.direction_to(get_global_mouse_position())
	if aim_direction.length_squared() > 0.001:
		sword_weapon.rotation = aim_direction.angle()


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		sword_weapon.try_attack(false)
	if Input.is_action_just_pressed("heavy_attack"):
		sword_weapon.try_attack(true)


func _handle_time_input() -> void:
	if Input.is_action_just_pressed("time_stop"):
		time_manager.try_time_stop()
	if Input.is_action_just_pressed("time_rewind"):
		time_manager.try_rewind(rewind_recorder)


func _handle_movement(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.001:
		_last_move_direction = input_vector.normalized()

	if Input.is_action_just_pressed("dash") and _dash_cooldown_remaining <= 0.0:
		_start_dash()

	if _dash_time_remaining > 0.0:
		velocity = _dash_velocity + _knockback_velocity
	else:
		velocity = input_vector * stats.move_speed + _knockback_velocity
	move_and_slide()


func _start_dash() -> void:
	_dash_time_remaining = DASH_DURATION
	_dash_cooldown_remaining = DASH_COOLDOWN
	_dash_velocity = _last_move_direction * DASH_SPEED
	health.apply_invulnerability(DASH_INVULNERABLE_TIME + _dash_invulnerable_bonus)
	EventBus.player_dashed.emit()
	EventBus.publish(EventBus.PLAYER_DASHED)


func apply_reward(reward_data: Dictionary) -> void:
	var effects: Dictionary = reward_data.get("effects", {})
	_apply_effects(effects)


func apply_curse(curse_data: Dictionary) -> void:
	var effects: Dictionary = curse_data.get("effects", {})
	_apply_effects(effects)
	GameState.add_run_curse(curse_data)
	EventBus.curse_selected.emit(curse_data)
	EventBus.publish(EventBus.CURSE_SELECTED, {"curse": curse_data})


func _apply_effects(effects: Dictionary) -> void:
	if effects.has("attack_multiplier"):
		stats.attack *= float(effects["attack_multiplier"])
	if effects.has("attack_speed_multiplier"):
		stats.attack_speed *= float(effects["attack_speed_multiplier"])
	if effects.has("max_hp_bonus"):
		stats.max_hp += float(effects["max_hp_bonus"])
	if effects.has("max_hp_multiplier"):
		stats.max_hp *= float(effects["max_hp_multiplier"])
	if effects.has("defense_bonus"):
		stats.defense += float(effects["defense_bonus"])
	if effects.has("time_energy_max_bonus"):
		stats.time_energy_max += float(effects["time_energy_max_bonus"])
	if effects.has("time_energy_regen_bonus"):
		stats.time_energy_regen += float(effects["time_energy_regen_bonus"])
	if effects.has("time_energy_regen_multiplier"):
		stats.time_energy_regen *= float(effects["time_energy_regen_multiplier"])
	if effects.has("time_stop_duration_bonus"):
		time_manager.time_stop_duration_bonus += float(effects["time_stop_duration_bonus"])
	if effects.has("time_stop_cost_multiplier"):
		time_manager.time_stop_cost_multiplier *= float(effects["time_stop_cost_multiplier"])
	if effects.has("time_stop_self_damage"):
		time_manager.time_stop_self_damage += float(effects["time_stop_self_damage"])
	if effects.has("rewind_cost_multiplier"):
		time_manager.rewind_cost_multiplier *= float(effects["rewind_cost_multiplier"])
	if effects.has("rewind_heal"):
		time_manager.rewind_heal += float(effects["rewind_heal"])
	if effects.has("rewind_self_damage"):
		time_manager.rewind_self_damage += float(effects["rewind_self_damage"])
	if effects.has("combo_finisher_multiplier_bonus"):
		sword_weapon.combo_finisher_multiplier_bonus += float(effects["combo_finisher_multiplier_bonus"])
	if effects.has("heavy_damage_multiplier_bonus"):
		sword_weapon.heavy_damage_multiplier_bonus += float(effects["heavy_damage_multiplier_bonus"])
	if effects.has("low_hp_damage_multiplier_bonus"):
		sword_weapon.low_hp_damage_multiplier_bonus += float(effects["low_hp_damage_multiplier_bonus"])
	if effects.has("dash_invulnerable_bonus"):
		_dash_invulnerable_bonus += float(effects["dash_invulnerable_bonus"])
	if effects.has("healing_multiplier"):
		health.healing_multiplier *= float(effects["healing_multiplier"])

	_apply_stats_to_components(false)

	if effects.has("heal"):
		health.heal(float(effects["heal"]))
	if effects.has("time_energy_restore"):
		time_manager.restore_energy(float(effects["time_energy_restore"]))
	if effects.has("invulnerable_duration"):
		health.apply_invulnerability(float(effects["invulnerable_duration"]))


func apply_knockback(knockback: Vector2) -> void:
	_knockback_velocity += knockback


func _on_damaged(_amount: float, _current_hp: float) -> void:
	visual.color = Color(1.0, 0.95, 0.85)
	var tween := create_tween()
	tween.tween_property(visual, "color", BASE_COLOR, 0.12)


func _apply_stats_to_components(reset_health: bool) -> void:
	if reset_health:
		health.configure_from_stats(stats)
	else:
		health.apply_stat_totals(stats)
	time_manager.configure_from_stats(stats)
	sword_weapon.base_attack = stats.attack
	sword_weapon.attack_speed = stats.attack_speed
