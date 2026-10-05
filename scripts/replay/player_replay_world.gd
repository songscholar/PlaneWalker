extends SubViewport

const Bus := preload("res://autoload/event_bus.gd")

var _event_bus: Node
var _player_ref: WeakRef


func _init() -> void:
	world_2d = World2D.new()
	size = Vector2i(640, 360)
	process_mode = Node.PROCESS_MODE_DISABLED
	_event_bus = Bus.new()
	_event_bus.name = "ReplayEventBus"
	add_child(_event_bus)


func event_bus() -> Node:
	return _event_bus


func create_player() -> Node2D:
	if not isolation_valid() or _player_ref != null:
		return null
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Node2D = scene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	_player_ref = weakref(player)
	return player


func owns_player(player: Node2D) -> bool:
	return _player_ref != null and _player_ref.get_ref() == player and player.get_parent() == self


func isolation_valid() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and process_mode == Node.PROCESS_MODE_DISABLED and get_parent() != null and world_2d != null and world_2d != get_parent().get_viewport().world_2d and is_instance_valid(_event_bus) and _event_bus.get_parent() == self and _event_bus.get_script() == Bus
