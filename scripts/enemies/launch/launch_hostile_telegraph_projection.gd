class_name LaunchHostileTelegraphProjection
extends Node2D

const Telegraph := preload("res://scripts/fx/combat_telegraph_2d.gd")
var _clip_bounds := Rect2()


static func present(owner: Node2D, facts: Array, action_id: String, phase: String) -> bool:
	var holder := owner.get_node_or_null("LaunchTelegraphs") as Node2D
	var visible_facts: Array = facts if phase in ["WARNING", "ACTIVE"] else []
	if holder == null and visible_facts.is_empty():
		return true
	if holder == null:
		holder = load("res://scripts/enemies/launch/launch_hostile_telegraph_projection.gd").new()
		holder.name = "LaunchTelegraphs"
		holder.z_index = -1
		owner.add_child(holder)
	holder.z_index = 4 if action_id.begins_with("traitor.counter_") else -1
	var motion: Dictionary = owner.get("_room_motion")
	if not motion.is_empty():
		var bounds: Dictionary = motion.bounds
		holder._clip_bounds = Rect2(Vector2(float(bounds.x), float(bounds.y)) - owner.global_position, Vector2(float(bounds.width), float(bounds.height)))
		holder.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		holder.queue_redraw()
	while holder.get_child_count() > visible_facts.size():
		var old := holder.get_child(holder.get_child_count() - 1)
		holder.remove_child(old)
		old.queue_free()
	for index: int in range(visible_facts.size()):
		var telegraph: Node2D
		if index >= holder.get_child_count():
			telegraph = Telegraph.new()
			telegraph.name = "Primitive%d" % index
			holder.add_child(telegraph)
			telegraph.top_level = false
			telegraph.set_process(false)
		else:
			telegraph = holder.get_child(index)
		telegraph.set_accessibility_options(bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))
		if not telegraph.project_fact(visible_facts[index], action_id):
			return false
	return true


func _draw() -> void:
	if _clip_bounds.has_area():
		draw_rect(_clip_bounds, Color.WHITE)
