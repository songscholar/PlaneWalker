class_name BowWeapon
extends Node2D

const ArrowScene := preload("res://scenes/combat/player_arrow.tscn")

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0

@onready var owner_player: Node2D = get_node(owner_path)

var _profile_shot: Dictionary = {}
var _profile_shot_released: bool = false


func reset_runtime_state() -> void:
	cancel_profile_shot()


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
