class_name GauntletsZoneExecution
extends Area2D

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

signal payload_result(action_token: int, generation: int, result: Dictionary)

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const PIXELS_PER_TILE := 64.0
const VALID_MODES: Array[String] = [
	"space_time_shatter",
	"primordial_collapse",
	"charged_heavy_shockwave",
	"rewind_counter_shockwave",
]
const EXECUTION_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "action_token", "generation", "source_action_id", "descriptor_id",
	"outcome_id", "outcome_index", "deterministic_seed", "mode", "parameters", "base_attack",
	"source_id", "execution_frame", "duration_frames", "remaining_frames", "tick_interval_frames",
	"fractional_frames", "execution_active", "damage_claim_keys",
]

var action_token: int = 0
var generation: int = 0
var source_action_id: String = ""
var descriptor_id: String = ""
var outcome_id: String = ""
var outcome_index: int = 0
var deterministic_seed: int = 0
var mode: String = ""
var parameters: Dictionary = {}
var base_attack: float = 6.0
var source: Node
var owner_entity: Node

var _execution_active: bool = false
var _execution_frame: int = 0
var _fractional_frames: float = 0.0
var _duration_frames: int = 0
var _tick_interval_frames: int = 0
var _slow_targets: Dictionary = {}
var _damage_claims: Dictionary = {}
var _source_id: StringName = &""
var _collision_shape: CollisionShape2D


func _ready() -> void:
	add_to_group("gauntlets_payloads")
	add_to_group("gauntlets_zones")
	set_physics_process(_execution_active)


func _physics_process(delta: float) -> void:
	if not _execution_active or delta <= 0.0:
		return
	_fractional_frames += delta * 60.0
	var frames := int(floorf(_fractional_frames))
	if frames <= 0:
		return
	_fractional_frames -= float(frames)
	advance_execution_for_test(frames)


func configure_execution(execution: Dictionary) -> bool:
	reset_execution_state()
	for field: String in [
		"action_token",
		"generation",
		"source_action_id",
		"descriptor_id",
		"outcome_index",
		"deterministic_seed",
		"mode",
		"parameters",
		"base_attack",
	]:
		if not execution.has(field):
			return false
	if (
		typeof(execution["action_token"]) != TYPE_INT
		or int(execution["action_token"]) <= 0
		or typeof(execution["generation"]) != TYPE_INT
		or int(execution["generation"]) <= 0
		or str(execution["source_action_id"]).is_empty()
		or str(execution["descriptor_id"]).is_empty()
		or typeof(execution["outcome_index"]) != TYPE_INT
		or int(execution["outcome_index"]) < 0
		or typeof(execution["deterministic_seed"]) != TYPE_INT
		or str(execution["mode"]) not in VALID_MODES
		or not execution["parameters"] is Dictionary
		or not _positive_number(execution["base_attack"])
	):
		return false
	var parsed := (execution["parameters"] as Dictionary).duplicate(true)
	if not _parameters_are_valid(parsed):
		return false
	action_token = int(execution["action_token"])
	generation = int(execution["generation"])
	source_action_id = str(execution["source_action_id"])
	descriptor_id = str(execution["descriptor_id"])
	outcome_id = str(execution.get("outcome_id", "%s:%d" % [descriptor_id, int(execution["outcome_index"])]))
	outcome_index = int(execution["outcome_index"])
	deterministic_seed = int(execution["deterministic_seed"])
	mode = str(execution["mode"])
	parameters = parsed
	base_attack = float(execution["base_attack"])
	var source_value: Variant = execution.get("source")
	source = source_value as Node if source_value is Node else null
	var owner_value: Variant = execution.get("owner_entity")
	owner_entity = owner_value as Node if owner_value is Node else null
	_duration_frames = int(parameters["duration_frames"])
	_tick_interval_frames = int(parameters["tick_interval_frames"])
	_source_id = StringName("gauntlets_zone:%d:%d:%s" % [action_token, generation, descriptor_id])
	_execution_active = true
	_configure_collision()
	set_physics_process(is_inside_tree())
	return true


func advance_execution_for_test(frames: int) -> void:
	if not _execution_active or frames <= 0:
		return
	for _frame: int in range(frames):
		if not _execution_active:
			break
		_execution_frame += 1
		_maintain_slow()
		if _execution_frame % _tick_interval_frames == 0:
			_tick_damage()
		if _execution_frame >= _duration_frames:
			_complete()


func execution_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"action_token": action_token,
		"generation": generation,
		"source_action_id": source_action_id,
		"descriptor_id": descriptor_id,
		"outcome_id": outcome_id,
		"outcome_index": outcome_index,
		"deterministic_seed": deterministic_seed,
		"mode": mode,
		"parameters": parameters.duplicate(true),
		"base_attack": base_attack,
		"source_id": _source_id,
		"execution_frame": _execution_frame,
		"duration_frames": _duration_frames,
		"remaining_frames": maxi(0, _duration_frames - _execution_frame),
		"tick_interval_frames": _tick_interval_frames,
		"fractional_frames": _fractional_frames,
		"execution_active": _execution_active,
		"damage_claim_keys": _sorted_string_keys(_damage_claims),
	}


func can_restore_execution_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, EXECUTION_SNAPSHOT_FIELDS):
		return false
	if (
		int(value.get("schema_version", -1)) != 1
		or typeof(value.get("action_token")) != TYPE_INT
		or int(value.get("action_token", 0)) <= 0
		or typeof(value.get("generation")) != TYPE_INT
		or int(value.get("generation", 0)) <= 0
		or str(value.get("source_action_id", "")).is_empty()
		or str(value.get("descriptor_id", "")).is_empty()
		or str(value.get("outcome_id", "")).is_empty()
		or typeof(value.get("outcome_index")) != TYPE_INT
		or int(value.get("outcome_index", -1)) < 0
		or typeof(value.get("deterministic_seed")) != TYPE_INT
		or str(value.get("mode", "")) not in VALID_MODES
		or not value.get("parameters") is Dictionary
		or not _positive_number(value.get("base_attack"))
		or typeof(value.get("execution_frame")) != TYPE_INT
		or typeof(value.get("duration_frames")) != TYPE_INT
		or typeof(value.get("remaining_frames")) != TYPE_INT
		or typeof(value.get("tick_interval_frames")) != TYPE_INT
		or typeof(value.get("fractional_frames")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value.get("fractional_frames", NAN)))
		or float(value.get("fractional_frames", -1.0)) < 0.0
		or float(value.get("fractional_frames", 1.0)) >= 1.0
		or typeof(value.get("execution_active")) != TYPE_BOOL
		or not bool(value.get("execution_active", false))
		or not value.get("damage_claim_keys") is Array
	):
		return false
	var parsed := value["parameters"] as Dictionary
	if not _parameters_are_valid(parsed):
		return false
	var execution_frame := int(value["execution_frame"])
	var duration_frames := int(parsed["duration_frames"])
	var tick_interval_frames := int(parsed["tick_interval_frames"])
	if (
		int(value["duration_frames"]) != duration_frames
		or int(value["tick_interval_frames"]) != tick_interval_frames
		or execution_frame < 0
		or execution_frame >= duration_frames
		or int(value["remaining_frames"]) != duration_frames - execution_frame
		or str(value.get("source_id", "")) != "gauntlets_zone:%d:%d:%s" % [
			int(value["action_token"]), int(value["generation"]), str(value["descriptor_id"])
		]
		or not _valid_sorted_claim_keys(value["damage_claim_keys"])
	):
		return false
	return _variant_numbers_are_finite(value)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func restore_execution_snapshot(value: Dictionary, dependencies: Dictionary) -> bool:
	if not can_restore_execution_snapshot(value):
		return false
	var execution := {
		"action_token": int(value["action_token"]),
		"generation": int(value["generation"]),
		"source_action_id": str(value["source_action_id"]),
		"descriptor_id": str(value["descriptor_id"]),
		"outcome_id": str(value["outcome_id"]),
		"outcome_index": int(value["outcome_index"]),
		"deterministic_seed": int(value["deterministic_seed"]),
		"mode": str(value["mode"]),
		"parameters": (value["parameters"] as Dictionary).duplicate(true),
		"base_attack": float(value["base_attack"]),
		"source": dependencies.get("source"),
		"owner_entity": dependencies.get("owner_entity"),
	}
	if not configure_execution(execution):
		return false
	_execution_frame = int(value["execution_frame"])
	_fractional_frames = float(value["fractional_frames"])
	_damage_claims.clear()
	for claim_key: Variant in value["damage_claim_keys"]:
		_damage_claims[str(claim_key)] = true
	return execution_snapshot() == value


func reset_execution_state() -> void:
	_clear_slow_targets()
	_execution_active = false
	_execution_frame = 0
	_fractional_frames = 0.0
	_duration_frames = 0
	_tick_interval_frames = 0
	_damage_claims.clear()
	action_token = 0
	generation = 0
	source_action_id = ""
	descriptor_id = ""
	outcome_id = ""
	outcome_index = 0
	deterministic_seed = 0
	mode = ""
	parameters.clear()
	base_attack = 6.0
	source = null
	owner_entity = null
	_source_id = &""
	set_physics_process(false)
	if is_instance_valid(_collision_shape):
		_collision_shape.queue_free()
	_collision_shape = null


func _exit_tree() -> void:
	reset_execution_state()


func _maintain_slow() -> void:
	var current: Dictionary = {}
	var multiplier := clampf(float(parameters.get("move_speed_multiplier", 1.0)), 0.1, 1.0)
	for target: Node in _targets_in_radius():
		var target_id := _stable_target_id(target)
		current[target_id] = target
		if target.has_method("apply_time_rift"):
			target.call("apply_time_rift", _source_id, multiplier)
	for target_id: Variant in _slow_targets:
		if current.has(target_id):
			continue
		var target_value: Variant = _slow_targets[target_id]
		if is_instance_valid(target_value) and target_value is Node and (target_value as Node).has_method("clear_time_rift"):
			(target_value as Node).call("clear_time_rift", _source_id)
	_slow_targets = current


func _tick_damage() -> void:
	var tick_index := _execution_frame / _tick_interval_frames
	for target: Node in _targets_in_radius():
		var target_id := _stable_target_id(target)
		var claim := "%d:%d" % [tick_index, target_id]
		if _damage_claims.has(claim):
			continue
		_damage_claims[claim] = true
		var resolved := _deliver_damage(target)
		payload_result.emit(action_token, generation, {
			"type": "damage_resolved",
			"claim_id": "zone:%d:%d:%d" % [outcome_index, tick_index, target_id],
			"descriptor_id": descriptor_id,
			"outcome_id": "%s:tick:%d" % [outcome_id, tick_index],
			"outcome_index": outcome_index,
			"target_id": target_id,
			"terminal": false,
			"hit": resolved > 0.0,
			"hit_confirmed": resolved > 0.0,
			"damage": maxf(0.0, resolved),
			"impact_position": _target_position(target),
			"execution_frame": _execution_frame,
			"deterministic_seed": deterministic_seed,
			"combo_gain": 0,
			"energy_return": 0.0,
			"stop_extension_frames": 0,
			"combo_eligible": false,
			"energy_eligible": false,
			"stop_extension_eligible": false,
			"recursive_echo": false,
			"is_echo": false,
			"spatial_context": {
				"center": global_position,
				"radius_pixels": float(parameters["radius_tiles"]) * PIXELS_PER_TILE,
				"source_generation": int(parameters.get("rift_source_generation", 0)),
			},
		})


func _deliver_damage(target: Node) -> float:
	var multiplier := float(parameters["damage_multiplier"])
	var split := parameters.get("damage_type_split", {"time": 1.0}) as Dictionary
	var total := 0.0
	for damage_name: String in ["physical", "time", "void"]:
		var ratio := float(split.get(damage_name, 0.0))
		if ratio <= 0.0:
			continue
		var info = DamageInfoScript.from_plan({
			"run_id": &"runtime",
			"target_id": _damage_target_id(target),
			"hostile_source_id": StringName("player:gauntlets_zone:%d:%d" % [action_token, generation]),
			"attack_generation": maxi(1, generation + _execution_frame),
			"hit_index": outcome_index,
			"action_token": action_token,
			"amount": base_attack * multiplier * ratio,
			"damage_type": _damage_type_from_name(damage_name),
			"source": source,
			"attacker": owner_entity,
			"can_crit": false,
			"tags": [
				"weapon:gauntlets",
				"action:%s" % source_action_id,
				"attack:gauntlets_zone",
				"non_recursive:combo",
				"non_recursive:energy",
				"non_recursive:stop_extension",
			],
			"source_generation": generation,
		})
		if info == null:
			continue
		total += _deliver_to_target(target, info)
	return total


func _deliver_to_target(target: Node, damage_info: RefCounted) -> float:
	if target.has_method("receive_hit"):
		return float(target.call("receive_hit", damage_info))
	for child: Node in target.get_children():
		if child.has_method("receive_hit"):
			return float(child.call("receive_hit", damage_info))
	var health := target.get_node_or_null("HealthComponent")
	if health != null and health.has_method("take_damage"):
		return float(health.call("take_damage", damage_info))
	return 0.0


func _targets_in_radius() -> Array[Node]:
	var targets: Array[Node] = []
	if not is_inside_tree():
		return targets
	var radius := float(parameters.get("radius_tiles", 0.0)) * PIXELS_PER_TILE
	for target: Node in SceneScope.nodes_in_group(self, "enemies"):
		if target == null or not is_instance_valid(target) or not target is Node2D:
			continue
		if (target as Node2D).global_position.distance_to(global_position) <= radius + 0.001:
			targets.append(target)
	targets.sort_custom(func(a: Node, b: Node) -> bool: return _stable_target_id(a) < _stable_target_id(b))
	return targets


func _clear_slow_targets() -> void:
	for target_value: Variant in _slow_targets.values():
		if is_instance_valid(target_value) and target_value is Node and (target_value as Node).has_method("clear_time_rift"):
			(target_value as Node).call("clear_time_rift", _source_id)
	_slow_targets.clear()


func _complete() -> void:
	_clear_slow_targets()
	_execution_active = false
	set_physics_process(false)
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _configure_collision() -> void:
	_collision_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = float(parameters["radius_tiles"]) * PIXELS_PER_TILE
	_collision_shape.shape = circle
	add_child(_collision_shape)


func _parameters_are_valid(values: Dictionary) -> bool:
	if (
		not _positive_number(values.get("radius_tiles"))
		or typeof(values.get("duration_frames")) != TYPE_INT
		or int(values.get("duration_frames", 0)) <= 0
		or typeof(values.get("tick_interval_frames")) != TYPE_INT
		or int(values.get("tick_interval_frames", 0)) <= 0
		or int(values.get("tick_interval_frames", 0)) > int(values.get("duration_frames", 0))
		or not _non_negative_number(values.get("damage_multiplier"))
	):
		return false
	var split_value: Variant = values.get("damage_type_split", {"time": 1.0})
	if not split_value is Dictionary:
		return false
	var total := 0.0
	for key: Variant in split_value:
		if str(key) not in ["physical", "time", "void"] or not _non_negative_number((split_value as Dictionary)[key]):
			return false
		total += float((split_value as Dictionary)[key])
	return is_equal_approx(total, 1.0)


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return int(value)
	return target.get_instance_id()


func _damage_target_id(target: Node) -> StringName:
	if target != null and target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return StringName("target:%d" % int(value))
	return &"pending_target"


func _target_position(target: Node) -> Vector2:
	return (target as Node2D).global_position if target is Node2D else global_position


func _damage_type_from_name(damage_name: String) -> int:
	match damage_name:
		"time":
			return DamageInfoScript.DamageType.TIME
		"void":
			return DamageInfoScript.DamageType.VOID
	return DamageInfoScript.DamageType.PHYSICAL


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _non_negative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in values.keys():
		result.append(str(key))
	result.sort()
	return result


func _valid_sorted_claim_keys(value: Array) -> bool:
	var previous := ""
	for claim_key: Variant in value:
		if typeof(claim_key) != TYPE_STRING or str(claim_key).is_empty():
			return false
		if not previous.is_empty() and str(claim_key) <= previous:
			return false
		previous = str(claim_key)
	return true


func _variant_numbers_are_finite(value: Variant) -> bool:
	if typeof(value) in [TYPE_FLOAT, TYPE_VECTOR2]:
		if value is Vector2:
			return is_finite((value as Vector2).x) and is_finite((value as Vector2).y)
		return is_finite(float(value))
	if value is Dictionary:
		for child: Variant in (value as Dictionary).values():
			if not _variant_numbers_are_finite(child):
				return false
	if value is Array:
		for child: Variant in value:
			if not _variant_numbers_are_finite(child):
				return false
	return true
