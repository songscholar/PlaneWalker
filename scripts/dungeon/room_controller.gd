class_name RoomController
extends Node2D

const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")

@export var room_id: StringName = &"combat_room_01"
@export var enemy_scenes: Array[PackedScene] = []
@export var boss_scene: PackedScene
@export var spawn_warning_scene: PackedScene
@export var reward_marker_path: NodePath
@export var run_director_path: NodePath
@export var rooms_per_floor: int = 5
@export var spawn_warning_duration: float = 0.45
@export var curse_offer_rooms: Array[int] = [4]
@export var elite_rooms: Array[int] = [3]
@export var event_rooms: Array[int] = [2]
@export var auto_start: bool = true

@onready var spawn_points: Node2D = $SpawnPoints
@onready var boss_spawn_point: Marker2D = $BossSpawnPoint
@onready var enemies_root: Node2D = $Enemies
@onready var reward_marker: Node = get_node_or_null(reward_marker_path)

var _alive_enemies: int = 0
var _cleared: bool = false
var _run_director: RunDirector


func _ready() -> void:
	_run_director = get_node_or_null(run_director_path) as RunDirector
	if _run_director == null:
		_run_director = RunDirectorScript.new()
		add_child(_run_director)
	_run_director.configure_fixed_sequence(rooms_per_floor, event_rooms, elite_rooms, curse_offer_rooms)
	EventBus.entity_died.connect(_on_entity_died)
	EventBus.reward_selected.connect(_on_reward_selected)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	if auto_start:
		call_deferred("begin_run")


func begin_run() -> void:
	if GameState.current_room <= 0:
		GameState.current_room = 1
	start_room()


func start_room() -> void:
	GameState.set_phase(GameState.GamePhase.DUNGEON)
	_cleared = false
	if reward_marker != null:
		reward_marker.visible = false
	_clear_enemy_nodes()
	GameState.set_current_room_type(_current_room_type())
	var active_room_id := _active_room_id()
	EventBus.room_started.emit(active_room_id)
	EventBus.publish(EventBus.ROOM_STARTED, {"room_id": active_room_id, "room_type": GameState.get_current_room_type()})
	await _spawn_enemies()


func _spawn_enemies() -> void:
	_alive_enemies = 0
	if _is_event_room():
		_cleared = true
		GameState.set_phase(GameState.GamePhase.SELECTION)
		return
	if _is_boss_room() and boss_scene != null:
		_show_spawn_warning(boss_spawn_point.global_position, 44.0)
		await get_tree().create_timer(spawn_warning_duration).timeout
		if GameState.phase == GameState.GamePhase.DEATH:
			return
		_spawn_boss()
		return

	var points := spawn_points.get_children()
	var spawn_count := _run_director.spawn_count_for(GameState.current_room, points.size(), enemy_scenes.size())
	for index: int in range(spawn_count):
		_show_spawn_warning(points[index].global_position, 24.0)
	await get_tree().create_timer(spawn_warning_duration).timeout
	if GameState.phase == GameState.GamePhase.DEATH:
		return
	for index: int in range(spawn_count):
		var scene_index := mini(index, enemy_scenes.size() - 1)
		var enemy := enemy_scenes[scene_index].instantiate()
		enemies_root.add_child(enemy)
		enemy.global_position = points[index].global_position
		if _is_elite_room() and index == spawn_count - 1 and enemy.has_method("apply_elite_modifier"):
			enemy.apply_elite_modifier()
		_alive_enemies += 1
		enemy.set_meta("room_counted", true)
		EventBus.enemy_spawned.emit(enemy)
		EventBus.publish(EventBus.ENEMY_SPAWNED, {"enemy": enemy})


func _show_spawn_warning(spawn_position: Vector2, radius: float) -> void:
	if spawn_warning_scene != null:
		var warning := spawn_warning_scene.instantiate()
		warning.radius = radius
		warning.duration = spawn_warning_duration
		add_child(warning)
		warning.global_position = spawn_position


func _spawn_boss() -> void:
	GameState.set_phase(GameState.GamePhase.BOSS_FIGHT)
	var boss := boss_scene.instantiate()
	enemies_root.add_child(boss)
	boss.global_position = boss_spawn_point.global_position
	_alive_enemies = 1
	boss.set_meta("room_counted", true)
	EventBus.enemy_spawned.emit(boss)
	EventBus.publish(EventBus.ENEMY_SPAWNED, {"enemy": boss, "boss": true})


func _on_enemy_spawned(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.get_parent() != enemies_root:
		return
	if bool(enemy.get_meta("room_counted", false)):
		return
	enemy.set_meta("room_counted", true)
	_alive_enemies += 1


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
	GameState.set_curse_offer_pending(_should_offer_curse())
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
			"blessings": GameState.current_run.get("blessings", []),
			"talent_choices": GameState.current_run.get("talent_choices", []),
			"curses": GameState.current_run.get("curses", []),
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
	return _current_room_type() == &"boss"


func _is_elite_room() -> bool:
	return _current_room_type() == &"elite"


func _is_event_room() -> bool:
	return _current_room_type() == &"event"


func _current_room_type() -> StringName:
	return StringName(_run_director.room_type_for(GameState.current_room))


func _should_offer_curse() -> bool:
	return _run_director.should_offer_curse(GameState.current_room)


func _on_player_died(killer: Variant) -> void:
	_clear_enemy_nodes()
	if reward_marker != null:
		reward_marker.visible = false
	GameState.fail_run(killer)
