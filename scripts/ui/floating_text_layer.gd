class_name FloatingTextLayer
extends CanvasLayer

@export var text_lifetime: float = 0.65
@export var vertical_drift: float = 38.0

var _active_entries: Array[Dictionary] = []


func _ready() -> void:
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


func _process(delta: float) -> void:
	for index: int in range(_active_entries.size() - 1, -1, -1):
		var entry: Dictionary = _active_entries[index]
		var label := entry.get("label") as Label
		if label == null or not is_instance_valid(label):
			_active_entries.remove_at(index)
			continue
		var elapsed := float(entry.get("elapsed", 0.0)) + delta
		entry["elapsed"] = elapsed
		var lifetime := maxf(0.1, float(entry.get("lifetime", text_lifetime)))
		var progress := clampf(elapsed / lifetime, 0.0, 1.0)
		var step_count := 6
		var step := mini(step_count, floori(progress * float(step_count)))
		var start: Vector2 = entry.get("start", Vector2.ZERO)
		var drift_per_step := vertical_drift / float(step_count)
		label.position = Vector2(
			roundf(start.x),
			roundf(start.y - float(step) * drift_per_step)
		)
		label.modulate.a = 1.0 if progress < 0.55 else 1.0 - (progress - 0.55) / 0.45
		_active_entries[index] = entry
		if elapsed >= lifetime:
			_active_entries.remove_at(index)
			label.queue_free()


func _on_hit_confirmed(damage_info: Variant, target: Node, final_amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target is Node2D:
		return
	var target_2d := target as Node2D
	var label := Label.new()
	label.text = _format_damage(final_amount, damage_info)
	label.position = Vector2(
		roundf(target_2d.global_position.x - 18.0),
		roundf(target_2d.global_position.y - 42.0)
	)
	label.modulate = _damage_color(damage_info)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.035, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", _font_size(damage_info))
	label.scale = _label_scale(damage_info)
	label.pivot_offset = Vector2(18.0, 10.0)
	label.z_index = 100
	add_child(label)
	_active_entries.append({
		"label": label,
		"start": label.position,
		"elapsed": 0.0,
		"lifetime": text_lifetime + (0.12 if _is_power_hit(damage_info) else 0.0),
	})


func _format_damage(final_amount: float, damage_info: Variant) -> String:
	var prefix := ""
	if damage_info != null and damage_info.tags.has("attack:full_charge"):
		prefix = ">>"
	elif damage_info != null and damage_info.tags.has("attack:finisher"):
		prefix = "◆"
	elif damage_info != null and damage_info.tags.has("attack:heavy"):
		prefix = "!"
	elif damage_info != null and damage_info.tags.has("time:echo"):
		prefix = "⌛"
	return "%s%d" % [prefix, roundi(final_amount)]


func _damage_color(damage_info: Variant) -> Color:
	if damage_info != null and damage_info.tags.has("enemy:melee"):
		return Color(1.0, 0.35, 0.3)
	if damage_info != null and damage_info.tags.has("enemy:projectile"):
		return Color(1.0, 0.72, 0.28)
	if damage_info != null and damage_info.tags.has("attack:full_charge"):
		return Color(0.55, 1.0, 0.72)
	if damage_info != null and damage_info.tags.has("attack:finisher"):
		return Color(1.0, 0.78, 0.22)
	if damage_info != null and damage_info.tags.has("attack:heavy"):
		return Color(0.45, 0.9, 1.0)
	if damage_info != null and damage_info.tags.has("time:echo"):
		return Color(0.52, 0.48, 1.0)
	return Color(1.0, 1.0, 0.86)


func get_active_text_snapshots_for_test() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _active_entries:
		var label := entry.get("label") as Label
		if label == null or not is_instance_valid(label):
			continue
		result.append({
			"text": label.text,
			"position": label.position,
			"pixel_snapped": is_equal_approx(label.position.x, roundf(label.position.x))
				and is_equal_approx(label.position.y, roundf(label.position.y)),
			"font_size": label.get_theme_font_size("font_size"),
			"outline_size": label.get_theme_constant("outline_size"),
		})
	return result


func _font_size(damage_info: Variant) -> int:
	if damage_info != null and damage_info.tags.has("attack:heavy"):
		return 22
	if damage_info != null and damage_info.tags.has("attack:finisher"):
		return 20
	return 16


func _label_scale(damage_info: Variant) -> Vector2:
	if damage_info != null and damage_info.tags.has("attack:heavy"):
		return Vector2(1.25, 1.25)
	if damage_info != null and damage_info.tags.has("attack:finisher"):
		return Vector2(1.12, 1.12)
	return Vector2.ONE


func _is_power_hit(damage_info: Variant) -> bool:
	return damage_info != null and (
		damage_info.tags.has("attack:heavy")
		or damage_info.tags.has("attack:finisher")
		or damage_info.tags.has("attack:full_charge")
	)
