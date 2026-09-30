class_name TimeRift
extends Area2D

const GAMEPLAY_FRAMES_PER_SECOND := 60
const FRAME_SNAPSHOT_SCHEMA_VERSION := 1
const FRAME_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"payload_id",
	"source_id",
	"remaining_frames",
	"last_runtime_frame",
	"finished",
	"retirement_requested",
]

@export var duration: float = 4.0
@export var radius: float = 92.0
@export var slow_multiplier: float = 0.45

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Polygon2D = $Visual

var _affected: Array[Node] = []
var _remaining_duration: float = 0.0
var _remaining_frames: int = 0
var _finished: bool = false
var _finalized: bool = false
var _payload_id: StringName = &""
var _source_id: StringName = &""
var _world_payload_retire_callback: Callable = Callable()
var _retirement_requested: bool = false
var _last_runtime_frame: int = -1


func _ready() -> void:
	if _source_id == &"":
		_source_id = StringName("time_rift_%d" % get_instance_id())
	add_to_group("time_rifts")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_configure_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_set_remaining_frames(_seconds_to_frames(duration))
	call_deferred("_apply_overlapping_targets")


func _process(_delta: float) -> void:
	# The Area2D may project visuals here, but lifetime is fixed-frame gameplay.
	pass


func advance_frame(runtime_frame: int) -> bool:
	if (
		(_finished and not _retirement_requested)
		or runtime_frame < 0
		or (_last_runtime_frame >= 0 and runtime_frame != _last_runtime_frame + 1)
	):
		return false
	_last_runtime_frame = runtime_frame
	_set_remaining_frames(_remaining_frames - 1)
	if _remaining_frames <= 0:
		if _payload_id == &"":
			_expire()
		else:
			# WorldPayloadAuthority owns final retirement. Marking completion here is
			# reversible until the authority commits the whole frame.
			_finished = true
			set_process(false)
	return true


func configure_world_payload_identity(payload_id: StringName) -> bool:
	var normalized := StringName(str(payload_id).strip_edges())
	if (
		normalized == &""
		or is_inside_tree()
		or _last_runtime_frame >= 0
		or _finished
		or _finalized
	):
		return false
	if _payload_id != &"":
		return _payload_id == normalized
	_payload_id = normalized
	_source_id = StringName("world_payload:%s" % normalized)
	return true


func source_id() -> StringName:
	return _source_id


func is_finished() -> bool:
	return _finished


func configure_world_payload_retirement(callback: Callable) -> bool:
	if (
		_payload_id == &""
		or not callback.is_valid()
		or is_inside_tree()
		or _last_runtime_frame >= 0
		or _finished
		or _finalized
	):
		return false
	if _world_payload_retire_callback.is_valid():
		return _world_payload_retire_callback == callback
	_world_payload_retire_callback = callback
	return true


func world_payload_frame_snapshot() -> Dictionary:
	return {
		"schema_version": FRAME_SNAPSHOT_SCHEMA_VERSION,
		"payload_id": str(_payload_id),
		"source_id": str(_source_id),
		"remaining_frames": _remaining_frames,
		"last_runtime_frame": _last_runtime_frame,
		"finished": _finished,
		"retirement_requested": _retirement_requested,
	}


func restore_world_payload_frame_snapshot(snapshot: Dictionary) -> bool:
	if world_payload_frame_snapshot() == snapshot:
		return true
	if _finalized or not _valid_world_payload_frame_snapshot(snapshot):
		return false
	if (
		StringName(str(snapshot["payload_id"])) != _payload_id
		or StringName(str(snapshot["source_id"])) != _source_id
	):
		return false
	_set_remaining_frames(int(snapshot["remaining_frames"]))
	_last_runtime_frame = int(snapshot["last_runtime_frame"])
	_finished = bool(snapshot["finished"])
	_retirement_requested = bool(snapshot["retirement_requested"])
	set_process(not _finished)
	return world_payload_frame_snapshot() == snapshot


func _valid_world_payload_frame_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.size() != FRAME_SNAPSHOT_FIELDS.size():
		return false
	for field: String in FRAME_SNAPSHOT_FIELDS:
		if not snapshot.has(field):
			return false
	return (
		typeof(snapshot["schema_version"]) == TYPE_INT
		and int(snapshot["schema_version"]) == FRAME_SNAPSHOT_SCHEMA_VERSION
		and typeof(snapshot["payload_id"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and typeof(snapshot["source_id"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and typeof(snapshot["remaining_frames"]) == TYPE_INT
		and int(snapshot["remaining_frames"]) >= 0
		and typeof(snapshot["last_runtime_frame"]) == TYPE_INT
		and int(snapshot["last_runtime_frame"]) >= -1
		and typeof(snapshot["finished"]) == TYPE_BOOL
		and typeof(snapshot["retirement_requested"]) == TYPE_BOOL
		and (
			not bool(snapshot["retirement_requested"])
			or bool(snapshot["finished"])
		)
	)


func _set_remaining_frames(frame_count: int) -> void:
	_remaining_frames = maxi(0, frame_count)
	_remaining_duration = (
		float(_remaining_frames) / float(GAMEPLAY_FRAMES_PER_SECOND)
	)


static func _seconds_to_frames(seconds: float) -> int:
	if not is_finite(seconds) or seconds <= 0.0:
		return 0
	return maxi(1, roundi(seconds * float(GAMEPLAY_FRAMES_PER_SECOND)))


func _configure_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision_shape.shape = circle

	var points: PackedVector2Array = []
	var segments := 40
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	visual.polygon = points


func _on_body_entered(body: Node) -> void:
	_apply_target(body)


func _on_area_entered(area: Area2D) -> void:
	_apply_target(area)


func _apply_overlapping_targets() -> void:
	if _finished:
		return
	for body: Node in get_overlapping_bodies():
		_apply_target(body)
	for area: Area2D in get_overlapping_areas():
		_apply_target(area)
	for body: Node in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D and global_position.distance_to(body.global_position) <= radius:
			_apply_target(body)


func _apply_target(target: Node) -> void:
	if _finished:
		return
	if not target.has_method("apply_time_rift"):
		return
	if _affected.has(target):
		return
	target.apply_time_rift(_source_id, slow_multiplier)
	_affected.append(target)


func _on_body_exited(body: Node) -> void:
	_clear_target(body)


func _on_area_exited(area: Area2D) -> void:
	_clear_target(area)


func _expire() -> void:
	_finish(true)


func cancel(publish_end_event: bool = true) -> void:
	if _payload_id != &"":
		if _finalized or _retirement_requested:
			return
		var reason := &"cancelled" if publish_end_event else &"silent_cancel"
		if not _world_payload_retire_callback.is_valid():
			push_error("World-owned Time Rift is missing its retirement callback")
			return
		var retired_value: Variant = _world_payload_retire_callback.call(
			_payload_id,
			reason
		)
		if not retired_value is Dictionary or not bool(
			(retired_value as Dictionary).get("ok", false)
		):
			push_error("World-owned Time Rift retirement was rejected")
			return
		_retirement_requested = true
		_finished = true
		set_process(false)
		for target: Node in _affected.duplicate():
			_clear_target(target)
		return
	_finish(publish_end_event)


func retire_world_payload(reason: StringName) -> void:
	_retirement_requested = false
	_finish(reason not in [
		&"replay_replaced",
		&"runtime_reset",
		&"player_runtime_reset",
		&"silent_cancel",
		&"transaction_rollback",
	], false)


func _finish(publish_end_event: bool, release_node: bool = true) -> void:
	if _finalized:
		return
	_finished = true
	_finalized = true
	set_process(false)
	for target: Node in _affected.duplicate():
		_clear_target(target)
	if publish_end_event:
		EventBus.time_skill_ended.emit(&"time_rift", {})
	if release_node:
		queue_free()


func _clear_target(target: Node) -> void:
	if not _affected.has(target):
		return
	_affected.erase(target)
	if is_instance_valid(target) and target.has_method("clear_time_rift"):
		target.clear_time_rift(_source_id)
