class_name RoomController
extends Node2D

@export var room_id: StringName = &"combat_room_01"
@export var enemy_scenes: Array[PackedScene] = []
@export var reward_marker_path: NodePath

@onready var spawn_points: Node2D = $SpawnPoints
@onready var enemies_root: Node2D = $Enemies
@onready var reward_marker: Node = get_node_or_null(reward_marker_path)

var _alive_enemies: int = 0
var _cleared: bool = false


func _ready() -> void:
	EventBus.entity_died.connect(_on_entity_died)
	start_room()


func start_room() -> void:
	_cleared = false
	_spawn_enemies()
	EventBus.room_started.emit(room_id)
	EventBus.publish(EventBus.ROOM_STARTED, {"room_id": room_id})


func _spawn_enemies() -> void:
	_alive_enemies = 0
	var points := spawn_points.get_children()
	for index: int in range(mini(points.size(), enemy_scenes.size())):
		var enemy := enemy_scenes[index].instantiate()
		enemies_root.add_child(enemy)
		enemy.global_position = points[index].global_position
		_alive_enemies += 1
		EventBus.enemy_spawned.emit(enemy)
		EventBus.publish(EventBus.ENEMY_SPAWNED, {"enemy": enemy})


func _on_entity_died(entity: Node, _killer: Variant) -> void:
	if _cleared or not entity.is_in_group("enemies"):
		return
	_alive_enemies = max(0, _alive_enemies - 1)
	if _alive_enemies == 0:
		_clear_room()


func _clear_room() -> void:
	_cleared = true
	if reward_marker != null:
		reward_marker.visible = true
	EventBus.room_cleared.emit(room_id)
	EventBus.publish(EventBus.ROOM_CLEARED, {"room_id": room_id})
