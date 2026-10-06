class_name GunProjectile
extends Area2D

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

signal projectile_hit_confirmed(action_token: int, outcome_index: int, target: Node)
signal action_hit_confirmed(action_token: int, target: Node)
signal resource_reward_requested(action_token: int, reward_id: StringName, amount: float)

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const Targets := preload("res://scripts/combat/weapon_target_policy.gd")
const NativeHitbox := preload("res://scripts/combat/hitbox.gd")
const PIXELS_PER_TILE := 64.0
const EXECUTION_SNAPSHOT_SCHEMA_VERSION := 1
const VALID_ACTION_IDS: Array[String] = [
	"normal_fire",
	"aimed_fire",
	"shotgun_fire",
	"void_penetration",
]

@export var speed: float = 760.0
@export var lifetime: float = 2.0
@export var damage: float = 30.0
@export var base_attack: float = 30.0
@export var max_range_pixels: float = 960.0
@export var pierce: int = 0
@export var pierce_mode: String = "limited"
@export var damage_type: int = DamageInfoScript.DamageType.PHYSICAL
@export var time_damage_ratio: float = 0.0
@export var critical_chance_bonus: float = 0.0
@export var knockback_pixels: float = 70.0
@export var action_token: int = 0
@export var outcome_index: int = 0
@export var deterministic_seed: int = 0
@export var source_action_id: String = ""
@export var descriptor_id: String = ""
@export var trail_duration_frames: int = 0
@export var trail_tick_interval_frames: int = 0
@export var trail_width_pixels: float = 0.0
@export var trail_tick_damage_multiplier: float = 0.0
@export var trail_damage_type: int = DamageInfoScript.DamageType.TIME

@onready var visual: CanvasItem = $Visual

var direction: Vector2 = Vector2.RIGHT
var source: Node
var owner_entity: Node
var attack_tags: Array[String] = ["weapon:gun"]
var time_interactions: Array[Dictionary] = []
var boss_conversion: Dictionary = {}
var resource_reward: Dictionary = {}
var action_claims: Dictionary = {}
var penetration_explosion: Dictionary = {}
var vulnerability: Dictionary = {}
var aimed_time_burst: Dictionary = {}
var _hit_targets: Dictionary = {}
var _trail_points: Array[Dictionary] = []
var _trail_targets: Dictionary = {}
var _start_position: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0
var _execution_frame: int = 0
var _lifetime_remaining: float = 0.0
var _flight_complete: bool = false
var _last_configuration_error: String = ""
var _execution_active: bool = false
var _restored_released_attachment: bool = false


func _ready() -> void:
	add_to_group("player_projectiles")
	add_to_group("gun_projectiles")
	area_entered.connect(_on_physical_area_entered)
	if not _execution_active:
		monitoring = false
		set_physics_process(false)
		return
	rotation = direction.angle()
	if _restored_released_attachment:
		_restored_released_attachment = false
	else:
		_start_position = global_position
		_lifetime_remaining = lifetime
		if trail_duration_frames > 0:
			_append_trail_point(global_position)
	monitoring = not _flight_complete
	set_physics_process(true)
	if is_instance_valid(visual):
		visual.visible = not _flight_complete


func _physics_process(delta: float) -> void:
	if not _execution_active:
		return
	_lifetime_remaining = maxf(0.0, _lifetime_remaining - delta)
	if _lifetime_remaining <= 0.0:
		_retire_execution()
		return
	if not _flight_complete:
		var distance := speed * delta
		if max_range_pixels > 0.0:
			distance = minf(distance, maxf(0.0, max_range_pixels - _distance_travelled))
		var destination := global_position + direction.normalized() * distance
		for area: Area2D in Targets.swept_hurtboxes(self, global_position, destination):
			_on_area_entered(area)
			if not _execution_active or is_queued_for_deletion():
				return
		global_position = destination
		_distance_travelled += distance
		if trail_duration_frames > 0:
			_append_trail_point(global_position)
		if max_range_pixels > 0.0 and _distance_travelled >= max_range_pixels - 0.001:
			_flight_complete = true
			monitoring = false
			visual.visible = false
	advance_execution_for_test(1)


func configure_execution(execution: Dictionary) -> bool:
	_execution_active = false
	_restored_released_attachment = false
	_clear_transient_state()
	action_claims = {}
	_last_configuration_error = ""
	if is_queued_for_deletion():
		_last_configuration_error = "queued_for_deletion"
		return false
	for field: String in [
		"action_token",
		"source_action_id",
		"descriptor_id",
		"outcome_index",
		"deterministic_seed",
		"damage",
		"base_attack",
		"speed",
		"max_range_pixels",
		"pierce",
		"pierce_mode",
		"damage_type",
		"time_damage_ratio",
		"trail",
		"time_interactions",
		"boss_conversion",
		"resource_reward",
		"action_claims",
		"tags",
	]:
		if not execution.has(field):
			_last_configuration_error = "missing:%s" % field
			return false
	if (
		typeof(execution["action_token"]) != TYPE_INT
		or int(execution["action_token"]) <= 0
		or str(execution["source_action_id"]) not in VALID_ACTION_IDS
		or str(execution["descriptor_id"]).is_empty()
		or typeof(execution["outcome_index"]) != TYPE_INT
		or int(execution["outcome_index"]) < 0
		or typeof(execution["deterministic_seed"]) != TYPE_INT
		or not _positive_number(execution["damage"])
		or not _non_negative_number(execution["base_attack"])
		or not _positive_number(execution["speed"])
		or not _non_negative_number(execution["max_range_pixels"])
		or typeof(execution["pierce"]) != TYPE_INT
		or int(execution["pierce"]) < 0
		or str(execution["pierce_mode"]) not in ["limited", "unlimited"]
		or typeof(execution["damage_type"]) != TYPE_INT
		or int(execution["damage_type"]) < DamageInfoScript.DamageType.PHYSICAL
		or int(execution["damage_type"]) > DamageInfoScript.DamageType.LIGHTNING
		or not _non_negative_number(execution["time_damage_ratio"])
		or float(execution["time_damage_ratio"]) > 100.0
		or not execution["trail"] is Dictionary
		or not execution["time_interactions"] is Array
		or not execution["boss_conversion"] is Dictionary
		or not execution["resource_reward"] is Dictionary
		or not execution["action_claims"] is Dictionary
		or not execution["tags"] is Array
	):
		_last_configuration_error = "basic_contract"
		return false
	var parsed_interactions: Array[Dictionary] = []
	for interaction_value: Variant in execution["time_interactions"]:
		if not interaction_value is Dictionary:
			_last_configuration_error = "time_interaction_type"
			return false
		parsed_interactions.append((interaction_value as Dictionary).duplicate(true))
	var parsed_tags: Array[String] = []
	for tag_value: Variant in execution["tags"]:
		var tag := str(tag_value)
		if tag.is_empty():
			continue
		if not parsed_tags.has(tag):
			parsed_tags.append(tag)
	var critical_value: Variant = execution.get("critical_chance_bonus", 0.0)
	var knockback_value: Variant = execution.get("knockback_pixels", 70.0)
	if (
		not _non_negative_number(critical_value)
		or float(critical_value) > 1.0
		or not _non_negative_number(knockback_value)
	):
		_last_configuration_error = "critical_or_knockback"
		return false
	var explosion_value: Variant = execution.get("penetration_explosion", {})
	var vulnerability_value: Variant = execution.get("vulnerability", {})
	if not explosion_value is Dictionary or not vulnerability_value is Dictionary:
		_last_configuration_error = "secondary_payload_type"
		return false
	var parsed_explosion := _parse_explosion(explosion_value as Dictionary)
	var parsed_vulnerability := _parse_vulnerability(vulnerability_value as Dictionary)
	if not bool(parsed_explosion.get("ok", false)) or not bool(parsed_vulnerability.get("ok", false)):
		_last_configuration_error = "secondary_payload_value"
		return false
	var trail: Dictionary = execution["trail"]
	var parsed_trail := _parse_trail(trail, parsed_interactions, str(execution["source_action_id"]))
	if not bool(parsed_trail.get("ok", false)):
		_last_configuration_error = "trail_value"
		return false
	var parsed_aimed_time_burst := _parse_aimed_time_burst(
		parsed_interactions,
		str(execution["source_action_id"])
	)
	if not bool(parsed_aimed_time_burst.get("ok", false)):
		_last_configuration_error = "aimed_time_burst_value"
		return false

	action_token = int(execution["action_token"])
	source_action_id = str(execution["source_action_id"])
	descriptor_id = str(execution["descriptor_id"])
	outcome_index = int(execution["outcome_index"])
	deterministic_seed = int(execution["deterministic_seed"])
	damage = float(execution["damage"])
	base_attack = float(execution["base_attack"])
	speed = float(execution["speed"])
	max_range_pixels = float(execution["max_range_pixels"])
	pierce = int(execution["pierce"])
	pierce_mode = str(execution["pierce_mode"])
	damage_type = int(execution["damage_type"])
	time_damage_ratio = float(execution["time_damage_ratio"])
	critical_chance_bonus = float(critical_value)
	knockback_pixels = float(knockback_value)
	time_interactions = parsed_interactions
	boss_conversion = (execution["boss_conversion"] as Dictionary).duplicate(true)
	resource_reward = (execution["resource_reward"] as Dictionary).duplicate(true)
	action_claims = execution["action_claims"]
	penetration_explosion = (parsed_explosion.get("value", {}) as Dictionary).duplicate(true)
	vulnerability = (parsed_vulnerability.get("value", {}) as Dictionary).duplicate(true)
	aimed_time_burst = (parsed_aimed_time_burst.get("value", {}) as Dictionary).duplicate(true)
	attack_tags = parsed_tags
	if not attack_tags.has("weapon:gun"):
		attack_tags.append("weapon:gun")
	if not attack_tags.has("non_recursive:resource_reward"):
		attack_tags.append("non_recursive:resource_reward")
	trail_duration_frames = int(parsed_trail["duration_frames"])
	trail_tick_interval_frames = int(parsed_trail["tick_interval_frames"])
	trail_width_pixels = float(parsed_trail["width_pixels"])
	trail_tick_damage_multiplier = float(parsed_trail["tick_damage_multiplier"])
	trail_damage_type = int(parsed_trail["damage_type"])
	if trail_duration_frames > 0:
		var flight_seconds := max_range_pixels / speed if max_range_pixels > 0.0 else lifetime
		lifetime = maxf(lifetime, flight_seconds + float(trail_duration_frames) / 60.0 + 0.25)
	_start_position = global_position
	_distance_travelled = 0.0
	_execution_frame = 0
	_lifetime_remaining = lifetime
	_flight_complete = false
	_execution_active = true
	set_physics_process(true)
	if is_inside_tree():
		monitoring = true
		if is_instance_valid(visual):
			visual.visible = true
	return true


func configuration_error_for_test() -> String:
	return _last_configuration_error


func execution_snapshot() -> Dictionary:
	return {
		"schema_version": EXECUTION_SNAPSHOT_SCHEMA_VERSION,
		"action_token": action_token,
		"source_action_id": source_action_id,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"deterministic_seed": deterministic_seed,
		"damage": damage,
		"base_attack": base_attack,
		"speed": speed,
		"max_range_pixels": max_range_pixels,
		"pierce": pierce,
		"pierce_mode": pierce_mode,
		"damage_type": damage_type,
		"time_damage_ratio": time_damage_ratio,
		"critical_chance_bonus": critical_chance_bonus,
		"knockback_pixels": knockback_pixels,
		"penetration_explosion": penetration_explosion.duplicate(true),
		"vulnerability": vulnerability.duplicate(true),
		"aimed_time_burst": aimed_time_burst.duplicate(true),
		"trail_duration_frames": trail_duration_frames,
		"trail_tick_interval_frames": trail_tick_interval_frames,
		"trail_width_pixels": trail_width_pixels,
		"trail_tick_damage_multiplier": trail_tick_damage_multiplier,
		"trail_damage_type": trail_damage_type,
		"trail": {
			"duration_frames": trail_duration_frames,
			"tick_interval_frames": trail_tick_interval_frames,
			"width_pixels": trail_width_pixels,
			"tick_damage_multiplier": trail_tick_damage_multiplier,
			"damage_type": trail_damage_type,
		} if trail_duration_frames > 0 else {},
		"direction": direction,
		"start_position": _start_position,
		"distance_travelled": _distance_travelled,
		"execution_frame": _execution_frame,
		"lifetime": lifetime,
		"lifetime_remaining": _lifetime_remaining,
		"flight_complete": _flight_complete,
		"trail_points": _trail_points.duplicate(true),
		"hit_target_ids": _sorted_integer_keys(_hit_targets),
		"trail_target_ids": _sorted_integer_keys(_trail_targets),
		"action_claims": action_claims.duplicate(true),
		"execution_active": _execution_active,
		"trail_point_count": _trail_points.size(),
		"trail_target_count": _trail_targets.size(),
		"hit_target_count": _hit_targets.size(),
		"time_interactions": time_interactions.duplicate(true),
		"boss_conversion": boss_conversion.duplicate(true),
		"resource_reward": resource_reward.duplicate(true),
		"tags": attack_tags.duplicate(),
	}


func can_restore_execution_snapshot(value: Dictionary) -> bool:
	var expected_fields: Array[String] = [
		"schema_version", "action_token", "source_action_id", "descriptor_id", "outcome_index",
		"deterministic_seed", "damage", "base_attack", "speed", "max_range_pixels", "pierce",
		"pierce_mode", "damage_type", "time_damage_ratio", "critical_chance_bonus",
		"knockback_pixels", "penetration_explosion", "vulnerability", "aimed_time_burst",
		"trail_duration_frames", "trail_tick_interval_frames", "trail_width_pixels",
		"trail_tick_damage_multiplier", "trail_damage_type", "trail", "direction",
		"start_position", "distance_travelled", "execution_frame", "lifetime",
		"lifetime_remaining", "flight_complete", "trail_points", "hit_target_ids", "trail_target_ids",
		"action_claims", "execution_active", "trail_point_count", "trail_target_count",
		"hit_target_count", "time_interactions", "boss_conversion", "resource_reward", "tags",
	]
	if not _has_exact_fields(value, expected_fields):
		return false
	if int(value.get("schema_version", -1)) != EXECUTION_SNAPSHOT_SCHEMA_VERSION:
		return false
	var trail_value: Variant = value.get("trail")
	if not trail_value is Dictionary:
		return false
	var trail := trail_value as Dictionary
	if (
		(not trail.is_empty() and not _has_exact_fields(trail, ["duration_frames", "tick_interval_frames", "width_pixels", "tick_damage_multiplier", "damage_type"]))
		or (int(value.get("trail_duration_frames", 0)) == 0 and not trail.is_empty())
		or (int(value.get("trail_duration_frames", 0)) > 0 and trail.is_empty())
	):
		return false
	var staged := GunProjectile.new()
	var configured := staged.configure_execution(value)
	if not configured:
		staged.free()
		return false
	var direction_value: Variant = value.get("direction")
	var start_value: Variant = value.get("start_position")
	var distance_value: Variant = value.get("distance_travelled")
	var frame_value: Variant = value.get("execution_frame")
	var lifetime_value: Variant = value.get("lifetime")
	var remaining_value: Variant = value.get("lifetime_remaining")
	var trail_points_value: Variant = value.get("trail_points")
	var hit_ids_value: Variant = value.get("hit_target_ids")
	var trail_target_ids_value: Variant = value.get("trail_target_ids")
	var claims_value: Variant = value.get("action_claims")
	var valid := (
		direction_value is Vector2
		and _finite_vector(direction_value as Vector2)
		and (direction_value as Vector2).length_squared() > 0.001
		and start_value is Vector2
		and _finite_vector(start_value as Vector2)
		and _non_negative_number(distance_value)
		and float(distance_value) <= staged.max_range_pixels + 0.001
		and typeof(frame_value) == TYPE_INT
		and int(frame_value) >= 0
		and _positive_number(lifetime_value)
		and is_equal_approx(float(lifetime_value), staged.lifetime)
		and _positive_number(remaining_value)
		and float(remaining_value) <= float(lifetime_value) + 0.001
		and typeof(value.get("flight_complete")) == TYPE_BOOL
		and _valid_trail_points(trail_points_value, int(frame_value))
		and _valid_positive_integer_array(hit_ids_value)
		and _valid_positive_integer_array(trail_target_ids_value)
		and _valid_claim_dictionary(claims_value)
		and typeof(value.get("execution_active")) == TYPE_BOOL
		and bool(value.get("execution_active", false))
		and int(value.get("trail_point_count", -1)) == (trail_points_value as Array).size()
		and int(value.get("trail_target_count", -1)) == (trail_target_ids_value as Array).size()
		and int(value.get("hit_target_count", -1)) == (hit_ids_value as Array).size()
	)
	var expected_flight_complete := (
		staged.max_range_pixels > 0.0
		and float(distance_value) >= staged.max_range_pixels - 0.001
	)
	if valid and bool(value.get("flight_complete", false)) != expected_flight_complete:
		valid = false
	if valid and staged.trail_duration_frames == 0 and not (trail_points_value as Array).is_empty():
		valid = false
	staged.free()
	return valid


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func restore_execution_snapshot(value: Dictionary) -> bool:
	if is_queued_for_deletion() or not can_restore_execution_snapshot(value):
		return false
	var rollback := execution_snapshot() if _execution_active else {}
	if _apply_validated_execution_snapshot(value) and execution_snapshot() == value:
		return true
	if not rollback.is_empty() and can_restore_execution_snapshot(rollback):
		_apply_validated_execution_snapshot(rollback)
	else:
		reset_execution_state()
	return false


func prepare_restored_tree_attachment(released: bool) -> void:
	_restored_released_attachment = released


func bind_action_claims(shared_claims: Dictionary) -> void:
	action_claims = shared_claims


func _apply_validated_execution_snapshot(value: Dictionary) -> bool:
	if not configure_execution(value):
		return false
	direction = (value["direction"] as Vector2).normalized()
	_start_position = value["start_position"] as Vector2
	_distance_travelled = float(value["distance_travelled"])
	_execution_frame = int(value["execution_frame"])
	lifetime = float(value["lifetime"])
	_lifetime_remaining = float(value["lifetime_remaining"])
	_flight_complete = bool(value["flight_complete"])
	_trail_points = (value["trail_points"] as Array).duplicate(true)
	_trail_targets.clear()
	for target_id_value: Variant in value["trail_target_ids"] as Array:
		_trail_targets[int(target_id_value)] = null
	_hit_targets.clear()
	for target_id_value: Variant in value["hit_target_ids"] as Array:
		_hit_targets[int(target_id_value)] = true
	action_claims = (value["action_claims"] as Dictionary).duplicate(true)
	_execution_active = true
	_restored_released_attachment = true
	rotation = direction.angle()
	monitoring = is_inside_tree() and not _flight_complete
	set_physics_process(is_inside_tree())
	if is_instance_valid(visual):
		visual.visible = not _flight_complete
	return true


func reset_execution_state() -> void:
	_clear_transient_state()
	action_claims = {}
	_restored_released_attachment = false
	_retire_execution()


func advance_execution_for_test(frames: int) -> void:
	if not _execution_active or frames <= 0:
		return
	for _frame: int in range(frames):
		_execution_frame += 1
		_prune_trail_points()
		if trail_tick_interval_frames > 0 and _execution_frame % trail_tick_interval_frames == 0:
			_refresh_trail_targets()
			_tick_trail_targets()


func _on_physical_area_entered(area: Area2D) -> void:
	NativeHitbox.dispatch_contact(_on_area_entered.bind(area))


func _on_area_entered(area: Area2D) -> void:
	if (
		not _execution_active
		or is_queued_for_deletion()
		or not is_instance_valid(area)
		or not area.has_method("receive_hit")
	):
		return
	var target := area.get_parent()
	if not Targets.is_attackable(target):
		return
	var target_id := _stable_target_id(target)
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	_deliver_damage(area, damage, damage_type, [])
	var time_damage := base_attack * time_damage_ratio
	if time_damage > 0.0:
		_deliver_damage(
			area,
			time_damage,
			DamageInfoScript.DamageType.TIME,
			["damage:time_component", "non_recursive:time_interaction"]
		)
	if Targets.is_arena_construct(target):
		if pierce_mode != "unlimited" and _hit_targets.size() > pierce:
			_retire_execution()
		return
	_apply_aimed_time_burst(target)
	projectile_hit_confirmed.emit(action_token, outcome_index, target)
	_emit_action_confirmation(target)
	_emit_resource_reward()
	_apply_penetration_explosion(target)
	_apply_vulnerability(target)
	_apply_boss_conversion(target)
	if pierce_mode != "unlimited" and _hit_targets.size() > pierce:
		_retire_execution()


func _deliver_damage(
	area: Area2D,
	amount: float,
	type: int,
	extra_tags: Array[String]
) -> void:
	if amount <= 0.0:
		return
	var resolved_tags: Array[String] = attack_tags.duplicate()
	for tag: String in extra_tags:
		if not resolved_tags.has(tag):
			resolved_tags.append(tag)
	var target := area.get_parent()
	var damage_info = DamageInfoScript.from_plan({
		"run_id": &"runtime",
		"target_id": _damage_target_id(target),
		"hostile_source_id": StringName("player:gun:%d:%d" % [action_token, outcome_index]),
		"attack_generation": maxi(1, action_token),
		"hit_index": outcome_index,
		"action_token": maxi(1, action_token),
		"amount": amount,
		"damage_type": type,
		"source": source,
		"attacker": owner_entity,
		"crit_chance": critical_chance_bonus if type == damage_type else 0.0,
		"knockback": direction.normalized() * knockback_pixels if type == damage_type else Vector2.ZERO,
		"tags": resolved_tags,
	})
	if damage_info == null:
		return
	area.call("receive_hit", damage_info)


func _emit_action_confirmation(target: Node) -> void:
	if _claim_action_once("hit_confirmed"):
		action_hit_confirmed.emit(action_token, target)


func _emit_resource_reward() -> void:
	if resource_reward.is_empty():
		return
	var reward_id := StringName(str(resource_reward.get("reward_id", "")))
	var amount := float(resource_reward.get("amount", 0.0))
	if reward_id == &"" or not is_finite(amount) or amount <= 0.0:
		return
	if _claim_action_once("resource:%s" % str(reward_id)):
		resource_reward_requested.emit(action_token, reward_id, amount)


func _claim_action_once(claim_id: String) -> bool:
	var key := "%d:%s" % [action_token, claim_id]
	if action_claims.has(key):
		return false
	action_claims[key] = true
	return true


func _append_trail_point(point: Vector2) -> void:
	if trail_duration_frames <= 0:
		return
	if not _trail_points.is_empty():
		var previous: Vector2 = _trail_points[-1]["position"]
		if previous.distance_squared_to(point) < 1.0:
			_trail_points[-1]["expires_at"] = _execution_frame + trail_duration_frames
			return
	_trail_points.append({
		"position": point,
		"expires_at": _execution_frame + trail_duration_frames,
	})


func _prune_trail_points() -> void:
	for index: int in range(_trail_points.size() - 1, -1, -1):
		if int(_trail_points[index]["expires_at"]) <= _execution_frame:
			_trail_points.remove_at(index)
	if _trail_points.is_empty():
		_trail_targets.clear()


func _refresh_trail_targets() -> void:
	if _trail_points.is_empty() or not is_inside_tree():
		_trail_targets.clear()
		return
	var active_targets: Dictionary = {}
	for enemy: Node in SceneScope.nodes_in_group(self, "enemies"):
		if not is_instance_valid(enemy):
			continue
		for child: Node in enemy.get_children():
			if child is Area2D and child.has_method("receive_hit") and _area_is_on_trail(child):
				active_targets[_stable_target_id(enemy)] = child
				break
	_trail_targets = active_targets


func _tick_trail_targets() -> void:
	if trail_tick_damage_multiplier <= 0.0:
		return
	var amount := base_attack * trail_tick_damage_multiplier
	if amount <= 0.0:
		return
	var stale_ids: Array[int] = []
	for target_id: Variant in _trail_targets:
		var area_value: Variant = _trail_targets[target_id]
		if (
			not is_instance_valid(area_value)
			or not area_value is Area2D
			or (area_value as Area2D).get_parent() == null
			or not (area_value as Area2D).get_parent().is_in_group("enemies")
		):
			stale_ids.append(int(target_id))
			continue
		_deliver_damage(
			area_value,
			amount,
			trail_damage_type,
			[
				"attack:gun_rift_trail",
				"non_recursive:time_interaction",
			]
		)
	for target_id: int in stale_ids:
		_trail_targets.erase(target_id)
	_trail_targets.clear()


func _area_is_on_trail(area: Area2D) -> bool:
	if _trail_points.size() == 1:
		return area.global_position.distance_to(_trail_points[0]["position"]) <= trail_width_pixels * 0.5
	for index: int in range(1, _trail_points.size()):
		var start: Vector2 = _trail_points[index - 1]["position"]
		var finish: Vector2 = _trail_points[index]["position"]
		if _distance_to_segment(area.global_position, start, finish) <= trail_width_pixels * 0.5:
			return true
	return false


func _apply_aimed_time_burst(impact_target: Node) -> void:
	if (
		aimed_time_burst.is_empty()
		or impact_target == null
		or not is_inside_tree()
		or not _claim_action_once("interaction:gun_aimed_time_burst")
	):
		return
	var radius := float(aimed_time_burst.get("radius_pixels", 0.0))
	var multiplier := float(aimed_time_burst.get("damage_multiplier", 0.0))
	var burst_damage_type := int(aimed_time_burst.get(
		"damage_type",
		DamageInfoScript.DamageType.TIME
	))
	if radius <= 0.0 or multiplier <= 0.0:
		return
	var center: Vector2 = (
		(impact_target as Node2D).global_position
		if impact_target is Node2D
		else global_position
	)
	for enemy: Node in SceneScope.nodes_in_group(self, "enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if (enemy as Node2D).global_position.distance_to(center) > radius:
			continue
		for child: Node in enemy.get_children():
			if child is Area2D and child.has_method("receive_hit"):
				_deliver_damage(
					child,
					base_attack * multiplier,
					burst_damage_type,
					[
						"attack:gun_aimed_time_burst",
						"non_recursive:time_interaction",
					]
				)
				break
	var extension_frames := int(aimed_time_burst.get("stop_extension_frames", 0))
	if (
		extension_frames > 0
		and is_instance_valid(owner_entity)
		and owner_entity.has_method("extend_weapon_time_stop")
	):
		owner_entity.call("extend_weapon_time_stop", action_token, extension_frames)


func _apply_penetration_explosion(impact_target: Node) -> void:
	if penetration_explosion.is_empty() or impact_target == null or not is_inside_tree():
		return
	var radius := float(penetration_explosion.get("radius_pixels", 0.0))
	var multiplier := float(penetration_explosion.get("damage_multiplier", 0.0))
	var explosion_damage_type := int(penetration_explosion.get(
		"damage_type",
		DamageInfoScript.DamageType.VOID
	))
	if radius <= 0.0 or multiplier <= 0.0:
		return
	var center: Vector2 = (
		(impact_target as Node2D).global_position
		if impact_target is Node2D
		else global_position
	)
	var impact_id := _stable_target_id(impact_target)
	for enemy: Node in SceneScope.nodes_in_group(self, "enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if (enemy as Node2D).global_position.distance_to(center) > radius:
			continue
		var claim_key := "%d:explosion:%d:%d" % [action_token, impact_id, _stable_target_id(enemy)]
		if action_claims.has(claim_key):
			continue
		for child: Node in enemy.get_children():
			if child is Area2D and child.has_method("receive_hit"):
				action_claims[claim_key] = true
				_deliver_damage(
					child,
					base_attack * multiplier,
					explosion_damage_type,
					["attack:void_penetration_explosion", "non_recursive:secondary_payload"]
				)
				break


func _apply_vulnerability(target: Node) -> void:
	if vulnerability.is_empty() or target == null or not target.has_method("apply_damage_vulnerability"):
		return
	var duration_frames := int(vulnerability.get("duration_frames", 0))
	var damage_taken_bonus := float(vulnerability.get("damage_taken_bonus", 0.0))
	if duration_frames <= 0 or damage_taken_bonus <= 0.0:
		return
	var source_id := StringName("gun_void_vulnerability_%d" % action_token)
	target.call("apply_damage_vulnerability", source_id, duration_frames, damage_taken_bonus)


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _apply_boss_conversion(target: Node) -> void:
	if (
		boss_conversion.is_empty()
		or target == null
		or not target.is_in_group("bosses")
		or not target.has_method("get_boss_ui_snapshot")
		or not target.has_method("apply_weapon_control_conversion")
	):
		return
	var snapshot_value: Variant = target.call("get_boss_ui_snapshot")
	if not snapshot_value is Dictionary:
		return
	var snapshot: Dictionary = snapshot_value
	var phase := str(snapshot.get("phase", ""))
	if phase == "WINDUP":
		return
	var conversion_phase := "EXPOSED" if bool(snapshot.get("exposed", false)) else phase
	var allowed_value: Variant = boss_conversion.get("allowed_phases", ["RECOVERY", "EXPOSED"])
	if not allowed_value is Array or conversion_phase not in allowed_value:
		return
	var conversion_id := str(boss_conversion.get("conversion_id", ""))
	var poise_damage := float(boss_conversion.get("poise_damage", 0.0))
	if conversion_id.is_empty() or not is_finite(poise_damage) or poise_damage <= 0.0:
		return
	var claim_key := "%d:boss_conversion:%s" % [action_token, conversion_id]
	if action_claims.has(claim_key):
		return
	var source_id := StringName("%s:%d" % [conversion_id, action_token])
	if bool(target.call("apply_weapon_control_conversion", source_id, 0, 0, poise_damage)):
		action_claims[claim_key] = true


func _parse_trail(
	trail: Dictionary,
	interactions: Array[Dictionary],
	action_id: String
) -> Dictionary:
	if trail.is_empty():
		return {
			"ok": true,
			"duration_frames": 0,
			"tick_interval_frames": 0,
			"width_pixels": 0.0,
			"tick_damage_multiplier": 0.0,
			"damage_type": DamageInfoScript.DamageType.TIME,
		}
	var trail_is_authorized := action_id == "void_penetration"
	for interaction: Dictionary in interactions:
		if str(interaction.get("interaction_id", interaction.get("effect", ""))) == "gun_rift_trail":
			trail_is_authorized = true
			break
	var duration_frames := int(trail.get("duration_frames", 0))
	var tick_interval_frames := int(trail.get("tick_interval_frames", 0))
	var width_pixels := float(trail.get("width_pixels", 0.0))
	var tick_damage_multiplier := float(trail.get("tick_damage_multiplier", 0.0))
	var parsed_damage_type := _parse_damage_type(
		trail.get("damage_type", "void" if action_id == "void_penetration" else "time")
	)
	if (
		not trail_is_authorized
		or duration_frames <= 0
		or tick_interval_frames <= 0
		or not is_finite(width_pixels)
		or width_pixels <= 0.0
		or not is_finite(tick_damage_multiplier)
		or tick_damage_multiplier <= 0.0
		or parsed_damage_type < 0
	):
		return {"ok": false}
	return {
		"ok": true,
		"duration_frames": duration_frames,
		"tick_interval_frames": tick_interval_frames,
		"width_pixels": width_pixels,
		"tick_damage_multiplier": tick_damage_multiplier,
		"damage_type": parsed_damage_type,
	}


func _parse_aimed_time_burst(
	interactions: Array[Dictionary],
	action_id: String
) -> Dictionary:
	var parsed: Dictionary = {}
	for interaction: Dictionary in interactions:
		if str(interaction.get("interaction_id", interaction.get("effect", ""))) != "gun_aimed_time_burst":
			continue
		if not parsed.is_empty() or action_id != "aimed_fire":
			return {"ok": false}
		var radius_tiles_value: Variant = interaction.get("explosion_radius_tiles")
		var multiplier_value: Variant = interaction.get("explosion_damage_multiplier")
		var stop_extension_value: Variant = interaction.get("stop_extension_frames")
		var parsed_damage_type := _damage_type_from_name(str(interaction.get("damage_type", "")))
		if (
			str(interaction.get("requires_action", "")) != "aimed_fire"
			or not _positive_number(radius_tiles_value)
			or not _positive_number(multiplier_value)
			or typeof(stop_extension_value) != TYPE_INT
			or int(stop_extension_value) <= 0
			or typeof(interaction.get("extension_once_per_action_token")) != TYPE_BOOL
			or not bool(interaction.get("extension_once_per_action_token", false))
			or parsed_damage_type < 0
		):
			return {"ok": false}
		parsed = {
			"radius_pixels": float(radius_tiles_value) * PIXELS_PER_TILE,
			"damage_multiplier": float(multiplier_value),
			"damage_type": parsed_damage_type,
			"stop_extension_frames": int(stop_extension_value),
		}
	return {"ok": true, "value": parsed}


func _parse_explosion(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {"ok": true, "value": {}}
	var radius_pixels := float(value.get("radius_pixels", 0.0))
	var damage_multiplier := float(value.get("damage_multiplier", 0.0))
	var parsed_damage_type := _parse_damage_type(value.get("damage_type", "void"))
	if (
		not is_finite(radius_pixels)
		or radius_pixels <= 0.0
		or not is_finite(damage_multiplier)
		or damage_multiplier <= 0.0
		or parsed_damage_type < 0
	):
		return {"ok": false}
	return {
		"ok": true,
		"value": {
			"radius_pixels": radius_pixels,
			"damage_multiplier": damage_multiplier,
			"damage_type": parsed_damage_type,
		},
	}


func _parse_vulnerability(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {"ok": true, "value": {}}
	var duration_frames := int(value.get("duration_frames", 0))
	var damage_taken_bonus := float(value.get("damage_taken_bonus", 0.0))
	if (
		duration_frames <= 0
		or not is_finite(damage_taken_bonus)
		or damage_taken_bonus <= 0.0
	):
		return {"ok": false}
	return {
		"ok": true,
		"value": {
			"duration_frames": duration_frames,
			"damage_taken_bonus": damage_taken_bonus,
		},
	}


func _damage_type_from_name(value: String) -> int:
	match value.to_lower():
		"physical":
			return DamageInfoScript.DamageType.PHYSICAL
		"time":
			return DamageInfoScript.DamageType.TIME
		"void":
			return DamageInfoScript.DamageType.VOID
		_:
			return -1


func _parse_damage_type(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		var parsed := int(value)
		return parsed if parsed >= DamageInfoScript.DamageType.PHYSICAL and parsed <= DamageInfoScript.DamageType.LIGHTNING else -1
	return _damage_type_from_name(str(value))


func _stable_target_id(target: Node) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	if target.has_meta("stable_target_id"):
		var explicit_value: Variant = target.get_meta("stable_target_id")
		if typeof(explicit_value) == TYPE_INT and int(explicit_value) > 0:
			return int(explicit_value)
	var stable_key := ""
	if target.has_method("stable_entity_key"):
		stable_key = str(target.call("stable_entity_key"))
	elif target.has_meta("stable_entity_key"):
		stable_key = str(target.get_meta("stable_entity_key"))
	elif target.is_inside_tree():
		stable_key = str(target.get_path())
	if not stable_key.is_empty():
		var stable_hash := absi(stable_key.hash())
		return stable_hash if stable_hash > 0 else 1
	return int(target.get_instance_id())


func _damage_target_id(target: Node) -> StringName:
	if target != null and target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return StringName("target:%d" % int(value))
	return &"pending_target"


func _clear_transient_state() -> void:
	_hit_targets.clear()
	_trail_points.clear()
	_trail_targets.clear()


func _retire_execution() -> void:
	_execution_active = false
	set_physics_process(false)
	if not is_inside_tree():
		monitoring = false
	elif not is_queued_for_deletion():
		queue_free()


func _exit_tree() -> void:
	_execution_active = false
	_clear_transient_state()


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _non_negative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _sorted_integer_keys(value: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for key_value: Variant in value.keys():
		result.append(int(key_value))
	result.sort()
	return result


func _valid_positive_integer_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := 0
	for item: Variant in value as Array:
		if typeof(item) != TYPE_INT or int(item) <= previous:
			return false
		previous = int(item)
	return true


func _valid_claim_dictionary(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key_value: Variant in value as Dictionary:
		if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key_value).is_empty():
			return false
		if (value as Dictionary)[key_value] != true:
			return false
	return true


func _valid_trail_points(value: Variant, execution_frame: int) -> bool:
	if not value is Array:
		return false
	for point_value: Variant in value as Array:
		if not point_value is Dictionary:
			return false
		var point := point_value as Dictionary
		var position_value: Variant = point.get("position")
		if (
			not position_value is Vector2
			or not _finite_vector(position_value as Vector2)
			or typeof(point.get("expires_at")) != TYPE_INT
			or int(point.get("expires_at", 0)) <= execution_frame
		):
			return false
	return true
