class_name EnemyProjectile
extends Area2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var speed: float = 190.0
@export var lifetime: float = 4.0
@export var damage: float = 8.0

var direction: Vector2 = Vector2.RIGHT
var _time_stopped: bool = false


func _ready() -> void:
	add_to_group("time_stoppable")
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(lifetime).timeout
	if is_inside_tree():
		queue_free()


func _physics_process(delta: float) -> void:
	if _time_stopped:
		return
	global_position += direction.normalized() * speed * delta


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("receive_hit") and area.get_parent().is_in_group("player"):
		var damage_info := DamageInfoScript.new(damage, DamageInfoScript.DamageType.PHYSICAL, self, self)
		damage_info.tags = ["enemy:projectile"]
		area.receive_hit(damage_info)
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_node("HealthComponent"):
		var damage_info := DamageInfoScript.new(damage, DamageInfoScript.DamageType.PHYSICAL, self, self)
		damage_info.tags = ["enemy:projectile"]
		body.get_node("HealthComponent").take_damage(damage_info)
		queue_free()


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stopped = true
	await get_tree().create_timer(duration).timeout
	_time_stopped = false
