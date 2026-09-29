class_name PlayerController
extends CharacterBody2D

const StatsResource := preload("res://scripts/core/stats.gd")
const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerLoadoutRuntimeScript := preload("res://scripts/player/player_loadout_runtime.gd")
const BowWeaponRuntimeScript := preload("res://scripts/combat/weapons/bow_weapon_runtime.gd")
const SwordWeaponRuntimeScript := preload("res://scripts/combat/weapons/sword_weapon_runtime.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const DEFAULT_LOADOUT_CONFIG := {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}
const WEAPON_PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const WEAPON_MODIFIER_BOUNDS := {
	"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
	"weapon.charge_rate": {"minimum": 0.0, "maximum": 5.0},
	"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
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
var weapon_action_coordinator: RefCounted
var weapon_runtime: RefCounted
var weapon_runtime_profile: RefCounted
var weapon_modifier_state: RefCounted
var _weapon_combo_timeout_frames: int = 0
var _weapon_profile_compatibility_fallback: bool = false
var _buffered_time_skill: StringName = &""
var _weapon_action_reward_claims: Dictionary = {}

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
	_handle_priority_action_input()
	_handle_movement(delta)


func _update_timers(delta: float) -> void:
	_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)


func _update_weapon_aim() -> void:
	var aim_direction := global_position.direction_to(get_global_mouse_position())
	if aim_direction.length_squared() > 0.001:
		sword_weapon.rotation = aim_direction.angle()
		bow_weapon.rotation = aim_direction.angle()


func _handle_priority_action_input() -> void:
	var time_actions: Array[StringName] = []
	for action_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		if Input.is_action_just_pressed(action_id):
			time_actions.append(action_id)
	var weapon_actions: Array[StringName] = []
	for action_id: StringName in [&"attack", &"heavy_attack"]:
		if Input.is_action_just_pressed(action_id):
			weapon_actions.append(action_id)
	_submit_priority_action_edges(
		Input.is_action_just_pressed("dash"),
		time_actions,
		weapon_actions
	)
	handle_ranged_input_for_test(
		Input.is_action_just_pressed("ranged_attack"),
		Input.is_action_just_released("ranged_attack")
	)


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
	if mode == "toggle":
		if just_pressed:
			try_action(&"ranged_release" if _weapon_hold_is_active() else &"ranged_attack")
		return
	if just_pressed:
		try_action(&"ranged_attack")
	if just_released:
		try_action(&"ranged_release")


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
			return loadout_runtime.has_weapon(&"sword") and _submit_weapon_intent(&"weapon_secondary")
		&"ranged_attack", &"ranged_release":
			return _commit_ranged_input(action_id)
		&"dash":
			return _request_dash()
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
	var next_config := config.duplicate(true)
	var next_weapon_id := StringName(str(next_config.get("weapon_id", "")))
	var explicit_weapon_profile := next_config.has("weapon_profile")
	var used_compatibility_profile := false
	if next_weapon_id in [&"sword", &"bow"] and not next_config.has("weapon_profile"):
		var default_profile := _weapon_profile_definition(next_weapon_id)
		if default_profile.is_empty():
			return false
		next_config["weapon_profile"] = default_profile
		used_compatibility_profile = true
	if explicit_weapon_profile and not _profile_allows_milestone(next_config):
		return false

	var validator = PlayerLoadoutRuntimeScript.new()
	var loadout_is_valid := validator.configure(next_config)
	validator.free()
	if not loadout_is_valid:
		return false

	var assembly := _assemble_weapon_runtime(next_config)
	if not bool(assembly.get("ok", false)):
		return false
	if not loadout_runtime.configure(next_config):
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
	_buffered_time_skill = &""
	_dash_cooldown_remaining = 0.0
	_dash_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_last_move_direction = Vector2.RIGHT
	if weapon_action_coordinator != null:
		weapon_action_coordinator.reset_runtime_state(&"player_runtime_reset")
	else:
		sword_weapon.cancel_attack()
		sword_weapon.reset_combo()
	bow_weapon.reset_runtime_state()
	time_manager.reset_runtime_state()
	_force_clear_time_acceleration()
	_apply_stats_to_components(true)
	health.invulnerable = false
	if rewind_recorder.has_method("clear_snapshots"):
		rewind_recorder.clear_snapshots()


func advance_action_frame() -> void:
	if _weapon_combo_timeout_frames > 0:
		_weapon_combo_timeout_frames -= 1
		if _weapon_combo_timeout_frames == 0 and weapon_runtime != null and weapon_runtime.has_method("reset_combo"):
			weapon_runtime.call("reset_combo")

	action_state.advance_frame()
	if weapon_action_coordinator != null:
		weapon_action_coordinator.advance_frame(false)
		_sync_weapon_action_projection()

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
		weapon_action_coordinator.reset_runtime_state(&"rewind_restore")
	else:
		sword_weapon.cancel_attack()
		sword_weapon.reset_combo()
	_dash_velocity = Vector2.ZERO
	_buffered_time_skill = &""
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
		&"bow_charge_rate_bonus":
			bow_weapon.charge_rate_bonus += numeric
		&"bow_full_charge_damage_multiplier_bonus":
			bow_weapon.full_charge_damage_multiplier_bonus += numeric
		&"bow_pierce_bonus":
			bow_weapon.pierce_bonus += int(value)
		_:
			return false
	return true


func _submit_weapon_intent(
	semantic_action: StringName,
	edge: StringName = &"pressed"
) -> bool:
	if weapon_action_coordinator == null:
		return false
	if action_state.current_state in [
		PlayerActionStateScript.State.DASH,
		PlayerActionStateScript.State.TIME_CAST,
		PlayerActionStateScript.State.HITSTUN,
		PlayerActionStateScript.State.DEAD,
	]:
		return false
	var result: Dictionary = weapon_action_coordinator.submit_intent(
		{
			"id": str(semantic_action),
			"edge": str(edge),
			"buffer_frames": PlayerActionStateScript.COMBO_BUFFER_FRAMES,
		},
		{
			"aim_direction": _weapon_aim_direction(),
			"facing": _last_move_direction,
		}
	)
	_sync_weapon_action_projection()
	if not bool(result.get("ok", false)):
		return false
	return true


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
	_dash_velocity = _last_move_direction * DASH_SPEED
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
	if weapon_id not in [&"sword", &"bow"]:
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

	var next_runtime = (
		SwordWeaponRuntimeScript.new()
		if weapon_id == &"sword"
		else BowWeaponRuntimeScript.new()
	)
	if not next_runtime.configure(self, next_profile, next_modifiers):
		return {"ok": false, "reason": "runtime_configuration_failed"}
	var next_coordinator = WeaponActionCoordinatorScript.new()
	if not next_coordinator.configure(next_runtime):
		return {"ok": false, "reason": "coordinator_configuration_failed"}
	return {
		"ok": true,
		"profile": next_profile,
		"modifiers": next_modifiers,
		"runtime": next_runtime,
		"coordinator": next_coordinator,
	}


func _modifier_bounds_for(capabilities: PackedStringArray) -> Dictionary:
	var bounds: Dictionary = {}
	for capability_value: String in capabilities:
		if not WEAPON_MODIFIER_BOUNDS.has(capability_value):
			return {}
		bounds[capability_value] = (WEAPON_MODIFIER_BOUNDS[capability_value] as Dictionary).duplicate(true)
	return bounds


func _weapon_profile_definition(weapon_id: StringName) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAPON_PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	var preferred_profile_id: String = str({
		&"sword": "sword_m1_v1",
		&"bow": "bow_candidate_v1",
	}.get(weapon_id, ""))
	if preferred_profile_id.is_empty():
		return {}
	for definition_value: Variant in parsed as Array:
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		if str(definition.get("id", "")) == preferred_profile_id:
			return definition.duplicate(true)
	return {}


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


func _clear_transient_effects() -> void:
	_cancel_weapon_action(&"transient_clear")
	_dash_velocity = Vector2.ZERO
	_buffered_time_skill = &""
	if bow_weapon.has_method("cancel_charge"):
		bow_weapon.cancel_charge()


func _weapon_hold_is_active() -> bool:
	return (
		weapon_action_coordinator != null
		and weapon_action_coordinator.phase_name() == &"HOLD"
	)


func _weapon_aim_direction() -> Vector2:
	var weapon_id: StringName = loadout_runtime.weapon_id() if loadout_runtime != null else &""
	var rotation_value: float = (
		float(bow_weapon.global_rotation)
		if weapon_id == &"bow"
		else float(sword_weapon.global_rotation)
	)
	return Vector2.RIGHT.rotated(rotation_value)


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
	visual.color = Color(1.0, 0.95, 0.85)
	var tween := create_tween()
	tween.tween_property(visual, "color", BASE_COLOR, 0.12)
	if health.current_hp > 0.0:
		apply_hitstun_frames(_seconds_to_frames(HITSTUN_DURATION))


func _on_died(_killer: Variant) -> void:
	if action_state.transition_to(PlayerActionStateScript.State.DEAD, 0):
		action_state.clear_buffered_inputs()
		_clear_transient_effects()
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
