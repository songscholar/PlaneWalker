class_name TrainingArena
extends Node2D

const Target := preload("res://scenes/training/training_target.tscn")
const Boss := preload("res://scenes/training/training_warden.tscn")
const Floor := preload("res://data/content_packs/base/assets/training/training_floor.png")
const PLAYER_ENTRY := Vector2(204, 204)
const TARGET_ENTRY := Vector2(424, 204)

var _attempt: Node2D
var _target: Node2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background := Sprite2D.new()
	background.name = "Background"
	background.texture = Floor
	background.centered = false
	add_child(background)
	for bounds: Rect2 in [Rect2(0, 0, 640, 76), Rect2(0, 328, 640, 32), Rect2(0, 76, 16, 252), Rect2(624, 76, 16, 252)]:
		var wall := StaticBody2D.new()
		wall.position = bounds.get_center()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = bounds.size
		collider.shape = shape
		wall.add_child(collider)
		add_child(wall)


func begin_attempt(player: Node2D, request: Dictionary) -> Node2D:
	retire_attempt()
	_attempt = Node2D.new()
	_attempt.name = "Attempt"
	add_child(_attempt)
	_target = Boss.instantiate() if request.task_id == "T-05" else Target.instantiate()
	_target.configure_hostile_identity(StringName("training-%d-%s-target" % [int(request.seed), str(request.task_id).to_lower()]), 1)
	_attempt.add_child(_target)
	_target.global_position = global_position + TARGET_ENTRY
	_target.target = player
	_target.set_meta("stable_target_id", "training-target-%d" % int(request.seed))
	if request.task_id == "T-05":
		_target.health.configure_run(player.current_run_id())
		for field: String in ["run_id", "room_id", "encounter_id", "encounter_spawn_id", "encounter_enemy_id"]:
			_target.set_meta(field, {"run_id": str(player.current_run_id()), "room_id": "training-room", "encounter_id": "training-t-05", "encounter_spawn_id": str(_target.hostile_source_id), "encounter_enemy_id": "boss_chrono_warden"}[field])
	return _target


func native_target() -> Node2D:
	return _target if is_instance_valid(_target) else null


func retire_attempt() -> void:
	if is_instance_valid(_attempt):
		for actor: Node in _attempt.get_children():
			actor.remove_from_group("enemies")
			actor.remove_from_group("bosses")
			actor.remove_from_group("time_stoppable")
			actor.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(_attempt)
		_attempt.queue_free()
	_attempt = null
	_target = null
