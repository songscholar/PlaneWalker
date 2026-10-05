class_name GauntletsHitExecution
extends Area2D

signal payload_result(action_token: int, generation: int, result: Dictionary)
signal execution_finished(action_token: int, generation: int)

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const Targets := preload("res://scripts/combat/weapon_target_policy.gd")
const PIXELS_PER_TILE := 64.0
const VALID_ACTION_IDS: Array[String] = [
	"punch_1",
	"punch_2",
	"punch_3",
	"punch_4",
	"punch_5",
	"charged_heavy",
	"dodge_counter",
	"space_time_shatter",
	"primordial_collapse_punch",
]
const VALID_KINDS: Array[String] = ["hitbox", "shockwave"]
const PROGRESS_CLAIM_LIMIT := 512
const EXECUTION_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "action_token", "generation", "source_action_id", "descriptor_id",
	"outcome_id", "outcome_index", "deterministic_seed", "kind", "parameters", "base_attack",
	"direction", "target_deduplication", "boss_conversion", "combo_eligible", "energy_eligible",
	"stop_extension_eligible", "recursive_echo", "is_echo", "execution_frame", "active_frames",
	"remaining_frames", "fractional_frames", "execution_active", "completion_emitted",
	"hit_target_ids", "spatial_context",
]
const DEFAULT_GEOMETRY := {
	"punch_1": {"shape": "rectangle", "range_tiles": 1.5, "width_tiles": 1.0},
	"punch_2": {"shape": "rectangle", "range_tiles": 1.5, "width_tiles": 1.0},
	"punch_3": {"shape": "arc", "range_tiles": 1.8, "arc_degrees": 120.0},
	"punch_4": {"shape": "arc", "range_tiles": 1.8, "arc_degrees": 120.0},
	"punch_5": {"shape": "rectangle", "range_tiles": 2.0, "width_tiles": 1.2},
	"charged_heavy": {"shape": "rectangle", "range_tiles": 2.5, "width_tiles": 1.5},
	"dodge_counter": {"shape": "arc", "range_tiles": 2.0, "arc_degrees": 180.0},
	"space_time_shatter": {"shape": "rectangle", "range_tiles": 3.0, "width_tiles": 2.0},
	"primordial_collapse_punch": {"shape": "rectangle", "range_tiles": 5.0, "width_tiles": 3.0},
}
const DEFAULT_ACTIVE_FRAMES := {
	"punch_1": 3,
	"punch_2": 3,
	"punch_3": 4,
	"punch_4": 4,
	"punch_5": 6,
	"charged_heavy": 5,
	"dodge_counter": 5,
	"space_time_shatter": 8,
	"primordial_collapse_punch": 10,
}

var action_token: int = 0
var generation: int = 0
var source_action_id: String = ""
var descriptor_id: String = ""
var outcome_id: String = ""
var outcome_index: int = 0
var deterministic_seed: int = 0
var kind: String = ""
var parameters: Dictionary = {}
var base_attack: float = 6.0
var direction: Vector2 = Vector2.RIGHT
var source: Node
var owner_entity: Node
var target_deduplication: String = "per_action_target"
var boss_conversion: Dictionary = {}
var progress_claims: Dictionary = {}
var progress_claim_order: Array = []
var damage_claims: Dictionary = {}
var damage_claim_order: Array = []

var _execution_active: bool = false
var _execution_frame: int = 0
var _active_frames: int = 0
var _hit_targets: Dictionary = {}
var _fractional_frames: float = 0.0
var _collision_shape: CollisionShape2D
var _completion_emitted: bool = false


func _ready() -> void:
	add_to_group("gauntlets_payloads")
	add_to_group("gauntlets_hit_executions")
	area_entered.connect(_on_area_entered)
	monitoring = _execution_active
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
		"kind",
		"parameters",
		"base_attack",
		"direction",
		"target_deduplication",
		"progress_claims",
		"progress_claim_order",
		"damage_claims",
		"damage_claim_order",
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
		or str(execution["kind"]) not in VALID_KINDS
		or not execution["parameters"] is Dictionary
		or not _positive_number(execution["base_attack"])
		or not execution["direction"] is Vector2
		or (execution["direction"] as Vector2).is_zero_approx()
		or str(execution["target_deduplication"]) != "per_action_target"
		or not execution["progress_claims"] is Dictionary
		or not execution["progress_claim_order"] is Array
		or not execution["damage_claims"] is Dictionary
		or not execution["damage_claim_order"] is Array
	):
		return false
	var parsed_parameters := (execution["parameters"] as Dictionary).duplicate(true)
	if not _parameters_are_valid(parsed_parameters, str(execution["source_action_id"])):
		return false

	action_token = int(execution["action_token"])
	generation = int(execution["generation"])
	source_action_id = str(execution["source_action_id"])
	descriptor_id = str(execution["descriptor_id"])
	outcome_id = str(execution.get("outcome_id", "%s:%d" % [descriptor_id, int(execution["outcome_index"])]))
	if outcome_id.is_empty():
		reset_execution_state()
		return false
	outcome_index = int(execution["outcome_index"])
	deterministic_seed = int(execution["deterministic_seed"])
	kind = str(execution["kind"])
	parameters = parsed_parameters
	base_attack = float(execution["base_attack"])
	direction = (execution["direction"] as Vector2).normalized()
	target_deduplication = str(execution["target_deduplication"])
	progress_claims = execution["progress_claims"]
	progress_claim_order = execution["progress_claim_order"]
	damage_claims = execution["damage_claims"]
	damage_claim_order = execution["damage_claim_order"]
	var source_value: Variant = execution.get("source")
	source = source_value as Node if source_value is Node else null
	var owner_value: Variant = execution.get("owner_entity")
	owner_entity = owner_value as Node if owner_value is Node else null
	var conversion_value: Variant = execution.get("boss_conversion", {})
	if not conversion_value is Dictionary:
		reset_execution_state()
		return false
	boss_conversion = (conversion_value as Dictionary).duplicate(true)
	_active_frames = int(parameters.get("active_frames", DEFAULT_ACTIVE_FRAMES[source_action_id]))
	_execution_active = true
	_configure_collision()
	monitoring = is_inside_tree()
	set_physics_process(is_inside_tree())
	return true


func execute_target_for_test(target: Node) -> Dictionary:
	return _execute_target_hit(target)


func advance_execution_for_test(frames: int) -> void:
	if not _execution_active or frames <= 0:
		return
	_execution_frame += frames
	if _execution_frame >= _active_frames:
		_retire()


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
		"kind": kind,
		"parameters": parameters.duplicate(true),
		"base_attack": base_attack,
		"direction": direction,
		"target_deduplication": target_deduplication,
		"boss_conversion": boss_conversion.duplicate(true),
		"combo_eligible": bool(parameters.get("combo_eligible", false)),
		"energy_eligible": bool(parameters.get("energy_eligible", false)),
		"stop_extension_eligible": bool(parameters.get("stop_extension_eligible", false)),
		"recursive_echo": bool(parameters.get("recursive_echo", false)),
		"is_echo": bool(parameters.get("is_echo", false)),
		"execution_frame": _execution_frame,
		"active_frames": _active_frames,
		"remaining_frames": maxi(0, _active_frames - _execution_frame),
		"fractional_frames": _fractional_frames,
		"execution_active": _execution_active,
		"completion_emitted": _completion_emitted,
		"hit_target_ids": _sorted_integer_keys(_hit_targets),
		"spatial_context": _spatial_context(global_position),
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
		or str(value.get("source_action_id", "")) not in VALID_ACTION_IDS
		or str(value.get("descriptor_id", "")).is_empty()
		or str(value.get("outcome_id", "")).is_empty()
		or typeof(value.get("outcome_index")) != TYPE_INT
		or int(value.get("outcome_index", -1)) < 0
		or typeof(value.get("deterministic_seed")) != TYPE_INT
		or str(value.get("kind", "")) not in VALID_KINDS
		or not value.get("parameters") is Dictionary
		or not _positive_number(value.get("base_attack"))
		or not value.get("direction") is Vector2
		or (value.get("direction") as Vector2).is_zero_approx()
		or str(value.get("target_deduplication", "")) != "per_action_target"
		or not value.get("boss_conversion", {}) is Dictionary
		or typeof(value.get("execution_frame")) != TYPE_INT
		or typeof(value.get("active_frames")) != TYPE_INT
		or typeof(value.get("remaining_frames")) != TYPE_INT
		or typeof(value.get("fractional_frames")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value.get("fractional_frames", NAN)))
		or float(value.get("fractional_frames", -1.0)) < 0.0
		or float(value.get("fractional_frames", 1.0)) >= 1.0
		or typeof(value.get("execution_active")) != TYPE_BOOL
		or not bool(value.get("execution_active", false))
		or typeof(value.get("completion_emitted")) != TYPE_BOOL
		or bool(value.get("completion_emitted", true))
		or not value.get("hit_target_ids") is Array
		or not value.get("spatial_context") is Dictionary
	):
		return false
	var parsed_parameters := value["parameters"] as Dictionary
	if not _parameters_are_valid(parsed_parameters, str(value["source_action_id"])):
		return false
	var expected_active_frames := int(parsed_parameters.get(
		"active_frames", DEFAULT_ACTIVE_FRAMES[str(value["source_action_id"])]
	))
	var execution_frame := int(value["execution_frame"])
	if (
		int(value["active_frames"]) != expected_active_frames
		or execution_frame < 0
		or execution_frame >= expected_active_frames
		or int(value["remaining_frames"]) != expected_active_frames - execution_frame
		or not _valid_sorted_positive_ids(value["hit_target_ids"])
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
	if (
		not can_restore_execution_snapshot(value)
		or not dependencies.get("progress_claims") is Dictionary
		or not dependencies.get("progress_claim_order") is Array
		or not dependencies.get("damage_claims") is Dictionary
		or not dependencies.get("damage_claim_order") is Array
	):
		return false
	var execution := {
		"action_token": int(value["action_token"]),
		"generation": int(value["generation"]),
		"source_action_id": str(value["source_action_id"]),
		"descriptor_id": str(value["descriptor_id"]),
		"outcome_id": str(value["outcome_id"]),
		"outcome_index": int(value["outcome_index"]),
		"deterministic_seed": int(value["deterministic_seed"]),
		"kind": str(value["kind"]),
		"parameters": (value["parameters"] as Dictionary).duplicate(true),
		"base_attack": float(value["base_attack"]),
		"direction": value["direction"],
		"target_deduplication": str(value["target_deduplication"]),
		"boss_conversion": (value["boss_conversion"] as Dictionary).duplicate(true),
		"source": dependencies.get("source"),
		"owner_entity": dependencies.get("owner_entity"),
		"progress_claims": dependencies["progress_claims"],
		"progress_claim_order": dependencies["progress_claim_order"],
		"damage_claims": dependencies["damage_claims"],
		"damage_claim_order": dependencies["damage_claim_order"],
	}
	if not configure_execution(execution):
		return false
	_execution_frame = int(value["execution_frame"])
	_fractional_frames = float(value["fractional_frames"])
	_completion_emitted = false
	_hit_targets.clear()
	for target_id: Variant in value["hit_target_ids"]:
		_hit_targets[int(target_id)] = true
	return execution_snapshot() == value


func reset_execution_state() -> void:
	_execution_active = false
	_execution_frame = 0
	_active_frames = 0
	_fractional_frames = 0.0
	_completion_emitted = false
	_hit_targets.clear()
	action_token = 0
	generation = 0
	source_action_id = ""
	descriptor_id = ""
	outcome_id = ""
	outcome_index = 0
	deterministic_seed = 0
	kind = ""
	parameters.clear()
	base_attack = 6.0
	direction = Vector2.RIGHT
	source = null
	owner_entity = null
	target_deduplication = "per_action_target"
	boss_conversion.clear()
	progress_claims = {}
	progress_claim_order = []
	damage_claims = {}
	damage_claim_order = []
	monitoring = false
	set_physics_process(false)
	if is_instance_valid(_collision_shape):
		_collision_shape.queue_free()
	_collision_shape = null


func _on_area_entered(area: Area2D) -> void:
	if not _execution_active or area == null or not is_instance_valid(area) or not area.has_method("receive_hit"):
		return
	var target := area.get_parent()
	if not Targets.is_attackable(target):
		return
	_execute_target_hit(target)


func _execute_target_hit(target: Node) -> Dictionary:
	if not _execution_active or not Targets.is_attackable(target):
		return {}
	var target_id := _stable_target_id(target)
	if target_id <= 0 or _hit_targets.has(target_id) or not _target_inside_geometry(target):
		return {}
	_hit_targets[target_id] = true
	if bool(parameters.get("shared_damage_claim", false)) and not _claim_damage_once(target_id):
		var duplicate_zone := _zone_descriptor(_target_position(target))
		if not duplicate_zone.is_empty():
			var duplicate_result := {
				"type": "damage_claim_duplicate",
				"claim_id": "duplicate:%d:%d" % [outcome_index, target_id],
				"descriptor_id": descriptor_id,
				"outcome_id": outcome_id,
				"outcome_index": outcome_index,
				"target_id": target_id,
				"terminal": false,
				"hit": false,
				"hit_confirmed": false,
				"damage": 0.0,
				"impact_position": _target_position(target),
				"deterministic_seed": deterministic_seed,
				"combo_gain": 0,
				"energy_return": 0.0,
				"stop_extension_frames": 0,
				"combo_eligible": false,
				"energy_eligible": false,
				"stop_extension_eligible": false,
				"recursive_echo": false,
				"is_echo": false,
				"control_effect": {},
				"spatial_context": _spatial_context(_target_position(target)),
				"spawn_zone": duplicate_zone,
			}
			payload_result.emit(action_token, generation, duplicate_result.duplicate(true))
			return duplicate_result
		return {}
	var impact_position := _target_position(target)
	var resolved_damage := _deliver_damage_components(target)
	var eligible_claimed := not Targets.is_arena_construct(target) and _claim_progress_once(target_id)
	var combo_eligible := bool(parameters.get("combo_eligible", false)) and eligible_claimed
	var energy_eligible := bool(parameters.get("energy_eligible", false)) and eligible_claimed
	var stop_eligible := bool(parameters.get("stop_extension_eligible", false)) and eligible_claimed
	var result := {
		"type": "hit_confirmed",
		"claim_id": "hit:%d:%d" % [outcome_index, target_id],
		"descriptor_id": descriptor_id,
		"outcome_id": outcome_id,
		"outcome_index": outcome_index,
		"target_id": target_id,
		"terminal": false,
		"hit": resolved_damage > 0.0,
		"hit_confirmed": resolved_damage > 0.0,
		"damage": maxf(0.0, resolved_damage),
		"impact_position": impact_position,
		"deterministic_seed": deterministic_seed,
		"combo_gain": int(parameters.get("combo_gain", 0)) if combo_eligible else 0,
		"energy_return": float(parameters.get("energy_return", 0.0)) if energy_eligible else 0.0,
		"stop_extension_frames": int(parameters.get("stop_extension_frames", 0)) if stop_eligible else 0,
		"combo_eligible": combo_eligible,
		"energy_eligible": energy_eligible,
		"stop_extension_eligible": stop_eligible,
		"recursive_echo": bool(parameters.get("recursive_echo", false)),
		"is_echo": bool(parameters.get("is_echo", false)),
		"control_effect": _control_effect(),
		"spatial_context": _spatial_context(impact_position),
		"spawn_zone": _zone_descriptor(impact_position),
	}
	payload_result.emit(action_token, generation, result.duplicate(true))
	return result


func _deliver_damage_components(target: Node) -> float:
	var multiplier := float(parameters.get("resolved_damage_multiplier", parameters.get("damage_multiplier", 0.0)))
	var split_value: Variant = parameters.get("damage_type_split", {})
	var split := split_value as Dictionary if split_value is Dictionary else {}
	var components: Array[Dictionary] = []
	if split.is_empty():
		components.append({"type": DamageInfoScript.DamageType.PHYSICAL, "amount": base_attack * multiplier, "primary": true})
	else:
		for damage_name: String in ["physical", "time", "void"]:
			var ratio := float(split.get(damage_name, 0.0))
			if ratio <= 0.0:
				continue
			components.append({
				"type": _damage_type_from_name(damage_name),
				"amount": base_attack * multiplier * ratio,
				"primary": components.is_empty(),
			})
	var time_damage_ratio := float(parameters.get("time_damage_ratio", 0.0))
	if time_damage_ratio > 0.0:
		components.append({
			"type": DamageInfoScript.DamageType.TIME,
			"amount": base_attack * time_damage_ratio,
			"primary": false,
			"time_bonus": true,
		})
	var total := 0.0
	for component: Dictionary in components:
		total += _deliver_component(target, component)
	return total


func _deliver_component(target: Node, component: Dictionary) -> float:
	var amount := float(component.get("amount", 0.0))
	if amount <= 0.0:
		return 0.0
	var primary := bool(component.get("primary", false))
	var crit_chance := float(parameters.get(
		"critical_chance_bonus",
		parameters.get("critical_bonus", 0.0)
	)) if primary else 0.0
	var damage_info = DamageInfoScript.from_plan({
		"run_id": &"runtime",
		"target_id": _damage_target_id(target),
		"hostile_source_id": StringName("player:gauntlets:%d:%d" % [action_token, generation]),
		"attack_generation": generation,
		"hit_index": outcome_index,
		"action_token": action_token,
		"amount": amount,
		"damage_type": int(component["type"]),
		"source": source,
		"attacker": owner_entity,
		"can_crit": primary,
		"crit_chance": crit_chance,
		"knockback": direction * _knockback_pixels() if primary else Vector2.ZERO,
		"tags": _damage_tags(component),
		"source_generation": generation,
		"control_effect": _control_effect() if primary else {},
	})
	if damage_info == null:
		return 0.0
	return _deliver_to_target(target, damage_info)


func _damage_tags(component: Dictionary) -> Array[String]:
	var tags: Array[String] = [
		"weapon:gauntlets",
		"action:%s" % source_action_id,
		"descriptor:%s" % descriptor_id,
		"impact:%s" % _impact_tier(),
	]
	if source_action_id == "punch_5":
		tags.append("attack:finisher")
	elif source_action_id in ["charged_heavy", "dodge_counter", "space_time_shatter", "primordial_collapse_punch"]:
		tags.append("attack:heavy")
	elif source_action_id in ["punch_3", "punch_4"]:
		tags.append("attack:hook")
	if bool(parameters.get("is_echo", false)):
		tags.append("time:accelerate_echo")
		tags.append("non_recursive:echo")
	if bool(component.get("time_bonus", false)):
		tags.append("non_recursive:time_damage")
	if not bool(parameters.get("combo_eligible", false)):
		tags.append("non_recursive:combo")
	if not bool(parameters.get("energy_eligible", false)):
		tags.append("non_recursive:energy")
	if not bool(parameters.get("stop_extension_eligible", false)):
		tags.append("non_recursive:stop_extension")
	return tags


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


func _control_effect() -> Dictionary:
	var configured_value: Variant = parameters.get("control_effect", {})
	var configured := (
		(configured_value as Dictionary).duplicate(true)
		if configured_value is Dictionary
		else {}
	)
	var launch := float(parameters.get("launch", configured.get("launch", 0.0)))
	if launch <= 0.0 and configured.is_empty():
		return {}
	var multiplier := float(parameters.get("resolved_damage_multiplier", parameters.get("damage_multiplier", 0.0)))
	var conversion_id := str(boss_conversion.get("conversion_id", "gauntlets_poised_launch"))
	var allowed_value: Variant = boss_conversion.get("allowed_states", boss_conversion.get("allowed_phases", ["RECOVERY", "EXPOSED"]))
	var allowed_states := (allowed_value as Array).duplicate(true) if allowed_value is Array else ["RECOVERY", "EXPOSED"]
	return {
		"kind": str(configured.get("kind", "launch")),
		"conversion_id": str(configured.get("conversion_id", conversion_id)),
		"airborne": false,
		"poise_damage": float(configured.get("poise_damage", parameters.get("poise_damage", base_attack * multiplier * maxf(1.0, launch)))),
		"boss_poise_multiplier": float(configured.get("boss_poise_multiplier", boss_conversion.get("poise_multiplier", 1.4))),
		"displacement_pixels": float(configured.get("displacement_pixels", parameters.get("displacement_tiles", launch * 1.5))) * (1.0 if configured.has("displacement_pixels") else PIXELS_PER_TILE),
		"allowed_states": allowed_states,
		"active_attack_policy": str(boss_conversion.get("active_attack_policy", "preserve_committed")),
		"interrupt_active_attack": false,
	}


func _zone_descriptor(impact_position: Vector2) -> Dictionary:
	var zone_value: Variant = parameters.get("zone", {})
	if not zone_value is Dictionary or (zone_value as Dictionary).is_empty():
		return {}
	return {
		"descriptor_id": "%s:zone" % descriptor_id,
		"outcome_id": "%s:zone" % outcome_id,
		"outcome_index": outcome_index,
		"seed": deterministic_seed,
		"position": impact_position,
		"parameters": (zone_value as Dictionary).duplicate(true),
	}


func _spatial_context(center: Vector2) -> Dictionary:
	var geometry := _geometry()
	var rift_value: Variant = parameters.get("rift_context", {})
	var rift := (rift_value as Dictionary).duplicate(true) if rift_value is Dictionary else {}
	return {
		"center": center,
		"origin": global_position,
		"direction": direction,
		"shape": str(geometry["shape"]),
		"range_pixels": float(geometry["range_tiles"]) * PIXELS_PER_TILE,
		"width_pixels": float(geometry.get("width_tiles", 0.0)) * PIXELS_PER_TILE,
		"arc_degrees": float(geometry.get("arc_degrees", 0.0)),
		"source_generation": int(rift.get("source_generation", 0)),
		"spatial_policy": str(rift.get("spatial_policy", "")),
		"active_rifts": (rift.get("active_rifts", []) as Array).duplicate(true) if rift.get("active_rifts", []) is Array else [],
	}


func _claim_progress_once(target_id: int) -> bool:
	var key := "%d:%d:%d" % [action_token, generation, target_id]
	if progress_claims.has(key):
		return false
	while progress_claim_order.size() >= PROGRESS_CLAIM_LIMIT:
		var expired_key := str(progress_claim_order.pop_front())
		progress_claims.erase(expired_key)
	progress_claims[key] = true
	progress_claim_order.append(key)
	return true


func _claim_damage_once(target_id: int) -> bool:
	var key := "%d:%d:%d" % [action_token, generation, target_id]
	if damage_claims.has(key):
		return false
	while damage_claim_order.size() >= PROGRESS_CLAIM_LIMIT:
		var expired_key := str(damage_claim_order.pop_front())
		damage_claims.erase(expired_key)
	damage_claims[key] = true
	damage_claim_order.append(key)
	return true


func _target_inside_geometry(target: Node) -> bool:
	if not target is Node2D:
		return false
	var geometry := _geometry()
	var offset := (target as Node2D).global_position - global_position
	var range_pixels := float(geometry["range_tiles"]) * PIXELS_PER_TILE
	if str(geometry["shape"]) == "arc":
		if offset.length() > range_pixels + 0.001:
			return false
		if offset.is_zero_approx():
			return true
		return absf(rad_to_deg(direction.angle_to(offset.normalized()))) <= float(geometry.get("arc_degrees", 180.0)) * 0.5 + 0.001
	var forward := offset.dot(direction)
	var lateral := absf(offset.dot(direction.orthogonal()))
	return forward >= -0.001 and forward <= range_pixels + 0.001 and lateral <= float(geometry.get("width_tiles", 1.0)) * PIXELS_PER_TILE * 0.5 + 0.001


func _configure_collision() -> void:
	if is_instance_valid(_collision_shape):
		_collision_shape.free()
	_collision_shape = CollisionShape2D.new()
	var geometry := _geometry()
	var range_pixels := float(geometry["range_tiles"]) * PIXELS_PER_TILE
	if str(geometry["shape"]) == "arc":
		var circle := CircleShape2D.new()
		circle.radius = range_pixels
		_collision_shape.shape = circle
	else:
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(range_pixels, float(geometry.get("width_tiles", 1.0)) * PIXELS_PER_TILE)
		_collision_shape.shape = rectangle
		_collision_shape.position = direction * range_pixels * 0.5
		_collision_shape.rotation = direction.angle()
	add_child(_collision_shape)


func _geometry() -> Dictionary:
	var geometry := (DEFAULT_GEOMETRY[source_action_id] as Dictionary).duplicate(true)
	for field: String in ["shape", "range_tiles", "width_tiles", "arc_degrees"]:
		if parameters.has(field):
			geometry[field] = parameters[field]
	return geometry


func _parameters_are_valid(values: Dictionary, action_id: String) -> bool:
	var multiplier_value: Variant = values.get("resolved_damage_multiplier", values.get("damage_multiplier"))
	if not _positive_number(multiplier_value):
		return false
	for flag: String in ["combo_eligible", "energy_eligible", "stop_extension_eligible", "recursive_echo", "is_echo", "shared_damage_claim"]:
		if values.has(flag) and typeof(values[flag]) != TYPE_BOOL:
			return false
	var active_frames := int(values.get("active_frames", DEFAULT_ACTIVE_FRAMES[action_id]))
	if active_frames <= 0:
		return false
	var split_value: Variant = values.get("damage_type_split", {})
	if not split_value is Dictionary:
		return false
	if not (split_value as Dictionary).is_empty():
		var total := 0.0
		for key: Variant in split_value:
			if str(key) not in ["physical", "time", "void"] or not _non_negative_number((split_value as Dictionary)[key]):
				return false
			total += float((split_value as Dictionary)[key])
		if not is_equal_approx(total, 1.0):
			return false
	for field: String in ["time_damage_ratio", "critical_chance_bonus", "critical_bonus", "energy_return"]:
		if values.has(field) and not _non_negative_number(values[field]):
			return false
	return true


func _knockback_pixels() -> float:
	if parameters.has("knockback_pixels"):
		return maxf(0.0, float(parameters["knockback_pixels"]))
	return maxf(0.0, float(parameters.get("knockback_tiles", 0.0)) * PIXELS_PER_TILE)


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


func _retire() -> void:
	if not _completion_emitted:
		_completion_emitted = true
		execution_finished.emit(action_token, generation)
	_execution_active = false
	monitoring = false
	set_physics_process(false)
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _impact_tier() -> String:
	if source_action_id == "primordial_collapse_punch":
		return "ultimate"
	if source_action_id in ["punch_5", "charged_heavy", "dodge_counter", "space_time_shatter"]:
		return "heavy"
	if source_action_id in ["punch_3", "punch_4"]:
		return "medium"
	return "light"


func _sorted_integer_keys(values: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	result.sort()
	return result


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _non_negative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _valid_sorted_positive_ids(value: Array) -> bool:
	var previous := 0
	for target_id: Variant in value:
		if typeof(target_id) != TYPE_INT or int(target_id) <= previous:
			return false
		previous = int(target_id)
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
