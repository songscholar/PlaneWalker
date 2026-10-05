class_name PlayerController
extends CharacterBody2D

signal authoritative_frame_committed(frame: int)

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

const StatsResource := preload("res://scripts/core/stats.gd")
const MetaStatsScript := preload("res://scripts/progression/meta_stats_applicator.gd")
const MetaCatalogFactoryScript := preload("res://scripts/progression/meta_catalog_factory.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const EventTemporaryModifierLayerScript := preload("res://scripts/events/event_temporary_modifier_layer.gd")
const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const ActiveItemRuntimeScript := preload("res://scripts/items/active_item_runtime.gd")
const EffectHandlerCatalogScript := preload(
	"res://scripts/content/effects/effect_handler_catalog.gd"
)
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerLoadoutRuntimeScript := preload("res://scripts/player/player_loadout_runtime.gd")
const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)
const PlayerCharacterRuntimeScript := preload(
	"res://scripts/player/characters/player_character_runtime.gd"
)
const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)
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
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const CHARACTER_WORLD_PAYLOAD_HANDLERS: Array[StringName] = [
	&"character_time_echo",
	&"character_time_shockwave",
	&"character_void_echo",
	&"void_devour_cone",
	&"realm_cleave_execution",
	&"planar_echo_execution",
]


class CharacterWorldPayloadNode extends Node2D:
	const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

	var _descriptor: Dictionary = {}
	var _owner_ref: WeakRef
	var _last_runtime_frame: int = -1
	var _resolved: bool = false


	func configure(descriptor: Dictionary, owner_entity: Node) -> bool:
		if (
			descriptor.is_empty()
			or owner_entity == null
			or not is_instance_valid(owner_entity)
			or not descriptor.get("geometry") is Dictionary
			or not descriptor.get("parameters") is Dictionary
		):
			return false
		_descriptor = descriptor.duplicate(true)
		_owner_ref = weakref(owner_entity)
		transform = descriptor.get("transform", Transform2D.IDENTITY)
		return true


	func advance_frame(runtime_frame: int) -> bool:
		if runtime_frame < 0 or (_last_runtime_frame >= 0 and runtime_frame <= _last_runtime_frame):
			return false
		_last_runtime_frame = runtime_frame
		return true


	func world_payload_frame_snapshot() -> Dictionary:
		return {
			"last_runtime_frame": _last_runtime_frame,
			"resolved": _resolved,
		}


	func restore_world_payload_frame_snapshot(value: Dictionary) -> bool:
		if (
			value.size() != 2
			or typeof(value.get("last_runtime_frame")) != TYPE_INT
			or int(value.get("last_runtime_frame", -2)) < -1
			or typeof(value.get("resolved")) != TYPE_BOOL
		):
			return false
		_last_runtime_frame = int(value["last_runtime_frame"])
		_resolved = bool(value["resolved"])
		return world_payload_frame_snapshot() == value


	func retire_world_payload(reason: StringName) -> void:
		if reason == &"expired" and not _resolved:
			_resolved = true
			_apply_payload_damage()


	func _apply_payload_damage() -> void:
		var owner_entity: Node = _owner_ref.get_ref() as Node if _owner_ref != null else null
		if owner_entity == null or not is_instance_valid(owner_entity):
			return
		var scene_tree := owner_entity.get_tree()
		if scene_tree == null:
			return
		var geometry := _descriptor.get("geometry", {}) as Dictionary
		var parameters := _descriptor.get("parameters", {}) as Dictionary
		var damage := float(parameters.get("damage", 0.0))
		if not is_finite(damage) or damage <= 0.0:
			return
		var targets_by_identity: Dictionary = {}
		for candidate: Node in SceneScope.nodes_in_group(owner_entity, &"enemies"):
			if not candidate is Node2D or not is_instance_valid(candidate):
				continue
			if not _geometry_contains_point(geometry, (candidate as Node2D).global_position):
				continue
			var target_identity := _target_id(candidate)
			if target_identity == &"" or targets_by_identity.has(target_identity):
				continue
			targets_by_identity[target_identity] = candidate
		var target_identities: Array = targets_by_identity.keys()
		target_identities.sort_custom(func(left: Variant, right: Variant) -> bool:
			return str(left) < str(right)
		)
		for target_identity_value: Variant in target_identities:
			var target := targets_by_identity[target_identity_value] as Node
			var target_health := target.get_node_or_null("HealthComponent")
			if target_health == null or not target_health.has_method("take_damage"):
				continue
			var info := DamageInfoScript.from_plan({
				"run_id": StringName(str(_descriptor.get("run_id", ""))),
				"target_id": StringName(str(target_identity_value)),
				"hostile_source_id": StringName("character_payload_%s" % str(
					_descriptor.get("payload_generation", 1)
				)),
				"attack_generation": maxi(1, int(_descriptor.get("payload_generation", 1))),
				"hit_index": 0,
				"action_token": maxi(1, int(_descriptor.get("source_token", 1))),
				"amount": damage,
				"damage_type": DamageInfoScript.DamageType.TIME,
				"source": self,
				"attacker": owner_entity,
				"can_crit": false,
				"knockback": Vector2.ZERO,
				"tags": (_descriptor.get("tags", []) as Array).duplicate(),
				"source_generation": maxi(1, int(_descriptor.get("owner_character_generation", 1))),
			})
			if info != null:
				target_health.call("take_damage", info)


	func _target_id(target: Node) -> StringName:
		if target == null or not is_instance_valid(target):
			return &""
		for key: StringName in [&"stable_target_id", &"stable_target_key", &"encounter_spawn_id"]:
			if not target.has_meta(key):
				continue
			var stable_value := str(target.get_meta(key)).strip_edges()
			if not stable_value.is_empty():
				return StringName(stable_value)
		return &""


	func _geometry_contains_point(geometry: Dictionary, point: Vector2) -> bool:
		match StringName(str(geometry.get("shape", ""))):
			&"circle":
				var center_value: Variant = geometry.get("center")
				var radius := float(geometry.get("radius", 0.0))
				return (
					center_value is Vector2
					and is_finite(radius)
					and radius > 0.0
					and point.distance_to(center_value as Vector2) <= radius
				)
			&"cone":
				var origin_value: Variant = geometry.get("origin")
				var aim_value: Variant = geometry.get("aim_direction")
				var length := float(geometry.get("length", 0.0))
				var degrees := float(geometry.get("degrees", 0.0))
				if (
					not origin_value is Vector2
					or not aim_value is Vector2
					or not is_finite(length)
					or length <= 0.0
					or not is_finite(degrees)
					or degrees <= 0.0
					or degrees > 360.0
				):
					return false
				var offset := point - (origin_value as Vector2)
				if offset.length_squared() <= 0.000001:
					return true
				var aim := (aim_value as Vector2).normalized()
				return (
					aim.length_squared() > 0.000001
					and offset.length() <= length
					and absf(aim.angle_to(offset.normalized())) <= deg_to_rad(degrees * 0.5)
				)
		return false

const DEFAULT_LOADOUT_CONFIG := {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}
const WEAPON_PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const CHARACTER_PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/character_runtime_profiles.json"
const BASE_CONTENT_PACK_PATH := "res://data/content_packs/base/pack.json"
const BASE_CONTENT_PACK_GAME_VERSION := "0.4.0-dev"
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
var _event_temporary_modifier_layer: RefCounted = EventTemporaryModifierLayerScript.new()

@onready var health: Node = $HealthComponent
@onready var loadout_runtime: Node = $PlayerLoadoutRuntime
@onready var time_manager: Node = $TimeManager
@onready var world_payload_authority: Node = $WorldPayloadAuthority
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

var _dash_cooldown_remaining_frames: int = 0
var _dash_velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _last_move_direction: Vector2 = Vector2.RIGHT
var _last_weapon_aim_direction: Vector2 = Vector2.RIGHT
var _dash_invulnerable_bonus: float = 0.0
var _runtime_frame: int = 0
var _last_authoritative_frame_intents: Dictionary = {}
var _last_authoritative_intents_frame: int = -1
var _last_authoritative_intents_run: StringName = &""
var _last_authoritative_intents_generation: int = -1
var _hostile_frame_participant: RefCounted
var _active_hostile_frame_ticket: Dictionary = {}
var _fixed_frame_weapon_observations: Array[Dictionary] = []
var _fixed_frame_commit_irreversible := false
var _reward_effect_publication_active: bool = false
var _reward_effect_publication_in_progress: bool = false
var _reward_effect_pending_health_signal: Dictionary = {}
var _reward_effect_pending_time_signal: Dictionary = {}
var _floor_rule_modifiers: Dictionary = {}
var active_item_runtime: RefCounted = ActiveItemRuntimeScript.new()
var _active_item_last_activation: Dictionary = {}
var _active_item_last_events: Array[Dictionary] = []
var _dash_completion_token: int = 0
var _dash_completed_at_runtime_frame: int = -1
var _dash_direction: Vector2 = Vector2.RIGHT
var _time_acceleration_multiplier: float = 1.0
var _time_acceleration_token: int = 0
var _time_acceleration_remaining: float = 0.0
var action_state = PlayerActionStateScript.new()
var character_action_coordinator: RefCounted = CharacterActionCoordinatorScript.new()
var character_runtime: RefCounted
var weapon_action_coordinator: RefCounted
var weapon_runtime: RefCounted
var weapon_runtime_profile: RefCounted
var weapon_modifier_state: RefCounted
var _weapon_combo_timeout_frames: int = 0
var _weapon_profile_compatibility_fallback: bool = false
var _buffered_time_skill: StringName = &""
var _next_time_action_token: int = 1
var _time_action_generation: int = 1
var _weapon_action_reward_claims: Dictionary = {}
var _weapon_action_ids_by_token: Dictionary = {}
var _weapon_action_generations_by_token: Dictionary = {}
var _weapon_action_mastery_contexts_by_token: Dictionary = {}
var _weapon_action_token_order: Array[int] = []
var _weapon_hit_fact_claims: Dictionary = {}
var _weapon_mastery_target_ids_by_token: Dictionary = {}
var _weapon_resource_fact_state: Dictionary = {}
var _weapon_resource_publication_enabled := true
var _next_weapon_action_token_floor: int = 1
var _weapon_replay_events: Array[Dictionary] = []
var _weapon_replay_capture_sequence: int = 0
var _applying_weapon_replay_event: bool = false
var _weapon_replay_fact_baseline: Dictionary = {}
var _weapon_replay_capture_invalid_reason: StringName = &""
var _weapon_replay_restore_invalid_reason: StringName = &""
var _weapon_intent_router: RefCounted = WeaponIntentRouterScript.new()
var _run_id: StringName = &""
var _owner_character_generation: int = 0
var _launch_replay_identity_baseline: Dictionary = {}
var _active_time_frame_signal_ticket: Dictionary = {}
var _active_health_frame_signal_ticket: Dictionary = {}
var _active_world_frame_ticket: Dictionary = {}
var _character_skill_live_hold_frames: int = 0
var _character_skill_input_owner: Dictionary = {}
var _last_priority_arbitration: Dictionary = {
	"frame": 0,
	"accepted": {},
	"decisions": [],
}

const DEFAULT_MOBILITY_PROFILE := {
	"dash_duration_frames": 17,
	"dash_cooldown_frames": 27,
	"dash_speed": 520.0,
	"dash_cost_kind": "none",
	"dash_cost": 0.0,
	"dash_invulnerable_frames": 12,
}
const MOBILITY_PROFILE_FIELDS: Array[String] = [
	"dash_duration_frames",
	"dash_cooldown_frames",
	"dash_speed",
	"dash_cost_kind",
	"dash_cost",
	"dash_invulnerable_frames",
]
var _mobility_profile: Dictionary = DEFAULT_MOBILITY_PROFILE.duplicate(true)
const KNOCKBACK_RETAINED_PER_FRAME := 0.8
const FIXED_FRAME_SECONDS := 1.0 / 60.0
const MAX_FIXED_FRAME_SLIDES := 4
const FRAME_INTENT_CATEGORIES: Array[String] = ["dash", "time", "active", "character", "weapon"]
const FRAME_INTENT_EDGES: Array[StringName] = [&"pressed", &"held", &"released"]
const FRAME_INTENT_MODES: Array[StringName] = [&"press", &"hold", &"toggle"]
const BASE_COLOR := Color(0.2, 0.85, 0.95)
const TIME_CAST_DURATION := 0.18
const HITSTUN_DURATION := 0.18
const TIME_CAST_MOVEMENT_MULTIPLIER := 0.35
const BOW_TARGET_DISTANCE_PIXELS := 8.0 * 64.0
const GUN_BASE_ATTACK := 15.0
const GAUNTLETS_BASE_ATTACK := 6.0
const STAFF_BASE_ATTACK := 9.0
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
	"action_mastery_contexts_by_token",
	"action_token_order",
	"hit_fact_claims",
	"mastery_target_ids_by_token",
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
const WEAPON_UPGRADE_SNAPSHOT_SCHEMA_VERSION := 1
const NONLETHAL_HEALTH_TICKET_SCHEMA_ID := "player_nonlethal_health_cost_ticket_v1"
const NONLETHAL_HEALTH_RECEIPT_SCHEMA_ID := "player_nonlethal_health_cost_receipt_v1"
const NONLETHAL_HEALTH_TRANSACTION_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const NONLETHAL_HEALTH_TICKET_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"cost",
	"before_snapshot",
	"after_snapshot",
	"fingerprint",
]
const NONLETHAL_HEALTH_RECEIPT_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"cost",
	"before_snapshot",
	"after_snapshot",
	"ticket_fingerprint",
	"fingerprint",
]

var _pending_nonlethal_health_costs: Dictionary = {}
var _committed_nonlethal_health_costs: Dictionary = {}


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
	var character_decision := _plan_character_damage_defense(damage_info)
	return {
		"weapon": weapon_decision,
		"character": character_decision,
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
	var equipped_adapter: Node = null
	if not weapon_decision.is_empty():
		var planned_weapon_id := _planned_defense_weapon_id(weapon_decision)
		var equipped_weapon_id: StringName = loadout_runtime.weapon_id()
		if planned_weapon_id == &"" or planned_weapon_id != equipped_weapon_id:
			return false
		equipped_adapter = _weapon_adapter(equipped_weapon_id)
		if (
			equipped_adapter == null
			or not equipped_adapter.has_method("can_commit_damage_defense")
			or not equipped_adapter.has_method("commit_damage_defense")
			or not bool(equipped_adapter.call(
				"can_commit_damage_defense",
				weapon_decision.duplicate(true),
				resolution
			))
		):
			return false

	var character_before: Dictionary = {}
	var character_action_before: Dictionary = {}
	if not character_decision.is_empty():
		if (
			character_action_coordinator == null
			or not character_action_coordinator.has_method("snapshot")
			or not character_action_coordinator.has_method("action_snapshot")
			or not character_action_coordinator.has_method("after_damage")
			or not _character_damage_commit_is_current(character_decision, resolution)
		):
			return false
		character_before = character_action_coordinator.call("snapshot")
		character_action_before = character_action_coordinator.call("action_snapshot")
		if character_before.is_empty() or character_action_before.is_empty():
			return false
		var commit_context := character_decision.get("commit_context", {}) as Dictionary
		var damage_context := (
			commit_context.get("damage_context", {}) as Dictionary
		).duplicate(true)
		var resolution_snapshot: Dictionary = resolution.call("snapshot")
		damage_context["decision"] = (
			commit_context.get("character_decision", {}) as Dictionary
		).duplicate(true)
		damage_context["finalized_damage"] = float(resolution.call("finalized_damage"))
		damage_context["prevented"] = bool(resolution.call("is_prevented"))
		damage_context["irreversible"] = bool(resolution_snapshot.get("irreversible", false))
		damage_context["applied"] = true
		var character_result: Variant = character_action_coordinator.call(
			"after_damage",
			damage_context
		)
		if (
			not character_result is Dictionary
			or not bool((character_result as Dictionary).get("ok", false))
			or not _apply_character_result_events(character_result as Dictionary)
		):
			_restore_character_coordinator_pair(character_before, character_action_before)
			return false

	if equipped_adapter == null:
		return true
	if bool(equipped_adapter.call(
		"commit_damage_defense",
		weapon_decision.duplicate(true),
		resolution
	)):
		_confirm_sword_guard_mastery(weapon_decision, resolution)
		return true
	if not character_before.is_empty():
		_restore_character_coordinator_pair(character_before, character_action_before)
	return false


func _plan_character_damage_defense(damage_info: RefCounted) -> Dictionary:
	if (
		damage_info == null
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("before_damage")
	):
		return {}
	var damage_context := _character_damage_context(damage_info)
	if damage_context.is_empty():
		return {}
	var result_value: Variant = character_action_coordinator.call(
		"before_damage",
		damage_context.duplicate(true)
	)
	if not result_value is Dictionary or not bool((result_value as Dictionary).get("ok", false)):
		return {"invalid_character_decision": true}
	var result_context := (result_value as Dictionary).get("context", {}) as Dictionary
	var raw_decision := result_context.get("decision", {}) as Dictionary
	var prevented := bool(raw_decision.get("prevented", false))
	var multiplier := float(raw_decision.get("combined_multiplier", 1.0))
	if not is_finite(multiplier) or multiplier < 0.0 or multiplier > 1.0:
		return {"invalid_character_decision": true}
	var guard_kind := StringName(str(raw_decision.get("guard_kind", "")))
	if guard_kind == &"none":
		guard_kind = &""
	var coordinator_snapshot: Dictionary = character_action_coordinator.call("snapshot")
	var action_snapshot: Dictionary = character_action_coordinator.call("action_snapshot")
	if coordinator_snapshot.is_empty() or action_snapshot.is_empty():
		return {"invalid_character_decision": true}
	return {
		"prevented": prevented,
		"multiplier": 1.0 if prevented else multiplier,
		"prevent_reason": &"character_guard" if prevented else &"",
		"guard_kind": guard_kind,
		"commit_context": {
			"character_decision": raw_decision.duplicate(true),
			"damage_context": damage_context.duplicate(true),
			"binding": {
				"run_id": _run_id,
				"runtime_frame": _runtime_frame,
				"owner_character_generation": _owner_character_generation,
				"character_id": StringName(str(character_runtime.call("character_id"))) if character_runtime != null else &"",
				"coordinator_revision": int(coordinator_snapshot.get("revision", -1)),
				"action_revision": int(action_snapshot.get("revision", -1)),
				"damage_run_id": StringName(str(damage_context.get("damage_run_id", ""))),
				"hostile_source_id": StringName(str(damage_context.get("hostile_source_id", ""))),
				"attack_generation": int(damage_context.get("attack_generation", 0)),
				"original_amount": float(damage_context.get("original_amount", -1.0)),
			},
		},
	}


func _character_damage_commit_is_current(
	character_decision: Dictionary,
	resolution: RefCounted
) -> bool:
	if resolution == null or not resolution.has_method("snapshot"):
		return false
	var commit_context_value: Variant = character_decision.get("commit_context")
	if not commit_context_value is Dictionary:
		return false
	var commit_context := commit_context_value as Dictionary
	var raw_decision_value: Variant = commit_context.get("character_decision")
	var damage_context_value: Variant = commit_context.get("damage_context")
	var binding_value: Variant = commit_context.get("binding")
	if (
		not raw_decision_value is Dictionary
		or not damage_context_value is Dictionary
		or not binding_value is Dictionary
	):
		return false
	var raw_decision := raw_decision_value as Dictionary
	var damage_context := damage_context_value as Dictionary
	var binding := binding_value as Dictionary
	var coordinator_snapshot: Dictionary = character_action_coordinator.call("snapshot")
	var action_snapshot: Dictionary = character_action_coordinator.call("action_snapshot")
	var resolution_snapshot: Dictionary = resolution.call("snapshot")
	var expected_guard_kind := StringName(str(raw_decision.get("guard_kind", "")))
	if expected_guard_kind == &"none":
		expected_guard_kind = &""
	var expected_prevented := bool(raw_decision.get("prevented", false))
	var expected_multiplier := float(raw_decision.get("combined_multiplier", 1.0))
	return (
		binding.size() == 10
		and StringName(str(binding.get("run_id", ""))) == _run_id
		and int(binding.get("runtime_frame", -1)) == _runtime_frame
		and int(binding.get("owner_character_generation", 0)) == _owner_character_generation
		and character_runtime != null
		and StringName(str(binding.get("character_id", "")))
		== StringName(str(character_runtime.call("character_id")))
		and int(binding.get("coordinator_revision", -1))
		== int(coordinator_snapshot.get("revision", -2))
		and int(binding.get("action_revision", -1))
		== int(action_snapshot.get("revision", -2))
		and bool(character_decision.get("prevented", false)) == expected_prevented
		and is_equal_approx(
			float(character_decision.get("multiplier", -1.0)),
			1.0 if expected_prevented else expected_multiplier
		)
		and StringName(str(character_decision.get("guard_kind", ""))) == expected_guard_kind
		and StringName(str(binding.get("hostile_source_id", "")))
		== StringName(str(damage_context.get("hostile_source_id", "")))
		and int(binding.get("attack_generation", 0))
		== int(damage_context.get("attack_generation", -1))
		and is_equal_approx(
			float(binding.get("original_amount", -1.0)),
			float(damage_context.get("original_amount", -2.0))
		)
		and StringName(str(resolution_snapshot.get("run_id", "")))
		== StringName(str(binding.get("damage_run_id", "")))
		and StringName(str(resolution_snapshot.get("hostile_source_id", "")))
		== StringName(str(binding.get("hostile_source_id", "")))
		and int(resolution_snapshot.get("attack_generation", -1))
		== int(binding.get("attack_generation", -2))
		and is_equal_approx(
			float(resolution_snapshot.get("original_amount", -1.0)),
			float(binding.get("original_amount", -2.0))
		)
	)


func _character_damage_context(damage_info: RefCounted) -> Dictionary:
	if damage_info == null or not damage_info.has_method("snapshot"):
		return {}
	var snapshot_value: Variant = damage_info.call("snapshot")
	if not snapshot_value is Dictionary or (snapshot_value as Dictionary).is_empty():
		return {}
	var snapshot := snapshot_value as Dictionary
	var incoming_direction := Vector2.ZERO
	var attacker_value: Variant = snapshot.get("attacker")
	if attacker_value is Node2D and is_instance_valid(attacker_value):
		incoming_direction = global_position.direction_to((attacker_value as Node2D).global_position)
	var knockback := snapshot.get("knockback", Vector2.ZERO) as Vector2
	if incoming_direction.length_squared() <= 0.000001 and knockback.length_squared() > 0.000001:
		incoming_direction = -knockback.normalized()
	var tags: Array[String] = []
	for tag_value: Variant in snapshot.get("tags", []) as Array:
		tags.append(str(tag_value))
	var hostile_source_id := StringName(str(snapshot.get("hostile_source_id", "")))
	var attack_generation := int(snapshot.get("attack_generation", 0))
	return {
		"runtime_frame": _runtime_frame,
		"run_id": _run_id,
		"damage_run_id": StringName(str(snapshot.get("run_id", ""))),
		"run_revision": _owner_character_generation,
		"owner_character_generation": _owner_character_generation,
		"hostile_source_id": hostile_source_id,
		"attack_generation": attack_generation,
		"original_amount": float(snapshot.get("amount", 0.0)),
		"tags": tags,
		"facing_direction": _last_move_direction,
		"incoming_direction": incoming_direction,
		"source_kind": (
			&"enemy"
			if hostile_source_id != &"" and attack_generation > 0 and not tags.has("self_cost")
			else &"other"
		),
	}


func _planned_defense_weapon_id(decision: Dictionary) -> StringName:
	var context_value: Variant = decision.get("commit_context", {})
	if not context_value is Dictionary:
		return &""
	var weapon_id_value: Variant = (context_value as Dictionary).get("weapon_id", &"")
	if typeof(weapon_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return &""
	return StringName(str(weapon_id_value))


func _restore_character_coordinator_pair(
	coordinator_snapshot: Dictionary,
	action_snapshot: Dictionary
) -> bool:
	return (
		character_action_coordinator != null
		and character_action_coordinator.has_method("restore_snapshot")
		and character_action_coordinator.has_method("restore_action_snapshot")
		and bool(character_action_coordinator.call(
			"restore_snapshot",
			coordinator_snapshot.duplicate(true)
		))
		and bool(character_action_coordinator.call(
			"restore_action_snapshot",
			action_snapshot.duplicate(true)
		))
	)


func _apply_character_result_events(result: Dictionary) -> bool:
	var events_value: Variant = result.get("events", [])
	if not events_value is Array:
		return false
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary or not _apply_character_event(event_value as Dictionary):
			return false
	return true


func apply_character_runtime_events(events: Array) -> bool:
	for event_value: Variant in events:
		if not event_value is Dictionary or not _apply_character_event(event_value as Dictionary):
			return false
	return true


func character_time_action_participant_snapshot() -> Dictionary:
	if (
		character_action_coordinator == null
		or not character_action_coordinator.has_method("snapshot")
		or not character_action_coordinator.has_method("action_snapshot")
		or health == null
		or not health.has_method("runtime_state_snapshot")
	):
		return {}
	var coordinator_value: Variant = character_action_coordinator.call("snapshot")
	var action_value: Variant = character_action_coordinator.call("action_snapshot")
	var health_value: Variant = health.call("runtime_state_snapshot")
	if (
		not coordinator_value is Dictionary
		or not action_value is Dictionary
		or not health_value is Dictionary
	):
		return {}
	return {
		"character": (coordinator_value as Dictionary).duplicate(true),
		"character_action": (action_value as Dictionary).duplicate(true),
		"health": (health_value as Dictionary).duplicate(true),
	}


func restore_character_time_action_participant_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 3
		or not value.get("character") is Dictionary
		or not value.get("character_action") is Dictionary
		or not value.get("health") is Dictionary
	):
		return false
	var before := character_time_action_participant_snapshot()
	if before.is_empty():
		return false
	if before == value:
		return true
	var character_ok := _restore_character_coordinator_pair(
		(value["character"] as Dictionary).duplicate(true),
		(value["character_action"] as Dictionary).duplicate(true)
	)
	var health_ok := bool(health.call(
		"restore_replay_snapshot",
		(value["health"] as Dictionary).duplicate(true)
	))
	if character_ok and health_ok and character_time_action_participant_snapshot() == value:
		return true
	_restore_character_coordinator_pair(
		(before["character"] as Dictionary).duplicate(true),
		(before["character_action"] as Dictionary).duplicate(true)
	)
	health.call("restore_replay_snapshot", (before["health"] as Dictionary).duplicate(true))
	return false


func plan_character_time_action(context: Dictionary) -> Dictionary:
	if (
		character_action_coordinator == null
		or not character_action_coordinator.has_method("before_time_skill")
	):
		return {"ok": true, "decision": {}}
	var before := character_action_coordinator.call("snapshot") as Dictionary
	var action_before := character_action_coordinator.call("action_snapshot") as Dictionary
	var result_value: Variant = character_action_coordinator.call(
		"before_time_skill",
		context.duplicate(true)
	)
	if not result_value is Dictionary or not bool((result_value as Dictionary).get("ok", false)):
		_restore_character_coordinator_pair(before, action_before)
		return {"ok": false, "decision": {}}
	var after := character_action_coordinator.call("snapshot") as Dictionary
	var action_after := character_action_coordinator.call("action_snapshot") as Dictionary
	if after != before or action_after != action_before:
		_restore_character_coordinator_pair(before, action_before)
		return {"ok": false, "decision": {}}
	var result_context := (result_value as Dictionary).get("context", {}) as Dictionary
	return {
		"ok": true,
		"decision": (result_context.get("decision", {}) as Dictionary).duplicate(true),
	}


func commit_character_time_action(context: Dictionary) -> bool:
	if (
		character_action_coordinator == null
		or not character_action_coordinator.has_method("after_time_skill")
	):
		return true
	var result_value: Variant = character_action_coordinator.call(
		"after_time_skill",
		context.duplicate(true)
	)
	return (
		result_value is Dictionary
		and bool((result_value as Dictionary).get("ok", false))
		and _apply_character_result_events(result_value as Dictionary)
	)


func _apply_character_event(event: Dictionary) -> bool:
	var event_id := StringName(str(event.get("event_id", "")))
	var context_value: Variant = event.get("context", {})
	if event_id == &"" or not context_value is Dictionary:
		return false
	var context := context_value as Dictionary
	match event_id:
		&"time_energy_spend_requested":
			var amount := float(context.get("amount", -1.0))
			if not is_finite(amount) or amount < 0.0 or time_manager == null:
				return false
			var resource_state_value: Variant = time_manager.call("resource_state", &"time_energy")
			if not resource_state_value is Dictionary:
				return false
			var resource_state := resource_state_value as Dictionary
			var spend_value: Variant = time_manager.call(
				"try_spend_resource",
				&"time_energy",
				amount,
				int(resource_state.get("revision", 0)),
				StringName(str(context.get("reason", event_id)))
			)
			return spend_value is Dictionary and bool((spend_value as Dictionary).get("ok", false))
		&"time_energy_restore_requested":
			var amount := float(context.get("amount", -1.0))
			if not is_finite(amount) or amount < 0.0 or time_manager == null:
				return false
			time_manager.call("restore_energy", amount)
			return true
		&"health_restore_requested":
			var amount := float(context.get("amount", -1.0))
			if not is_finite(amount) or amount < 0.0 or health == null:
				return false
			health.call("heal", amount)
			return true
		&"irreversible_health_loss_requested":
			var amount := float(context.get("amount", -1.0))
			var source_token := int(context.get("source_token", 0))
			var source_generation := int(context.get("source_generation", 0))
			var reason := StringName(str(context.get("reason", event_id)))
			if (
				not is_finite(amount)
				or amount <= 0.0
				or source_token <= 0
				or source_generation <= 0
				or reason == &""
				or health == null
				or not health.has_method("lose_health_irreversible")
			):
				return false
			var resolution_value: Variant = health.call(
				"lose_health_irreversible",
				amount,
				reason,
				source_token,
				source_generation,
				_run_id
			)
			return (
				resolution_value is RefCounted
				and not bool((resolution_value as RefCounted).call("is_prevented"))
			)
		&"waypoint_recall_requested":
			var target_value: Variant = context.get("target_position")
			var heal_amount := float(context.get("heal_amount", -1.0))
			if (
				not target_value is Vector2
				or not is_finite((target_value as Vector2).x)
				or not is_finite((target_value as Vector2).y)
				or not is_finite(heal_amount)
				or heal_amount < 0.0
				or health == null
			):
				return false
			global_position = target_value as Vector2
			health.call("heal", heal_amount)
			return true
		&"world_payload_requested":
			var descriptor_value: Variant = context.get("descriptor")
			if not descriptor_value is Dictionary or world_payload_authority == null:
				return false
			var committed_value: Variant = world_payload_authority.call(
				"commit_payload",
				(descriptor_value as Dictionary).duplicate(true)
			)
			return committed_value is Dictionary and bool((committed_value as Dictionary).get("ok", false))
		&"time_cooldown_reduction_requested":
			if time_manager == null or not time_manager.has_method(
				"reduce_longer_equipped_cooldown_frames"
			):
				return false
			return bool(time_manager.call(
				"reduce_longer_equipped_cooldown_frames",
				(context.get("equipped_time_abilities", []) as Array).duplicate(),
				int(context.get("amount_frames", 0))
			))
		&"boss_exposure_extension_requested":
			if time_manager == null or not time_manager.has_method("extend_boss_exposure_frames"):
				return false
			return bool(time_manager.call(
				"extend_boss_exposure_frames",
				int(context.get("stop_generation", 0)),
				int(context.get("amount_frames", 0))
			))
		_:
			return true


func _reset_weapon_adapters() -> void:
	for adapter_value: Variant in _weapon_adapters.values():
		if adapter_value is Node and (adapter_value as Node).has_method("reset_runtime_state"):
			(adapter_value as Node).call("reset_runtime_state")


func sync_event_temporary_modifiers(modifiers: Array) -> bool:
	if stats == null or time_manager == null:
		return false
	var candidate = EventTemporaryModifierLayerScript.new()
	if not candidate.replace_projection(modifiers) or not is_finite(float(stats.attack) * candidate.attack_multiplier()):
		return false
	if not time_manager.call("set_event_energy_regen_multiplier", candidate.energy_regen_multiplier()):
		return false
	_event_temporary_modifier_layer = candidate
	_sync_weapon_adapter_stats()
	return true


func event_temporary_modifier_snapshot() -> Array:
	return _event_temporary_modifier_layer.call("snapshot")


func get_effective_attack() -> float:
	return float(stats.attack) * float(_event_temporary_modifier_layer.call("attack_multiplier")) if stats != null else 0.0


func get_damage_taken_multiplier() -> float:
	return _event_temporary_modifier_layer.call("damage_taken_multiplier")


func get_damage_taken_multiplier_for(damage_info: RefCounted) -> float:
	var multiplier := get_damage_taken_multiplier()
	if damage_info != null and damage_info.damage_type == DamageInfoScript.DamageType.VOID:
		var projection := meta_run_projection_snapshot()
		if not projection.is_empty():
			multiplier *= 1.0 - float(projection.stat_bonuses.void_reduction)
	return multiplier


func meta_run_projection_snapshot() -> Dictionary:
	if loadout_runtime == null:
		return {}
	var value: Variant = loadout_runtime.snapshot().get("meta_run_projection", {})
	return value.duplicate(true) if value is Dictionary else {}


func _sync_weapon_adapter_stats() -> void:
	var effective_attack := get_effective_attack()
	var character_attack_scale := effective_attack / 30.0
	var committed_attack_speed := (
		float(stats.attack_speed) * _time_acceleration_multiplier
	)
	for weapon_id: StringName in WEAPON_ADAPTER_IDS:
		var adapter := _weapon_adapter(weapon_id)
		if adapter == null:
			continue
		var base_attack: float
		match weapon_id:
			&"sword", &"bow":
				base_attack = effective_attack
			&"gun":
				base_attack = GUN_BASE_ATTACK * character_attack_scale
			&"staff":
				base_attack = STAFF_BASE_ATTACK * character_attack_scale
			&"gauntlets":
				base_attack = GAUNTLETS_BASE_ATTACK * character_attack_scale
			_:
				continue
		adapter.set("base_attack", base_attack)
		adapter.set("character_attack_scale", character_attack_scale)
		adapter.set("attack_speed", committed_attack_speed)
		adapter.set("crit_chance", float(stats.crit_chance))
		adapter.set("crit_multiplier", float(stats.crit_multiplier))


func apply_mobility_profile(profile: Dictionary) -> bool:
	var normalized := _normalized_mobility_profile(profile)
	if normalized.is_empty():
		return false
	_mobility_profile = normalized.duplicate(true)
	return true


func mobility_snapshot() -> Dictionary:
	return _mobility_profile.duplicate(true)


func _normalized_mobility_profile(profile: Dictionary) -> Dictionary:
	if profile.size() != MOBILITY_PROFILE_FIELDS.size():
		return {}
	for field: String in MOBILITY_PROFILE_FIELDS:
		if not profile.has(field):
			return {}
	for field: String in [
		"dash_duration_frames",
		"dash_cooldown_frames",
		"dash_invulnerable_frames",
	]:
		var frame_value: Variant = profile[field]
		if (
			typeof(frame_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(frame_value))
			or float(frame_value) != floorf(float(frame_value))
			or int(frame_value) <= 0
		):
			return {}
	if int(profile["dash_invulnerable_frames"]) > int(profile["dash_duration_frames"]):
		return {}
	if (
		typeof(profile["dash_speed"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(profile["dash_speed"]))
		or float(profile["dash_speed"]) <= 0.0
		or typeof(profile["dash_cost_kind"]) not in [TYPE_STRING, TYPE_STRING_NAME]
		or StringName(str(profile["dash_cost_kind"])) != &"none"
		or typeof(profile["dash_cost"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(profile["dash_cost"]))
		or not is_zero_approx(float(profile["dash_cost"]))
	):
		return {}
	return {
		"dash_duration_frames": int(profile["dash_duration_frames"]),
		"dash_cooldown_frames": int(profile["dash_cooldown_frames"]),
		"dash_speed": float(profile["dash_speed"]),
		"dash_cost_kind": "none",
		"dash_cost": 0.0,
		"dash_invulnerable_frames": int(profile["dash_invulnerable_frames"]),
	}


func _ready() -> void:
	add_to_group("player" if SceneScope.replay_world(self) == null else "replay_player")
	if not _discover_weapon_adapters():
		push_error("Player weapon adapter discovery failed")
		return
	if stats == null:
		stats = StatsResource.new()
	if not configure_run(&"standalone"):
		push_error("Player run identity configuration failed")
		return
	for handler_id: StringName in CHARACTER_WORLD_PAYLOAD_HANDLERS:
		if not world_payload_authority.register_factory(
			handler_id,
			Callable(self, "_spawn_character_world_payload")
		):
			push_error("WorldPayloadAuthority rejected Character payload factory %s" % handler_id)
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
	if not SceneScope.event_bus(self).hit_confirmed.is_connected(_on_weapon_replay_hit_confirmed):
		SceneScope.event_bus(self).hit_confirmed.connect(_on_weapon_replay_hit_confirmed)
	if not SceneScope.event_bus(self).room_started.is_connected(_on_character_room_started):
		SceneScope.event_bus(self).room_started.connect(_on_character_room_started)
	if not SceneScope.event_bus(self).room_cleared.is_connected(_on_character_room_cleared):
		SceneScope.event_bus(self).room_cleared.connect(_on_character_room_cleared)


func _spawn_character_world_payload(descriptor: Dictionary) -> Node:
	var handler_id := StringName(str(descriptor.get("handler_id", "")))
	if handler_id not in CHARACTER_WORLD_PAYLOAD_HANDLERS:
		return null
	var payload := CharacterWorldPayloadNode.new()
	if not payload.configure(descriptor, self):
		payload.free()
		return null
	return payload


func _physics_process(_delta: float) -> void:
	advance_action_frame(_collect_live_frame_intents())


func _advance_player_fixed_timers() -> void:
	if _dash_cooldown_remaining_frames > 0:
		_dash_cooldown_remaining_frames -= 1
	if _knockback_velocity.length_squared() <= 0.000001:
		_knockback_velocity = Vector2.ZERO
	else:
		_knockback_velocity *= KNOCKBACK_RETAINED_PER_FRAME


func _update_weapon_aim() -> void:
	_apply_weapon_aim_direction(_resolve_weapon_aim_direction(
		_right_stick_aim_direction(),
		global_position.direction_to(get_global_mouse_position())
	))


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
	_last_weapon_aim_direction = direction.normalized()
	var rotation_value := direction.angle()
	for adapter_value: Variant in _weapon_adapters.values():
		if adapter_value is Node2D:
			(adapter_value as Node2D).rotation = rotation_value


func _handle_priority_action_input() -> void:
	advance_action_frame(_collect_live_frame_intents())


func _collect_live_frame_intents() -> Dictionary:
	var result := _empty_frame_intents()
	result["movement"] = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	result["aim"] = _resolve_weapon_aim_direction(
		_right_stick_aim_direction(),
		global_position.direction_to(get_global_mouse_position())
	)
	if Input.is_action_just_pressed("dash"):
		(result["dash"] as Array).append(_frame_intent(&"dash", &"pressed", 0, &"press"))

	var queued_time_abilities: Dictionary = {}
	for slot_action: StringName in [&"time_slot_1", &"time_slot_2"]:
		if not Input.is_action_just_pressed(slot_action):
			continue
		var canonical_slot := _canonical_time_action_id(slot_action)
		if canonical_slot != &"":
			queued_time_abilities[canonical_slot] = true
		(result["time"] as Array).append(_frame_intent(slot_action, &"pressed", 0, &"press"))
	for action_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		if not Input.is_action_just_pressed(action_id):
			continue
		var canonical_id: StringName = time_manager.canonical_skill_id(action_id)
		if canonical_id == &"" or queued_time_abilities.has(canonical_id):
			continue
		queued_time_abilities[canonical_id] = true
		(result["time"] as Array).append(_frame_intent(action_id, &"pressed", 0, &"press"))
	if InputMap.has_action("active_item") and Input.is_action_just_pressed("active_item"):
		(result["active"] as Array).append(_frame_intent(
			&"active_item",
			&"pressed",
			0,
			&"press"
		))

	for intent: Dictionary in _collect_live_character_frame_intents():
		(result["character"] as Array).append(intent)
	for intent: Dictionary in _collect_raw_weapon_frame_intents():
		(result["weapon"] as Array).append(intent)
	return result


func _collect_live_character_frame_intents() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	if not InputMap.has_action("character_skill"):
		_character_skill_live_hold_frames = 0
		return intents
	var mode := _character_skill_input_mode()
	if Input.is_action_just_pressed("character_skill"):
		_character_skill_live_hold_frames = 0
		intents.append(_frame_intent(&"character_skill", &"pressed", 0, mode))
	elif Input.is_action_just_released("character_skill"):
		if mode == &"hold":
			intents.append(_frame_intent(
				&"character_skill",
				&"released",
				_character_skill_live_hold_frames,
				mode
			))
		_character_skill_live_hold_frames = 0
	elif Input.is_action_pressed("character_skill") and mode == &"hold":
		_character_skill_live_hold_frames += 1
		intents.append(_frame_intent(
			&"character_skill",
			&"held",
			_character_skill_live_hold_frames,
			mode
		))
	return intents


func _character_skill_input_mode() -> StringName:
	var profile: Dictionary = {}
	if loadout_runtime != null and loadout_runtime.has_method("character_profile_snapshot"):
		profile = loadout_runtime.call("character_profile_snapshot")
	elif character_runtime != null and character_runtime.has_method("profile_snapshot"):
		profile = character_runtime.call("profile_snapshot")
	var skill := profile.get("character_skill", {}) as Dictionary
	return &"hold" if int(skill.get("hold_threshold_frames", 0)) > 0 else &"press"


func _collect_raw_weapon_frame_intents() -> Array[Dictionary]:
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
		elif alias_still_pressed and mode in [&"hold", &"toggle"]:
			raw_edge = &"held"
		if raw_edge != &"":
			intents.append(_frame_intent(
				semantic_action,
				raw_edge,
				_current_weapon_hold_frames(),
				mode
			))
	return intents


func _empty_frame_intents() -> Dictionary:
	return {
		"dash": [],
		"time": [],
		"active": [],
		"weapon": [],
		"character": [],
		"movement": Vector2.ZERO,
		"aim": _last_weapon_aim_direction,
		"meta": {},
	}


func _frame_intent(
	action_id: StringName,
	edge: StringName,
	held_frames: int,
	mode: StringName
) -> Dictionary:
	return {
		"id": action_id,
		"edge": edge,
		"held_frames": held_frames,
		"mode": mode,
	}


func _validated_frame_intents(value: Dictionary) -> Dictionary:
	var grouped := _empty_frame_intents()
	if value.is_empty():
		return grouped
	var action_envelope := value.duplicate(true)
	for vector_key: String in ["movement", "aim"]:
		if not action_envelope.has(vector_key):
			continue
		if not action_envelope[vector_key] is Vector2:
			return {}
		var vector_value := action_envelope[vector_key] as Vector2
		if not is_finite(vector_value.x) or not is_finite(vector_value.y):
			return {}
		if vector_key == "movement" and vector_value.length_squared() > 1.0001:
			vector_value = vector_value.normalized()
		if vector_key == "aim" and vector_value.length_squared() > 0.001:
			vector_value = vector_value.normalized()
		grouped[vector_key] = vector_value
		action_envelope.erase(vector_key)
	if action_envelope.has("meta"):
		if not action_envelope["meta"] is Dictionary:
			return {}
		for meta_key_value: Variant in (action_envelope["meta"] as Dictionary).keys():
			if str(meta_key_value) not in ["source", "target_frame", "frame"]:
				return {}
		var nested_meta := action_envelope["meta"] as Dictionary
		if nested_meta.has("source"):
			if typeof(nested_meta["source"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return {}
			(grouped["meta"] as Dictionary)["source"] = str(nested_meta["source"])
		for frame_key: String in ["target_frame", "frame"]:
			if not nested_meta.has(frame_key):
				continue
			if typeof(nested_meta[frame_key]) != TYPE_INT or int(nested_meta[frame_key]) < 0:
				return {}
			(grouped["meta"] as Dictionary)[frame_key] = int(nested_meta[frame_key])
		action_envelope.erase("meta")
	if action_envelope.has("source"):
		if typeof(action_envelope["source"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {}
		(grouped["meta"] as Dictionary)["source"] = str(action_envelope["source"])
		action_envelope.erase("source")
	if action_envelope.has("target_frame"):
		if typeof(action_envelope["target_frame"]) != TYPE_INT or int(action_envelope["target_frame"]) < 0:
			return {}
		(grouped["meta"] as Dictionary)["target_frame"] = int(action_envelope["target_frame"])
		action_envelope.erase("target_frame")
	if action_envelope.has("frame"):
		if typeof(action_envelope["frame"]) != TYPE_INT or int(action_envelope["frame"]) < 0:
			return {}
		(grouped["meta"] as Dictionary)["frame"] = int(action_envelope["frame"])
		action_envelope.erase("frame")
	if action_envelope.is_empty():
		return grouped
	var uses_grouped_envelope := false
	for category: String in FRAME_INTENT_CATEGORIES:
		if action_envelope.has(category):
			uses_grouped_envelope = true
			break
	if uses_grouped_envelope:
		for key_value: Variant in action_envelope.keys():
			if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return {}
			var category := str(key_value)
			if category not in FRAME_INTENT_CATEGORIES or not action_envelope[key_value] is Array:
				return {}
			for entry_value: Variant in action_envelope[key_value] as Array:
				var entry := _validated_frame_intent_entry(entry_value, category)
				if entry.is_empty():
					return {}
				(grouped[category] as Array).append(entry)
		return grouped if _frame_intents_have_unique_edges(grouped) else {}

	for action_value: Variant in action_envelope.keys():
		if typeof(action_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {}
		var action_id := StringName(str(action_value))
		var category := _frame_intent_category(action_id)
		if category == &"" or not action_envelope[action_value] is Dictionary:
			return {}
		var shorthand := (action_envelope[action_value] as Dictionary).duplicate(true)
		shorthand["id"] = action_id
		var entry := _validated_frame_intent_entry(shorthand, str(category))
		if entry.is_empty():
			return {}
		(grouped[str(category)] as Array).append(entry)
	return grouped if _frame_intents_have_unique_edges(grouped) else {}


func _validated_frame_intent_entry(value: Variant, category: String) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source := value as Dictionary
	for key_value: Variant in source.keys():
		if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {}
		if str(key_value) not in ["id", "edge", "held_frames", "mode"]:
			return {}
	if typeof(source.get("id")) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {}
	var action_id := StringName(str(source.get("id", "")))
	var edge := StringName(str(source.get("edge", "pressed")))
	var held_frames_value: Variant = source.get("held_frames", 0)
	var mode := StringName(str(source.get("mode", (
		_weapon_semantic_input_mode(action_id)
		if category == "weapon"
		else "press"
	))))
	if (
		action_id == &""
		or _frame_intent_category(action_id) != StringName(category)
		or edge not in FRAME_INTENT_EDGES
		or typeof(held_frames_value) != TYPE_INT
		or int(held_frames_value) < 0
		or mode not in FRAME_INTENT_MODES
	):
		return {}
	return _frame_intent(action_id, edge, int(held_frames_value), mode)


func _frame_intent_category(action_id: StringName) -> StringName:
	if action_id == &"dash":
		return &"dash"
	if action_id in [
		&"time_slot_1", &"time_slot_2", &"time_stop", &"time_rewind",
		&"time_rift", &"time_accelerate",
	]:
		return &"time"
	if action_id == &"active_item":
		return &"active"
	if action_id in [
		&"weapon_primary", &"weapon_secondary", &"weapon_utility",
		&"weapon_skill", &"weapon_ultimate",
	]:
		return &"weapon"
	if str(action_id).begins_with("character_") or str(action_id).begins_with("character."):
		return &"character"
	return &""


func _frame_intents_have_unique_edges(value: Dictionary) -> bool:
	var seen: Dictionary = {}
	for category: String in FRAME_INTENT_CATEGORIES:
		for entry: Dictionary in value.get(category, []) as Array:
			var key := "%s:%s:%s" % [category, str(entry["id"]), str(entry["edge"])]
			if seen.has(key):
				return false
			seen[key] = true
	return true


func _apply_frame_intents(value: Dictionary) -> bool:
	_last_priority_arbitration = {
		"frame": _runtime_frame,
		"accepted": {},
		"decisions": [],
	}
	var ordered := _ordered_frame_intents(value)
	var accepted := false
	for ordered_value: Variant in ordered:
		var intent := ordered_value as Dictionary
		if accepted:
			_discard_suppressed_frame_intent(intent)
			_record_priority_decision(intent, &"priority_suppressed")
			continue
		var attempt := _attempt_frame_intent(intent, value)
		var status := StringName(str(attempt.get("status", "rejected")))
		_record_priority_decision(intent, status)
		if not bool(attempt.get("accepted", false)):
			continue
		accepted = true
		_last_priority_arbitration["accepted"] = {
			"category": str(intent.get("category", "")),
			"id": str(intent.get("id", "")),
			"edge": str(intent.get("edge", "")),
		}
	return true


func _ordered_frame_intents(value: Dictionary) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for category: String in FRAME_INTENT_CATEGORIES:
		var entries: Array[Dictionary] = []
		for entry_value: Variant in value.get(category, []) as Array:
			var entry := (entry_value as Dictionary).duplicate(true)
			entry["category"] = category
			entries.append(entry)
		entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_rank := _frame_intent_priority_rank(category, left)
			var right_rank := _frame_intent_priority_rank(category, right)
			if left_rank != right_rank:
				return left_rank < right_rank
			return _frame_edge_rank(StringName(str(left.get("edge", "")))) < _frame_edge_rank(
				StringName(str(right.get("edge", "")))
			)
		)
		ordered.append_array(entries)
	return ordered


func _frame_intent_priority_rank(category: String, intent: Dictionary) -> int:
	var action_id := StringName(str(intent.get("id", "")))
	match category:
		"dash":
			return 0
		"time":
			match action_id:
				&"time_slot_1":
					return 0
				&"time_slot_2":
					return 1
				&"time_stop":
					return 2
				&"time_rewind":
					return 3
				&"time_rift":
					return 4
				&"time_accelerate":
					return 5
		"character":
			return 0
		"active":
			return 0
		"weapon":
			var declaration_order := _weapon_semantic_priority_order()
			var declaration_index := declaration_order.find(action_id)
			return declaration_index if declaration_index >= 0 else declaration_order.size()
	return 100


func _frame_edge_rank(edge: StringName) -> int:
	match edge:
		&"pressed":
			return 0
		&"held":
			return 1
		&"released":
			return 2
	return 3


func _weapon_semantic_priority_order() -> Array[StringName]:
	var fallback: Array[StringName] = [
		&"weapon_primary",
		&"weapon_secondary",
		&"weapon_utility",
		&"weapon_skill",
		&"weapon_ultimate",
	]
	if weapon_runtime_profile == null or not weapon_runtime_profile.has_method("snapshot"):
		return fallback
	var profile_value: Variant = weapon_runtime_profile.call("snapshot")
	if not profile_value is Dictionary:
		return fallback
	var result: Array[StringName] = []
	for action_value: Variant in (profile_value as Dictionary).get("actions", []) as Array:
		if not action_value is Dictionary:
			continue
		var semantic_id := StringName(str((action_value as Dictionary).get("semantic_action", "")))
		if semantic_id in fallback and not result.has(semantic_id):
			result.append(semantic_id)
	for semantic_id: StringName in fallback:
		if not result.has(semantic_id):
			result.append(semantic_id)
	return result


func _attempt_frame_intent(intent: Dictionary, frame_intents: Dictionary) -> Dictionary:
	var category := StringName(str(intent.get("category", "")))
	var action_id := StringName(str(intent.get("id", "")))
	var edge := StringName(str(intent.get("edge", "")))
	match category:
		&"dash":
			return _frame_attempt_result(edge == &"pressed" and try_action(&"dash"))
		&"time":
			return _frame_attempt_result(edge == &"pressed" and try_action(action_id))
		&"active":
			return _frame_attempt_result(edge == &"pressed" and try_action(action_id))
		&"character":
			return _submit_character_frame_intent(intent, frame_intents)
		&"weapon":
			var normalized: Dictionary = _weapon_intent_router.call(
				"normalize_edge",
				action_id,
				edge,
				int(intent.get("held_frames", 0)),
				StringName(str(intent.get("mode", "press")))
			)
			if normalized.is_empty():
				return _frame_attempt_result(false)
			return _frame_attempt_result(_submit_normalized_weapon_intent(normalized))
	return _frame_attempt_result(false)


func _frame_attempt_result(accepted: bool, status: StringName = &"") -> Dictionary:
	return {
		"accepted": accepted,
		"status": status if status != &"" else (&"accepted" if accepted else &"rejected"),
	}


func _submit_character_frame_intent(
	intent: Dictionary,
	frame_intents: Dictionary
) -> Dictionary:
	var edge := StringName(str(intent.get("edge", "")))
	var mode := StringName(str(intent.get("mode", "press")))
	if edge in [&"held", &"released"] and not _character_input_owner_is_current():
		if edge == &"released":
			_clear_character_input_owner()
		return _frame_attempt_result(false, &"unowned_edge")
	if edge == &"held" and _character_input_owner_is_pending():
		return _frame_attempt_result(true, &"hold_pending")
	if character_action_coordinator == null or not character_action_coordinator.has_method(
		"try_character_skill"
	):
		if edge == &"released":
			_clear_character_input_owner()
		return _frame_attempt_result(false)
	var coordinator_before: Dictionary = {}
	var action_before: Dictionary = {}
	if (
		character_action_coordinator.has_method("snapshot")
		and character_action_coordinator.has_method("action_snapshot")
	):
		coordinator_before = character_action_coordinator.call("snapshot")
		action_before = character_action_coordinator.call("action_snapshot")
	var context := {
		"run_id": str(_run_id),
		"run_revision": _owner_character_generation,
		"owner_character_generation": _owner_character_generation,
		"runtime_frame": _runtime_frame,
		"alive": health != null and bool(health.call("is_alive")),
		"position": global_position,
		"current_hp": float(health.get("current_hp")) if health != null else 0.0,
		"maximum_hp": float(health.get("max_hp")) if health != null else 0.0,
		"attack": get_effective_attack(),
		"aim_direction": _last_weapon_aim_direction.normalized(),
		"time_energy": float(time_manager.get("energy")) if time_manager != null else 0.0,
		"movement": frame_intents.get("movement", Vector2.ZERO),
		"aim": frame_intents.get("aim", _last_weapon_aim_direction),
		"owner_token": int(_character_skill_input_owner.get("token", 0)),
		"owner_generation": int(_character_skill_input_owner.get("generation", 0)),
	}
	var result_value: Variant = character_action_coordinator.call(
		"try_character_skill",
		intent.duplicate(true),
		context
	)
	var result := (result_value as Dictionary) if result_value is Dictionary else {}
	var accepted := bool(result.get("ok", false))
	if not accepted and edge == &"pressed" and mode == &"hold":
		var pending_generation := int(action_before.get("generation", 0))
		var pending_token := int(action_before.get("next_token", 0))
		if pending_generation > 0 and pending_token > 0:
			_character_skill_input_owner = {
				"generation": pending_generation,
				"token": pending_token,
			}
			return _frame_attempt_result(true, &"hold_pending")
	if accepted and not _apply_character_result_events(result):
		if (
			coordinator_before.is_empty()
			or action_before.is_empty()
			or not _restore_character_coordinator_pair(coordinator_before, action_before)
		):
			set_physics_process(false)
		return _frame_attempt_result(false, &"character_event_rejected")
	if accepted and edge == &"pressed" and mode == &"hold":
		var result_context := result.get("context", {}) as Dictionary
		var generation := int(result_context.get("generation", 0))
		var token := int(result_context.get("token", 0))
		if generation > 0 and token > 0:
			_character_skill_input_owner = {
				"generation": generation,
				"token": token,
			}
	if edge == &"released":
		_clear_character_input_owner()
	return _frame_attempt_result(accepted)


func _discard_suppressed_frame_intent(intent: Dictionary) -> void:
	var category := StringName(str(intent.get("category", "")))
	var action_id := StringName(str(intent.get("id", "")))
	var edge := StringName(str(intent.get("edge", "")))
	if category == &"weapon" and action_id != &"":
		_weapon_intent_router.call("reset_action", action_id)
	elif category == &"character" and edge == &"released":
		_clear_character_input_owner()


func _record_priority_decision(intent: Dictionary, status: StringName) -> void:
	(_last_priority_arbitration["decisions"] as Array).append({
		"category": str(intent.get("category", "")),
		"id": str(intent.get("id", "")),
		"edge": str(intent.get("edge", "")),
		"status": str(status),
	})


func priority_arbitration_snapshot() -> Dictionary:
	return _last_priority_arbitration.duplicate(true)


func character_input_owner_snapshot() -> Dictionary:
	return {
		"active": not _character_skill_input_owner.is_empty(),
		"generation": int(_character_skill_input_owner.get("generation", 0)),
		"token": int(_character_skill_input_owner.get("token", 0)),
		"held_frames": _character_skill_live_hold_frames,
	}


func _valid_character_input_owner_snapshot(value: Dictionary) -> bool:
	if value.size() != 4:
		return false
	for field: String in ["active", "generation", "token", "held_frames"]:
		if not value.has(field):
			return false
	if (
		typeof(value["active"]) != TYPE_BOOL
		or typeof(value["generation"]) != TYPE_INT
		or typeof(value["token"]) != TYPE_INT
		or typeof(value["held_frames"]) != TYPE_INT
		or int(value["generation"]) < 0
		or int(value["token"]) < 0
		or int(value["held_frames"]) < 0
	):
		return false
	return (
		(bool(value["active"]) and int(value["generation"]) > 0 and int(value["token"]) > 0)
		or (
			not bool(value["active"])
			and int(value["generation"]) == 0
			and int(value["token"]) == 0
		)
	)


func _restore_character_input_owner_snapshot(value: Dictionary) -> bool:
	if not _valid_character_input_owner_snapshot(value):
		return false
	_character_skill_live_hold_frames = int(value["held_frames"])
	_character_skill_input_owner.clear()
	if bool(value["active"]):
		_character_skill_input_owner = {
			"generation": int(value["generation"]),
			"token": int(value["token"]),
		}
	return character_input_owner_snapshot() == value


func _character_input_owner_is_current() -> bool:
	if (
		_character_skill_input_owner.is_empty()
		or character_action_coordinator == null
	):
		return false
	var generation := int(_character_skill_input_owner.get("generation", 0))
	var token := int(_character_skill_input_owner.get("token", 0))
	if (
		character_action_coordinator.has_method("owns_action")
		and bool(character_action_coordinator.call("owns_action", generation, token))
	):
		return true
	return _character_input_owner_is_pending()


func _character_input_owner_is_pending() -> bool:
	if (
		_character_skill_input_owner.is_empty()
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("action_snapshot")
	):
		return false
	var action_value: Variant = character_action_coordinator.call("action_snapshot")
	if not action_value is Dictionary:
		return false
	var action := action_value as Dictionary
	return (
		int(action.get("generation", 0))
		== int(_character_skill_input_owner.get("generation", 0))
		and int(action.get("next_token", 0))
		== int(_character_skill_input_owner.get("token", 0))
		and int(action.get("current_token", 0)) == 0
		and (action.get("committed_plan", {}) as Dictionary).is_empty()
	)


func _clear_character_input_owner() -> void:
	_character_skill_input_owner.clear()
	_character_skill_live_hold_frames = 0


func _cancel_uncommitted_character_action(reason: StringName) -> bool:
	if character_action_coordinator == null:
		_clear_character_input_owner()
		return true
	if character_action_coordinator.has_method("cancel_uncommitted_action"):
		if not bool(character_action_coordinator.call("cancel_uncommitted_action", reason)):
			return false
	elif (
		character_action_coordinator.has_method("has_uncommitted_action")
		and bool(character_action_coordinator.call("has_uncommitted_action"))
	):
		return false
	_clear_character_input_owner()
	return true


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
	_apply_frame_movement(Input.get_vector("move_left", "move_right", "move_up", "move_down"))


func _apply_frame_movement(input_vector: Vector2) -> void:
	if input_vector.length_squared() > 0.001:
		_last_move_direction = input_vector.normalized()

	if action_state.current_state == PlayerActionStateScript.State.DASH:
		velocity = _dash_velocity * _floor_rule_movement_multiplier() + _knockback_velocity
	else:
		velocity = input_vector * stats.move_speed * _time_acceleration_multiplier * get_action_movement_multiplier() + _knockback_velocity
	var remaining_motion := velocity * FIXED_FRAME_SECONDS
	for _slide_index: int in range(MAX_FIXED_FRAME_SLIDES):
		if remaining_motion.is_zero_approx():
			break
		var collision := move_and_collide(remaining_motion)
		if collision == null:
			break
		var collision_normal := collision.get_normal()
		velocity = velocity.slide(collision_normal)
		remaining_motion = collision.get_remainder().slide(collision_normal)


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
		&"active_item":
			return bool(activate_equipped_active_item().get("ok", false))
		_:
			return false


func configure_loadout(config: Dictionary, meta_catalog: RefCounted = null) -> bool:
	if loadout_runtime == null or not _runtime_reset_preflight():
		return false
	var next_config := config.duplicate(true)
	var next_character_id := StringName(str(next_config.get("character_id", "wanderer")))
	var explicit_character_profile := next_config.has("character_profile")
	if explicit_character_profile:
		var character_profile_value: Variant = next_config.get("character_profile")
		if not character_profile_value is Dictionary:
			return false
		var supplied_character_profile := character_profile_value as Dictionary
		var authoritative_character_profile := _character_profile_catalog_definition(
			StringName(str(supplied_character_profile.get("id", "")))
		)
		if (
			_canonical_character_profile(authoritative_character_profile).is_empty()
			or _canonical_character_profile(supplied_character_profile)
			!= _canonical_character_profile(authoritative_character_profile)
		):
			return false
		next_config["character_profile"] = authoritative_character_profile.duplicate(true)
	else:
		var compatibility_character_profile := _default_character_profile_definition(
			next_character_id,
			StringName(str(next_config.get("milestone", "M1")))
		)
		if compatibility_character_profile.is_empty():
			return false
		next_config["character_id"] = str(next_character_id)
		next_config["character_profile"] = compatibility_character_profile.duplicate(true)
	if not next_config.has("character_talents"):
		next_config["character_talents"] = []
	if not _character_profile_allows_milestone(next_config):
		return false
	var character_profile := next_config.get("character_profile", {}) as Dictionary
	var next_stats = StatsResource.new()
	var permanent_stats: Dictionary = character_profile.get("base_stats", {})
	if next_config.has("meta_run_projection"):
		if str(next_config.get("milestone", "")) not in ["LAUNCH", "EXPANSION"] or not next_config.meta_run_projection is Dictionary:
			return false
		var selected_catalog := meta_catalog
		if selected_catalog == null:
			var loaded_catalog: Dictionary = MetaCatalogFactoryScript.load_base()
			if not loaded_catalog.ok:
				return false
			selected_catalog = loaded_catalog.context.catalog
		var prepared_stats: Dictionary = MetaStatsScript.prepare(character_profile, {}, str(next_config.get("weapon_id", "")), next_config.meta_run_projection, selected_catalog)
		if not prepared_stats.ok:
			return false
		permanent_stats = prepared_stats.context.stats
	if not bool(next_stats.call("apply_profile", permanent_stats)):
		return false
	var next_mobility := _normalized_mobility_profile(
		character_profile.get("mobility", {}) as Dictionary
	)
	if next_mobility.is_empty():
		return false
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

	var character_assembly := _assemble_character_runtime(next_config)
	if not bool(character_assembly.get("ok", false)):
		return false
	var assembly := _assemble_weapon_runtime(next_config)
	if not bool(assembly.get("ok", false)):
		return false
	var transaction_before := _loadout_configuration_transaction_snapshot()
	_capture_next_weapon_action_token_floor()
	if not loadout_runtime.configure(next_config):
		_rollback_loadout_configuration(transaction_before)
		return false
	if not _cancel_uncommitted_character_action(&"loadout_replacement"):
		_rollback_loadout_configuration(transaction_before)
		return false
	stats = next_stats
	_mobility_profile = next_mobility.duplicate(true)
	character_runtime = character_assembly.get("runtime") as RefCounted
	character_action_coordinator = character_assembly.get("coordinator") as RefCounted
	var assembled_runtime := assembly.get("runtime") as RefCounted
	if (
		bool(assembly.get("requires_adapter_activation", false))
		and (
			assembled_runtime == null
			or not assembled_runtime.has_method("activate_adapter")
			or not bool(assembled_runtime.call("activate_adapter"))
		)
	):
		_rollback_loadout_configuration(transaction_before)
		return false

	_disconnect_weapon_coordinator()
	weapon_runtime_profile = assembly.get("profile") as RefCounted
	weapon_modifier_state = assembly.get("modifiers") as RefCounted
	weapon_runtime = assembly.get("runtime") as RefCounted
	weapon_action_coordinator = assembly.get("coordinator") as RefCounted
	_weapon_profile_compatibility_fallback = used_compatibility_profile
	_connect_weapon_coordinator()
	if not reset_runtime_state():
		if not _rollback_loadout_configuration(transaction_before):
			set_physics_process(false)
			push_error("Loadout runtime reset rollback failed closed")
		return false
	if not _capture_launch_replay_identity_baseline():
		if not _rollback_loadout_configuration(transaction_before):
			set_physics_process(false)
			push_error("Loadout Replay identity rollback failed closed")
		return false
	return true


func _loadout_configuration_transaction_snapshot() -> Dictionary:
	var loadout: Dictionary = (
		(loadout_runtime.call("snapshot") as Dictionary).duplicate(true)
		if loadout_runtime != null and loadout_runtime.has_method("snapshot")
		else {}
	)
	return {
		"loadout": loadout,
		"full_player": full_player_replay_snapshot(),
		"stats_resource": stats,
		"stats_state": stats.snapshot() if stats != null and stats.has_method("snapshot") else {},
		"mobility": mobility_snapshot(),
		"run_id": _run_id,
		"owner_character_generation": _owner_character_generation,
		"launch_replay_identity_baseline": _launch_replay_identity_baseline.duplicate(true),
		"character_runtime": character_runtime,
		"character_action_coordinator": character_action_coordinator,
		"weapon_runtime_profile": weapon_runtime_profile,
		"weapon_modifier_state": weapon_modifier_state,
		"weapon_runtime": weapon_runtime,
		"weapon_action_coordinator": weapon_action_coordinator,
		"compatibility_fallback": _weapon_profile_compatibility_fallback,
		"physics_processing": is_physics_processing(),
	}


func _rollback_loadout_configuration(before: Dictionary) -> bool:
	var loadout_value: Variant = before.get("loadout")
	if not loadout_value is Dictionary or not loadout_runtime.configure(
		(loadout_value as Dictionary).duplicate(true)
	):
		return false
	var prior_stats := before.get("stats_resource") as Resource
	var prior_stats_state: Variant = before.get("stats_state", {})
	var prior_mobility_value: Variant = before.get("mobility", {})
	if (
		prior_stats == null
		or not prior_stats_state is Dictionary
		or not prior_stats.has_method("apply_profile")
		or not bool(prior_stats.call("apply_profile", prior_stats_state))
		or not prior_mobility_value is Dictionary
	):
		return false
	var restored_mobility := _normalized_mobility_profile(prior_mobility_value as Dictionary)
	if restored_mobility.is_empty():
		return false
	stats = prior_stats
	_mobility_profile = restored_mobility
	_run_id = StringName(str(before.get("run_id", _run_id)))
	_owner_character_generation = int(before.get(
		"owner_character_generation",
		_owner_character_generation
	))
	_launch_replay_identity_baseline = (
		before.get("launch_replay_identity_baseline", {}) as Dictionary
	).duplicate(true)
	character_runtime = before.get("character_runtime") as RefCounted
	character_action_coordinator = before.get("character_action_coordinator") as RefCounted
	_disconnect_weapon_coordinator()
	weapon_runtime_profile = before.get("weapon_runtime_profile") as RefCounted
	weapon_modifier_state = before.get("weapon_modifier_state") as RefCounted
	weapon_runtime = before.get("weapon_runtime") as RefCounted
	weapon_action_coordinator = before.get("weapon_action_coordinator") as RefCounted
	_weapon_profile_compatibility_fallback = bool(before.get("compatibility_fallback", false))
	_connect_weapon_coordinator()
	var full_player_value: Variant = before.get("full_player")
	if (
		full_player_value is Dictionary
		and not (full_player_value as Dictionary).is_empty()
		and not restore_full_player_replay_snapshot(
			(full_player_value as Dictionary).duplicate(true)
		)
	):
		return false
	_sync_weapon_adapter_stats()
	set_physics_process(bool(before.get("physics_processing", false)))
	return (
		loadout_runtime.snapshot() == loadout_value
		and character_runtime == before.get("character_runtime")
		and character_action_coordinator == before.get("character_action_coordinator")
		and _run_id == StringName(str(before.get("run_id", "")))
		and _owner_character_generation == int(before.get("owner_character_generation", 0))
		and _launch_replay_identity_baseline
		== (before.get("launch_replay_identity_baseline", {}) as Dictionary)
		and (
			not full_player_value is Dictionary
			or (full_player_value as Dictionary).is_empty()
			or full_player_replay_snapshot() == full_player_value
		)
	)


func configure_run(run_id: StringName) -> bool:
	var normalized := StringName(str(run_id).strip_edges())
	if normalized == &"" or str(normalized).contains(":"):
		return false
	if _run_id == normalized:
		return true
	if (
		health == null
		or not health.has_method("configure_run")
		or not health.has_method("irreversible_run_id")
		or rewind_recorder == null
		or not rewind_recorder.has_method("configure_run")
		or not rewind_recorder.has_method("current_run_id")
	):
		return false
	if (
		StringName(str(health.call("irreversible_run_id"))) != _run_id
		or StringName(str(rewind_recorder.call("current_run_id"))) != _run_id
	):
		return false
	if not _can_replace_world_payload_generation():
		return false
	var target_generation := _first_available_world_payload_generation(normalized, 1)
	if target_generation <= 0:
		return false
	var recorder_before := _rewind_run_configuration_snapshot()
	if recorder_before.is_empty():
		return false
	if not bool(rewind_recorder.call("configure_run", normalized)):
		return false
	if not bool(health.call("configure_run", normalized)):
		_restore_rewind_run_configuration_snapshot(recorder_before)
		return false
	if not _run_id.is_empty() and _owner_character_generation > 0:
		if not _invalidate_world_payload_generation(&"run_replacement"):
			set_physics_process(false)
			push_error("Run replacement generation invalidation violated its preflight")
			return false
	_run_id = normalized
	_owner_character_generation = target_generation
	_launch_replay_identity_baseline.clear()
	return true


func current_run_id() -> StringName:
	return _run_id


func owner_character_generation() -> int:
	return _owner_character_generation


func _can_replace_world_payload_generation() -> bool:
	if _run_id == &"" or _owner_character_generation <= 0 or world_payload_authority == null:
		return true
	if (
		world_payload_authority.has_method("generation_is_invalidated")
		and bool(world_payload_authority.call(
			"generation_is_invalidated",
			_run_id,
			_owner_character_generation
		))
	):
		return true
	return (
		world_payload_authority.has_method("can_invalidate_generation")
		and bool(world_payload_authority.call(
			"can_invalidate_generation",
			_run_id,
			_owner_character_generation,
			&"run_replacement"
		))
	)


func _invalidate_world_payload_generation(reason: StringName) -> bool:
	if world_payload_authority == null:
		return true
	if _run_id != &"" and _owner_character_generation > 0:
		var invalidated_value: Variant = world_payload_authority.call(
			"invalidate_generation",
			_run_id,
			_owner_character_generation,
			reason
		)
		if not invalidated_value is Dictionary:
			return false
		var invalidated := invalidated_value as Dictionary
		if (
			not bool(invalidated.get("ok", false))
			and StringName(str(invalidated.get("code", ""))) != &"GENERATION_ALREADY_INVALIDATED"
		):
			return false
	return true


func _activate_next_world_payload_generation() -> bool:
	if _run_id == &"":
		return false
	var minimum_generation := maxi(1, _owner_character_generation + 1)
	var next_generation := _first_available_world_payload_generation(
		_run_id,
		minimum_generation
	)
	if next_generation <= 0:
		return false
	_owner_character_generation = next_generation
	return true


func _first_available_world_payload_generation(
	run_id: StringName,
	minimum_generation: int
) -> int:
	if run_id == &"" or minimum_generation <= 0:
		return 0
	if world_payload_authority == null:
		return minimum_generation
	if not world_payload_authority.has_method("first_available_generation"):
		return 0
	var generation_value: Variant = world_payload_authority.call(
		"first_available_generation",
		run_id,
		minimum_generation
	)
	return int(generation_value) if typeof(generation_value) == TYPE_INT else 0


func _runtime_reset_preflight() -> bool:
	if _run_id == &"" or _owner_character_generation <= 0:
		return false
	if world_payload_authority == null:
		return true
	return (
		world_payload_authority.has_method("can_reset_generation_runtime")
		and bool(world_payload_authority.call(
			"can_reset_generation_runtime",
			_run_id,
			_owner_character_generation,
			&"player_runtime_reset"
		))
	)


func reset_runtime_state() -> bool:
	var pending_world_rollback_ok := true
	if not _active_world_frame_ticket.is_empty():
		pending_world_rollback_ok = (
			world_payload_authority != null
			and world_payload_authority.has_method("rollback_frame_transaction")
			and bool(world_payload_authority.call(
				"rollback_frame_transaction",
				_active_world_frame_ticket.duplicate(true)
			))
		)
	_active_world_frame_ticket.clear()
	var pending_event_rollback_ok := true
	if not _active_time_frame_signal_ticket.is_empty():
		pending_event_rollback_ok = (
			time_manager != null
			and time_manager.has_method("rollback_frame_signal_transaction")
			and bool(time_manager.call(
				"rollback_frame_signal_transaction",
				_active_time_frame_signal_ticket.duplicate(true)
			))
		)
	_active_time_frame_signal_ticket.clear()
	if not _active_health_frame_signal_ticket.is_empty():
		pending_event_rollback_ok = (
			health != null
			and health.has_method("rollback_frame_signal_transaction")
			and bool(health.call(
				"rollback_frame_signal_transaction",
				_active_health_frame_signal_ticket.duplicate(true)
			))
			and pending_event_rollback_ok
		)
	_active_health_frame_signal_ticket.clear()
	if (
		weapon_action_coordinator != null
		and weapon_action_coordinator.has_method("frame_event_buffer_is_active")
		and bool(weapon_action_coordinator.call("frame_event_buffer_is_active"))
	):
		pending_event_rollback_ok = (
			bool(weapon_action_coordinator.call("rollback_frame_event_buffer"))
			and pending_event_rollback_ok
		)
	if not pending_world_rollback_ok or not pending_event_rollback_ok:
		set_physics_process(false)
		push_error("Fixed-frame transaction rollback failed closed during runtime reset")
		return false
	if not _runtime_reset_preflight():
		set_physics_process(false)
		push_error("WorldPayloadAuthority runtime reset preflight failed closed")
		return false
	if not _cancel_uncommitted_character_action(&"player_runtime_reset"):
		set_physics_process(false)
		push_error("CharacterActionCoordinator runtime reset cancellation failed")
		return false
	action_state.reset_runtime_state()
	if character_action_coordinator != null:
		if not bool(character_action_coordinator.call("reset_runtime_state", &"player_runtime_reset")):
			set_physics_process(false)
			push_error("CharacterActionCoordinator runtime reset failed")
			return false
	_weapon_combo_timeout_frames = 0
	_weapon_action_reward_claims.clear()
	_weapon_action_ids_by_token.clear()
	_weapon_action_generations_by_token.clear()
	_weapon_action_mastery_contexts_by_token.clear()
	_weapon_action_token_order.clear()
	_weapon_hit_fact_claims.clear()
	_weapon_mastery_target_ids_by_token.clear()
	_weapon_resource_fact_state.clear()
	_weapon_replay_events.clear()
	_weapon_replay_capture_sequence = 0
	_applying_weapon_replay_event = false
	_weapon_replay_fact_baseline.clear()
	_weapon_replay_capture_invalid_reason = &""
	_weapon_replay_restore_invalid_reason = &""
	_weapon_intent_router.call("reset_all")
	_clear_character_input_owner()
	_last_priority_arbitration = {"frame": 0, "accepted": {}, "decisions": []}
	_buffered_time_skill = &""
	_next_time_action_token = 1
	_time_action_generation += 1
	_dash_cooldown_remaining_frames = 0
	_dash_velocity = Vector2.ZERO
	_runtime_frame = 0
	_dash_completion_token = 0
	_dash_completed_at_runtime_frame = -1
	_dash_direction = Vector2.RIGHT
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_last_move_direction = Vector2.RIGHT
	_floor_rule_modifiers.clear()
	_event_temporary_modifier_layer.call("replace_projection", [])
	if weapon_action_coordinator != null:
		weapon_action_coordinator.reset_runtime_state(&"player_runtime_reset")
		_capture_next_weapon_action_token_floor()
	_reset_weapon_adapters()
	_sync_weapon_resource_facts(&"runtime_reset")
	_clear_owned_player_arrows()
	_clear_owned_player_projectiles()
	time_manager.reset_runtime_state(true)
	_force_clear_time_acceleration()
	_apply_stats_to_components(true)
	health.invulnerable = false
	if rewind_recorder.has_method("reset_runtime_state"):
		if not bool(rewind_recorder.call("reset_runtime_state")):
			set_physics_process(false)
			push_error("RewindRecorder runtime reset failed")
			return false
	elif rewind_recorder.has_method("clear_snapshots"):
		rewind_recorder.clear_snapshots()
	if not _invalidate_world_payload_generation(&"player_runtime_reset"):
		set_physics_process(false)
		push_error("WorldPayloadAuthority runtime reset failed closed")
		return false
	elif (
		world_payload_authority != null
		and world_payload_authority.has_method("reset_runtime_clock")
		and not bool(world_payload_authority.call("reset_runtime_clock"))
	):
		set_physics_process(false)
		push_error("WorldPayloadAuthority runtime clock reset failed closed")
		return false
	elif not _activate_next_world_payload_generation():
		set_physics_process(false)
		push_error("WorldPayloadAuthority generation activation failed closed")
		return false
	_refresh_weapon_replay_fact_baseline()
	return true


func advance_action_frame(frame_intents: Dictionary = {}) -> bool:
	# Live play and Replay share this single fixed-frame transaction boundary.
	var normalized_frame_intents := _validated_frame_intents(frame_intents)
	if normalized_frame_intents.is_empty():
		return false
	if not _fixed_frame_preflight():
		return false
	var frame_before := _fixed_frame_transaction_snapshot()
	if frame_before.is_empty():
		return false
	var next_runtime_frame := _runtime_frame + 1
	if _hostile_frame_participant != null:
		var hostile_ticket: Variant = _hostile_frame_participant.call("begin_frame", next_runtime_frame)
		if not hostile_ticket is Dictionary or hostile_ticket.is_empty():
			return false
		_active_hostile_frame_ticket = hostile_ticket.duplicate(true)
	if not _begin_fixed_frame_event_buffers(next_runtime_frame):
		_rollback_fixed_frame_hostile_transaction()
		return false

	_runtime_frame = next_runtime_frame
	if (
		health == null
		or not health.has_method("advance_reward_invulnerability_frame")
		or not bool(health.call("advance_reward_invulnerability_frame"))
	):
		return _reject_fixed_frame(
			frame_before,
			"HealthComponent rejected authoritative reward frame %d" % _runtime_frame
		)
	if not bool(time_manager.call("advance_frame", _runtime_frame)):
		return _reject_fixed_frame(
			frame_before,
			"TimeManager rejected authoritative runtime frame %d" % _runtime_frame
		)
	_active_item_last_events = active_item_runtime.call(
		"advance_frame",
		{"runtime_frame": _runtime_frame}
	)
	if not _fixed_frame_event_buffers_can_commit():
		return _reject_fixed_frame(
			frame_before,
			"Fixed-frame event buffer preflight rejected runtime frame %d" % _runtime_frame
		)
	if _weapon_combo_timeout_frames > 0:
		_weapon_combo_timeout_frames -= 1
		if _weapon_combo_timeout_frames == 0 and weapon_runtime != null and weapon_runtime.has_method("reset_combo"):
			weapon_runtime.call("reset_combo")
	_advance_player_fixed_timers()

	var previous_action_state: int = action_state.current_state
	action_state.advance_frame()
	if (
		previous_action_state == PlayerActionStateScript.State.DASH
		and action_state.current_state == PlayerActionStateScript.State.FREE
	):
		_dash_completion_token += 1
		_dash_completed_at_runtime_frame = _runtime_frame
	var character_prepare_value: Variant = character_action_coordinator.call(
		"prepare_frame_advance",
		_runtime_frame,
		{
			"run_id": str(_run_id),
			"run_revision": _owner_character_generation,
			"owner_character_generation": _owner_character_generation,
			"alive": health != null and bool(health.call("is_alive")),
			"position": global_position,
			"time_energy": float(time_manager.get("energy")) if time_manager != null else 0.0,
			"frame_intents": normalized_frame_intents.duplicate(true),
		}
	)
	if (
		not character_prepare_value is Dictionary
		or not bool((character_prepare_value as Dictionary).get("ok", false))
	):
		if (
			character_prepare_value is Dictionary
			and StringName(str((character_prepare_value as Dictionary).get("code", "")))
			== &"ROLLBACK_FAILED"
		):
			set_physics_process(false)
		return _reject_fixed_frame(
			frame_before,
			"CharacterActionCoordinator rejected authoritative runtime frame %d" % _runtime_frame
		)
	if weapon_action_coordinator != null:
		var held_semantic := _active_hold_semantic_action()
		if held_semantic != &"" and weapon_action_coordinator.has_method("update_live_context"):
			weapon_action_coordinator.update_live_context(_weapon_submission_context())
		var weapon_advance_value: Variant = weapon_action_coordinator.call(
			"advance_frame",
			false
		)
		if typeof(weapon_advance_value) != TYPE_BOOL or not bool(weapon_advance_value):
			return _reject_fixed_frame(
				frame_before,
				"WeaponActionCoordinator rejected authoritative runtime frame %d" % _runtime_frame
			)
		if held_semantic != &"" and weapon_action_coordinator.phase_name() != &"HOLD":
			_weapon_intent_router.call("reset_action", held_semantic)
		_sync_weapon_action_projection()
		_sync_weapon_resource_facts(&"runtime_frame")
		if int((weapon_action_coordinator.call("snapshot") as Dictionary).get("frame", -1)) != _runtime_frame:
			return _reject_fixed_frame(
				frame_before,
				"WeaponActionCoordinator frame verification failed at %d" % _runtime_frame
			)
	var character_commit_value: Variant = character_action_coordinator.call(
		"commit_prepared_frame"
	)
	if (
		not character_commit_value is Dictionary
		or not bool((character_commit_value as Dictionary).get("ok", false))
	):
		return _reject_fixed_frame(
			frame_before,
			"CharacterActionCoordinator failed to commit runtime frame %d" % _runtime_frame
		)
	if not _apply_character_result_events(character_commit_value as Dictionary):
		return _reject_fixed_frame(
			frame_before,
			"Character runtime event settlement failed at frame %d" % _runtime_frame
		)
	if world_payload_authority != null and world_payload_authority.has_method("advance_frame"):
		var payload_advance_value: Variant = world_payload_authority.call(
			"advance_frame",
			_runtime_frame
		)
		if (
			not payload_advance_value is Dictionary
			or not bool((payload_advance_value as Dictionary).get("ok", false))
		):
			return _reject_fixed_frame(
				frame_before,
				"WorldPayloadAuthority rejected authoritative runtime frame %d" % _runtime_frame
			)
	if rewind_recorder != null and rewind_recorder.has_method("advance_frame"):
		if not bool(rewind_recorder.call("advance_frame", _runtime_frame)):
			return _reject_fixed_frame(
				frame_before,
			"RewindRecorder rejected authoritative runtime frame %d" % _runtime_frame
			)
	_apply_weapon_aim_direction(normalized_frame_intents.get(
		"aim",
		_last_weapon_aim_direction
	) as Vector2)
	if not _apply_frame_intents(normalized_frame_intents):
		return _reject_fixed_frame(
			frame_before,
			"Frame intent application rejected authoritative runtime frame %d" % _runtime_frame
		)
	var external_action_consumed := _consume_buffered_action()
	if (
		not external_action_consumed
		and weapon_action_coordinator != null
		and weapon_action_coordinator.consume_buffered_intent()
	):
		_sync_weapon_action_projection()
	_apply_frame_movement(normalized_frame_intents.get("movement", Vector2.ZERO) as Vector2)
	if _hostile_frame_participant != null and not bool(_hostile_frame_participant.call("prepare_frame", _active_hostile_frame_ticket)):
		return _reject_fixed_frame(frame_before, "Hostile frame preparation rejected runtime frame %d" % _runtime_frame)
	if not _commit_fixed_frame_event_buffers():
		if _fixed_frame_commit_irreversible:
			return false
		return _reject_fixed_frame(
			frame_before,
			"Fixed-frame event buffer settlement rejected runtime frame %d" % _runtime_frame
		)

	_refresh_weapon_replay_fact_baseline()
	_last_authoritative_frame_intents = normalized_frame_intents.duplicate(true)
	_last_authoritative_intents_frame = _runtime_frame
	_last_authoritative_intents_run = _run_id
	_last_authoritative_intents_generation = _owner_character_generation
	authoritative_frame_committed.emit(_runtime_frame)
	return true


func authoritative_frame_intents(frame: int) -> Dictionary:
	if frame != _runtime_frame or frame != _last_authoritative_intents_frame or _run_id != _last_authoritative_intents_run or _owner_character_generation != _last_authoritative_intents_generation:
		return {}
	return _last_authoritative_frame_intents.duplicate(true)


func _fixed_frame_preflight() -> bool:
	if _hostile_frame_participant != null and (not _active_hostile_frame_ticket.is_empty() or not bool(_hostile_frame_participant.call("is_ready_for_frame", _runtime_frame + 1))):
		return false
	if (
		_runtime_frame < 0
		or time_manager == null
		or not time_manager.has_method("replay_snapshot")
		or not time_manager.has_method("restore_replay_snapshot")
		or not time_manager.has_method("fixed_frame_transaction_snapshot")
		or not time_manager.has_method("restore_fixed_frame_transaction_snapshot")
		or not time_manager.has_method("advance_frame")
		or not time_manager.has_method("begin_frame_signal_transaction")
		or not time_manager.has_method("can_commit_frame_signal_transaction")
		or not time_manager.has_method("prepare_frame_signal_publication")
		or not time_manager.has_method("finalize_frame_signal_publication")
		or not time_manager.has_method("discard_finalized_frame_signal_publication")
		or not time_manager.has_method("publish_prepared_frame_signals")
		or not time_manager.has_method("rollback_frame_signal_transaction")
		or active_item_runtime == null
		or not active_item_runtime.has_method("snapshot")
		or not active_item_runtime.has_method("restore_snapshot")
		or not active_item_runtime.has_method("advance_frame")
		or health == null
		or not health.has_method("runtime_state_snapshot")
		or not health.has_method("restore_replay_snapshot")
		or not health.has_method("begin_frame_signal_transaction")
		or not health.has_method("can_commit_frame_signal_transaction")
		or not health.has_method("prepare_frame_signal_publication")
		or not health.has_method("finalize_frame_signal_publication")
		or not health.has_method("discard_finalized_frame_signal_publication")
		or not health.has_method("publish_prepared_frame_signals")
		or not health.has_method("rollback_frame_signal_transaction")
		or not health.has_method("frame_signal_transaction_is_active")
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("prepare_frame_advance")
		or not character_action_coordinator.has_method("commit_prepared_frame")
		or not character_action_coordinator.has_method("rollback_prepared_frame")
		or weapon_action_coordinator == null
		or not weapon_action_coordinator.has_method("snapshot")
		or not weapon_action_coordinator.has_method("restore_snapshot_for_rollback")
		or not weapon_action_coordinator.has_method("begin_frame_event_buffer")
		or not weapon_action_coordinator.has_method("can_commit_frame_event_buffer")
		or not weapon_action_coordinator.has_method("prepare_frame_event_publication")
		or not weapon_action_coordinator.has_method("finalize_frame_event_publication")
		or not weapon_action_coordinator.has_method("discard_finalized_frame_event_publication")
		or not weapon_action_coordinator.has_method("publish_prepared_frame_events")
		or not weapon_action_coordinator.has_method("rollback_frame_event_buffer")
		or not weapon_action_coordinator.has_method("frame_event_buffer_is_active")
		or world_payload_authority == null
		or not world_payload_authority.has_method("replay_snapshot")
		or not world_payload_authority.has_method("begin_frame_transaction")
		or not world_payload_authority.has_method("can_commit_frame_transaction")
		or not world_payload_authority.has_method("commit_frame_transaction")
		or not world_payload_authority.has_method("rollback_frame_transaction")
		or rewind_recorder == null
		or not rewind_recorder.has_method("advance_frame")
	):
		return false
	var time_value: Variant = time_manager.call("replay_snapshot")
	var weapon_value: Variant = weapon_action_coordinator.call("snapshot")
	var character_value: Variant = character_action_coordinator.call("snapshot")
	var world_value: Variant = world_payload_authority.call("replay_snapshot")
	if (
		not time_value is Dictionary
		or not weapon_value is Dictionary
		or not character_value is Dictionary
		or not world_value is Dictionary
	):
		return false
	var world_frame := int((world_value as Dictionary).get("last_runtime_frame", -2))
	var character_frame := int((character_value as Dictionary).get("last_runtime_frame", -2))
	var samples_value: Variant = rewind_recorder.get("samples_per_second")
	var record_seconds_value: Variant = rewind_recorder.get("record_seconds")
	var active_rewind_transaction_value: Variant = rewind_recorder.get("_active_transaction")
	return (
		int((time_value as Dictionary).get("runtime_frame", -1)) == _runtime_frame
		and int((weapon_value as Dictionary).get("frame", -1)) == _runtime_frame
		and int(action_state.snapshot().get("frame", -1)) == _runtime_frame
		and (character_frame == _runtime_frame or (_runtime_frame == 0 and character_frame == -1))
		and (world_frame == _runtime_frame or (_runtime_frame == 0 and world_frame == -1))
		and int(rewind_recorder.get("_last_runtime_frame")) == _runtime_frame
		and typeof(samples_value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(samples_value))
		and float(samples_value) == 10.0
		and typeof(record_seconds_value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(record_seconds_value))
		and float(record_seconds_value) > 0.0
		and active_rewind_transaction_value is Dictionary
		and (active_rewind_transaction_value as Dictionary).is_empty()
		and _active_time_frame_signal_ticket.is_empty()
		and _active_health_frame_signal_ticket.is_empty()
		and _active_world_frame_ticket.is_empty()
		and not bool(health.call("frame_signal_transaction_is_active"))
		and not bool(weapon_action_coordinator.call("frame_event_buffer_is_active"))
	)


func _fixed_frame_transaction_snapshot() -> Dictionary:
	var time_value: Variant = time_manager.call("replay_snapshot")
	var time_transaction_value: Variant = time_manager.call("fixed_frame_transaction_snapshot")
	var health_value: Variant = health.call("runtime_state_snapshot")
	var health_reward_value: Variant = health.call("reward_effect_snapshot")
	var health_invulnerability_value: Variant = health.call(
		"invulnerability_replay_snapshot"
	)
	var character_value: Variant = character_action_coordinator.call("snapshot")
	var character_action_value: Variant = character_action_coordinator.call("action_snapshot")
	var weapon_value: Variant = weapon_action_coordinator.call("snapshot")
	var world_value: Variant = world_payload_authority.call("replay_snapshot")
	var intent_value: Variant = _weapon_intent_router.call("runtime_snapshot")
	var active_item_value: Variant = active_item_runtime.call("snapshot")
	var rewind_value := _rewind_frame_transaction_snapshot()
	if (
		not time_value is Dictionary
		or not time_transaction_value is Dictionary
		or not health_value is Dictionary
		or not health_reward_value is Dictionary
		or not health_invulnerability_value is Dictionary
		or not character_value is Dictionary
		or not character_action_value is Dictionary
		or not weapon_value is Dictionary
		or not world_value is Dictionary
		or not intent_value is Dictionary
		or not active_item_value is Dictionary
		or rewind_value.is_empty()
	):
		return {}
	return {
		"runtime_frame": _runtime_frame,
		"position": global_position,
		"velocity": velocity,
		"facing": _last_move_direction,
		"weapon_aim_direction": _last_weapon_aim_direction,
		"combo_timeout_frames": _weapon_combo_timeout_frames,
		"dash_cooldown_remaining_frames": _dash_cooldown_remaining_frames,
		"dash_velocity": _dash_velocity,
		"dash_direction": _dash_direction,
		"knockback_velocity": _knockback_velocity,
		"buffered_time_skill": _buffered_time_skill,
		"dash_completion_token": _dash_completion_token,
		"dash_completed_at_runtime_frame": _dash_completed_at_runtime_frame,
		"next_time_action_token": _next_time_action_token,
		"character_input_owner": character_input_owner_snapshot(),
		"priority_arbitration": priority_arbitration_snapshot(),
		"active_item": (active_item_value as Dictionary).duplicate(true),
		"active_item_last_activation": _active_item_last_activation.duplicate(true),
		"active_item_last_events": _active_item_last_events.duplicate(true),
		"action": action_state.snapshot(),
		"character": (character_value as Dictionary).duplicate(true),
		"character_action": (character_action_value as Dictionary).duplicate(true),
		"weapon": (weapon_value as Dictionary).duplicate(true),
			"time": (time_value as Dictionary).duplicate(true),
			"time_transaction": (time_transaction_value as Dictionary).duplicate(true),
			"health": (health_value as Dictionary).duplicate(true),
			"health_reward": (health_reward_value as Dictionary).duplicate(true),
			"health_invulnerability": (
				health_invulnerability_value as Dictionary
			).duplicate(true),
			"world": (world_value as Dictionary).duplicate(true),
		"rewind": rewind_value,
		"intent_router": (intent_value as Dictionary).duplicate(true),
		"player_weapon_state": {
			"action_reward_claims": _weapon_action_reward_claims.duplicate(true),
			"action_ids_by_token": _weapon_action_ids_by_token.duplicate(true),
			"action_generations_by_token": _weapon_action_generations_by_token.duplicate(true),
			"action_mastery_contexts_by_token": _weapon_action_mastery_contexts_by_token.duplicate(true),
			"action_token_order": _weapon_action_token_order.duplicate(),
			"hit_fact_claims": _weapon_hit_fact_claims.duplicate(true),
			"mastery_target_ids_by_token": _weapon_mastery_target_ids_by_token.duplicate(true),
			"resource_fact_state": _weapon_resource_fact_state.duplicate(true),
			"next_token_floor": _next_weapon_action_token_floor,
			"combo_timeout_frames": _weapon_combo_timeout_frames,
		},
		"replay_events": _weapon_replay_events.duplicate(true),
		"replay_capture_sequence": _weapon_replay_capture_sequence,
		"replay_fact_baseline": _weapon_replay_fact_baseline.duplicate(true),
		"replay_capture_invalid_reason": _weapon_replay_capture_invalid_reason,
		"replay_restore_invalid_reason": _weapon_replay_restore_invalid_reason,
	}


func _restore_fixed_frame_transaction(value: Dictionary) -> bool:
	var prepared_rollback_ok := bool(character_action_coordinator.call(
		"rollback_prepared_frame"
	))
	var time_ok := bool(time_manager.call(
		"restore_replay_snapshot",
		(value.get("time", {}) as Dictionary).duplicate(true)
	))
	var time_transaction_ok := bool(time_manager.call(
		"restore_fixed_frame_transaction_snapshot",
		(value.get("time_transaction", {}) as Dictionary).duplicate(true)
	))
	var health_ok := bool(health.call(
		"restore_replay_snapshot",
		(value.get("health", {}) as Dictionary).duplicate(true)
	))
	var health_invulnerability_ok := bool(health.call(
		"restore_invulnerability_replay_snapshot",
		(value.get("health_invulnerability", {}) as Dictionary).duplicate(true)
	))
	var health_reward_ok := bool(health.call(
		"restore_reward_effect_snapshot",
		(value.get("health_reward", {}) as Dictionary).duplicate(true)
	))
	var action_ok := bool(action_state.call(
		"restore_transaction_snapshot",
		(value.get("action", {}) as Dictionary).duplicate(true)
	))
	var character_ok := bool(character_action_coordinator.call(
		"restore_snapshot",
		(value.get("character", {}) as Dictionary).duplicate(true)
	))
	var character_action_ok := bool(character_action_coordinator.call(
		"restore_action_snapshot",
		(value.get("character_action", {}) as Dictionary).duplicate(true)
	))
	var weapon_ok := bool(weapon_action_coordinator.call(
		"restore_snapshot_for_rollback",
		(value.get("weapon", {}) as Dictionary).duplicate(true)
	))
	var intent_ok := bool(_weapon_intent_router.call(
		"restore_runtime_snapshot",
		(value.get("intent_router", {}) as Dictionary).duplicate(true)
	))
	var active_item_ok := bool(active_item_runtime.call(
		"restore_snapshot",
		(value.get("active_item", {}) as Dictionary).duplicate(true)
	))
	var rewind_ok := _restore_rewind_frame_transaction_snapshot(
		value.get("rewind", {}) as Dictionary
	)
	_runtime_frame = int(value.get("runtime_frame", _runtime_frame))
	global_position = value.get("position", global_position) as Vector2
	velocity = value.get("velocity", velocity) as Vector2
	_last_move_direction = value.get("facing", _last_move_direction) as Vector2
	_last_weapon_aim_direction = value.get(
		"weapon_aim_direction",
		_last_weapon_aim_direction
	) as Vector2
	_apply_weapon_aim_direction(_last_weapon_aim_direction)
	_weapon_combo_timeout_frames = int(value.get(
		"combo_timeout_frames",
		_weapon_combo_timeout_frames
	))
	_dash_cooldown_remaining_frames = int(value.get(
		"dash_cooldown_remaining_frames",
		_dash_cooldown_remaining_frames
	))
	_dash_velocity = value.get("dash_velocity", _dash_velocity) as Vector2
	_dash_direction = value.get("dash_direction", _dash_direction) as Vector2
	_knockback_velocity = value.get("knockback_velocity", _knockback_velocity) as Vector2
	_buffered_time_skill = StringName(str(value.get(
		"buffered_time_skill",
		_buffered_time_skill
	)))
	_dash_completion_token = int(value.get("dash_completion_token", _dash_completion_token))
	_dash_completed_at_runtime_frame = int(value.get(
		"dash_completed_at_runtime_frame",
		_dash_completed_at_runtime_frame
	))
	_next_time_action_token = int(value.get(
		"next_time_action_token",
		_next_time_action_token
	))
	var character_input_ok := _restore_character_input_owner_snapshot(
		value.get("character_input_owner", {}) as Dictionary
	)
	_last_priority_arbitration = (
		value.get("priority_arbitration", _last_priority_arbitration) as Dictionary
	).duplicate(true)
	_active_item_last_activation = (
		value.get("active_item_last_activation", {}) as Dictionary
	).duplicate(true)
	_active_item_last_events.clear()
	for event_value: Variant in value.get("active_item_last_events", []) as Array:
		if event_value is Dictionary:
			_active_item_last_events.append((event_value as Dictionary).duplicate(true))
	_install_player_weapon_replay_state(value.get("player_weapon_state", {}) as Dictionary)
	var replay_events: Array[Dictionary] = []
	for event_value: Variant in value.get("replay_events", []) as Array:
		if event_value is Dictionary:
			replay_events.append((event_value as Dictionary).duplicate(true))
	_restore_weapon_replay_event_log(replay_events, int(value.get(
		"replay_capture_sequence",
		_weapon_replay_capture_sequence
	)))
	_weapon_replay_fact_baseline = (value.get(
		"replay_fact_baseline",
		{}
	) as Dictionary).duplicate(true)
	_weapon_replay_capture_invalid_reason = StringName(str(value.get(
		"replay_capture_invalid_reason",
		_weapon_replay_capture_invalid_reason
	)))
	_weapon_replay_restore_invalid_reason = StringName(str(value.get(
		"replay_restore_invalid_reason",
		_weapon_replay_restore_invalid_reason
	)))
	return (
		prepared_rollback_ok
		and time_ok
		and time_transaction_ok
		and health_ok
		and health_invulnerability_ok
		and health_reward_ok
		and action_ok
		and character_ok
		and character_action_ok
		and character_input_ok
		and weapon_ok
		and intent_ok
		and active_item_ok
		and rewind_ok
		and time_manager.call("replay_snapshot") == value.get("time", {})
		and time_manager.call("fixed_frame_transaction_snapshot")
		== value.get("time_transaction", {})
		and health.call("runtime_state_snapshot") == value.get("health", {})
		and health.call("reward_effect_snapshot") == value.get("health_reward", {})
		and health.call("invulnerability_replay_snapshot")
		== value.get("health_invulnerability", {})
		and _next_time_action_token == int(value.get("next_time_action_token", -1))
		and action_state.snapshot() == value.get("action", {})
		and character_action_coordinator.call("snapshot") == value.get("character", {})
		and character_action_coordinator.call("action_snapshot")
		== value.get("character_action", {})
		and character_input_owner_snapshot() == value.get("character_input_owner", {})
		and priority_arbitration_snapshot() == value.get("priority_arbitration", {})
		and active_item_runtime.call("snapshot") == value.get("active_item", {})
		and _active_item_last_activation == value.get("active_item_last_activation", {})
		and _active_item_last_events == value.get("active_item_last_events", [])
		and weapon_action_coordinator.call("snapshot") == value.get("weapon", {})
		and world_payload_authority.call("replay_snapshot") == value.get("world", {})
		and _rewind_frame_transaction_snapshot() == value.get("rewind", {})
	)


func _reject_fixed_frame(value: Dictionary, reason: String) -> bool:
	var world_rollback_ok := _rollback_fixed_frame_world_transaction()
	var hostile_rollback_ok := _rollback_fixed_frame_hostile_transaction()
	var state_rollback_ok := _restore_fixed_frame_transaction(value)
	var event_rollback_ok := _rollback_fixed_frame_event_buffers()
	if not world_rollback_ok or not hostile_rollback_ok or not state_rollback_ok or not event_rollback_ok:
		set_physics_process(false)
		push_error("Fixed-frame rollback failed closed after: %s" % reason)
	else:
		push_error(reason)
	return false


func _begin_fixed_frame_event_buffers(runtime_frame: int) -> bool:
	_fixed_frame_commit_irreversible = false
	_fixed_frame_weapon_observations.clear()
	if not bool(weapon_action_coordinator.call("begin_frame_event_buffer")):
		return false
	var time_ticket_value: Variant = time_manager.call(
		"begin_frame_signal_transaction",
		runtime_frame
	)
	if not time_ticket_value is Dictionary or (time_ticket_value as Dictionary).is_empty():
		if not bool(weapon_action_coordinator.call("rollback_frame_event_buffer")):
			set_physics_process(false)
			push_error("Weapon frame event rollback failed after Time signal begin rejection")
			return false
	_active_time_frame_signal_ticket = (time_ticket_value as Dictionary).duplicate(true)
	var health_ticket_value: Variant = health.call(
		"begin_frame_signal_transaction",
		runtime_frame
	)
	if not health_ticket_value is Dictionary or (health_ticket_value as Dictionary).is_empty():
		var time_rollback_ok := bool(time_manager.call(
			"rollback_frame_signal_transaction",
			_active_time_frame_signal_ticket.duplicate(true)
		))
		_active_time_frame_signal_ticket.clear()
		var weapon_rollback_ok := bool(weapon_action_coordinator.call(
			"rollback_frame_event_buffer"
		))
		if not time_rollback_ok or not weapon_rollback_ok:
			set_physics_process(false)
			push_error("Fixed-frame begin rollback failed after Health signal rejection")
		return false
	_active_health_frame_signal_ticket = (health_ticket_value as Dictionary).duplicate(true)
	var world_ticket_value: Variant = world_payload_authority.call(
		"begin_frame_transaction",
		runtime_frame
	)
	if not world_ticket_value is Dictionary or (world_ticket_value as Dictionary).is_empty():
		var health_rollback_ok := bool(health.call(
			"rollback_frame_signal_transaction",
			_active_health_frame_signal_ticket.duplicate(true)
		))
		_active_health_frame_signal_ticket.clear()
		var time_rollback_ok := bool(time_manager.call(
			"rollback_frame_signal_transaction",
			_active_time_frame_signal_ticket.duplicate(true)
		))
		_active_time_frame_signal_ticket.clear()
		var weapon_rollback_ok := bool(weapon_action_coordinator.call(
			"rollback_frame_event_buffer"
		))
		if not health_rollback_ok or not time_rollback_ok or not weapon_rollback_ok:
			set_physics_process(false)
			push_error("Fixed-frame begin rollback failed after World rejection")
		return false
	_active_world_frame_ticket = (world_ticket_value as Dictionary).duplicate(true)
	return true


func _commit_fixed_frame_event_buffers() -> bool:
	if (
		_active_time_frame_signal_ticket.is_empty()
		or _active_health_frame_signal_ticket.is_empty()
		or _active_world_frame_ticket.is_empty()
	):
		return false
	var time_ticket := _active_time_frame_signal_ticket.duplicate(true)
	var health_ticket := _active_health_frame_signal_ticket.duplicate(true)
	var world_ticket := _active_world_frame_ticket.duplicate(true)
	var hostile_publication: Dictionary = {}
	if _hostile_frame_participant != null:
		var hostile_value: Variant = _hostile_frame_participant.call("prepare_frame_publication", _active_hostile_frame_ticket)
		if not hostile_value is Dictionary or hostile_value.is_empty():
			return false
		hostile_publication = hostile_value.duplicate(true)
	var time_publication_value: Variant = time_manager.call(
		"prepare_frame_signal_publication",
		time_ticket
	)
	var weapon_publication_value: Variant = weapon_action_coordinator.call(
		"prepare_frame_event_publication"
	)
	var health_publication_value: Variant = health.call(
		"prepare_frame_signal_publication",
		health_ticket
	)
	if (
		not time_publication_value is Dictionary
		or (time_publication_value as Dictionary).is_empty()
		or not weapon_publication_value is Dictionary
		or (weapon_publication_value as Dictionary).is_empty()
		or not health_publication_value is Dictionary
		or (health_publication_value as Dictionary).is_empty()
		or not bool(world_payload_authority.call(
			"can_commit_frame_transaction",
			world_ticket
		))
	):
		return false
	var time_publication := (time_publication_value as Dictionary).duplicate(true)
	var weapon_publication := (weapon_publication_value as Dictionary).duplicate(true)
	var health_publication := (health_publication_value as Dictionary).duplicate(true)
	if not bool(weapon_action_coordinator.call(
		"finalize_frame_event_publication",
		weapon_publication
	)):
		return false
	if not bool(time_manager.call(
		"finalize_frame_signal_publication",
		time_publication
	)):
		weapon_action_coordinator.call(
			"discard_finalized_frame_event_publication",
			weapon_publication
		)
		return false
	if not bool(health.call(
		"finalize_frame_signal_publication",
		health_publication
	)):
		var time_discard_ok := bool(time_manager.call(
			"discard_finalized_frame_signal_publication",
			time_publication
		))
		var weapon_discard_ok := bool(weapon_action_coordinator.call(
			"discard_finalized_frame_event_publication",
			weapon_publication
		))
		_active_time_frame_signal_ticket.clear()
		if not time_discard_ok or not weapon_discard_ok:
			set_physics_process(false)
			push_error("Finalized frame publication discard failed after Health rejection")
		return false
	if _hostile_frame_participant != null and not bool(_hostile_frame_participant.call("finalize_frame_publication", hostile_publication)):
		var time_discard_ok := bool(time_manager.call("discard_finalized_frame_signal_publication", time_publication))
		var weapon_discard_ok := bool(weapon_action_coordinator.call("discard_finalized_frame_event_publication", weapon_publication))
		var health_discard_ok := bool(health.call("discard_finalized_frame_signal_publication", health_publication))
		_active_time_frame_signal_ticket.clear()
		_active_health_frame_signal_ticket.clear()
		if not time_discard_ok or not weapon_discard_ok or not health_discard_ok:
			set_physics_process(false)
			push_error("Finalized Player publication discard failed after hostile rejection")
		return false
	if not bool(world_payload_authority.call(
		"commit_frame_transaction",
		world_ticket
	)):
		var time_discard_ok := bool(time_manager.call(
			"discard_finalized_frame_signal_publication",
			time_publication
		))
		var weapon_discard_ok := bool(weapon_action_coordinator.call(
			"discard_finalized_frame_event_publication",
			weapon_publication
		))
		var health_discard_ok := bool(health.call(
			"discard_finalized_frame_signal_publication",
			health_publication
		))
		_active_time_frame_signal_ticket.clear()
		_active_health_frame_signal_ticket.clear()
		if not time_discard_ok or not weapon_discard_ok or not health_discard_ok:
			set_physics_process(false)
			push_error("Finalized frame publication discard failed closed")
		return false
	_active_world_frame_ticket.clear()
	_fixed_frame_commit_irreversible = true
	if _hostile_frame_participant != null and not bool(_hostile_frame_participant.call("seal_frame_publication", hostile_publication)):
		set_physics_process(false)
		push_error("Hostile compensation retirement failed after irreversible World commit")
		return false
	_active_hostile_frame_ticket.clear()
	_active_time_frame_signal_ticket.clear()
	_active_health_frame_signal_ticket.clear()
	var weapon_observations := _fixed_frame_weapon_observations.duplicate(true)
	_fixed_frame_weapon_observations.clear()
	# All complete batches are now irreversible and detached from their live
	# transactions; observers cannot invalidate sibling publication.
	time_manager.call("publish_prepared_frame_signals")
	weapon_action_coordinator.call("publish_prepared_frame_events")
	health.call("publish_prepared_frame_signals")
	if _hostile_frame_participant != null:
		_hostile_frame_participant.call("publish_prepared_frame")
	for observation: Dictionary in weapon_observations:
		_flush_weapon_observation(observation)
	return true


func _fixed_frame_event_buffers_can_commit() -> bool:
	if (
		_active_time_frame_signal_ticket.is_empty()
		or _active_health_frame_signal_ticket.is_empty()
	):
		return false
	return (
		bool(time_manager.call(
			"can_commit_frame_signal_transaction",
			_active_time_frame_signal_ticket.duplicate(true)
		))
		and bool(health.call(
			"can_commit_frame_signal_transaction",
			_active_health_frame_signal_ticket.duplicate(true)
		))
		and bool(weapon_action_coordinator.call("can_commit_frame_event_buffer"))
	)


func _rollback_fixed_frame_event_buffers() -> bool:
	_fixed_frame_weapon_observations.clear()
	var time_ok := true
	if not _active_time_frame_signal_ticket.is_empty():
		time_ok = bool(time_manager.call(
			"rollback_frame_signal_transaction",
			_active_time_frame_signal_ticket.duplicate(true)
		))
	_active_time_frame_signal_ticket.clear()
	var health_ok := true
	if not _active_health_frame_signal_ticket.is_empty():
		health_ok = bool(health.call(
			"rollback_frame_signal_transaction",
			_active_health_frame_signal_ticket.duplicate(true)
		))
	_active_health_frame_signal_ticket.clear()
	var weapon_ok := true
	if bool(weapon_action_coordinator.call("frame_event_buffer_is_active")):
		weapon_ok = bool(weapon_action_coordinator.call(
			"rollback_frame_event_buffer"
		))
	return time_ok and health_ok and weapon_ok


func _rollback_fixed_frame_world_transaction() -> bool:
	if _active_world_frame_ticket.is_empty():
		return true
	var ticket := _active_world_frame_ticket.duplicate(true)
	var rolled_back := bool(world_payload_authority.call(
		"rollback_frame_transaction",
		ticket
	))
	_active_world_frame_ticket.clear()
	return rolled_back


func configure_hostile_frame_participant(participant: RefCounted) -> bool:
	if not _active_hostile_frame_ticket.is_empty() or not _active_world_frame_ticket.is_empty() or not _active_time_frame_signal_ticket.is_empty() or not _active_health_frame_signal_ticket.is_empty():
		return false
	if _hostile_frame_participant != null and bool(_hostile_frame_participant.call("frame_transaction_is_active")):
		return false
	if participant != null:
		for method: StringName in [&"is_ready_for_frame", &"frame_transaction_is_active", &"begin_frame", &"prepare_frame", &"prepare_frame_publication", &"finalize_frame_publication", &"seal_frame_publication", &"publish_prepared_frame", &"rollback_frame"]:
			if not participant.has_method(method):
				return false
		if not bool(participant.call("is_ready_for_frame", _runtime_frame + 1)):
			return false
	_hostile_frame_participant = participant
	return true


func _rollback_fixed_frame_hostile_transaction() -> bool:
	if _active_hostile_frame_ticket.is_empty():
		return true
	var ticket := _active_hostile_frame_ticket.duplicate(true)
	_active_hostile_frame_ticket.clear()
	return _hostile_frame_participant != null and bool(_hostile_frame_participant.call("rollback_frame", ticket))


func _rewind_frame_transaction_snapshot() -> Dictionary:
	if rewind_recorder == null:
		return {}
	var snapshots_value: Variant = rewind_recorder.get("_snapshots")
	var active_transaction_value: Variant = rewind_recorder.get("_active_transaction")
	if not snapshots_value is Array or not active_transaction_value is Dictionary:
		return {}
	return {
		"snapshots": (snapshots_value as Array).duplicate(true),
		"sample_timer": float(rewind_recorder.get("_sample_timer")),
		"history_revision": int(rewind_recorder.get("_history_revision")),
		"next_sample_sequence": int(rewind_recorder.get("_next_sample_sequence")),
		"last_runtime_frame": int(rewind_recorder.get("_last_runtime_frame")),
		"active_transaction": (active_transaction_value as Dictionary).duplicate(true),
	}


func _restore_rewind_frame_transaction_snapshot(value: Dictionary) -> bool:
	if not _valid_rewind_frame_transaction_snapshot(value):
		return false
	var restored_snapshots: Array[Dictionary] = []
	for snapshot_value: Variant in value["snapshots"] as Array:
		restored_snapshots.append((snapshot_value as Dictionary).duplicate(true))
	rewind_recorder.set("_snapshots", restored_snapshots)
	rewind_recorder.set("_sample_timer", float(value["sample_timer"]))
	rewind_recorder.set("_history_revision", int(value["history_revision"]))
	rewind_recorder.set("_next_sample_sequence", int(value["next_sample_sequence"]))
	rewind_recorder.set("_last_runtime_frame", int(value["last_runtime_frame"]))
	rewind_recorder.set(
		"_active_transaction",
		(value["active_transaction"] as Dictionary).duplicate(true)
	)
	return _rewind_frame_transaction_snapshot() == value


func _valid_rewind_frame_transaction_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 6
		or not value.get("snapshots") is Array
		or typeof(value.get("sample_timer")) != TYPE_FLOAT
		or typeof(value.get("history_revision")) != TYPE_INT
		or typeof(value.get("next_sample_sequence")) != TYPE_INT
		or typeof(value.get("last_runtime_frame")) != TYPE_INT
		or not value.get("active_transaction") is Dictionary
	):
		return false
	for snapshot_value: Variant in value["snapshots"] as Array:
		if not snapshot_value is Dictionary:
			return false
	return true


func _rewind_run_configuration_snapshot() -> Dictionary:
	var frame_state := _rewind_frame_transaction_snapshot()
	if frame_state.is_empty():
		return {}
	frame_state["run_id"] = StringName(str(rewind_recorder.get("_run_id")))
	frame_state["next_ticket_id"] = int(rewind_recorder.get("_next_ticket_id"))
	frame_state["restore_fault_for_test"] = StringName(str(
		rewind_recorder.get("_restore_fault_for_test")
	))
	return frame_state


func _restore_rewind_run_configuration_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 9
		or typeof(value.get("run_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value.get("next_ticket_id")) != TYPE_INT
		or typeof(value.get("restore_fault_for_test")) not in [
			TYPE_STRING,
			TYPE_STRING_NAME,
		]
	):
		return false
	var frame_state := value.duplicate(true)
	frame_state.erase("run_id")
	frame_state.erase("next_ticket_id")
	frame_state.erase("restore_fault_for_test")
	if not _restore_rewind_frame_transaction_snapshot(frame_state):
		return false
	rewind_recorder.set("_run_id", StringName(str(value["run_id"])))
	rewind_recorder.set("_next_ticket_id", int(value["next_ticket_id"]))
	rewind_recorder.set(
		"_restore_fault_for_test",
		StringName(str(value["restore_fault_for_test"]))
	)
	return _rewind_run_configuration_snapshot() == value


func get_action_movement_multiplier() -> float:
	var character_multiplier := _character_movement_multiplier()
	var floor_rule_multiplier := _floor_rule_movement_multiplier()
	if weapon_action_coordinator != null and weapon_action_coordinator.phase_name() != &"READY":
		return (
			weapon_action_coordinator.movement_multiplier()
			* character_multiplier
			* floor_rule_multiplier
		)
	match action_state.current_state:
		PlayerActionStateScript.State.DASH:
			return (
				float(_mobility_profile["dash_speed"])
				/ maxf(1.0, float(stats.move_speed))
				* floor_rule_multiplier
			)
		PlayerActionStateScript.State.TIME_CAST:
			return TIME_CAST_MOVEMENT_MULTIPLIER * character_multiplier * floor_rule_multiplier
		PlayerActionStateScript.State.HITSTUN, PlayerActionStateScript.State.DEAD:
			return 0.0
		_:
			return character_multiplier * floor_rule_multiplier


func floor_rule_effect_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"modifiers": _floor_rule_modifiers.duplicate(true),
	}


func restore_floor_rule_effect_snapshot(value: Dictionary) -> bool:
	if not _valid_floor_rule_effect_snapshot(value):
		return false
	var before := _floor_rule_modifiers.duplicate(true)
	_floor_rule_modifiers = (value["modifiers"] as Dictionary).duplicate(true)
	if (
		_sync_floor_rule_time_cost_multiplier()
		and floor_rule_effect_snapshot() == value
	):
		return true
	_floor_rule_modifiers = before
	if not _sync_floor_rule_time_cost_multiplier():
		push_error("Floor-rule modifier rollback failed")
	return false


func apply_floor_rule_modifier(
	source_id: StringName,
	modifier_id: StringName,
	operation: StringName,
	values: Dictionary
) -> bool:
	if source_id == &"" or modifier_id == &"" or operation not in [&"apply", &"remove"]:
		return false
	var key := "%s|%s" % [str(source_id), str(modifier_id)]
	var before := _floor_rule_modifiers.duplicate(true)
	if operation == &"remove":
		if not values.is_empty():
			return false
		_floor_rule_modifiers.erase(key)
	else:
		if not _valid_floor_rule_modifier_values(values):
			return false
		_floor_rule_modifiers[key] = {
			"source_id": str(source_id),
			"modifier_id": str(modifier_id),
			"values": values.duplicate(true),
		}
	if _sync_floor_rule_time_cost_multiplier():
		return true
	_floor_rule_modifiers = before
	if not _sync_floor_rule_time_cost_multiplier():
		push_error("Floor-rule modifier apply rollback failed")
	return false


func _valid_floor_rule_effect_snapshot(value: Dictionary) -> bool:
	if not _dictionary_has_exact_fields(value, ["schema_version", "modifiers"]):
		return false
	if typeof(value["schema_version"]) != TYPE_INT or int(value["schema_version"]) != 1:
		return false
	if not value["modifiers"] is Dictionary:
		return false
	for key_value: Variant in (value["modifiers"] as Dictionary).keys():
		if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var entry_value: Variant = (value["modifiers"] as Dictionary)[key_value]
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		if not _dictionary_has_exact_fields(entry, ["source_id", "modifier_id", "values"]):
			return false
		var source_id := StringName(str(entry["source_id"]))
		var modifier_id := StringName(str(entry["modifier_id"]))
		if (
			source_id == &""
			or modifier_id == &""
			or str(key_value) != "%s|%s" % [str(source_id), str(modifier_id)]
			or not entry["values"] is Dictionary
			or not _valid_floor_rule_modifier_values(entry["values"] as Dictionary)
		):
			return false
	return true


func _valid_floor_rule_modifier_values(values: Dictionary) -> bool:
	if values.is_empty():
		return false
	for key_value: Variant in values.keys():
		if str(key_value) not in [
			"movement_multiplier",
			"time_cost_multiplier",
			"zone_locked",
			"safe_area_required",
		]:
			return false
	if values.has("movement_multiplier"):
		var movement_value: Variant = values["movement_multiplier"]
		if (
			typeof(movement_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(movement_value))
			or float(movement_value) < 0.0
		):
			return false
	if values.has("time_cost_multiplier"):
		var time_value: Variant = values["time_cost_multiplier"]
		if (
			typeof(time_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(time_value))
			or float(time_value) <= 0.0
		):
			return false
	for field: String in ["zone_locked", "safe_area_required"]:
		if values.has(field) and typeof(values[field]) != TYPE_BOOL:
			return false
	return true


func _floor_rule_movement_multiplier() -> float:
	var multiplier := 1.0
	for entry_value: Variant in _floor_rule_modifiers.values():
		if not entry_value is Dictionary:
			continue
		var values := (entry_value as Dictionary).get("values", {}) as Dictionary
		if bool(values.get("zone_locked", false)):
			return 0.0
		multiplier *= float(values.get("movement_multiplier", 1.0))
	return multiplier


func _sync_floor_rule_time_cost_multiplier() -> bool:
	if time_manager == null or not time_manager.has_method("set_floor_rule_cost_multiplier"):
		return false
	var multiplier := 1.0
	for entry_value: Variant in _floor_rule_modifiers.values():
		if not entry_value is Dictionary:
			return false
		var values := (entry_value as Dictionary).get("values", {}) as Dictionary
		multiplier *= float(values.get("time_cost_multiplier", 1.0))
	return bool(time_manager.call("set_floor_rule_cost_multiplier", multiplier))


func _character_movement_multiplier() -> float:
	if character_runtime == null or not character_runtime.has_method("presentation_snapshot"):
		return 1.0
	var presentation_value: Variant = character_runtime.call("presentation_snapshot")
	if not presentation_value is Dictionary:
		return 1.0
	var multiplier_value: Variant = (presentation_value as Dictionary).get(
		"movement_multiplier",
		1.0
	)
	if (
		typeof(multiplier_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(multiplier_value))
		or float(multiplier_value) < 0.0
	):
		return 1.0
	return float(multiplier_value)


func apply_hitstun_frames(duration_frames: int) -> bool:
	if duration_frames <= 0 or action_state.current_state == PlayerActionStateScript.State.DEAD:
		return false
	if not action_state.can_transition_to(PlayerActionStateScript.State.HITSTUN):
		return false
	if not _cancel_uncommitted_character_action(&"hitstun"):
		return false
	if not action_state.transition_to(PlayerActionStateScript.State.HITSTUN, duration_frames):
		return false
	action_state.clear_buffered_inputs()
	_clear_transient_effects()
	return true


func cancel_transient_actions() -> void:
	_cancel_uncommitted_character_action(&"transient_clear")
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
	return action_state.force_safe_reset()


func rewind_transaction_snapshot() -> Dictionary:
	if (
		not action_state.has_method("snapshot")
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("snapshot")
		or not character_action_coordinator.has_method("action_snapshot")
		or weapon_action_coordinator == null
		or not weapon_action_coordinator.has_method("gameplay_rewind_snapshot")
		or not _weapon_intent_router.has_method("runtime_snapshot")
	):
		return {}
	var action_value: Variant = action_state.call("snapshot")
	var character_value: Variant = character_action_coordinator.call("snapshot")
	var character_action_value: Variant = character_action_coordinator.call("action_snapshot")
	var coordinator_value: Variant = weapon_action_coordinator.call("gameplay_rewind_snapshot")
	var intent_value: Variant = _weapon_intent_router.call("runtime_snapshot")
	if (
		not action_value is Dictionary
		or not character_value is Dictionary
		or not character_action_value is Dictionary
		or not coordinator_value is Dictionary
		or not intent_value is Dictionary
	):
		return {}
	return {
		"run_id": _run_id,
		"position": global_position,
		"velocity": velocity,
		"facing": _last_move_direction,
		"dash_velocity": _dash_velocity,
		"knockback_velocity": _knockback_velocity,
		"buffered_time_skill": _buffered_time_skill,
		"combo_timeout_frames": _weapon_combo_timeout_frames,
		"runtime_frame": _runtime_frame,
		"action_state": (action_value as Dictionary).duplicate(true),
		"character": (character_value as Dictionary).duplicate(true),
		"character_action": (character_action_value as Dictionary).duplicate(true),
		"character_input_owner": character_input_owner_snapshot(),
		"priority_arbitration": priority_arbitration_snapshot(),
		"coordinator": (coordinator_value as Dictionary).duplicate(true),
		"intent_router": (intent_value as Dictionary).duplicate(true),
		"next_time_action_token": _next_time_action_token,
		"time_action_generation": _time_action_generation,
		"replay_events": _weapon_replay_events.duplicate(true),
		"replay_capture_sequence": _weapon_replay_capture_sequence,
		"replay_fact_baseline": _weapon_replay_fact_baseline.duplicate(true),
		"replay_capture_invalid_reason": _weapon_replay_capture_invalid_reason,
		"replay_restore_invalid_reason": _weapon_replay_restore_invalid_reason,
	}


func can_prepare_gameplay_rewind() -> bool:
	return (
		_run_id != &""
		and not health.dead
		and action_state.current_state != PlayerActionStateScript.State.DEAD
		and weapon_action_coordinator != null
		and weapon_action_coordinator.has_method("cancel_for_gameplay_rewind")
		and weapon_action_coordinator.has_method("gameplay_rewind_snapshot")
		and weapon_action_coordinator.has_method("restore_gameplay_rewind_snapshot_for_rollback")
	)


func install_gameplay_rewind_state(target_snapshot: Dictionary) -> bool:
	if not can_prepare_gameplay_rewind() or not _valid_rewind_target_snapshot(target_snapshot):
		return false
	if not _cancel_uncommitted_character_action(&"gameplay_rewind"):
		return false
	if not bool(weapon_action_coordinator.call("cancel_for_gameplay_rewind")):
		return false
	if not action_state.force_safe_reset():
		return false
	_weapon_combo_timeout_frames = 0
	_dash_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_buffered_time_skill = &""
	_weapon_intent_router.call("reset_all")
	global_position = target_snapshot["position"]
	velocity = target_snapshot["velocity"]
	restore_rewind_facing(target_snapshot["facing"])
	return (
		global_position == target_snapshot["position"]
		and velocity == target_snapshot["velocity"]
		and _last_move_direction == (target_snapshot["facing"] as Vector2).normalized()
		and action_state.current_state == PlayerActionStateScript.State.FREE
	)


func restore_rewind_transaction_snapshot(value: Dictionary) -> bool:
	if not _valid_rewind_transaction_snapshot(value):
		return false
	if not bool(weapon_action_coordinator.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		(value["coordinator"] as Dictionary).duplicate(true)
	)):
		return false
	if not bool(action_state.call(
		"restore_transaction_snapshot",
		(value["action_state"] as Dictionary).duplicate(true)
	)):
		return false
	if not bool(character_action_coordinator.call(
		"restore_snapshot",
		(value["character"] as Dictionary).duplicate(true)
	)):
		return false
	if not bool(character_action_coordinator.call(
		"restore_action_snapshot",
		(value["character_action"] as Dictionary).duplicate(true)
	)):
		return false
	if not bool(_weapon_intent_router.call(
		"restore_runtime_snapshot",
		(value["intent_router"] as Dictionary).duplicate(true)
	)):
		return false
	global_position = value["position"]
	velocity = value["velocity"]
	_last_move_direction = value["facing"]
	_dash_velocity = value["dash_velocity"]
	_knockback_velocity = value["knockback_velocity"]
	_buffered_time_skill = StringName(str(value["buffered_time_skill"]))
	_weapon_combo_timeout_frames = int(value["combo_timeout_frames"])
	_runtime_frame = int(value["runtime_frame"])
	_next_time_action_token = int(value["next_time_action_token"])
	_time_action_generation = int(value["time_action_generation"])
	if not _restore_character_input_owner_snapshot(
		value["character_input_owner"] as Dictionary
	):
		return false
	_last_priority_arbitration = (
		value["priority_arbitration"] as Dictionary
	).duplicate(true)
	var replay_events: Array[Dictionary] = []
	for event_value: Variant in value["replay_events"] as Array:
		replay_events.append((event_value as Dictionary).duplicate(true))
	_restore_weapon_replay_event_log(replay_events, int(value["replay_capture_sequence"]))
	_weapon_replay_fact_baseline = (value["replay_fact_baseline"] as Dictionary).duplicate(true)
	_weapon_replay_capture_invalid_reason = StringName(str(value["replay_capture_invalid_reason"]))
	_weapon_replay_restore_invalid_reason = StringName(str(value["replay_restore_invalid_reason"]))
	return rewind_transaction_snapshot() == value


func gameplay_rewind_payload_guard() -> Dictionary:
	if weapon_action_coordinator == null or not weapon_action_coordinator.has_method("committed_payload_guard"):
		return {}
	var value: Variant = weapon_action_coordinator.call("committed_payload_guard")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func gameplay_rewind_commit_matches(
	target_snapshot: Dictionary,
	committed_payload_guard: Dictionary
) -> bool:
	return (
		_valid_rewind_target_snapshot(target_snapshot)
		and global_position == target_snapshot["position"]
		and velocity == target_snapshot["velocity"]
		and action_state.current_state == PlayerActionStateScript.State.FREE
		and gameplay_rewind_payload_guard() == committed_payload_guard
	)


func _valid_rewind_target_snapshot(value: Dictionary) -> bool:
	if (
		StringName(str(value.get("run_id", ""))) != _run_id
		or not value.get("position") is Vector2
		or not value.get("velocity") is Vector2
		or not value.get("facing") is Vector2
		or (value.get("facing") as Vector2).length_squared() <= 0.001
	):
		return false
	return true


func _valid_rewind_transaction_snapshot(value: Dictionary) -> bool:
	if value.size() != 23:
		return false
	for field: String in [
		"run_id", "position", "velocity", "facing", "dash_velocity",
		"knockback_velocity", "buffered_time_skill", "combo_timeout_frames",
		"runtime_frame", "action_state", "character", "character_action",
		"character_input_owner", "priority_arbitration", "coordinator", "intent_router",
		"next_time_action_token", "time_action_generation", "replay_events",
		"replay_capture_sequence", "replay_fact_baseline",
		"replay_capture_invalid_reason", "replay_restore_invalid_reason",
	]:
		if not value.has(field):
			return false
	if (
		not value["action_state"] is Dictionary
		or not action_state.has_method("can_restore_snapshot")
		or not bool(action_state.call(
			"can_restore_snapshot",
			(value["action_state"] as Dictionary).duplicate(true)
		))
	):
		return false
	return (
		StringName(str(value["run_id"])) == _run_id
		and value["position"] is Vector2
		and value["velocity"] is Vector2
		and value["facing"] is Vector2
		and value["dash_velocity"] is Vector2
		and value["knockback_velocity"] is Vector2
		and typeof(value["buffered_time_skill"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and typeof(value["combo_timeout_frames"]) == TYPE_INT
		and int(value["combo_timeout_frames"]) >= 0
		and typeof(value["runtime_frame"]) == TYPE_INT
		and int(value["runtime_frame"]) >= 0
		and value["coordinator"] is Dictionary
		and value["character"] is Dictionary
		and value["character_action"] is Dictionary
		and value["character_input_owner"] is Dictionary
		and _valid_character_input_owner_snapshot(value["character_input_owner"] as Dictionary)
		and value["priority_arbitration"] is Dictionary
		and value["intent_router"] is Dictionary
		and typeof(value["next_time_action_token"]) == TYPE_INT
		and int(value["next_time_action_token"]) > 0
		and typeof(value["time_action_generation"]) == TYPE_INT
		and int(value["time_action_generation"]) > 0
		and value["replay_events"] is Array
		and typeof(value["replay_capture_sequence"]) == TYPE_INT
		and int(value["replay_capture_sequence"]) >= 0
		and value["replay_fact_baseline"] is Dictionary
		and typeof(value["replay_capture_invalid_reason"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and typeof(value["replay_restore_invalid_reason"]) in [TYPE_STRING, TYPE_STRING_NAME]
	)


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
		"character": character_presentation_snapshot(),
		"active_item": active_item_presentation_snapshot(),
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


func configure_replay_view_identity(recorded_identity: Dictionary) -> bool:
	var world := SceneScope.replay_world(self)
	var identity := ReplayRecorderScript.validate_full_player_identity(recorded_identity)
	if world == null or not world.isolation_valid() or not world.owns_player(self) or process_mode != Node.PROCESS_MODE_DISABLED or is_physics_processing() or _hostile_frame_participant != null or _run_id != &"standalone" or _runtime_frame != 0 or identity.is_empty() or int(identity.owner_character_generation) < 2:
		return false
	var character := _character_profile_catalog_definition(StringName(identity.character_profile_id))
	var weapon := _weapon_profile_catalog_definition(StringName(identity.weapon_profile_id))
	if character.is_empty() or weapon.is_empty() or _normalized_mobility_profile(character.get("mobility", {})) != identity.mobility:
		return false
	var registry := ContentRegistryScript.new()
	var report = registry.load_packs([{"path": BASE_CONTENT_PACK_PATH, "required": true}], BASE_CONTENT_PACK_GAME_VERSION, &"LAUNCH")
	if report.has_blocking_errors():
		return false
	var talents: Array = []
	for id: String in identity.character_talent_ids:
		talents.append(registry.get_content(StringName(id)))
	var config := {"milestone": "M1" if identity.character_profile_id == "wanderer_m1_v1" else "LAUNCH", "character_id": identity.character_id, "weapon_id": identity.weapon_id, "character_profile": character, "weapon_profile": weapon, "character_talents": identity.character_talent_ids.duplicate(), "character_talent_definitions": talents, "enabled_time_skills": identity.time_ability_ids.duplicate()}
	if not configure_run(StringName(identity.run_id)):
		return false
	# Loadout reset advances both the payload and character generation once.
	_owner_character_generation = int(identity.owner_character_generation) - 1
	if not configure_loadout(config) or not stats.apply_profile(identity.stats):
		return false
	_apply_stats_to_components(true)
	_launch_replay_identity_baseline = identity.duplicate(true)
	return full_player_replay_identity() == identity


func full_player_replay_identity() -> Dictionary:
	var current := _current_full_player_replay_identity(
		_launch_replay_identity_baseline.is_empty()
	)
	if current.is_empty():
		return {}
	if str(current.get("character_profile_id", "")) == "wanderer_m1_v1":
		return current
	if _launch_replay_identity_baseline.is_empty():
		return current
	return _launch_replay_identity_baseline.duplicate(true)


func _current_full_player_replay_identity(require_exact_initial_talents: bool = true) -> Dictionary:
	if (
		_run_id == &""
		or _owner_character_generation <= 0
		or loadout_runtime == null
		or character_runtime == null
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("is_configured")
		or not bool(character_action_coordinator.call("is_configured"))
		or stats == null
		or not stats.has_method("snapshot")
	):
		return {}
	var loadout: Dictionary = loadout_runtime.call("snapshot")
	var character_id := str(loadout.get("character_id", "wanderer"))
	var stats_state: Dictionary = stats.call("snapshot")
	var mobility_state := mobility_snapshot()
	var profile_id := str(loadout_runtime.call("character_profile_id"))
	var loadout_talents: Array = loadout_runtime.call("character_talent_ids")
	var character_talents: Array[String] = []
	for talent_value: Variant in loadout_talents:
		character_talents.append(str(talent_value))
	var runtime_talents: Array[String] = []
	for talent_value: Variant in character_runtime.call("selected_talent_ids"):
		runtime_talents.append(str(talent_value))
	var character_action_value: Variant = character_action_coordinator.call("action_snapshot")
	if (
		character_id.is_empty()
		or profile_id.is_empty()
		or stats_state.is_empty()
		or mobility_state.is_empty()
		or str(character_runtime.call("character_id")) != character_id
		or str(character_runtime.call("profile_id")) != profile_id
		or (require_exact_initial_talents and runtime_talents != character_talents)
		or not character_action_value is Dictionary
		or int((character_action_value as Dictionary).get("generation", 0))
		!= _owner_character_generation
	):
		return {}
	var time_abilities: Array[String] = []
	for ability_value: Variant in loadout_runtime.call("time_ability_ids"):
		time_abilities.append(str(ability_value))
	var identity := {
		"run_id": str(_run_id),
		"owner_character_generation": _owner_character_generation,
		"character_id": character_id,
		"character_profile_id": profile_id,
		"character_talent_ids": character_talents,
		"weapon_id": str(loadout_runtime.call("weapon_id")),
		"weapon_profile_id": str(loadout_runtime.call("weapon_profile_id")),
		"time_ability_ids": time_abilities,
		"move_speed": float(stats.move_speed),
		"stats": stats_state,
		"mobility": mobility_state,
	}
	var projection := meta_run_projection_snapshot()
	if not projection.is_empty():
		identity["meta_projection_digest"] = projection.projection_digest
	return identity


func _capture_launch_replay_identity_baseline() -> bool:
	var current := _current_full_player_replay_identity()
	if current.is_empty():
		return false
	if str(current.get("character_profile_id", "")) == "wanderer_m1_v1":
		_launch_replay_identity_baseline.clear()
		return true
	_launch_replay_identity_baseline = current.duplicate(true)
	return true


func full_player_replay_snapshot() -> Dictionary:
	var identity := full_player_replay_identity()
	var rewind_state := _rewind_frame_transaction_snapshot()
	if (
		identity.is_empty()
		or rewind_state.is_empty()
		or health == null
		or not health.has_method("runtime_state_snapshot")
		or not health.has_method("can_restore_replay_snapshot")
		or not health.has_method("restore_replay_snapshot")
		or weapon_action_coordinator == null
		or time_manager == null
		or world_payload_authority == null
	):
		return {}
	var snapshot_schema_version := (
		ReplayRecorderScript.full_player_snapshot_schema_version_for_identity(identity)
	)
	var player_state := {
		"position": global_position,
		"velocity": velocity,
		"facing": _last_move_direction,
		"weapon_aim_direction": _last_weapon_aim_direction,
		"dash_cooldown_remaining_frames": _dash_cooldown_remaining_frames,
		"dash_velocity": _dash_velocity,
		"dash_direction": _dash_direction,
		"knockback_velocity": _knockback_velocity,
		"combo_timeout_frames": _weapon_combo_timeout_frames,
		"buffered_time_skill": _buffered_time_skill,
		"dash_completion_token": _dash_completion_token,
		"dash_completed_at_runtime_frame": _dash_completed_at_runtime_frame,
		"next_time_action_token": _next_time_action_token,
		"time_action_generation": _time_action_generation,
		"character_input_owner": character_input_owner_snapshot(),
		"priority_arbitration": priority_arbitration_snapshot(),
	}
	if ReplayRecorderScript.is_current_launch_snapshot_schema(snapshot_schema_version):
		if (
			not health.has_method("invulnerability_replay_snapshot")
			or not health.has_method("can_restore_invulnerability_replay_snapshot")
			or not health.has_method("restore_invulnerability_replay_snapshot")
		):
			return {}
		player_state["invulnerability_state"] = health.call(
			"invulnerability_replay_snapshot"
		)
	var snapshot := {
		"schema_version": snapshot_schema_version,
		"frame": _runtime_frame,
		"identity": identity,
		"player_state": player_state,
		"health_state": health.call("runtime_state_snapshot"),
		"action_state": action_state.snapshot(),
		"character_state": character_action_coordinator.call("snapshot"),
		"character_action_state": character_action_coordinator.call("action_snapshot"),
		"weapon_state": weapon_action_coordinator.call("snapshot"),
		"time_manager_state": time_manager.call("replay_snapshot"),
		"world_payload_state": world_payload_authority.call("replay_snapshot"),
		"rewind_state": rewind_state,
		"intent_router_state": _weapon_intent_router.call("runtime_snapshot"),
		"player_weapon_state": {
			"action_reward_claims": _weapon_action_reward_claims.duplicate(true),
			"action_ids_by_token": _weapon_action_ids_by_token.duplicate(true),
			"action_generations_by_token": _weapon_action_generations_by_token.duplicate(true),
			"action_mastery_contexts_by_token": _weapon_action_mastery_contexts_by_token.duplicate(true),
			"action_token_order": _weapon_action_token_order.duplicate(),
			"hit_fact_claims": _weapon_hit_fact_claims.duplicate(true),
			"mastery_target_ids_by_token": _weapon_mastery_target_ids_by_token.duplicate(true),
			"resource_fact_state": _weapon_resource_fact_state.duplicate(true),
			"next_token_floor": _next_weapon_action_token_floor,
			"combo_timeout_frames": _weapon_combo_timeout_frames,
		},
		"weapon_replay_events": _weapon_replay_events.duplicate(true),
		"weapon_replay_capture_sequence": _weapon_replay_capture_sequence,
		"weapon_replay_fact_baseline": _weapon_replay_fact_baseline.duplicate(true),
		"weapon_replay_capture_invalid_reason": _weapon_replay_capture_invalid_reason,
		"weapon_replay_restore_invalid_reason": _weapon_replay_restore_invalid_reason,
	}
	if ReplayRecorderScript.is_current_launch_snapshot_schema(int(snapshot["schema_version"])):
		var active_item_state := active_item_snapshot()
		var reward_effect_state := reward_effect_snapshot()
		var live_talent_state := _full_player_live_talent_state()
		if (
			active_item_state.is_empty()
			or reward_effect_state.is_empty()
			or live_talent_state.is_empty()
		):
			return {}
		snapshot["active_item_state"] = active_item_state
		snapshot["reward_effect_state"] = reward_effect_state
		snapshot["live_talent_state"] = live_talent_state
		snapshot["event_temporary_modifiers"] = event_temporary_modifier_snapshot()
	return snapshot


func _full_player_live_talent_state() -> Dictionary:
	if (
		character_runtime == null
		or not character_runtime.has_method("selected_talent_ids")
		or not character_runtime.has_method("talent_definition_snapshots")
		or not character_runtime.has_method("talent_modifier_snapshot")
	):
		return {}
	var selected_value: Variant = character_runtime.call("selected_talent_ids")
	var definitions_value: Variant = character_runtime.call("talent_definition_snapshots")
	var modifiers_value: Variant = character_runtime.call("talent_modifier_snapshot")
	if (
		not selected_value is Array
		or not definitions_value is Array
		or not modifiers_value is Dictionary
	):
		return {}
	return ReplayRecorderScript.full_player_live_talent_state(
		character_runtime.call("character_id"),
		selected_value,
		definitions_value,
		modifiers_value
	)


func restore_full_player_replay_snapshot(snapshot: Dictionary) -> bool:
	var normalized := _validated_full_player_replay_snapshot(snapshot)
	if normalized.is_empty() or normalized["identity"] != full_player_replay_identity():
		return false
	var before := full_player_replay_snapshot()
	if before.is_empty():
		return false
	if before == normalized:
		_last_authoritative_intents_frame = -1
		return true
	if _install_full_player_replay_snapshot(normalized, false):
		_last_authoritative_intents_frame = -1
		return true
	if not _install_full_player_replay_snapshot(before, true):
		set_physics_process(false)
		push_error("Full Player Replay restore rollback failed closed")
	return false


func _install_full_player_replay_snapshot(value: Dictionary, for_rollback: bool) -> bool:
	if not _can_install_full_player_replay_snapshot(value):
		return false
	var active_item_target: Dictionary = {}
	if value.has("active_item_state"):
		if (
			active_item_runtime == null
			or not active_item_runtime.has_method("can_restore_snapshot")
			or not active_item_runtime.has_method("restore_snapshot")
			or not value.get("active_item_state") is Dictionary
		):
			return false
		active_item_target = (
			value.get("active_item_state", {}) as Dictionary
		).duplicate(true)
		if not bool(active_item_runtime.call("can_restore_snapshot", active_item_target)):
			return false
	if (
		value.has("reward_effect_state")
		and not restore_reward_effect_snapshot(
			(value.get("reward_effect_state", {}) as Dictionary).duplicate(true),
			false,
			(value.player_state.get("invulnerability_state", {}) as Dictionary).duplicate(true)
		)
	):
		return false
	var health_target := (value.get("health_state", {}) as Dictionary).duplicate(true)
	if not bool(health.call("can_restore_replay_snapshot", health_target)):
		return false
	var world_target := (value.get("world_payload_state", {}) as Dictionary).duplicate(true)
	var world_ticket_value: Variant = world_payload_authority.call(
		"begin_transaction_restore",
		world_target
	)
	if not world_ticket_value is Dictionary or (world_ticket_value as Dictionary).is_empty():
		return false
	var world_ticket := (world_ticket_value as Dictionary).duplicate(true)
	if not bool(health.call("restore_replay_snapshot", health_target)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	var time_target := (value.get("time_manager_state", {}) as Dictionary).duplicate(true)
	if not bool(time_manager.call("restore_replay_snapshot", time_target)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	if not sync_event_temporary_modifiers(value.get("event_temporary_modifiers", [])):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	var action_target := (value.get("action_state", {}) as Dictionary).duplicate(true)
	if not bool(action_state.call("restore_replay_snapshot", action_target)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	var character_target := (value.get("character_state", {}) as Dictionary).duplicate(true)
	if not bool(character_action_coordinator.call("restore_replay_snapshot", character_target)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	var character_action_target := (
		value.get("character_action_state", {}) as Dictionary
	).duplicate(true)
	if not bool(character_action_coordinator.call(
		"restore_action_snapshot",
		character_action_target
	)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	if (
		value.has("active_item_state")
		and not bool(active_item_runtime.call("restore_snapshot", active_item_target))
	):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	var weapon_target := (value.get("weapon_state", {}) as Dictionary).duplicate(true)
	# Full Replay checkpoints are allowed to move generation/token state backward.
	# The coordinator's ordinary restore enforces live monotonicity, while this
	# exact restore path is already protected by the outer all-participant rollback.
	if not bool(weapon_action_coordinator.call(
		"restore_snapshot_for_rollback",
		weapon_target
	)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	if not bool(_weapon_intent_router.call(
		"restore_runtime_snapshot",
		(value.get("intent_router_state", {}) as Dictionary).duplicate(true)
	)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	if not _restore_rewind_frame_transaction_snapshot(
		(value.get("rewind_state", {}) as Dictionary).duplicate(true)
	):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	_install_player_weapon_replay_state(
		(value.get("player_weapon_state", {}) as Dictionary).duplicate(true)
	)
	var replay_events: Array[Dictionary] = []
	for event_value: Variant in value.get("weapon_replay_events", []) as Array:
		replay_events.append((event_value as Dictionary).duplicate(true))
	_restore_weapon_replay_event_log(
		replay_events,
		int(value.get("weapon_replay_capture_sequence", 0))
	)
	_weapon_replay_fact_baseline = (
		value.get("weapon_replay_fact_baseline", {}) as Dictionary
	).duplicate(true)
	_weapon_replay_capture_invalid_reason = StringName(str(
		value.get("weapon_replay_capture_invalid_reason", "")
	))
	_weapon_replay_restore_invalid_reason = StringName(str(
		value.get("weapon_replay_restore_invalid_reason", "")
	))

	var player_state := value.get("player_state", {}) as Dictionary
	_runtime_frame = int(value.get("frame", 0))
	global_position = player_state.get("position", global_position) as Vector2
	velocity = player_state.get("velocity", velocity) as Vector2
	_last_move_direction = player_state.get("facing", _last_move_direction) as Vector2
	_last_weapon_aim_direction = player_state.get(
		"weapon_aim_direction",
		_last_weapon_aim_direction
	) as Vector2
	_apply_weapon_aim_direction(_last_weapon_aim_direction)
	_dash_cooldown_remaining_frames = int(player_state.get(
		"dash_cooldown_remaining_frames",
		0
	))
	_dash_velocity = player_state.get("dash_velocity", Vector2.ZERO) as Vector2
	_dash_direction = player_state.get("dash_direction", Vector2.RIGHT) as Vector2
	_knockback_velocity = player_state.get("knockback_velocity", Vector2.ZERO) as Vector2
	_weapon_combo_timeout_frames = int(player_state.get("combo_timeout_frames", 0))
	_buffered_time_skill = StringName(str(player_state.get("buffered_time_skill", "")))
	_dash_completion_token = int(player_state.get("dash_completion_token", 0))
	_dash_completed_at_runtime_frame = int(player_state.get(
		"dash_completed_at_runtime_frame",
		-1
	))
	_next_time_action_token = int(player_state.get("next_time_action_token", 1))
	_time_action_generation = int(player_state.get("time_action_generation", 1))
	if not _restore_character_input_owner_snapshot(
		player_state.get("character_input_owner", {}) as Dictionary
	):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	if (
		ReplayRecorderScript.is_current_launch_snapshot_schema(int(value.get("schema_version", 0)))
		and not bool(health.call(
			"restore_invulnerability_replay_snapshot",
			(player_state.get("invulnerability_state", {}) as Dictionary).duplicate(true)
		))
	):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	_last_priority_arbitration = (
		player_state.get("priority_arbitration", {}) as Dictionary
	).duplicate(true)
	_sync_weapon_action_projection()
	if full_player_replay_snapshot() != value:
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	if not bool(world_payload_authority.call(
		"commit_transaction_restore",
		world_ticket
	)):
		_rollback_full_player_world_restore(world_ticket, for_rollback)
		return false
	return true


func _rollback_full_player_world_restore(ticket: Dictionary, for_rollback: bool) -> bool:
	if bool(world_payload_authority.call("rollback_transaction_restore", ticket)):
		return true
	set_physics_process(false)
	push_error(
		"Full Player Replay %s world rollback failed closed"
		% ("compensation" if for_rollback else "restore")
	)
	return false


func _can_install_full_player_replay_snapshot(value: Dictionary) -> bool:
	if value.has("event_temporary_modifiers") and not ReplayRecorderScript.validate_full_player_event_modifiers(value["event_temporary_modifiers"]):
		return false
	if value.has("active_item_state") and (
		active_item_runtime == null
		or not active_item_runtime.has_method("can_restore_snapshot")
		or not value.get("active_item_state") is Dictionary
		or not bool(active_item_runtime.call(
			"can_restore_snapshot",
			(value["active_item_state"] as Dictionary).duplicate(true)
		))
	):
		return false
	if value.has("reward_effect_state") and (
		not value.get("reward_effect_state") is Dictionary
		or not can_restore_reward_effect_snapshot(
			(value["reward_effect_state"] as Dictionary).duplicate(true),
			(value.player_state.get("invulnerability_state", {}) as Dictionary).duplicate(true)
		)
	):
		return false
	var health_target := (value.get("health_state", {}) as Dictionary).duplicate(true)
	var world_target := (value.get("world_payload_state", {}) as Dictionary).duplicate(true)
	var time_target := (value.get("time_manager_state", {}) as Dictionary).duplicate(true)
	var action_target := (value.get("action_state", {}) as Dictionary).duplicate(true)
	var character_target := (value.get("character_state", {}) as Dictionary).duplicate(true)
	var character_action_target := (
		value.get("character_action_state", {}) as Dictionary
	).duplicate(true)
	var weapon_target := (value.get("weapon_state", {}) as Dictionary).duplicate(true)
	var intent_target := (value.get("intent_router_state", {}) as Dictionary).duplicate(true)
	var rewind_target := (value.get("rewind_state", {}) as Dictionary).duplicate(true)
	var player_weapon_target := (
		value.get("player_weapon_state", {}) as Dictionary
	).duplicate(true)
	var player_state := value.get("player_state", {}) as Dictionary
	var is_launch_snapshot := ReplayRecorderScript.is_current_launch_snapshot_schema(int(value.get("schema_version", 0)))
	if is_launch_snapshot and (
		health == null
		or not health.has_method("can_restore_invulnerability_replay_snapshot")
		or not health.has_method("restore_invulnerability_replay_snapshot")
		or not player_state.get("invulnerability_state") is Dictionary
		or (
			not value.has("reward_effect_state")
			and not bool(health.call(
				"can_restore_invulnerability_replay_snapshot",
				(player_state["invulnerability_state"] as Dictionary).duplicate(true)
			))
		)
	):
		return false
	return (
		health != null
		and health.has_method("can_restore_replay_snapshot")
		and bool(health.call("can_restore_replay_snapshot", health_target))
		and world_payload_authority != null
		and world_payload_authority.has_method("can_restore_replay_snapshot")
		and world_payload_authority.has_method("begin_transaction_restore")
		and world_payload_authority.has_method("commit_transaction_restore")
		and world_payload_authority.has_method("rollback_transaction_restore")
		and bool(world_payload_authority.call("can_restore_replay_snapshot", world_target))
		and time_manager != null
		and time_manager.has_method("can_restore_replay_snapshot")
		and bool(time_manager.call("can_restore_replay_snapshot", time_target))
		and action_state.has_method("can_restore_replay_snapshot")
		and bool(action_state.call("can_restore_replay_snapshot", action_target))
		and character_action_coordinator != null
		and character_action_coordinator.has_method("can_restore_replay_snapshot")
		and bool(character_action_coordinator.call(
			"can_restore_replay_snapshot",
			character_target
		))
		and character_action_coordinator.has_method("can_restore_action_snapshot")
		and bool(character_action_coordinator.call(
			"can_restore_action_snapshot",
			character_action_target
		))
		and weapon_action_coordinator != null
		and weapon_action_coordinator.has_method("can_restore_snapshot_for_rollback")
		and bool(weapon_action_coordinator.call(
			"can_restore_snapshot_for_rollback",
			weapon_target
		))
		and _weapon_intent_router.has_method("can_restore_runtime_snapshot")
		and bool(_weapon_intent_router.call("can_restore_runtime_snapshot", intent_target))
		and _valid_rewind_frame_transaction_snapshot(rewind_target)
		and _valid_weapon_replay_player_state(player_weapon_target, weapon_target)
	)


func _validated_full_player_replay_snapshot(value: Dictionary) -> Dictionary:
	var normalization := ReplayRecorderScript.normalize_full_player_snapshot(value)
	if not bool(normalization.get("ok", false)):
		return {}
	value = (
		(normalization.get("context", {}) as Dictionary).get("snapshot", {}) as Dictionary
	).duplicate(true)
	var normalized_identity_value: Variant = value.get("identity")
	if not normalized_identity_value is Dictionary:
		return {}
	var normalized_identity := ReplayRecorderScript.validate_full_player_identity(
		normalized_identity_value as Dictionary
	)
	if normalized_identity.is_empty():
		return {}
	var expected_schema_version := (
		ReplayRecorderScript.full_player_snapshot_schema_version_for_identity(
			normalized_identity
		)
	)
	var fields: Array[String] = [
		"schema_version", "frame", "identity", "player_state", "health_state",
		"action_state", "character_state", "character_action_state", "weapon_state", "time_manager_state",
		"world_payload_state", "rewind_state", "intent_router_state",
		"player_weapon_state", "weapon_replay_events",
		"weapon_replay_capture_sequence", "weapon_replay_fact_baseline",
		"weapon_replay_capture_invalid_reason", "weapon_replay_restore_invalid_reason",
	]
	if ReplayRecorderScript.is_current_launch_snapshot_schema(expected_schema_version):
		fields.append("active_item_state")
		fields.append("reward_effect_state")
		fields.append("live_talent_state")
		fields.append("event_temporary_modifiers")
	if value.size() != fields.size():
		return {}
	for field: String in fields:
		if not value.has(field):
			return {}
	if (
		typeof(value.get("schema_version")) != TYPE_INT
		or typeof(value.get("frame")) != TYPE_INT
		or int(value["frame"]) < 0
		or not value["identity"] is Dictionary
		or not value["player_state"] is Dictionary
		or not value["health_state"] is Dictionary
		or not value["action_state"] is Dictionary
		or not value["character_state"] is Dictionary
		or not value["character_action_state"] is Dictionary
		or not value["weapon_state"] is Dictionary
		or not value["time_manager_state"] is Dictionary
		or not value["world_payload_state"] is Dictionary
		or not value["rewind_state"] is Dictionary
		or not value["intent_router_state"] is Dictionary
		or not value["player_weapon_state"] is Dictionary
		or not value["weapon_replay_events"] is Array
		or typeof(value.get("weapon_replay_capture_sequence")) != TYPE_INT
		or int(value["weapon_replay_capture_sequence"]) < 0
		or not value["weapon_replay_fact_baseline"] is Dictionary
		or typeof(value.get("weapon_replay_capture_invalid_reason")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value.get("weapon_replay_restore_invalid_reason")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or (
			ReplayRecorderScript.is_current_launch_snapshot_schema(expected_schema_version)
			and (
				not value.get("active_item_state") is Dictionary
				or not value.get("reward_effect_state") is Dictionary
				or not value.get("live_talent_state") is Dictionary
			)
		)
	):
		return {}
	if (
		int(value["schema_version"]) != expected_schema_version
	):
		return {}
	if ReplayRecorderScript.is_current_launch_snapshot_schema(expected_schema_version):
		if not ReplayRecorderScript.validate_full_player_event_modifiers(value.get("event_temporary_modifiers")):
			return {}
		var active_item_state := value.get("active_item_state", {}) as Dictionary
		if (
			active_item_runtime == null
			or not active_item_runtime.has_method("can_restore_snapshot")
			or not bool(active_item_runtime.call(
				"can_restore_snapshot",
				active_item_state.duplicate(true)
			))
			or not ReplayRecorderScript.validate_full_player_active_item_state(
				active_item_state,
				int(value["frame"])
			)
		):
			return {}
		var reward_effect_state := value.get("reward_effect_state", {}) as Dictionary
		if not ReplayRecorderScript.validate_full_player_reward_effect_state(
			reward_effect_state
		):
			return {}
		var live_talent_state := value.get("live_talent_state", {}) as Dictionary
		if (
			not ReplayRecorderScript.validate_full_player_live_talent_state(
				live_talent_state,
				normalized_identity
			)
		):
			return {}
		var sealed_character_state := value.get("character_state", {}) as Dictionary
		var sealed_character_runtime := sealed_character_state.get("runtime", {}) as Dictionary
		if (
			sealed_character_runtime.get("selected_talent_ids")
				!= live_talent_state.get("selected_talent_ids")
			or sealed_character_runtime.get("talent_definitions")
				!= live_talent_state.get("talent_definitions")
			or not _full_player_talent_definitions_match_authority(
				live_talent_state,
				normalized_identity
			)
		):
			return {}
	var player_state := value["player_state"] as Dictionary
	var player_state_fields: Array[String] = [
		"position", "velocity", "facing", "weapon_aim_direction",
		"dash_cooldown_remaining_frames", "dash_velocity", "dash_direction",
		"knockback_velocity", "combo_timeout_frames", "buffered_time_skill",
		"dash_completion_token", "dash_completed_at_runtime_frame",
		"next_time_action_token", "time_action_generation",
		"character_input_owner", "priority_arbitration",
	]
	var is_launch_snapshot := ReplayRecorderScript.is_current_launch_snapshot_schema(expected_schema_version)
	if is_launch_snapshot:
		player_state_fields.append("invulnerability_state")
	if player_state.size() != player_state_fields.size():
		return {}
	for player_state_field: String in player_state_fields:
		if not player_state.has(player_state_field):
			return {}
	for vector_field: String in [
		"position", "velocity", "facing", "dash_velocity", "dash_direction",
		"knockback_velocity", "weapon_aim_direction",
	]:
		if not player_state.get(vector_field) is Vector2:
			return {}
	for integer_field: String in [
		"dash_cooldown_remaining_frames", "combo_timeout_frames",
		"dash_completion_token", "dash_completed_at_runtime_frame",
		"next_time_action_token", "time_action_generation",
	]:
		if typeof(player_state.get(integer_field)) != TYPE_INT:
			return {}
	if (
		int(player_state["dash_cooldown_remaining_frames"]) < 0
		or int(player_state["combo_timeout_frames"]) < 0
		or int(player_state["dash_completion_token"]) < 0
		or int(player_state["dash_completed_at_runtime_frame"]) < -1
		or int(player_state["next_time_action_token"]) <= 0
		or int(player_state["time_action_generation"]) <= 0
		or typeof(player_state.get("buffered_time_skill")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or not player_state.get("character_input_owner") is Dictionary
		or not _valid_character_input_owner_snapshot(
			player_state.get("character_input_owner", {}) as Dictionary
		)
		or not player_state.get("priority_arbitration") is Dictionary
		or health == null
		or not health.has_method("can_restore_replay_snapshot")
		or not bool(health.call(
			"can_restore_replay_snapshot",
			(value["health_state"] as Dictionary).duplicate(true)
		))
		or int((value["time_manager_state"] as Dictionary).get("runtime_frame", -1)) != int(value["frame"])
		or int((value["action_state"] as Dictionary).get("frame", -1)) != int(value["frame"])
		or (
			int((value["character_state"] as Dictionary).get("last_runtime_frame", -2))
			!= int(value["frame"])
			and not (
				int(value["frame"]) == 0
				and int((value["character_state"] as Dictionary).get(
					"last_runtime_frame",
					-2
				)) == -1
			)
		)
		or int((value["character_action_state"] as Dictionary).get("generation", 0))
		!= int((value["identity"] as Dictionary).get("owner_character_generation", -1))
		or int((value["weapon_state"] as Dictionary).get("frame", -1)) != int(value["frame"])
		or int((value["world_payload_state"] as Dictionary).get("last_runtime_frame", -2)) != int(value["frame"])
		or int((value["rewind_state"] as Dictionary).get("last_runtime_frame", -1)) != int(value["frame"])
	):
		return {}
	if is_launch_snapshot and (
		not player_state.get("invulnerability_state") is Dictionary
		or health == null
		or not health.has_method("can_restore_full_replay_reward_snapshot")
		or not bool(health.call(
			"can_restore_full_replay_reward_snapshot",
			(value.reward_effect_state.health as Dictionary).duplicate(true),
			(player_state["invulnerability_state"] as Dictionary).duplicate(true)
		))
	):
		return {}
	for event_value: Variant in value["weapon_replay_events"] as Array:
		if not event_value is Dictionary:
			return {}
	return value.duplicate(true)


func _full_player_talent_definitions_match_authority(
	live_talent_state: Dictionary,
	identity: Dictionary
) -> bool:
	var selected_value: Variant = live_talent_state.get("selected_talent_ids")
	var definitions_value: Variant = live_talent_state.get("talent_definitions")
	if not selected_value is Array or not definitions_value is Array:
		return false
	var selected := selected_value as Array
	var definitions := definitions_value as Array
	if selected.size() != definitions.size():
		return false
	var registry: RefCounted = ContentRegistryScript.new()
	var report: RefCounted = registry.call("load_packs", [
		{"path": BASE_CONTENT_PACK_PATH, "required": true},
	], BASE_CONTENT_PACK_GAME_VERSION, &"LAUNCH")
	if report == null or bool(report.call("has_blocking_errors")):
		return false
	var definitions_by_id: Dictionary = {}
	for talent_value: Variant in selected:
		var definition_id := str(talent_value)
		var definition: Dictionary = registry.call(
			"get_content",
			StringName(definition_id)
		)
		if (
			definition_id.is_empty()
			or str(definition.get("category", "")) != "talent"
			or definitions_by_id.has(definition_id)
		):
			return false
		definitions_by_id[definition_id] = definition.duplicate(true)
	for index: int in range(selected.size()):
		var talent_id := str(selected[index])
		if (
			talent_id.is_empty()
			or not definitions[index] is Dictionary
			or not definitions_by_id.has(talent_id)
			or (definitions[index] as Dictionary) != definitions_by_id[talent_id]
		):
			return false
		var compatibility: Variant = (
			definitions[index] as Dictionary
		).get("compatibility", {})
		if not compatibility is Dictionary:
			return false
		var character_ids_value: Variant = (compatibility as Dictionary).get(
			"character_ids",
			[]
		)
		if (
			not character_ids_value is Array
			or not (character_ids_value as Array).has(str(identity.get("character_id", "")))
		):
			return false
	return true


func weapon_replay_snapshot() -> Dictionary:
	if _weapon_replay_capture_invalid_reason == &"" and _has_active_current_rift_payload():
		_weapon_replay_capture_invalid_reason = &"ACTIVE_RIFT_REPLAY_UNSUPPORTED"
		_weapon_replay_fact_baseline.clear()
	if (
		_weapon_replay_capture_invalid_reason != &""
		or weapon_action_coordinator == null
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
			"action_mastery_contexts_by_token": _weapon_action_mastery_contexts_by_token.duplicate(true),
			"action_token_order": _weapon_action_token_order.duplicate(),
			"hit_fact_claims": _weapon_hit_fact_claims.duplicate(true),
			"mastery_target_ids_by_token": _weapon_mastery_target_ids_by_token.duplicate(true),
			"resource_fact_state": _weapon_resource_fact_state.duplicate(true),
			"next_token_floor": _next_weapon_action_token_floor,
			"combo_timeout_frames": _weapon_combo_timeout_frames,
		},
	}


func weapon_replay_capture_status() -> Dictionary:
	if _weapon_replay_capture_invalid_reason == &"":
		return {"ok": true, "code": &"OK"}
	return {
		"ok": false,
		"code": _weapon_replay_capture_invalid_reason,
	}


func weapon_replay_restore_status() -> Dictionary:
	if _weapon_replay_restore_invalid_reason == &"":
		return {"ok": true, "code": &"OK"}
	return {
		"ok": false,
		"code": _weapon_replay_restore_invalid_reason,
	}


func mark_gameplay_rewind_replay_boundary() -> void:
	_weapon_replay_capture_invalid_reason = &"GAMEPLAY_REWIND_UNSUPPORTED"
	_weapon_replay_fact_baseline.clear()


func _refresh_weapon_replay_fact_baseline() -> void:
	if _weapon_replay_capture_invalid_reason != &"":
		_weapon_replay_fact_baseline.clear()
		return
	var snapshot := weapon_replay_snapshot()
	_weapon_replay_fact_baseline = snapshot.duplicate(true) if not snapshot.is_empty() else {}


func restore_weapon_replay_snapshot(snapshot: Dictionary) -> bool:
	_weapon_replay_restore_invalid_reason = &"RESTORE_REJECTED"
	var normalized := _validated_weapon_replay_snapshot(snapshot)
	var world_snapshot := _world_payload_replay_snapshot()
	if not (world_snapshot.get("descriptors", []) as Array).is_empty():
		_weapon_replay_restore_invalid_reason = &"ACTIVE_WORLD_PAYLOAD_REPLAY_UNSUPPORTED"
		return false
	var target_frame := int(normalized.get("frame", -1))
	if (
		normalized.is_empty()
		or not _can_reanchor_weapon_replay_clocks(target_frame)
		or not _weapon_action_state_can_restore_replay()
		or time_manager == null
		or not time_manager.has_method("begin_weapon_replay_restore_transaction")
		or not time_manager.has_method("commit_weapon_replay_restore_transaction")
		or not time_manager.has_method("rollback_weapon_replay_restore_transaction")
		or not ReplayRecorderScript.event_prefix_matches(normalized, _weapon_replay_events)
	):
		_weapon_replay_restore_invalid_reason = &"RESTORE_PRECONDITION_REJECTED"
		return false
	var target_event_prefix_count := int(normalized["event_prefix_count"])
	var before := weapon_replay_snapshot()
	if before.is_empty():
		return false
	if before == normalized:
		_refresh_weapon_replay_fact_baseline()
		_weapon_replay_restore_invalid_reason = &""
		return true
	var before_events: Array[Dictionary] = _weapon_replay_events.duplicate(true)
	var before_capture_sequence := _weapon_replay_capture_sequence
	var before_coordinator := (before.get("coordinator", {}) as Dictionary).duplicate(true)
	var clock_before := _weapon_replay_clock_snapshot()
	if clock_before.is_empty():
		_weapon_replay_restore_invalid_reason = &"CLOCK_SNAPSHOT_REJECTED"
		return false
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
	if not _reanchor_weapon_replay_clocks(target_frame):
		var coordinator_rollback_after_clock_failure := (
			not before_coordinator.is_empty()
			and _rollback_weapon_coordinator_replay_snapshot(before_coordinator)
		)
		_install_player_weapon_replay_state(before.get("player_weapon_state", {}) as Dictionary)
		_restore_weapon_replay_event_log(before_events, before_capture_sequence)
		var time_rollback_after_clock_failure := bool(time_manager.call(
			"rollback_weapon_replay_restore_transaction",
			time_restore_transaction_token
		))
		var clock_rollback_after_failure := _restore_weapon_replay_clocks(clock_before)
		if (
			not coordinator_rollback_after_clock_failure
			or not time_rollback_after_clock_failure
			or not clock_rollback_after_failure
		):
			_fail_closed_weapon_replay_restore(&"clock_reanchor_rollback_failed")
		_weapon_replay_restore_invalid_reason = &"CLOCK_REANCHOR_REJECTED"
		return false
	if weapon_replay_snapshot() == normalized:
		if bool(time_manager.call(
			"commit_weapon_replay_restore_transaction",
			time_restore_transaction_token
		)):
			_refresh_weapon_replay_fact_baseline()
			_weapon_replay_restore_invalid_reason = &""
			return true
		var coordinator_rollback_after_commit_failure := (
			not before_coordinator.is_empty()
			and _rollback_weapon_coordinator_replay_snapshot(before_coordinator)
		)
		_install_player_weapon_replay_state(before.get("player_weapon_state", {}) as Dictionary)
		_restore_weapon_replay_event_log(before_events, before_capture_sequence)
		var clock_rollback_after_commit_failure := _restore_weapon_replay_clocks(clock_before)
		if not coordinator_rollback_after_commit_failure or not clock_rollback_after_commit_failure:
			_fail_closed_weapon_replay_restore(&"time_restore_commit_failed")
		_weapon_replay_restore_invalid_reason = &"TIME_RESTORE_COMMIT_REJECTED"
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
	var clock_rollback_ok := _restore_weapon_replay_clocks(clock_before)
	if not coordinator_rollback_ok or not time_rollback_ok or not clock_rollback_ok:
		_fail_closed_weapon_replay_restore(&"coordinator_rollback_failed")
		return false
	if weapon_replay_snapshot() != before or _weapon_replay_events != before_events:
		_fail_closed_weapon_replay_restore(&"rollback_verification_failed")
	return false


func _has_active_current_rift_payload() -> bool:
	if world_payload_authority == null or not world_payload_authority.has_method("replay_snapshot"):
		return false
	var snapshot := _world_payload_replay_snapshot()
	for descriptor_value: Variant in snapshot.get("descriptors", []) as Array:
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		if (
			StringName(str(descriptor.get("handler_id", ""))) == &"time_rift"
			and StringName(str(descriptor.get("run_id", ""))) == _run_id
			and int(descriptor.get("owner_character_generation", 0))
			== _owner_character_generation
		):
			return true
	return false


func _world_payload_replay_snapshot() -> Dictionary:
	if world_payload_authority == null or not world_payload_authority.has_method("replay_snapshot"):
		return {}
	var value: Variant = world_payload_authority.call("replay_snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _can_reanchor_weapon_replay_clocks(target_frame: int) -> bool:
	if _weapon_replay_clocks_match(target_frame):
		return true
	var character_can_reanchor := (
		character_action_coordinator != null
		and (
			(
				not bool(character_action_coordinator.call("is_configured"))
				and character_action_coordinator.has_method(
					"reanchor_unconfigured_runtime_frame"
				)
			)
			or (
				character_action_coordinator.has_method(
					"can_reanchor_replay_neutral_runtime_frame"
				)
				and bool(character_action_coordinator.call(
					"can_reanchor_replay_neutral_runtime_frame",
					target_frame
				))
			)
		)
	)
	return (
		target_frame >= 0
		and character_can_reanchor
		and world_payload_authority != null
		and world_payload_authority.has_method("reanchor_empty_runtime_clock")
		and world_payload_authority.has_method("restore_transaction_snapshot")
		and (_world_payload_replay_snapshot().get("descriptors", []) as Array).is_empty()
		and rewind_recorder != null
		and not bool(rewind_recorder.call("has_snapshot"))
		and time_manager != null
		and time_manager.has_method("replay_snapshot")
		and time_manager.has_method("restore_replay_snapshot")
	)


func _weapon_replay_clocks_match(target_frame: int) -> bool:
	if (
		target_frame < 0
		or time_manager == null
		or not time_manager.has_method("replay_snapshot")
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("snapshot")
		or world_payload_authority == null
		or not world_payload_authority.has_method("replay_snapshot")
		or rewind_recorder == null
	):
		return false
	var time_value: Variant = time_manager.call("replay_snapshot")
	var character_value: Variant = character_action_coordinator.call("snapshot")
	var world_value: Variant = world_payload_authority.call("replay_snapshot")
	return (
		time_value is Dictionary
		and character_value is Dictionary
		and world_value is Dictionary
		and _runtime_frame == target_frame
		and int((time_value as Dictionary).get("runtime_frame", -1)) == target_frame
		and int(action_state.snapshot().get("frame", -1)) == target_frame
		and int((character_value as Dictionary).get("last_runtime_frame", -1)) == target_frame
		and int((world_value as Dictionary).get("last_runtime_frame", -1)) == target_frame
		and int(rewind_recorder.get("_last_runtime_frame")) == target_frame
	)


func _weapon_replay_clock_snapshot() -> Dictionary:
	var time_value: Variant = time_manager.call("replay_snapshot")
	var character_value: Variant = character_action_coordinator.call("snapshot")
	var world_value: Variant = world_payload_authority.call("replay_snapshot")
	var intent_value: Variant = _weapon_intent_router.call("runtime_snapshot")
	if (
		not time_value is Dictionary
		or not character_value is Dictionary
		or not world_value is Dictionary
		or not intent_value is Dictionary
	):
		return {}
	return {
		"runtime_frame": _runtime_frame,
		"time": (time_value as Dictionary).duplicate(true),
		"action": action_state.snapshot(),
		"character": (character_value as Dictionary).duplicate(true),
		"world": (world_value as Dictionary).duplicate(true),
		"intent_router": (intent_value as Dictionary).duplicate(true),
		"rewind_runtime_frame": int(rewind_recorder.get("_last_runtime_frame")),
	}


func _reanchor_weapon_replay_clocks(target_frame: int) -> bool:
	if _weapon_replay_clocks_match(target_frame):
		return true
	var time_target := time_manager.call("replay_snapshot") as Dictionary
	time_target["runtime_frame"] = target_frame
	if not bool(time_manager.call("restore_replay_snapshot", time_target)):
		return false
	var action_target := action_state.snapshot()
	action_target["frame"] = target_frame
	if not bool(action_state.call("restore_transaction_snapshot", action_target)):
		return false
	var character_reanchored := (
		bool(character_action_coordinator.call(
			"reanchor_replay_neutral_runtime_frame",
			target_frame
		))
		if bool(character_action_coordinator.call("is_configured"))
		else bool(character_action_coordinator.call(
			"reanchor_unconfigured_runtime_frame",
			target_frame
		))
	)
	if not character_reanchored:
		return false
	if not bool(world_payload_authority.call(
		"reanchor_empty_runtime_clock",
		target_frame
	)):
		return false
	rewind_recorder.set("_last_runtime_frame", target_frame)
	_runtime_frame = target_frame
	return (
		int((time_manager.call("replay_snapshot") as Dictionary).get("runtime_frame", -1))
		== target_frame
		and int(action_state.snapshot().get("frame", -1)) == target_frame
		and int((character_action_coordinator.call("snapshot") as Dictionary).get(
			"last_runtime_frame",
			-1
		)) == target_frame
		and int((world_payload_authority.call("replay_snapshot") as Dictionary).get(
			"last_runtime_frame",
			-1
		)) == target_frame
		and int(rewind_recorder.get("_last_runtime_frame")) == target_frame
	)


func _restore_weapon_replay_clocks(value: Dictionary) -> bool:
	var time_ok := bool(time_manager.call(
		"restore_replay_snapshot",
		(value.get("time", {}) as Dictionary).duplicate(true)
	))
	var action_ok := bool(action_state.call(
		"restore_transaction_snapshot",
		(value.get("action", {}) as Dictionary).duplicate(true)
	))
	var character_ok := bool(character_action_coordinator.call(
		"restore_snapshot",
		(value.get("character", {}) as Dictionary).duplicate(true)
	))
	var world_ok := bool(world_payload_authority.call(
		"restore_transaction_snapshot",
		(value.get("world", {}) as Dictionary).duplicate(true)
	))
	var intent_ok := bool(_weapon_intent_router.call(
		"restore_runtime_snapshot",
		(value.get("intent_router", {}) as Dictionary).duplicate(true)
	))
	rewind_recorder.set(
		"_last_runtime_frame",
		int(value.get("rewind_runtime_frame", 0))
	)
	_runtime_frame = int(value.get("runtime_frame", 0))
	return time_ok and action_ok and character_ok and world_ok and intent_ok


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
		or not state.get("action_mastery_contexts_by_token") is Dictionary
		or not state.get("action_token_order") is Array
		or not state.get("hit_fact_claims") is Dictionary
		or not state.get("mastery_target_ids_by_token") is Dictionary
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
	var mastery_contexts := state["action_mastery_contexts_by_token"] as Dictionary
	var mastery_targets := state["mastery_target_ids_by_token"] as Dictionary
	var token_order := state["action_token_order"] as Array
	if (
		action_ids.size() != generations.size()
		or action_ids.size() != mastery_contexts.size()
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
			or not mastery_contexts.has(token)
		):
			return false
		var mastery_context_value: Variant = mastery_contexts[token]
		if not mastery_context_value is Dictionary:
			return false
		var mastery_context := mastery_context_value as Dictionary
		if (
			not _dictionary_has_exact_fields(mastery_context, ["context", "plan"])
			or not mastery_context["context"] is Dictionary
			or not mastery_context["plan"] is Dictionary
			or not ReplaySafeValueScript.is_supported(mastery_context)
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
	for token_value: Variant in mastery_targets.keys():
		if typeof(token_value) != TYPE_INT or not action_ids.has(int(token_value)):
			return false
		var targets_value: Variant = mastery_targets[token_value]
		if not targets_value is Array:
			return false
		var previous_target := 0
		for target_value: Variant in targets_value as Array:
			if typeof(target_value) != TYPE_INT or int(target_value) <= previous_target:
				return false
			previous_target = int(target_value)
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
	_weapon_action_mastery_contexts_by_token = (
		state.get("action_mastery_contexts_by_token", {}) as Dictionary
	).duplicate(true)
	_weapon_action_token_order.clear()
	for token_value: Variant in state.get("action_token_order", []):
		_weapon_action_token_order.append(int(token_value))
	_weapon_hit_fact_claims = (state.get("hit_fact_claims", {}) as Dictionary).duplicate(true)
	_weapon_mastery_target_ids_by_token = (
		state.get("mastery_target_ids_by_token", {}) as Dictionary
	).duplicate(true)
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
	_weapon_action_mastery_contexts_by_token.clear()
	_weapon_action_token_order.clear()
	_weapon_hit_fact_claims.clear()
	_weapon_mastery_target_ids_by_token.clear()
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
	base_value: float = 1.0,
	stack_rule: StringName = &"multiply",
	required_weapon_id: StringName = &""
) -> bool:
	var resolved_weapon_id := required_weapon_id
	if resolved_weapon_id == &"":
		if loadout_runtime == null or not loadout_runtime.has_method("weapon_id"):
			return false
		resolved_weapon_id = StringName(str(loadout_runtime.call("weapon_id")))
	return apply_weapon_capability_effects([{
		"capability": str(capability),
		"value": value,
		"base_value": base_value,
		"stack_rule": str(stack_rule),
		"weapon_id": str(resolved_weapon_id),
	}])


func weapon_upgrade_snapshot() -> Dictionary:
	if (
		loadout_runtime == null
		or not loadout_runtime.has_method("weapon_id")
		or weapon_modifier_state == null
		or not weapon_modifier_state.has_method("snapshot")
	):
		return {}
	var weapon_id := StringName(str(loadout_runtime.call("weapon_id")))
	if weapon_id not in WEAPON_ADAPTER_IDS:
		return {}
	var modifiers_value: Variant = weapon_modifier_state.call("snapshot")
	if not modifiers_value is Dictionary:
		return {}
	var modifiers := (modifiers_value as Dictionary).duplicate(true)
	return {
		"schema_version": WEAPON_UPGRADE_SNAPSHOT_SCHEMA_VERSION,
		"weapon_id": str(weapon_id),
		"modifiers": modifiers,
	}


func can_restore_weapon_upgrade_snapshot(value: Dictionary) -> bool:
	if not _dictionary_has_exact_fields(
		value,
		["schema_version", "weapon_id", "modifiers"]
	):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != WEAPON_UPGRADE_SNAPSHOT_SCHEMA_VERSION
		or typeof(value["weapon_id"]) != TYPE_STRING
		or not value["modifiers"] is Dictionary
		or loadout_runtime == null
		or not loadout_runtime.has_method("weapon_id")
		or str(value["weapon_id"]) != str(loadout_runtime.call("weapon_id"))
		or StringName(str(value["weapon_id"])) not in WEAPON_ADAPTER_IDS
		or weapon_modifier_state == null
		or not weapon_modifier_state.has_method("can_restore_snapshot")
		or not bool(weapon_modifier_state.call(
			"can_restore_snapshot",
			(value["modifiers"] as Dictionary).duplicate(true)
		))
	):
		return false
	return true


func restore_weapon_upgrade_snapshot(value: Dictionary) -> bool:
	if not can_restore_weapon_upgrade_snapshot(value):
		return false
	var before := weapon_upgrade_snapshot()
	if before.is_empty():
		return false
	if before == value:
		return true
	var target_modifiers := (value["modifiers"] as Dictionary).duplicate(true)
	if bool(weapon_modifier_state.call(
		"restore_snapshot", target_modifiers
	)) and weapon_upgrade_snapshot() == value:
		return true
	var before_modifiers := (before["modifiers"] as Dictionary).duplicate(true)
	var modifier_rollback_ok := bool(weapon_modifier_state.call(
		"restore_snapshot", before_modifiers
	))
	if not modifier_rollback_ok or weapon_upgrade_snapshot() != before:
		push_error("Player weapon-upgrade snapshot rollback failed")
	return false


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
	_confirm_live_weapon_intent_mastery(result)
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
	if _dash_cooldown_remaining_frames > 0 or not action_state.can_transition_to(PlayerActionStateScript.State.DASH):
		return false
	if not _cancel_uncommitted_character_action(&"dash"):
		return false
	if (
		action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY
		or _weapon_hold_is_active()
	):
		_cancel_weapon_action(&"dash_cancel")
	if not action_state.transition_to(
		PlayerActionStateScript.State.DASH,
		int(_mobility_profile["dash_duration_frames"])
	):
		return false
	_dash_cooldown_remaining_frames = int(_mobility_profile["dash_cooldown_frames"])
	_dash_direction = _last_move_direction.normalized()
	_dash_velocity = _dash_direction * float(_mobility_profile["dash_speed"])
	health.apply_invulnerability(
		float(_mobility_profile["dash_invulnerable_frames"]) * FIXED_FRAME_SECONDS
		+ _dash_invulnerable_bonus
	)
	SceneScope.event_bus(self).player_dashed.emit({})
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
	var canonical_id: StringName = time_manager.canonical_skill_id(skill_id)
	var transaction_context := committed_context.duplicate(true)
	transaction_context.erase("recorder")
	if canonical_id == &"rewind":
		transaction_context["pre_return_position"] = global_position
	var player_before_time_cast := rewind_transaction_snapshot()
	if player_before_time_cast.is_empty():
		return false
	if (
		action_state.current_state == PlayerActionStateScript.State.ATTACK_RECOVERY
		or _weapon_hold_is_active()
	):
		_cancel_weapon_action(&"time_cast_cancel")
	if not action_state.transition_to(
		PlayerActionStateScript.State.TIME_CAST,
		_seconds_to_frames(TIME_CAST_DURATION)
	):
		if not restore_rewind_transaction_snapshot(player_before_time_cast):
			set_physics_process(false)
			push_error("Player time-cast transition rollback failed closed")
		return false
	var time_action_token := _next_time_action_token
	var transaction: Dictionary = time_manager.prepare_time_action(
		time_action_token,
		_time_action_generation,
		_runtime_frame,
		_run_id,
		canonical_id,
		transaction_context
	)
	if transaction.is_empty():
		if not restore_rewind_transaction_snapshot(player_before_time_cast):
			set_physics_process(false)
			push_error("Player time-cast prepare rollback failed closed")
		return false
	var commit_result: Dictionary = time_manager.commit_time_action(transaction)
	var committed := bool(commit_result.get("ok", false))
	if committed:
		_next_time_action_token += 1
	elif not restore_rewind_transaction_snapshot(player_before_time_cast):
		set_physics_process(false)
		push_error("Player time-cast commit rollback failed closed")
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


func character_runtime_snapshot() -> Dictionary:
	if character_runtime == null or character_action_coordinator == null:
		return {}
	var runtime_value: Variant = character_runtime.call("snapshot")
	var coordinator_value: Variant = character_action_coordinator.call("snapshot")
	var action_value: Variant = character_action_coordinator.call("action_snapshot")
	if (
		not runtime_value is Dictionary
		or not coordinator_value is Dictionary
		or not action_value is Dictionary
	):
		return {}
	return {
		"character_id": str(character_runtime.call("character_id")),
		"profile_id": str(character_runtime.call("profile_id")),
		"selected_talent_ids": character_runtime.call("selected_talent_ids"),
		"runtime": (runtime_value as Dictionary).duplicate(true),
		"coordinator": (coordinator_value as Dictionary).duplicate(true),
		"action": (action_value as Dictionary).duplicate(true),
	}


func character_presentation_snapshot() -> Dictionary:
	if character_runtime == null:
		return {}
	var value: Variant = character_runtime.call("presentation_snapshot")
	if not value is Dictionary:
		return {}
	var result := (value as Dictionary).duplicate(true)
	var runtime_value: Variant = character_runtime.call("snapshot")
	if not runtime_value is Dictionary:
		return result
	var strategy := (runtime_value as Dictionary).get("strategy", {}) as Dictionary
	var runtime_kind := StringName(str(strategy.get("runtime_kind", "")))
	match runtime_kind:
		&"wanderer":
			result["path_progress"] = int(strategy.get("path_progress", 0))
			result["wayfarer_active"] = int(strategy.get("wayfarer_until_frame", -1)) > _runtime_frame
			result["wayfarer_until_frame"] = int(strategy.get("wayfarer_until_frame", -1))
			result["anchor_active"] = bool(strategy.get("anchor_active", false))
			result["anchor_expires_frame"] = int(strategy.get("anchor_expires_frame", -1))
			result["skill_cooldown_until_frame"] = int(strategy.get("skill_cooldown_until_frame", -1))
		&"time_guardian":
			var skill_action := strategy.get("skill_action", {}) as Dictionary
			var fortress_until_frame := int(strategy.get("fortress_until_frame", -1))
			var fortress_active := fortress_until_frame > _runtime_frame
			result["guard_active"] = (
				not skill_action.is_empty()
				and not bool(skill_action.get("committed", false))
			)
			result["fortress_active"] = fortress_active
			result["fortress_until_frame"] = fortress_until_frame
			result["fortress_shockwave_armed"] = bool(strategy.get("fortress_shockwave_armed", false))
			result["rebuke_active"] = int(strategy.get("rebuke_until_frame", -1)) > _runtime_frame
			result["rebuke_until_frame"] = int(strategy.get("rebuke_until_frame", -1))
			result["skill_cooldown_until_frame"] = int(strategy.get("skill_cooldown_until_frame", -1))
			result["movement_multiplier"] = 1.0
			if fortress_active and character_runtime.has_method("profile_snapshot"):
				var profile := character_runtime.call("profile_snapshot") as Dictionary
				var skill := profile.get("character_skill", {}) as Dictionary
				var parameters := skill.get("parameters", {}) as Dictionary
				result["movement_multiplier"] = float(parameters.get("movement_multiplier", 1.0))
	return result


func _assemble_character_runtime(config: Dictionary) -> Dictionary:
	var definition_value: Variant = config.get("character_profile", {})
	var talent_ids_value: Variant = config.get("character_talents", [])
	var talent_definitions_value: Variant = config.get(
		"character_talent_definitions", []
	)
	if (
		not definition_value is Dictionary
		or (definition_value as Dictionary).is_empty()
		or not talent_ids_value is Array
		or not talent_definitions_value is Array
	):
		return {"ok": false, "reason": "character_profile_missing"}
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(
		(definition_value as Dictionary).duplicate(true)
	)
	if profile == null:
		return {"ok": false, "reason": "character_profile_invalid"}
	var runtime = PlayerCharacterRuntimeScript.new()
	if not bool(runtime.call(
		"configure",
		self,
		profile,
		(talent_ids_value as Array).duplicate(true),
		(talent_definitions_value as Array).duplicate(true)
	)):
		return {"ok": false, "reason": "character_runtime_configuration_failed"}
	var coordinator = CharacterActionCoordinatorScript.new()
	var generation_floor := maxi(1, _owner_character_generation)
	var next_token_floor := (
		int(character_action_coordinator.call("next_token"))
		if character_action_coordinator != null
		and character_action_coordinator.has_method("next_token")
		else 1
	)
	if (
		not bool(coordinator.call("set_generation_floor", generation_floor))
		or not bool(coordinator.call("set_next_token_floor", next_token_floor))
		or not bool(coordinator.call("configure", runtime, SceneScope.event_bus(self)))
	):
		return {"ok": false, "reason": "character_coordinator_configuration_failed"}
	return {
		"ok": true,
		"profile": profile,
		"runtime": runtime,
		"coordinator": coordinator,
	}


func install_character_talent(definition: Dictionary) -> bool:
	if (
		loadout_runtime == null
		or character_runtime == null
		or not loadout_runtime.has_method("install_character_talent")
		or not character_runtime.has_method("install_talent")
		or not character_runtime.has_method("snapshot")
	):
		return false
	var loadout_before: Dictionary = loadout_runtime.call("snapshot")
	var runtime_before_value: Variant = character_runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return false
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	if not bool(loadout_runtime.call(
		"install_character_talent",
		definition.duplicate(true)
	)):
		return false
	if not bool(character_runtime.call("install_talent", definition.duplicate(true))):
		if not bool(loadout_runtime.call("configure", loadout_before.duplicate(true))):
			set_physics_process(false)
			push_error("Character talent loadout rollback failed closed")
		return false
	var loadout_ids: Array[String] = []
	for id_value: Variant in loadout_runtime.call("character_talent_ids"):
		loadout_ids.append(str(id_value))
	var runtime_ids: Array[String] = []
	for id_value: Variant in character_runtime.call("selected_talent_ids"):
		runtime_ids.append(str(id_value))
	if loadout_ids != runtime_ids:
		var loadout_rollback_ok := bool(loadout_runtime.call(
			"configure",
			loadout_before.duplicate(true)
		))
		var runtime_rollback_ok := bool(character_runtime.call(
			"restore_snapshot",
			runtime_before.duplicate(true)
		))
		if not loadout_rollback_ok or not runtime_rollback_ok:
			set_physics_process(false)
			push_error("Character talent identity rollback failed closed")
		return false
	return true


func character_talent_transaction_snapshot() -> Dictionary:
	if (
		loadout_runtime == null
		or character_runtime == null
		or not loadout_runtime.has_method("snapshot")
		or not character_runtime.has_method("snapshot")
	):
		return {}
	var runtime_value: Variant = character_runtime.call("snapshot")
	if not runtime_value is Dictionary:
		return {}
	return {
		"loadout": (loadout_runtime.call("snapshot") as Dictionary).duplicate(true),
		"runtime": (runtime_value as Dictionary).duplicate(true),
	}


func restore_character_talent_transaction_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 2
		or not value.get("loadout") is Dictionary
		or not value.get("runtime") is Dictionary
		or loadout_runtime == null
		or character_runtime == null
	):
		return false
	var before := character_talent_transaction_snapshot()
	if before.is_empty():
		return false
	if (
		bool(loadout_runtime.call(
			"configure",
			(value["loadout"] as Dictionary).duplicate(true)
		))
		and bool(character_runtime.call(
			"restore_snapshot",
			(value["runtime"] as Dictionary).duplicate(true)
		))
		and character_talent_transaction_snapshot() == value
	):
		return true
	var loadout_rollback_ok := bool(loadout_runtime.call(
		"configure",
		(before["loadout"] as Dictionary).duplicate(true)
	))
	var runtime_rollback_ok := bool(character_runtime.call(
		"restore_snapshot",
		(before["runtime"] as Dictionary).duplicate(true)
	))
	if not loadout_rollback_ok or not runtime_rollback_ok:
		set_physics_process(false)
		push_error("Character talent transaction rollback failed closed")
	return false


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


func _character_profile_catalog_definition(profile_id: StringName) -> Dictionary:
	if profile_id == &"":
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		CHARACTER_PROFILE_CATALOG_PATH
	))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		if StringName(str(definition.get("id", ""))) == profile_id:
			return definition.duplicate(true)
	return {}


func _default_character_profile_definition(
	character_id: StringName,
	milestone: StringName
) -> Dictionary:
	if character_id != &"wanderer":
		return {}
	var normalized_milestone := str(milestone).strip_edges().to_upper()
	var profile_id := StringName()
	if normalized_milestone in ["M1", "CURRENT", "NEXT"]:
		profile_id = &"wanderer_m1_v1"
	elif normalized_milestone in ["LAUNCH", "EXPANSION"]:
		profile_id = &"wanderer_launch_v1"
	return _character_profile_catalog_definition(profile_id)


func _canonical_character_profile(source: Dictionary) -> Dictionary:
	if source.is_empty():
		return {}
	var profile = CharacterRuntimeProfileScript.new()
	var result: Dictionary = profile.configure(source.duplicate(true))
	var snapshot: Dictionary = (
		(result.get("profile", {}) as Dictionary).duplicate(true)
		if bool(result.get("ok", false)) and result.get("profile", {}) is Dictionary
		else {}
	)
	if snapshot.is_empty():
		return {}
	for field: String in ["availability", "tags", "references", "capabilities", "talent_ids"]:
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


func _character_profile_allows_milestone(config: Dictionary) -> bool:
	var profile_value: Variant = config.get("character_profile", {})
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
	var committed_plan: Dictionary = {}
	if weapon_action_coordinator != null:
		var coordinator_snapshot: Dictionary = weapon_action_coordinator.snapshot()
		var plan_value: Variant = coordinator_snapshot.get("plan", {})
		if plan_value is Dictionary:
			committed_plan = (plan_value as Dictionary).duplicate(true)
			_weapon_combo_timeout_frames = maxi(
				0,
				int((plan_value as Dictionary).get("combo_reset_frames", 0))
			)
		_settle_character_weapon_action(
			weapon_id,
			action_id,
			token,
			context,
			plan_value as Dictionary,
			coordinator_snapshot
		)
	_track_weapon_action_token(
		token,
		action_id,
		int(context.get("action_generation", 0)),
		context,
		committed_plan
	)
	_confirm_weapon_action_commit_mastery(weapon_id, action_id, token, context, committed_plan)
	SceneScope.event_bus(self).weapon_action_committed.emit(
		weapon_id,
		action_id,
		token,
		context.duplicate(true)
	)
	_sync_weapon_resource_facts(&"action_committed")


func _settle_character_weapon_action(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary,
	plan: Dictionary,
	coordinator_snapshot: Dictionary
) -> void:
	if (
		character_action_coordinator == null
		or not character_action_coordinator.has_method("on_weapon_action_committed")
		or token <= 0
		or weapon_id == &""
		or action_id == &""
	):
		return
	var action_generation := int(context.get(
		"action_generation",
		coordinator_snapshot.get("generation", 0)
	))
	if action_generation <= 0:
		return
	var character_before: Dictionary = character_action_coordinator.call("snapshot")
	var action_before: Dictionary = character_action_coordinator.call("action_snapshot")
	if character_before.is_empty() or action_before.is_empty():
		set_physics_process(false)
		push_error("Character weapon-action settlement could not capture rollback state")
		return
	var character_context := context.duplicate(true)
	character_context["runtime_frame"] = _runtime_frame
	character_context["run_id"] = _run_id
	character_context["run_revision"] = _owner_character_generation
	character_context["owner_character_generation"] = _owner_character_generation
	character_context["generation"] = action_generation
	character_context["action_token"] = token
	character_context["weapon_id"] = weapon_id
	character_context["action_id"] = action_id
	character_context["position"] = global_position
	character_context["plan"] = plan.duplicate(true)
	character_context["approved_payload_descriptors"] = (
		plan.get("payload_descriptors", plan.get(
			"approved_payload_descriptors",
			plan.get("payloads", [])
		)) as Array
	).duplicate(true)
	character_context["full_charge"] = bool(context.get("full_charge", false)) or (
		str(context.get("charge_tier", "")) == "full"
		or action_id in [&"charged_slash", &"primordial_edge", &"charged_heavy"]
	)
	var result_value: Variant = character_action_coordinator.call(
		"on_weapon_action_committed",
		character_context
	)
	if (
		not result_value is Dictionary
		or not bool((result_value as Dictionary).get("ok", false))
		or not _apply_character_result_events(result_value as Dictionary)
	):
		if not _restore_character_coordinator_pair(character_before, action_before):
			set_physics_process(false)
			push_error("Character weapon-action rollback failed closed")


func _track_weapon_action_token(
	token: int,
	action_id: StringName,
	generation: int,
	context: Dictionary = {},
	plan: Dictionary = {}
) -> void:
	if token <= 0 or action_id == &"" or generation <= 0:
		return
	if not _weapon_action_ids_by_token.has(token):
		_weapon_action_token_order.append(token)
	_weapon_action_ids_by_token[token] = action_id
	_weapon_action_generations_by_token[token] = generation
	_weapon_action_mastery_contexts_by_token[token] = _weapon_mastery_action_source_snapshot(
		context,
		plan
	)
	while _weapon_action_token_order.size() > MAX_TRACKED_WEAPON_FACT_TOKENS:
		var expired_token: int = int(_weapon_action_token_order.pop_front())
		_weapon_action_ids_by_token.erase(expired_token)
		_weapon_action_generations_by_token.erase(expired_token)
		_weapon_action_mastery_contexts_by_token.erase(expired_token)
		_weapon_hit_fact_claims.erase(expired_token)
		_weapon_mastery_target_ids_by_token.erase(expired_token)
		_clear_weapon_action_reward_claims(expired_token)


func _weapon_mastery_action_source_snapshot(
	context: Dictionary,
	plan: Dictionary
) -> Dictionary:
	var committed_context: Dictionary = {}
	for field: String in ["held_frames", "full_charge", "charge_tier"]:
		if context.has(field):
			committed_context[field] = context[field]
	var committed_plan: Dictionary = {}
	for field: String in ["held_frames", "ammo_cost", "time_load_active"]:
		if plan.has(field):
			committed_plan[field] = plan[field]
	var payloads_value: Variant = plan.get("payloads")
	if payloads_value is Array and not (payloads_value as Array).is_empty():
		var payload_value: Variant = (payloads_value as Array)[0]
		if payload_value is Dictionary:
			var parameters_value: Variant = (payload_value as Dictionary).get("parameters")
			if parameters_value is Dictionary and (parameters_value as Dictionary).has("full_charge"):
				committed_plan["payload_full_charge"] = (
					(parameters_value as Dictionary)["full_charge"]
				)
	return {
		"context": committed_context,
		"plan": committed_plan,
	}


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
	_queue_weapon_observation(&"hit", [&"gun", action_id, action_token, target.get_instance_id(), {"source": "gun_projectile", "scope": "action"}])
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
	if _weapon_resource_publication_enabled:
		SceneScope.event_bus(self).weapon_resource_changed.emit(
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
	if _weapon_resource_publication_enabled:
		SceneScope.event_bus(self).weapon_resource_changed.emit(
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


func set_weapon_resource_publication_enabled(enabled: bool) -> void:
	_weapon_resource_publication_enabled = enabled


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
	if _weapon_resource_publication_enabled:
		SceneScope.event_bus(self).weapon_resource_changed.emit(weapon_id, resource_id, current, maximum, reason)


func _on_staff_payload_result_reported(
	action_token: int,
	generation: int,
	result: Dictionary
) -> void:
	if loadout_runtime == null or not loadout_runtime.has_weapon(&"staff"):
		return
	_confirm_weapon_payload_mastery(&"staff", action_token, generation, result)
	_sync_weapon_resource_facts(&"payload_result")
	_record_weapon_replay_payload_result(action_token, generation, result)


func _on_gauntlets_payload_result_reported(
	action_token: int,
	generation: int,
	result: Dictionary
) -> void:
	if loadout_runtime == null or not loadout_runtime.has_weapon(&"gauntlets"):
		return
	_confirm_weapon_payload_mastery(&"gauntlets", action_token, generation, result)
	_record_weapon_replay_payload_result(action_token, generation, result)


func _confirm_weapon_action_commit_mastery(
	weapon_id: StringName,
	action_id: StringName,
	action_token: int,
	context: Dictionary,
	plan: Dictionary
) -> void:
	if (
		weapon_id == &"gun"
		and action_id == &"reload"
		and bool(context.get("perfect_reload", false))
	):
		_confirm_weapon_mastery(
			weapon_id,
			&"gun_perfect_reload",
			action_id,
			action_token,
			0,
			{"confirmed": true, "mastery_eligible": true},
			{
				"reload_frame": int(context.get("reload_frame", -1)),
				"plan": plan.duplicate(true),
			}
		)


func _confirm_live_weapon_intent_mastery(result: Dictionary) -> void:
	if loadout_runtime == null or not loadout_runtime.has_weapon(&"gun"):
		return
	var result_context := result.get("context", {}) as Dictionary
	if not bool(result_context.get("perfect_reload", false)):
		return
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.call("snapshot")
	var action_token := int(result.get("token", coordinator_snapshot.get("token", 0)))
	var plan := coordinator_snapshot.get("plan", {}) as Dictionary
	if action_token <= 0 or StringName(str(plan.get("action_id", ""))) != &"reload":
		return
	_confirm_weapon_mastery(
		&"gun",
		&"gun_perfect_reload",
		&"reload",
		action_token,
		0,
		{"confirmed": true, "mastery_eligible": true},
		{
			"reload_frame": int(result_context.get("reload_frame", -1)),
			"perfect_reload": true,
		}
	)


func _confirm_sword_guard_mastery(
	weapon_decision: Dictionary,
	resolution: RefCounted
) -> void:
	if (
		resolution == null
		or StringName(str(weapon_decision.get("guard_kind", ""))) != &"sword_perfect"
		or not bool(weapon_decision.get("prevented", false))
		or not bool(resolution.call("is_prevented"))
		or weapon_action_coordinator == null
	):
		return
	var coordinator_snapshot: Dictionary = weapon_action_coordinator.call("snapshot")
	var action_token := int(coordinator_snapshot.get("token", 0))
	var plan := coordinator_snapshot.get("plan", {}) as Dictionary
	var action_id := StringName(str(plan.get("action_id", "")))
	if action_token <= 0 or action_id not in [&"guard", &"sword_guard"]:
		return
	_confirm_weapon_mastery(
		&"sword",
		&"sword_perfect_guard",
		action_id,
		action_token,
		0,
		{"confirmed": true, "mastery_eligible": true},
		{
			"guard_kind": &"sword_perfect",
			"prevented": true,
			"blocked_damage": float((
				weapon_decision.get("commit_context", {}) as Dictionary
			).get("blocked_damage", 0.0)),
		}
	)


func _confirm_weapon_hit_mastery(
	damage_info: RefCounted,
	target: Node,
	final_amount: float,
	action_token: int,
	weapon_action_generation: int
) -> void:
	if not _weapon_action_ids_by_token.has(action_token):
		return
	var action_id := StringName(str(_weapon_action_ids_by_token[action_token]))
	var source := _weapon_action_mastery_context(action_token)
	var plan := source.get("plan", {}) as Dictionary
	var committed_context := source.get("context", {}) as Dictionary
	var tags: Array[String] = []
	for tag_value: Variant in damage_info.get("tags") as Array:
		tags.append(str(tag_value))
	var payload_result := {
		"confirmed": true,
		"hit_confirmed": true,
		"mastery_eligible": true,
		"is_echo": tags.has("non_recursive:echo") or tags.has("time:accelerate_echo"),
		"recursive_echo": tags.has("recursive_echo"),
		"tags": tags.duplicate(),
	}
	var target_id := _stable_weapon_mastery_target_id(target)
	if target_id <= 0:
		return
	var weapon_id := StringName(str(loadout_runtime.weapon_id())) if loadout_runtime != null else &""
	var mastery_id := StringName()
	var semantic_context := {
		"damage": final_amount,
		"weapon_action_generation": weapon_action_generation,
		"tags": tags.duplicate(),
	}
	match weapon_id:
		&"sword":
			if action_id == &"counter":
				mastery_id = &"sword_counter_confirmed"
			elif action_id == &"charged_slash" and (
				bool(committed_context.get("full_charge", false))
				or int(committed_context.get("held_frames", 0)) >= 30
				or int(plan.get("held_frames", 0)) >= 30
			):
				mastery_id = &"sword_charged_commitment"
		&"bow":
			var full_charge := (
				bool(committed_context.get("full_charge", false))
				or str(committed_context.get("charge_tier", "")) == "full"
				or bool(plan.get("payload_full_charge", false))
			)
			if not full_charge:
				return
			var target_count := _record_weapon_mastery_target(action_token, target_id)
			if _target_has_active_weakpoint(target, damage_info):
				mastery_id = &"bow_full_charge_weakpoint"
			elif target_count >= 2:
				mastery_id = &"bow_full_charge_penetration"
			semantic_context["distinct_target_count"] = target_count
		&"gun":
			var runtime_presentation := (
				weapon_runtime.call("presentation_snapshot") as Dictionary
				if weapon_runtime != null and weapon_runtime.has_method("presentation_snapshot")
				else {}
			)
			if (
				action_id in [&"normal_fire", &"aimed_fire"]
				and int(plan.get("ammo_cost", 0)) > 0
				and not bool(plan.get("time_load_active", false))
				and int(runtime_presentation.get("ammo", -1)) == 0
			):
				mastery_id = &"gun_magazine_finisher"
				semantic_context["ammo_after_commit"] = 0
	if mastery_id == &"":
		return
	_confirm_weapon_mastery(
		weapon_id,
		mastery_id,
		action_id,
		action_token,
		target_id,
		payload_result,
		semantic_context
	)


func _confirm_weapon_payload_mastery(
	weapon_id: StringName,
	action_token: int,
	payload_generation: int,
	result: Dictionary
) -> void:
	if (
		action_token <= 0
		or not _weapon_action_ids_by_token.has(action_token)
		or int(_weapon_action_generations_by_token.get(action_token, 0)) <= 0
		or bool(result.get("is_echo", false))
		or bool(result.get("recursive_echo", false))
		or not bool(result.get("hit_confirmed", result.get("hit", false)))
	):
		return
	var action_id := StringName(str(_weapon_action_ids_by_token[action_token]))
	var target_id := int(result.get("target_id", 0))
	if target_id <= 0:
		return
	var mastery_id := StringName()
	var semantic_context := {
		"payload_generation": payload_generation,
		"outcome_id": str(result.get("outcome_id", "")),
	}
	match weapon_id:
		&"staff":
			var combination_value: Variant = result.get("combination", {})
			if combination_value is Dictionary and not (combination_value as Dictionary).is_empty():
				mastery_id = &"staff_ordered_combination"
				semantic_context["combo_id"] = str((combination_value as Dictionary).get("combo_id", ""))
			elif action_id == &"planar_collapse" and _record_weapon_mastery_target(
				action_token,
				target_id
			) >= 3:
				mastery_id = &"staff_controlled_zone"
				semantic_context["distinct_target_count"] = 3
		&"gauntlets":
			if action_id == &"dodge_counter":
				mastery_id = &"gauntlets_dodge_counter"
			elif action_id == &"punch_5":
				mastery_id = &"gauntlets_chain_finisher"
			else:
				var combo_gain := int(result.get("combo_gain", 0))
				var runtime_snapshot := (
					weapon_runtime.call("snapshot") as Dictionary
					if weapon_runtime != null and weapon_runtime.has_method("snapshot")
					else {}
				)
				var combo_state := runtime_snapshot.get("combo_state", {}) as Dictionary
				var combo_after := int(combo_state.get("combo_count", 0))
				var combo_before := maxi(0, combo_after - maxi(0, combo_gain))
				var threshold := 30 if combo_before < 30 and combo_after >= 30 else (
					15 if combo_before < 15 and combo_after >= 15 else 0
				)
				if threshold > 0:
					mastery_id = &"gauntlets_combo_threshold"
					semantic_context["threshold"] = threshold
					semantic_context["combo_before"] = combo_before
					semantic_context["combo_after"] = combo_after
	if mastery_id == &"":
		return
	_confirm_weapon_mastery(
		weapon_id,
		mastery_id,
		action_id,
		action_token,
		target_id,
		result,
		semantic_context
	)


func _confirm_weapon_mastery(
	weapon_id: StringName,
	mastery_id: StringName,
	action_id: StringName,
	action_token: int,
	target_id: int,
	payload_result: Dictionary,
	semantic_context: Dictionary
) -> bool:
	if (
		weapon_runtime == null
		or loadout_runtime == null
		or loadout_runtime.weapon_id() != weapon_id
		or not weapon_runtime.has_method("build_mastery_fact")
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("prepare_weapon_mastery")
		or not character_action_coordinator.has_method("settle_prepared_weapon_mastery")
		or not character_action_coordinator.has_method("abort_prepared_weapon_mastery")
	):
		return false
	var fact_context := _weapon_mastery_context(action_token, semantic_context)
	var fact_value: Variant = weapon_runtime.call(
		"build_mastery_fact",
		mastery_id,
		action_id,
		int(character_action_coordinator.call("generation")),
		action_token,
		target_id,
		payload_result.duplicate(true),
		fact_context
	)
	if not fact_value is Dictionary or (fact_value as Dictionary).is_empty():
		return false
	return _settle_weapon_mastery_fact(fact_value as Dictionary)


func _settle_weapon_mastery_fact(fact: Dictionary) -> bool:
	var external_before := _weapon_mastery_external_snapshot()
	if external_before.is_empty():
		return false
	var prepared: Dictionary = character_action_coordinator.call(
		"prepare_weapon_mastery",
		fact.duplicate(true)
	)
	if not bool(prepared.get("ok", false)):
		_discard_weapon_mastery_external_snapshot(external_before)
		return false
	var ticket_value: Variant = (prepared.get("context", {}) as Dictionary).get("ticket", {})
	if not ticket_value is Dictionary:
		_restore_weapon_mastery_external_snapshot(external_before)
		return false
	var ticket := (ticket_value as Dictionary).duplicate(true)
	if not _apply_prepared_weapon_mastery_events(prepared.get("events", []) as Array):
		var external_restored := _restore_weapon_mastery_external_snapshot(external_before)
		var aborted := bool((character_action_coordinator.call(
			"abort_prepared_weapon_mastery",
			ticket
		) as Dictionary).get("ok", false))
		if not external_restored or not aborted:
			set_physics_process(false)
			push_error("Weapon mastery external-event rollback failed closed")
		return false
	var settled: Dictionary = character_action_coordinator.call(
		"settle_prepared_weapon_mastery",
		ticket,
		Callable(self, "_observe_weapon_mastery")
	)
	if bool(settled.get("ok", false)):
		return _discard_weapon_mastery_external_snapshot(external_before)
	var external_restored := _restore_weapon_mastery_external_snapshot(external_before)
	var aborted := bool((character_action_coordinator.call(
		"abort_prepared_weapon_mastery",
		ticket
	) as Dictionary).get("ok", false))
	if not external_restored or not aborted:
		set_physics_process(false)
		push_error("Weapon mastery settlement rollback failed closed")
	return false


func _apply_prepared_weapon_mastery_events(events: Array) -> bool:
	var boss_events: Array[Dictionary] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			return false
		var event := event_value as Dictionary
		if StringName(str(event.get("event_id", ""))) == &"boss_exposure_extension_requested":
			boss_events.append(event.duplicate(true))
		elif not _apply_character_event(event):
			return false
	for event: Dictionary in boss_events:
		if not _apply_character_event(event):
			return false
	return true


func _weapon_mastery_external_snapshot() -> Dictionary:
	if (
		time_manager == null
		or not time_manager.has_method("replay_snapshot")
		or health == null
		or not health.has_method("transaction_snapshot")
		or world_payload_authority == null
		or not world_payload_authority.has_method("replay_snapshot")
	):
		return {}
	var time_value: Variant = time_manager.call("replay_snapshot")
	var health_value: Variant = health.call("transaction_snapshot")
	var world_value: Variant = world_payload_authority.call("replay_snapshot")
	if not time_value is Dictionary or not health_value is Dictionary or not world_value is Dictionary:
		return {}
	var boss_snapshots: Array[Dictionary] = []
	if get_tree() != null:
		for boss: Node in SceneScope.nodes_in_group(self, "bosses"):
			if (
				is_instance_valid(boss)
				and boss.has_method("character_boss_exposure_snapshot")
				and boss.has_method("restore_character_boss_exposure_snapshot")
			):
				var exposure_value: Variant = boss.call("character_boss_exposure_snapshot")
				if exposure_value is Dictionary:
					boss_snapshots.append({
						"node": boss,
						"snapshot": (exposure_value as Dictionary).duplicate(true),
					})
	return {
		"position": global_position,
		"time": (time_value as Dictionary).duplicate(true),
		"health": (health_value as Dictionary).duplicate(true),
		"world": (world_value as Dictionary).duplicate(true),
		"bosses": boss_snapshots,
	}


func _restore_weapon_mastery_external_snapshot(value: Dictionary) -> bool:
	var boss_ok := true
	for boss_value: Variant in value.get("bosses", []) as Array:
		if not boss_value is Dictionary:
			boss_ok = false
			continue
		var boss_entry := boss_value as Dictionary
		var boss_value_node: Variant = boss_entry.get("node")
		if (
			not boss_value_node is Node
			or not is_instance_valid(boss_value_node)
			or not bool((boss_value_node as Node).call(
				"restore_character_boss_exposure_snapshot",
				(boss_entry.get("snapshot", {}) as Dictionary).duplicate(true)
			))
		):
			boss_ok = false
	var world_ok := bool(world_payload_authority.call(
		"restore_replay_snapshot",
		(value.get("world", {}) as Dictionary).duplicate(true)
	))
	var time_ok := bool(time_manager.call(
		"restore_replay_snapshot",
		(value.get("time", {}) as Dictionary).duplicate(true)
	))
	var health_ok := bool(health.call(
		"restore_transaction_snapshot",
		(value.get("health", {}) as Dictionary).duplicate(true)
	))
	global_position = value.get("position", global_position)
	return boss_ok and world_ok and time_ok and health_ok and global_position == value.get("position")


func _discard_weapon_mastery_external_snapshot(value: Dictionary) -> bool:
	return bool(health.call(
		"discard_transaction_snapshot",
		(value.get("health", {}) as Dictionary).duplicate(true)
	))


func _weapon_mastery_context(action_token: int, semantic_context: Dictionary) -> Dictionary:
	var action_source := _weapon_action_mastery_context(action_token)
	var committed_context := action_source.get("context", {}) as Dictionary
	var result := {
		"runtime_frame": _runtime_frame,
		"run_id": _run_id,
		"run_revision": _owner_character_generation,
		"owner_character_generation": _owner_character_generation,
		"maximum_hp": float(health.max_hp) if health != null else 0.0,
		"position": global_position,
		"attack": get_effective_attack(),
		"aim_direction": _last_weapon_aim_direction,
		"weapon_action_generation": int(_weapon_action_generations_by_token.get(action_token, 0)),
		"tags": (semantic_context.get("tags", []) as Array).duplicate(true),
	}
	for key: Variant in semantic_context.keys():
		result[key] = semantic_context[key]
	for field: String in ["held_frames", "full_charge", "charge_tier"]:
		if committed_context.has(field) and not result.has(field):
			result[field] = committed_context[field]
	return result


func _weapon_action_mastery_context(action_token: int) -> Dictionary:
	var value: Variant = _weapon_action_mastery_contexts_by_token.get(action_token, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _record_weapon_mastery_target(action_token: int, target_id: int) -> int:
	if action_token <= 0 or target_id <= 0:
		return 0
	var targets: Array = (
		_weapon_mastery_target_ids_by_token.get(action_token, []) as Array
	).duplicate()
	if not targets.has(target_id):
		targets.append(target_id)
		targets.sort()
	_weapon_mastery_target_ids_by_token[action_token] = targets
	return targets.size()


func _stable_weapon_mastery_target_id(target: Node) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	if target.has_meta("stable_target_id"):
		var stable_id := int(target.get_meta("stable_target_id"))
		return stable_id if stable_id > 0 else 0
	for key: StringName in [&"stable_target_key", &"encounter_spawn_id", &"spawn_id"]:
		if target.has_meta(key):
			var stable_key := str(target.get_meta(key)).strip_edges()
			if not stable_key.is_empty():
				return maxi(1, stable_key.hash())
	return 0


func _target_has_active_weakpoint(target: Node, damage_info: RefCounted) -> bool:
	var observation := _published_damage_observation_context(damage_info, target)
	if observation.has("weakpoint_active"):
		return bool(observation["weakpoint_active"])
	if target.has_meta("weakpoint_active") and bool(target.get_meta("weakpoint_active")):
		return true
	if target.has_method("get_weakpoint_damage_bonus"):
		var bonus_value: Variant = target.call("get_weakpoint_damage_bonus", damage_info)
		return (
			typeof(bonus_value) in [TYPE_INT, TYPE_FLOAT]
			and is_finite(float(bonus_value))
			and float(bonus_value) > 0.0
		)
	return false


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


func stage_frame_damage_observation(damage_info: RefCounted, target: Node, final_amount: float) -> bool:
	if _active_time_frame_signal_ticket.is_empty() or _active_world_frame_ticket.is_empty() or damage_info == null or target == null or not is_instance_valid(target) or damage_info.get("attacker") != self:
		return false
	var observation := _published_damage_observation_context(damage_info, target)
	if observation.is_empty() or bool(observation.get("internal_observation_recorded", false)):
		return false
	_refresh_weapon_replay_fact_baseline()
	_on_weapon_replay_hit_confirmed(damage_info, target, final_amount)
	return true


func _published_damage_observation_context(damage_info: RefCounted, target: Node) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	var target_health := target.get_node_or_null("HealthComponent")
	if target_health == null and target.has_method("published_damage_observation_context"):
		target_health = target
	if target_health == null or not target_health.has_method("published_damage_observation_context"):
		return {}
	var value: Variant = target_health.call("published_damage_observation_context", damage_info)
	return value.duplicate(true) if value is Dictionary else {}


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
	var observation := _published_damage_observation_context(damage_info as RefCounted, target)
	if bool(observation.get("internal_observation_recorded", false)):
		return
	var damage_tags_value: Variant = (damage_info as RefCounted).get("tags")
	if damage_tags_value is Array:
		for tag_value: Variant in damage_tags_value as Array:
			if str(tag_value) in [
				"character_owned",
				"character_echo",
				"world_owned",
				"no_character_facts",
			]:
				return
	var identity := _weapon_replay_damage_identity(damage_info as RefCounted)
	var action_token := int(identity.get("token", 0))
	var generation := int(identity.get("generation", 0))
	if action_token <= 0 or generation <= 0:
		return
	_confirm_weapon_hit_mastery(
		damage_info as RefCounted,
		target,
		final_amount,
		action_token,
		generation
	)
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
	var hp_after := float(observation.get("hp_after", health.get("current_hp")))
	var hp_before := float(observation.get("hp_before", hp_after + final_amount))
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
			"target_dead_after": bool(observation.get("target_dead_after", health.get("dead"))),
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
	_queue_weapon_observation(&"hit", [&"gauntlets", action_id, action_token, target_id, context])


func _observe_weapon_mastery(fact: Dictionary) -> void:
	_queue_weapon_observation(&"mastery", [
		StringName(fact.weapon_id), StringName(fact.mastery_family),
		StringName(fact.mastery_id), StringName(fact.action_id),
		int(fact.action_token), int(fact.generation), int(fact.target_id),
		(fact.context as Dictionary).duplicate(true),
	])


func _queue_weapon_observation(kind: StringName, arguments: Array) -> void:
	var observation := {"kind": kind, "arguments": arguments.duplicate(true)}
	if not _active_world_frame_ticket.is_empty():
		_fixed_frame_weapon_observations.append(observation)
	else:
		_flush_weapon_observation(observation)


func _flush_weapon_observation(observation: Dictionary) -> void:
	var arguments := observation.arguments as Array
	if observation.kind == &"mastery":
		SceneScope.event_bus(self).weapon_mastery_confirmed.emit(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7])
	elif observation.kind == &"hit":
		SceneScope.event_bus(self).weapon_hit_confirmed.emit(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4])


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
				SceneScope.event_bus(self).weapon_cue_requested.emit(
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
	var context := {
		"attack": get_effective_attack(),
		"equipped_time_abilities": (
			loadout_runtime.time_ability_ids()
			if loadout_runtime != null and loadout_runtime.has_method("time_ability_ids")
			else []
		),
	}
	match time_manager.canonical_skill_id(skill_id):
		&"rewind":
			context["recorder"] = rewind_recorder
		&"rift":
			context["position"] = global_position
	return context


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
	var context := {
		"aim_direction": aim_direction,
		"target_point": global_position + aim_direction * BOW_TARGET_DISTANCE_PIXELS,
		"facing": _last_move_direction,
		"runtime_frame": _runtime_frame,
		"run_id": _run_id,
		"run_revision": _owner_character_generation,
		"owner_character_generation": _owner_character_generation,
		"position": global_position,
		"run_seed": loadout_runtime.run_seed() if loadout_runtime != null else 0,
		"dash_completion_token": _dash_completion_token,
		"frames_since_dash_completion": frames_since_dash_completion,
		"dash_direction": _dash_direction,
		"time_interactions": weapon_time_interaction_context(),
	}
	var forgiveness := _character_forgiveness_descriptor_for_weapon(
		loadout_runtime.weapon_id() if loadout_runtime != null else &""
	)
	if not forgiveness.is_empty():
		context["character_forgiveness"] = forgiveness
	return context


func _character_forgiveness_descriptor_for_weapon(weapon_id: StringName) -> Dictionary:
	if (
		weapon_id == &""
		or character_runtime == null
		or not character_runtime.has_method("snapshot")
	):
		return {}
	var runtime_value: Variant = character_runtime.call("snapshot")
	if not runtime_value is Dictionary:
		return {}
	var strategy_value: Variant = (runtime_value as Dictionary).get("strategy")
	if not strategy_value is Dictionary:
		return {}
	var strategy := strategy_value as Dictionary
	var descriptor_value: Variant = strategy.get("forgiveness_descriptor")
	if (
		not descriptor_value is Dictionary
		or int(strategy.get("forgiveness_expires_frame", -1)) <= _runtime_frame
	):
		return {}
	var descriptor := descriptor_value as Dictionary
	if StringName(str(descriptor.get("weapon_id", ""))) != weapon_id:
		return {}
	return descriptor.duplicate(true)


func _clear_owned_player_arrows() -> void:
	if bow_weapon == null:
		return
	for arrow: Node in SceneScope.nodes_in_group(self, "player_arrows"):
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
	for projectile: Node in SceneScope.nodes_in_group(self, "player_projectiles"):
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


func equip_active_item(definition: Dictionary, replace_existing: bool = false) -> Dictionary:
	if active_item_runtime == null or not active_item_runtime.has_method("configure"):
		return {"ok": false, "code": &"RUNTIME_UNAVAILABLE", "context": {}}
	var current: Dictionary = active_item_runtime.call("snapshot")
	if bool(current.get("configured", false)) and not replace_existing:
		return {
			"ok": false,
			"code": &"REPLACEMENT_REQUIRED",
			"context": {
				"equipped_content_id": str((current.get("definition", {}) as Dictionary).get("id", "")),
				"offered_content_id": str(definition.get("id", "")),
			},
		}
	var candidate: RefCounted = ActiveItemRuntimeScript.new()
	if not bool(candidate.call("configure", definition.duplicate(true))):
		return {"ok": false, "code": &"INVALID_DEFINITION", "context": {}}
	var previous_content_id := str((current.get("definition", {}) as Dictionary).get("id", ""))
	active_item_runtime = candidate
	_active_item_last_activation.clear()
	_active_item_last_events.clear()
	return {
		"ok": true,
		"code": &"REPLACED" if not previous_content_id.is_empty() else &"OK",
		"content_id": str(definition.get("id", "")),
		"previous_content_id": previous_content_id,
		"context": {},
	}


func active_item_snapshot() -> Dictionary:
	if active_item_runtime == null or not active_item_runtime.has_method("snapshot"):
		return {}
	return (active_item_runtime.call("snapshot") as Dictionary).duplicate(true)


func active_item_presentation_snapshot() -> Dictionary:
	var snapshot := active_item_snapshot()
	var configured := bool(snapshot.get("configured", false))
	if not configured:
		return {
			"equipped": false,
			"content_id": "",
			"name_key": "",
			"icon_id": "",
			"archetype": "",
			"cooldown_remaining_frames": 0,
			"cooldown_max_frames": 0,
			"ready": false,
			"generation": int(snapshot.get("generation", 0)),
			"next_token": int(snapshot.get("next_token", 1)),
		}
	var definition := snapshot.get("definition", {}) as Dictionary
	var content_id := str(definition.get("id", ""))
	var cooldown_remaining := int(active_item_runtime.call("cooldown_remaining"))
	return {
		"equipped": true,
		"content_id": content_id,
		"name_key": "%s_NAME" % content_id.to_upper(),
		"icon_id": "content_%s" % content_id,
		"archetype": str(definition.get("archetype", "")),
		"cooldown_remaining_frames": cooldown_remaining,
		"cooldown_max_frames": int(definition.get("cooldown_frames", 0)),
		"ready": cooldown_remaining <= 0,
		"generation": int(snapshot.get("generation", 0)),
		"next_token": int(snapshot.get("next_token", 1)),
	}


func activate_equipped_active_item(context_override: Dictionary = {}) -> Dictionary:
	if (
		active_item_runtime == null
		or not active_item_runtime.has_method("plan_activate")
		or not active_item_runtime.has_method("commit_activate")
		or time_manager == null
		or health == null
	):
		return {"ok": false, "code": &"RUNTIME_UNAVAILABLE", "context": {}}
	var context := {
		"runtime_frame": _runtime_frame,
		"energy_current": float(time_manager.get("energy")),
		"health_current": float(health.get("current_hp")),
		"health_maximum": float(health.get("max_hp")),
		"is_boss_target": _active_item_has_boss_target(),
	}
	if context_override.has("is_boss_target"):
		context["is_boss_target"] = bool(context_override["is_boss_target"])
	var prepared_value: Variant = active_item_runtime.call("plan_activate", context)
	var prepared := (prepared_value as Dictionary) if prepared_value is Dictionary else {}
	if not bool(prepared.get("ok", false)):
		_present_active_item_feedback(prepared, false)
		return prepared.duplicate(true)
	var plan := (prepared.get("plan", {}) as Dictionary).duplicate(true)
	var runtime_before := active_item_snapshot()
	var health_before: Dictionary = health.call("reward_effect_snapshot")
	var time_before: Dictionary = time_manager.call("resource_state", &"time_energy")
	var committed_value: Variant = active_item_runtime.call(
		"commit_activate",
		plan.duplicate(true),
		int(plan.get("token", 0))
	)
	var committed := (committed_value as Dictionary) if committed_value is Dictionary else {}
	if not bool(committed.get("ok", false)):
		_present_active_item_feedback(committed, false)
		return committed.duplicate(true)
	var claims := committed.get("resource_claims", {}) as Dictionary
	var settlement := _settle_active_item_claims(claims, time_before, health_before)
	if not bool(settlement.get("ok", false)):
		if not bool(active_item_runtime.call("restore_snapshot", runtime_before)):
			set_physics_process(false)
			var rollback_failure := {"ok": false, "code": &"ROLLBACK_FAILED", "context": settlement}
			_present_active_item_feedback(rollback_failure, false)
			return rollback_failure
		_present_active_item_feedback(settlement, false)
		return settlement
	var definition := runtime_before.get("definition", {}) as Dictionary
	var result := committed.duplicate(true)
	result["content_id"] = str(definition.get("id", ""))
	result["handler_id"] = str(definition.get("active_handler_id", ""))
	result["runtime_frame"] = _runtime_frame
	_active_item_last_activation = result.duplicate(true)
	_present_active_item_feedback(result, true)
	return result


func _present_active_item_feedback(result: Dictionary, accepted: bool) -> void:
	if not CombatFeedback.has_method("present_active_item_result"):
		return
	var snapshot := active_item_snapshot()
	var definition_value: Variant = snapshot.get("definition", {})
	if not definition_value is Dictionary:
		return
	var definition := definition_value as Dictionary
	var content_id := StringName(str(definition.get("id", "")))
	var handler_id := StringName(str(definition.get("active_handler_id", "")))
	if content_id == &"" or handler_id == &"":
		return
	CombatFeedback.call(
		"present_active_item_result",
		self,
		content_id,
		handler_id,
		accepted,
		&"" if accepted else StringName(str(result.get("code", "rejected")).to_lower())
	)


func _settle_active_item_claims(
	claims: Dictionary,
	time_before: Dictionary,
	health_before: Dictionary
) -> Dictionary:
	if claims.has("time_energy"):
		var spent_value: Variant = time_manager.call(
			"try_spend_resource",
			&"time_energy",
			float(claims["time_energy"]),
			int(time_before.get("revision", 0)),
			&"active_item"
		)
		if not spent_value is Dictionary or not bool((spent_value as Dictionary).get("ok", false)):
			return (
				(spent_value as Dictionary).duplicate(true)
				if spent_value is Dictionary
				else {"ok": false, "code": &"RESOURCE_COMMIT_FAILED", "context": {}}
			)
	if claims.has("health"):
		var expected_loss := float(claims["health"])
		var actual_loss := float(health.call("lose_health", expected_loss, self))
		if not is_equal_approx(actual_loss, expected_loss) or not bool(health.call("is_alive")):
			var restored := bool(health.call(
				"restore_reward_effect_snapshot",
				health_before.duplicate(true)
			))
			return {
				"ok": false,
				"code": &"RESOURCE_COMMIT_FAILED" if restored else &"ROLLBACK_FAILED",
				"context": {"resource_id": "health"},
			}
	return {"ok": true, "code": &"OK", "context": {}}


func _active_item_has_boss_target() -> bool:
	if not is_inside_tree():
		return false
	for candidate: Node in SceneScope.nodes_in_group(self, "bosses"):
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			return true
	return false


func apply_reward(reward_data: Dictionary) -> Dictionary:
	return _apply_effects(reward_data, "")


func apply_curse(curse_data: Dictionary) -> Dictionary:
	return _apply_effects(curse_data, "curse")


func reward_effect_begin_publication() -> bool:
	if (
		_reward_effect_publication_active
		or _reward_effect_publication_in_progress
		or health == null
		or not health.has_method("publish_reward_healed")
		or time_manager == null
		or not time_manager.has_method("publish_reward_energy_changed")
	):
		return false
	_reward_effect_publication_active = true
	_reward_effect_pending_health_signal.clear()
	_reward_effect_pending_time_signal.clear()
	return true


func reward_effect_publication_can_commit() -> bool:
	if not _reward_effect_publication_active or _reward_effect_publication_in_progress:
		return false
	if not _reward_effect_pending_health_signal.is_empty():
		var healed_amount := float(_reward_effect_pending_health_signal.get("amount", -1.0))
		var resulting_hp := float(_reward_effect_pending_health_signal.get("current_hp", -1.0))
		if (
			not is_finite(healed_amount)
			or healed_amount <= 0.0
			or not is_finite(resulting_hp)
			or resulting_hp < 0.0
			or resulting_hp > float(health.get("max_hp"))
		):
			return false
	if not _reward_effect_pending_time_signal.is_empty():
		var current := float(_reward_effect_pending_time_signal.get("current", -1.0))
		var maximum := float(_reward_effect_pending_time_signal.get("maximum", -1.0))
		if (
			not is_finite(current)
			or not is_finite(maximum)
			or maximum <= 0.0
			or current < 0.0
			or current > maximum
		):
			return false
	return true


func reward_effect_commit_publication() -> bool:
	if not reward_effect_publication_can_commit():
		return false
	var health_signal := _reward_effect_pending_health_signal.duplicate(true)
	var time_signal := _reward_effect_pending_time_signal.duplicate(true)
	_reward_effect_publication_in_progress = true
	_reward_effect_pending_health_signal.clear()
	_reward_effect_pending_time_signal.clear()
	var time_ok := true
	if (
		not time_signal.is_empty()
	):
		time_ok = bool(time_manager.call(
			"publish_reward_energy_changed",
			float(time_signal["current"]),
			float(time_signal["maximum"])
		))
	var health_ok := true
	if (
		not health_signal.is_empty()
	):
		health_ok = bool(health.call(
			"publish_reward_healed",
			float(health_signal["amount"]),
			float(health_signal["current_hp"])
		))
	_reward_effect_publication_active = false
	_reward_effect_publication_in_progress = false
	return time_ok and health_ok


func reward_effect_rollback_publication() -> bool:
	if not _reward_effect_publication_active or _reward_effect_publication_in_progress:
		return false
	_reward_effect_publication_active = false
	_reward_effect_pending_health_signal.clear()
	_reward_effect_pending_time_signal.clear()
	return true


func prepare_nonlethal_health_cost(
	transaction_id: String,
	cost: int,
	frozen_snapshot: Dictionary
) -> Dictionary:
	if not _valid_nonlethal_health_transaction_id(transaction_id):
		return _nonlethal_health_failure(&"HEALTH_COST_TRANSACTION_INVALID")
	if (
		_pending_nonlethal_health_costs.has(transaction_id)
		or _committed_nonlethal_health_costs.has(transaction_id)
	):
		return _nonlethal_health_failure(&"HEALTH_COST_DUPLICATE")
	if cost <= 0:
		return _nonlethal_health_failure(&"HEALTH_COST_INVALID")
	var current := reward_effect_snapshot()
	if (
		current.is_empty()
		or current != frozen_snapshot
		or not can_restore_reward_effect_snapshot(frozen_snapshot.duplicate(true))
	):
		return _nonlethal_health_failure(&"HEALTH_COST_STALE")
	var health_value: Variant = frozen_snapshot.get("health")
	if not health_value is Dictionary:
		return _nonlethal_health_failure(&"HEALTH_COST_SNAPSHOT_INVALID")
	var health_snapshot := health_value as Dictionary
	var current_hp_value: Variant = health_snapshot.get("current_hp")
	if (
		typeof(current_hp_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(current_hp_value))
		or float(current_hp_value) - float(cost) < 1.0
	):
		return _nonlethal_health_failure(&"HEALTH_COST_LETHAL")
	var after := frozen_snapshot.duplicate(true)
	var after_health := after["health"] as Dictionary
	after_health["current_hp"] = float(current_hp_value) - float(cost)
	after_health["dead"] = false
	if not can_restore_reward_effect_snapshot(after.duplicate(true)):
		return _nonlethal_health_failure(&"HEALTH_COST_SNAPSHOT_INVALID")
	var unsigned_ticket := {
		"schema_id": NONLETHAL_HEALTH_TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"cost": cost,
		"before_snapshot": frozen_snapshot.duplicate(true),
		"after_snapshot": after.duplicate(true),
	}
	var ticket := unsigned_ticket.duplicate(true)
	ticket["fingerprint"] = _merchant_participant_digest(unsigned_ticket)
	_pending_nonlethal_health_costs[transaction_id] = ticket.duplicate(true)
	return _nonlethal_health_success({"ticket": ticket.duplicate(true)})


func commit_nonlethal_health_cost(ticket: Dictionary) -> Dictionary:
	if not _valid_nonlethal_health_ticket(ticket):
		return _nonlethal_health_failure(&"HEALTH_COST_TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _committed_nonlethal_health_costs.has(transaction_id):
		return _nonlethal_health_failure(&"HEALTH_COST_DUPLICATE")
	if (
		not _pending_nonlethal_health_costs.has(transaction_id)
		or _pending_nonlethal_health_costs[transaction_id] != ticket
	):
		return _nonlethal_health_failure(&"HEALTH_COST_TICKET_STALE")
	var before := ticket["before_snapshot"] as Dictionary
	if reward_effect_snapshot() != before:
		return _nonlethal_health_failure(&"HEALTH_COST_STALE")
	var after := ticket["after_snapshot"] as Dictionary
	if (
		not restore_reward_effect_snapshot(after.duplicate(true), false)
		or reward_effect_snapshot() != after
	):
		if reward_effect_snapshot() != before:
			restore_reward_effect_snapshot(before.duplicate(true), false)
		return _nonlethal_health_failure(&"HEALTH_COST_APPLY_FAILED")
	var unsigned_receipt := {
		"schema_id": NONLETHAL_HEALTH_RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"cost": int(ticket["cost"]),
		"before_snapshot": before.duplicate(true),
		"after_snapshot": after.duplicate(true),
		"ticket_fingerprint": str(ticket["fingerprint"]),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["fingerprint"] = _merchant_participant_digest(unsigned_receipt)
	_pending_nonlethal_health_costs.erase(transaction_id)
	_committed_nonlethal_health_costs[transaction_id] = receipt.duplicate(true)
	return _nonlethal_health_success({"receipt": receipt.duplicate(true)})


func rollback_nonlethal_health_cost(receipt_or_ticket: Dictionary) -> Dictionary:
	if _valid_nonlethal_health_ticket(receipt_or_ticket):
		var pending_id := str(receipt_or_ticket["transaction_id"])
		if (
			not _pending_nonlethal_health_costs.has(pending_id)
			or _pending_nonlethal_health_costs[pending_id] != receipt_or_ticket
			or reward_effect_snapshot() != receipt_or_ticket["before_snapshot"]
		):
			return _nonlethal_health_failure(&"HEALTH_COST_TICKET_STALE")
		_pending_nonlethal_health_costs.erase(pending_id)
		return _nonlethal_health_success({
			"transaction_id": pending_id,
			"rolled_back": "pending",
		})
	if not _valid_nonlethal_health_receipt(receipt_or_ticket):
		return _nonlethal_health_failure(&"HEALTH_COST_RECEIPT_INVALID")
	var transaction_id := str(receipt_or_ticket["transaction_id"])
	if (
		not _committed_nonlethal_health_costs.has(transaction_id)
		or _committed_nonlethal_health_costs[transaction_id] != receipt_or_ticket
		or reward_effect_snapshot() != receipt_or_ticket["after_snapshot"]
	):
		return _nonlethal_health_failure(&"HEALTH_COST_RECEIPT_STALE")
	var before := receipt_or_ticket["before_snapshot"] as Dictionary
	if (
		not restore_reward_effect_snapshot(before.duplicate(true), false)
		or reward_effect_snapshot() != before
	):
		return _nonlethal_health_failure(&"HEALTH_COST_ROLLBACK_FAILED")
	_committed_nonlethal_health_costs.erase(transaction_id)
	return _nonlethal_health_success({
		"transaction_id": transaction_id,
		"rolled_back": "committed",
	})


func _valid_nonlethal_health_ticket(ticket: Dictionary) -> bool:
	if not _dictionary_has_exact_fields(ticket, NONLETHAL_HEALTH_TICKET_FIELDS):
		return false
	if (
		typeof(ticket["schema_id"]) != TYPE_STRING
		or str(ticket["schema_id"]) != NONLETHAL_HEALTH_TICKET_SCHEMA_ID
		or typeof(ticket["owner_instance_id"]) != TYPE_INT
		or int(ticket["owner_instance_id"]) != get_instance_id()
		or typeof(ticket["transaction_id"]) != TYPE_STRING
		or not _valid_nonlethal_health_transaction_id(str(ticket["transaction_id"]))
		or typeof(ticket["cost"]) != TYPE_INT
		or int(ticket["cost"]) <= 0
		or not ticket["before_snapshot"] is Dictionary
		or not ticket["after_snapshot"] is Dictionary
		or typeof(ticket["fingerprint"]) != TYPE_STRING
	):
		return false
	var before := ticket["before_snapshot"] as Dictionary
	var after := ticket["after_snapshot"] as Dictionary
	if (
		not can_restore_reward_effect_snapshot(before.duplicate(true))
		or not can_restore_reward_effect_snapshot(after.duplicate(true))
		or not _nonlethal_health_transition_matches(before, after, int(ticket["cost"]))
	):
		return false
	var unsigned := ticket.duplicate(true)
	unsigned.erase("fingerprint")
	return str(ticket["fingerprint"]) == _merchant_participant_digest(unsigned)


func _valid_nonlethal_health_receipt(receipt: Dictionary) -> bool:
	if not _dictionary_has_exact_fields(receipt, NONLETHAL_HEALTH_RECEIPT_FIELDS):
		return false
	if (
		typeof(receipt["schema_id"]) != TYPE_STRING
		or str(receipt["schema_id"]) != NONLETHAL_HEALTH_RECEIPT_SCHEMA_ID
		or typeof(receipt["owner_instance_id"]) != TYPE_INT
		or int(receipt["owner_instance_id"]) != get_instance_id()
		or typeof(receipt["transaction_id"]) != TYPE_STRING
		or not _valid_nonlethal_health_transaction_id(str(receipt["transaction_id"]))
		or typeof(receipt["cost"]) != TYPE_INT
		or int(receipt["cost"]) <= 0
		or not receipt["before_snapshot"] is Dictionary
		or not receipt["after_snapshot"] is Dictionary
		or typeof(receipt["ticket_fingerprint"]) != TYPE_STRING
		or str(receipt["ticket_fingerprint"]).is_empty()
		or typeof(receipt["fingerprint"]) != TYPE_STRING
		or not _nonlethal_health_transition_matches(
			receipt["before_snapshot"] as Dictionary,
			receipt["after_snapshot"] as Dictionary,
			int(receipt["cost"])
		)
	):
		return false
	var unsigned := receipt.duplicate(true)
	unsigned.erase("fingerprint")
	return str(receipt["fingerprint"]) == _merchant_participant_digest(unsigned)


func _nonlethal_health_transition_matches(
	before: Dictionary,
	after: Dictionary,
	cost: int
) -> bool:
	if cost <= 0 or before.size() != after.size():
		return false
	var expected := before.duplicate(true)
	var health_value: Variant = expected.get("health")
	if not health_value is Dictionary:
		return false
	var health_snapshot := health_value as Dictionary
	var current_hp_value: Variant = health_snapshot.get("current_hp")
	if typeof(current_hp_value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var remaining_hp := float(current_hp_value) - float(cost)
	if not is_finite(remaining_hp) or remaining_hp < 1.0:
		return false
	health_snapshot["current_hp"] = remaining_hp
	health_snapshot["dead"] = false
	return expected == after


func _valid_nonlethal_health_transaction_id(value: String) -> bool:
	var regex := RegEx.new()
	return (
		regex.compile(NONLETHAL_HEALTH_TRANSACTION_PATTERN) == OK
		and regex.search(value) != null
	)


func _merchant_participant_digest(value: Dictionary) -> String:
	return JSON.stringify(value).sha256_text()


func _nonlethal_health_success(values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": {}}
	for key_value: Variant in values.keys():
		result[key_value] = values[key_value]
	return result


func _nonlethal_health_failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}


func _apply_effects(definition: Dictionary, fallback_category: String) -> Dictionary:
	var effects_value: Variant = definition.get("effects", {})
	if not effects_value is Dictionary:
		return {"ok": false, "code": &"INVALID_EFFECTS"}
	var definition_id := str(definition.get("id", "legacy_reward")).strip_edges()
	if definition_id.is_empty():
		definition_id = "legacy_reward"
	var category := str(definition.get("category", fallback_category))
	return ItemEffectScript.apply_to_player(
		self,
		(effects_value as Dictionary).duplicate(true),
		definition_id,
		category
	)


func reward_effect_snapshot() -> Dictionary:
	if (
		stats == null
		or not stats.has_method("snapshot")
		or health == null
		or not health.has_method("reward_effect_snapshot")
		or not health.has_method("restore_reward_effect_snapshot")
		or not health.has_method("apply_reward_invulnerability")
		or time_manager == null
		or not time_manager.has_method("reward_effect_snapshot")
		or not time_manager.has_method("restore_reward_effect_snapshot")
		or weapon_modifier_state == null
		or not weapon_modifier_state.has_method("snapshot")
		or not weapon_modifier_state.has_method("restore_snapshot")
	):
		return {}
	var stats_value: Variant = stats.call("snapshot")
	var health_value: Variant = health.call("reward_effect_snapshot")
	var time_value: Variant = time_manager.call("reward_effect_snapshot")
	var modifier_value: Variant = weapon_modifier_state.call("snapshot")
	if (
		not stats_value is Dictionary
		or not health_value is Dictionary
		or not time_value is Dictionary
		or not modifier_value is Dictionary
	):
		return {}
	var weapon_runtime_snapshot: Dictionary = {}
	if weapon_runtime != null and weapon_runtime.has_method("snapshot"):
		var runtime_value: Variant = weapon_runtime.call("snapshot")
		if not runtime_value is Dictionary:
			return {}
		weapon_runtime_snapshot = (runtime_value as Dictionary).duplicate(true)
	return {
		"schema_version": 1,
		"stats": (stats_value as Dictionary).duplicate(true),
		"health": (health_value as Dictionary).duplicate(true),
		"time": (time_value as Dictionary).duplicate(true),
		"weapon": {
			"modifiers": (modifier_value as Dictionary).duplicate(true),
			"runtime": weapon_runtime_snapshot,
		},
		"character": {"dash_invulnerable_bonus": _dash_invulnerable_bonus},
	}


func can_restore_reward_effect_snapshot(value: Dictionary, replay_invulnerability: Dictionary = {}) -> bool:
	if not _valid_reward_effect_snapshot(value):
		return false
	var weapon := value["weapon"] as Dictionary
	var health_target := (value["health"] as Dictionary).duplicate(true)
	var health_valid := health != null and health.has_method("can_restore_reward_effect_snapshot")
	if health_valid:
		if replay_invulnerability.is_empty():
			health_valid = bool(health.call("can_restore_reward_effect_snapshot", health_target))
		else:
			health_valid = health.has_method("can_restore_full_replay_reward_snapshot") and bool(health.call(
				"can_restore_full_replay_reward_snapshot", health_target, replay_invulnerability
			))
	return (
		_valid_reward_stats_snapshot(value["stats"] as Dictionary)
		and health_valid
		and time_manager != null
		and time_manager.has_method("can_restore_reward_effect_snapshot")
		and bool(time_manager.call(
			"can_restore_reward_effect_snapshot",
			(value["time"] as Dictionary).duplicate(true)
		))
		and weapon_modifier_state != null
		and weapon_modifier_state.has_method("can_restore_snapshot")
		and bool(weapon_modifier_state.call(
			"can_restore_snapshot",
			(weapon["modifiers"] as Dictionary).duplicate(true)
		))
	)


func restore_reward_effect_snapshot(
	value: Dictionary,
	publish_signals: bool = true,
	replay_invulnerability: Dictionary = {}
) -> bool:
	if not can_restore_reward_effect_snapshot(value, replay_invulnerability):
		return false
	var before := reward_effect_snapshot()
	if before.is_empty():
		return false
	var before_invulnerability: Dictionary = health.invulnerability_replay_snapshot() if not replay_invulnerability.is_empty() else {}
	if _install_reward_effect_snapshot(value, publish_signals, replay_invulnerability) and reward_effect_snapshot() == value:
		return true
	if not _install_reward_effect_snapshot(before, false, before_invulnerability) or reward_effect_snapshot() != before:
		push_error("Player reward-effect restore rollback failed")
	return false


func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
	var validation := _validated_reward_effect_operation(operation)
	if validation.is_empty():
		return {"ok": false, "code": &"INVALID_OPERATION"}
	var effect_id := StringName(str(validation["effect_id"]))
	var runtime_domain := StringName(str(validation["runtime_domain"]))
	var value: Variant = validation["value"]
	var applied := false
	match runtime_domain:
		&"stats":
			applied = _apply_reward_stats_operation(effect_id, value)
		&"health":
			applied = _apply_reward_health_operation(effect_id, value)
		&"time":
			applied = _apply_reward_time_operation(effect_id, value)
		&"weapon":
			applied = _apply_reward_weapon_operation(validation)
		&"character":
			applied = _apply_reward_character_operation(effect_id, value)
		&"trigger":
			applied = _apply_reward_trigger_operation(effect_id, value)
	if not applied:
		return {
			"ok": false,
			"code": &"OPERATION_REJECTED",
			"effect_id": effect_id,
			"runtime_domain": runtime_domain,
		}
	return {
		"ok": true,
		"code": &"OK",
		"effect_id": effect_id,
		"runtime_domain": runtime_domain,
	}


func _valid_reward_effect_snapshot(value: Dictionary) -> bool:
	if not _dictionary_has_exact_fields(
		value,
		["schema_version", "stats", "health", "time", "weapon", "character"]
	):
		return false
	if typeof(value["schema_version"]) != TYPE_INT or int(value["schema_version"]) != 1:
		return false
	for field: String in ["stats", "health", "time", "weapon", "character"]:
		if not value[field] is Dictionary:
			return false
	var weapon := value["weapon"] as Dictionary
	var character := value["character"] as Dictionary
	return (
		_dictionary_has_exact_fields(weapon, ["modifiers", "runtime"])
		and weapon["modifiers"] is Dictionary
		and weapon["runtime"] is Dictionary
		and _dictionary_has_exact_fields(character, ["dash_invulnerable_bonus"])
		and typeof(character["dash_invulnerable_bonus"]) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(character["dash_invulnerable_bonus"]))
	)


func _install_reward_effect_snapshot(value: Dictionary, publish_signals: bool = true, replay_invulnerability: Dictionary = {}) -> bool:
	var energy_before := float(time_manager.get("energy"))
	var max_energy_before := float(time_manager.get("max_energy"))
	if not _restore_reward_stats_snapshot(value["stats"] as Dictionary):
		return false
	_apply_stats_to_components(
		false,
		publish_signals and not _reward_effect_publication_active
	)
	if (
		_reward_effect_publication_active
		and (
			energy_before != float(time_manager.get("energy"))
			or max_energy_before != float(time_manager.get("max_energy"))
		)
	):
		_queue_reward_energy_signal()
	var health_target := (value["health"] as Dictionary).duplicate(true)
	var health_restored: bool
	if replay_invulnerability.is_empty():
		health_restored = bool(health.call("restore_reward_effect_snapshot", health_target))
	else:
		health_restored = bool(health.call("restore_full_replay_reward_snapshot", health_target, replay_invulnerability))
	if not health_restored:
		return false
	if not bool(time_manager.call(
		"restore_reward_effect_snapshot",
		(value["time"] as Dictionary).duplicate(true),
		publish_signals and not _reward_effect_publication_active
	)):
		return false
	if (
		_reward_effect_publication_active
		and (
			energy_before != float(time_manager.get("energy"))
			or max_energy_before != float(time_manager.get("max_energy"))
		)
	):
		_queue_reward_energy_signal()
	var weapon := value["weapon"] as Dictionary
	if not bool(weapon_modifier_state.call(
		"restore_snapshot",
		(weapon["modifiers"] as Dictionary).duplicate(true)
	)):
		return false
	var runtime_snapshot := weapon["runtime"] as Dictionary
	if not runtime_snapshot.is_empty():
		if (
			weapon_runtime == null
			or not weapon_runtime.has_method("restore_snapshot")
			or not bool(weapon_runtime.call("restore_snapshot", runtime_snapshot.duplicate(true)))
		):
			return false
	_dash_invulnerable_bonus = float((value["character"] as Dictionary)["dash_invulnerable_bonus"])
	return true


func _restore_reward_stats_snapshot(value: Dictionary) -> bool:
	if not _valid_reward_stats_snapshot(value):
		return false
	for field: String in [
		"max_hp", "attack", "defense", "move_speed", "attack_speed",
		"crit_chance", "crit_multiplier", "time_energy_max", "time_energy_regen",
	]:
		stats.set(field, float(value[field]))
	return stats.call("snapshot") == value


func _valid_reward_stats_snapshot(value: Dictionary) -> bool:
	const FIELDS: Array[String] = [
		"max_hp",
		"attack",
		"defense",
		"move_speed",
		"attack_speed",
		"crit_chance",
		"crit_multiplier",
		"time_energy_max",
		"time_energy_regen",
	]
	if not _dictionary_has_exact_fields(value, FIELDS):
		return false
	for field: String in FIELDS:
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field])):
			return false
	if (
		float(value["max_hp"]) <= 0.0
		or float(value["attack"]) < 0.0
		or float(value["move_speed"]) <= 0.0
		or float(value["attack_speed"]) <= 0.0
		or float(value["crit_chance"]) < 0.0
		or float(value["crit_chance"]) > 1.0
		or float(value["crit_multiplier"]) < 1.0
		or float(value["time_energy_max"]) <= 0.0
		or float(value["time_energy_regen"]) < 0.0
	):
		return false
	return true


func _validated_reward_effect_operation(operation: Dictionary) -> Dictionary:
	if not _dictionary_has_exact_fields(
		operation,
		["effect_id", "runtime_domain", "value", "stack_rule", "weapon_capabilities"]
	):
		return {}
	for field: String in ["effect_id", "runtime_domain", "stack_rule"]:
		if typeof(operation[field]) != TYPE_STRING or str(operation[field]).is_empty():
			return {}
	if not operation["weapon_capabilities"] is Array:
		return {}
	var effect_id := StringName(str(operation["effect_id"]))
	var catalog = EffectHandlerCatalogScript.new()
	var descriptor: Dictionary = catalog.effect_descriptor(effect_id)
	if descriptor.is_empty():
		return {}
	var normalized: Dictionary = catalog.normalize_effects({str(effect_id): operation["value"]})
	if (
		normalized.size() != 1
		or not normalized.has(str(effect_id))
		or normalized[str(effect_id)] != operation["value"]
		or str(descriptor.get("runtime_domain", "")) != str(operation["runtime_domain"])
		or str(descriptor.get("stack_rule", "")) != str(operation["stack_rule"])
		or descriptor.get("weapon_capabilities", []) != operation["weapon_capabilities"]
	):
		return {}
	return operation.duplicate(true)


func _apply_reward_stats_operation(effect_id: StringName, value: Variant) -> bool:
	var energy_before := float(time_manager.get("energy"))
	var max_energy_before := float(time_manager.get("max_energy"))
	var numeric := float(value)
	var next_value: float
	match effect_id:
		&"max_hp_bonus":
			next_value = float(stats.max_hp) + numeric
			if not is_finite(next_value) or next_value <= 0.0:
				return false
			stats.max_hp = next_value
		&"max_hp_multiplier":
			next_value = float(stats.max_hp) * numeric
			if not is_finite(next_value) or next_value <= 0.0:
				return false
			stats.max_hp = next_value
		&"defense_bonus":
			next_value = float(stats.defense) + numeric
			if not is_finite(next_value):
				return false
			stats.defense = next_value
		&"time_energy_max_bonus":
			next_value = float(stats.time_energy_max) + numeric
			if not is_finite(next_value) or next_value <= 0.0:
				return false
			stats.time_energy_max = next_value
		&"time_energy_regen_bonus":
			next_value = float(stats.time_energy_regen) + numeric
			if not is_finite(next_value) or next_value < 0.0:
				return false
			stats.time_energy_regen = next_value
		&"time_energy_regen_multiplier":
			next_value = float(stats.time_energy_regen) * numeric
			if not is_finite(next_value) or next_value < 0.0:
				return false
			stats.time_energy_regen = next_value
		_:
			return false
	_apply_stats_to_components(false, not _reward_effect_publication_active)
	if (
		_reward_effect_publication_active
		and (
			energy_before != float(time_manager.get("energy"))
			or max_energy_before != float(time_manager.get("max_energy"))
		)
	):
		_queue_reward_energy_signal()
	return true


func _apply_reward_health_operation(effect_id: StringName, value: Variant) -> bool:
	if effect_id != &"healing_multiplier":
		return false
	var next_value := float(health.get("healing_multiplier")) * float(value)
	if not is_finite(next_value) or next_value < 0.0:
		return false
	health.set("healing_multiplier", next_value)
	return true


func _apply_reward_time_operation(effect_id: StringName, value: Variant) -> bool:
	var current := float(time_manager.get(effect_id))
	var numeric := float(value)
	var next_value: Variant
	match effect_id:
		&"rewind_echo_enabled":
			next_value = bool(value)
		&"time_stop_cost_multiplier", &"rewind_cost_multiplier", \
		&"time_rift_cost_multiplier", &"time_accelerate_cost_multiplier":
			next_value = current * numeric
		&"time_stop_weakpoint_duration", &"rewind_path_hit_multiplier", \
		&"low_energy_regen_multiplier", &"low_energy_threshold":
			next_value = maxf(current, numeric)
		&"time_stop_duration_bonus", &"time_stop_weakpoint_damage_bonus", \
		&"time_stop_self_damage", &"rewind_heal", &"rewind_self_damage", \
		&"time_rift_duration_bonus", &"time_rift_radius_bonus", \
		&"time_rift_slow_bonus", &"time_accelerate_duration_bonus", \
		&"time_accelerate_multiplier_bonus":
			next_value = current + numeric
		_:
			return false
	if next_value is float and (not is_finite(float(next_value)) or float(next_value) < 0.0):
		return false
	time_manager.set(effect_id, next_value)
	return true


func _apply_reward_weapon_operation(operation: Dictionary) -> bool:
	var routes: Array[Dictionary] = []
	for mapping_value: Variant in operation["weapon_capabilities"] as Array:
		if not mapping_value is Dictionary:
			return false
		var mapping := (mapping_value as Dictionary).duplicate(true)
		mapping["effect_id"] = str(operation["effect_id"])
		mapping["value"] = operation["value"]
		mapping["stack_rule"] = str(operation["stack_rule"])
		routes.append(mapping)
	return not routes.is_empty() and apply_weapon_capability_effects(routes)


func _apply_reward_character_operation(effect_id: StringName, value: Variant) -> bool:
	if effect_id != &"dash_invulnerable_bonus":
		return false
	var next_value := _dash_invulnerable_bonus + float(value)
	if not is_finite(next_value) or next_value < 0.0:
		return false
	_dash_invulnerable_bonus = next_value
	return true


func _apply_reward_trigger_operation(effect_id: StringName, value: Variant) -> bool:
	match effect_id:
		&"heal":
			var healed_amount := float(health.call(
				"heal",
				float(value),
				not _reward_effect_publication_active
			))
			if _reward_effect_publication_active and healed_amount > 0.0:
				_reward_effect_pending_health_signal = {
					"amount": healed_amount,
					"current_hp": float(health.get("current_hp")),
				}
			return true
		&"time_energy_restore":
			time_manager.call(
				"restore_energy",
				float(value),
				not _reward_effect_publication_active
			)
			if _reward_effect_publication_active:
				_queue_reward_energy_signal()
			return true
		&"invulnerable_duration":
			return bool(health.call("apply_reward_invulnerability", float(value)))
		_:
			return false


func _queue_reward_energy_signal() -> void:
	_reward_effect_pending_time_signal = {
		"current": float(time_manager.get("energy")),
		"maximum": float(time_manager.get("max_energy")),
	}


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


func _on_character_room_started(
	run_id: String,
	room_id: StringName,
	revision: int
) -> void:
	if (
		StringName(run_id) != _run_id
		or room_id == &""
		or revision <= 0
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("on_room_started")
	):
		return
	var before: Dictionary = character_action_coordinator.call("snapshot")
	var action_before: Dictionary = character_action_coordinator.call("action_snapshot")
	var result_value: Variant = character_action_coordinator.call("on_room_started", {
		"run_id": _run_id,
		"run_revision": _owner_character_generation,
		"room_id": room_id,
		"room_revision": revision,
		"owner_character_generation": _owner_character_generation,
	})
	if (
		not result_value is Dictionary
		or not bool((result_value as Dictionary).get("ok", false))
		or not _apply_character_result_events(result_value as Dictionary)
	):
		if not _restore_character_coordinator_pair(before, action_before):
			set_physics_process(false)
		push_error("Character room-start settlement failed closed")


func _on_character_room_cleared(
	run_id: String,
	room_id: StringName,
	revision: int
) -> void:
	if (
		StringName(run_id) != _run_id
		or room_id == &""
		or revision <= 0
		or character_action_coordinator == null
		or not character_action_coordinator.has_method("on_room_cleared")
	):
		return
	var before: Dictionary = character_action_coordinator.call("snapshot")
	var action_before: Dictionary = character_action_coordinator.call("action_snapshot")
	var result_value: Variant = character_action_coordinator.call("on_room_cleared", {
		"run_id": _run_id,
		"run_revision": _owner_character_generation,
		"room_id": room_id,
		"room_revision": revision,
		"owner_character_generation": _owner_character_generation,
	})
	if (
		not result_value is Dictionary
		or not bool((result_value as Dictionary).get("ok", false))
		or not _apply_character_result_events(result_value as Dictionary)
	):
		if not _restore_character_coordinator_pair(before, action_before):
			set_physics_process(false)
		push_error("Character room-clear settlement failed closed")


func _on_died(_killer: Variant) -> void:
	_cancel_uncommitted_character_action(&"player_died")
	if action_state.transition_to(PlayerActionStateScript.State.DEAD, 0):
		if not _invalidate_world_payload_generation(&"player_died"):
			push_error("WorldPayloadAuthority death invalidation failed")
		action_state.clear_buffered_inputs()
		_clear_character_input_owner()
		_clear_transient_effects()
		_clear_owned_player_arrows()
		_clear_owned_player_projectiles()
		_clear_owned_staff_payloads()
		_clear_owned_gauntlets_payloads()
		cancel_active_time_effects(&"player_died")


func _apply_stats_to_components(reset_health: bool, publish_signals: bool = true) -> void:
	if reset_health:
		health.configure_from_stats(stats)
	else:
		health.apply_stat_totals(stats)
	time_manager.configure_from_stats(stats, publish_signals)
	_sync_weapon_adapter_stats()
