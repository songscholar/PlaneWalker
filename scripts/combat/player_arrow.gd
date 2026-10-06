class_name PlayerArrow
extends Area2D

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const Targets := preload("res://scripts/combat/weapon_target_policy.gd")
const NativeHitbox := preload("res://scripts/combat/hitbox.gd")

@export var speed: float = 520.0
@export var lifetime: float = 1.5
@export var damage: float = 24.0
@export var pierce: int = 0
@export var full_charge: bool = false
@export var time_energy_restore: float = 0.0
@export var action_token: int = 0
@export var energy_reward_once_per_action: bool = false
@export var damage_type: int = DamageInfoScript.DamageType.PHYSICAL
@export var time_damage_ratio: float = 0.0
@export var max_range_pixels: float = 0.0
@export var pierce_mode: String = "limited"
@export var outcome_index: int = 0
@export var deterministic_seed: int = 0
@export var base_attack: float = 0.0
@export var source_action_id: String = ""
@export var descriptor_id: String = ""
@export var trail_duration_frames: int = 0
@export var trail_tick_interval_frames: int = 0
@export var trail_width_pixels: float = 0.0
@export var trail_tick_damage_multiplier: float = 0.0
@export var trail_slow_ratio: float = 0.0

@onready var visual: CanvasItem = $Visual

var direction: Vector2 = Vector2.RIGHT
var source: Node
var owner_entity: Node
var attack_tags: Array[String] = ["weapon:bow"]
var time_interactions: Array[Dictionary] = []
var boss_conversion: Dictionary = {}
var first_hit_control: Dictionary = {}
var interaction_claims: Dictionary = {}
var _hit_targets: Dictionary = {}
var _start_position: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0
var _flight_complete: bool = false
var _execution_frame: int = 0
var _trail_points: Array[Dictionary] = []
var _trail_targets: Dictionary = {}
var _time_stop_targets: Dictionary = {}
var _first_hit_control_applied: bool = false
var _lifetime_remaining: float = 0.0
var _restored_before_ready: bool = false


func _ready() -> void:
	add_to_group("player_arrows")
	area_entered.connect(_on_physical_area_entered)
	rotation = direction.angle()
	if not _restored_before_ready:
		_start_position = global_position
		_lifetime_remaining = lifetime
		if trail_duration_frames > 0:
			_append_trail_point(global_position)
	else:
		monitoring = not _flight_complete
		visual.visible = not _flight_complete
	_restored_before_ready = false


func _physics_process(delta: float) -> void:
	_lifetime_remaining = maxf(0.0, _lifetime_remaining - delta)
	if _lifetime_remaining <= 0.0:
		queue_free()
		return
	if not _flight_complete:
		var distance := speed * delta
		if max_range_pixels > 0.0:
			distance = minf(distance, maxf(0.0, max_range_pixels - _distance_travelled))
		var destination := global_position + direction.normalized() * distance
		for area: Area2D in Targets.swept_hurtboxes(self, global_position, destination):
			_on_area_entered(area)
			if is_queued_for_deletion():
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
		"full_charge",
		"time_energy_restore",
		"energy_reward_once_per_action",
		"time_damage_ratio",
		"trail",
		"first_hit_control",
		"time_interactions",
		"boss_conversion",
		"tags",
	]:
		if not execution.has(field):
			return false
	if (
		typeof(execution["action_token"]) != TYPE_INT
		or int(execution["action_token"]) <= 0
		or typeof(execution["outcome_index"]) != TYPE_INT
		or typeof(execution["deterministic_seed"]) != TYPE_INT
		or not _positive_number(execution["damage"])
		or not _positive_number(execution["speed"])
		or not _non_negative_number(execution["max_range_pixels"])
		or not execution["trail"] is Dictionary
		or not execution["first_hit_control"] is Dictionary
		or not execution["time_interactions"] is Array
		or not execution["boss_conversion"] is Dictionary
		or not execution["tags"] is Array
	):
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
	full_charge = bool(execution["full_charge"])
	time_energy_restore = float(execution["time_energy_restore"])
	energy_reward_once_per_action = bool(execution["energy_reward_once_per_action"])
	time_damage_ratio = clampf(float(execution["time_damage_ratio"]), 0.0, 1.0)
	first_hit_control = (execution["first_hit_control"] as Dictionary).duplicate(true)
	boss_conversion = (execution["boss_conversion"] as Dictionary).duplicate(true)
	var claims_value: Variant = execution.get("interaction_claims", {})
	interaction_claims = claims_value if claims_value is Dictionary else {}
	time_interactions.clear()
	for interaction_value: Variant in execution["time_interactions"]:
		if not interaction_value is Dictionary:
			return false
		time_interactions.append((interaction_value as Dictionary).duplicate(true))
	attack_tags.clear()
	for tag_value: Variant in execution["tags"]:
		var tag := str(tag_value)
		if not tag.is_empty() and not attack_tags.has(tag):
			attack_tags.append(tag)
	var trail: Dictionary = execution["trail"]
	trail_duration_frames = int(trail.get("duration_frames", 0))
	trail_tick_interval_frames = int(trail.get("tick_interval_frames", 0))
	trail_width_pixels = float(trail.get("width_pixels", float(trail.get("width_cells", 0.0)) * 64.0))
	trail_tick_damage_multiplier = float(trail.get("tick_damage_multiplier", 0.0))
	trail_slow_ratio = clampf(float(trail.get("slow_ratio", 0.0)), 0.0, 0.9)
	if trail_duration_frames > 0:
		if trail_tick_interval_frames <= 0 or trail_width_pixels <= 0.0 or trail_tick_damage_multiplier <= 0.0:
			return false
		var flight_seconds := max_range_pixels / speed if max_range_pixels > 0.0 else lifetime
		lifetime = maxf(lifetime, flight_seconds + float(trail_duration_frames) / 60.0 + 0.25)
	return true


func _on_physical_area_entered(area: Area2D) -> void:
	NativeHitbox.dispatch_contact(_on_area_entered.bind(area))


func _on_area_entered(area: Area2D) -> void:
	if not area.has_method("receive_hit"):
		return
	var target := area.get_parent()
	if not Targets.is_attackable(target):
		return
	var target_id := _stable_target_id(target)
	if _hit_targets.has(target_id):
		return

	_hit_targets[target_id] = true
	_deal_projectile_damage(area)
	if Targets.is_arena_construct(target):
		if pierce_mode != "unlimited" and _hit_targets.size() > pierce:
			queue_free()
		return
	_restore_time_energy()
	_apply_first_hit_control(area)
	_apply_time_interactions(area)
	_apply_boss_conversion(area)
	if pierce_mode != "unlimited" and _hit_targets.size() > pierce:
		queue_free()


func _deal_projectile_damage(area: Area2D) -> void:
	var time_amount := damage * time_damage_ratio
	var physical_amount := damage - time_amount
	if physical_amount > 0.0:
		_deliver_damage(area, physical_amount, DamageInfoScript.DamageType.PHYSICAL, false)
	if time_amount > 0.0:
		_deliver_damage(area, time_amount, DamageInfoScript.DamageType.TIME, true)
	if physical_amount <= 0.0 and time_amount <= 0.0:
		_deliver_damage(area, damage, damage_type, damage_type == DamageInfoScript.DamageType.TIME)


func _deliver_damage(area: Area2D, amount: float, type: int, time_component: bool) -> void:
	var resolved_tags: Array[String] = attack_tags.duplicate()
	if full_charge and not resolved_tags.has("attack:full_charge"):
		resolved_tags.append("attack:full_charge")
	if time_component and not resolved_tags.has("damage:time_component"):
		resolved_tags.append("damage:time_component")
	var damage_info = DamageInfoScript.from_plan({
		"run_id": &"runtime",
		"target_id": _damage_target_id(area.get_parent()),
		"hostile_source_id": StringName("player:bow:%d:%d" % [action_token, outcome_index]),
		"attack_generation": maxi(1, action_token),
		"hit_index": outcome_index,
		"action_token": maxi(1, action_token),
		"amount": amount,
		"damage_type": type,
		"source": source,
		"attacker": owner_entity,
		"knockback": direction.normalized() * 90.0 if not time_component else Vector2.ZERO,
		"tags": resolved_tags,
	})
	if damage_info == null:
		return
	area.receive_hit(damage_info)


func advance_execution_for_test(frames: int) -> void:
	if frames <= 0:
		return
	for _frame: int in range(frames):
		_execution_frame += 1
		_prune_trail_points()
		_prune_time_stop_sources()
		if trail_tick_interval_frames > 0 and _execution_frame % trail_tick_interval_frames == 0:
			_refresh_trail_targets()
			_tick_trail_targets()


func execution_snapshot() -> Dictionary:
	return {
		"action_token": action_token,
		"source_action_id": source_action_id,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"deterministic_seed": deterministic_seed,
		"damage_type": "TIME" if time_damage_ratio >= 1.0 else "MIXED" if time_damage_ratio > 0.0 else "PHYSICAL",
		"damage_type_value": damage_type,
		"damage": damage,
		"base_attack": base_attack,
		"speed": speed,
		"max_range_pixels": max_range_pixels,
		"pierce": pierce,
		"full_charge": full_charge,
		"time_energy_restore": time_energy_restore,
		"energy_reward_once_per_action": energy_reward_once_per_action,
		"time_damage_ratio": time_damage_ratio,
		"pierce_mode": pierce_mode,
		"direction": direction,
		"lifetime": lifetime,
		"lifetime_remaining": _lifetime_remaining,
		"distance_travelled": _distance_travelled,
		"flight_complete": _flight_complete,
		"execution_frame": _execution_frame,
		"trail_duration_frames": trail_duration_frames,
		"trail_tick_interval_frames": trail_tick_interval_frames,
		"trail_width_pixels": trail_width_pixels,
		"trail_tick_damage_multiplier": trail_tick_damage_multiplier,
		"trail_slow_ratio": trail_slow_ratio,
		"trail_point_count": _trail_points.size(),
		"trail_points": _trail_points.duplicate(true),
		"hit_target_ids": _sorted_integer_keys(_hit_targets),
		"trail_target_ids": _sorted_integer_keys(_trail_targets),
		"time_stop_targets": _time_stop_target_snapshot(),
		"first_hit_control_applied": _first_hit_control_applied,
		"first_hit_control": first_hit_control.duplicate(true),
		"interaction_claims": interaction_claims.duplicate(true),
		"tags": attack_tags.duplicate(),
		"time_interactions": time_interactions.duplicate(true),
		"boss_conversion": boss_conversion.duplicate(true),
	}


func can_restore_execution_snapshot(value: Dictionary) -> bool:
	var expected_fields: Array[String] = [
		"action_token", "source_action_id", "descriptor_id", "outcome_index",
		"deterministic_seed", "damage_type", "damage_type_value", "damage", "base_attack",
		"speed", "max_range_pixels", "pierce", "full_charge", "time_energy_restore",
		"energy_reward_once_per_action", "time_damage_ratio", "pierce_mode", "direction",
		"lifetime", "lifetime_remaining", "distance_travelled", "flight_complete",
		"execution_frame", "trail_duration_frames", "trail_tick_interval_frames",
		"trail_width_pixels", "trail_tick_damage_multiplier", "trail_slow_ratio",
		"trail_point_count", "trail_points", "hit_target_ids", "trail_target_ids",
		"time_stop_targets", "first_hit_control_applied", "first_hit_control",
		"interaction_claims", "tags", "time_interactions", "boss_conversion",
	]
	if not _has_exact_fields(value, expected_fields):
		return false
	var execution := _execution_definition_from_snapshot(value)
	if execution.is_empty():
		return false
	var staged := PlayerArrow.new()
	if not staged.configure_execution(execution):
		staged.free()
		return false
	var direction_value: Variant = value.get("direction")
	var trail_points_value: Variant = value.get("trail_points")
	var valid := (
		direction_value is Vector2
		and _finite_vector(direction_value as Vector2)
		and not (direction_value as Vector2).is_zero_approx()
		and _positive_number(value.get("lifetime"))
		and _positive_number(value.get("lifetime_remaining"))
		and float(value.get("lifetime_remaining")) <= float(value.get("lifetime")) + 0.001
		and _non_negative_number(value.get("distance_travelled"))
		and (float(value.get("max_range_pixels", 0.0)) <= 0.0 or float(value.get("distance_travelled")) <= float(value.get("max_range_pixels")) + 0.001)
		and typeof(value.get("flight_complete")) == TYPE_BOOL
		and typeof(value.get("execution_frame")) == TYPE_INT
		and int(value.get("execution_frame")) >= 0
		and trail_points_value is Array
		and _valid_trail_points(trail_points_value, int(value.get("execution_frame")))
		and int(value.get("trail_point_count", -1)) == (trail_points_value as Array).size()
		and _valid_positive_integer_array(value.get("hit_target_ids"))
		and _valid_positive_integer_array(value.get("trail_target_ids"))
		and _valid_time_stop_targets(value.get("time_stop_targets"), int(value.get("execution_frame")))
		and typeof(value.get("first_hit_control_applied")) == TYPE_BOOL
		and value.get("interaction_claims") is Dictionary
		and typeof(value.get("damage_type")) == TYPE_STRING
		and str(value.get("damage_type")) == (
			"TIME" if float(value.get("time_damage_ratio")) >= 1.0
			else "MIXED" if float(value.get("time_damage_ratio")) > 0.0
			else "PHYSICAL"
		)
	)
	staged.free()
	return valid


func restore_execution_snapshot(value: Dictionary) -> bool:
	if not can_restore_execution_snapshot(value):
		return false
	var execution := _execution_definition_from_snapshot(value)
	if not configure_execution(execution):
		return false
	direction = (value["direction"] as Vector2).normalized()
	damage_type = int(value["damage_type_value"])
	lifetime = float(value["lifetime"])
	_lifetime_remaining = float(value["lifetime_remaining"])
	_distance_travelled = float(value["distance_travelled"])
	_flight_complete = bool(value["flight_complete"])
	_execution_frame = int(value["execution_frame"])
	_trail_points = _dictionary_array(value["trail_points"])
	_hit_targets.clear()
	for target_id_value: Variant in value["hit_target_ids"] as Array:
		_hit_targets[int(target_id_value)] = true
	_trail_targets.clear()
	for target_id_value: Variant in value["trail_target_ids"] as Array:
		_trail_targets[int(target_id_value)] = null
	_time_stop_targets.clear()
	for state_value: Variant in value["time_stop_targets"] as Array:
		var state := state_value as Dictionary
		_time_stop_targets[int(state["target_id"])] = {
			"target": null,
			"source_id": StringName(str(state["source_id"])),
			"expires_at_frame": int(state["expires_at_frame"]),
		}
	_first_hit_control_applied = bool(value["first_hit_control_applied"])
	interaction_claims = (value["interaction_claims"] as Dictionary).duplicate(true)
	_restored_before_ready = not is_inside_tree()
	if is_inside_tree():
		rotation = direction.angle()
		monitoring = not _flight_complete
		visual.visible = not _flight_complete
	return execution_snapshot() == value


func activate_restored_execution_state(shared_claims: Dictionary = {}) -> bool:
	if not is_inside_tree() or _lifetime_remaining <= 0.0:
		return false
	interaction_claims = shared_claims
	var restored_trail_targets: Dictionary = {}
	for target_id_value: Variant in _trail_targets:
		var target := _target_by_stable_id(int(target_id_value))
		var area := _target_hurtbox(target)
		if target == null or area == null:
			_rollback_restored_target_effects(restored_trail_targets, {})
			return false
		restored_trail_targets[int(target_id_value)] = area
		_apply_trail_slow(target)
	_trail_targets = restored_trail_targets
	var restored_stop_targets: Dictionary = {}
	for target_id_value: Variant in _time_stop_targets:
		var state := _time_stop_targets[target_id_value] as Dictionary
		var target := _target_by_stable_id(int(target_id_value))
		var remaining_frames := int(state["expires_at_frame"]) - _execution_frame
		if target == null or remaining_frames <= 0 or not target.has_method("apply_time_stop_source"):
			_rollback_restored_target_effects(restored_trail_targets, restored_stop_targets)
			return false
		var source_id := StringName(str(state["source_id"]))
		target.call("apply_time_stop_source", source_id, float(remaining_frames) / 60.0)
		restored_stop_targets[int(target_id_value)] = {
			"target": target,
			"source_id": source_id,
			"expires_at_frame": int(state["expires_at_frame"]),
		}
	_time_stop_targets = restored_stop_targets
	return true


func reset_execution_state() -> void:
	_clear_all_trail_targets()
	_clear_all_time_stop_sources()
	_hit_targets.clear()
	_trail_points.clear()
	_distance_travelled = 0.0
	_flight_complete = false
	_execution_frame = 0
	_first_hit_control_applied = false
	_lifetime_remaining = 0.0
	monitoring = false
	set_physics_process(false)


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
		_clear_all_trail_targets()


func _refresh_trail_targets() -> void:
	if _trail_points.is_empty():
		_clear_all_trail_targets()
		return
	if trail_width_pixels <= 0.0 or not is_inside_tree():
		return
	var active_targets: Dictionary = {}
	for enemy: Node in SceneScope.nodes_in_group(self, "enemies"):
		if not is_instance_valid(enemy):
			continue
		for child: Node in enemy.get_children():
			if child is Area2D and child.has_method("receive_hit") and _area_is_on_trail(child):
				active_targets[_stable_target_id(enemy)] = child
				break
	for target_id: Variant in _trail_targets:
		if active_targets.has(target_id):
			continue
		var stale_value: Variant = _trail_targets[target_id]
		if is_instance_valid(stale_value) and stale_value is Area2D:
			_clear_trail_slow((stale_value as Area2D).get_parent())
	_trail_targets = active_targets


func _area_is_on_trail(area: Area2D) -> bool:
	if _trail_points.size() == 1:
		return area.global_position.distance_to(_trail_points[0]["position"]) <= trail_width_pixels * 0.5
	for index: int in range(1, _trail_points.size()):
		var start: Vector2 = _trail_points[index - 1]["position"]
		var finish: Vector2 = _trail_points[index]["position"]
		if _distance_to_segment(area.global_position, start, finish) <= trail_width_pixels * 0.5:
			return true
	return false


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _on_trail_area_entered(area: Area2D) -> void:
	if (
		trail_duration_frames <= 0
		or not is_instance_valid(area)
		or not area.has_method("receive_hit")
		or area.get_parent() == null
		or not area.get_parent().is_in_group("enemies")
	):
		return
	_trail_targets[_stable_target_id(area.get_parent())] = area


func _tick_trail_targets() -> void:
	if trail_tick_damage_multiplier <= 0.0:
		return
	var stale_ids: Array[int] = []
	for target_id: Variant in _trail_targets:
		var area_value: Variant = _trail_targets[target_id]
		if not is_instance_valid(area_value) or not area_value is Area2D:
			stale_ids.append(int(target_id))
			continue
		var area: Area2D = area_value
		if area.get_parent() == null or not area.get_parent().is_in_group("enemies"):
			stale_ids.append(int(target_id))
			continue
		var tick_damage := maxf(0.0, base_attack * trail_tick_damage_multiplier)
		if tick_damage <= 0.0:
			continue
		var resolved_tags: Array[String] = attack_tags.duplicate()
		resolved_tags.append("attack:temporal_trail")
		resolved_tags.append("non_recursive:resource_reward")
		var damage_info = DamageInfoScript.from_plan({
			"run_id": &"runtime",
			"target_id": _damage_target_id(area.get_parent()),
			"hostile_source_id": StringName("player:bow_trail:%d:%d" % [action_token, outcome_index]),
			"attack_generation": maxi(1, _execution_frame),
			"hit_index": outcome_index,
			"action_token": maxi(1, action_token),
			"amount": tick_damage,
			"damage_type": DamageInfoScript.DamageType.TIME,
			"source": source,
			"attacker": owner_entity,
			"tags": resolved_tags,
		})
		if damage_info == null:
			continue
		area.receive_hit(damage_info)
		_apply_trail_slow(area.get_parent())
	for target_id: int in stale_ids:
		_trail_targets.erase(target_id)


func _apply_trail_slow(target: Node) -> void:
	if trail_slow_ratio <= 0.0 or not target.has_method("apply_time_rift"):
		return
	var source_id := StringName("bow_trail_%d_%d" % [action_token, outcome_index])
	target.call("apply_time_rift", source_id, 1.0 - trail_slow_ratio)


func _clear_trail_slow(target: Node) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("clear_time_rift"):
		return
	var source_id := StringName("bow_trail_%d_%d" % [action_token, outcome_index])
	target.call("clear_time_rift", source_id)


func _clear_all_trail_targets() -> void:
	for area_value: Variant in _trail_targets.values():
		if is_instance_valid(area_value) and area_value is Area2D:
			_clear_trail_slow((area_value as Area2D).get_parent())
	_trail_targets.clear()


func _exit_tree() -> void:
	_clear_all_trail_targets()
	_clear_all_time_stop_sources()


func _apply_first_hit_control(area: Area2D) -> void:
	if _first_hit_control_applied or first_hit_control.is_empty():
		return
	_first_hit_control_applied = true
	var target := area.get_parent()
	if target == null or target.is_in_group("bosses"):
		return
	var duration_frames := int(first_hit_control.get(
		"duration_frames",
		first_hit_control.get("ordinary_freeze_frames", 0)
	))
	if duration_frames <= 0:
		return
	if target.has_method("apply_time_stop_source"):
		var source_id := StringName("bow_arrow_stop_%d_%d" % [action_token, outcome_index])
		target.call("apply_time_stop_source", source_id, float(duration_frames) / 60.0)
		_time_stop_targets[_stable_target_id(target)] = {
			"target": target,
			"source_id": source_id,
			"expires_at_frame": _execution_frame + duration_frames,
		}
	elif target.has_method("apply_time_stop"):
		target.call("apply_time_stop", float(duration_frames) / 60.0)


func _apply_time_interactions(area: Area2D) -> void:
	if attack_tags.has("non_recursive:time_interaction"):
		return
	for interaction: Dictionary in time_interactions:
		match str(interaction.get("interaction_id", interaction.get("effect", ""))):
			"full_charge_explosion", "bow_stopped_target_burst":
				if full_charge:
					_deal_radial_time_damage(
						area.global_position,
						float(interaction.get("explosion_radius_cells", interaction.get("radius_cells", 2.5))) * 64.0,
						base_attack * float(interaction.get("explosion_damage_multiplier", interaction.get("damage_multiplier", 2.0))),
						"attack:stop_explosion"
					)
					_extend_owner_time_stop(int(interaction.get("stop_extension_frames", interaction.get("extension_frames", 60))))
			"penetration_detonation", "bow_rift_penetration":
				var target := area.get_parent()
				if target != null and target.has_method("is_time_rifted") and bool(target.call("is_time_rifted")):
					var detonation_radius := _rift_detonation_radius(target, interaction)
					if detonation_radius > 0.0 and _claim_interaction_once("rift_detonation"):
						_deal_radial_time_damage(
							area.global_position,
							detonation_radius,
							base_attack * float(interaction.get(
								"detonation_damage_multiplier",
								interaction.get("damage_multiplier", 1.5)
							)),
							"attack:rift_detonation"
						)


func _rift_detonation_radius(target: Node, interaction: Dictionary) -> float:
	for explicit_field: String in ["detonation_radius_pixels", "explosion_radius_pixels"]:
		if _positive_number(interaction.get(explicit_field, 0.0)):
			return float(interaction[explicit_field])
	for explicit_field: String in ["detonation_radius_cells", "radius_cells"]:
		if _positive_number(interaction.get(explicit_field, 0.0)):
			return float(interaction[explicit_field]) * 64.0
	if not is_inside_tree() or not target is Node2D:
		return 0.0
	var multiplier := float(interaction.get("detonation_radius_multiplier", 1.5))
	if not is_finite(multiplier) or multiplier <= 0.0:
		return 0.0
	var resolved_radius := 0.0
	for rift: Node in SceneScope.nodes_in_group(self, "time_rifts"):
		if not is_instance_valid(rift) or not rift is Node2D:
			continue
		var radius_value: Variant = rift.get("radius")
		if not _positive_number(radius_value):
			continue
		var radius := float(radius_value)
		if (rift as Node2D).global_position.distance_to((target as Node2D).global_position) <= radius:
			resolved_radius = maxf(resolved_radius, radius * multiplier)
	return resolved_radius


func _claim_interaction_once(interaction_id: String) -> bool:
	var key := "%d:%s" % [action_token, interaction_id]
	if interaction_claims.has(key):
		return false
	interaction_claims[key] = true
	return true


func _prune_time_stop_sources() -> void:
	for target_id: Variant in _time_stop_targets.keys():
		var state: Dictionary = _time_stop_targets[target_id]
		if int(state.get("expires_at_frame", 0)) > _execution_frame:
			continue
		_clear_time_stop_source(int(target_id))


func _clear_time_stop_source(target_id: int) -> void:
	if not _time_stop_targets.has(target_id):
		return
	var state: Dictionary = _time_stop_targets[target_id]
	_time_stop_targets.erase(target_id)
	var target_value: Variant = state.get("target")
	if (
		is_instance_valid(target_value)
		and target_value is Node
		and (target_value as Node).has_method("clear_time_stop_source")
	):
		(target_value as Node).call("clear_time_stop_source", state.get("source_id", &""))


func _clear_all_time_stop_sources() -> void:
	for target_id: Variant in _time_stop_targets.keys():
		_clear_time_stop_source(int(target_id))
	_time_stop_targets.clear()


func _execution_definition_from_snapshot(value: Dictionary) -> Dictionary:
	for field: String in [
		"action_token", "source_action_id", "descriptor_id", "outcome_index",
		"deterministic_seed", "damage_type_value", "damage", "base_attack", "speed", "max_range_pixels",
		"pierce", "pierce_mode", "full_charge", "time_energy_restore",
		"energy_reward_once_per_action", "time_damage_ratio", "trail_duration_frames",
		"trail_tick_interval_frames", "trail_width_pixels", "trail_tick_damage_multiplier",
		"trail_slow_ratio", "first_hit_control", "time_interactions", "boss_conversion", "tags",
	]:
		if not value.has(field):
			return {}
	if (
		typeof(value["damage_type_value"]) != TYPE_INT
		or int(value["damage_type_value"]) not in [
			DamageInfoScript.DamageType.PHYSICAL,
			DamageInfoScript.DamageType.TIME,
		]
		or not value["first_hit_control"] is Dictionary
		or not value["time_interactions"] is Array
		or not value["boss_conversion"] is Dictionary
		or not value["interaction_claims"] is Dictionary
		or not value["tags"] is Array
	):
		return {}
	return {
		"action_token": value["action_token"],
		"source_action_id": value["source_action_id"],
		"descriptor_id": value["descriptor_id"],
		"outcome_index": value["outcome_index"],
		"deterministic_seed": value["deterministic_seed"],
		"damage": value["damage"],
		"base_attack": value["base_attack"],
		"speed": value["speed"],
		"max_range_pixels": value["max_range_pixels"],
		"pierce": value["pierce"],
		"pierce_mode": value["pierce_mode"],
		"full_charge": value["full_charge"],
		"time_energy_restore": value["time_energy_restore"],
		"energy_reward_once_per_action": value["energy_reward_once_per_action"],
		"time_damage_ratio": value["time_damage_ratio"],
		"trail": {
			"duration_frames": value["trail_duration_frames"],
			"tick_interval_frames": value["trail_tick_interval_frames"],
			"width_pixels": value["trail_width_pixels"],
			"tick_damage_multiplier": value["trail_tick_damage_multiplier"],
			"slow_ratio": value["trail_slow_ratio"],
		},
		"first_hit_control": (value["first_hit_control"] as Dictionary).duplicate(true),
		"time_interactions": (value["time_interactions"] as Array).duplicate(true),
		"boss_conversion": (value["boss_conversion"] as Dictionary).duplicate(true),
		"interaction_claims": (value["interaction_claims"] as Dictionary).duplicate(true),
		"tags": (value["tags"] as Array).duplicate(),
	}


func _time_stop_target_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := _sorted_integer_keys(_time_stop_targets)
	for target_id: int in ids:
		var state := _time_stop_targets[target_id] as Dictionary
		result.append({
			"target_id": target_id,
			"source_id": str(state.get("source_id", "")),
			"expires_at_frame": int(state.get("expires_at_frame", 0)),
		})
	return result


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
			or int(point["expires_at"]) <= execution_frame
		):
			return false
	return true


func _valid_positive_integer_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := 0
	var seen: Dictionary = {}
	for item: Variant in value as Array:
		if typeof(item) != TYPE_INT or int(item) <= 0 or seen.has(int(item)):
			return false
		if not seen.is_empty() and int(item) <= previous:
			return false
		seen[int(item)] = true
		previous = int(item)
	return true


func _valid_time_stop_targets(value: Variant, execution_frame: int) -> bool:
	if not value is Array:
		return false
	var ids: Array[int] = []
	for state_value: Variant in value as Array:
		if not state_value is Dictionary:
			return false
		var state := state_value as Dictionary
		if (
			typeof(state.get("target_id")) != TYPE_INT
			or int(state["target_id"]) <= 0
			or ids.has(int(state["target_id"]))
			or str(state.get("source_id", "")).is_empty()
			or typeof(state.get("expires_at_frame")) != TYPE_INT
			or int(state["expires_at_frame"]) <= execution_frame
		):
			return false
		ids.append(int(state["target_id"]))
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	return ids == sorted_ids


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value as Array:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _sorted_integer_keys(values: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	result.sort()
	return result


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		return int(target.get_meta("stable_target_id"))
	if target.has_meta("encounter_spawn_id"):
		return maxi(1, str(target.get_meta("encounter_spawn_id")).hash())
	return target.get_instance_id()


func _damage_target_id(target: Node) -> StringName:
	if target != null and target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return StringName("target:%d" % int(value))
	if target != null and target.has_meta("encounter_spawn_id"):
		var spawn_id := str(target.get_meta("encounter_spawn_id")).strip_edges()
		if not spawn_id.is_empty() and spawn_id.length() <= 56:
			return StringName("target:%s" % spawn_id)
	return &"pending_target"


func _target_by_stable_id(target_id: int) -> Node:
	if target_id <= 0 or not is_inside_tree():
		return null
	for candidate: Node in SceneScope.nodes_in_group(self, "enemies"):
		if candidate != null and is_instance_valid(candidate) and _stable_target_id(candidate) == target_id:
			return candidate
	return null


func _target_hurtbox(target: Node) -> Area2D:
	if target == null:
		return null
	for child: Node in target.get_children():
		if child is Area2D and child.has_method("receive_hit"):
			return child as Area2D
	return null


func _rollback_restored_target_effects(trail_targets: Dictionary, stop_targets: Dictionary) -> void:
	for area_value: Variant in trail_targets.values():
		if typeof(area_value) == TYPE_OBJECT and is_instance_valid(area_value):
			_clear_trail_slow((area_value as Area2D).get_parent())
	for state_value: Variant in stop_targets.values():
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		var target_value: Variant = state.get("target")
		if typeof(target_value) == TYPE_OBJECT and is_instance_valid(target_value) and (target_value as Node).has_method("clear_time_stop_source"):
			(target_value as Node).call("clear_time_stop_source", state.get("source_id", &""))


func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _extend_owner_time_stop(extension_frames: int) -> void:
	if extension_frames <= 0 or owner_entity == null:
		return
	if owner_entity.has_method("extend_weapon_time_stop"):
		owner_entity.call("extend_weapon_time_stop", action_token, extension_frames)
		return
	var manager := owner_entity.get_node_or_null("TimeManager")
	if manager != null and manager.has_method("extend_time_stop_frames"):
		manager.call("extend_time_stop_frames", extension_frames, action_token)


func _deal_radial_time_damage(center: Vector2, radius: float, amount: float, tag: String) -> void:
	if radius <= 0.0 or amount <= 0.0 or not is_inside_tree():
		return
	var hit_ids: Dictionary = {}
	for enemy: Node in SceneScope.nodes_in_group(self, "enemies"):
		if not is_instance_valid(enemy) or hit_ids.has(enemy.get_instance_id()):
			continue
		for child: Node in enemy.get_children():
			if (
				child is Area2D
				and child.has_method("receive_hit")
				and child.global_position.distance_to(center) <= radius
			):
				hit_ids[enemy.get_instance_id()] = true
				var resolved_tags: Array[String] = attack_tags.duplicate()
				resolved_tags.append(tag)
				resolved_tags.append("non_recursive:time_interaction")
				var damage_info = DamageInfoScript.from_plan({
					"run_id": &"runtime",
					"target_id": _damage_target_id(enemy),
					"hostile_source_id": StringName("player:bow_interaction:%d:%d" % [action_token, outcome_index]),
					"attack_generation": maxi(1, action_token),
					"hit_index": outcome_index,
					"action_token": maxi(1, action_token),
					"amount": amount,
					"damage_type": DamageInfoScript.DamageType.TIME,
					"source": source,
					"attacker": owner_entity,
					"tags": resolved_tags,
				})
				if damage_info == null:
					continue
				child.call("receive_hit", damage_info)
				break


func _apply_boss_conversion(area: Area2D) -> void:
	if boss_conversion.is_empty():
		return
	var target := area.get_parent()
	if target == null or not target.is_in_group("bosses") or not target.has_method("get_boss_ui_snapshot"):
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
	var conversion_id := str(boss_conversion.get("conversion_id", "bow_control"))
	var source_id := StringName("%s:%d" % [conversion_id, action_token])
	var control_frames := int(first_hit_control.get("boss_slow_frames", 0))
	var recovery_frames := int(boss_conversion.get(
		"recovery_extension_frames",
		control_frames if control_frames > 0 else 12
	))
	var exposure_frames := int(boss_conversion.get(
		"exposure_frames",
		maxi(control_frames, 30)
	))
	var poise_damage := float(boss_conversion.get(
		"poise_damage",
		base_attack * 0.5 * float(boss_conversion.get("poise_multiplier", 1.0))
	))
	if target.has_method("apply_weapon_control_conversion"):
		target.call(
			"apply_weapon_control_conversion",
			source_id,
			recovery_frames,
			exposure_frames,
			poise_damage
		)


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _non_negative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _restore_time_energy() -> void:
	if not full_charge or time_energy_restore <= 0.0 or owner_entity == null:
		return
	if energy_reward_once_per_action:
		if (
			action_token <= 0
			or not owner_entity.has_method("claim_weapon_action_reward")
			or not bool(owner_entity.call(
				"claim_weapon_action_reward",
				action_token,
				&"full_charge_energy"
			))
		):
			return
	var time_manager := owner_entity.get_node_or_null("TimeManager")
	if time_manager != null and time_manager.has_method("restore_energy"):
		time_manager.restore_energy(time_energy_restore)
