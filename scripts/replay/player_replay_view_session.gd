class_name PlayerReplayViewSession
extends RefCounted

const Playback := preload("res://scripts/replay/replay_player.gd")
const PlayerScript := preload("res://scripts/player/player_controller.gd")
const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

var _playback: RefCounted
var _target_ref: WeakRef
var _world_ref: WeakRef
var _identity: Dictionary = {}
var _cursor := -1
var _busy := false


func configure(replay: Dictionary, target: Node2D) -> Dictionary:
	if _playback != null or not _isolated(target):
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	var playback := Playback.new()
	var result: Dictionary = playback.load_full_player_replay(replay, target.full_player_replay_identity())
	if not result.ok:
		return result
	_playback = playback
	_target_ref = weakref(target)
	_world_ref = weakref(SceneScope.replay_world(target))
	_identity = target.full_player_replay_identity().duplicate(true)
	return _success()


func snapshot() -> Dictionary:
	return {"loaded": _playback != null, "cursor": _cursor, "frame_count": _playback.full_player_frame_count() if _playback != null else 0, "identity": _identity.duplicate(true)}


func seek(index: int) -> Dictionary:
	var target := _target()
	if target == null or _busy:
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	_busy = true
	var restored: Dictionary = _playback.restore_full_player_frame(target, index)
	if restored.ok:
		_cursor = int(restored.context.index)
	_busy = false
	return restored


func play_to_terminal() -> Dictionary:
	var target := _target()
	if target == null or _busy or _cursor < 0:
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	_busy = true
	var played: Dictionary = _playback.replay_full_player_to_terminal(target, _cursor)
	if played.ok:
		_cursor = int(played.context.index)
	_busy = false
	return played


func _target() -> Node2D:
	if _target_ref == null or _playback == null:
		return null
	var target: Variant = _target_ref.get_ref()
	if not _isolated(target) or _world_ref.get_ref() != target.get_parent() or target.full_player_replay_identity() != _identity:
		return null
	return target


static func _isolated(target: Variant) -> bool:
	var world := SceneScope.replay_world(target)
	return is_instance_valid(target) and target is PlayerScript and target.is_inside_tree() and not target.is_queued_for_deletion() and world != null and world.isolation_valid() and world.owns_player(target) and target.process_mode == Node.PROCESS_MODE_DISABLED and not target.is_physics_processing() and target.get("_hostile_frame_participant") == null


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
