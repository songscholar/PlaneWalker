extends RefCounted

const ReplayWorld := preload("res://scripts/replay/player_replay_world.gd")


static func replay_world(node: Variant) -> SubViewport:
	if not is_instance_valid(node) or not node is Node:
		return null
	var ancestor: Node = node
	while ancestor != null:
		if ancestor is ReplayWorld:
			return ancestor
		ancestor = ancestor.get_parent()
	return null


static func event_bus(node: Variant) -> Node:
	var world := replay_world(node)
	return world.event_bus() if world != null else EventBus


static func nodes_in_group(node: Node, group: StringName) -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(node) or node.get_tree() == null:
		return result
	var world := replay_world(node)
	for candidate: Node in node.get_tree().get_nodes_in_group(group):
		if replay_world(candidate) == world:
			result.append(candidate)
	return result


static func scene_root(node: Node) -> Node:
	var world := replay_world(node)
	return world if world != null else (node.get_tree().current_scene if node.is_inside_tree() else null)
