class_name PlayerController
extends CharacterBody2D

const StatsResource := preload("res://scripts/core/stats.gd")
const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerLoadoutRuntimeScript := preload("res://scripts/player/player_loadout_runtime.gd")
const BowWeaponRuntimeScript := preload("res://scripts/combat/weapons/bow_weapon_runtime.gd")
const GauntletsWeaponRuntimeScript := preload("res://scripts/combat/weapons/gauntlets_weapon_runtime.gd")
const GunWeaponRuntimeScript := preload("res://scripts/combat/weapons/gun_weapon_runtime.gd")
const StaffWeaponRuntimeScript := preload("res://scripts/combat/weapons/staff_weapon_runtime.gd")
const SwordWeaponRuntimeScript := preload("res://scripts/combat/weapons/sword_weapon_runtime.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponIntentRouterScript := preload("res://scripts/input/weapon_intent_router.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponResourceTransactionScript := preload("res://scripts/combat/weapons/weapon_resource_transaction.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const DEFAULT_LOADOUT_CONFIG := {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}
const WEAPON_PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const WEAPON_MODIFIER_BOUNDS := {
	"weapon.ammo_capacity": {"minimum": 0.0, "maximum": 20.0},
	"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
	"weapon.charge_rate": {"minimum": 0.0, "maximum": 6.0},
	"weapon.combo_timeout": {"minimum": 0.25, "maximum": 4.0},
	"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.full_charge_damage": {"minimum": 0.0, "maximum": 11.0},
	"weapon.mana_max": {"minimum": 0.0, "maximum": 300.0},
	"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
	"weapon.reload_window": {"minimum": 0.0, "maximum": 10.0},
	"weapon.status_duration": {"minimum": 0.0, "maximum": 10.0},
}

@export var stats: Resource

@onready var health: Node = $HealthComponent
@onready var loadout_runtime: Node = $PlayerLoadoutRuntime
@onready var sword_weapon: Node = $SwordWeapon
@onready var bow_weapon: Node = $BowWeapon
@onready var gauntlets_weapon: Node = $GauntletsWeapon
@onready var gun_weapon: Node = $GunWeapon
@onready var staff_weapon: Node = $StaffWeapon
@onready var time_manager: Node = $TimeManager
@onready var rewind_recorder: Node = $RewindRecorder
@onready var visual: Polygon2D = $Visual

var _dash_cooldown_remaining: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _last_move_direction: Vector2 = Vector2.RIGHT
var _dash_invulnerable_bonus: float = 0.0
var _runtime_frame: int = 0
var _dash_completion_token: int = 0
var _dash_completed_at_runtime_frame: int = -1
var _dash_direction: Vector2 = Vector2.RIGHT
var _time_acceleration_multiplier: float = 1.0
var _time_acceleration_token: int = 0
var _time_acceleration_remaining: float = 0.0
var action_state = PlayerActionStateScript.new()
var weapon_action_coordinator: RefCounted
var weapon_runtime: RefCounted
var weapon_runtime_profile: RefCounted
var weapon_modifier_state: RefCounted
var _weapon_combo_timeout_frames: int = 0
var _weapon_profile_compatibility_fallback: bool = false
var _buffered_time_skill: StringName = &""
var _weapon_action_reward_claims: Dictionary = {}
var _weapon_action_ids_by_token: Dictionary = {}
var _weapon_action_generations_by_token: Dictionary = {}
var _weapon_action_token_order: Array[int] = []
var _weapon_hit_fact_claims: Dictionary = {}
var _weapon_resource_fact_state: Dictionary = {}
var _next_weapon_action_token_floor: int = 1
var _weapon_intent_router: RefCounted = WeaponIntentRouterScript.new()

const DASH_DURATION := 0.28
const DASH_COOLDOWN := 0.45
const DASH_SPEED := 520.0
const DASH_INVULNERABLE_TIME := 0.20
const KNOCKBACK_DECAY := 12.0
const BASE_COLOR := Color(0.2, 0.85, 0.95)
const TIME_CAST_DURATION := 0.18
const HITSTUN_DURATION := 0.18
const TIME_CAST_MOVEMENT_MULTIPLIER := 0.35
const BOW_TARGET_DISTANCE_PIXELS := 8.0 * 64.0
const GUN_BASE_ATTACK := 15.0
const GUN_ATTACK_SPEED := 0.9
const GAUNTLETS_BASE_ATTACK := 6.0
const GAUNTLETS_ATTACK_SPEED := 1.4
const STAFF_BASE_ATTACK := 9.0
const MAX_TRACKED_WEAPON_FACT_TOKENS := 256
const RIGHT_STICK_AIM_DEADZONE := 0.25
const GAUNTLETS_COUNTER_WINDOW_LAST_FRAME := 8


func _ready() -> void:
	add_to_group("player")
	if stats == null:
		stats = StatsResource.new()
	_apply_stats_to_components(true)
	configure_loadout(DEFAULT_LOADOUT_CONFIG)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if not gun_weapon.action_hit_confirmed.is_connected(_on_gun_action_hit_confirmed):
		gun_weapon.action_hit_confirmed.connect(_on_gun_action_hit_confirmed)
	if not gun_weapon.resource_reward_requested.is_connected(_on_gun_resource_reward_requested):
		gun_weapon.resource_reward_requested.connect(_on_gun_resource_reward_requested)
	if not staff_weapon.payload_result_reported.is_connected(_on_staff_payload_result_reported):
		staff_weapon.payload_result_reported.connect(_on_staff_payload_result_reported)
	if not staff_weapon.resource_reward_requested.is_connected(_on_staff_resource_reward_requested):
		staff_weapon.resource_reward_requested.connect(_on_staff_resource_reward_requested)
	if (
		gauntlets_weapon.has_signal("impact_feedback_requested")
		and not gauntlets_weapon.impact_feedback_requested.is_connected(_on_gauntlets_impact_feedback_requested)
	):
		gauntlets_weapon.impact_feedback_requested.connect(_on_gauntlets_impact_feedback_requested)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	advance_action_frame()
	_update_weapon_aim()
	_handle_priority_action_input()
	_handle_movement(delta)


func _update_timers(delta: float) -> void:
	_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)


func _update_weapon_aim() -> void:
	var aim_direction := _resolve_weapon_aim_direction(
		_right_stick_aim_direction(),
		global_position.direction_to(get_global_mouse_position())
	)
	_apply_weapon_aim_direction(aim_direction)


func _right_stick_aim_direction() -> Vector2:
	for device_id: int in Input.get_connected_joypads():
		var direction := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		)
		if direction.length_squared() > RIGHT_STICK_AIM_DEADZONE * RIGHT_STICK_AIM_DEADZONE:
			return direction
	return Vector2.ZERO


func _resolve_weapon_aim_direction(
	right_stick_direction: Vector2,
	mouse_direction: Vector2
) -> Vector2:
	if (
		right_stick_direction.length_squared()
		> RIGHT_STICK_AIM_DEADZONE * RIGHT_STICK_AIM_DEADZONE
	):
		return right_stick_direction.normalized()
	if mouse_direction.length_squared() > 0.001:
		return mouse_direction.normalized()
	if _last_move_direction.length_squared() > 0.001:
		return _last_move_direction.normalized()
	return Vector2.RIGHT


func _apply_weapon_aim_direction(direction: Vector2) -> void:
	if direction.length_squared() <= 0.001:
		return
	var rotation_value := direction.angle()
	sword_weapon.rotation = rotation_value
	bow_weapon.rotation = rotation_value
	gauntlets_weapon.rotation = rotation_value
	gun_weapon.rotation = rotation_value
	staff_weapon.rotation = rotation_value


func _handle_priority_action_input() -> void:
	var time_actions: Array[StringName] = []
	for slot_action: StringName in [&"time_slot_1", &"time_slot_2"]:
		if Input.is_action_just_pressed(slot_action):
			time_actions.append(slot_action)
	for action_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		if Input.is_action_just_pressed(action_id):
			var canonical_id: StringName = time_manager.canonical_skill_id(action_id)
			var duplicate := false
			for queued_action: StringName in time_actions:
				if _canonical_time_action_id(queued_action) == canonical_id:
					duplicate = true
					break
			if not duplicate:
				time_actions.append(action_id)
	if _submit_priority_action_edges(
		Input.is_action_just_pressed("dash"),
		time_actions,
		[]
	):
		return
	var weapon_intents := _collect_weapon_input_intents()
	for index: int in range(weapon_intents.size()):
		var intent: Dictionary = weapon_intents[index]
		if _submit_normalized_weapon_intent(intent):
			for pending_index: int in range(index + 1, weapon_intents.size()):
				_reset_weapon_intent_latch(weapon_intents[pending_index])
			return


func _submit_priority_action_edges(
	dash_pressed: bool,
	time_actions: Array[StringName],
	weapon_actions: Array[StringName]
) -> bool:
	if dash_pressed and try_action(&"dash"):
		return true
	for action_id: StringName in time_actions:
		if try_action(action_id):
			return true
	for action_id: StringName in weapon_actions:
		if try_action(action_id):
			return true
	return false


func handle_ranged_input_for_test(just_pressed: bool, just_released: bool) -> void:
	var mode := str(GameState.get_setting("ranged_charge_mode", "hold"))
	if just_pressed:
		var pressed: Dictionary = _weapon_intent_router.call(
			"normalize_edge",
			&"ranged_attack",
			&"pressed",
			_current_weapon_hold_frames(),
			StringName(mode)
		)
		if not pressed.is_empty():
			_submit_normalized_weapon_intent(pressed)
	if just_released:
		var released: Dictionary = _weapon_intent_router.call(
			"normalize_edge",
			&"ranged_attack",
			&"released",
			_current_weapon_hold_frames(),
			StringName(mode)
		)
		if not released.is_empty():
			_submit_normalized_weapon_intent(released)


func _commit_ranged_input(action_id: StringName) -> bool:
	if not loadout_runtime.has_weapon(&"bow") or weapon_action_coordinator == null:
		return false
	if action_id == &"ranged_attack":
		return _submit_weapon_intent(&"weapon_primary", &"pressed")
	if action_id == &"ranged_release":
		return _submit_weapon_intent(&"weapon_primary", &"released")
	return false


func _handle_movement(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.001:
		_last_move_direction = input_vector.normalized()

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
			return loadout_runtime.has_weapon(&"sword") and _submit_weapon_intent(&"weapon_primary")
		&"heavy_attack":
			return _submit_weapon_intent(&"weapon_secondary")
		&"ranged_attack", &"ranged_release":
			return _commit_ranged_input(action_id)
		&"weapon_primary", &"weapon_secondary", &"weapon_utility", &"weapon_skill", &"weapon_ultimate":
			return _submit_weapon_intent(action_id)
		&"dash":
			return _request_dash()
		&"time_slot_1", &"time_slot_2":
			var slotted_action_id := _time_slot_action_id(action_id)
			if slotted_action_id == &"":
				return false
			return _request_time_skill(slotted_action_id)
		&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate":
			var canonical_id: StringName = time_manager.canonical_skill_id(action_id)
			if canonical_id == &"" or not loadout_runtime.has_time_ability(canonical_id):
				return false
			return _request_time_skill(action_id)
		_:
			return false


func configure_loadout(config: Dictionary) -> bool:
	if loadout_runtime == null:
		return false
	_capture_next_weapon_action_token_floor()
	var next_config := config.duplicate(true)
	var next_weapon_id := StringName(str(next_config.get("weapon_id", "")))
	var explicit_weapon_profile := next_config.has("weapon_profile")
	var used_compatibility_profile := false
	if explicit_weapon_profile:
		var profile_value: Variant = next_config.get("weapon_profile")
		if not profile_value is Dictionary:
			return false
		var supplied_profile := profile_value as Dictionary
		var authoritative_profile := _weapon_profile_catalog_definition(
			StringName(str(supplied_profile.get("id", "")))
		)
		var canonical_supplied := _canonical_weapon_profile(supplied_profile)
		var canonical_authoritative := _canonical_weapon_profile(authoritative_profile)
		if (
			canonical_authoritative.is_empty()
			or canonical_supplied != canonical_authoritative
		):
			return false
		next_config["weapon_profile"] = authoritative_profile.duplicate(true)
	if next_weapon_id in [&"sword", &"bow", &"staff", &"gauntlets"] and not next_config.has("weapon_profile"):
		var default_profile := _weapon_profile_definition(next_weapon_id)
		if default_profile.is_empty():
			return false
		next_config["weapon_profile"] = default_profile
		used_compatibility_profile = true
	if (
		(explicit_weapon_profile or next_weapon_id in [&"bow", &"staff", &"gauntlets"])
		and next_config.has("weapon_profile")
		and not _profile_allows_milestone(next_config)
	):
		return false

	var validator = PlayerLoadoutRuntimeScript.new()
	var loadout_is_valid := validator.configure(next_config)
	validator.free()
	if not loadout_is_valid:
		return false

	var assembly := _assemble_weapon_runtime(next_config)
	if not bool(assembly.get("ok", false)):
		return false
	var loadout_before: Dictionary = (
		(loadout_runtime.call("snapshot") as Dictionary).duplicate(true)
		if loadout_runtime.has_method("snapshot")
		else {}
	)
	if not loadout_runtime.configure(next_config):
		return false
	var assembled_runtime := assembly.get("runtime") as RefCounted
	if (
		bool(assembly.get("requires_adapter_activation", false))
		and (
			assembled_runtime == null
			or not assembled_runtime.has_method("activate_adapter")
			or not bool(assembled_runtime.call("activate_adapter"))
		)
	):
		if not loadout_before.is_empty():
			loadout_runtime.configure(loadout_before)
		return false

	_disconnect_weapon_coordinator()
	weapon_runtime_profile = assembly.get("profile") as RefCounted
	weapon_modifier_state = assembly.get("modifiers") as RefCounted
	weapon_runtime = assembly.get("runtime") as RefCounted
	weapon_action_coordinator = assembly.get("coordinator") as RefCounted
	_weapon_profile_compatibility_fallback = used_compatibility_profile
	_connect_weapon_coordinator()
	reset_runtime_state()
	return true


func reset_runtime_state() -> void:
	action_state.reset_runtime_state()
	_weapon_combo_timeout_frames = 0
	_weapon_action_reward_claims.clear()
	_weapon_action_ids_by_token.clear()
	_weapon_action_generations_by_token.clear()
	_weapon_action_token_order.clear()
	_weapon_hit_fact_claims.clear()
	_weapon_resource_fact_state.clear()
	_weapon_intent_router.call("reset_all")
	_buffered_time_skill = &""
	_dash_cooldown_remaining = 0.0
	_dash_velocity = Vector2.ZERO
	_runtime_frame = 0
	_dash_completion_token = 0
	_dash_completed_at_runtime_frame = -1
	_dash_direction = Vector2.RIGHT
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_last_move_direction = Vector2.RIGHT
	if weapon_action_coordinator != null:
		weapon_action_coordinator.reset_runtime_state(&"player_runtime_reset")
	else:
		sword_weapon.cancel_attack()
		sword_weapon.reset_combo()
	bow_weapon.reset_runtime_state()
	gauntlets_weapon.reset_runtime_state()
	gun_weapon.reset_runtime_state()
	staff_weapon.reset_runtime_state()
	_sync_weapon_resource_facts(&"runtime_reset")
	_clear_owned_player_arrows()
	_clear_owned_player_projectiles()
	time_manager.reset_runtime_state()
	_force_clear_time_acceleration()
	_apply_stats_to_components(true)
	health.invulnerable = false
	if rewind_recorder.has_method("clear_snapshots"):
		rewind_recorder.clear_snapshots()


func advance_action_frame() -> void:
	_runtime_frame += 1
	if _weapon_combo_timeout_frames > 0:
		_weapon_combo_timeout_frames -= 1
		if _weapon_combo_timeout_frames == 0 and weapon_runtime != null and weapon_runtime.has_method("reset_combo"):
			weapon_runtime.call("reset_combo")

	var previous_action_state: int = action_state.current_state
	action_state.advance_frame()
	if (
		previous_action_state == PlayerActionStateScript.State.DASH
		and action_state.current_state == PlayerActionStateScript.State.FREE
	):
		_dash_completion_token += 1
		_dash_completed_at_runtime_frame = _runtime_frame
	if weapon_action_coordinator != null:
		var held_semantic := _active_hold_semantic_action()
		if held_semantic != &"" and weapon_action_coordinator.has_method("update_live_context"):
			weapon_action_coordinator.update_live_context(_weapon_submission_context())
		weapon_action_coordinator.advance_frame(false)
		if held_semantic != &"" and weapon_action_coordinator.phase_name() != &"HOLD":
			_weapon_intent_router.call("reset_action", held_semantic)
		_sync_weapon_action_projection()
		_sync_weapon_resource_facts(&"runtime_frame")

	var external_action_consumed := _consume_buffered_action()
	if (
		not external_action_consumed
		and weapon_action_coordinator != null
		and weapon_action_coordinator.consume_buffered_intent()
	):
		_sync_weapon_action_projection()


func get_action_movement_multiplier() -> float:
	if weapon_action_coordinator != null and weapon_action_coordinator.phase_name() != &"READY":
		return weapon_action_coordinator.movement_multiplier()
	match action_state.current_state:
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
	action_state.clear_buffered_inputs()
	action_state.force_safe_reset()
	_weapon_combo_timeout_frames = 0
	_clear_transient_effects()
	_clear_owned_player_arrows()
	_clear_owned_player_projectiles()
	_clear_owned_staff_payloads()
	_clear_owned_gauntlets_payloads()
	if weapon_runtime != null and weapon_runtime.has_method("reset_combo"):
		weapon_runtime.call("reset_combo")


func cancel_active_time_effects(reason: StringName = &"player_cancel") -> void:
	if time_manager != null and time_manager.has_method("cancel_all_time_effects"):
		time_manager.cancel_all_time_effects(reason)


func get_rewind_safe_action_state() -> Dictionary:
	return {"action_state": "FREE"}


func restore_rewind_safe_action_state(state: Dictionary) -> bool:
	if action_state.current_state == PlayerActionStateScript.State.DEAD or health.dead:
		return false
	if str(state.get("action_state", "FREE")) != "FREE":
		return false
	_weapon_combo_timeout_frames = 0
	if weapon_action_coordinator != null:
		weapon_action_coordinator.restore_rewind_safe_state(&"rewind_restore")
	else:
		sword_weapon.cancel_attack()
		sword_weapon.reset_combo()
	_dash_velocity = Vector2.ZERO
	_buffered_time_skill = &""
	_weapon_intent_router.call("reset_all")
	_clear_owned_player_arrows()
	_clear_owned_player_projectiles()
	_clear_owned_staff_payloads()
	_clear_owned_gauntlets_payloads()
	return action_state.force_safe_reset()


func get_rewind_facing() -> Vector2:
	return _last_move_direction


func restore_rewind_facing(facing: Vector2) -> void:
	if facing.length_squared() > 0.001:
		_last_move_direction = facing.normalized()


func get_player_ui_snapshot() -> Dictionary:
	var state_name := str(PlayerActionStateScript.State.keys()[action_state.current_state])
	var time_slots: Array[Dictionary] = []
	for raw_ability_id: Variant in loadout_runtime.time_ability_ids():
		var ability_id := StringName(str(raw_ability_id))
		var action_id: StringName = time_manager.action_skill_id(ability_id)
		time_slots.append({
			"ability_id": str(ability_id),
			"action_id": str(action_id),
			"cooldown": maxf(0.0, time_manager.get_cooldown(action_id)),
		})
	return {
		"hp": clampf(float(health.current_hp), 0.0, float(health.max_hp)),
		"max_hp": maxf(1.0, float(health.max_hp)),
		"energy": clampf(float(time_manager.energy), 0.0, float(time_manager.max_energy)),
		"max_energy": maxf(1.0, float(time_manager.max_energy)),
		"action_state": state_name,
		"weapon": weapon_presentation_snapshot(),
		"time_slots": time_slots.duplicate(true),
	}


func weapon_presentation_snapshot() -> Dictionary:
	var result: Dictionary = {
		"weapon_id": str(loadout_runtime.weapon_id()) if loadout_runtime != null else "",
		"action_id": "",
		"phase": "READY",
		"phase_frame": 0,
		"phase_duration_frames": 0,
		"cancel_from_frame": -1,
		"movement_multiplier": 1.0,
		"token": 0,
		"generation": 0,
		"runtime": {},
	}
	if weapon_action_coordinator != null:
		result = weapon_action_coordinator.presentation_snapshot()
	if loadout_runtime != null and loadout_runtime.has_weapon(&"gauntlets"):
		var runtime_value: Variant = result.get("runtime", {})
		if runtime_value is Dictionary:
			var runtime_presentation := (runtime_value as Dictionary).duplicate(true)
			runtime_presentation["counter_ready"] = _gauntlets_counter_window_is_open()
			result["runtime"] = runtime_presentation
	var profile_snapshot: Dictionary = (
		loadout_runtime.weapon_profile_snapshot()
		if loadout_runtime != null and loadout_runtime.has_method("weapon_profile_snapshot")
		else {}
	)
	result["profile_id"] = str(profile_snapshot.get("id", ""))
	result["profile_version"] = int(profile_snapshot.get("profile_version", 0))
	result["compatibility_profile_fallback"] = _weapon_profile_compatibility_fallback
	return result.duplicate(true)


func apply_weapon_modifier(capability: StringName, value: Variant) -> bool:
	if weapon_runtime == null or not weapon_runtime.has_method("apply_modifier"):
		return false
	return bool(weapon_runtime.call("apply_modifier", capability, value))


func apply_weapon_modifier_bonus(
	capability: StringName,
	value: Variant,
	base_value: float,
	required_weapon_id: StringName = &""
) -> bool:
	if (
		required_weapon_id != &""
		and (
			loadout_runtime == null
			or not loadout_runtime.has_method("has_weapon")
			or not bool(loadout_runtime.call("has_weapon", required_weapon_id))
		)
	):
		return false
	if weapon_modifier_state == null or not weapon_modifier_state.has_method("apply_additive"):
		return false
	return bool(weapon_modifier_state.call("apply_additive", capability, value, base_value))


func claim_weapon_action_reward(token: int, reward_kind: StringName) -> bool:
	if token <= 0 or reward_kind == &"":
		return false
	if weapon_runtime != null and weapon_runtime.has_method("claim_action_reward"):
		var runtime_result: Variant = weapon_runtime.call("claim_action_reward", token, reward_kind)
		return runtime_result is Dictionary and bool((runtime_result as Dictionary).get("ok", false))
	var key := "%d:%s" % [token, str(reward_kind)]
	if _weapon_action_reward_claims.has(key):
		return false
	_weapon_action_reward_claims[key] = true
	return true


func weapon_time_interaction_context() -> Dictionary:
	if time_manager == null or not time_manager.has_method("weapon_interaction_context"):
		return {}
	var context_value: Variant = time_manager.call("weapon_interaction_context")
	return (context_value as Dictionary).duplicate(true) if context_value is Dictionary else {}


func claim_weapon_time_interaction(interaction_id: StringName, generation: int) -> bool:
	if time_manager == null or not time_manager.has_method("claim_weapon_interaction"):
		return false
	return bool(time_manager.call("claim_weapon_interaction", interaction_id, generation))


func extend_weapon_time_stop(action_token: int, extension_frames: int) -> bool:
	if time_manager == null or not time_manager.has_method("extend_stop_for_weapon"):
		return false
	return bool(time_manager.call("extend_stop_for_weapon", action_token, extension_frames))


func apply_weapon_effect(effect_id: StringName, value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return false
	var numeric := float(value)
	match effect_id:
		&"combo_finisher_multiplier_bonus":
			sword_weapon.combo_finisher_multiplier_bonus += numeric
		&"heavy_damage_multiplier_bonus":
			sword_weapon.heavy_damage_multiplier_bonus += numeric
		&"heavy_execute_multiplier_bonus":
			sword_weapon.heavy_execute_multiplier_bonus += numeric
		&"heavy_execute_threshold":
			sword_weapon.heavy_execute_threshold = numeric
		&"low_hp_damage_multiplier_bonus":
			sword_weapon.low_hp_damage_multiplier_bonus += numeric
		_:
			return false
	return true


func _submit_weapon_intent(
	semantic_action: StringName,
	edge: StringName = &"pressed"
) -> bool:
	var intent: Dictionary = _weapon_intent_router.call(
		"normalize_edge",
		semantic_action,
		edge,
		_current_weapon_hold_frames(),
		_weapon_semantic_input_mode(semantic_action)
	)
	if intent.is_empty():
		return false
	return _submit_normalized_weapon_intent(intent)


func _submit_normalized_weapon_intent(intent: Dictionary) -> bool:
	if weapon_action_coordinator == null:
		_reset_weapon_intent_latch(intent)
		return false
	if action_state.current_state in [
		PlayerActionStateScript.State.DASH,
		PlayerActionStateScript.State.TIME_CAST,
		PlayerActionStateScript.State.HITSTUN,
		PlayerActionStateScript.State.DEAD,
	]:
		_reset_weapon_intent_latch(intent)
		return false
	var submitted_intent := intent.duplicate(true)
	submitted_intent["buffer_frames"] = int(submitted_intent.get(
		"buffer_frames",
		PlayerActionStateScript.COMBO_BUFFER_FRAMES
	))
	var result: Dictionary = weapon_action_coordinator.submit_intent(
		submitted_intent,
		_weapon_submission_context()
	)
	_sync_weapon_action_projection()
	_sync_weapon_resource_facts(&"intent_commit")
	if not bool(result.get("ok", false)):
		_reset_weapon_intent_latch(intent)
		return false
	return true


func _reset_weapon_intent_latch(intent: Dictionary) -> void:
	var semantic_action := StringName(str(intent.get("id", "")))
	if semantic_action != &"":
		_weapon_intent_router.call("reset_action", semantic_action)


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
	if (
		action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY
		or _weapon_hold_is_active()
	):
		_cancel_weapon_action(&"dash_cancel")
	if not action_state.transition_to(PlayerActionStateScript.State.DASH, _seconds_to_frames(DASH_DURATION)):
		return false
	_dash_cooldown_remaining = DASH_COOLDOWN
	_dash_direction = _last_move_direction.normalized()
	_dash_velocity = _dash_direction * DASH_SPEED
	health.apply_invulnerability(DASH_INVULNERABLE_TIME + _dash_invulnerable_bonus)
	EventBus.player_dashed.emit({})
	return true


func _request_time_skill(skill_id: StringName) -> bool:
	var context := _time_skill_context(skill_id)
	if not time_manager.can_use(skill_id, context):
		return false
	if action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST):
		return _begin_time_skill(skill_id, context)
	if _can_buffer_committed_action():
		_buffered_time_skill = skill_id
		action_state.buffer_input(&"time_cast", PlayerActionStateScript.COMBO_BUFFER_FRAMES)
		return true
	return false


func _begin_time_skill(skill_id: StringName, context: Dictionary = {}) -> bool:
	if not action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST):
		return false
	var committed_context := context if not context.is_empty() else _time_skill_context(skill_id)
	if not time_manager.can_use(skill_id, committed_context):
		return false
	if (
		action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY
		or _weapon_hold_is_active()
	):
		_cancel_weapon_action(&"time_cast_cancel")
	if not action_state.transition_to(PlayerActionStateScript.State.TIME_CAST, _seconds_to_frames(TIME_CAST_DURATION)):
		return false
	var committed: bool = time_manager.try_use(skill_id, committed_context)
	if not committed and action_state.current_state == PlayerActionStateScript.State.TIME_CAST:
		action_state.force_safe_reset()
	return committed


func _consume_buffered_action() -> bool:
	var buffered_action := action_state.consume_highest_priority_buffered_input()
	match buffered_action:
		&"dash":
			return _begin_dash()
		&"time_cast":
			var skill_id := _buffered_time_skill
			_buffered_time_skill = &""
			return _begin_time_skill(skill_id, _time_skill_context(skill_id))
	return false


func _can_buffer_committed_action() -> bool:
	return action_state.current_state in [
		PlayerActionStateScript.State.ATTACK_WINDUP,
		PlayerActionStateScript.State.ATTACK_ACTIVE,
		PlayerActionStateScript.State.ATTACK_RECOVERY,
	]


func _assemble_weapon_runtime(config: Dictionary) -> Dictionary:
	var weapon_id := StringName(str(config.get("weapon_id", "")))
	if weapon_id not in [&"sword", &"bow", &"gun", &"staff", &"gauntlets"]:
		return {
			"ok": true,
			"profile": null,
			"modifiers": null,
			"runtime": null,
			"coordinator": null,
		}

	var profile_value: Variant = config.get("weapon_profile", {})
	if not profile_value is Dictionary or (profile_value as Dictionary).is_empty():
		return {"ok": false, "reason": "profile_missing"}
	var next_profile = WeaponRuntimeProfileScript.new()
	var profile_result: Dictionary = next_profile.configure((profile_value as Dictionary).duplicate(true))
	if not bool(profile_result.get("ok", false)):
		return {"ok": false, "reason": "profile_invalid", "context": profile_result.duplicate(true)}

	var profile_snapshot: Dictionary = next_profile.snapshot()
	if StringName(str(profile_snapshot.get("weapon_id", ""))) != weapon_id:
		return {"ok": false, "reason": "profile_weapon_mismatch"}
	var capabilities := PackedStringArray(profile_snapshot.get("capabilities", []))
	var bounds := _modifier_bounds_for(capabilities)
	if bounds.size() != capabilities.size():
		return {"ok": false, "reason": "capability_bounds_missing"}
	var next_modifiers = WeaponModifierStateScript.new()
	if not next_modifiers.configure(capabilities, bounds):
		return {"ok": false, "reason": "modifier_configuration_failed"}

	var next_runtime = _new_weapon_runtime(weapon_id)
	if next_runtime == null:
		return {"ok": false, "reason": "runtime_unavailable"}
	var requires_adapter_activation := (
		weapon_id == &"gauntlets"
		and next_runtime.has_method("configure_detached")
		and next_runtime.has_method("activate_adapter")
	)
	var runtime_configured := bool(next_runtime.call(
		"configure_detached" if requires_adapter_activation else "configure",
		self,
		next_profile,
		next_modifiers
	))
	if not runtime_configured:
		return {"ok": false, "reason": "runtime_configuration_failed"}
	var runtime_owned_resources := PackedStringArray()
	for resource_value: Variant in profile_snapshot.get("resources", []):
		if not resource_value is Dictionary:
			return {"ok": false, "reason": "resource_definition_invalid"}
		var resource_id := str((resource_value as Dictionary).get("resource_id", ""))
		if resource_id.is_empty():
			return {"ok": false, "reason": "resource_definition_invalid"}
		runtime_owned_resources.append(resource_id)
	var next_resource_transaction = WeaponResourceTransactionScript.new()
	if not next_resource_transaction.configure(
		weapon_id,
		runtime_owned_resources,
		{&"time_energy": time_manager}
	):
		return {"ok": false, "reason": "resource_transaction_configuration_failed"}
	var next_coordinator = WeaponActionCoordinatorScript.new()
	if not next_coordinator.configure(next_runtime, next_resource_transaction):
		return {"ok": false, "reason": "coordinator_configuration_failed"}
	if not bool(next_coordinator.call(
		"set_next_token_floor",
		_next_weapon_action_token_floor
	)):
		return {"ok": false, "reason": "coordinator_token_floor_failed"}
	if weapon_id == &"staff" and not bool(staff_weapon.call("configure_result_sink", next_runtime)):
		return {"ok": false, "reason": "payload_result_sink_configuration_failed"}
	return {
		"ok": true,
		"profile": next_profile,
		"modifiers": next_modifiers,
		"runtime": next_runtime,
		"coordinator": next_coordinator,
		"requires_adapter_activation": requires_adapter_activation,
	}


func _new_weapon_runtime(weapon_id: StringName) -> RefCounted:
	match weapon_id:
		&"sword":
			return SwordWeaponRuntimeScript.new()
		&"bow":
			return BowWeaponRuntimeScript.new()
		&"gun":
			return GunWeaponRuntimeScript.new()
		&"staff":
			return StaffWeaponRuntimeScript.new()
		&"gauntlets":
			return GauntletsWeaponRuntimeScript.new()
		_:
			return null


func _modifier_bounds_for(capabilities: PackedStringArray) -> Dictionary:
	var bounds: Dictionary = {}
	for capability_value: String in capabilities:
		if not WEAPON_MODIFIER_BOUNDS.has(capability_value):
			return {}
		bounds[capability_value] = (WEAPON_MODIFIER_BOUNDS[capability_value] as Dictionary).duplicate(true)
	return bounds


func _weapon_profile_definition(weapon_id: StringName) -> Dictionary:
	var preferred_profile_id: String = str({
		&"sword": "sword_m1_v1",
		&"bow": "bow_candidate_v1",
		&"staff": "staff_launch_v1",
		&"gauntlets": "gauntlets_launch_v1",
	}.get(weapon_id, ""))
	if preferred_profile_id.is_empty():
		return {}
	return _weapon_profile_catalog_definition(StringName(preferred_profile_id))


func _weapon_profile_catalog_definition(profile_id: StringName) -> Dictionary:
	if profile_id == &"":
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAPON_PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		if StringName(str(definition.get("id", ""))) == profile_id:
			return definition.duplicate(true)
	return {}


func _canonical_weapon_profile(source: Dictionary) -> Dictionary:
	if source.is_empty():
		return {}
	var profile = WeaponRuntimeProfileScript.new()
	var result: Dictionary = profile.configure(source.duplicate(true))
	var snapshot: Dictionary = (
		(result.get("profile", {}) as Dictionary).duplicate(true)
		if bool(result.get("ok", false)) and result.get("profile", {}) is Dictionary
		else {}
	)
	if snapshot.is_empty():
		return {}
	for field: String in ["availability", "tags", "references", "capabilities"]:
		var values: Array = snapshot.get(field, [])
		values.sort()
		snapshot[field] = values
	var compatibility: Dictionary = snapshot.get("compatibility", {}).duplicate(true)
	for field_value: Variant in compatibility.keys():
		var values: Array = compatibility[field_value]
		values.sort()
		compatibility[field_value] = values
	snapshot["compatibility"] = compatibility
	return snapshot


func _profile_allows_milestone(config: Dictionary) -> bool:
	var profile_value: Variant = config.get("weapon_profile", {})
	if not profile_value is Dictionary:
		return false
	var availability_value: Variant = (profile_value as Dictionary).get("availability", [])
	if not availability_value is Array:
		return false
	var milestone := str(config.get("milestone", "M1")).strip_edges().to_upper()
	for availability: Variant in availability_value as Array:
		if str(availability).strip_edges().to_upper() == milestone:
			return true
	return false


func _connect_weapon_coordinator() -> void:
	if weapon_action_coordinator == null:
		return
	if not weapon_action_coordinator.weapon_action_committed.is_connected(_on_weapon_action_committed):
		weapon_action_coordinator.weapon_action_committed.connect(_on_weapon_action_committed)
	if not weapon_action_coordinator.weapon_runtime_event.is_connected(_on_weapon_runtime_event):
		weapon_action_coordinator.weapon_runtime_event.connect(_on_weapon_runtime_event)


func _capture_next_weapon_action_token_floor() -> void:
	if weapon_action_coordinator == null or not weapon_action_coordinator.has_method("snapshot"):
		return
	var coordinator_snapshot_value: Variant = weapon_action_coordinator.call("snapshot")
	if not coordinator_snapshot_value is Dictionary:
		return
	var observed_next_token := int((coordinator_snapshot_value as Dictionary).get("next_token", 0))
	if observed_next_token > 0:
		_next_weapon_action_token_floor = maxi(
			_next_weapon_action_token_floor,
			observed_next_token
		)


func _disconnect_weapon_coordinator() -> void:
	if weapon_action_coordinator == null:
		return
	if weapon_action_coordinator.weapon_action_committed.is_connected(_on_weapon_action_committed):
		weapon_action_coordinator.weapon_action_committed.disconnect(_on_weapon_action_committed)
	if weapon_action_coordinator.weapon_runtime_event.is_connected(_on_weapon_runtime_event):
		weapon_action_coordinator.weapon_runtime_event.disconnect(_on_weapon_runtime_event)


func _on_weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	if token > 0:
		_next_weapon_action_token_floor = maxi(
			_next_weapon_action_token_floor,
			token + 1
		)
	_track_weapon_action_token(token, action_id, int(context.get("action_generation", 0)))
	if weapon_action_coordinator != null:
		var coordinator_snapshot: Dictionary = weapon_action_coordinator.snapshot()
		var plan_value: Variant = coordinator_snapshot.get("plan", {})
		if plan_value is Dictionary:
			_weapon_combo_timeout_frames = maxi(
				0,
				int((plan_value as Dictionary).get("combo_reset_frames", 0))
			)
	EventBus.weapon_action_committed.emit(
		weapon_id,
		action_id,
		token,
		context.duplicate(true)
	)
	_sync_weapon_resource_facts(&"action_committed")


func _track_weapon_action_token(token: int, action_id: StringName, generation: int) -> void:
	if token <= 0 or action_id == &"" or generation <= 0:
		return
	if not _weapon_action_ids_by_token.has(token):
		_weapon_action_token_order.append(token)
	_weapon_action_ids_by_token[token] = action_id
	_weapon_action_generations_by_token[token] = generation
	while _weapon_action_token_order.size() > MAX_TRACKED_WEAPON_FACT_TOKENS:
		var expired_token: int = int(_weapon_action_token_order.pop_front())
		_weapon_action_ids_by_token.erase(expired_token)
		_weapon_action_generations_by_token.erase(expired_token)
		_weapon_hit_fact_claims.erase(expired_token)
		_clear_weapon_action_reward_claims(expired_token)


func _clear_weapon_action_reward_claims(action_token: int) -> void:
	var prefix := "%d:" % action_token
	for claim_key: Variant in _weapon_action_reward_claims.keys():
		if str(claim_key).begins_with(prefix):
			_weapon_action_reward_claims.erase(claim_key)


func _on_gun_action_hit_confirmed(action_token: int, target: Node) -> void:
	if (
		action_token <= 0
		or target == null
		or not is_instance_valid(target)
		or loadout_runtime == null
		or not loadout_runtime.has_weapon(&"gun")
		or not _weapon_action_ids_by_token.has(action_token)
		or _weapon_hit_fact_claims.has(action_token)
	):
		return
	var action_id := StringName(str(_weapon_action_ids_by_token[action_token]))
	if action_id == &"":
		return
	_weapon_hit_fact_claims[action_token] = true
	EventBus.weapon_hit_confirmed.emit(
		&"gun",
		action_id,
		action_token,
		target.get_instance_id(),
		{"source": "gun_projectile", "scope": "action"}
	)


func _on_gun_resource_reward_requested(
	action_token: int,
	reward_id: StringName,
	amount: float
) -> void:
	if (
		action_token <= 0
		or reward_id != &"time_energy"
		or not is_finite(amount)
		or amount <= 0.0
		or loadout_runtime == null
		or not loadout_runtime.has_weapon(&"gun")
		or not _weapon_action_ids_by_token.has(action_token)
		or not claim_weapon_action_reward(
			action_token,
			StringName("resource:%s" % str(reward_id))
		)
	):
		return
	var before := float(time_manager.energy)
	time_manager.restore_energy(amount)
	var current := float(time_manager.energy)
	if current <= before:
		return
	EventBus.weapon_resource_changed.emit(
		&"gun",
		reward_id,
		current,
		float(time_manager.max_energy),
		&"projectile_reward"
	)


func _on_staff_resource_reward_requested(
	action_token: int,
	claim_id: StringName,
	reward_id: StringName,
	amount: float
) -> void:
	var generation := int(_weapon_action_generations_by_token.get(action_token, 0))
	if (
		action_token <= 0
		or generation <= 0
		or claim_id == &""
		or reward_id != &"time_energy"
		or not is_finite(amount)
		or amount <= 0.0
		or loadout_runtime == null
		or not loadout_runtime.has_weapon(&"staff")
		or StringName(str(_weapon_action_ids_by_token.get(action_token, ""))) != &"primordial_wrath"
		or not _valid_staff_ultimate_reward_claim(claim_id)
		or not claim_weapon_action_reward(
			action_token,
			StringName(
				"resource:%s:%s:generation:%d" % [
					str(reward_id),
					str(claim_id),
					generation,
				]
			)
		)
	):
		return
	var before := float(time_manager.energy)
	time_manager.restore_energy(amount)
	var current := float(time_manager.energy)
	if current <= before:
		return
	EventBus.weapon_resource_changed.emit(
		&"staff",
		reward_id,
		current,
		float(time_manager.max_energy),
		&"ultimate_tick"
	)


func _valid_staff_ultimate_reward_claim(claim_id: StringName) -> bool:
	const PREFIX := "staff_ultimate_tick:"
	var claim := str(claim_id)
	if not claim.begins_with(PREFIX):
		return false
	var tick_text := claim.trim_prefix(PREFIX)
	if not tick_text.is_valid_int():
		return false
	var tick_index := int(tick_text)
	return tick_index >= 0 and tick_index < 20 and str(tick_index) == tick_text


func _sync_weapon_resource_facts(reason: StringName) -> void:
	if (
		weapon_runtime == null
		or not weapon_runtime.has_method("presentation_snapshot")
		or loadout_runtime == null
	):
		return
	var weapon_id: StringName = loadout_runtime.weapon_id()
	var resource_id: StringName = &""
	var current_field := ""
	var maximum_field := ""
	match weapon_id:
		&"gun":
			resource_id = &"ammo"
			current_field = "ammo"
			maximum_field = "ammo_maximum"
		&"staff":
			resource_id = &"mana"
			current_field = "mana"
			maximum_field = "mana_maximum"
		_:
			return
	var snapshot_value: Variant = weapon_runtime.call("presentation_snapshot")
	if not snapshot_value is Dictionary:
		return
	var snapshot := snapshot_value as Dictionary
	var current_value: Variant = snapshot.get(current_field)
	var maximum_value: Variant = snapshot.get(maximum_field)
	if (
		typeof(current_value) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(maximum_value) not in [TYPE_INT, TYPE_FLOAT]
	):
		return
	var current := float(current_value)
	var maximum := float(maximum_value)
	if (
		not is_finite(current)
		or not is_finite(maximum)
		or current < 0.0
		or maximum <= 0.0
		or current > maximum
	):
		return
	var resource_key := str(resource_id)
	var previous_value: Variant = _weapon_resource_fact_state.get(resource_key)
	if previous_value is Dictionary:
		var previous := previous_value as Dictionary
		if (
			is_equal_approx(float(previous.get("current", -1.0)), current)
			and is_equal_approx(float(previous.get("maximum", -1.0)), maximum)
		):
			return
	_weapon_resource_fact_state[resource_key] = {"current": current, "maximum": maximum}
	EventBus.weapon_resource_changed.emit(weapon_id, resource_id, current, maximum, reason)


func _on_staff_payload_result_reported(
	_action_token: int,
	_generation: int,
	_result: Dictionary
) -> void:
	if loadout_runtime == null or not loadout_runtime.has_weapon(&"staff"):
		return
	_sync_weapon_resource_facts(&"payload_result")


func _on_gauntlets_impact_feedback_requested(
	action_token: int,
	generation: int,
	fact: Dictionary
) -> void:
	if (
		action_token <= 0
		or generation != action_token
		or loadout_runtime == null
		or not loadout_runtime.has_weapon(&"gauntlets")
		or not _weapon_action_ids_by_token.has(action_token)
	):
		return
	var action_id := StringName(str(_weapon_action_ids_by_token[action_token]))
	var target_id := int(fact.get("target_id", 0))
	if action_id == &"" or str(fact.get("action_id", "")) != str(action_id) or target_id <= 0:
		return
	var context := fact.duplicate(true)
	context["source"] = "gauntlets_payload"
	context["generation"] = generation
	EventBus.weapon_hit_confirmed.emit(
		&"gauntlets",
		action_id,
		action_token,
		target_id,
		context
	)


func _on_weapon_runtime_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	var weapon_id := StringName(str(event.get("weapon_id", "")))
	var action_id := StringName(str(event.get("action_id", "")))
	var token := int(event.get("token", 0))
	if weapon_id == &"" or action_id == &"" or token <= 0:
		return
	match event_type:
		"payload_released":
			EventBus.player_attacked.emit(
				weapon_id,
				{
					"action_id": str(action_id),
					"descriptor_id": str(event.get("descriptor_id", "")),
					"token": token,
				}
			)
		"cue_requested":
			var cue_value: Variant = event.get("cue", {})
			if cue_value is Dictionary and not (cue_value as Dictionary).is_empty():
				EventBus.weapon_cue_requested.emit(
					weapon_id,
					action_id,
					token,
					(cue_value as Dictionary).duplicate(true)
				)


func _sync_weapon_action_projection() -> void:
	if weapon_action_coordinator == null:
		if action_state.current_state in [
			PlayerActionStateScript.State.ATTACK_WINDUP,
			PlayerActionStateScript.State.ATTACK_ACTIVE,
			PlayerActionStateScript.State.ATTACK_RECOVERY,
		]:
			action_state.clear_weapon_projection()
		return
	var presentation: Dictionary = weapon_action_coordinator.presentation_snapshot()
	var phase := StringName(str(presentation.get("phase", "READY")))
	if phase == &"READY":
		action_state.clear_weapon_projection()
		return
	action_state.project_weapon_phase(
		phase,
		int(presentation.get("phase_frame", 0)),
		int(presentation.get("phase_duration_frames", 0)),
		int(presentation.get("cancel_from_frame", -1))
	)


func _cancel_weapon_action(reason: StringName) -> void:
	if weapon_action_coordinator != null:
		weapon_action_coordinator.cancel(reason)
	else:
		sword_weapon.cancel_attack()
	_weapon_intent_router.call("reset_all")
	if action_state.current_state in [
		PlayerActionStateScript.State.ATTACK_WINDUP,
		PlayerActionStateScript.State.ATTACK_ACTIVE,
		PlayerActionStateScript.State.ATTACK_RECOVERY,
	]:
		action_state.clear_weapon_projection()


func _time_skill_context(skill_id: StringName) -> Dictionary:
	match time_manager.canonical_skill_id(skill_id):
		&"rewind":
			return {"recorder": rewind_recorder}
		&"rift":
			return {"position": global_position}
		_:
			return {}


func _time_slot_action_id(slot_action_id: StringName) -> StringName:
	if loadout_runtime == null or time_manager == null:
		return &""
	var slot_index := -1
	match slot_action_id:
		&"time_slot_1":
			slot_index = 0
		&"time_slot_2":
			slot_index = 1
		_:
			return &""
	var ability_ids: Array = loadout_runtime.time_ability_ids()
	if slot_index >= ability_ids.size():
		return &""
	return time_manager.action_skill_id(StringName(str(ability_ids[slot_index])))


func _canonical_time_action_id(action_id: StringName) -> StringName:
	var resolved_action_id := _time_slot_action_id(action_id)
	if resolved_action_id != &"":
		return time_manager.canonical_skill_id(resolved_action_id)
	return time_manager.canonical_skill_id(action_id)


func _clear_transient_effects() -> void:
	_cancel_weapon_action(&"transient_clear")
	_dash_velocity = Vector2.ZERO
	_buffered_time_skill = &""


func _weapon_hold_is_active() -> bool:
	return (
		weapon_action_coordinator != null
		and weapon_action_coordinator.phase_name() == &"HOLD"
	)


func _collect_weapon_input_intents() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for semantic_action: StringName in [
		&"weapon_primary",
		&"weapon_secondary",
		&"weapon_utility",
		&"weapon_skill",
		&"weapon_ultimate",
	]:
		var aliases := _weapon_input_aliases(semantic_action)
		var just_pressed := false
		var just_released := false
		var alias_still_pressed := false
		for action_id: StringName in aliases:
			just_pressed = just_pressed or Input.is_action_just_pressed(action_id)
			just_released = just_released or Input.is_action_just_released(action_id)
			alias_still_pressed = alias_still_pressed or Input.is_action_pressed(action_id)
		var mode := _weapon_semantic_input_mode(semantic_action)
		var raw_edge := &""
		if just_pressed:
			raw_edge = &"pressed"
		elif just_released and not alias_still_pressed and mode == &"hold":
			raw_edge = &"released"
		if raw_edge == &"":
			continue
		var intent: Dictionary = _weapon_intent_router.call(
			"normalize_edge",
			semantic_action,
			raw_edge,
			_current_weapon_hold_frames(),
			mode
		)
		if not intent.is_empty():
			intents.append(intent)
	return intents


func _weapon_input_aliases(semantic_action: StringName) -> Array[StringName]:
	match semantic_action:
		&"weapon_primary":
			var aliases: Array[StringName] = [&"weapon_primary"]
			if loadout_runtime != null and loadout_runtime.has_weapon(&"bow"):
				aliases.append(&"ranged_attack")
			else:
				aliases.append(&"attack")
			return aliases
		&"weapon_secondary":
			return [&"weapon_secondary", &"heavy_attack"]
		&"weapon_utility":
			return [&"weapon_utility"]
		&"weapon_skill":
			return [&"weapon_skill"]
		&"weapon_ultimate":
			return [&"weapon_ultimate"]
		_:
			return []


func _weapon_semantic_input_mode(semantic_action: StringName) -> StringName:
	var profile: Dictionary = (
		loadout_runtime.weapon_profile_snapshot()
		if loadout_runtime != null and loadout_runtime.has_method("weapon_profile_snapshot")
		else {}
	)
	for action_value: Variant in profile.get("actions", []):
		if not action_value is Dictionary:
			continue
		var action := action_value as Dictionary
		if StringName(str(action.get("semantic_action", ""))) != semantic_action:
			continue
		if StringName(str(action.get("activation_mode", "press"))) in [&"release", &"hold", &"channel"]:
			return StringName(str(GameState.get_setting("ranged_charge_mode", "hold")))
	return &"press"


func _current_weapon_hold_frames() -> int:
	if weapon_action_coordinator == null or weapon_action_coordinator.phase_name() != &"HOLD":
		return 0
	return int(weapon_action_coordinator.presentation_snapshot().get("hold_frames", 0))


func _active_hold_semantic_action() -> StringName:
	if weapon_action_coordinator == null or weapon_action_coordinator.phase_name() != &"HOLD":
		return &""
	var snapshot: Dictionary = weapon_action_coordinator.snapshot()
	return StringName(str((snapshot.get("plan", {}) as Dictionary).get("semantic_action", "")))


func _gauntlets_counter_window_is_open() -> bool:
	if (
		loadout_runtime == null
		or not loadout_runtime.has_weapon(&"gauntlets")
		or weapon_action_coordinator == null
		or weapon_action_coordinator.phase_name() != &"READY"
		or action_state.current_state != PlayerActionStateScript.State.FREE
		or _dash_completion_token <= 0
		or _dash_completed_at_runtime_frame < 0
	):
		return false
	var frames_since_completion := _runtime_frame - _dash_completed_at_runtime_frame
	return (
		frames_since_completion >= 0
		and frames_since_completion <= GAUNTLETS_COUNTER_WINDOW_LAST_FRAME
	)


func _weapon_aim_direction() -> Vector2:
	var weapon_id: StringName = loadout_runtime.weapon_id() if loadout_runtime != null else &""
	var rotation_value := float(sword_weapon.global_rotation)
	match weapon_id:
		&"bow":
			rotation_value = float(bow_weapon.global_rotation)
		&"gun":
			rotation_value = float(gun_weapon.global_rotation)
		&"staff":
			rotation_value = float(staff_weapon.global_rotation)
		&"gauntlets":
			rotation_value = float(gauntlets_weapon.global_rotation)
	return Vector2.RIGHT.rotated(rotation_value)


func _weapon_submission_context() -> Dictionary:
	var aim_direction := _weapon_aim_direction().normalized()
	var frames_since_dash_completion := -1
	if _dash_completion_token > 0 and _dash_completed_at_runtime_frame >= 0:
		frames_since_dash_completion = maxi(
			0,
			_runtime_frame - _dash_completed_at_runtime_frame
		)
	return {
		"aim_direction": aim_direction,
		"target_point": global_position + aim_direction * BOW_TARGET_DISTANCE_PIXELS,
		"facing": _last_move_direction,
		"run_seed": loadout_runtime.run_seed() if loadout_runtime != null else 0,
		"dash_completion_token": _dash_completion_token,
		"frames_since_dash_completion": frames_since_dash_completion,
		"dash_direction": _dash_direction,
		"time_interactions": weapon_time_interaction_context(),
	}


func _clear_owned_player_arrows() -> void:
	if bow_weapon == null:
		return
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		if (
			is_instance_valid(arrow)
			and not arrow.is_queued_for_deletion()
			and arrow.get("owner_entity") == self
			and arrow.get("source") == bow_weapon
		):
			arrow.queue_free()


func _clear_owned_player_projectiles() -> void:
	if gun_weapon == null and staff_weapon == null:
		return
	for projectile: Node in get_tree().get_nodes_in_group("player_projectiles"):
		if (
			is_instance_valid(projectile)
			and not projectile.is_queued_for_deletion()
			and projectile.get("owner_entity") == self
			and projectile.get("source") in [gun_weapon, staff_weapon]
		):
			projectile.queue_free()


func _clear_owned_staff_payloads() -> void:
	if staff_weapon != null and staff_weapon.has_method("reset_runtime_state"):
		staff_weapon.call("reset_runtime_state")


func _clear_owned_gauntlets_payloads() -> void:
	if gauntlets_weapon != null and gauntlets_weapon.has_method("reset_runtime_state"):
		gauntlets_weapon.call("reset_runtime_state")


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
	if time_manager != null and time_manager.has_method("apply_legacy_time_acceleration"):
		time_manager.apply_legacy_time_acceleration(multiplier, duration)


func apply_time_acceleration_token(token: int, multiplier: float, duration: float) -> bool:
	if token <= 0 or duration <= 0.0:
		return false
	_time_acceleration_token = token
	_time_acceleration_multiplier = maxf(1.0, multiplier)
	_time_acceleration_remaining = duration
	_apply_stats_to_components(false)
	return true


func clear_time_acceleration(token: int) -> bool:
	if token != _time_acceleration_token:
		return false
	_time_acceleration_multiplier = 1.0
	_time_acceleration_remaining = 0.0
	_apply_stats_to_components(false)
	return true


func _clear_time_acceleration(token: int) -> void:
	clear_time_acceleration(token)


func _force_clear_time_acceleration() -> void:
	_time_acceleration_token += 1
	_time_acceleration_multiplier = 1.0
	_time_acceleration_remaining = 0.0


func is_time_accelerated() -> bool:
	return _time_acceleration_multiplier > 1.0


func _on_damaged(_amount: float, _current_hp: float) -> void:
	if loadout_runtime != null and loadout_runtime.has_weapon(&"gauntlets") and weapon_runtime != null:
		if weapon_runtime.has_method("on_player_damaged"):
			weapon_runtime.call("on_player_damaged")
		elif weapon_runtime.has_method("reset_combo"):
			weapon_runtime.call("reset_combo")
	visual.color = Color(1.0, 0.95, 0.85)
	var tween := create_tween()
	tween.tween_property(visual, "color", BASE_COLOR, 0.12)
	if health.current_hp > 0.0:
		apply_hitstun_frames(_seconds_to_frames(HITSTUN_DURATION))


func _on_died(_killer: Variant) -> void:
	if action_state.transition_to(PlayerActionStateScript.State.DEAD, 0):
		action_state.clear_buffered_inputs()
		_clear_transient_effects()
		_clear_owned_player_arrows()
		_clear_owned_player_projectiles()
		_clear_owned_staff_payloads()
		_clear_owned_gauntlets_payloads()
		cancel_active_time_effects(&"player_died")


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
	gun_weapon.base_attack = GUN_BASE_ATTACK
	gun_weapon.attack_speed = GUN_ATTACK_SPEED * _time_acceleration_multiplier
	gauntlets_weapon.base_attack = GAUNTLETS_BASE_ATTACK
	gauntlets_weapon.attack_speed = GAUNTLETS_ATTACK_SPEED * _time_acceleration_multiplier
	staff_weapon.base_attack = STAFF_BASE_ATTACK
