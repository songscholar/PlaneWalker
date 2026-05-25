class_name FloatingTextLayer
extends CanvasLayer

@export var text_lifetime: float = 0.65
@export var vertical_drift: float = 38.0


func _ready() -> void:
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


func _on_hit_confirmed(damage_info: Variant, target: Node, final_amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target is Node2D:
		return
	var target_2d := target as Node2D
	var label := Label.new()
	label.text = _format_damage(final_amount, damage_info)
	label.position = target_2d.global_position + Vector2(-18.0, -42.0)
	label.modulate = _damage_color(damage_info)
	label.z_index = 100
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0.0, -vertical_drift), text_lifetime)
	tween.tween_property(label, "modulate:a", 0.0, text_lifetime)
	tween.finished.connect(label.queue_free)


func _format_damage(final_amount: float, damage_info: Variant) -> String:
	var prefix := ""
	if damage_info != null and damage_info.tags.has("attack:full_charge"):
		prefix = ">>"
	elif damage_info != null and damage_info.tags.has("attack:heavy"):
		prefix = "!"
	return "%s%d" % [prefix, roundi(final_amount)]


func _damage_color(damage_info: Variant) -> Color:
	if damage_info != null and damage_info.tags.has("enemy:melee"):
		return Color(1.0, 0.35, 0.3)
	if damage_info != null and damage_info.tags.has("enemy:projectile"):
		return Color(1.0, 0.72, 0.28)
	if damage_info != null and damage_info.tags.has("attack:full_charge"):
		return Color(0.55, 1.0, 0.72)
	if damage_info != null and damage_info.tags.has("attack:heavy"):
		return Color(0.45, 0.9, 1.0)
	return Color(1.0, 1.0, 0.86)
