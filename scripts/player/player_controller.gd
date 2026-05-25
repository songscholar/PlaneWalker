class_name PlayerController
extends CharacterBody2D

@export var stats: Stats

@onready var health: HealthComponent = $HealthComponent
@onready var sword_weapon: SwordWeapon = $SwordWeapon

var _dash_time_remaining: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _last_move_direction: Vector2 = Vector2.RIGHT

const DASH_DURATION := 0.28
const DASH_COOLDOWN := 0.45
const DASH_SPEED := 520.0
const DASH_INVULNERABLE_TIME := 0.20


func _ready() -> void:
	add_to_group("player")
	if stats == null:
		stats = Stats.new()
	health.configure_from_stats(stats)
	sword_weapon.base_attack = stats.attack


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_weapon_aim()
	_handle_attack_input()
	_handle_movement(delta)


func _update_timers(delta: float) -> void:
	_dash_time_remaining = maxf(0.0, _dash_time_remaining - delta)
	_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)


func _update_weapon_aim() -> void:
	var aim_direction := global_position.direction_to(get_global_mouse_position())
	if aim_direction.length_squared() > 0.001:
		sword_weapon.rotation = aim_direction.angle()


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		sword_weapon.try_attack(false)
	if Input.is_action_just_pressed("heavy_attack"):
		sword_weapon.try_attack(true)


func _handle_movement(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.001:
		_last_move_direction = input_vector.normalized()

	if Input.is_action_just_pressed("dash") and _dash_cooldown_remaining <= 0.0:
		_start_dash()

	if _dash_time_remaining > 0.0:
		velocity = _dash_velocity
	else:
		velocity = input_vector * stats.move_speed
	move_and_slide()


func _start_dash() -> void:
	_dash_time_remaining = DASH_DURATION
	_dash_cooldown_remaining = DASH_COOLDOWN
	_dash_velocity = _last_move_direction * DASH_SPEED
	health.apply_invulnerability(DASH_INVULNERABLE_TIME)
	EventBus.player_dashed.emit()
	EventBus.publish(EventBus.PLAYER_DASHED)
