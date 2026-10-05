class_name StaffProjectile
extends Area2D

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

signal payload_result(action_token: int, generation: int, result: Dictionary)

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const Targets := preload("res://scripts/combat/weapon_target_policy.gd")
const NativeHitbox := preload("res://scripts/combat/hitbox.gd")
const PIXELS_PER_TILE := 64.0

const VALID_ACTION_IDS: Array[String] = ["arcane_bolt", "charged_element"]
const VALID_ELEMENTS: Array[String] = ["arcane", "fire", "ice", "lightning"]
const EXECUTION_SNAPSHOT_FIELDS: Array[String] = [
	"action_token", "generation", "source_action_id", "descriptor_id", "outcome_index",
	"deterministic_seed", "element_id", "damage", "base_attack", "speed",
	"max_range_pixels", "target_deduplication", "effect_descriptor", "combination", "chain",
	"status_source_id", "boss_conversion", "direction", "distance_travelled", "hit_target_ids",
	"damage_claims", "terminal_emitted", "execution_active",
]

@export var speed: float = 560.0
@export var max_range_pixels: float = 768.0
@export var damage: float = 7.2
@export var base_attack: float = 9.0

var direction: Vector2 = Vector2.RIGHT
var source: Node
var owner_entity: Node

var action_token: int = 0
var generation: int = 0
var source_action_id: String = ""
var descriptor_id: String = ""
var outcome_index: int = 0
var deterministic_seed: int = 0
var element_id: String = ""
var target_deduplication: String = "per_action_target"
var effect_descriptor: Dictionary = {}
var combination: Dictionary = {}
var chain: Dictionary = {}
var status_source_id: StringName = &""
var boss_conversion: Dictionary = {}

var _execution_active: bool = false
var _terminal_emitted: bool = false
var _hit_targets: Dictionary = {}
var _damage_claims: Dictionary = {}
var _start_position: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0


func _ready() -> void:
	add_to_group("player_projectiles")
	add_to_group("staff_projectiles")
	area_entered.connect(_on_physical_area_entered)
	if not _execution_active:
		monitoring = false
		set_physics_process(false)
		return
	_start_position = global_position
	rotation = direction.angle()
	monitoring = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _execution_active or delta <= 0.0:
		return
	var travel := speed * delta
	if max_range_pixels > 0.0:
		travel = minf(travel, maxf(0.0, max_range_pixels - _distance_travelled))
	var destination := global_position + direction.normalized() * travel
	for area: Area2D in Targets.swept_hurtboxes(self, global_position, destination):
		_on_area_entered(area)
		if not _execution_active or is_queued_for_deletion():
			return
	global_position = destination
	_distance_travelled += travel
	if max_range_pixels > 0.0 and _distance_travelled >= max_range_pixels - 0.001:
		complete_without_hit_for_test()


func configure_execution(execution: Dictionary) -> bool:
	reset_execution_state()
	for field: String in [
		"action_token",
		"generation",
		"source_action_id",
		"descriptor_id",
		"outcome_index",
		"deterministic_seed",
		"element_id",
		"damage",
		"base_attack",
		"speed",
		"max_range_pixels",
		"target_deduplication",
		"effect_descriptor",
		"combination",
		"chain",
	]:
		if not execution.has(field):
			return false
	if (
		typeof(execution["action_token"]) != TYPE_INT
		or int(execution["action_token"]) <= 0
		or typeof(execution["generation"]) != TYPE_INT
		or int(execution["generation"]) <= 0
		or str(execution["source_action_id"]) not in VALID_ACTION_IDS
		or str(execution["descriptor_id"]).is_empty()
		or typeof(execution["outcome_index"]) != TYPE_INT
		or int(execution["outcome_index"]) < 0
		or typeof(execution["deterministic_seed"]) != TYPE_INT
		or str(execution["element_id"]) not in VALID_ELEMENTS
		or not _positive_number(execution["damage"])
		or not _positive_number(execution["base_attack"])
		or not _positive_number(execution["speed"])
		or not _positive_number(execution["max_range_pixels"])
		or str(execution["target_deduplication"]) != "per_action_target"
		or not execution["effect_descriptor"] is Dictionary
		or not execution["combination"] is Dictionary
		or not execution["chain"] is Dictionary
	):
		return false
	var direction_value: Variant = execution.get("direction", Vector2.RIGHT)
	if not direction_value is Vector2:
		return false
	var parsed_direction := direction_value as Vector2
	if not is_finite(parsed_direction.x) or not is_finite(parsed_direction.y) or parsed_direction.is_zero_approx():
		return false

	action_token = int(execution["action_token"])
	generation = int(execution["generation"])
	source_action_id = str(execution["source_action_id"])
	descriptor_id = str(execution["descriptor_id"])
	outcome_index = int(execution["outcome_index"])
	deterministic_seed = int(execution["deterministic_seed"])
	element_id = str(execution["element_id"])
	damage = float(execution["damage"])
	base_attack = float(execution["base_attack"])
	speed = float(execution["speed"])
	max_range_pixels = float(execution["max_range_pixels"])
	target_deduplication = str(execution["target_deduplication"])
	effect_descriptor = (execution["effect_descriptor"] as Dictionary).duplicate(true)
	combination = (execution["combination"] as Dictionary).duplicate(true)
	chain = (execution["chain"] as Dictionary).duplicate(true)
	var boss_conversion_value: Variant = execution.get("boss_conversion", {})
	if not boss_conversion_value is Dictionary:
		reset_execution_state()
		return false
	boss_conversion = (boss_conversion_value as Dictionary).duplicate(true)
	status_source_id = StringName(str(execution.get(
		"status_source_id",
		"staff:%d:%s:%d" % [action_token, descriptor_id, outcome_index]
	)))
	if status_source_id == &"":
		reset_execution_state()
		return false
	direction = parsed_direction.normalized()
	_execution_active = true
	monitoring = is_inside_tree()
	set_physics_process(is_inside_tree())
	return true


func execution_snapshot() -> Dictionary:
	return {
		"action_token": action_token,
		"generation": generation,
		"source_action_id": source_action_id,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"deterministic_seed": deterministic_seed,
		"element_id": element_id,
		"damage": damage,
		"base_attack": base_attack,
		"speed": speed,
		"max_range_pixels": max_range_pixels,
		"target_deduplication": target_deduplication,
		"effect_descriptor": effect_descriptor.duplicate(true),
		"combination": combination.duplicate(true),
		"chain": chain.duplicate(true),
		"status_source_id": status_source_id,
		"boss_conversion": boss_conversion.duplicate(true),
		"direction": direction,
		"distance_travelled": _distance_travelled,
		"hit_target_ids": _sorted_integer_keys(_hit_targets),
		"damage_claims": _sorted_string_keys(_damage_claims),
		"terminal_emitted": _terminal_emitted,
		"execution_active": _execution_active,
	}


func can_restore_execution_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, EXECUTION_SNAPSHOT_FIELDS):
		return false
	var staged := StaffProjectile.new()
	var configured := staged.configure_execution(value)
	if not configured:
		staged.free()
		return false
	var hit_ids_value: Variant = value.get("hit_target_ids")
	var damage_claims_value: Variant = value.get("damage_claims")
	var direction_value: Variant = value.get("direction")
	var distance_value: Variant = value.get("distance_travelled")
	var valid := (
		hit_ids_value is Array
		and damage_claims_value is Array
		and direction_value is Vector2
		and typeof(distance_value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(distance_value))
		and float(distance_value) >= 0.0
		and float(distance_value) <= float(value.get("max_range_pixels", 0.0)) + 0.001
		and typeof(value.get("terminal_emitted")) == TYPE_BOOL
		and typeof(value.get("execution_active")) == TYPE_BOOL
		and bool(value.get("execution_active", false)) != bool(value.get("terminal_emitted", false))
		and _valid_positive_integer_array(hit_ids_value)
		and _valid_claim_array(damage_claims_value)
	)
	if valid and not (hit_ids_value as Array).is_empty() and not bool(value.get("terminal_emitted", false)):
		valid = false
	if valid and bool(value.get("execution_active", false)) and float(distance_value) >= float(value.get("max_range_pixels", 0.0)):
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
	if not can_restore_execution_snapshot(value):
		return false
	if not configure_execution(value):
		return false
	direction = (value["direction"] as Vector2).normalized()
	_distance_travelled = float(value["distance_travelled"])
	_hit_targets.clear()
	for target_id_value: Variant in value["hit_target_ids"] as Array:
		_hit_targets[int(target_id_value)] = true
	_damage_claims.clear()
	for claim_value: Variant in value["damage_claims"] as Array:
		_damage_claims[str(claim_value)] = true
	_terminal_emitted = bool(value["terminal_emitted"])
	_execution_active = bool(value["execution_active"])
	rotation = direction.angle()
	monitoring = _execution_active and is_inside_tree()
	set_physics_process(_execution_active and is_inside_tree())
	return execution_snapshot() == value


func hit_for_test(target_id: int, candidates: Array = []) -> Dictionary:
	return _resolve_hit(target_id, candidates, 0.0, global_position)


func complete_without_hit_for_test() -> void:
	if not _execution_active or _terminal_emitted or not _hit_targets.is_empty():
		return
	_terminal_emitted = true
	_emit_result({
		"type": "terminal_miss",
		"claim_id": "terminal:%d" % outcome_index,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"element_id": element_id,
	})
	_retire()


func reset_execution_state() -> void:
	_execution_active = false
	_terminal_emitted = false
	_hit_targets.clear()
	_damage_claims.clear()
	_distance_travelled = 0.0
	action_token = 0
	generation = 0
	source_action_id = ""
	descriptor_id = ""
	outcome_index = 0
	deterministic_seed = 0
	element_id = ""
	effect_descriptor.clear()
	combination.clear()
	chain.clear()
	status_source_id = &""
	boss_conversion.clear()
	monitoring = false
	set_physics_process(false)


func _on_physical_area_entered(area: Area2D) -> void:
	NativeHitbox.dispatch_contact(_on_area_entered.bind(area))


func _on_area_entered(area: Area2D) -> void:
	if (
		not _execution_active
		or area == null
		or not is_instance_valid(area)
		or not area.has_method("receive_hit")
	):
		return
	var target := area.get_parent()
	if not Targets.is_attackable(target):
		return
	var target_id := _stable_target_id(target)
	if target_id <= 0 or _hit_targets.has(target_id):
		return
	_execute_target_hit(target)


func status_source_identity() -> Dictionary:
	return {
		"source_id": status_source_id,
		"generation": generation,
		"action_token": action_token,
	}


func _execute_target_hit(target: Node) -> Dictionary:
	if not _execution_active or target == null or not is_instance_valid(target):
		return {}
	var target_id := _stable_target_id(target)
	if target_id <= 0 or _hit_targets.has(target_id):
		return {}
	var impact_position := _target_position(target)
	var primary_damage := _deliver_damage_to_target(
		target,
		damage,
		element_id,
		_primary_knockback(target)
	)
	var candidates: Array[Dictionary] = []
	if Targets.is_arena_construct(target):
		return _resolve_hit(target_id, candidates, primary_damage, impact_position)
	match element_id:
		"fire":
			_execute_fire_impact(target)
		"lightning":
			_apply_elemental_status(
				target,
				&"shock",
				int(effect_descriptor.get("shock_duration_frames", 0)),
				float(effect_descriptor.get("shock_bonus_damage_multiplier", 0.0))
			)
			for chained_target: Node in _lightning_target_nodes(target):
				var chained_id := _stable_target_id(chained_target)
				var chained_position := _target_position(chained_target)
				var distance_tiles := _target_position(target).distance_to(chained_position) / PIXELS_PER_TILE
				candidates.append({
					"target_id": chained_id,
					"distance_tiles": distance_tiles,
					"impact_position": chained_position,
				})
				_resolve_derived_damage_once(
					chained_target,
					damage * float(chain.get("chain_damage_multiplier", 0.0)),
					"lightning",
					"lightning_chain"
				)
				_apply_elemental_status(
					chained_target,
					&"shock",
					int(effect_descriptor.get("shock_duration_frames", 0)),
					float(effect_descriptor.get("shock_bonus_damage_multiplier", 0.0))
				)
	return _resolve_hit(target_id, candidates, primary_damage, impact_position)


func _resolve_hit(
	target_id: int,
	candidates: Array,
	resolved_damage: float,
	impact_position: Vector2
) -> Dictionary:
	if not _execution_active or target_id <= 0 or _hit_targets.has(target_id):
		return {}
	_hit_targets[target_id] = true
	_terminal_emitted = true
	var result := {
		"type": "hit_confirmed",
		"claim_id": "hit:%d:%d" % [outcome_index, target_id],
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"target_id": target_id,
		"element_id": element_id,
		"element": element_id,
		"terminal": true,
		"hit": resolved_damage > 0.0,
		"damage": maxf(0.0, resolved_damage),
		"impact_position": impact_position,
		"deterministic_seed": deterministic_seed,
		"effect_descriptors": _effect_descriptors(),
		"chain_target_ids": [],
		"chain_target_impacts": [],
		"spawn_zone": {},
		"combination": combination.duplicate(true),
	}
	if element_id == "lightning":
		var chain_target_ids := _resolved_lightning_chain(target_id, candidates)
		result["chain_target_ids"] = chain_target_ids
		result["chain_target_impacts"] = _resolved_lightning_chain_impacts(chain_target_ids, candidates)
	if element_id == "ice":
		result["spawn_zone"] = _ice_zone_descriptor()
	_emit_result(result)
	_retire()
	return result.duplicate(true)


func _effect_descriptors() -> Array[Dictionary]:
	if element_id != "fire":
		return []
	return [
		{
			"effect_id": "fire_explosion",
			"kind": "explosion",
			"parameters": {
				"radius_tiles": float(effect_descriptor.get("explosion_radius_tiles", 0.0)),
				"damage_multiplier": float(effect_descriptor.get("explosion_damage_multiplier", 1.0)),
				"damage_type": "fire",
			},
		},
		{
			"effect_id": "burn",
			"kind": "status",
			"parameters": {
				"duration_frames": int(effect_descriptor.get("burn_duration_frames", 0)),
				"tick_interval_frames": int(effect_descriptor.get("burn_tick_interval_frames", 0)),
				"damage_multiplier": float(effect_descriptor.get("burn_damage_multiplier", 0.0)),
				"damage_type": "fire",
			},
		},
	]


func _ice_zone_descriptor() -> Dictionary:
	return {
		"mode": "ice_zone",
		"descriptor_id": "%s:ice_zone" % descriptor_id,
		"parameters": {
			"radius_tiles": float(effect_descriptor.get("zone_radius_tiles", 0.0)),
			"duration_frames": int(effect_descriptor.get("zone_duration_frames", 0)),
			"tick_interval_frames": int(effect_descriptor.get("zone_tick_interval_frames", 0)),
			"damage_multiplier": float(effect_descriptor.get("zone_damage_multiplier", 0.0)),
			"move_speed_multiplier": float(effect_descriptor.get("move_speed_multiplier", 1.0)),
			"attack_speed_multiplier": float(effect_descriptor.get("attack_speed_multiplier", 1.0)),
			"freeze_duration_frames": int(effect_descriptor.get("freeze_duration_frames", 0)),
		},
	}


func _resolved_lightning_chain(primary_target_id: int, candidates: Array) -> Array[int]:
	var maximum_count := int(chain.get("additional_target_count", 0))
	var maximum_distance := float(chain.get("chain_range_tiles", 0.0))
	if maximum_count <= 0 or maximum_distance <= 0.0:
		return []
	var closest_by_target: Dictionary = {}
	for candidate_value: Variant in candidates:
		if not candidate_value is Dictionary:
			continue
		var candidate := candidate_value as Dictionary
		var target_id := int(candidate.get("target_id", 0))
		var distance := float(candidate.get("distance_tiles", -1.0))
		if (
			target_id <= 0
			or target_id == primary_target_id
			or not is_finite(distance)
			or distance < 0.0
			or distance > maximum_distance
		):
			continue
		if not closest_by_target.has(target_id) or distance < float(closest_by_target[target_id]):
			closest_by_target[target_id] = distance
	var ordered: Array[Dictionary] = []
	for target_value: Variant in closest_by_target:
		ordered.append({
			"target_id": int(target_value),
			"distance_tiles": float(closest_by_target[target_value]),
		})
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_distance := float(left["distance_tiles"])
		var right_distance := float(right["distance_tiles"])
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left["target_id"]) < int(right["target_id"])
	)
	var result: Array[int] = []
	for candidate: Dictionary in ordered:
		if result.size() >= maximum_count:
			break
		result.append(int(candidate["target_id"]))
	return result


func _resolved_lightning_chain_impacts(target_ids: Array[int], candidates: Array) -> Array[Dictionary]:
	var candidate_positions: Dictionary = {}
	for candidate_value: Variant in candidates:
		if not candidate_value is Dictionary:
			continue
		var candidate := candidate_value as Dictionary
		var target_id := int(candidate.get("target_id", 0))
		var position_value: Variant = candidate.get("impact_position")
		if target_id <= 0 or candidate_positions.has(target_id) or not position_value is Vector2:
			continue
		var position := position_value as Vector2
		if not is_finite(position.x) or not is_finite(position.y):
			continue
		candidate_positions[target_id] = position
	var impacts: Array[Dictionary] = []
	for target_id: int in target_ids:
		if not candidate_positions.has(target_id):
			continue
		impacts.append({
			"target_id": target_id,
			"impact_position": candidate_positions[target_id] as Vector2,
		})
	return impacts


func _lightning_candidates(primary_target: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target: Node in _lightning_target_nodes(primary_target):
		result.append({
			"target_id": _stable_target_id(target),
			"distance_tiles": _target_position(primary_target).distance_to(_target_position(target)) / PIXELS_PER_TILE,
		})
	return result


func _execute_fire_impact(primary_target: Node) -> void:
	var radius_tiles := float(effect_descriptor.get("explosion_radius_tiles", 0.0))
	if radius_tiles <= 0.0:
		return
	var origin := _target_position(primary_target)
	var explosion_multiplier := float(effect_descriptor.get("explosion_damage_multiplier", 1.0))
	for target: Node in _targets_in_radius(origin, radius_tiles):
		if target != primary_target:
			var knockback := origin.direction_to(_target_position(target)) * float(effect_descriptor.get("knockback_tiles", 0.0)) * PIXELS_PER_TILE
			_resolve_derived_damage_once(
				target,
				damage * explosion_multiplier,
				"fire",
				"fire_splash",
				knockback,
				origin
			)
		_apply_elemental_status(
			target,
			&"burn",
			int(effect_descriptor.get("burn_duration_frames", 0)),
			base_attack * float(effect_descriptor.get("burn_damage_multiplier", 0.0)),
			int(effect_descriptor.get("burn_tick_interval_frames", 0))
		)


func _lightning_target_nodes(primary_target: Node) -> Array[Node]:
	if element_id != "lightning" or not is_inside_tree():
		return []
	var maximum_count := int(chain.get("additional_target_count", 0))
	var maximum_distance := float(chain.get("chain_range_tiles", 0.0))
	if maximum_count <= 0 or maximum_distance <= 0.0:
		return []
	var origin := _target_position(primary_target)
	var targets := _targets_in_radius(origin, maximum_distance)
	targets.erase(primary_target)
	targets.sort_custom(func(left: Node, right: Node) -> bool:
		var left_distance := origin.distance_squared_to(_target_position(left))
		var right_distance := origin.distance_squared_to(_target_position(right))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return _stable_target_id(left) < _stable_target_id(right)
	)
	if targets.size() > maximum_count:
		targets.resize(maximum_count)
	return targets


func _targets_in_radius(origin: Vector2, radius_tiles: float) -> Array[Node]:
	var result: Array[Node] = []
	if not is_inside_tree() or radius_tiles <= 0.0:
		return result
	var maximum_distance_squared := pow(radius_tiles * PIXELS_PER_TILE, 2.0)
	var seen: Dictionary = {}
	for candidate: Node in SceneScope.nodes_in_group(self, "enemies"):
		if candidate == null or not is_instance_valid(candidate) or not candidate is Node2D:
			continue
		var target_id := _stable_target_id(candidate)
		if target_id <= 0 or seen.has(target_id):
			continue
		if origin.distance_squared_to((candidate as Node2D).global_position) > maximum_distance_squared + 0.001:
			continue
		seen[target_id] = true
		result.append(candidate)
	result.sort_custom(func(left: Node, right: Node) -> bool:
		return _stable_target_id(left) < _stable_target_id(right)
	)
	return result


func _deliver_damage_to_target(
	target: Node,
	amount: float,
	damage_element: String,
	knockback: Vector2 = Vector2.ZERO
) -> float:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return 0.0
	var damage_type := DamageInfoScript.DamageType.PHYSICAL
	match damage_element:
		"fire":
			damage_type = DamageInfoScript.DamageType.FIRE
		"ice":
			damage_type = DamageInfoScript.DamageType.ICE
		"lightning":
			damage_type = DamageInfoScript.DamageType.LIGHTNING
	var damage_info = DamageInfoScript.from_plan({
		"run_id": &"runtime",
		"target_id": _damage_target_id(target),
		"hostile_source_id": StringName("player:staff:%d:%d" % [action_token, generation]),
		"attack_generation": generation,
		"hit_index": outcome_index,
		"action_token": action_token,
		"amount": amount,
		"damage_type": damage_type,
		"source": source,
		"attacker": owner_entity,
		"knockback": knockback,
		"tags": ["weapon:staff", "action:%s" % source_action_id, "element:%s" % damage_element],
		"source_generation": generation,
	})
	if damage_info == null:
		return 0.0
	var hurtbox := target.get_node_or_null("Hurtbox")
	if hurtbox != null and hurtbox.has_method("receive_hit"):
		return float(hurtbox.call("receive_hit", damage_info))
	if target.has_method("receive_hit"):
		return float(target.call("receive_hit", damage_info))
	var health := target.get_node_or_null("HealthComponent")
	if health != null and health.has_method("take_damage"):
		return float(health.call("take_damage", damage_info))
	return 0.0


func _resolve_derived_damage_once(
	target: Node,
	amount: float,
	damage_element: String,
	claim_scope: String,
	knockback: Vector2 = Vector2.ZERO,
	origin_position: Vector2 = Vector2.INF
) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var target_id := _stable_target_id(target)
	if target_id <= 0 or claim_scope.is_empty():
		return 0.0
	var claim := "damage:%d:%s:%s:%d" % [outcome_index, claim_scope, damage_element, target_id]
	if _damage_claims.has(claim):
		return 0.0
	_damage_claims[claim] = true
	var resolved_damage := _deliver_damage_to_target(
		target,
		amount,
		damage_element,
		knockback
	)
	var impact := _target_position(target)
	var origin := origin_position if origin_position != Vector2.INF else impact
	_emit_result({
		"type": "damage_resolved",
		"claim_id": claim,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"outcome_id": "%s:%d" % [descriptor_id, outcome_index],
		"target_id": target_id,
		"element_id": damage_element,
		"element": damage_element,
		"terminal": false,
		"hit": resolved_damage > 0.0,
		"damage": maxf(0.0, resolved_damage),
		"impact_position": impact,
		"origin_position": origin,
		"damage_scope": claim_scope,
	})
	return resolved_damage


func _apply_elemental_status(
	target: Node,
	effect_id: StringName,
	duration_frames: int,
	magnitude: float,
	tick_interval_frames: int = 30,
	attack_speed_multiplier: float = -1.0
) -> bool:
	if (
		target == null
		or not is_instance_valid(target)
		or status_source_id == &""
		or duration_frames <= 0
		or not target.has_method("apply_elemental_status")
	):
		return false
	if effect_id in [&"freeze", &"blind"] and not _boss_control_is_allowed(target):
		return false
	if effect_id == &"blind" and not _ensure_elemental_blind_seed(target):
		return false
	return bool(target.call(
		"apply_elemental_status",
		effect_id,
		status_source_id,
		generation,
		duration_frames,
		magnitude,
		maxi(1, tick_interval_frames),
		attack_speed_multiplier,
		source,
		owner_entity
	))


func _boss_control_is_allowed(target: Node) -> bool:
	if not target.is_in_group("bosses") or boss_conversion.is_empty():
		return true
	if not target.has_method("get_boss_ui_snapshot"):
		return false
	var snapshot_value: Variant = target.call("get_boss_ui_snapshot")
	if not snapshot_value is Dictionary:
		return false
	var snapshot := snapshot_value as Dictionary
	var phase := str(snapshot.get("phase", ""))
	if phase == "WINDUP" and bool(boss_conversion.get("preserve_committed_active_attack", true)):
		return false
	var conversion_state := "EXPOSED" if bool(snapshot.get("exposed", false)) else phase
	var allowed_value: Variant = boss_conversion.get("allowed_states", ["RECOVERY", "EXPOSED"])
	return allowed_value is Array and conversion_state in (allowed_value as Array)


func _primary_knockback(target: Node) -> Vector2:
	var tiles := float(effect_descriptor.get("knockback_tiles", 0.0))
	if tiles <= 0.0:
		return Vector2.ZERO
	var resolved_direction := direction.normalized()
	if resolved_direction.is_zero_approx():
		resolved_direction = global_position.direction_to(_target_position(target))
	return resolved_direction * tiles * PIXELS_PER_TILE


func _target_position(target: Node) -> Vector2:
	return (target as Node2D).global_position if target is Node2D else global_position


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		return int(target.get_meta("stable_target_id"))
	var stable_key := _stable_target_key(target)
	if not stable_key.is_empty():
		return maxi(1, _stable_hash(stable_key))
	return target.get_instance_id()


func _damage_target_id(target: Node) -> StringName:
	if target != null and target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return StringName("target:%d" % int(value))
	for metadata_key: String in ["encounter_spawn_id", "spawn_id"]:
		if target != null and target.has_meta(metadata_key):
			var metadata_value := str(target.get_meta(metadata_key, "")).strip_edges()
			if not metadata_value.is_empty() and metadata_value.length() <= 56:
				return StringName("target:%s" % metadata_value)
	return &"pending_target"


func _ensure_elemental_blind_seed(target: Node) -> bool:
	if target.has_meta("elemental_status_seed_initialized"):
		return true
	if not target.has_method("configure_elemental_status_seed"):
		return false
	var target_key := _stable_target_key(target)
	if target_key.is_empty():
		return false
	var resolved_seed := _stable_hash("%d|%s" % [deterministic_seed, target_key])
	target.call("configure_elemental_status_seed", resolved_seed, 0.30)
	target.set_meta("elemental_status_seed_initialized", resolved_seed)
	target.set_meta("elemental_status_seed_material", target_key)
	return true


func _stable_target_key(target: Node) -> String:
	if target.has_meta("stable_target_id"):
		return "stable:%s" % str(target.get_meta("stable_target_id"))
	for metadata_key: String in ["encounter_spawn_id", "spawn_id"]:
		if target.has_meta(metadata_key):
			var metadata_value := str(target.get_meta(metadata_key, ""))
			if not metadata_value.is_empty():
				return "%s:%s" % [metadata_key, metadata_value]
	if target.is_inside_tree():
		var path := str(target.get_path())
		if not path.is_empty():
			return "path:%s" % path
	return ""


func _stable_hash(material: String) -> int:
	var value := 0
	for index: int in range(material.length()):
		value = int((value * 131 + material.unicode_at(index)) % 2147483647)
	return value


func _emit_result(result: Dictionary) -> void:
	payload_result.emit(action_token, generation, result.duplicate(true))


func _retire() -> void:
	_execution_active = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _sorted_integer_keys(values: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	result.sort()
	return result


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _valid_positive_integer_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	var previous := 0
	for item: Variant in value as Array:
		if typeof(item) != TYPE_INT or int(item) <= 0 or seen.has(int(item)):
			return false
		if not seen.is_empty() and int(item) <= previous:
			return false
		seen[int(item)] = true
		previous = int(item)
	return true


func _valid_claim_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	var previous := ""
	for item: Variant in value as Array:
		if typeof(item) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var claim := str(item)
		if claim.is_empty() or seen.has(claim) or (not previous.is_empty() and claim <= previous):
			return false
		seen[claim] = true
		previous = claim
	return true


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0
