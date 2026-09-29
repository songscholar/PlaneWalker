class_name BowWeapon
extends Node2D

const ArrowScene := preload("res://scenes/combat/player_arrow.tscn")

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0
@export var min_charge_time: float = 0.15
@export var full_charge_time: float = 0.9
@export var cooldown: float = 0.35
@export var full_charge_time_restore: float = 6.0

@onready var owner_player: Node2D = get_node(owner_path)

var _charging: bool = false
var _charge_time: float = 0.0
var _cooldown_remaining: float = 0.0
var _profile_shot: Dictionary = {}
var _profile_shot_released: bool = false
var charge_rate_bonus: float = 0.0
var full_charge_damage_multiplier_bonus: float = 0.0
var pierce_bonus: int = 0


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _charging:
		_charge_time += delta * maxf(0.2, attack_speed) * (1.0 + charge_rate_bonus)


func start_charge() -> bool:
	if _charging or _cooldown_remaining > 0.0:
		return false
	_charging = true
	_charge_time = 0.0
	return true


func release_charge(direction: Vector2) -> bool:
	if not _charging:
		return false
	_charging = false
	if _charge_time < min_charge_time:
		_charge_time = 0.0
		_cooldown_remaining = cooldown * 0.35
		return false

	var charge_ratio := get_charge_ratio()
	_fire_arrow(direction, charge_ratio)
	_charge_time = 0.0
	_cooldown_remaining = cooldown / maxf(0.2, attack_speed)
	return true


func cancel_charge() -> void:
	_charging = false
	_charge_time = 0.0


func reset_runtime_state() -> void:
	cancel_charge()
	_cooldown_remaining = 0.0
	cancel_profile_shot()


func is_charging() -> bool:
	return _charging


func get_cooldown_remaining() -> float:
	return _cooldown_remaining


func get_charge_ratio() -> float:
	return clampf(_charge_time / full_charge_time, 0.0, 1.0)


func begin_profile_shot(definition: Dictionary) -> Dictionary:
	if is_profile_action_active() or not _profile_definition_is_valid(definition):
		return {}
	var direction: Vector2 = definition["direction"]
	if direction.length_squared() <= 0.001:
		direction = Vector2.RIGHT.rotated(global_rotation)
	_profile_shot = definition.duplicate(true)
	_profile_shot["direction"] = direction.normalized()
	_profile_shot_released = false
	return _profile_shot.duplicate(true)


func release_profile_shot() -> bool:
	if _profile_shot.is_empty() or _profile_shot_released:
		return false
	var arrow := ArrowScene.instantiate()
	var direction: Vector2 = _profile_shot["direction"]
	arrow.global_position = global_position + direction * 28.0
	arrow.direction = direction
	arrow.damage = float(_profile_shot["damage"])
	arrow.speed = float(_profile_shot["speed"])
	arrow.pierce = int(_profile_shot["pierce"])
	arrow.full_charge = bool(_profile_shot["full_charge"])
	arrow.time_energy_restore = float(_profile_shot["time_energy_restore"])
	arrow.action_token = int(_profile_shot["token"])
	arrow.energy_reward_once_per_action = bool(
		_profile_shot.get("energy_reward_once_per_action", false)
	)
	arrow.attack_tags.clear()
	for tag_value: Variant in _profile_shot["tags"]:
		var tag := str(tag_value)
		if not tag.is_empty() and not arrow.attack_tags.has(tag):
			arrow.attack_tags.append(tag)
	arrow.source = self
	arrow.owner_entity = owner_player
	var current_scene := get_tree().current_scene
	if current_scene == null:
		arrow.free()
		return false
	current_scene.add_child(arrow)
	_profile_shot_released = true
	return true


func is_profile_action_active() -> bool:
	return not _profile_shot.is_empty()


func cancel_profile_shot() -> void:
	_profile_shot.clear()
	_profile_shot_released = false


func finish_profile_shot() -> void:
	cancel_profile_shot()


func _fire_arrow(direction: Vector2, charge_ratio: float) -> void:
	var shot_direction := direction.normalized()
	if shot_direction.length_squared() <= 0.001:
		shot_direction = Vector2.RIGHT.rotated(global_rotation)
	var arrow := ArrowScene.instantiate()
	arrow.global_position = global_position + shot_direction * 28.0
	arrow.direction = shot_direction
	var full_charge_multiplier := 1.0 + full_charge_damage_multiplier_bonus if charge_ratio >= 0.98 else 1.0
	arrow.damage = base_attack * lerpf(0.75, 1.75, charge_ratio) * full_charge_multiplier
	arrow.speed = lerpf(440.0, 680.0, charge_ratio)
	arrow.pierce = (1 if charge_ratio >= 0.98 else 0) + pierce_bonus
	arrow.full_charge = charge_ratio >= 0.98
	arrow.time_energy_restore = full_charge_time_restore if arrow.full_charge else 0.0
	arrow.source = self
	arrow.owner_entity = owner_player
	get_tree().current_scene.add_child(arrow)
	EventBus.player_attacked.emit(&"bow", {"charge": charge_ratio})


func _profile_definition_is_valid(definition: Dictionary) -> bool:
	for field: String in [
		"token",
		"direction",
		"damage",
		"speed",
		"pierce",
		"full_charge",
		"time_energy_restore",
		"energy_reward_once_per_action",
		"tags",
		"source_action_id",
	]:
		if not definition.has(field):
			return false
	if typeof(definition["token"]) != TYPE_INT or int(definition["token"]) <= 0:
		return false
	if not definition["direction"] is Vector2:
		return false
	if not _finite_non_negative(definition["damage"]) or float(definition["damage"]) <= 0.0:
		return false
	if not _finite_non_negative(definition["speed"]) or float(definition["speed"]) <= 0.0:
		return false
	if typeof(definition["pierce"]) != TYPE_INT or int(definition["pierce"]) < 0:
		return false
	if typeof(definition["full_charge"]) != TYPE_BOOL:
		return false
	if not _finite_non_negative(definition["time_energy_restore"]):
		return false
	if typeof(definition["energy_reward_once_per_action"]) != TYPE_BOOL:
		return false
	if not definition["tags"] is Array or str(definition["source_action_id"]).is_empty():
		return false
	return true


func _finite_non_negative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0
