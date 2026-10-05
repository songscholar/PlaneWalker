class_name WeaponTargetPolicy
extends RefCounted

const Construct := preload("res://scripts/enemies/launch/launch_boss_construct.gd")
const Wall := preload("res://scripts/enemies/launch/launch_boss_wall.gd")
const Debris := preload("res://scripts/enemies/launch/launch_ruin_debris.gd")
const ForestAuxiliary := preload("res://scripts/enemies/launch/launch_forest_auxiliary_construct.gd")
const PLAYER_ATTACK_MASK := 1 | 4


static func is_arena_construct(target: Node) -> bool:
	return is_instance_valid(target) and (target is Construct or target is Wall or target is Debris or target is ForestAuxiliary)


static func is_attackable(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if target.is_in_group("enemies"):
		return true
	if is_arena_construct(target):
		var state: Dictionary = target.native_construct_snapshot()
		return state.has("current_hp") and not bool(state.get("broken", false)) and not bool(state.get("retired", false)) and not bool(state.get("expired", false)) and not bool(state.get("used", false)) and target.collision_layer == 1
	return false


static func swept_hurtboxes(projectile: Area2D, origin: Vector2, destination: Vector2) -> Array[Area2D]:
	var result: Array[Area2D] = []
	var collision := projectile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not collision.shape is CircleShape2D or not projectile.is_inside_tree():
		return result
	# Area2D has no continuous collision detection; sweep the authored circular hit width.
	var radius := (collision.shape as CircleShape2D).radius * maxf(absf(projectile.global_scale.x), absf(projectile.global_scale.y))
	var capsule := CapsuleShape2D.new()
	capsule.radius = radius
	capsule.height = origin.distance_to(destination) + radius * 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = capsule
	query.transform = Transform2D(origin.direction_to(destination).angle() + PI * 0.5, (origin + destination) * 0.5)
	query.collision_mask = projectile.collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [projectile.get_rid()]
	for hit: Dictionary in projectile.get_world_2d().direct_space_state.intersect_shape(query, 256):
		var area := hit.get("collider") as Area2D
		if area != null and area.has_method("receive_hit") and is_attackable(area.get_parent()) and not result.has(area):
			result.append(area)
	result.sort_custom(func(left: Area2D, right: Area2D):
		var left_distance := origin.distance_squared_to(left.global_position)
		var right_distance := origin.distance_squared_to(right.global_position)
		return str(left.get_path()) < str(right.get_path()) if is_equal_approx(left_distance, right_distance) else left_distance < right_distance
	)
	return result
