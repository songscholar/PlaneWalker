class_name PlayerArrow
extends Area2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var speed: float = 520.0
@export var lifetime: float = 1.5
@export var damage: float = 24.0
@export var pierce: int = 0
@export var full_charge: bool = false
@export var time_energy_restore: float = 0.0
@export var action_token: int = 0
@export var energy_reward_once_per_action: bool = false

@onready var visual: Polygon2D = $Visual

var direction: Vector2 = Vector2.RIGHT
var source: Node
var owner_entity: Node
var attack_tags: Array[String] = ["weapon:bow"]
var _hit_areas: Array[Area2D] = []


func _ready() -> void:
	add_to_group("player_arrows")
	area_entered.connect(_on_area_entered)
	rotation = direction.angle()
	await get_tree().create_timer(lifetime).timeout
	if is_inside_tree():
		queue_free()


func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * speed * delta


func _on_area_entered(area: Area2D) -> void:
	if area in _hit_areas:
		return
	if not area.has_method("receive_hit"):
		return
	if not area.get_parent().is_in_group("enemies"):
		return

	_hit_areas.append(area)
	var damage_info := DamageInfoScript.new(damage, DamageInfoScript.DamageType.PHYSICAL, source, owner_entity)
	damage_info.tags = attack_tags.duplicate()
	if full_charge and not damage_info.tags.has("attack:full_charge"):
		damage_info.tags.append("attack:full_charge")
	damage_info.knockback = direction.normalized() * 90.0
	area.receive_hit(damage_info)
	_restore_time_energy()
	if _hit_areas.size() > pierce:
		queue_free()


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
				&"bow_full_charge_energy"
			))
		):
			return
	var time_manager := owner_entity.get_node_or_null("TimeManager")
	if time_manager != null and time_manager.has_method("restore_energy"):
		time_manager.restore_energy(time_energy_restore)
