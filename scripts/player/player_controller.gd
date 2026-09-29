class_name PlayerController
extends CharacterBody2D

const StatsResource := preload("res://scripts/core/stats.gd")
const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")

const DEFAULT_LOADOUT_CONFIG := {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}

@export var stats: Resource

@onready var health: Node = $HealthComponent
@onready var loadout_runtime: Node = $PlayerLoadoutRuntime
@onready var sword_weapon: Node = $SwordWeapon
@onready var bow_weapon: Node = $BowWeapon
@onready var time_manager: Node = $TimeManager
@onready var rewind_recorder: Node = $RewindRecorder
@onready var visual: Polygon2D = $Visual

var _dash_cooldown_remaining: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _last_move_direction: Vector2 = Vector2.RIGHT
var _dash_invulnerable_bonus: float = 0.0
var _time_acceleration_multiplier: float = 1.0
var _time_acceleration_token: int = 0
var _time_acceleration_remaining: float = 0.0
var action_state = PlayerActionStateScript.new()
var _active_attack_definition: Dictionary = {}
var _combo_window_frames_remaining: int = 0
var _buffered_attack_heavy: bool = false
var _buffered_time_skill: StringName = &""
var _action_generation: int = 0

const DASH_DURATION := 0.28
const DASH_COOLDOWN := 0.45
const DASH_SPEED := 520.0
const DASH_INVULNERABLE_TIME := 0.20
const KNOCKBACK_DECAY := 12.0
const BASE_COLOR := Color(0.2, 0.85, 0.95)
const TIME_CAST_DURATION := 0.18
const HITSTUN_DURATION := 0.18
const TIME_CAST_MOVEMENT_MULTIPLIER := 0.35


func _ready() -> void:
	add_to_group("player")
	if stats == null:
		stats = StatsResource.new()
	_apply_stats_to_components(true)
	configure_loadout(DEFAULT_LOADOUT_CONFIG)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	advance_action_frame()
	_update_weapon_aim()
	_handle_attack_input()
	_handle_time_input()
	_handle_movement(delta)


func _update_timers(delta: float) -> void:
	_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)
	if _time_acceleration_remaining > 0.0:
		_time_acceleration_remaining = maxf(0.0, _time_acceleration_remaining - delta)
		if _time_acceleration_remaining <= 0.0:
			_clear_time_acceleration(_time_acceleration_token)


func _update_weapon_aim() -> void:
	var aim_direction := global_position.direction_to(get_global_mouse_position())
	if aim_direction.length_squared() > 0.001:
		sword_weapon.rotation = aim_direction.angle()
		bow_weapon.rotation = aim_direction.angle()


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		try_action(&"attack")
	if Input.is_action_just_pressed("heavy_attack"):
		try_action(&"heavy_attack")
	handle_ranged_input_for_test(
		Input.is_action_just_pressed("ranged_attack"),
		Input.is_action_just_released("ranged_attack")
	)


func handle_ranged_input_for_test(just_pressed: bool, just_released: bool) -> void:
	var mode := str(GameState.get_setting("ranged_charge_mode", "hold"))
	if mode == "toggle":
		if just_pressed:
			try_action(&"ranged_release" if bow_weapon.is_charging() else &"ranged_attack")
		return
	if just_pressed:
		try_action(&"ranged_attack")
	if just_released:
		try_action(&"ranged_release")


func _commit_ranged_input(action_id: StringName) -> bool:
	if not loadout_runtime.has_weapon(&"bow"):
		return false
	if action_state.current_state != PlayerActionStateScript.State.FREE:
		return false
	if action_id == &"ranged_attack":
		return bow_weapon.start_charge()
	if action_id == &"ranged_release":
		return bow_weapon.release_charge(Vector2.RIGHT.rotated(bow_weapon.global_rotation))
	return false


func _handle_time_input() -> void:
	if Input.is_action_just_pressed("time_stop"):
		try_action(&"time_stop")
	if Input.is_action_just_pressed("time_rewind"):
		try_action(&"time_rewind")
	if Input.is_action_just_pressed("time_rift"):
		try_action(&"time_rift")
	if Input.is_action_just_pressed("time_accelerate"):
		try_action(&"time_accelerate")


func _handle_movement(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.001:
		_last_move_direction = input_vector.normalized()

	if Input.is_action_just_pressed("dash"):
		try_action(&"dash")

	if action_state.current_state == PlayerActionStateScript.State.DASH:
		velocity = _dash_velocity + _knockback_velocity
	else:
		velocity = input_vector * stats.move_speed * _time_acceleration_multiplier * get_action_movement_multiplier() + _knockback_velocity
	move_and_slide()


func try_action(action_id: StringName) -> bool:
	if action_state.current_state == PlayerActionStateScript.State.DEAD:
		return false
	match action_id:
		&"attack":
			return loadout_runtime.has_weapon(&"sword") and _request_attack(false)
		&"heavy_attack":
			return loadout_runtime.has_weapon(&"sword") and _request_attack(true)
		&"ranged_attack", &"ranged_release":
			return _commit_ranged_input(action_id)
		&"dash":
			return _request_dash()
		&"time_stop":
			if not loadout_runtime.has_time_ability(&"stop"):
				return false
			return _request_time_skill(action_id)
		&"time_rewind":
			if not loadout_runtime.has_time_ability(&"rewind"):
				return false
			return _request_time_skill(action_id)
		&"time_rift", &"time_accelerate":
			return false
		_:
			return false


func configure_loadout(config: Dictionary) -> bool:
	if loadout_runtime == null or not loadout_runtime.configure(config):
		return false
	reset_runtime_state()
	return true


func reset_runtime_state() -> void:
	_action_generation += 1
	action_state.reset_runtime_state()
	_active_attack_definition.clear()
	_combo_window_frames_remaining = 0
	_buffered_attack_heavy = false
	_buffered_time_skill = &""
	_dash_cooldown_remaining = 0.0
	_dash_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_last_move_direction = Vector2.RIGHT
	sword_weapon.cancel_attack()
	sword_weapon.reset_combo()
	bow_weapon.reset_runtime_state()
	_time_acceleration_token += 1
	_time_acceleration_multiplier = 1.0
	_time_acceleration_remaining = 0.0
	_apply_stats_to_components(true)
	time_manager.reset_runtime_state()
	health.invulnerable = false
	if rewind_recorder.has_method("clear_snapshots"):
		rewind_recorder.clear_snapshots()


func advance_action_frame() -> void:
	if _combo_window_frames_remaining > 0:
		_combo_window_frames_remaining -= 1
		if _combo_window_frames_remaining == 0:
			sword_weapon.reset_combo()

	var previous_state: int = action_state.current_state
	action_state.advance_frame()
	if previous_state == PlayerActionStateScript.State.ATTACK_RECOVERY and action_state.current_state == PlayerActionStateScript.State.FREE:
		sword_weapon.finish_attack()
		_active_attack_definition.clear()

	if action_state.current_state == PlayerActionStateScript.State.ATTACK_WINDUP and action_state.is_state_complete():
		_enter_attack_active()
	elif action_state.current_state == PlayerActionStateScript.State.ATTACK_ACTIVE and action_state.is_state_complete():
		_enter_attack_recovery()

	_consume_buffered_action()


func get_action_movement_multiplier() -> float:
	match action_state.current_state:
		PlayerActionStateScript.State.ATTACK_WINDUP, PlayerActionStateScript.State.ATTACK_ACTIVE, PlayerActionStateScript.State.ATTACK_RECOVERY:
			return float(_active_attack_definition.get("movement_multiplier", 1.0))
		PlayerActionStateScript.State.DASH:
			return DASH_SPEED / maxf(1.0, float(stats.move_speed))
		PlayerActionStateScript.State.TIME_CAST:
			return TIME_CAST_MOVEMENT_MULTIPLIER
		PlayerActionStateScript.State.HITSTUN, PlayerActionStateScript.State.DEAD:
			return 0.0
		_:
			return 1.0


func apply_hitstun_frames(duration_frames: int) -> bool:
	if duration_frames <= 0 or action_state.current_state == PlayerActionStateScript.State.DEAD:
		return false
	if not action_state.transition_to(PlayerActionStateScript.State.HITSTUN, duration_frames):
		return false
	action_state.clear_buffered_inputs()
	_clear_transient_effects()
	return true


func cancel_transient_actions() -> void:
	_action_generation += 1
	action_state.clear_buffered_inputs()
	action_state.force_safe_reset()
	_combo_window_frames_remaining = 0
	sword_weapon.reset_combo()
	_clear_transient_effects()


func get_rewind_safe_action_state() -> Dictionary:
	return {"action_state": "FREE"}


func restore_rewind_safe_action_state(state: Dictionary) -> bool:
	if action_state.current_state == PlayerActionStateScript.State.DEAD or health.dead:
		return false
	if str(state.get("action_state", "FREE")) != "FREE":
		return false
	_active_attack_definition.clear()
	_combo_window_frames_remaining = 0
	sword_weapon.reset_combo()
	_dash_velocity = Vector2.ZERO
	_buffered_attack_heavy = false
	_buffered_time_skill = &""
	return action_state.force_safe_reset()


func get_rewind_facing() -> Vector2:
	return _last_move_direction


func restore_rewind_facing(facing: Vector2) -> void:
	if facing.length_squared() > 0.001:
		_last_move_direction = facing.normalized()


func get_player_ui_snapshot() -> Dictionary:
	var state_name := str(PlayerActionStateScript.State.keys()[action_state.current_state])
	return {
		"hp": clampf(float(health.current_hp), 0.0, float(health.max_hp)),
		"max_hp": maxf(1.0, float(health.max_hp)),
		"energy": clampf(float(time_manager.energy), 0.0, float(time_manager.max_energy)),
		"max_energy": maxf(1.0, float(time_manager.max_energy)),
		"action_state": state_name,
		"cooldowns": {
			"time_stop": maxf(0.0, time_manager.get_cooldown(&"time_stop")),
			"time_rewind": maxf(0.0, time_manager.get_cooldown(&"time_rewind")),
		},
	}


func _request_attack(heavy: bool) -> bool:
	if action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP):
		return _begin_attack(heavy)
	if _can_buffer_committed_action():
		_buffered_attack_heavy = heavy
		action_state.buffer_input(&"combo", PlayerActionStateScript.COMBO_BUFFER_FRAMES)
		return true
	return false


func _begin_attack(heavy: bool) -> bool:
	if not action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP):
		return false
	if action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY:
		sword_weapon.cancel_attack()
		_active_attack_definition.clear()
	var definition: Dictionary = sword_weapon.attack_definition(heavy)
	if not action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, int(definition["windup_frames"])):
		return false
	var committed: Dictionary = sword_weapon.begin_attack(heavy)
	if committed.is_empty():
		action_state.force_safe_reset()
		return false
	_active_attack_definition = committed
	_combo_window_frames_remaining = int(committed["combo_reset_frames"])
	return true


func _enter_attack_active() -> void:
	if _active_attack_definition.is_empty():
		cancel_transient_actions()
		return
	if not action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, int(_active_attack_definition["active_frames"])):
		return
	if not sword_weapon.enter_active_phase():
		cancel_transient_actions()


func _enter_attack_recovery() -> void:
	sword_weapon.leave_active_phase()
	action_state.transition_to(
		PlayerActionStateScript.State.ATTACK_RECOVERY,
		int(_active_attack_definition["recovery_frames"]),
		int(_active_attack_definition["recovery_cancel_frame"])
	)


func _request_dash() -> bool:
	if action_state.can_transition_to(PlayerActionStateScript.State.DASH):
		return _begin_dash()
	if _can_buffer_committed_action():
		action_state.buffer_input(&"dash", PlayerActionStateScript.COMBO_BUFFER_FRAMES)
		return true
	return false


func _begin_dash() -> bool:
	if _dash_cooldown_remaining > 0.0 or not action_state.can_transition_to(PlayerActionStateScript.State.DASH):
		return false
	if action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY:
		sword_weapon.cancel_attack()
		_active_attack_definition.clear()
	if not action_state.transition_to(PlayerActionStateScript.State.DASH, _seconds_to_frames(DASH_DURATION)):
		return false
	_dash_cooldown_remaining = DASH_COOLDOWN
	_dash_velocity = _last_move_direction * DASH_SPEED
	health.apply_invulnerability(DASH_INVULNERABLE_TIME + _dash_invulnerable_bonus)
	EventBus.player_dashed.emit({})
	return true


func _request_time_skill(skill_id: StringName) -> bool:
	if action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST):
		return _begin_time_skill(skill_id)
	if _can_buffer_committed_action():
		_buffered_time_skill = skill_id
		action_state.buffer_input(&"time_cast", PlayerActionStateScript.COMBO_BUFFER_FRAMES)
		return true
	return false


func _begin_time_skill(skill_id: StringName) -> bool:
	if not action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST):
		return false
	if skill_id == &"time_stop" and not time_manager.can_time_stop():
		return false
	if skill_id == &"time_rewind" and not time_manager.can_rewind(rewind_recorder):
		return false
	if action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY:
		sword_weapon.cancel_attack()
		_active_attack_definition.clear()
	if not action_state.transition_to(PlayerActionStateScript.State.TIME_CAST, _seconds_to_frames(TIME_CAST_DURATION)):
		return false
	var committed: bool = time_manager.try_time_stop() if skill_id == &"time_stop" else time_manager.try_rewind(rewind_recorder)
	if not committed and action_state.current_state == PlayerActionStateScript.State.TIME_CAST:
		action_state.force_safe_reset()
	return committed


func _consume_buffered_action() -> void:
	var buffered_action := action_state.consume_highest_priority_buffered_input()
	match buffered_action:
		&"dash":
			_begin_dash()
		&"time_cast":
			var skill_id := _buffered_time_skill
			_buffered_time_skill = &""
			_begin_time_skill(skill_id)
		&"combo", &"attack":
			var heavy := _buffered_attack_heavy
			_buffered_attack_heavy = false
			_begin_attack(heavy)


func _can_buffer_committed_action() -> bool:
	return action_state.current_state in [
		PlayerActionStateScript.State.ATTACK_WINDUP,
		PlayerActionStateScript.State.ATTACK_ACTIVE,
		PlayerActionStateScript.State.ATTACK_RECOVERY,
	]


func _clear_transient_effects() -> void:
	sword_weapon.cancel_attack()
	_active_attack_definition.clear()
	_dash_velocity = Vector2.ZERO
	_buffered_attack_heavy = false
	_buffered_time_skill = &""
	if bow_weapon.has_method("cancel_charge"):
		bow_weapon.cancel_charge()


func _seconds_to_frames(seconds: float) -> int:
	return maxi(1, ceili(seconds * Engine.physics_ticks_per_second))


func apply_reward(reward_data: Dictionary) -> void:
	var effects: Dictionary = reward_data.get("effects", {})
	_apply_effects(effects)


func apply_curse(curse_data: Dictionary) -> void:
	var effects: Dictionary = curse_data.get("effects", {})
	_apply_effects(effects)


func _apply_effects(effects: Dictionary) -> void:
	ItemEffectScript.apply_to_player(self, effects)


func apply_knockback(knockback: Vector2) -> void:
	_knockback_velocity += knockback


func apply_time_acceleration(multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_time_acceleration_token += 1
	_time_acceleration_multiplier = maxf(1.0, multiplier)
	_time_acceleration_remaining = duration
	_apply_stats_to_components(false)


func _clear_time_acceleration(token: int) -> void:
	if token != _time_acceleration_token:
		return
	_time_acceleration_multiplier = 1.0
	_time_acceleration_remaining = 0.0
	_apply_stats_to_components(false)


func is_time_accelerated() -> bool:
	return _time_acceleration_multiplier > 1.0


func _on_damaged(_amount: float, _current_hp: float) -> void:
	visual.color = Color(1.0, 0.95, 0.85)
	var tween := create_tween()
	tween.tween_property(visual, "color", BASE_COLOR, 0.12)
	if health.current_hp > 0.0:
		apply_hitstun_frames(_seconds_to_frames(HITSTUN_DURATION))


func _on_died(_killer: Variant) -> void:
	if action_state.transition_to(PlayerActionStateScript.State.DEAD, 0):
		action_state.clear_buffered_inputs()
		_clear_transient_effects()


func _apply_stats_to_components(reset_health: bool) -> void:
	if reset_health:
		health.configure_from_stats(stats)
	else:
		health.apply_stat_totals(stats)
	time_manager.configure_from_stats(stats)
	sword_weapon.base_attack = stats.attack
	sword_weapon.attack_speed = stats.attack_speed * _time_acceleration_multiplier
	bow_weapon.base_attack = stats.attack
	bow_weapon.attack_speed = stats.attack_speed * _time_acceleration_multiplier
