class_name LaunchBossWatchHurtbox
extends Area2D

var _projection: Dictionary = {}


func receive_hit(damage_info: RefCounted) -> float:
	var body := get_parent()
	return float(body.receive_native_watch_hit(damage_info)) if body != null and body.has_method("receive_native_watch_hit") else 0.0


func stable_entity_key() -> String:
	var body := get_parent()
	return str(body.get("hostile_source_id")) if body != null else ""


func present(value: Dictionary) -> void:
	_projection = value.duplicate(true)
	visible = bool(value.hittable)
	collision_layer = 4 if value.hittable else 0
	var sprite := get_node("Sprite2D") as Sprite2D
	sprite.frame = 3 if value.current_hp <= 0.0 else (1 + int(value.runtime_frame / 12) % 2 if value.cast_generation > 0 else 0)


func projection_snapshot() -> Dictionary:
	return _projection.duplicate(true)
