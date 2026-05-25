class_name Hitbox
extends Area2D

var _active_damage_info: DamageInfo
var _hit_areas: Array[Area2D] = []


func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)


func activate(damage_info: DamageInfo, duration: float) -> void:
	_active_damage_info = damage_info
	_hit_areas.clear()
	monitoring = true
	await get_tree().create_timer(duration).timeout
	monitoring = false
	_active_damage_info = null


func _on_area_entered(area: Area2D) -> void:
	if _active_damage_info == null:
		return
	if area in _hit_areas:
		return
	if not area.has_method("receive_hit"):
		return

	_hit_areas.append(area)
	area.receive_hit(_active_damage_info.copy_for_source(self))
