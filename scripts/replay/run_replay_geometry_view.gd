extends Node2D

const Telegraph := preload("res://scripts/fx/combat_telegraph_2d.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")

var facts: Array = []
var frame := 0


func _ready() -> void:
	for value: Dictionary in facts:
		if frame > int(value.get("active_through_frame", -1)):
			continue
		var telegraph := Telegraph.new()
		add_child(telegraph)
		telegraph.project_fact(Actions.native_threat_fact(value))


static func _point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
