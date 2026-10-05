class_name WeaponTargetPolicy
extends RefCounted

const Construct := preload("res://scripts/enemies/launch/launch_boss_construct.gd")


static func is_arena_construct(target: Node) -> bool:
	return is_instance_valid(target) and target is Construct


static func is_attackable(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if target.is_in_group("enemies"):
		return true
	if is_arena_construct(target):
		var state: Dictionary = target.native_construct_snapshot()
		return not state.is_empty() and not state.broken and target.collision_layer == 1
	return false
