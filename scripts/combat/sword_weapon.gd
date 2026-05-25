class_name SwordWeapon
extends Node2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var owner_path: NodePath
@export var base_attack: float = 30.0

@onready var hitbox: Node = $Hitbox
@onready var owner_player: Node = get_node(owner_path)

var _combo_index: int = 0
var _combo_reset_time: float = 0.0
var _attacking: bool = false


func _process(delta: float) -> void:
	if _combo_reset_time > 0.0:
		_combo_reset_time -= delta
		if _combo_reset_time <= 0.0:
			_combo_index = 0


func try_attack(heavy: bool = false) -> bool:
	if _attacking:
		return false
	if heavy:
		_start_attack(2.0, 0.35, 0.12, 0.45, true)
		return true

	var combo_data := [
		{"mult": 0.8, "windup": 0.10, "active": 0.08, "recovery": 0.18},
		{"mult": 1.0, "windup": 0.12, "active": 0.08, "recovery": 0.20},
		{"mult": 1.3, "windup": 0.16, "active": 0.10, "recovery": 0.28},
	]
	var data: Dictionary = combo_data[_combo_index]
	_combo_index = (_combo_index + 1) % combo_data.size()
	_combo_reset_time = 0.8
	_start_attack(data["mult"], data["windup"], data["active"], data["recovery"], false)
	return true


func is_attacking() -> bool:
	return _attacking


func _start_attack(multiplier: float, windup: float, active: float, recovery: float, heavy: bool) -> void:
	_attacking = true
	await get_tree().create_timer(windup).timeout

	var damage_info := DamageInfoScript.new(base_attack * multiplier, DamageInfoScript.DamageType.PHYSICAL, self, owner_player)
	damage_info.tags = ["weapon:sword"]
	if heavy:
		damage_info.knockback = Vector2.RIGHT.rotated(global_rotation) * 260.0
		damage_info.tags.append("attack:heavy")
	else:
		damage_info.knockback = Vector2.RIGHT.rotated(global_rotation) * 120.0
	EventBus.player_attacked.emit(&"sword")
	EventBus.publish(EventBus.PLAYER_ATTACKED, {"weapon_id": "sword"})
	hitbox.activate(damage_info, active)

	await get_tree().create_timer(active + recovery).timeout
	_attacking = false
