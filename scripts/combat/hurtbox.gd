class_name Hurtbox
extends Area2D

@export var health_component_path: NodePath

@onready var health_component: Node = get_node(health_component_path)


func receive_hit(damage_info: RefCounted) -> float:
	if health_component == null:
		return 0.0
	return health_component.take_damage(damage_info)
