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
const StaffSpellZoneScript := preload("res://scripts/combat/staff_spell_zone.gd")
const SwordWeaponRuntimeScript := preload("res://scripts/combat/weapons/sword_weapon_runtime.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponIntentRouterScript := preload("res://scripts/input/weapon_intent_router.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponResourceTransactionScript := preload("res://scripts/combat/weapons/weapon_resource_transaction.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")

const DEFAULT_LOADOUT_CONFIG := {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}
const WEAPON_PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const WEAPON_MODIFIER_BOUNDS := {
	"weapon.ammo_capacity": {"minimum": 0.0, "maximum": 20.0},
	"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
	"weapon.charge_rate": {"minimum": 0.0, "maximum": 6.0},
	"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.combo_timeout": {"minimum": 0.25, "maximum": 4.0},
	"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.full_charge_damage": {"minimum": 0.0, "maximum": 11.0},
	"weapon.heavy_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.heavy_execute_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.heavy_execute_threshold": {"minimum": 0.0, "maximum": 1.0},
	"weapon.low_hp_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.mana_max": {"minimum": 0.0, "maximum": 300.0},
	"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
	"weapon.reload_window": {"minimum": 0.0, "maximum": 10.0},
	"weapon.status_duration": {"minimum": 0.0, "maximum": 10.0},
}

@export var stats: Resource

@onready var health: Node = $HealthComponent
@onready var loadout_runtime: Node = $PlayerLoadoutRuntime
@onready var time_manager: Node = $TimeManager
@onready var rewind_recorder: Node = $RewindRecorder
@onready var visual: Polygon2D = $Visual

var _weapon_adapters: Dictionary = {}
var sword_weapon: Node:
	get:
		return _weapon_adapter(&"sword")
var bow_weapon: Node:
	get:
		return _weapon_adapter(&"bow")
var gun_weapon: Node:
	get:
		return _weapon_adapter(&"gun")
var staff_weapon: Node:
	get:
		return _weapon_adapter(&"staff")
var gauntlets_weapon: Node:
	get:
		return _weapon_adapter(&"gauntlets")

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
var _weapon_replay_events: Array[Dictionary] = []
var _weapon_replay_capture_sequence: int = 0
var _applying_weapon_replay_event: bool = false
var _weapon_replay_fact_baseline: Dictionary = {}
var _weapon_intent_router: RefCounted = WeaponIntentRouterScript.new()
var _run_id: StringName = &""

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
const STAFF_ATTACK_SPEED := 0.85
const MAX_TRACKED_WEAPON_FACT_TOKENS := 256
const WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION := 3
const WEAPON_REPLAY_EVENT_SCHEMA_VERSION := 3
const WEAPON_REPLAY_EVENT_FIELDS: Array[String] = [
	"schema_version",
	"frame",
	"sequence",
	"capture_sequence",
	"event_type",
	"payload",
]
const WEAPON_REPLAY_STATE_FIELDS: Array[String] = [
	"action_reward_claims",
	"action_ids_by_token",
	"action_generations_by_token",
	"action_token_order",
	"hit_fact_claims",
	"resource_fact_state",
	"next_token_floor",
	"combo_timeout_frames",
]
const WEAPON_REPLAY_CONTEXT_RESERVED_FIELDS: Array[String] = [
	"context_schema_version",
	"action_token",
	"action_generation",
	"coordinator_frame",
	"weapon_id",
	"action_id",
	"profile_id",
	"profile_version",
	"resource_transaction",
]
const WEAPON_REPLAY_CALLBACK_CLAIM_LIMIT := 512
const WEAPON_REPLAY_RESOURCE_REWARD_CLAIM_LIMIT := 128
const WEAPON_REPLAY_FEEDBACK_FACT_LIMIT := 256
const WEAPON_REPLAY_HP_ABSOLUTE_EPSILON := 0.0001
const WEAPON_REPLAY_STATE_FACT_TYPES: Array[String] = [
	"combat_damage",
	"weapon_hit_claim",
	"weapon_payload_result",
	"weapon_resource_reward",
]
const WEAPON_REPLAY_TIME_FACT_TYPES: Array[String] = [
	"time_interaction_claim",
	"time_stop_extension",
]
const RIGHT_STICK_AIM_DEADZONE := 0.25
const GAUNTLETS_COUNTER_WINDOW_LAST_FRAME := 8
const WEAPON_ADAPTER_IDS: Array[StringName] = [
	&"sword",
	&"bow",
	&"gun",
	&"staff",
	&"gauntlets",
]


func _discover_weapon_adapters() -> bool:
	_weapon_adapters.clear()
	for child: Node in get_children():
		if not child is Node2D or not child.has_method("weapon_id"):
			continue
		var weapon_id := StringName(str(child.call("weapon_id")))
		if weapon_id not in WEAPON_ADAPTER_IDS or _weapon_adapters.has(weapon_id):
			return false
		_weapon_adapters[weapon_id] = child
	return _weapon_adapters.size() == WEAPON_ADAPTER_IDS.size()


func _weapon_adapter(weapon_id: StringName) -> Node:
	return _weapon_adapters.get(weapon_id) as Node


func weapon_damage_action_identity() -> Dictionary:
	if weapon_action_coordinator == null or loadout_runtime == null:
		return {}
	var action_token := int(weapon_action_coordinator.current_token())
	var attack_generation := int(_weapon_action_generations_by_token.get(action_token, 0))
	if action_token <= 0 or attack_generation <= 0:
		return {}
	return {
		"weapon_id": loadout_runtime.weapon_id(),
		"attack_generation": attack_generation,
		"action_token": action_token,
	}


func damage_defense_decisions(damage_info: RefCounted) -> Dictionary:
	var weapon_decision: Dictionary = {}
	if damage_info != null and loadout_runtime != null:
		var equipped_weapon_id: StringName = loadout_runtime.weapon_id()
		var equipped_adapter := _weapon_adapter(equipped_weapon_id)
		if equipped_adapter != null and equipped_adapter.has_method("plan_damage_defense"):
			var decision_value: Variant = equipped_adapter.call("plan_damage_defense", damage_info)
			if decision_value is Dictionary:
				weapon_decision = (decision_value as Dictionary).duplicate(true)
				if (
					not weapon_decision.is_empty()
					and _planned_defense_weapon_id(weapon_decision) != equipped_weapon_id
				):
					weapon_decision = {"invalid_adapter_decision": true}
			else:
				weapon_decision = {"invalid_adapter_decision": true}
	return {
		"weapon": weapon_decision,
		"character": {},
	}


func commit_damage_defense(decisions: Dictionary, resolution: RefCounted) -> bool:
	if (
		resolution == null
		or decisions.size() != 2
		or not decisions.has("weapon")
		or not decisions.has("character")
		or not decisions["weapon"] is Dictionary
		or not decisions["character"] is Dictionary
		or loadout_runtime == null
	):
		return false
	var weapon_decision: Dictionary = decisions["weapon"]
	var character_decision: Dictionary = decisions["character"]
	# P12B installs the character defense runtime in a later isolated gate. Until
	# that owner exists, a non-empty character stage must fail before any weapon
	# resource or mastery state is committed.
	if not character_decision.is_empty():
		return false
	if weapon_decision.is_empty():
		return true
	var planned_weapon_id := _planned_defense_weapon_id(weapon_decision)
	var equipped_weapon_id: StringName = loadout_runtime.weapon_id()
	if planned_weapon_id == &"" or planned_weapon_id != equipped_weapon_id:
		return false
	var equipped_adapter := _weapon_adapter(equipped_weapon_id)
	if (
		equipped_adapter == null
		or not equipped_adapter.has_method("can_commit_damage_defense")
		or not equipped_adapter.has_method("commit_damage_defense")
	):
		return false
	if not bool(equipped_adapter.call(
		"can_commit_damage_defense",
		weapon_decision.duplicate(true),
		resolution
	)):
		return false
	return bool(equipped_adapter.call(
		"commit_damage_defense",
		weapon_decision.duplicate(true),
		resolution
	))


func _planned_defense_weapon_id(decision: Dictionary) -> StringName:
	var context_value: Variant = decision.get("commit_context", {})
	if not context_value is Dictionary:
		return &""
	var weapon_id_value: Variant = (context_value as Dictionary).get("weapon_id", &"")
	if typeof(weapon_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return &""
	return StringName(str(weapon_id_value))


func _reset_weapon_adapters() -> void:
	for adapter_value: Variant in _weapon_adapters.values():
		if adapter_value is Node and (adapter_value as Node).has_method("reset_runtime_state"):
			(adapter_value as Node).call("reset_runtime_state")


func _sync_weapon_adapter_stats() -> void:
	for weapon_id: StringName in WEAPON_ADAPTER_IDS:
		var adapter := _weapon_adapter(weapon_id)
		if adapter == null:
			continue
		var base_attack: float
		var attack_speed: float
		match weapon_id:
			&"sword", &"bow":
				base_attack = float(stats.attack)
				attack_speed = float(stats.attack_speed)
			&"gun":
				base_attack = GUN_BASE_ATTACK
				attack_speed = GUN_ATTACK_SPEED
			&"staff":
				base_attack = STAFF_BASE_ATTACK
				attack_speed = STAFF_ATTACK_SPEED
			&"gauntlets":
				base_attack = GAUNTLETS_BASE_ATTACK
				attack_speed = GAUNTLETS_ATTACK_SPEED
			_:
				continue
		adapter.set("base_attack", base_attack)
		adapter.set("attack_speed", attack_speed * _time_acceleration_multiplier)


func _ready() -> void:
	add_to_group("player")
	if not _discover_weapon_adapters():
		push_error("Player weapon adapter discovery failed")
		return
	if stats == null:
		stats = StatsResource.new()
	if not configure_run(&"standalone"):
		push_error("Player run identity configuration failed")
		return
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
	if (
		gauntlets_weapon.has_signal("payload_result_reported")
		and not gauntlets_weapon.payload_result_reported.is_connected(_on_gauntlets_payload_result_reported)
	):
		gauntlets_weapon.payload_result_reported.connect(_on_gauntlets_payload_result_reported)
	if not EventBus.hit_confirmed.is_connected(_on_weapon_replay_hit_confirmed):
		EventBus.hit_confirmed.connect(_on_weapon_replay_hit_confirmed)


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
	for adapter_value: Variant in _weapon_adapters.values():
		if adapter_value is Node2D:
			(adapter_value as Node2D).rotation = rotation_value


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


func configure_run(run_id: StringName) -> bool:
	var normalized := StringName(str(run_id).strip_edges())
	if normalized == &"" or str(normalized).contains(":"):
		return false
	if _run_id == normalized:
		return true
	if health == null or not health.has_method("configure_run"):
		return false
	if rewind_recorder == null or not rewind_recorder.has_method("configure_run"):
		return false
	if not bool(health.call("configure_run", normalized)):
		return false
	if not bool(rewind_recorder.call("configure_run", normalized)):
		return false
	_run_id = normalized
	return true


func current_run_id() -> StringName:
	return _run_id


func reset_runtime_state() -> void:
	action_state.reset_runtime_state()
	_weapon_combo_timeout_frames = 0
	_weapon_action_reward_claims.clear()
	_weapon_action_ids_by_token.clear()
	_weapon_action_generations_by_token.clear()
	_weapon_action_token_order.clear()
	_weapon_hit_fact_claims.clear()
	_weapon_resource_fact_state.clear()
	_weapon_replay_events.clear()
	_weapon_replay_capture_sequence = 0
	_applying_weapon_replay_event = false
	_weapon_replay_fact_baseline.clear()
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
		_capture_next_weapon_action_token_floor()
	_reset_weapon_adapters()
	_sync_weapon_resource_facts(&"runtime_reset")
	_clear_owned_player_arrows()
	_clear_owned_player_projectiles()
	time_manager.reset_runtime_state()
	_force_clear_time_acceleration()
	_apply_stats_to_components(true)
	health.invulnerable = false
	if rewind_recorder.has_method("clear_snapshots"):
		rewind_recorder.clear_snapshots()
	_refresh_weapon_replay_fact_baseline()


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
	_refresh_weapon_replay_fact_baseline()


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


func weapon_replay_snapshot() -> Dictionary:
	if (
		weapon_action_coordinator == null
		or not weapon_action_coordinator.has_method("snapshot")
		or loadout_runtime == null
		or not loadout_runtime.has_method("weapon_profile_snapshot")
		or time_manager == null
		or not time_manager.has_method("weapon_replay_snapshot")
	):
		return {}
	var coordinator_value: Variant = weapon_action_coordinator.call("snapshot")
	var profile_value: Variant = loadout_runtime.call("weapon_profile_snapshot")
	var time_state_value: Variant = time_manager.call("weapon_replay_snapshot")
	if (
		not coordinator_value is Dictionary
		or not profile_value is Dictionary
		or not time_state_value is Dictionary
	):
		return {}
	var coordinator := (coordinator_value as Dictionary).duplicate(true)
	var profile := profile_value as Dictionary
	if coordinator.is_empty() or profile.is_empty():
		return {}
	var event_prefix_count := _weapon_replay_event_prefix_count()
	var event_prefix_root := ReplayRecorderScript.event_prefix_root(
		_weapon_replay_events,
		event_prefix_count
	)
	if event_prefix_root.is_empty():
		return {}
	return {
		"schema_version": WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION,
		"event_prefix_count": event_prefix_count,
		"event_prefix_root": event_prefix_root,
		"weapon_id": str(coordinator.get("weapon_id", "")),
		"profile_id": str(profile.get("id", "")),
		"profile_version": int(profile.get("profile_version", 0)),
		"frame": int(coordinator.get("frame", -1)),
		"token": int(coordinator.get("token", -1)),
		"generation": int(coordinator.get("generation", -1)),
		"phase": str(coordinator.get("phase", "")),
		"coordinator": coordinator,
		"time_manager_state": (time_state_value as Dictionary).duplicate(true),
		"player_weapon_state": {
			"action_reward_claims": _weapon_action_reward_claims.duplicate(true),
			"action_ids_by_token": _weapon_action_ids_by_token.duplicate(true),
			"action_generations_by_token": _weapon_action_generations_by_token.duplicate(true),
			"action_token_order": _weapon_action_token_order.duplicate(),
			"hit_fact_claims": _weapon_hit_fact_claims.duplicate(true),
			"resource_fact_state": _weapon_resource_fact_state.duplicate(true),
			"next_token_floor": _next_weapon_action_token_floor,
			"combo_timeout_frames": _weapon_combo_timeout_frames,
		},
	}


func _refresh_weapon_replay_fact_baseline() -> void:
	var snapshot := weapon_replay_snapshot()
	_weapon_replay_fact_baseline = snapshot.duplicate(true) if not snapshot.is_empty() else {}


func restore_weapon_replay_snapshot(snapshot: Dictionary) -> bool:
	var normalized := _validated_weapon_replay_snapshot(snapshot)
	if (
		normalized.is_empty()
		or not _weapon_action_state_can_restore_replay()
		or time_manager == null
		or not time_manager.has_method("begin_weapon_replay_restore_transaction")
		or not time_manager.has_method("commit_weapon_replay_restore_transaction")
		or not time_manager.has_method("rollback_weapon_replay_restore_transaction")
		or not ReplayRecorderScript.event_prefix_matches(normalized, _weapon_replay_events)
	):
		return false
	var target_event_prefix_count := int(normalized["event_prefix_count"])
	var before := weapon_replay_snapshot()
	if before.is_empty():
		return false
	var before_events: Array[Dictionary] = _weapon_replay_events.duplicate(true)
	var before_capture_sequence := _weapon_replay_capture_sequence
	var before_coordinator := (before.get("coordinator", {}) as Dictionary).duplicate(true)
	var time_restore_transaction_token := int(time_manager.call(
		"begin_weapon_replay_restore_transaction"
	))
	if time_restore_transaction_token <= 0:
		return false
	var coordinator_target := (normalized["coordinator"] as Dictionary).duplicate(true)
	if not _restore_weapon_coordinator_replay_snapshot(coordinator_target):
		var time_transaction_rollback_ok := bool(time_manager.call(
			"rollback_weapon_replay_restore_transaction",
			time_restore_transaction_token
		))
		if (
			before_coordinator.is_empty()
			or weapon_action_coordinator.call("snapshot") != before_coordinator
			or not time_transaction_rollback_ok
		):
			_fail_closed_weapon_replay_restore(&"coordinator_target_rollback_failed")
		else:
			_restore_weapon_replay_event_log(before_events, before_capture_sequence)
		return false
	var time_target := (normalized["time_manager_state"] as Dictionary).duplicate(true)
	if not bool(time_manager.call("restore_weapon_replay_snapshot", time_target)):
		var coordinator_rollback_after_time_failure := (
			not before_coordinator.is_empty()
			and _rollback_weapon_coordinator_replay_snapshot(before_coordinator)
		)
		var time_rollback_after_time_failure := bool(time_manager.call(
			"rollback_weapon_replay_restore_transaction",
			time_restore_transaction_token
		))
		if not coordinator_rollback_after_time_failure or not time_rollback_after_time_failure:
			_fail_closed_weapon_replay_restore(&"time_restore_rollback_failed")
		else:
			_restore_weapon_replay_event_log(before_events, before_capture_sequence)
		return false
	_install_player_weapon_replay_state(normalized["player_weapon_state"] as Dictionary)
	_truncate_weapon_replay_events(
		target_event_prefix_count,
		_applying_weapon_replay_event
	)
	action_state.force_safe_reset()
	_sync_weapon_action_projection()
	_sync_weapon_replay_intent_latch()
	if weapon_replay_snapshot() == normalized:
		if bool(time_manager.call(
			"commit_weapon_replay_restore_transaction",
			time_restore_transaction_token
		)):
			_refresh_weapon_replay_fact_baseline()
			return true
		_fail_closed_weapon_replay_restore(&"time_restore_commit_failed")
		return false

	var coordinator_rollback_ok := (
		not before_coordinator.is_empty()
		and _rollback_weapon_coordinator_replay_snapshot(before_coordinator)
	)
	_install_player_weapon_replay_state(before.get("player_weapon_state", {}) as Dictionary)
	_restore_weapon_replay_event_log(before_events, before_capture_sequence)
	var time_rollback_ok := bool(time_manager.call(
		"rollback_weapon_replay_restore_transaction",
		time_restore_transaction_token
	))
	if not coordinator_rollback_ok or not time_rollback_ok:
		_fail_closed_weapon_replay_restore(&"coordinator_rollback_failed")
		return false
	action_state.force_safe_reset()
	_sync_weapon_action_projection()
	_sync_weapon_replay_intent_latch()
	if weapon_replay_snapshot() != before or _weapon_replay_events != before_events:
		_fail_closed_weapon_replay_restore(&"rollback_verification_failed")
	return false


func restore_weapon_replay_snapshot_with_event_prefix(
	snapshot: Dictionary,
	event_prefix: Array
) -> bool:
	var normalized := _validated_weapon_replay_snapshot(snapshot)
	if normalized.is_empty() or not _valid_weapon_replay_event_prefix(normalized, event_prefix):
		return false
	var before := weapon_replay_snapshot()
	if before.is_empty():
		return false
	var before_events: Array[Dictionary] = _weapon_replay_events.duplicate(true)
	var before_capture_sequence := _weapon_replay_capture_sequence
	_install_weapon_replay_event_prefix(event_prefix)
	if restore_weapon_replay_snapshot(normalized):
		return true
	_restore_weapon_replay_event_log(before_events, before_capture_sequence)
	if weapon_replay_snapshot() != before:
		if not restore_weapon_replay_snapshot(before):
			_fail_closed_weapon_replay_restore(&"event_prefix_restore_rollback_failed")
			return false
	return weapon_replay_snapshot() == before and _weapon_replay_events == before_events


func weapon_replay_events() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = _weapon_replay_events.duplicate(true)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_frame := int(left.get("frame", -1))
		var right_frame := int(right.get("frame", -1))
		if left_frame != right_frame:
			return left_frame < right_frame
		var left_priority := 0 if str(left.get("event_type", "")) == "weapon_intent" else 1
		var right_priority := 0 if str(right.get("event_type", "")) == "weapon_intent" else 1
		if left_priority != right_priority:
			return left_priority < right_priority
		return int(left.get("capture_sequence", 0)) < int(right.get("capture_sequence", 0))
	)
	var normalized: Array[Dictionary] = []
	for index: int in range(ordered.size()):
		var event := ordered[index].duplicate(true)
		event["sequence"] = index + 1
		normalized.append(event)
	return normalized


func apply_weapon_replay_event(event: Dictionary) -> bool:
	if (
		not _dictionary_has_exact_fields(event, WEAPON_REPLAY_EVENT_FIELDS)
		or ReplayRecorderScript.validate_event(event).is_empty()
		or weapon_action_coordinator == null
	):
		return false
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.snapshot()
	if int(event["frame"]) != int(coordinator_snapshot.get("frame", -1)):
		return false
	var capture_sequence := int(event["capture_sequence"])
	var capture_digest := ReplayRecorderScript.capture_event_digest(event)
	for captured_event: Dictionary in _weapon_replay_events:
		if int(captured_event.get("capture_sequence", 0)) == capture_sequence:
			return ReplayRecorderScript.capture_event_digest(captured_event) == capture_digest
	_applying_weapon_replay_event = true
	var applied := false
	var payload := event["payload"] as Dictionary
	if str(event["event_type"]) == "weapon_intent":
		applied = _apply_weapon_replay_intent_event(payload)
	else:
		applied = _apply_weapon_replay_external_fact(payload)
	_applying_weapon_replay_event = false
	if applied:
		_weapon_replay_events.append(event.duplicate(true))
		_weapon_replay_capture_sequence = maxi(
			_weapon_replay_capture_sequence,
			capture_sequence
		)
		_refresh_weapon_replay_fact_baseline()
	return applied


func _apply_weapon_replay_intent_event(payload: Dictionary) -> bool:
	var semantic_action := StringName(str(payload["semantic_action"]))
	if semantic_action not in [
		&"weapon_primary",
		&"weapon_secondary",
		&"weapon_utility",
		&"weapon_skill",
		&"weapon_ultimate",
	]:
		return false
	var intent_value: Variant = _weapon_intent_router.call(
		"normalize_edge",
		semantic_action,
		StringName(str(payload["edge"])),
		int(payload["held_frames"]),
		_weapon_semantic_input_mode(semantic_action)
	)
	if not intent_value is Dictionary or (intent_value as Dictionary).is_empty():
		return false
	var intent := intent_value as Dictionary
	if (
		str(intent.get("id", "")) != str(semantic_action)
		or str(intent.get("edge", "")) != str(payload["edge"])
		or int(intent.get("held_frames", -1)) != int(payload["held_frames"])
	):
		_reset_weapon_intent_latch(intent)
		return false
	return _submit_normalized_weapon_intent_with_context(
		intent,
		(payload["context"] as Dictionary).duplicate(true),
		false
	)


func _apply_weapon_replay_external_fact(payload: Dictionary) -> bool:
	if (
		str(payload.get("weapon_id", "")) != str(loadout_runtime.weapon_id())
		or typeof(payload.get("action_token")) != TYPE_INT
		or int(payload["action_token"]) <= 0
		or typeof(payload.get("action_generation")) != TYPE_INT
		or int(payload["action_generation"]) <= 0
		or not payload.get("data") is Dictionary
	):
		return false
	var data := payload["data"] as Dictionary
	match str(payload.get("fact_type", "")):
		"combat_damage":
			return _apply_weapon_replay_damage_fact(payload, data)
		"weapon_hit_claim", "weapon_payload_result", "weapon_resource_reward":
			return _apply_weapon_replay_state_keyframe_fact(payload, data)
		"time_interaction_claim", "time_stop_extension":
			return _apply_weapon_replay_time_fact(payload, data)
	return false


func _apply_weapon_replay_state_keyframe_fact(payload: Dictionary, data: Dictionary) -> bool:
	var state_after_value: Variant = data.get("state_after")
	if not state_after_value is Dictionary:
		return false
	var state_after := _validated_weapon_replay_snapshot(state_after_value as Dictionary)
	var current := weapon_replay_snapshot()
	if (
		state_after.is_empty()
		or current.is_empty()
		or not _weapon_replay_state_fact_transition_is_valid(
			payload,
			data,
			current,
			state_after
		)
	):
		return false
	return restore_weapon_replay_snapshot(state_after)


func _weapon_replay_state_fact_transition_is_valid(
	payload: Dictionary,
	data: Dictionary,
	state_before: Dictionary,
	state_after: Dictionary
) -> bool:
	if (
		str(payload.get("fact_type", "")) not in WEAPON_REPLAY_STATE_FACT_TYPES
		or not data.has("state_before_digest")
		or ReplayRecorderScript.value_digest(state_before)
			!= str(data.get("state_before_digest", ""))
		or not _weapon_replay_snapshot_matches_external_fact_identity(
			state_before,
			payload
		)
		or not _weapon_replay_snapshot_matches_external_fact_identity(
			state_after,
			payload
		)
	):
		return false
	match str(payload.get("fact_type", "")):
		"combat_damage":
			return _weapon_replay_damage_transition_is_valid(
				state_before,
				state_after,
				payload
			)
		"weapon_hit_claim":
			return _weapon_replay_hit_claim_transition_is_valid(
				state_before,
				state_after,
				int(payload.get("action_token", 0))
			)
		"weapon_payload_result":
			return _weapon_replay_payload_result_transition_is_valid(
				state_before,
				state_after,
				payload,
				data
			)
		"weapon_resource_reward":
			return _weapon_replay_resource_reward_transition_is_valid(
				state_before,
				state_after,
				payload,
				data
			)
	return false


func _weapon_replay_snapshot_matches_external_fact_identity(
	snapshot: Dictionary,
	payload: Dictionary
) -> bool:
	if weapon_action_coordinator == null or not weapon_action_coordinator.has_method("snapshot"):
		return false
	var normalized := _validated_weapon_replay_snapshot(snapshot)
	if normalized.is_empty() or normalized != snapshot:
		return false
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.call("snapshot")
	if (
		int(snapshot.get("frame", -1)) != int(coordinator_snapshot.get("frame", -1))
		or int(snapshot.get("event_prefix_count", -1)) != _weapon_replay_event_prefix_count()
		or not ReplayRecorderScript.event_prefix_matches(snapshot, _weapon_replay_events)
	):
		return false
	var player_value: Variant = snapshot.get("player_weapon_state")
	if not player_value is Dictionary:
		return false
	var player := player_value as Dictionary
	var generations_value: Variant = player.get("action_generations_by_token")
	var action_ids_value: Variant = player.get("action_ids_by_token")
	if not generations_value is Dictionary or not action_ids_value is Dictionary:
		return false
	var action_token := int(payload.get("action_token", 0))
	var action_generation := int(payload.get("action_generation", 0))
	var generations := generations_value as Dictionary
	var action_ids := action_ids_value as Dictionary
	return (
		action_token > 0
		and action_generation > 0
		and generations.has(action_token)
		and int(generations[action_token]) == action_generation
		and action_ids.has(action_token)
		and not str(action_ids[action_token]).is_empty()
	)


func _weapon_replay_hit_claim_transition_is_valid(
	state_before: Dictionary,
	state_after: Dictionary,
	action_token: int
) -> bool:
	if action_token <= 0 or state_before.is_empty() or state_after.is_empty():
		return false
	var before_player_value: Variant = state_before.get("player_weapon_state")
	if not before_player_value is Dictionary:
		return false
	var before_player := before_player_value as Dictionary
	var before_claims_value: Variant = before_player.get("hit_fact_claims")
	if not before_claims_value is Dictionary:
		return false
	var before_claims := before_claims_value as Dictionary
	if before_claims.has(action_token):
		return false
	var expected_after := state_before.duplicate(true)
	var expected_player := expected_after["player_weapon_state"] as Dictionary
	var expected_claims := expected_player["hit_fact_claims"] as Dictionary
	expected_claims[action_token] = true
	return state_after == expected_after


func _weapon_replay_damage_transition_is_valid(
	state_before: Dictionary,
	state_after: Dictionary,
	payload: Dictionary
) -> bool:
	if state_before.is_empty() or state_after.is_empty():
		return false
	if state_before == state_after:
		return true
	var expected_after := state_before.duplicate(true)
	var weapon_id := str(payload.get("weapon_id", ""))
	var action_token := int(payload.get("action_token", 0))
	match weapon_id:
		"sword":
			if not _weapon_replay_project_sword_damage(expected_after, state_after):
				return false
		"gun":
			if not _weapon_replay_project_gun_damage(
				expected_after,
				state_after,
				action_token
			):
				return false
		"staff":
			if not _weapon_replay_project_staff_damage(
				expected_after,
				state_after,
				action_token,
				int(payload.get("action_generation", 0))
			):
				return false
		"gauntlets":
			if not _weapon_replay_project_gauntlets_damage(
				expected_after,
				state_after,
				action_token,
				int(payload.get("action_generation", 0))
			):
				return false
		_:
			return false
	return state_after == expected_after


func _weapon_replay_project_sword_damage(
	expected_after: Dictionary,
	state_after: Dictionary
) -> bool:
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	var expected_adapter_value: Variant = expected_runtime.get("launch_adapter")
	var after_adapter_value: Variant = after_runtime.get("launch_adapter")
	if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
		return false
	var expected_adapter := expected_adapter_value as Dictionary
	var after_adapter := after_adapter_value as Dictionary
	var before_payloads_value: Variant = expected_adapter.get("payloads")
	var after_payloads_value: Variant = after_adapter.get("payloads")
	if not before_payloads_value is Array or not after_payloads_value is Array:
		return false
	var before_payloads := before_payloads_value as Array
	var after_payloads := after_payloads_value as Array
	if before_payloads.size() != after_payloads.size():
		return false
	var projected_payloads := before_payloads.duplicate(true)
	var changed_payloads := 0
	for index: int in range(before_payloads.size()):
		if not before_payloads[index] is Dictionary or not after_payloads[index] is Dictionary:
			return false
		var before_payload := before_payloads[index] as Dictionary
		var after_payload := after_payloads[index] as Dictionary
		if before_payload == after_payload:
			continue
		var before_keys_value: Variant = before_payload.get("hit_target_keys")
		var after_keys_value: Variant = after_payload.get("hit_target_keys")
		if (
			not before_keys_value is Array
			or not after_keys_value is Array
			or not _weapon_replay_string_array_has_single_append(
				before_keys_value as Array,
				after_keys_value as Array
			)
		):
			return false
		var projected_payload := before_payload.duplicate(true)
		projected_payload["hit_target_keys"] = (after_keys_value as Array).duplicate()
		if projected_payload != after_payload:
			return false
		projected_payloads[index] = projected_payload
		changed_payloads += 1
	if changed_payloads != 1:
		return false
	expected_adapter["payloads"] = projected_payloads
	return true


func _weapon_replay_project_gun_damage(
	expected_after: Dictionary,
	state_after: Dictionary,
	action_token: int
) -> bool:
	if action_token <= 0:
		return false
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	var expected_adapter_value: Variant = expected_runtime.get("adapter_snapshot")
	var after_adapter_value: Variant = after_runtime.get("adapter_snapshot")
	if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
		return false
	var expected_adapter := expected_adapter_value as Dictionary
	var after_adapter := after_adapter_value as Dictionary
	var token_key := str(action_token)
	var claim_key := "%d:hit_confirmed" % action_token
	var before_claims_by_token_value: Variant = expected_adapter.get("action_claims_by_token")
	var after_claims_by_token_value: Variant = after_adapter.get("action_claims_by_token")
	if not before_claims_by_token_value is Dictionary or not after_claims_by_token_value is Dictionary:
		return false
	var projected_claims_by_token := (before_claims_by_token_value as Dictionary).duplicate(true)
	var after_claims_by_token := after_claims_by_token_value as Dictionary
	var claim_added := false
	if projected_claims_by_token != after_claims_by_token:
		if not projected_claims_by_token.has(token_key) or not after_claims_by_token.has(token_key):
			return false
		var before_token_claims := projected_claims_by_token[token_key] as Dictionary
		var after_token_claims := after_claims_by_token[token_key] as Dictionary
		if not _weapon_replay_dictionary_has_single_true_addition(
			before_token_claims,
			after_token_claims,
			claim_key
		):
			return false
		projected_claims_by_token[token_key] = after_token_claims.duplicate(true)
		claim_added = true
	expected_adapter["action_claims_by_token"] = projected_claims_by_token
	var hit_changes := 0
	for payload_field: String in ["prepared_projectiles", "owned_projectiles"]:
		var before_payloads_value: Variant = expected_adapter.get(payload_field)
		var after_payloads_value: Variant = after_adapter.get(payload_field)
		if not before_payloads_value is Array or not after_payloads_value is Array:
			return false
		var before_payloads := before_payloads_value as Array
		var after_payloads := after_payloads_value as Array
		if before_payloads.size() != after_payloads.size():
			return false
		var projected_payloads := before_payloads.duplicate(true)
		for index: int in range(before_payloads.size()):
			if not before_payloads[index] is Dictionary or not after_payloads[index] is Dictionary:
				return false
			var before_entry := before_payloads[index] as Dictionary
			var after_entry := after_payloads[index] as Dictionary
			var before_execution_value: Variant = before_entry.get("execution")
			var after_execution_value: Variant = after_entry.get("execution")
			if not before_execution_value is Dictionary or not after_execution_value is Dictionary:
				return false
			var before_execution := before_execution_value as Dictionary
			var after_execution := after_execution_value as Dictionary
			if int(before_execution.get("action_token", 0)) != action_token:
				if before_entry != after_entry:
					return false
				continue
			var projected_execution := before_execution.duplicate(true)
			if claim_added:
				var execution_claims_value: Variant = projected_execution.get("action_claims")
				var after_execution_claims_value: Variant = after_execution.get("action_claims")
				if not execution_claims_value is Dictionary or not after_execution_claims_value is Dictionary:
					return false
				if not _weapon_replay_dictionary_has_single_true_addition(
					execution_claims_value as Dictionary,
					after_execution_claims_value as Dictionary,
					claim_key
				):
					return false
				projected_execution["action_claims"] = (
					after_execution_claims_value as Dictionary
				).duplicate(true)
			var before_hit_ids_value: Variant = before_execution.get("hit_target_ids")
			var after_hit_ids_value: Variant = after_execution.get("hit_target_ids")
			if (
				payload_field == "owned_projectiles"
				and before_hit_ids_value is Array
				and after_hit_ids_value is Array
				and _weapon_replay_integer_array_has_single_addition(
					before_hit_ids_value as Array,
					after_hit_ids_value as Array
				)
			):
				projected_execution["hit_target_ids"] = (after_hit_ids_value as Array).duplicate()
				projected_execution["hit_target_count"] = int(
					after_execution.get("hit_target_count", -1)
				)
				if int(projected_execution["hit_target_count"]) != (after_hit_ids_value as Array).size():
					return false
				hit_changes += 1
			var projected_entry := before_entry.duplicate(true)
			projected_entry["execution"] = projected_execution
			if projected_entry != after_entry:
				return false
			projected_payloads[index] = projected_entry
		expected_adapter[payload_field] = projected_payloads
	return hit_changes <= 1 and (hit_changes == 1 or claim_added)


func _weapon_replay_project_staff_damage(
	expected_after: Dictionary,
	state_after: Dictionary,
	action_token: int,
	action_generation: int
) -> bool:
	if action_token <= 0 or action_generation <= 0:
		return false
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	var expected_adapter_value: Variant = expected_runtime.get("adapter_snapshot")
	var after_adapter_value: Variant = after_runtime.get("adapter_snapshot")
	if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
		return false
	var expected_adapter := expected_adapter_value as Dictionary
	var after_adapter := after_adapter_value as Dictionary
	var before_payloads_value: Variant = expected_adapter.get("owned_payloads")
	var after_payloads_value: Variant = after_adapter.get("owned_payloads")
	if not before_payloads_value is Array or not after_payloads_value is Array:
		return false
	var before_payloads := before_payloads_value as Array
	var after_payloads := after_payloads_value as Array
	if before_payloads.size() != after_payloads.size():
		return false
	var projected_payloads := before_payloads.duplicate(true)
	var changed_payloads := 0
	for index: int in range(before_payloads.size()):
		if not before_payloads[index] is Dictionary or not after_payloads[index] is Dictionary:
			return false
		var before_entry := before_payloads[index] as Dictionary
		var after_entry := after_payloads[index] as Dictionary
		if before_entry == after_entry:
			continue
		if (
			int(before_entry.get("token", 0)) != action_token
			or int(before_entry.get("generation", 0)) != action_generation
			or before_entry.get("kind") != after_entry.get("kind")
			or before_entry.get("token") != after_entry.get("token")
			or before_entry.get("generation") != after_entry.get("generation")
		):
			return false
		var before_execution_value: Variant = before_entry.get("execution")
		var after_execution_value: Variant = after_entry.get("execution")
		if not before_execution_value is Dictionary or not after_execution_value is Dictionary:
			return false
		var before_execution := before_execution_value as Dictionary
		var after_execution := after_execution_value as Dictionary
		var projected_execution := before_execution.duplicate(true)
		var projected_entry := before_entry.duplicate(true)
		match str(before_entry.get("kind", "")):
			"projectile":
				var before_position_value: Variant = before_entry.get("global_position")
				var after_position_value: Variant = after_entry.get("global_position")
				var direction_value: Variant = before_execution.get("direction")
				if (
					not before_position_value is Vector2
					or not after_position_value is Vector2
					or not direction_value is Vector2
				):
					return false
				var before_distance := float(before_execution.get("distance_travelled", NAN))
				var after_distance := float(after_execution.get("distance_travelled", NAN))
				if (
					not is_finite(before_distance)
					or not is_finite(after_distance)
					or after_distance + 0.001 < before_distance
				):
					return false
				var distance_delta := after_distance - before_distance
				var expected_position := (
					(before_position_value as Vector2)
					+ (direction_value as Vector2).normalized() * distance_delta
				)
				if not expected_position.is_equal_approx(after_position_value as Vector2):
					return false
				projected_entry["global_position"] = after_position_value
				projected_execution["distance_travelled"] = after_distance
				var before_claims_value: Variant = before_execution.get("damage_claims")
				var after_claims_value: Variant = after_execution.get("damage_claims")
				if not before_claims_value is Array or not after_claims_value is Array:
					return false
				if before_claims_value != after_claims_value:
					var added_claim := _weapon_replay_single_added_string(
						before_claims_value as Array,
						after_claims_value as Array
					)
					if not _weapon_replay_staff_projectile_damage_claim_is_valid(
						added_claim,
						before_execution
					):
						return false
					var projected_claims := (before_claims_value as Array).duplicate()
					projected_claims.append(added_claim)
					projected_claims.sort()
					projected_execution["damage_claims"] = projected_claims
			"zone":
				if before_entry.get("global_position") != after_entry.get("global_position"):
					return false
				var before_claims_value: Variant = before_execution.get("claims")
				var after_claims_value: Variant = after_execution.get("claims")
				if not before_claims_value is Array or not after_claims_value is Array:
					return false
				var added_claim := _weapon_replay_single_added_string(
					before_claims_value as Array,
					after_claims_value as Array
				)
				var before_frame := int(before_execution.get("execution_frame", -1))
				var after_frame := int(after_execution.get("execution_frame", -1))
				var duration_frames := int(before_execution.get("duration_frames", -1))
				var after_fractional := float(after_execution.get("fractional_frames", NAN))
				if (
					not _weapon_replay_staff_zone_damage_claim_is_valid(
						added_claim,
						before_execution,
						after_frame
					)
					or
					before_frame < 0
					or after_frame < before_frame
					or after_frame > duration_frames
					or not is_finite(after_fractional)
					or after_fractional < 0.0
					or after_fractional >= 1.0
				):
					return false
				projected_execution["execution_frame"] = after_frame
				projected_execution["fractional_frames"] = after_fractional
				var projected_claims := (before_claims_value as Array).duplicate()
				projected_claims.append(added_claim)
				projected_claims.sort()
				projected_execution["claims"] = projected_claims
			_:
				return false
		projected_entry["execution"] = projected_execution
		if projected_entry != after_entry:
			return false
		projected_payloads[index] = projected_entry
		changed_payloads += 1
	if changed_payloads != 1:
		return false
	expected_adapter["owned_payloads"] = projected_payloads
	return true


func _weapon_replay_project_gauntlets_damage(
	expected_after: Dictionary,
	state_after: Dictionary,
	action_token: int,
	_action_generation: int
) -> bool:
	if action_token <= 0:
		return false
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	var expected_adapter_value: Variant = expected_runtime.get("adapter")
	var after_adapter_value: Variant = after_runtime.get("adapter")
	if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
		return false
	var expected_adapter := expected_adapter_value as Dictionary
	var after_adapter := after_adapter_value as Dictionary
	var before_payloads_value: Variant = expected_adapter.get("owned_payloads")
	var after_payloads_value: Variant = after_adapter.get("owned_payloads")
	if not before_payloads_value is Array or not after_payloads_value is Array:
		return false
	var before_payloads := before_payloads_value as Array
	var after_payloads := after_payloads_value as Array
	if before_payloads.size() != after_payloads.size():
		return false
	var projected_payloads := before_payloads.duplicate(true)
	var changed_payloads := 0
	for index: int in range(before_payloads.size()):
		if not before_payloads[index] is Dictionary or not after_payloads[index] is Dictionary:
			return false
		var before_entry := before_payloads[index] as Dictionary
		var after_entry := after_payloads[index] as Dictionary
		if before_entry == after_entry:
			continue
		if (
			int(before_entry.get("token", 0)) != action_token
			or int(before_entry.get("generation", 0)) <= 0
			or before_entry.get("payload_type") != after_entry.get("payload_type")
			or before_entry.get("token") != after_entry.get("token")
			or before_entry.get("generation") != after_entry.get("generation")
			or before_entry.get("global_position") != after_entry.get("global_position")
		):
			return false
		var before_snapshot_value: Variant = before_entry.get("snapshot")
		var after_snapshot_value: Variant = after_entry.get("snapshot")
		if not before_snapshot_value is Dictionary or not after_snapshot_value is Dictionary:
			return false
		var before_snapshot := before_snapshot_value as Dictionary
		var after_snapshot := after_snapshot_value as Dictionary
		var projected_snapshot := before_snapshot.duplicate(true)
		if str(before_entry.get("payload_type", "")) == "hit":
			var before_ids_value: Variant = before_snapshot.get("hit_target_ids")
			var after_ids_value: Variant = after_snapshot.get("hit_target_ids")
			if (
				not before_ids_value is Array
				or not after_ids_value is Array
				or not _weapon_replay_integer_array_has_single_addition(
					before_ids_value as Array,
					after_ids_value as Array
				)
			):
				return false
			projected_snapshot["hit_target_ids"] = (after_ids_value as Array).duplicate()
			var before_frame := int(before_snapshot.get("execution_frame", -1))
			var after_frame := int(after_snapshot.get("execution_frame", -1))
			var active_frames := int(before_snapshot.get("active_frames", 0))
			var after_fractional := float(after_snapshot.get("fractional_frames", NAN))
			if (
				before_frame < 0
				or after_frame < before_frame
				or active_frames <= 0
				or after_frame >= active_frames
				or int(after_snapshot.get("remaining_frames", -1)) != active_frames - after_frame
				or not is_finite(after_fractional)
				or after_fractional < 0.0
				or after_fractional >= 1.0
			):
				return false
			projected_snapshot["execution_frame"] = after_frame
			projected_snapshot["remaining_frames"] = active_frames - after_frame
			projected_snapshot["fractional_frames"] = after_fractional
			var appended_target_id := _weapon_replay_single_added_integer(
				before_ids_value as Array,
				after_ids_value as Array
			)
			var parameters_value: Variant = before_snapshot.get("parameters", {})
			if appended_target_id <= 0 or not parameters_value is Dictionary:
				return false
			if bool((parameters_value as Dictionary).get("shared_damage_claim", false)):
				var payload_generation := int(before_entry.get("generation", 0))
				var damage_claims_value: Variant = expected_adapter.get("damage_claims")
				var damage_order_value: Variant = expected_adapter.get("damage_claim_order")
				if not damage_claims_value is Dictionary or not damage_order_value is Array:
					return false
				if not _weapon_replay_apply_bounded_true_claim(
					damage_claims_value as Dictionary,
					damage_order_value as Array,
					"%d:%d:%d" % [action_token, payload_generation, appended_target_id],
					WEAPON_REPLAY_CALLBACK_CLAIM_LIMIT
				):
					return false
		elif str(before_entry.get("payload_type", "")) == "zone":
			var before_claims_value: Variant = before_snapshot.get("damage_claim_keys")
			var after_claims_value: Variant = after_snapshot.get("damage_claim_keys")
			if (
				not before_claims_value is Array
				or not after_claims_value is Array
				or not _weapon_replay_string_array_has_single_addition(
					before_claims_value as Array,
					after_claims_value as Array
				)
			):
				return false
			var added_claim := _weapon_replay_single_added_string(
				before_claims_value as Array,
				after_claims_value as Array
			)
			var claim_parts := added_claim.split(":", false)
			var tick_interval := int(before_snapshot.get("tick_interval_frames", 0))
			var duration_frames := int(before_snapshot.get("duration_frames", 0))
			var before_frame := int(before_snapshot.get("execution_frame", -1))
			var after_frame := int(after_snapshot.get("execution_frame", -1))
			var after_fractional := float(after_snapshot.get("fractional_frames", NAN))
			if (
				claim_parts.size() != 2
				or not str(claim_parts[0]).is_valid_int()
				or not str(claim_parts[1]).is_valid_int()
				or int(claim_parts[0]) <= 0
				or int(claim_parts[1]) <= 0
				or tick_interval <= 0
				or duration_frames <= 0
				or after_frame != int(claim_parts[0]) * tick_interval
				or after_frame < before_frame
				or after_frame >= duration_frames
				or int(after_snapshot.get("remaining_frames", -1)) != duration_frames - after_frame
				or not is_finite(after_fractional)
				or after_fractional < 0.0
				or after_fractional >= 1.0
			):
				return false
			projected_snapshot["execution_frame"] = after_frame
			projected_snapshot["remaining_frames"] = duration_frames - after_frame
			projected_snapshot["fractional_frames"] = after_fractional
			projected_snapshot["damage_claim_keys"] = (after_claims_value as Array).duplicate()
		else:
			return false
		var projected_entry := before_entry.duplicate(true)
		projected_entry["snapshot"] = projected_snapshot
		if projected_entry != after_entry:
			return false
		projected_payloads[index] = projected_entry
		changed_payloads += 1
	if changed_payloads != 1:
		return false
	expected_adapter["owned_payloads"] = projected_payloads
	return true


func _weapon_replay_payload_result_transition_is_valid(
	state_before: Dictionary,
	state_after: Dictionary,
	payload: Dictionary,
	data: Dictionary
) -> bool:
	if state_before.is_empty() or state_after.is_empty():
		return false
	var result_value: Variant = data.get("result")
	var payload_generation := int(data.get("payload_generation", 0))
	if not result_value is Dictionary or payload_generation <= 0:
		return false
	var expected_after := state_before.duplicate(true)
	match str(payload.get("weapon_id", "")):
		"staff":
			if not _weapon_replay_project_staff_payload_result(
				expected_after,
				state_after,
				int(payload.get("action_token", 0)),
				payload_generation,
				result_value as Dictionary
			):
				return false
		"gauntlets":
			if not _weapon_replay_project_gauntlets_payload_result(
				expected_after,
				state_after,
				int(payload.get("action_token", 0)),
				payload_generation,
				result_value as Dictionary
			):
				return false
		_:
			return false
	return state_after == expected_after


func _weapon_replay_project_staff_payload_result(
	expected_after: Dictionary,
	state_after: Dictionary,
	action_token: int,
	payload_generation: int,
	result: Dictionary
) -> bool:
	var claim_id := str(result.get("claim_id", ""))
	if action_token <= 0 or payload_generation <= 0 or claim_id.is_empty():
		return false
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	if expected_runtime.is_empty() or after_runtime.is_empty():
		return false
	var normalized := _weapon_replay_normalize_staff_runtime_result(result)
	if not bool(normalized.get("valid", false)):
		return false
	var runtime_response: Dictionary = {}
	if bool(normalized.get("applies", false)):
		if weapon_runtime == null or not weapon_runtime.has_method("project_replay_payload_result"):
			return false
		var projection_value: Variant = weapon_runtime.call(
			"project_replay_payload_result",
			expected_runtime.duplicate(true),
			action_token,
			payload_generation,
			(normalized.get("result", {}) as Dictionary).duplicate(true)
		)
		if not projection_value is Dictionary:
			return false
		var projection := projection_value as Dictionary
		var projected_snapshot_value: Variant = projection.get("snapshot")
		var projected_result_value: Variant = projection.get("payload_result", {})
		if (
			not bool(projection.get("ok", false))
			or not projected_snapshot_value is Dictionary
			or not projected_result_value is Dictionary
		):
			return false
		expected_runtime = projected_snapshot_value as Dictionary
		runtime_response = (projected_result_value as Dictionary).duplicate(true)
	var expected_adapter_value: Variant = expected_runtime.get("adapter_snapshot")
	var after_adapter_value: Variant = after_runtime.get("adapter_snapshot")
	if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
		return false
	var expected_adapter := expected_adapter_value as Dictionary
	var after_adapter := after_adapter_value as Dictionary
	var callback_claims_value: Variant = expected_adapter.get("callback_claims")
	var callback_order_value: Variant = expected_adapter.get("callback_claim_order")
	if not callback_claims_value is Dictionary or not callback_order_value is Array:
		return false
	var claim_key := "%d:%d:%s" % [action_token, payload_generation, claim_id]
	if not _weapon_replay_apply_bounded_true_claim(
		callback_claims_value as Dictionary,
		callback_order_value as Array,
		claim_key,
		WEAPON_REPLAY_CALLBACK_CLAIM_LIMIT
	):
		return false
	if not _weapon_replay_project_staff_payload_adapter(
		expected_adapter,
		after_adapter,
		action_token,
		payload_generation,
		result,
		runtime_response
	):
		return false
	expected_runtime["adapter_snapshot"] = expected_adapter
	var expected_player_value: Variant = expected_after.get("player_weapon_state")
	if not expected_player_value is Dictionary:
		return false
	var expected_player := expected_player_value as Dictionary
	var resource_facts_value: Variant = expected_player.get("resource_fact_state")
	if not resource_facts_value is Dictionary:
		return false
	var resource_facts := resource_facts_value as Dictionary
	var prior_mana_value: Variant = resource_facts.get("mana")
	if not prior_mana_value is Dictionary:
		return false
	var prior_mana := prior_mana_value as Dictionary
	var projected_mana := float(expected_runtime.get("mana", NAN))
	var mana_maximum := float(prior_mana.get("maximum", NAN))
	if (
		not is_finite(projected_mana)
		or not is_finite(mana_maximum)
		or projected_mana < 0.0
		or mana_maximum <= 0.0
		or projected_mana > mana_maximum
	):
		return false
	resource_facts["mana"] = {
		"current": projected_mana,
		"maximum": mana_maximum,
	}
	var expected_coordinator := expected_after["coordinator"] as Dictionary
	expected_coordinator["runtime"] = expected_runtime
	return true


func _weapon_replay_normalize_staff_runtime_result(result: Dictionary) -> Dictionary:
	var result_type := str(result.get("type", ""))
	if result_type not in [
		"damage_resolved", "hit_confirmed", "terminal_miss", "zone_tick",
		"combination_resolved", "ultimate_tick", "zone_complete",
	]:
		return {"valid": false}
	if result_type not in ["damage_resolved", "hit_confirmed", "terminal_miss"]:
		return {"valid": true, "applies": false, "result": {}}
	var descriptor_id := str(result.get("descriptor_id", ""))
	var outcome_index_value: Variant = result.get("outcome_index")
	var element_id := str(result.get("element", result.get("element_id", "")))
	var hit_value: Variant = result.get("hit", result_type == "hit_confirmed")
	var damage_value: Variant = result.get("damage", 0.0)
	if (
		descriptor_id.is_empty()
		or typeof(outcome_index_value) != TYPE_INT
		or int(outcome_index_value) < 0
		or element_id.is_empty()
		or typeof(hit_value) != TYPE_BOOL
		or typeof(damage_value) not in [TYPE_INT, TYPE_FLOAT]
	):
		return {"valid": false}
	var damage := float(damage_value)
	var hit := bool(hit_value)
	var target_id := int(result.get("target_id", -1))
	if not is_finite(damage) or damage < 0.0 or (hit and target_id < 0):
		return {"valid": false}
	var normalized := result.duplicate(true)
	var outcome_id := str(result.get(
		"outcome_id",
		"%s:%d" % [descriptor_id, int(outcome_index_value)]
	))
	if result_type == "damage_resolved":
		var frame_value: Variant = result.get("execution_frame")
		if typeof(frame_value) == TYPE_INT and int(frame_value) >= 0:
			outcome_id = "%s:frame:%d:%s" % [outcome_id, int(frame_value), element_id]
		else:
			outcome_id = "%s:%s:%s" % [
				outcome_id,
				str(result.get("damage_scope", "derived")),
				element_id,
			]
	normalized["outcome_id"] = outcome_id
	normalized["element"] = element_id
	normalized["target_id"] = target_id
	normalized["terminal"] = result_type != "damage_resolved"
	normalized["damage"] = damage
	normalized["hit"] = hit
	normalized["resource_only"] = result_type == "damage_resolved"
	if result_type == "hit_confirmed" and hit and element_id == "lightning":
		var chain := _weapon_replay_valid_staff_chain_material(result)
		if not bool(chain.get("ok", false)):
			return {"valid": false}
		normalized["chain_target_ids"] = (chain.get("target_ids", []) as Array).duplicate()
		normalized["chain_origin_positions"] = (chain.get("positions", []) as Array).duplicate()
	return {"valid": true, "applies": true, "result": normalized}


func _weapon_replay_valid_staff_chain_material(result: Dictionary) -> Dictionary:
	var target_ids_value: Variant = result.get("chain_target_ids", [])
	var impacts_value: Variant = result.get("chain_target_impacts", [])
	if not target_ids_value is Array or not impacts_value is Array:
		return {"ok": false}
	var target_ids: Array[int] = []
	var seen: Dictionary = {}
	for target_id_value: Variant in target_ids_value as Array:
		if typeof(target_id_value) != TYPE_INT or int(target_id_value) <= 0 or seen.has(int(target_id_value)):
			return {"ok": false}
		seen[int(target_id_value)] = true
		target_ids.append(int(target_id_value))
	var impact_ids: Array[int] = []
	var positions: Array[Vector2] = []
	seen.clear()
	for impact_value: Variant in impacts_value as Array:
		if not impact_value is Dictionary:
			return {"ok": false}
		var impact := impact_value as Dictionary
		var target_id_value: Variant = impact.get("target_id")
		var position_value: Variant = impact.get("impact_position")
		if typeof(target_id_value) != TYPE_INT or not position_value is Vector2:
			return {"ok": false}
		var target_id := int(target_id_value)
		var position := position_value as Vector2
		if (
			target_id <= 0
			or seen.has(target_id)
			or not is_finite(position.x)
			or not is_finite(position.y)
		):
			return {"ok": false}
		seen[target_id] = true
		impact_ids.append(target_id)
		positions.append(position)
	return (
		{"ok": true, "target_ids": target_ids, "positions": positions}
		if impact_ids == target_ids
		else {"ok": false}
	)


func _weapon_replay_project_staff_payload_adapter(
	expected_adapter: Dictionary,
	after_adapter: Dictionary,
	action_token: int,
	payload_generation: int,
	result: Dictionary,
	runtime_response: Dictionary
) -> bool:
	var payloads_value: Variant = expected_adapter.get("owned_payloads")
	if not payloads_value is Array:
		return false
	var projected_payloads := (payloads_value as Array).duplicate(true)
	var source_index := _weapon_replay_staff_payload_index(
		projected_payloads,
		action_token,
		payload_generation,
		str(result.get("descriptor_id", "")),
		int(result.get("outcome_index", -1))
	)
	if source_index < 0 or not projected_payloads[source_index] is Dictionary:
		return false
	var source_entry := (projected_payloads[source_index] as Dictionary).duplicate(true)
	var source_execution_value: Variant = source_entry.get("execution")
	if not source_execution_value is Dictionary:
		return false
	var source_execution := source_execution_value as Dictionary
	if not _weapon_replay_project_staff_source_result(
		source_entry,
		after_adapter,
		result,
		source_index
	):
		return false
	var result_type := str(result.get("type", ""))
	var terminal := bool(result.get(
		"terminal",
		result_type in ["hit_confirmed", "terminal_miss", "zone_complete"]
	))
	if terminal:
		projected_payloads.remove_at(source_index)
	else:
		projected_payloads[source_index] = source_entry
	var result_zone := _weapon_replay_staff_result_zone_snapshot(source_entry, result)
	if bool(result_zone.get("invalid", false)):
		return false
	if not result_zone.is_empty():
		result_zone.erase("invalid")
		projected_payloads.append(result_zone)
	var combo_value: Variant = runtime_response.get("combo", {})
	if not combo_value is Dictionary:
		return false
	if not (combo_value as Dictionary).is_empty():
		var combo_zone := _weapon_replay_staff_combo_zone_snapshot(
			source_entry,
			result,
			combo_value as Dictionary
		)
		if combo_zone.is_empty():
			return false
		projected_payloads.append(combo_zone)
	expected_adapter["owned_payloads"] = projected_payloads
	return expected_adapter == after_adapter


func _weapon_replay_staff_payload_index(
	payloads: Array,
	action_token: int,
	payload_generation: int,
	descriptor_id: String,
	outcome_index: int
) -> int:
	if descriptor_id.is_empty() or outcome_index < 0:
		return -1
	var matched := -1
	for index: int in range(payloads.size()):
		if not payloads[index] is Dictionary:
			return -1
		var entry := payloads[index] as Dictionary
		var execution_value: Variant = entry.get("execution")
		if not execution_value is Dictionary:
			continue
		var execution := execution_value as Dictionary
		if (
			int(entry.get("token", 0)) == action_token
			and int(entry.get("generation", 0)) == payload_generation
			and str(execution.get("descriptor_id", "")) == descriptor_id
			and int(execution.get("outcome_index", -1)) == outcome_index
		):
			if matched >= 0:
				return -1
			matched = index
	return matched


func _weapon_replay_project_staff_source_result(
	source_entry: Dictionary,
	after_adapter: Dictionary,
	result: Dictionary,
	source_index: int
) -> bool:
	var execution_value: Variant = source_entry.get("execution")
	var after_payloads_value: Variant = after_adapter.get("owned_payloads")
	if not execution_value is Dictionary or not after_payloads_value is Array:
		return false
	var execution := (execution_value as Dictionary).duplicate(true)
	var result_type := str(result.get("type", ""))
	var terminal := bool(result.get(
		"terminal",
		result_type in ["hit_confirmed", "terminal_miss", "zone_complete"]
	))
	if terminal:
		return true
	var after_index := _weapon_replay_staff_payload_index(
		after_payloads_value as Array,
		int(source_entry.get("token", 0)),
		int(source_entry.get("generation", 0)),
		str(execution.get("descriptor_id", "")),
		int(execution.get("outcome_index", -1))
	)
	if after_index < 0 or not (after_payloads_value as Array)[after_index] is Dictionary:
		return false
	var after_entry := (after_payloads_value as Array)[after_index] as Dictionary
	var after_execution_value: Variant = after_entry.get("execution")
	if not after_execution_value is Dictionary:
		return false
	var after_execution := after_execution_value as Dictionary
	if source_entry.get("global_position") != after_entry.get("global_position"):
		return false
	match str(source_entry.get("kind", "")):
		"projectile":
			if result_type == "damage_resolved":
				var claims_value: Variant = execution.get("damage_claims")
				var claim_id := str(result.get("claim_id", ""))
				if not claims_value is Array or claim_id.is_empty():
					return false
				var claims := (claims_value as Array).duplicate()
				if not claims.has(claim_id):
					if not _weapon_replay_staff_projectile_damage_claim_is_valid(claim_id, execution):
						return false
					claims.append(claim_id)
					claims.sort()
				execution["damage_claims"] = claims
		"zone":
			var frame_value: Variant = result.get("execution_frame", execution.get("execution_frame"))
			if typeof(frame_value) != TYPE_INT:
				return false
			var frame := int(frame_value)
			var before_frame := int(execution.get("execution_frame", -1))
			var duration := int(execution.get("duration_frames", -1))
			var fractional := float(after_execution.get("fractional_frames", NAN))
			if (
				frame < before_frame
				or frame > duration
				or not is_finite(fractional)
				or fractional < 0.0
				or fractional >= 1.0
			):
				return false
			execution["execution_frame"] = frame
			execution["fractional_frames"] = fractional
			var claims_value: Variant = execution.get("claims")
			if not claims_value is Array:
				return false
			var claims := (claims_value as Array).duplicate()
			var source_claim := _weapon_replay_staff_source_result_claim(result)
			if not source_claim.is_empty() and not claims.has(source_claim):
				claims.append(source_claim)
				claims.sort()
			execution["claims"] = claims
		_:
			return false
	source_entry["execution"] = execution
	return source_entry == after_entry or terminal or source_index >= 0


func _weapon_replay_staff_source_result_claim(result: Dictionary) -> String:
	var result_type := str(result.get("type", ""))
	var frame := int(result.get("execution_frame", -1))
	match result_type:
		"damage_resolved":
			return str(result.get("claim_id", ""))
		"zone_tick":
			return (
				"combination_tick:%d" % frame
				if str(result.get("mode", "")) == "combination"
				else "zone_tick:%d" % frame
			)
		"combination_resolved":
			return "combination_resolved"
		"ultimate_tick":
			return "ultimate_tick:%d" % int(result.get("tick_index", -1))
		"zone_complete":
			return "zone_complete"
	return ""


func _weapon_replay_staff_result_zone_snapshot(
	source_entry: Dictionary,
	result: Dictionary
) -> Dictionary:
	var spawn_value: Variant = result.get("spawn_zone", {})
	if not spawn_value is Dictionary:
		return {"invalid": true}
	var spawn := spawn_value as Dictionary
	if spawn.is_empty():
		return {}
	var source_execution_value: Variant = source_entry.get("execution")
	if not source_execution_value is Dictionary:
		return {"invalid": true}
	var source_execution := source_execution_value as Dictionary
	var effect_value: Variant = source_execution.get("effect_descriptor", {})
	if str(source_execution.get("element_id", "")) != "ice" or not effect_value is Dictionary:
		return {"invalid": true}
	var effect := effect_value as Dictionary
	var expected_descriptor := {
		"mode": "ice_zone",
		"descriptor_id": "%s:ice_zone" % str(source_execution.get("descriptor_id", "")),
		"parameters": {
			"radius_tiles": float(effect.get("zone_radius_tiles", 0.0)),
			"duration_frames": int(effect.get("zone_duration_frames", 0)),
			"tick_interval_frames": int(effect.get("zone_tick_interval_frames", 0)),
			"damage_multiplier": float(effect.get("zone_damage_multiplier", 0.0)),
			"move_speed_multiplier": float(effect.get("move_speed_multiplier", 1.0)),
			"attack_speed_multiplier": float(effect.get("attack_speed_multiplier", 1.0)),
			"freeze_duration_frames": int(effect.get("freeze_duration_frames", 0)),
		},
	}
	if spawn != expected_descriptor:
		return {"invalid": true}
	return _weapon_replay_staff_zone_snapshot(
		source_entry,
		result,
		str(expected_descriptor["descriptor_id"]),
		"ice_zone",
		expected_descriptor["parameters"] as Dictionary
	)


func _weapon_replay_staff_combo_zone_snapshot(
	source_entry: Dictionary,
	result: Dictionary,
	combination: Dictionary
) -> Dictionary:
	var source_execution_value: Variant = source_entry.get("execution")
	var raw_combination_value: Variant = result.get("combination", {})
	if not source_execution_value is Dictionary or not raw_combination_value is Dictionary:
		return {}
	var source_execution := source_execution_value as Dictionary
	var raw_combination := raw_combination_value as Dictionary
	var source_combination_value: Variant = source_execution.get("combination", {})
	if not source_combination_value is Dictionary or raw_combination != (source_combination_value as Dictionary):
		return {}
	if str(raw_combination.get("combo_id", "")) != str(combination.get("combo_id", "")):
		return {}
	var parameters_value: Variant = combination.get("parameters", {})
	if not parameters_value is Dictionary:
		return {}
	var combo_parameters := (parameters_value as Dictionary).duplicate(true)
	var spatial_combo := combination.duplicate(true)
	spatial_combo["rift_interaction"] = (
		(raw_combination.get("rift_interaction", {}) as Dictionary).duplicate(true)
		if raw_combination.get("rift_interaction", {}) is Dictionary
		else {}
	)
	var rift: Dictionary = {}
	if staff_weapon != null and staff_weapon.has_method("_intersecting_rift_interaction"):
		var rift_value: Variant = staff_weapon.call(
			"_intersecting_rift_interaction",
			spatial_combo,
			result
		)
		if rift_value is Dictionary:
			rift = (rift_value as Dictionary).duplicate(true)
	if not rift.is_empty():
		_weapon_replay_scale_staff_combo_radii(
			combo_parameters,
			float(rift.get("area_multiplier", 1.0))
		)
		combo_parameters["time_damage_multiplier"] = float(rift.get("time_damage_multiplier", 0.0))
		combo_parameters["rift_source_generation"] = int(rift.get("source_generation", 0))
	var combo_id := str(combination.get("combo_id", ""))
	return _weapon_replay_staff_zone_snapshot(
		source_entry,
		result,
		"%s:%s" % [str(result.get("descriptor_id", "staff")), combo_id],
		"combination",
		{
			"combo_id": combo_id,
			"combo_kind": str(combination.get("kind", "")),
			"combo_parameters": combo_parameters,
		}
	)


func _weapon_replay_staff_zone_snapshot(
	source_entry: Dictionary,
	result: Dictionary,
	descriptor_id: String,
	mode: String,
	parameters: Dictionary
) -> Dictionary:
	var source_execution_value: Variant = source_entry.get("execution")
	var source_position_value: Variant = source_entry.get("global_position")
	if not source_execution_value is Dictionary or not source_position_value is Vector2:
		return {}
	var source_execution := source_execution_value as Dictionary
	var position := source_position_value as Vector2
	var impact_value: Variant = result.get("impact_position")
	if impact_value is Vector2:
		var impact := impact_value as Vector2
		if is_finite(impact.x) and is_finite(impact.y):
			position = impact
	var execution := {
		"action_token": int(source_entry.get("token", 0)),
		"generation": int(source_entry.get("generation", 0)),
		"source_action_id": str(source_execution.get("source_action_id", "")),
		"descriptor_id": descriptor_id,
		"outcome_index": int(result.get("outcome_index", -1)),
		"deterministic_seed": int(result.get(
			"deterministic_seed",
			source_execution.get("deterministic_seed", 0)
		)),
		"mode": mode,
		"parameters": parameters.duplicate(true),
		"base_attack": float(source_execution.get("base_attack", 0.0)),
		"boss_conversion": (
			(source_execution.get("boss_conversion", {}) as Dictionary).duplicate(true)
			if source_execution.get("boss_conversion", {}) is Dictionary
			else {}
		),
		"status_source_id": "staff:%d:%s:%d" % [
			int(source_entry.get("token", 0)),
			descriptor_id,
			int(result.get("outcome_index", -1)),
		],
	}
	var zone := StaffSpellZoneScript.new()
	if not bool(zone.call("configure_execution", execution)):
		zone.free()
		return {}
	var snapshot := (zone.call("execution_snapshot") as Dictionary).duplicate(true)
	zone.call("reset_execution_state")
	zone.free()
	return {
		"kind": "zone",
		"global_position": position,
		"token": int(source_entry.get("token", 0)),
		"generation": int(source_entry.get("generation", 0)),
		"execution": snapshot,
	}


func _weapon_replay_scale_staff_combo_radii(parameters: Dictionary, multiplier: float) -> void:
	if not is_finite(multiplier) or multiplier <= 0.0:
		return
	for field: String in ["radius_tiles", "freeze_radius_tiles", "explosion_radius_tiles"]:
		var value: Variant = parameters.get(field)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0:
			parameters[field] = float(value) * multiplier


func _weapon_replay_project_gauntlets_payload_result(
	expected_after: Dictionary,
	state_after: Dictionary,
	action_token: int,
	payload_generation: int,
	result: Dictionary
) -> bool:
	var claim_id := str(result.get("claim_id", ""))
	var outcome_id := str(result.get("outcome_id", ""))
	var target_id := int(result.get("target_id", 0))
	if (
		action_token <= 0
		or payload_generation <= 0
		or claim_id.is_empty()
		or outcome_id.is_empty()
		or target_id <= 0
	):
		return false
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	if expected_runtime.is_empty() or after_runtime.is_empty():
		return false
	var token_key := str(action_token)
	var expected_ledgers_value: Variant = expected_runtime.get("action_ledgers")
	if (
		not expected_ledgers_value is Dictionary
		or not (expected_ledgers_value as Dictionary).has(token_key)
		or not (expected_ledgers_value as Dictionary)[token_key] is Dictionary
	):
		return false
	var source_ledger := (
		(expected_ledgers_value as Dictionary)[token_key] as Dictionary
	).duplicate(true)
	if (
		weapon_runtime == null
		or not weapon_runtime.has_method("project_payload_result_replay_transition")
	):
		return false
	var projection_value: Variant = weapon_runtime.call(
		"project_payload_result_replay_transition",
		expected_runtime.duplicate(true),
		action_token,
		payload_generation,
		result.duplicate(true)
	)
	if not projection_value is Dictionary:
		return false
	var projection := projection_value as Dictionary
	var projected_runtime_value: Variant = projection.get("runtime_snapshot")
	var context_value: Variant = projection.get("context")
	if (
		not bool(projection.get("ok", false))
		or not projected_runtime_value is Dictionary
		or not context_value is Dictionary
	):
		return false
	expected_runtime = (projected_runtime_value as Dictionary).duplicate(true)
	var projection_context := context_value as Dictionary
	var expected_adapter_value: Variant = expected_runtime.get("adapter")
	var after_adapter_value: Variant = after_runtime.get("adapter")
	if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
		return false
	var expected_adapter := expected_adapter_value as Dictionary
	var after_adapter := after_adapter_value as Dictionary
	var source_payload_index := _weapon_replay_gauntlets_source_payload_index(
		expected_adapter,
		action_token,
		payload_generation,
		result
	)
	if source_payload_index < 0:
		return false
	var owned_payloads_value: Variant = expected_adapter.get("owned_payloads")
	if not owned_payloads_value is Array:
		return false
	var expected_payloads := (owned_payloads_value as Array).duplicate(true)
	var source_entry := expected_payloads[source_payload_index] as Dictionary
	var source_type := str(source_entry.get("payload_type", ""))
	var progress_claims_value: Variant = expected_adapter.get("progress_claims")
	var progress_order_value: Variant = expected_adapter.get("progress_claim_order")
	var reported_claims_value: Variant = expected_adapter.get("reported_claims")
	var reported_order_value: Variant = expected_adapter.get("reported_claim_order")
	if (
		not progress_claims_value is Dictionary
		or not progress_order_value is Array
		or not reported_claims_value is Dictionary
		or not reported_order_value is Array
	):
		return false
	var progress_key := "%d:%d:%d" % [action_token, payload_generation, target_id]
	if (
		source_type == "hit"
		and str(result.get("type", "")) != "damage_claim_duplicate"
		and not (progress_claims_value as Dictionary).has(progress_key)
	):
		if not _weapon_replay_apply_bounded_true_claim(
			progress_claims_value as Dictionary,
			progress_order_value as Array,
			progress_key,
			WEAPON_REPLAY_CALLBACK_CLAIM_LIMIT
		):
			return false
	if not _weapon_replay_apply_bounded_true_claim(
		reported_claims_value as Dictionary,
		reported_order_value as Array,
		"%d:%d:%s" % [action_token, payload_generation, claim_id],
		WEAPON_REPLAY_CALLBACK_CLAIM_LIMIT
	):
		return false
	var expected_feedback_value: Variant = expected_adapter.get("feedback_facts")
	if not expected_feedback_value is Array:
		return false
	var expected_feedback := (expected_feedback_value as Array).duplicate(true)
	if bool(result.get("hit", false)):
		if expected_feedback.size() >= WEAPON_REPLAY_FEEDBACK_FACT_LIMIT:
			expected_feedback.pop_front()
		var source_snapshot_value: Variant = source_entry.get("snapshot")
		if not source_snapshot_value is Dictionary:
			return false
		var source_snapshot := source_snapshot_value as Dictionary
		var action_id := str(source_snapshot.get("source_action_id", ""))
		expected_feedback.append({
			"weapon_id": "gauntlets",
			"action_id": action_id,
			"action_token": action_token,
			"generation": payload_generation,
			"descriptor_id": str(result.get("descriptor_id", "")),
			"outcome_index": int(result.get("outcome_index", -1)),
			"target_id": target_id,
			"damage": float(result.get("damage", 0.0)),
			"impact_position": result.get("impact_position", Vector2.ZERO),
			"deterministic_seed": int(result.get("deterministic_seed", 0)),
			"is_echo": bool(result.get("is_echo", false)),
			"impact_tier": _weapon_replay_gauntlets_impact_tier(action_id),
		})
	expected_adapter["feedback_facts"] = expected_feedback
	var after_payloads_value: Variant = after_adapter.get("owned_payloads")
	if not after_payloads_value is Array:
		return false
	var after_payloads := after_payloads_value as Array
	if after_payloads.size() < expected_payloads.size():
		return false
	for index: int in range(expected_payloads.size()):
		if expected_payloads[index] != after_payloads[index]:
			return false
	var spawn_zone_value: Variant = result.get("spawn_zone", {})
	if spawn_zone_value is Dictionary and not (spawn_zone_value as Dictionary).is_empty():
		if after_payloads.size() <= expected_payloads.size():
			return false
		var appended_zone_value: Variant = after_payloads[expected_payloads.size()]
		if (
			not appended_zone_value is Dictionary
			or not _weapon_replay_gauntlets_zone_entry_is_valid(
				appended_zone_value as Dictionary,
				source_entry,
				action_token,
				payload_generation,
				spawn_zone_value as Dictionary
			)
		):
			return false
		expected_payloads.append((appended_zone_value as Dictionary).duplicate(true))
	var echo_value: Variant = projection_context.get("echo_descriptor", {})
	if echo_value is Dictionary and not (echo_value as Dictionary).is_empty():
		if after_payloads.size() <= expected_payloads.size():
			return false
		var appended_echo_value: Variant = after_payloads[expected_payloads.size()]
		if (
			not appended_echo_value is Dictionary
			or not _weapon_replay_gauntlets_echo_entry_is_valid(
				appended_echo_value as Dictionary,
				source_entry,
				action_token,
				payload_generation,
				result,
				echo_value as Dictionary
			)
		):
			return false
		expected_payloads.append((appended_echo_value as Dictionary).duplicate(true))
	if after_payloads.size() != expected_payloads.size():
		return false
	expected_adapter["owned_payloads"] = expected_payloads
	if expected_adapter != after_adapter:
		return false
	expected_runtime["adapter"] = expected_adapter
	var expected_coordinator := expected_after.get("coordinator", {}) as Dictionary
	expected_coordinator["runtime"] = expected_runtime
	var energy_return := float(projection_context.get("energy_return", 0.0))
	if energy_return > 0.0:
		if not _weapon_replay_project_exact_energy_gain(
			expected_after,
			state_after,
			energy_return
		):
			return false
	var stop_extension_frames := int(projection_context.get("stop_extension_frames", 0))
	if stop_extension_frames > 0:
		if not _weapon_replay_project_exact_stop_extension(
			expected_after,
			action_token,
			int(source_ledger.get("stop_generation", 0)),
			stop_extension_frames
		):
			return false
	return true


func _weapon_replay_gauntlets_source_payload_index(
	adapter: Dictionary,
	action_token: int,
	payload_generation: int,
	result: Dictionary
) -> int:
	var payloads_value: Variant = adapter.get("owned_payloads")
	if not payloads_value is Array:
		return -1
	var matched := -1
	for index: int in range((payloads_value as Array).size()):
		var entry_value: Variant = (payloads_value as Array)[index]
		if not entry_value is Dictionary:
			return -1
		var entry := entry_value as Dictionary
		var snapshot_value: Variant = entry.get("snapshot")
		if not snapshot_value is Dictionary:
			return -1
		var snapshot := snapshot_value as Dictionary
		if (
			int(entry.get("token", 0)) != action_token
			or int(entry.get("generation", 0)) != payload_generation
			or str(snapshot.get("descriptor_id", "")) != str(result.get("descriptor_id", ""))
			or int(snapshot.get("outcome_index", -1)) != int(result.get("outcome_index", -2))
		):
			continue
		if matched >= 0:
			return -1
		matched = index
	return matched


func _weapon_replay_gauntlets_zone_entry_is_valid(
	entry: Dictionary,
	source_entry: Dictionary,
	action_token: int,
	payload_generation: int,
	zone_descriptor: Dictionary
) -> bool:
	var source_snapshot_value: Variant = source_entry.get("snapshot")
	var parameters_value: Variant = zone_descriptor.get("parameters")
	var snapshot_value: Variant = entry.get("snapshot")
	if (
		not source_snapshot_value is Dictionary
		or not parameters_value is Dictionary
		or not snapshot_value is Dictionary
	):
		return false
	var source_snapshot := source_snapshot_value as Dictionary
	var parameters := parameters_value as Dictionary
	var descriptor_id := str(zone_descriptor.get(
		"descriptor_id",
		"%s:zone" % str(source_snapshot.get("descriptor_id", ""))
	))
	var outcome_id := str(zone_descriptor.get(
		"outcome_id",
		"%s:zone" % str(source_snapshot.get("outcome_id", ""))
	))
	var expected_snapshot := {
		"schema_version": 1,
		"action_token": action_token,
		"generation": payload_generation,
		"source_action_id": str(source_snapshot.get("source_action_id", "")),
		"descriptor_id": descriptor_id,
		"outcome_id": outcome_id,
		"outcome_index": int(zone_descriptor.get("outcome_index", source_snapshot.get("outcome_index", -1))),
		"deterministic_seed": int(zone_descriptor.get("seed", source_snapshot.get("deterministic_seed", 0))),
		"mode": str(parameters.get("mode", "space_time_shatter")),
		"parameters": parameters.duplicate(true),
		"base_attack": float(source_snapshot.get("base_attack", 0.0)),
		"source_id": StringName("gauntlets_zone:%d:%d:%s" % [action_token, payload_generation, descriptor_id]),
		"execution_frame": 0,
		"duration_frames": int(parameters.get("duration_frames", 0)),
		"remaining_frames": int(parameters.get("duration_frames", 0)),
		"tick_interval_frames": int(parameters.get("tick_interval_frames", 0)),
		"fractional_frames": 0.0,
		"execution_active": true,
		"damage_claim_keys": [],
	}
	return entry == {
		"payload_type": "zone",
		"token": action_token,
		"generation": payload_generation,
		"global_position": zone_descriptor.get("position", source_entry.get("global_position", Vector2.ZERO)),
		"snapshot": expected_snapshot,
	}


func _weapon_replay_gauntlets_echo_entry_is_valid(
	entry: Dictionary,
	source_entry: Dictionary,
	action_token: int,
	payload_generation: int,
	result: Dictionary,
	echo_descriptor: Dictionary
) -> bool:
	var source_snapshot_value: Variant = source_entry.get("snapshot")
	var parameters_value: Variant = echo_descriptor.get("parameters")
	var snapshot_value: Variant = entry.get("snapshot")
	if (
		not source_snapshot_value is Dictionary
		or not parameters_value is Dictionary
		or not snapshot_value is Dictionary
	):
		return false
	var source_snapshot := source_snapshot_value as Dictionary
	var source_spatial_value: Variant = source_snapshot.get("spatial_context")
	if not source_spatial_value is Dictionary:
		return false
	var source_spatial := source_spatial_value as Dictionary
	var parameters := (parameters_value as Dictionary).duplicate(true)
	parameters["combo_eligible"] = false
	parameters["energy_eligible"] = false
	parameters["stop_extension_eligible"] = false
	parameters["recursive_echo"] = false
	parameters["is_echo"] = true
	var position: Variant = result.get(
		"impact_position",
		source_entry.get("global_position", Vector2.ZERO)
	)
	var descriptor_id := str(echo_descriptor.get("descriptor_id", ""))
	var outcome_index := int(echo_descriptor.get("outcome_index", -1))
	var expected_snapshot := {
		"schema_version": 1,
		"action_token": action_token,
		"generation": payload_generation,
		"source_action_id": str(source_snapshot.get("source_action_id", "")),
		"descriptor_id": descriptor_id,
		"outcome_id": str(echo_descriptor.get("outcome_id", "%s:%d" % [descriptor_id, outcome_index])),
		"outcome_index": outcome_index,
		"deterministic_seed": int(echo_descriptor.get("seed", 0)),
		"kind": str(echo_descriptor.get("kind", "")),
		"parameters": parameters,
		"base_attack": float(source_snapshot.get("base_attack", 0.0)),
		"direction": source_snapshot.get("direction", Vector2.RIGHT),
		"target_deduplication": str(echo_descriptor.get("target_deduplication", "")),
		"boss_conversion": {},
		"combo_eligible": false,
		"energy_eligible": false,
		"stop_extension_eligible": false,
		"recursive_echo": false,
		"is_echo": true,
		"execution_frame": 0,
		"active_frames": int(parameters.get("active_frames", 0)),
		"remaining_frames": int(parameters.get("active_frames", 0)),
		"fractional_frames": 0.0,
		"execution_active": true,
		"completion_emitted": false,
		"hit_target_ids": [],
		"spatial_context": {
			"center": position,
			"origin": position,
			"direction": source_snapshot.get("direction", Vector2.RIGHT),
			"shape": str(source_spatial.get("shape", "")),
			"range_pixels": float(source_spatial.get("range_pixels", 0.0)),
			"width_pixels": float(source_spatial.get("width_pixels", 0.0)),
			"arc_degrees": float(source_spatial.get("arc_degrees", 0.0)),
			"source_generation": 0,
			"spatial_policy": "",
			"active_rifts": [],
		},
	}
	return entry == {
		"payload_type": "hit",
		"token": action_token,
		"generation": payload_generation,
		"global_position": position,
		"snapshot": expected_snapshot,
	}


func _weapon_replay_gauntlets_impact_tier(action_id: String) -> String:
	if action_id == "primordial_collapse_punch":
		return "ultimate"
	if action_id in ["punch_5", "charged_heavy", "dodge_counter", "space_time_shatter"]:
		return "heavy"
	if action_id in ["punch_3", "punch_4"]:
		return "medium"
	return "light"


func _weapon_replay_project_exact_energy_gain(
	expected_after: Dictionary,
	state_after: Dictionary,
	amount: float
) -> bool:
	if not is_finite(amount) or amount <= 0.0:
		return false
	var before_energy := _weapon_replay_time_energy_state(expected_after)
	var after_energy := _weapon_replay_time_energy_state(state_after)
	if before_energy.is_empty() or after_energy.is_empty():
		return false
	var expected_current := minf(
		float(before_energy.get("maximum", -1.0)),
		float(before_energy.get("current", -1.0)) + amount
	)
	var changed := not is_equal_approx(
		expected_current,
		float(before_energy.get("current", -1.0))
	)
	var projected_energy := before_energy.duplicate(true)
	projected_energy["current"] = expected_current
	projected_energy["revision"] = int(before_energy.get("revision", 0)) + (1 if changed else 0)
	if after_energy != projected_energy:
		return false
	var expected_time := expected_after["time_manager_state"] as Dictionary
	expected_time["time_energy_state"] = projected_energy
	var expected_coordinator := expected_after["coordinator"] as Dictionary
	var expected_transaction := expected_coordinator["resource_transaction"] as Dictionary
	var expected_accounts := expected_transaction["external_accounts"] as Dictionary
	expected_accounts["time_energy"] = projected_energy.duplicate(true)
	return true


func _weapon_replay_project_exact_stop_extension(
	expected_after: Dictionary,
	action_token: int,
	stop_generation: int,
	extension_frames: int
) -> bool:
	if action_token <= 0 or stop_generation <= 0 or extension_frames <= 0:
		return false
	var time_value: Variant = expected_after.get("time_manager_state")
	if not time_value is Dictionary:
		return false
	var time_state := time_value as Dictionary
	var tokens_value: Variant = time_state.get("stop_extension_tokens")
	if (
		not bool(time_state.get("stop_active", false))
		or int(time_state.get("stop_source_sequence", 0)) != stop_generation
		or not tokens_value is Dictionary
		or (tokens_value as Dictionary).has(action_token)
	):
		return false
	var current_frames := int(time_state.get("stop_extension_frames", 0))
	if current_frames + extension_frames > 30:
		return false
	var projected_tokens := (tokens_value as Dictionary).duplicate(true)
	projected_tokens[action_token] = true
	time_state["stop_extension_tokens"] = projected_tokens
	time_state["stop_extension_frames"] = current_frames + extension_frames
	time_state["stop_remaining"] = (
		float(time_state.get("stop_remaining", 0.0))
		+ float(extension_frames) / 60.0
	)
	return true


func _weapon_replay_project_source_reward_claim(
	expected_after: Dictionary,
	state_after: Dictionary,
	action_token: int,
	action_generation: int,
	claim_id: String,
	reward_id: String
) -> bool:
	var expected_runtime := _weapon_replay_runtime_snapshot(expected_after)
	var after_runtime := _weapon_replay_runtime_snapshot(state_after)
	match str(expected_after.get("weapon_id", "")):
		"gun":
			var expected_adapter_value: Variant = expected_runtime.get("adapter_snapshot")
			var after_adapter_value: Variant = after_runtime.get("adapter_snapshot")
			if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
				return false
			var expected_adapter := expected_adapter_value as Dictionary
			var after_adapter := after_adapter_value as Dictionary
			var token_key := str(action_token)
			var source_claim_key := "%d:resource:%s" % [action_token, reward_id]
			var expected_claims_by_token_value: Variant = expected_adapter.get("action_claims_by_token")
			var after_claims_by_token_value: Variant = after_adapter.get("action_claims_by_token")
			if (
				not expected_claims_by_token_value is Dictionary
				or not after_claims_by_token_value is Dictionary
				or not (expected_claims_by_token_value as Dictionary).has(token_key)
				or not (after_claims_by_token_value as Dictionary).has(token_key)
			):
				return false
			var expected_claims_by_token := (expected_claims_by_token_value as Dictionary).duplicate(true)
			var before_token_claims := expected_claims_by_token[token_key] as Dictionary
			var after_token_claims := (after_claims_by_token_value as Dictionary)[token_key] as Dictionary
			if not _weapon_replay_dictionary_has_single_true_addition(
				before_token_claims,
				after_token_claims,
				source_claim_key
			):
				return false
			expected_claims_by_token[token_key] = after_token_claims.duplicate(true)
			expected_adapter["action_claims_by_token"] = expected_claims_by_token
			for payload_field: String in ["prepared_projectiles", "owned_projectiles"]:
				var expected_payloads_value: Variant = expected_adapter.get(payload_field)
				var after_payloads_value: Variant = after_adapter.get(payload_field)
				if not expected_payloads_value is Array or not after_payloads_value is Array:
					return false
				var expected_payloads := (expected_payloads_value as Array).duplicate(true)
				var after_payloads := after_payloads_value as Array
				if expected_payloads.size() != after_payloads.size():
					return false
				for index: int in range(expected_payloads.size()):
					var expected_entry := expected_payloads[index] as Dictionary
					var after_entry := after_payloads[index] as Dictionary
					var expected_execution := (expected_entry.get("execution", {}) as Dictionary).duplicate(true)
					var after_execution := after_entry.get("execution", {}) as Dictionary
					if int(expected_execution.get("action_token", 0)) == action_token:
						var before_claims := expected_execution.get("action_claims", {}) as Dictionary
						var after_claims := after_execution.get("action_claims", {}) as Dictionary
						if not _weapon_replay_dictionary_has_single_true_addition(
							before_claims,
							after_claims,
							source_claim_key
						):
							return false
						expected_execution["action_claims"] = after_claims.duplicate(true)
						expected_entry["execution"] = expected_execution
					if expected_entry != after_entry:
						return false
					expected_payloads[index] = expected_entry
				expected_adapter[payload_field] = expected_payloads
		"staff":
			var expected_adapter_value: Variant = expected_runtime.get("adapter_snapshot")
			var after_adapter_value: Variant = after_runtime.get("adapter_snapshot")
			if not expected_adapter_value is Dictionary or not after_adapter_value is Dictionary:
				return false
			var expected_adapter := expected_adapter_value as Dictionary
			var after_adapter := after_adapter_value as Dictionary
			if not _weapon_replay_project_staff_reward_source(
				expected_adapter,
				after_adapter,
				action_token,
				claim_id
			):
				return false
		_:
			return false
	return state_after == expected_after


func _weapon_replay_project_staff_reward_source(
	expected_adapter: Dictionary,
	after_adapter: Dictionary,
	action_token: int,
	claim_id: String
) -> bool:
	var tick_index := _weapon_replay_staff_reward_tick_index(claim_id)
	if tick_index < 0:
		return false
	var expected_claims_value: Variant = expected_adapter.get("resource_reward_claims")
	var expected_order_value: Variant = expected_adapter.get("resource_reward_claim_order")
	var after_claims_value: Variant = after_adapter.get("resource_reward_claims")
	var after_order_value: Variant = after_adapter.get("resource_reward_claim_order")
	if (
		not expected_claims_value is Dictionary
		or not expected_order_value is Array
		or not after_claims_value is Dictionary
		or not after_order_value is Array
	):
		return false
	var expected_order := expected_order_value as Array
	var expected_claims := expected_claims_value as Dictionary
	if expected_order.size() >= WEAPON_REPLAY_RESOURCE_REWARD_CLAIM_LIMIT:
		var expired_key := str(expected_order.pop_front())
		expected_claims.erase(expired_key)
	var after_order := after_order_value as Array
	if after_order.size() != expected_order.size() + 1:
		return false
	for index: int in range(expected_order.size()):
		if expected_order[index] != after_order[index]:
			return false
	var source_claim_key := str(after_order[-1])
	var key_parts := source_claim_key.split(":", false, 2)
	if (
		key_parts.size() != 3
		or not str(key_parts[0]).is_valid_int()
		or int(key_parts[0]) != action_token
		or not str(key_parts[1]).is_valid_int()
		or int(key_parts[1]) <= 0
		or str(key_parts[2]) != claim_id
	):
		return false
	var source_generation := int(key_parts[1])
	if not _weapon_replay_apply_bounded_true_claim(
		expected_claims,
		expected_order,
		source_claim_key,
		WEAPON_REPLAY_RESOURCE_REWARD_CLAIM_LIMIT
	):
		return false
	if expected_claims != (after_claims_value as Dictionary) or expected_order != after_order:
		return false
	var payloads_value: Variant = expected_adapter.get("owned_payloads")
	var after_payloads_value: Variant = after_adapter.get("owned_payloads")
	if not payloads_value is Array or not after_payloads_value is Array:
		return false
	var projected_payloads := (payloads_value as Array).duplicate(true)
	var after_payloads := after_payloads_value as Array
	if projected_payloads.size() != after_payloads.size():
		return false
	var matched := -1
	for index: int in range(projected_payloads.size()):
		if not projected_payloads[index] is Dictionary or not after_payloads[index] is Dictionary:
			return false
		var entry := (projected_payloads[index] as Dictionary).duplicate(true)
		var execution_value: Variant = entry.get("execution")
		if not execution_value is Dictionary:
			continue
		var execution := (execution_value as Dictionary).duplicate(true)
		if (
			str(entry.get("kind", "")) != "zone"
			or int(entry.get("token", 0)) != action_token
			or int(entry.get("generation", 0)) != source_generation
			or str(execution.get("source_action_id", "")) != "primordial_wrath"
			or str(execution.get("mode", "")) != "seeded_sequence"
		):
			continue
		if matched >= 0:
			return false
		var parameters_value: Variant = execution.get("parameters")
		var after_execution_value: Variant = (after_payloads[index] as Dictionary).get("execution")
		if not parameters_value is Dictionary or not after_execution_value is Dictionary:
			return false
		var parameters := parameters_value as Dictionary
		var count := int(parameters.get("count", 0))
		var interval := int(execution.get("tick_interval_frames", 0))
		var expected_frame := (tick_index + 1) * interval
		var after_execution := after_execution_value as Dictionary
		var fractional := float(after_execution.get("fractional_frames", NAN))
		if (
			count <= 0
			or tick_index >= count
			or interval <= 0
			or int(execution.get("execution_frame", -1)) > expected_frame
			or int(after_execution.get("execution_frame", -1)) != expected_frame
			or not is_finite(fractional)
			or fractional < 0.0
			or fractional >= 1.0
		):
			return false
		execution["execution_frame"] = expected_frame
		execution["fractional_frames"] = fractional
		entry["execution"] = execution
		if entry != after_payloads[index]:
			return false
		projected_payloads[index] = entry
		matched = index
	if matched < 0:
		return false
	expected_adapter["owned_payloads"] = projected_payloads
	return expected_adapter == after_adapter


func _weapon_replay_staff_reward_tick_index(claim_id: String) -> int:
	const PREFIX := "staff_ultimate_tick:"
	if not claim_id.begins_with(PREFIX):
		return -1
	var tick_text := claim_id.trim_prefix(PREFIX)
	if not tick_text.is_valid_int() or str(int(tick_text)) != tick_text:
		return -1
	return int(tick_text)


func _weapon_replay_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var coordinator_value: Variant = snapshot.get("coordinator")
	if not coordinator_value is Dictionary:
		return {}
	var runtime_value: Variant = (coordinator_value as Dictionary).get("runtime")
	return runtime_value as Dictionary if runtime_value is Dictionary else {}


func _weapon_replay_string_array_has_single_append(before: Array, after: Array) -> bool:
	if after.size() != before.size() + 1:
		return false
	for index: int in range(before.size()):
		if before[index] != after[index]:
			return false
	var appended_value: Variant = after[-1]
	return (
		typeof(appended_value) in [TYPE_STRING, TYPE_STRING_NAME]
		and not str(appended_value).is_empty()
		and not before.has(appended_value)
	)


func _weapon_replay_string_array_has_single_addition(before: Array, after: Array) -> bool:
	if after.size() != before.size() + 1:
		return false
	var seen: Dictionary = {}
	for value: Variant in after:
		if (
			typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(value).is_empty()
			or seen.has(str(value))
		):
			return false
		seen[str(value)] = true
	for value: Variant in before:
		if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME] or not seen.has(str(value)):
			return false
	return true


func _weapon_replay_single_added_string(before: Array, after: Array) -> String:
	if not _weapon_replay_string_array_has_single_addition(before, after):
		return ""
	for value: Variant in after:
		if not before.has(value):
			return str(value)
	return ""


func _weapon_replay_staff_projectile_damage_claim_is_valid(
	claim: String,
	execution: Dictionary
) -> bool:
	var parts := claim.split(":", false)
	return (
		parts.size() == 5
		and parts[0] == "damage"
		and str(parts[1]).is_valid_int()
		and int(parts[1]) == int(execution.get("outcome_index", -1))
		and not str(parts[2]).is_empty()
		and not str(parts[3]).is_empty()
		and str(parts[4]).is_valid_int()
		and int(parts[4]) > 0
	)


func _weapon_replay_staff_zone_damage_claim_is_valid(
	claim: String,
	execution: Dictionary,
	execution_frame: int
) -> bool:
	var parts := claim.split(":", false)
	return (
		parts.size() == 6
		and parts[0] == "damage"
		and str(parts[1]).is_valid_int()
		and int(parts[1]) == int(execution.get("outcome_index", -1))
		and str(parts[2]) == str(execution.get("mode", ""))
		and str(parts[3]).is_valid_int()
		and int(parts[3]) == execution_frame
		and not str(parts[4]).is_empty()
		and str(parts[5]).is_valid_int()
		and int(parts[5]) > 0
	)


func _weapon_replay_integer_array_has_single_addition(before: Array, after: Array) -> bool:
	if after.size() != before.size() + 1:
		return false
	var seen: Dictionary = {}
	for value: Variant in after:
		if typeof(value) != TYPE_INT or int(value) <= 0 or seen.has(int(value)):
			return false
		seen[int(value)] = true
	for value: Variant in before:
		if typeof(value) != TYPE_INT or not seen.has(int(value)):
			return false
	return true


func _weapon_replay_single_added_integer(before: Array, after: Array) -> int:
	if not _weapon_replay_integer_array_has_single_addition(before, after):
		return 0
	for value: Variant in after:
		if not before.has(value):
			return int(value)
	return 0


func _weapon_replay_dictionary_has_single_true_addition(
	before: Dictionary,
	after: Dictionary,
	key: String
) -> bool:
	if key.is_empty() or before.has(key) or after.size() != before.size() + 1:
		return false
	var expected := before.duplicate(true)
	expected[key] = true
	return after == expected


func _weapon_replay_apply_bounded_true_claim(
	claims: Dictionary,
	order: Array,
	key: String,
	limit: int
) -> bool:
	if key.is_empty() or limit <= 0 or claims.has(key):
		return false
	while order.size() >= limit:
		var expired_key := str(order.pop_front())
		claims.erase(expired_key)
	claims[key] = true
	order.append(key)
	return true


func _weapon_replay_time_manager_is_unchanged(
	state_before: Dictionary,
	state_after: Dictionary
) -> bool:
	var before_time_value: Variant = state_before.get("time_manager_state")
	var after_time_value: Variant = state_after.get("time_manager_state")
	return (
		before_time_value is Dictionary
		and after_time_value is Dictionary
		and (before_time_value as Dictionary) == (after_time_value as Dictionary)
	)


func _weapon_replay_resource_reward_transition_is_valid(
	state_before: Dictionary,
	state_after: Dictionary,
	payload: Dictionary,
	data: Dictionary
) -> bool:
	var before_energy := _weapon_replay_time_energy_state(state_before)
	var after_energy := _weapon_replay_time_energy_state(state_after)
	if before_energy.is_empty() or after_energy.is_empty():
		return false
	var before_time_value: Variant = state_before.get("time_manager_state")
	var after_time_value: Variant = state_after.get("time_manager_state")
	if not before_time_value is Dictionary or not after_time_value is Dictionary:
		return false
	var amount := float(data.get("amount", NAN))
	var energy_before := float(data.get("energy_before", NAN))
	var energy_after := float(data.get("energy_after", NAN))
	var maximum := float(data.get("maximum", NAN))
	var revision_before := int(data.get("energy_revision_before", 0))
	if (
		not is_finite(amount)
		or not is_finite(energy_before)
		or not is_finite(energy_after)
		or not is_finite(maximum)
		or amount <= 0.0
		or revision_before <= 0
	):
		return false
	var expected_after := minf(maximum, energy_before + amount)
	if not (
		is_equal_approx(float(before_energy.get("current", -1.0)), energy_before)
		and is_equal_approx(float(before_energy.get("maximum", -1.0)), maximum)
		and int(before_energy.get("revision", 0)) == revision_before
		and is_equal_approx(energy_after, expected_after)
		and is_equal_approx(float(after_energy.get("current", -1.0)), expected_after)
		and is_equal_approx(float(after_energy.get("maximum", -1.0)), maximum)
		and int(after_energy.get("revision", 0)) == revision_before + 1
	):
		return false
	var action_token := int(payload.get("action_token", 0))
	var action_generation := int(payload.get("action_generation", 0))
	var reward_id := str(data.get("reward_id", ""))
	var claim_id := str(data.get("claim_id", ""))
	var reward_kind := "resource:%s" % reward_id
	if not claim_id.is_empty():
		reward_kind = "resource:%s:%s:generation:%d" % [
			reward_id,
			claim_id,
			action_generation,
		]
	var reward_claim_key := "%d:%s" % [action_token, reward_kind]
	var expected_after_snapshot := state_before.duplicate(true)
	var expected_player := expected_after_snapshot["player_weapon_state"] as Dictionary
	var expected_reward_claims := expected_player["action_reward_claims"] as Dictionary
	if expected_reward_claims.has(reward_claim_key):
		return false
	expected_reward_claims[reward_claim_key] = true
	var expected_time := expected_after_snapshot["time_manager_state"] as Dictionary
	expected_time["time_energy_state"] = after_energy.duplicate(true)
	var expected_coordinator := expected_after_snapshot["coordinator"] as Dictionary
	var expected_transaction := expected_coordinator["resource_transaction"] as Dictionary
	var expected_accounts := expected_transaction["external_accounts"] as Dictionary
	expected_accounts["time_energy"] = after_energy.duplicate(true)
	if state_after == expected_after_snapshot:
		return true
	return _weapon_replay_project_source_reward_claim(
		expected_after_snapshot,
		state_after,
		action_token,
		action_generation,
		claim_id,
		reward_id
	)


func _weapon_replay_time_energy_state(snapshot: Dictionary) -> Dictionary:
	var time_state_value: Variant = snapshot.get("time_manager_state")
	if not time_state_value is Dictionary:
		return {}
	var energy_value: Variant = (time_state_value as Dictionary).get("time_energy_state")
	return (energy_value as Dictionary).duplicate(true) if energy_value is Dictionary else {}


func _weapon_replay_time_fact_transition_is_valid(
	payload: Dictionary,
	data: Dictionary,
	state_before: Dictionary
) -> bool:
	if (
		str(payload.get("fact_type", "")) not in WEAPON_REPLAY_TIME_FACT_TYPES
		or not _weapon_replay_snapshot_matches_external_fact_identity(
			state_before,
			payload
		)
		or not data.get("state_before") is Dictionary
		or not data.get("state_after") is Dictionary
	):
		return false
	var before_time_value: Variant = state_before.get("time_manager_state")
	return (
		before_time_value is Dictionary
		and (before_time_value as Dictionary) == (data["state_before"] as Dictionary)
	)


func _apply_weapon_replay_time_fact(payload: Dictionary, data: Dictionary) -> bool:
	if (
		time_manager == null
		or not time_manager.has_method("weapon_replay_snapshot")
		or not time_manager.has_method("can_restore_weapon_replay_snapshot")
		or not time_manager.has_method("restore_weapon_replay_snapshot")
	):
		return false
	var current_snapshot := weapon_replay_snapshot()
	if not _weapon_replay_time_fact_transition_is_valid(payload, data, current_snapshot):
		return false
	var state_before := data["state_before"] as Dictionary
	var state_after := data["state_after"] as Dictionary
	if (
		not bool(time_manager.call("can_restore_weapon_replay_snapshot", state_before.duplicate(true)))
		or not bool(time_manager.call("can_restore_weapon_replay_snapshot", state_after.duplicate(true)))
	):
		return false
	var current_value: Variant = time_manager.call("weapon_replay_snapshot")
	if not current_value is Dictionary:
		return false
	var current := current_value as Dictionary
	if current != state_before:
		return false
	return bool(time_manager.call("restore_weapon_replay_snapshot", state_after.duplicate(true)))


func _apply_weapon_replay_damage_fact(payload: Dictionary, data: Dictionary) -> bool:
	var state_after_value: Variant = data.get("state_after")
	if not state_after_value is Dictionary:
		return false
	var state_after := _validated_weapon_replay_snapshot(state_after_value as Dictionary)
	var current_player_snapshot := weapon_replay_snapshot()
	if (
		state_after.is_empty()
		or current_player_snapshot.is_empty()
		or not _weapon_replay_state_fact_transition_is_valid(
			payload,
			data,
			current_player_snapshot,
			state_after
		)
	):
		return false
	var target_path := NodePath(str(data.get("target_path", "")))
	var health_path := NodePath(str(data.get("health_path", "")))
	if target_path.is_absolute() or health_path.is_absolute():
		return false
	var target := get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return false
	var health := target.get_node_or_null(health_path)
	if (
		health == null
		or not is_instance_valid(health)
		or typeof(health.get("current_hp")) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(health.get("dead")) != TYPE_BOOL
	):
		return false
	var fact_id := str(payload.get("fact_id", ""))
	var fact_digest := ReplayRecorderScript.value_digest(payload)
	const CLAIMS_META := &"planewalker_replay_external_fact_claims"
	var claims_value: Variant = target.get_meta(CLAIMS_META, {})
	var claims: Dictionary = claims_value.duplicate(true) if claims_value is Dictionary else {}
	if claims.has(fact_id):
		return (
			str(claims[fact_id]) == fact_digest
			and (weapon_replay_snapshot() == state_after or restore_weapon_replay_snapshot(state_after))
		)
	var hp_before := float(data["hp_before"])
	var hp_after := float(data["hp_after"])
	var resolved_damage := float(data["resolved_damage"])
	var current_hp := float(health.get("current_hp"))
	if (
		absf(current_hp - hp_after) <= WEAPON_REPLAY_HP_ABSOLUTE_EPSILON
		and bool(health.get("dead")) == bool(data["target_dead_after"])
	):
		if weapon_replay_snapshot() != state_after and not restore_weapon_replay_snapshot(state_after):
			return false
		claims[fact_id] = fact_digest
		target.set_meta(CLAIMS_META, claims)
		return true
	if absf(current_hp - hp_before) > WEAPON_REPLAY_HP_ABSOLUTE_EPSILON:
		return false
	var player_before := current_player_snapshot
	if player_before.is_empty():
		return false
	if player_before != state_after and not restore_weapon_replay_snapshot(state_after):
		return false
	# Replay applies an already-resolved authoritative outcome. It does not call
	# lose_health/take_damage again, because those APIs publish gameplay signals
	# and can partially mutate before reporting failure. Directly installing the
	# validated HP/dead pair keeps duplicate replay side-effect free and lets us
	# roll both domains back if verification ever fails.
	health.set("current_hp", hp_after)
	health.set("dead", bool(data["target_dead_after"]))
	if (
		absf(float(health.get("current_hp")) - hp_after) > WEAPON_REPLAY_HP_ABSOLUTE_EPSILON
		or bool(health.get("dead")) != bool(data["target_dead_after"])
	):
		health.set("current_hp", current_hp)
		health.set("dead", current_hp <= 0.0)
		if weapon_replay_snapshot() != player_before:
			restore_weapon_replay_snapshot(player_before)
		return false
	claims[fact_id] = fact_digest
	target.set_meta(CLAIMS_META, claims)
	return true


func _validated_weapon_replay_snapshot(snapshot: Dictionary) -> Dictionary:
	const ROOT_FIELDS: Array[String] = [
		"schema_version",
		"event_prefix_count",
		"event_prefix_root",
		"weapon_id",
		"profile_id",
		"profile_version",
		"frame",
		"token",
		"generation",
		"phase",
		"coordinator",
		"time_manager_state",
		"player_weapon_state",
	]
	if not _dictionary_has_exact_fields(snapshot, ROOT_FIELDS):
		return {}
	if (
		typeof(snapshot.get("schema_version")) != TYPE_INT
		or int(snapshot["schema_version"]) != WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION
		or typeof(snapshot.get("event_prefix_count")) != TYPE_INT
		or int(snapshot["event_prefix_count"]) < 0
		or not ReplayRecorderScript._is_sha256(snapshot.get("event_prefix_root"))
		or typeof(snapshot.get("weapon_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(snapshot["weapon_id"]).is_empty()
		or typeof(snapshot.get("profile_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(snapshot["profile_id"]).is_empty()
		or typeof(snapshot.get("profile_version")) != TYPE_INT
		or int(snapshot["profile_version"]) <= 0
		or typeof(snapshot.get("frame")) != TYPE_INT
		or int(snapshot["frame"]) < 0
		or typeof(snapshot.get("token")) != TYPE_INT
		or int(snapshot["token"]) < 0
		or typeof(snapshot.get("generation")) != TYPE_INT
		or int(snapshot["generation"]) <= 0
		or typeof(snapshot.get("phase")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(snapshot["phase"]).is_empty()
		or not snapshot.get("coordinator") is Dictionary
		or not snapshot.get("time_manager_state") is Dictionary
		or not snapshot.get("player_weapon_state") is Dictionary
	):
		return {}
	var coordinator := snapshot["coordinator"] as Dictionary
	for field: String in ["weapon_id", "frame", "token", "generation", "phase"]:
		if coordinator.get(field) != snapshot.get(field):
			return {}
	var runtime_value: Variant = coordinator.get("runtime")
	if not runtime_value is Dictionary:
		return {}
	var runtime := runtime_value as Dictionary
	if (
		str(runtime.get("profile_id", "")) != str(snapshot["profile_id"])
		or int(runtime.get("profile_version", 0)) != int(snapshot["profile_version"])
	):
		return {}
	var profile: Dictionary = loadout_runtime.weapon_profile_snapshot()
	if (
		str(loadout_runtime.weapon_id()) != str(snapshot["weapon_id"])
		or str(profile.get("id", "")) != str(snapshot["profile_id"])
		or int(profile.get("profile_version", 0)) != int(snapshot["profile_version"])
	):
		return {}
	var state := snapshot["player_weapon_state"] as Dictionary
	if not _dictionary_has_exact_fields(state, WEAPON_REPLAY_STATE_FIELDS):
		return {}
	if not _valid_weapon_replay_player_state(state, coordinator):
		return {}
	if (
		time_manager == null
		or not time_manager.has_method("can_restore_weapon_replay_snapshot")
		or not bool(time_manager.call(
			"can_restore_weapon_replay_snapshot",
			(snapshot["time_manager_state"] as Dictionary).duplicate(true)
		))
	):
		return {}
	var time_state := snapshot["time_manager_state"] as Dictionary
	var time_energy_value: Variant = time_state.get("time_energy_state")
	var resource_transaction_value: Variant = coordinator.get("resource_transaction")
	if not time_energy_value is Dictionary or not resource_transaction_value is Dictionary:
		return {}
	var external_accounts_value: Variant = (resource_transaction_value as Dictionary).get(
		"external_accounts"
	)
	if not external_accounts_value is Dictionary:
		return {}
	var coordinator_time_energy_value: Variant = (external_accounts_value as Dictionary).get(
		"time_energy"
	)
	if (
		not coordinator_time_energy_value is Dictionary
		or (coordinator_time_energy_value as Dictionary) != (time_energy_value as Dictionary)
	):
		return {}
	return snapshot.duplicate(true)


func _valid_weapon_replay_player_state(state: Dictionary, coordinator: Dictionary) -> bool:
	if (
		not state.get("action_reward_claims") is Dictionary
		or not state.get("action_ids_by_token") is Dictionary
		or not state.get("action_generations_by_token") is Dictionary
		or not state.get("action_token_order") is Array
		or not state.get("hit_fact_claims") is Dictionary
		or not state.get("resource_fact_state") is Dictionary
		or typeof(state.get("next_token_floor")) != TYPE_INT
		or int(state["next_token_floor"]) <= 0
		or typeof(state.get("combo_timeout_frames")) != TYPE_INT
		or int(state["combo_timeout_frames"]) < 0
	):
		return false
	if (
		str(coordinator.get("phase", "")) != "HOLD"
		and int(coordinator.get("token", 0)) > 0
		and int(state["next_token_floor"]) <= int(coordinator.get("token", 0))
	):
		return false
	var action_ids := state["action_ids_by_token"] as Dictionary
	var generations := state["action_generations_by_token"] as Dictionary
	var token_order := state["action_token_order"] as Array
	if (
		action_ids.size() != generations.size()
		or action_ids.size() != token_order.size()
		or token_order.size() > MAX_TRACKED_WEAPON_FACT_TOKENS
	):
		return false
	var seen_tokens: Dictionary = {}
	var previous_token := 0
	var previous_generation := 0
	var next_token_floor := int(state["next_token_floor"])
	var coordinator_generation := int(coordinator.get("generation", 0))
	for token_value: Variant in token_order:
		if typeof(token_value) != TYPE_INT:
			return false
		var token := int(token_value)
		if (
			token <= previous_token
			or token >= next_token_floor
			or seen_tokens.has(token)
			or not action_ids.has(token)
			or not generations.has(token)
		):
			return false
		if (
			typeof(action_ids[token]) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(action_ids[token]).is_empty()
			or typeof(generations[token]) != TYPE_INT
			or int(generations[token]) <= 0
			or int(generations[token]) < previous_generation
			or int(generations[token]) > coordinator_generation
		):
			return false
		seen_tokens[token] = true
		previous_token = token
		previous_generation = int(generations[token])
	var coordinator_token := int(coordinator.get("token", 0))
	if coordinator_token > 0 and seen_tokens.has(coordinator_token):
		var plan := coordinator.get("plan", {}) as Dictionary
		if (
			int(generations[coordinator_token]) != coordinator_generation
			or str(action_ids[coordinator_token]) != str(plan.get("action_id", ""))
		):
			return false
	for claim_key_value: Variant in (state["action_reward_claims"] as Dictionary).keys():
		if typeof(claim_key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var claim_key := str(claim_key_value)
		var separator := claim_key.find(":")
		if separator <= 0 or separator >= claim_key.length() - 1:
			return false
		var token_text := claim_key.substr(0, separator)
		var claim_token := token_text.to_int()
		var claim_value: Variant = (state["action_reward_claims"] as Dictionary)[claim_key_value]
		if (
			claim_token <= 0
			or str(claim_token) != token_text
			or not action_ids.has(claim_token)
			or typeof(claim_value) != TYPE_BOOL
			or not bool(claim_value)
		):
			return false
	for token_value: Variant in (state["hit_fact_claims"] as Dictionary).keys():
		if (
			typeof(token_value) != TYPE_INT
			or not action_ids.has(int(token_value))
			or typeof((state["hit_fact_claims"] as Dictionary)[token_value]) != TYPE_BOOL
			or not bool((state["hit_fact_claims"] as Dictionary)[token_value])
		):
			return false
	for resource_value: Variant in (state["resource_fact_state"] as Dictionary).values():
		if not resource_value is Dictionary:
			return false
		var resource := resource_value as Dictionary
		if not _dictionary_has_exact_fields(resource, ["current", "maximum"]):
			return false
		var current_value: Variant = resource["current"]
		var maximum_value: Variant = resource["maximum"]
		if (
			typeof(current_value) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(maximum_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(current_value))
			or not is_finite(float(maximum_value))
			or float(current_value) < 0.0
			or float(maximum_value) <= 0.0
			or float(current_value) > float(maximum_value)
		):
			return false
	return true


func _install_player_weapon_replay_state(state: Dictionary) -> void:
	_weapon_action_reward_claims = (state.get("action_reward_claims", {}) as Dictionary).duplicate(true)
	_weapon_action_ids_by_token = (state.get("action_ids_by_token", {}) as Dictionary).duplicate(true)
	_weapon_action_generations_by_token = (state.get("action_generations_by_token", {}) as Dictionary).duplicate(true)
	_weapon_action_token_order.clear()
	for token_value: Variant in state.get("action_token_order", []):
		_weapon_action_token_order.append(int(token_value))
	_weapon_hit_fact_claims = (state.get("hit_fact_claims", {}) as Dictionary).duplicate(true)
	_weapon_resource_fact_state = (state.get("resource_fact_state", {}) as Dictionary).duplicate(true)
	_next_weapon_action_token_floor = int(state.get("next_token_floor", 1))
	_weapon_combo_timeout_frames = int(state.get("combo_timeout_frames", 0))


func _weapon_replay_event_prefix_count() -> int:
	var captured: Dictionary = {}
	for event: Dictionary in _weapon_replay_events:
		var capture_sequence := int(event.get("capture_sequence", 0))
		if capture_sequence > 0:
			captured[capture_sequence] = true
	var count := 0
	while captured.has(count + 1):
		count += 1
	return count


func _valid_weapon_replay_event_prefix(snapshot: Dictionary, event_prefix: Array) -> bool:
	var expected_count := int(snapshot.get("event_prefix_count", -1))
	if expected_count < 0 or event_prefix.size() != expected_count:
		return false
	var profile: Dictionary = loadout_runtime.weapon_profile_snapshot()
	var expected_identity: Dictionary = ReplayRecorderScript.profile_identity(profile)
	for index: int in range(event_prefix.size()):
		var event_value: Variant = event_prefix[index]
		if not event_value is Dictionary:
			return false
		var event := event_value as Dictionary
		if (
			not _dictionary_has_exact_fields(event, WEAPON_REPLAY_EVENT_FIELDS)
			or ReplayRecorderScript.validate_event(event, expected_identity).is_empty()
			or int(event.get("capture_sequence", 0)) != index + 1
			or int(event.get("frame", -1)) > int(snapshot.get("frame", -1))
		):
			return false
	return ReplayRecorderScript.event_prefix_matches(snapshot, event_prefix)


func _install_weapon_replay_event_prefix(event_prefix: Array) -> void:
	_weapon_replay_events.clear()
	_weapon_replay_capture_sequence = 0
	for event_value: Variant in event_prefix:
		var event := (event_value as Dictionary).duplicate(true)
		_weapon_replay_events.append(event)
		_weapon_replay_capture_sequence = maxi(
			_weapon_replay_capture_sequence,
			int(event.get("capture_sequence", 0))
		)


func _truncate_weapon_replay_events(
	capture_sequence: int,
	preserve_pending_events: bool = false
) -> void:
	var retained: Array[Dictionary] = []
	for event: Dictionary in _weapon_replay_events:
		if preserve_pending_events or int(event.get("capture_sequence", 0)) <= capture_sequence:
			retained.append(event.duplicate(true))
	_weapon_replay_events = retained
	_weapon_replay_capture_sequence = 0
	for event: Dictionary in _weapon_replay_events:
		_weapon_replay_capture_sequence = maxi(
			_weapon_replay_capture_sequence,
			int(event.get("capture_sequence", 0))
		)


func _restore_weapon_replay_event_log(
	events: Array[Dictionary],
	capture_sequence: int
) -> void:
	_weapon_replay_events.clear()
	for event: Dictionary in events:
		_weapon_replay_events.append(event.duplicate(true))
	_weapon_replay_capture_sequence = capture_sequence


func _fail_closed_weapon_replay_restore(reason: StringName) -> void:
	if weapon_action_coordinator != null and weapon_action_coordinator.has_method("reset_runtime_state"):
		weapon_action_coordinator.call("reset_runtime_state", reason)
	_weapon_action_reward_claims.clear()
	_weapon_action_ids_by_token.clear()
	_weapon_action_generations_by_token.clear()
	_weapon_action_token_order.clear()
	_weapon_hit_fact_claims.clear()
	_weapon_resource_fact_state.clear()
	_weapon_combo_timeout_frames = 0
	_weapon_replay_events.clear()
	_weapon_replay_capture_sequence = 0
	_applying_weapon_replay_event = false
	action_state.force_safe_reset()
	_weapon_intent_router.call("reset_all")
	_capture_next_weapon_action_token_floor()
	_sync_weapon_action_projection()
	_sync_weapon_resource_facts(reason)
	if time_manager != null and time_manager.has_method("reset_runtime_state"):
		time_manager.call("reset_runtime_state")
	_refresh_weapon_replay_fact_baseline()


func _restore_weapon_coordinator_replay_snapshot(target: Dictionary) -> bool:
	if weapon_action_coordinator == null or not weapon_action_coordinator.has_method("restore_snapshot"):
		return false
	if not weapon_action_coordinator.has_method("snapshot"):
		return false
	var before_value: Variant = weapon_action_coordinator.call("snapshot")
	if not before_value is Dictionary:
		return false
	var before := (before_value as Dictionary).duplicate(true)
	if before == target:
		return true
	if bool(weapon_action_coordinator.call("restore_snapshot", target.duplicate(true))):
		return true
	var after_direct_value: Variant = weapon_action_coordinator.call("snapshot")
	if (
		not after_direct_value is Dictionary
		or (after_direct_value as Dictionary) != before
	) and not _rollback_weapon_coordinator_replay_snapshot(before):
		return false
	if _replay_weapon_coordinator_forward(target):
		return true
	_rollback_weapon_coordinator_replay_snapshot(before)
	return false


func _rollback_weapon_coordinator_replay_snapshot(target: Dictionary) -> bool:
	if (
		weapon_action_coordinator == null
		or not weapon_action_coordinator.has_method("restore_snapshot_for_rollback")
		or not weapon_action_coordinator.has_method("snapshot")
	):
		return false
	return (
		bool(weapon_action_coordinator.call(
			"restore_snapshot_for_rollback",
			target.duplicate(true)
		))
		and weapon_action_coordinator.call("snapshot") == target
	)


func _replay_weapon_coordinator_forward(target: Dictionary) -> bool:
	if weapon_action_coordinator == null or not weapon_action_coordinator.has_method("snapshot"):
		return false
	var current_value: Variant = weapon_action_coordinator.call("snapshot")
	if not current_value is Dictionary:
		return false
	var current := current_value as Dictionary
	if current == target:
		return true
	if (
		str(target.get("weapon_id", "")) != str(current.get("weapon_id", ""))
		or int(target.get("frame", -1)) < int(current.get("frame", -1))
	):
		return false
	var current_phase := StringName(str(current.get("phase", "")))
	if current_phase == &"READY":
		if (
			int(target.get("token", 0)) != int(current.get("next_token", 0))
			or int(target.get("generation", 0)) != int(current.get("generation", -1))
			or int(target.get("next_token", 0)) != int(current.get("next_token", 0)) + 1
		):
			return false
	else:
		for field: String in ["token", "generation", "next_token"]:
			if current.get(field) != target.get(field):
				return false
		if current_phase != &"HOLD" or StringName(str(target.get("phase", ""))) == &"HOLD":
			for field: String in ["plan", "action_context"]:
				if current.get(field) != target.get(field):
					return false

	_disconnect_weapon_coordinator()
	var succeeded := false
	if current_phase == &"READY":
		var plan_value: Variant = target.get("plan")
		if plan_value is Dictionary:
			var plan := plan_value as Dictionary
			var semantic_action := StringName(str(plan.get("semantic_action", "")))
			var base_context := _weapon_replay_base_context(target.get("action_context", {}) as Dictionary)
			if semantic_action != &"":
				var action_start_frame := _weapon_replay_action_start_frame(target)
				while int((weapon_action_coordinator.call("snapshot") as Dictionary).get("frame", -1)) < action_start_frame:
					weapon_action_coordinator.call("advance_frame", false)
				var submitted_value: Variant = weapon_action_coordinator.call(
					"submit_intent",
					{"id": semantic_action, "edge": &"pressed", "held_frames": 0},
					base_context
				)
				succeeded = submitted_value is Dictionary and bool((submitted_value as Dictionary).get("ok", false))
	else:
		succeeded = true

	while succeeded:
		var replayed_value: Variant = weapon_action_coordinator.call("snapshot")
		if not replayed_value is Dictionary:
			succeeded = false
			break
		var replayed := replayed_value as Dictionary
		if replayed == target:
			break
		if int(replayed.get("frame", -1)) > int(target.get("frame", -1)):
			succeeded = false
			break
		if (
			StringName(str(replayed.get("phase", ""))) == &"HOLD"
			and StringName(str(target.get("phase", ""))) != &"HOLD"
			and int(replayed.get("frame", -1)) == int(
				(target.get("action_context", {}) as Dictionary).get("coordinator_frame", -1)
			)
		):
			var hold_plan := replayed.get("plan", {}) as Dictionary
			var release_value: Variant = weapon_action_coordinator.call(
				"submit_intent",
				{
					"id": StringName(str(hold_plan.get("semantic_action", ""))),
					"edge": &"released",
					"held_frames": int(replayed.get("phase_frame", 0)),
				},
				_weapon_replay_base_context(target.get("action_context", {}) as Dictionary)
			)
			if not release_value is Dictionary or not bool((release_value as Dictionary).get("ok", false)):
				succeeded = false
				break
			continue
		if int(replayed.get("frame", -1)) == int(target.get("frame", -1)):
			succeeded = false
			break
		weapon_action_coordinator.call("advance_frame", false)

	_connect_weapon_coordinator()
	return succeeded and weapon_action_coordinator.call("snapshot") == target


func _weapon_replay_base_context(committed_context: Dictionary) -> Dictionary:
	var result := committed_context.duplicate(true)
	for field: String in WEAPON_REPLAY_CONTEXT_RESERVED_FIELDS:
		result.erase(field)
	return result


func _weapon_replay_action_start_frame(target: Dictionary) -> int:
	var target_frame := int(target.get("frame", 0))
	if str(target.get("phase", "")) == "HOLD":
		return maxi(0, target_frame - int(target.get("phase_frame", 0)))
	var action_context := target.get("action_context", {}) as Dictionary
	var committed_frame := int(action_context.get("coordinator_frame", target_frame))
	var held_frames := int(action_context.get("held_frames", 0))
	return maxi(0, committed_frame - maxi(0, held_frames))


func _weapon_action_state_can_restore_replay() -> bool:
	return action_state.current_state in [
		PlayerActionStateScript.State.FREE,
		PlayerActionStateScript.State.ATTACK_WINDUP,
		PlayerActionStateScript.State.ATTACK_ACTIVE,
		PlayerActionStateScript.State.ATTACK_RECOVERY,
	]


func _sync_weapon_replay_intent_latch() -> void:
	_weapon_intent_router.call("reset_all")
	if weapon_action_coordinator == null or weapon_action_coordinator.phase_name() != &"HOLD":
		return
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.snapshot()
	var plan := coordinator_snapshot.get("plan", {}) as Dictionary
	var semantic_action := StringName(str(plan.get("semantic_action", "")))
	if semantic_action == &"":
		return
	_weapon_intent_router.call(
		"normalize_edge",
		semantic_action,
		&"pressed",
		0,
		&"hold"
	)


func _dictionary_has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func apply_weapon_modifier(capability: StringName, value: Variant) -> bool:
	if weapon_runtime == null or not weapon_runtime.has_method("apply_modifier"):
		return false
	return bool(weapon_runtime.call("apply_modifier", capability, value))


func apply_weapon_capability_effect(
	capability: StringName,
	value: Variant,
	base_value: float,
	stack_rule: StringName,
	required_weapon_id: StringName
) -> bool:
	return apply_weapon_capability_effects([{
		"capability": str(capability),
		"value": value,
		"base_value": base_value,
		"stack_rule": str(stack_rule),
		"weapon_id": str(required_weapon_id),
	}])


func apply_weapon_capability_effects(routes: Array) -> bool:
	if (
		routes.is_empty()
		or loadout_runtime == null
		or not loadout_runtime.has_method("has_weapon")
		or weapon_modifier_state == null
		or not weapon_modifier_state.has_method("snapshot")
		or not weapon_modifier_state.has_method("apply_batch")
		or not weapon_modifier_state.has_method("restore_snapshot")
		or weapon_runtime == null
		or not weapon_runtime.has_method("apply_modifier")
	):
		return false
	var snapshot_value: Variant = weapon_modifier_state.call("snapshot")
	if not snapshot_value is Dictionary:
		return false
	var staged := (snapshot_value as Dictionary).duplicate(true)
	var rollback_values: Dictionary = {}
	var matched_route := false
	for route_value: Variant in routes:
		if not route_value is Dictionary:
			return false
		var route := route_value as Dictionary
		var required_weapon_id := StringName(str(route.get("weapon_id", "")))
		if required_weapon_id == &"":
			return false
		if not bool(loadout_runtime.call("has_weapon", required_weapon_id)):
			continue
		matched_route = true
		var capability := StringName(str(route.get("capability", "")))
		var value: Variant = route.get("value")
		var base_value_variant: Variant = route.get("base_value")
		var stack_rule := StringName(str(route.get("stack_rule", "")))
		if (
			capability == &""
			or typeof(value) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(base_value_variant) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(value))
			or not is_finite(float(base_value_variant))
		):
			return false
		var capability_bounds_value: Variant = WEAPON_MODIFIER_BOUNDS.get(str(capability))
		if not capability_bounds_value is Dictionary:
			return false
		var capability_bounds := capability_bounds_value as Dictionary
		var base_value := float(base_value_variant)
		if (
			base_value < float(capability_bounds.get("minimum", INF))
			or base_value > float(capability_bounds.get("maximum", -INF))
		):
			return false
		if rollback_values.has(str(capability)):
			if not is_equal_approx(float(rollback_values[str(capability)]), float(
				(snapshot_value as Dictionary).get(str(capability), base_value)
			)):
				return false
		else:
			rollback_values[str(capability)] = float(
				(snapshot_value as Dictionary).get(str(capability), base_value)
			)
		var current := float(staged.get(str(capability), base_value))
		var numeric := float(value)
		var next_value: float
		match stack_rule:
			&"add":
				next_value = current + numeric
			&"maximum":
				next_value = maxf(current, numeric)
			&"multiply":
				next_value = current * numeric
			&"replace":
				next_value = numeric
			_:
				return false
		if (
			not is_finite(next_value)
			or next_value < float(capability_bounds.get("minimum", INF))
			or next_value > float(capability_bounds.get("maximum", -INF))
		):
			return false
		staged[str(capability)] = next_value
	if not matched_route:
		return false
	var updates: Dictionary = {}
	for capability_value: Variant in staged.keys():
		if (snapshot_value as Dictionary).get(capability_value) != staged[capability_value]:
			updates[str(capability_value)] = staged[capability_value]
	if updates.is_empty():
		return true
	if not bool(weapon_modifier_state.call("apply_batch", updates)):
		return false
	var synchronized_capabilities: Array[StringName] = []
	for capability_value: Variant in updates.keys():
		var synchronized_capability := StringName(str(capability_value))
		synchronized_capabilities.append(synchronized_capability)
		if not bool(weapon_runtime.call(
			"apply_modifier",
			synchronized_capability,
			updates[capability_value]
		)):
			for rollback_index: int in range(synchronized_capabilities.size() - 1, -1, -1):
				var rollback_capability := synchronized_capabilities[rollback_index]
				weapon_runtime.call(
					"apply_modifier",
					rollback_capability,
					rollback_values.get(str(rollback_capability), 0.0)
				)
			weapon_modifier_state.call("restore_snapshot", snapshot_value as Dictionary)
			return false
	return true


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
	_refresh_weapon_replay_fact_baseline()
	var before: Dictionary = (
		time_manager.call("weapon_replay_snapshot")
		if time_manager.has_method("weapon_replay_snapshot")
		else {}
	)
	var claimed := bool(time_manager.call("claim_weapon_interaction", interaction_id, generation))
	if claimed and not _applying_weapon_replay_event and not before.is_empty():
		var identity := _current_weapon_replay_fact_identity()
		var after: Dictionary = time_manager.call("weapon_replay_snapshot")
		_record_weapon_replay_external_fact(
			"time_interaction_claim",
			int(identity.get("token", 0)),
			int(identity.get("generation", 0)),
			{
				"interaction_id": str(interaction_id),
				"generation": generation,
				"state_before": before,
				"state_after": after,
			}
		)
	return claimed


func extend_weapon_time_stop(action_token: int, extension_frames: int) -> bool:
	return _extend_weapon_time_stop_internal(action_token, extension_frames, true)


func extend_weapon_time_stop_for_payload_result(
	action_token: int,
	payload_generation: int,
	extension_frames: int
) -> bool:
	if (
		loadout_runtime == null
		or not loadout_runtime.has_weapon(&"gauntlets")
		or action_token <= 0
		or payload_generation != action_token
		or not _weapon_action_generations_by_token.has(action_token)
		or weapon_action_coordinator == null
		or not weapon_action_coordinator.has_method("snapshot")
	):
		return false
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.call("snapshot")
	var runtime_value: Variant = coordinator_snapshot.get("runtime")
	if (
		int(coordinator_snapshot.get("token", 0)) != action_token
		or str(coordinator_snapshot.get("phase", "")) != "ACTIVE"
		or not runtime_value is Dictionary
	):
		return false
	var ledgers_value: Variant = (runtime_value as Dictionary).get("action_ledgers")
	var token_key := str(action_token)
	if (
		not ledgers_value is Dictionary
		or not (ledgers_value as Dictionary).has(token_key)
		or not (ledgers_value as Dictionary)[token_key] is Dictionary
		or int(((ledgers_value as Dictionary)[token_key] as Dictionary).get("generation", 0))
			!= payload_generation
	):
		return false
	return _extend_weapon_time_stop_internal(action_token, extension_frames, false)


func _extend_weapon_time_stop_internal(
	action_token: int,
	extension_frames: int,
	record_standalone_fact: bool
) -> bool:
	if time_manager == null or not time_manager.has_method("extend_stop_for_weapon"):
		return false
	if record_standalone_fact:
		_refresh_weapon_replay_fact_baseline()
	var before: Dictionary = (
		time_manager.call("weapon_replay_snapshot")
		if time_manager.has_method("weapon_replay_snapshot")
		else {}
	)
	var extended := bool(time_manager.call("extend_stop_for_weapon", action_token, extension_frames))
	if (
		extended
		and record_standalone_fact
		and not _applying_weapon_replay_event
		and not before.is_empty()
	):
		var generation := int(_weapon_action_generations_by_token.get(action_token, 0))
		_record_weapon_replay_external_fact(
			"time_stop_extension",
			action_token,
			generation,
			{
				"extension_frames": extension_frames,
				"state_before": before,
				"state_after": time_manager.call("weapon_replay_snapshot"),
			}
		)
	return extended


func _current_weapon_replay_fact_identity() -> Dictionary:
	if weapon_action_coordinator == null or not weapon_action_coordinator.has_method("snapshot"):
		return {}
	var snapshot: Dictionary = weapon_action_coordinator.call("snapshot")
	var token := int(snapshot.get("token", 0))
	var generation := int(snapshot.get("generation", 0))
	if token <= 0 or generation <= 0:
		return {}
	return {"token": token, "generation": generation}


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
	return _submit_normalized_weapon_intent_with_context(
		intent,
		_weapon_submission_context(),
		true
	)


func _submit_normalized_weapon_intent_with_context(
	intent: Dictionary,
	submission_context: Dictionary,
	record_replay_event: bool
) -> bool:
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
		submission_context.duplicate(true)
	)
	_sync_weapon_action_projection()
	_sync_weapon_resource_facts(&"intent_commit")
	if not bool(result.get("ok", false)):
		_reset_weapon_intent_latch(intent)
		return false
	if record_replay_event:
		_record_weapon_replay_event(submitted_intent, submission_context)
	return true


func _record_weapon_replay_event(intent: Dictionary, submission_context: Dictionary) -> void:
	if weapon_action_coordinator == null:
		return
	_append_weapon_replay_event("weapon_intent", {
		"semantic_action": str(intent.get("id", "")),
		"edge": str(intent.get("edge", "")),
		"held_frames": int(intent.get("held_frames", 0)),
		"context": submission_context.duplicate(true),
	})


func _append_weapon_replay_event(event_type: String, payload: Dictionary) -> int:
	if weapon_action_coordinator == null or event_type not in ["weapon_intent", "external_fact"]:
		return 0
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.snapshot()
	var frame := int(coordinator_snapshot.get("frame", -1))
	if frame < 0:
		return 0
	_weapon_replay_capture_sequence += 1
	_weapon_replay_events.append({
		"schema_version": WEAPON_REPLAY_EVENT_SCHEMA_VERSION,
		"frame": frame,
		"capture_sequence": _weapon_replay_capture_sequence,
		"event_type": event_type,
		"payload": payload.duplicate(true),
	})
	_refresh_weapon_replay_fact_baseline()
	return _weapon_replay_capture_sequence


func _record_weapon_replay_external_fact(
	fact_type: String,
	action_token: int,
	action_generation: int,
	data: Dictionary
) -> bool:
	if (
		_applying_weapon_replay_event
		or fact_type not in ReplayRecorderScript.VALID_EXTERNAL_FACT_TYPES
		or action_token <= 0
		or action_generation <= 0
		or data.is_empty()
		or loadout_runtime == null
	):
		return false
	var recorded_data := data.duplicate(true)
	if fact_type in WEAPON_REPLAY_STATE_FACT_TYPES:
		if _weapon_replay_fact_baseline.is_empty():
			return false
		recorded_data["state_before_digest"] = ReplayRecorderScript.value_digest(
			_weapon_replay_fact_baseline
		)
	var next_capture_sequence := _weapon_replay_capture_sequence + 1
	var payload := {
		"fact_type": fact_type,
		"fact_id": "%s:%d:%d:%d" % [
			fact_type,
			action_token,
			action_generation,
			next_capture_sequence,
		],
		"weapon_id": str(loadout_runtime.weapon_id()),
		"action_token": action_token,
		"action_generation": action_generation,
		"data": recorded_data,
	}
	if not _weapon_replay_recorded_external_fact_is_valid(
		payload,
		recorded_data,
		next_capture_sequence
	):
		return false
	return _append_weapon_replay_event("external_fact", payload) > 0


func _weapon_replay_recorded_external_fact_is_valid(
	payload: Dictionary,
	data: Dictionary,
	next_capture_sequence: int
) -> bool:
	if (
		next_capture_sequence <= 0
		or weapon_action_coordinator == null
		or not weapon_action_coordinator.has_method("snapshot")
		or loadout_runtime == null
		or not loadout_runtime.has_method("weapon_profile_snapshot")
	):
		return false
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.call("snapshot")
	var frame := int(coordinator_snapshot.get("frame", -1))
	var profile: Dictionary = loadout_runtime.call("weapon_profile_snapshot")
	var expected_identity := ReplayRecorderScript.profile_identity(profile)
	var prospective_event := {
		"schema_version": WEAPON_REPLAY_EVENT_SCHEMA_VERSION,
		"frame": frame,
		"sequence": next_capture_sequence,
		"capture_sequence": next_capture_sequence,
		"event_type": "external_fact",
		"payload": payload.duplicate(true),
	}
	if (
		frame < 0
		or expected_identity.is_empty()
		or ReplayRecorderScript.validate_event(
			prospective_event,
			expected_identity
		).is_empty()
	):
		return false
	var state_before := _weapon_replay_fact_baseline.duplicate(true)
	var current := weapon_replay_snapshot()
	if state_before.is_empty() or current.is_empty():
		return false
	var fact_type := str(payload.get("fact_type", ""))
	if fact_type in WEAPON_REPLAY_STATE_FACT_TYPES:
		var state_after_value: Variant = data.get("state_after")
		if not state_after_value is Dictionary:
			return false
		var state_after := _validated_weapon_replay_snapshot(state_after_value as Dictionary)
		return (
			not state_after.is_empty()
			and current == state_after
			and _weapon_replay_state_fact_transition_is_valid(
				payload,
				data,
				state_before,
				state_after
			)
		)
	if fact_type in WEAPON_REPLAY_TIME_FACT_TYPES:
		if not _weapon_replay_time_fact_transition_is_valid(payload, data, state_before):
			return false
		var expected_after := state_before.duplicate(true)
		expected_after["time_manager_state"] = (
			data["state_after"] as Dictionary
		).duplicate(true)
		return current == expected_after
	return false


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
	if (
		weapon_id == &"sword"
		and (
			not next_runtime.has_method("bind_adapter")
			or not bool(next_runtime.call("bind_adapter", _weapon_adapter(weapon_id)))
		)
	):
		return {"ok": false, "reason": "payload_adapter_binding_failed"}
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
	var damage_state_after := weapon_replay_snapshot()
	var action_generation := int(_weapon_action_generations_by_token.get(action_token, 0))
	_complete_latest_weapon_damage_fact_state_after(
		action_token,
		action_generation,
		target,
		damage_state_after
	)
	var before := weapon_replay_snapshot()
	_weapon_hit_fact_claims[action_token] = true
	EventBus.weapon_hit_confirmed.emit(
		&"gun",
		action_id,
		action_token,
		target.get_instance_id(),
		{"source": "gun_projectile", "scope": "action"}
	)
	if not _applying_weapon_replay_event and not before.is_empty() and target.is_inside_tree():
		_record_weapon_replay_external_fact(
			"weapon_hit_claim",
			action_token,
			action_generation,
			{
				"target_path": str(get_path_to(target)),
				"state_before_digest": ReplayRecorderScript.value_digest(before),
				"state_after": weapon_replay_snapshot(),
			}
		)


func _complete_latest_weapon_damage_fact_state_after(
	action_token: int,
	action_generation: int,
	target: Node,
	state_after: Dictionary
) -> void:
	if (
		action_token <= 0
		or action_generation <= 0
		or target == null
		or not is_instance_valid(target)
		or state_after.is_empty()
		or not is_inside_tree()
		or not target.is_inside_tree()
	):
		return
	var target_path := str(get_path_to(target))
	for index: int in range(_weapon_replay_events.size() - 1, -1, -1):
		var event := _weapon_replay_events[index]
		if str(event.get("event_type", "")) != "external_fact":
			continue
		var payload_value: Variant = event.get("payload")
		if not payload_value is Dictionary:
			continue
		var payload := payload_value as Dictionary
		if (
			str(payload.get("fact_type", "")) != "combat_damage"
			or int(payload.get("action_token", 0)) != action_token
			or int(payload.get("action_generation", 0)) != action_generation
		):
			continue
		var data_value: Variant = payload.get("data")
		if not data_value is Dictionary:
			continue
		var data := data_value as Dictionary
		if str(data.get("target_path", "")) != target_path:
			continue
		var completed_event := event.duplicate(true)
		var completed_payload := completed_event["payload"] as Dictionary
		var completed_data := completed_payload["data"] as Dictionary
		var original_state_after := completed_data.get("state_after", {}) as Dictionary
		var completed_state_after := state_after.duplicate(true)
		completed_state_after["event_prefix_count"] = int(
			original_state_after.get("event_prefix_count", -1)
		)
		completed_state_after["event_prefix_root"] = str(
			original_state_after.get("event_prefix_root", "")
		)
		completed_data["state_after"] = completed_state_after
		_weapon_replay_events[index] = completed_event
		_refresh_weapon_replay_fact_baseline()
		return


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
	):
		return
	var before_snapshot := weapon_replay_snapshot()
	var before := float(time_manager.energy)
	if not claim_weapon_action_reward(
		action_token,
		StringName("resource:%s" % str(reward_id))
	):
		return
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
	if not _applying_weapon_replay_event and not before_snapshot.is_empty():
		var before_energy_state := _weapon_replay_time_energy_state(before_snapshot)
		_record_weapon_replay_external_fact(
			"weapon_resource_reward",
			action_token,
			int(_weapon_action_generations_by_token.get(action_token, 0)),
			{
				"claim_id": "",
				"reward_id": str(reward_id),
				"amount": amount,
				"energy_before": before,
				"energy_after": current,
				"maximum": float(time_manager.max_energy),
				"energy_revision_before": int(before_energy_state.get("revision", 0)),
				"state_before_digest": ReplayRecorderScript.value_digest(before_snapshot),
				"state_after": weapon_replay_snapshot(),
			}
		)


func _on_staff_resource_reward_requested(
	action_token: int,
	claim_id: StringName,
	reward_id: StringName,
	amount: float
) -> void:
	var generation := int(_weapon_action_generations_by_token.get(action_token, 0))
	var source_generation := _live_staff_reward_source_generation(
		action_token,
		claim_id
	)
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
		or source_generation <= 0
	):
		return
	var before_snapshot := weapon_replay_snapshot()
	var before := float(time_manager.energy)
	if not claim_weapon_action_reward(
		action_token,
		StringName(
			"resource:%s:%s:generation:%d" % [
				str(reward_id),
				str(claim_id),
				generation,
			]
		)
	):
		return
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
	if not _applying_weapon_replay_event and not before_snapshot.is_empty():
		var before_energy_state := _weapon_replay_time_energy_state(before_snapshot)
		_record_weapon_replay_external_fact(
			"weapon_resource_reward",
			action_token,
			generation,
			{
				"claim_id": str(claim_id),
				"reward_id": str(reward_id),
				"amount": amount,
				"energy_before": before,
				"energy_after": current,
				"maximum": float(time_manager.max_energy),
				"energy_revision_before": int(before_energy_state.get("revision", 0)),
				"state_before_digest": ReplayRecorderScript.value_digest(before_snapshot),
				"state_after": weapon_replay_snapshot(),
			}
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


func _live_staff_reward_source_generation(
	action_token: int,
	claim_id: StringName
) -> int:
	if staff_weapon == null or not staff_weapon.has_method("runtime_snapshot"):
		return 0
	var snapshot_value: Variant = staff_weapon.call("runtime_snapshot")
	if not snapshot_value is Dictionary:
		return 0
	var snapshot := snapshot_value as Dictionary
	var claims_value: Variant = snapshot.get("resource_reward_claims")
	var payloads_value: Variant = snapshot.get("owned_payloads")
	if (
		not claims_value is Dictionary
		or not payloads_value is Array
	):
		return 0
	var source_generation := 0
	for key_value: Variant in (claims_value as Dictionary).keys():
		var key := str(key_value)
		var parts := key.split(":", false, 2)
		if (
			parts.size() == 3
			and str(parts[0]).is_valid_int()
			and int(parts[0]) == action_token
			and str(parts[1]).is_valid_int()
			and int(parts[1]) > 0
			and str(parts[2]) == str(claim_id)
			and (claims_value as Dictionary)[key_value] == true
		):
			if source_generation > 0:
				return 0
			source_generation = int(parts[1])
	if source_generation <= 0:
		return 0
	var tick_index := _weapon_replay_staff_reward_tick_index(str(claim_id))
	if tick_index < 0:
		return 0
	var matched := 0
	for payload_value: Variant in payloads_value as Array:
		if not payload_value is Dictionary:
			continue
		var payload := payload_value as Dictionary
		var execution_value: Variant = payload.get("execution")
		if not execution_value is Dictionary:
			continue
		var execution := execution_value as Dictionary
		var parameters_value: Variant = execution.get("parameters")
		if (
			str(payload.get("kind", "")) != "zone"
			or int(payload.get("token", 0)) != action_token
			or int(payload.get("generation", 0)) != source_generation
			or str(execution.get("source_action_id", "")) != "primordial_wrath"
			or str(execution.get("mode", "")) != "seeded_sequence"
			or not parameters_value is Dictionary
		):
			continue
		var interval := int(execution.get("tick_interval_frames", 0))
		if (
			interval <= 0
			or tick_index >= int((parameters_value as Dictionary).get("count", 0))
			or int(execution.get("execution_frame", -1)) != (tick_index + 1) * interval
		):
			return 0
		matched += 1
	return source_generation if matched == 1 else 0


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
	action_token: int,
	generation: int,
	result: Dictionary
) -> void:
	if loadout_runtime == null or not loadout_runtime.has_weapon(&"staff"):
		return
	_sync_weapon_resource_facts(&"payload_result")
	_record_weapon_replay_payload_result(action_token, generation, result)


func _on_gauntlets_payload_result_reported(
	action_token: int,
	generation: int,
	result: Dictionary
) -> void:
	if loadout_runtime == null or not loadout_runtime.has_weapon(&"gauntlets"):
		return
	_record_weapon_replay_payload_result(action_token, generation, result)


func _record_weapon_replay_payload_result(
	action_token: int,
	generation: int,
	result: Dictionary
) -> void:
	var authoritative_generation := int(_weapon_action_generations_by_token.get(action_token, 0))
	if (
		action_token <= 0
		or generation <= 0
		or authoritative_generation <= 0
		or result.is_empty()
		or _applying_weapon_replay_event
	):
		return
	var state_after := weapon_replay_snapshot()
	if state_after.is_empty():
		return
	_record_weapon_replay_external_fact(
		"weapon_payload_result",
		action_token,
		authoritative_generation,
		{
			"result": result.duplicate(true),
			"payload_generation": generation,
			"state_after": state_after,
		}
	)


func _on_weapon_replay_hit_confirmed(
	damage_info: Variant,
	target: Node,
	final_amount: float
) -> void:
	if (
		_applying_weapon_replay_event
		or not damage_info is RefCounted
		or target == null
		or not is_instance_valid(target)
		or not is_finite(final_amount)
		or final_amount <= 0.0
		or (damage_info as RefCounted).get("attacker") != self
	):
		return
	var identity := _weapon_replay_damage_identity(damage_info as RefCounted)
	var action_token := int(identity.get("token", 0))
	var generation := int(identity.get("generation", 0))
	if action_token <= 0 or generation <= 0:
		return
	var health := target.get_node_or_null("HealthComponent")
	var health_path := NodePath("HealthComponent")
	if health == null and target.has_method("lose_health"):
		health = target
		health_path = NodePath(".")
	if (
		health == null
		or typeof(health.get("current_hp")) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(health.get("dead")) != TYPE_BOOL
		or not is_inside_tree()
		or not target.is_inside_tree()
	):
		return
	var hp_after := float(health.get("current_hp"))
	var hp_before := hp_after + final_amount
	_record_weapon_replay_external_fact(
		"combat_damage",
		action_token,
		generation,
		{
			"target_path": str(get_path_to(target)),
			"health_path": str(health_path),
			"hp_before": hp_before,
			"hp_after": hp_after,
			"resolved_damage": final_amount,
			"target_dead_after": bool(health.get("dead")),
			"state_after": weapon_replay_snapshot(),
		}
	)


func _weapon_replay_damage_identity(damage_info: RefCounted) -> Dictionary:
	var token := int(damage_info.get("action_token"))
	var generation := int(damage_info.get("source_generation"))
	var source_value: Variant = damage_info.get("source")
	if source_value is Object:
		var source := source_value as Object
		if token <= 0:
			token = int(_object_property_value(source, &"action_token", 0))
		if generation <= 0:
			generation = int(_object_property_value(source, &"generation", 0))
	if token <= 0:
		var active := _current_weapon_replay_fact_identity()
		token = int(active.get("token", 0))
		generation = int(active.get("generation", generation))
	var authoritative_generation := int(_weapon_action_generations_by_token.get(token, 0))
	if authoritative_generation > 0:
		generation = authoritative_generation
	if token <= 0 or generation <= 0 or not _weapon_action_ids_by_token.has(token):
		return {}
	return {"token": token, "generation": generation}


func _object_property_value(object: Object, property_name: StringName, fallback: Variant) -> Variant:
	if object == null:
		return fallback
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return object.get(property_name)
	return fallback


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
	var adapter := _weapon_adapter(weapon_id) as Node2D
	var rotation_value := _last_move_direction.angle()
	if adapter != null:
		rotation_value = float(adapter.global_rotation)
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
	_sync_weapon_adapter_stats()
