class_name SwordWeapon
extends Node2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0

@onready var hitbox: Node = $Hitbox
@onready var owner_player: Node = get_node(owner_path)

var combo_finisher_multiplier_bonus: float = 0.0
var heavy_damage_multiplier_bonus: float = 0.0
var heavy_execute_multiplier_bonus: float = 0.0
var heavy_execute_threshold: float = 0.3
var low_hp_damage_multiplier_bonus: float = 0.0
var low_hp_threshold: float = 0.35
var _combo_index: int = 0
var _attacking: bool = false
var _active: bool = false
var _current_attack: Dictionary = {}

const LIGHT_COMBO: Array[Dictionary] = [
	{"multiplier": 0.8, "windup": 0.10, "active": 0.08, "recovery": 0.18, "finisher": false},
	{"multiplier": 1.0, "windup": 0.12, "active": 0.08, "recovery": 0.20, "finisher": false},
	{"multiplier": 1.3, "windup": 0.16, "active": 0.10, "recovery": 0.28, "finisher": true},
]


func attack_definition(heavy: bool = false) -> Dictionary:
	var data: Dictionary
	if heavy:
		data = {"multiplier": 2.0, "windup": 0.35, "active": 0.12, "recovery": 0.45, "finisher": false}
	else:
		data = LIGHT_COMBO[_combo_index]
	return {
		"heavy": heavy,
		"finisher": bool(data["finisher"]),
		"multiplier": float(data["multiplier"]),
		"knockback": 260.0 if heavy else 120.0,
		"tags": ["attack:heavy", "weapon:sword"] if heavy else (
			["attack:finisher", "weapon:sword"]
			if bool(data["finisher"])
			else ["weapon:sword"]
		),
		"windup_frames": _seconds_to_frames(float(data["windup"])),
		"active_frames": _seconds_to_frames(float(data["active"])),
		"recovery_frames": _seconds_to_frames(float(data["recovery"])),
		"recovery_cancel_frame": _seconds_to_frames(0.24 if heavy else 0.10),
		"movement_multiplier": 0.2 if heavy else 0.55,
		"combo_reset_frames": maxi(1, ceili(0.8 * Engine.physics_ticks_per_second)),
	}


func begin_attack(heavy: bool = false) -> Dictionary:
	return begin_profile_attack(attack_definition(heavy))


func begin_profile_attack(definition: Dictionary) -> Dictionary:
	if _attacking or not _valid_profile_attack(definition):
		return {}
	_current_attack = definition.duplicate(true)
	_attacking = true
	_active = false
	if not bool(_current_attack["heavy"]):
		_combo_index = (_combo_index + 1) % LIGHT_COMBO.size()
	return _current_attack.duplicate(true)


func is_attacking() -> bool:
	return _attacking


func enter_active_phase() -> bool:
	return enter_profile_active_phase(_current_attack)


func enter_profile_active_phase(definition: Dictionary) -> bool:
	if not _attacking or _active or not _valid_profile_attack(definition):
		return false
	_current_attack = definition.duplicate(true)
	_active = true
	var effective_multiplier := float(_current_attack["multiplier"])
	var heavy := bool(_current_attack["heavy"])
	var finisher := bool(_current_attack["finisher"])
	if heavy:
		effective_multiplier *= 1.0 + heavy_damage_multiplier_bonus
	elif finisher:
		effective_multiplier *= 1.0 + combo_finisher_multiplier_bonus
	if low_hp_damage_multiplier_bonus > 0.0 and _owner_hp_ratio() <= low_hp_threshold:
		effective_multiplier *= 1.0 + low_hp_damage_multiplier_bonus

	var damage_info := DamageInfoScript.new(base_attack * effective_multiplier, DamageInfoScript.DamageType.PHYSICAL, self, owner_player)
	var profile_tags: Array[String] = []
	for tag: Variant in _current_attack["tags"] as Array:
		profile_tags.append(str(tag))
	damage_info.tags = profile_tags
	damage_info.knockback = Vector2.RIGHT.rotated(global_rotation) * float(_current_attack["knockback"])
	if heavy:
		if heavy_execute_multiplier_bonus > 0.0:
			damage_info.tags.append("talent:ruin_execute")
	hitbox.activate(damage_info)
	return true


func leave_active_phase() -> void:
	_active = false
	hitbox.deactivate()


func finish_attack() -> void:
	leave_active_phase()
	_attacking = false
	_current_attack.clear()


func cancel_attack() -> void:
	finish_attack()


func reset_combo() -> void:
	_combo_index = 0


func _seconds_to_frames(seconds: float) -> int:
	var timing_scale := 1.0 / maxf(0.2, attack_speed)
	return maxi(1, ceili(seconds * timing_scale * Engine.physics_ticks_per_second))


func _owner_hp_ratio() -> float:
	var health_component := owner_player.get_node_or_null("HealthComponent")
	if health_component == null:
		return 1.0
	return float(health_component.current_hp) / maxf(1.0, float(health_component.max_hp))


func _valid_profile_attack(definition: Dictionary) -> bool:
	if (
		typeof(definition.get("heavy")) != TYPE_BOOL
		or typeof(definition.get("finisher")) != TYPE_BOOL
		or typeof(definition.get("multiplier")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(definition.get("multiplier", 0.0)))
		or float(definition.get("multiplier", 0.0)) <= 0.0
		or typeof(definition.get("knockback")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(definition.get("knockback", 0.0)))
		or float(definition.get("knockback", -1.0)) < 0.0
		or not definition.get("tags") is Array
	):
		return false
	var tags: Array = definition["tags"]
	if tags.is_empty():
		return false
	for tag: Variant in tags:
		if typeof(tag) not in [TYPE_STRING, TYPE_STRING_NAME] or str(tag).is_empty():
			return false
	return true
