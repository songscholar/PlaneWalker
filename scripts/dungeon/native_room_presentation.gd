class_name NativeRoomPresentation
extends Node

const DESIGN_SIZE := Vector2(640, 360)

var _host: Node
var _room_host: Node
var _camera: Camera2D
var _player: CharacterBody2D
var _legacy_visuals: Array[CanvasItem] = []
var _legacy_collisions: Array[Dictionary] = []
var _boundary: Node2D
var _legacy_camera_position := Vector2.ZERO
var _legacy_camera_zoom := Vector2.ONE
var _launch_mode := false


func configure(host: Node, room_host: Node, combat_room: Node2D) -> bool:
	if _host != null or not is_inside_tree() or not is_instance_valid(host) or not is_instance_valid(room_host) or not is_instance_valid(combat_room):
		return false
	_camera = combat_room.get_node_or_null("PixelCanvasCamera") as Camera2D
	_player = combat_room.get_node_or_null("Player") as CharacterBody2D
	if _camera == null or _player == null or not host.has_method("runtime_snapshot") or not room_host.has_method("active_room"):
		return false
	_host = host
	_room_host = room_host
	_legacy_camera_position = _camera.position
	_legacy_camera_zoom = _camera.zoom
	for path: String in ["Floor", "ArenaBounds", "Obstacles"]:
		var node := combat_room.get_node_or_null(path) as CanvasItem
		if node == null:
			return false
		_legacy_visuals.append(node)
		for collision: Node in node.find_children("*", "StaticBody2D", true, false):
			_legacy_collisions.append({"body": weakref(collision), "layer": collision.collision_layer, "mask": collision.collision_mask})
	_boundary = Node2D.new()
	_boundary.name = "NativeRoomBoundary"
	add_child(_boundary)
	for row: Array in [[Vector2(-8, 180), Vector2(16, 392)], [Vector2(648, 180), Vector2(16, 392)], [Vector2(320, -8), Vector2(640, 16)], [Vector2(320, 368), Vector2(640, 16)]]:
		var wall := StaticBody2D.new()
		wall.position = row[0]
		wall.collision_layer = 1
		wall.collision_mask = 0
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = row[1]
		collision.shape = shape
		wall.add_child(collision)
		_boundary.add_child(wall)
	_boundary.process_mode = Node.PROCESS_MODE_DISABLED
	_room_host.room_transitioned.connect(_on_room_transitioned)
	return true


func set_launch_mode(value: bool) -> void:
	_launch_mode = value
	for visual: CanvasItem in _legacy_visuals:
		visual.visible = not value
	for record: Dictionary in _legacy_collisions:
		var body: StaticBody2D = record.body.get_ref()
		if is_instance_valid(body):
			body.collision_layer = 0 if value else int(record.layer)
			body.collision_mask = 0 if value else int(record.mask)
	_boundary.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	_camera.position = DESIGN_SIZE * 0.5 if value else _legacy_camera_position
	_camera.zoom = Vector2.ONE if value else _legacy_camera_zoom
	_camera.reset_smoothing()
	_camera.force_update_scroll()


func _on_room_transitioned(_receipt: Dictionary) -> void:
	synchronize_active_room(_host.has_method("native_checkpoint_restore_active") and _host.native_checkpoint_restore_active())


func synchronize_active_room(preserve_position: bool = false) -> void:
	if not _launch_mode or not is_instance_valid(_player):
		return
	var room: Node2D = _room_host.active_room()
	var state: Dictionary = _host.runtime_snapshot()
	if not is_instance_valid(room):
		if not preserve_position and state.get("floor_plan", {}).get("current_node_id") == "entry":
			_player.global_position = DESIGN_SIZE * 0.5
		return
	var binding: Dictionary = room.binding_snapshot()
	if not binding.get("active", false) or binding.get("binding", {}).get("node_id") != state.get("floor_plan", {}).get("current_node_id"):
		return
	var camera_bounds := room.get_node_or_null("CameraBounds") as Area2D
	var entry := room.get_node_or_null("PlayerEntry") as Marker2D
	if camera_bounds == null or entry == null:
		return
	_camera.global_position = camera_bounds.global_position
	_camera.force_update_scroll()
	if preserve_position:
		return
	_player.global_position = entry.global_position
