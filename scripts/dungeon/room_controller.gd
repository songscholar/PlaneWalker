class_name RoomController
extends Node2D

@export var room_id: StringName = &"combat_room_01"
@export var enemy_scenes: Array[PackedScene] = []
@export var boss_scene: PackedScene
@export var reward_marker_path: NodePath
@export var rooms_per_floor: int = 5

@onready var spawn_points: Node2D = $SpawnPoints
@onready var boss_spawn_point: Marker2D = $BossSpawnPoint
@onready var enemies_root: Node2D = $Enemies
@onready var reward_marker: Node = get_node_or_null(reward_marker_path)

var _alive_enemies: int = 0
var _cleared: bool = false


func _ready() -> void:
	EventBus.entity_died.connect(_on_entity_died)
	EventBus.reward_selected.connect(_on_reward_selected)
	call_deferred("_start_initial_room")


func _start_initial_room() -> void:
	if GameState.current_room <= 0:
		GameState.current_room = 1
	start_room()


func start_room() -> void:
	GameState.set_phase(GameState.GamePhase.DUNGEON)
	_cleared = false
	if reward_marker != null:
		reward_marker.visible = false
	_clear_enemy_nodes()
	_spawn_enemies()
	var active_room_id := _active_room_id()
	EventBus.room_started.emit(active_room_id)
	EventBus.publish(EventBus.ROOM_STARTED, {"room_id": active_room_id})


func _spawn_enemies() -> void:
	_alive_enemies = 0
	if _is_boss_room() and boss_scene != null:
		_spawn_boss()
		return

	var points := spawn_points.get_children()
	var spawn_count := mini(mini(points.size(), enemy_scenes.size()), maxi(1, GameState.current_room))
	for index: int in range(spawn_count):
		var scene_index := mini(index, enemy_scenes.size() - 1)
		var enemy := enemy_scenes[scene_index].instantiate()
		enemies_root.add_child(enemy)
		enemy.global_position = points[index].global_position
		_alive_enemies += 1
		EventBus.enemy_spawned.emit(enemy)
		EventBus.publish(EventBus.ENEMY_SPAWNED, {"enemy": enemy})


func _spawn_boss() -> void:
	GameState.set_phase(GameState.GamePhase.BOSS_FIGHT)
	var boss := boss_scene.instantiate()
	enemies_root.add_child(boss)
	boss.global_position = boss_spawn_point.global_position
	_alive_enemies = 1
	EventBus.enemy_spawned.emit(boss)
	EventBus.publish(EventBus.ENEMY_SPAWNED, {"enemy": boss, "boss": true})


func _on_entity_died(entity: Node, _killer: Variant) -> void:
	if entity.is_in_group("player"):
		_on_player_died(_killer)
		return
	if _cleared or GameState.phase == GameState.GamePhase.DEATH or not entity.is_in_group("enemies"):
		return
	_alive_enemies = max(0, _alive_enemies - 1)
	if _alive_enemies == 0:
		_clear_room()


func _clear_room() -> void:
	if GameState.phase == GameState.GamePhase.DEATH:
		return
	_cleared = true
	GameState.set_phase(GameState.GamePhase.ROOM_CLEAR)
	if reward_marker != null:
		reward_marker.visible = true
	var active_room_id := _active_room_id()
	EventBus.room_cleared.emit(active_room_id)
	EventBus.publish(EventBus.ROOM_CLEARED, {"room_id": active_room_id})


func _on_reward_selected(_reward_data: Dictionary) -> void:
	if not _cleared or GameState.phase == GameState.GamePhase.DEATH:
		return
	if GameState.current_room >= rooms_per_floor:
		GameState.end_run({
			"result": "floor_cleared",
			"floor": GameState.current_floor,
			"rooms_cleared": GameState.current_room,
			"run_time": GameState.run_timer,
			"rewards": GameState.current_run.get("rewards", []),
		})
		return
	GameState.current_room += 1
	call_deferred("start_room")


func _clear_enemy_nodes() -> void:
	for enemy: Node in enemies_root.get_children():
		enemy.queue_free()


func _active_room_id() -> StringName:
	return StringName("%s_%02d" % [room_id, GameState.current_room])


func _is_boss_room() -> bool:
	return GameState.current_room >= rooms_per_floor


func _on_player_died(killer: Variant) -> void:
	_clear_enemy_nodes()
	if reward_marker != null:
		reward_marker.visible = false
	GameState.fail_run(killer)
