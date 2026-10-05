class_name Hitbox
extends Area2D

static var _contact_dispatch_depth := 0

var _active_damage_info: RefCounted
var _hit_areas: Array[Area2D] = []


func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)


func activate(damage_info: RefCounted) -> void:
	_active_damage_info = damage_info
	_hit_areas.clear()
	monitoring = true


func deactivate() -> void:
	monitoring = false
	_active_damage_info = null
	_hit_areas.clear()


func cancel() -> void:
	deactivate()


func is_active() -> bool:
	return monitoring and _active_damage_info != null


static func is_dispatching_contact() -> bool:
	return _contact_dispatch_depth > 0


static func dispatch_contact(callback: Callable) -> void:
	_contact_dispatch_depth += 1
	callback.call()
	_contact_dispatch_depth -= 1


func _on_area_entered(area: Area2D) -> void:
	if _active_damage_info == null:
		return
	if area in _hit_areas:
		return
	if not area.has_method("receive_hit"):
		return

	_hit_areas.append(area)
	dispatch_contact(Callable(area, "receive_hit").bind(_active_damage_info.copy_for_source(self)))
