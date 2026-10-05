extends Node

signal changed
signal rejected(code: StringName)

const Archive := preload("res://scripts/replay/player_replay_archive.gd")
const Package := preload("res://scripts/replay/player_replay_package.gd")
const World := preload("res://scripts/replay/player_replay_world.gd")
const Session := preload("res://scripts/replay/player_replay_view_session.gd")
const Atlas := preload("res://scripts/presentation/actor_atlas_projection.gd")
const Actions := preload("res://scripts/player/player_action_state.gd")

var _archive: RefCounted
var _world: SubViewport
var _session: RefCounted
var _selected := ""
var _root := ""
var _playing := false
var _speed := 1.0
var _remainder := 0.0
var _rows_revision := -1
var _rows_cache: Array[Dictionary] = []
var _atlas: Sprite2D


func configure(root_path: String, game_version: String, binding: Dictionary, profile_id: String, save_domain: String) -> Dictionary:
	if _archive != null or not is_inside_tree():
		return _failure(&"REPLAY_ARCHIVE_CONFIGURATION_INVALID")
	var archive := Archive.new()
	var result: Dictionary = archive.configure(root_path, game_version, binding, profile_id, save_domain)
	if result.ok:
		_archive = archive
		_root = root_path
	return result


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _archive == null:
		return result
	var archive: Dictionary = _archive.snapshot()
	if int(archive.revision) == _rows_revision:
		return _rows_cache.duplicate(true)
	for entry: Dictionary in archive.entries:
		var loaded: Dictionary = _archive.load_replay(entry.id)
		if loaded.ok:
			var summary: Dictionary = loaded.context.summary
			result.append({"id": entry.id, "character_id": summary.identity.character_id, "weapon_id": summary.identity.weapon_id, "seed": summary.seed, "frame_count": summary.frame_count, "first_frame": summary.first_frame, "last_frame": summary.last_frame})
	_rows_revision = int(archive.revision)
	_rows_cache = result.duplicate(true)
	return result


func snapshot() -> Dictionary:
	var session: Dictionary = _session.snapshot() if _session != null else {"cursor": -1, "frame_count": 0}
	return {"selected_id": _selected, "cursor": session.cursor, "frame_count": session.frame_count, "playing": _playing, "speed": _speed}


func current_player() -> Node2D:
	return _world.get_node_or_null("Player") if is_instance_valid(_world) else null


func current_world() -> SubViewport:
	return _world


func store(replay: Dictionary) -> Dictionary:
	return _announce(_archive.store(replay)) if _archive != null else _failure(&"REPLAY_ARCHIVE_NOT_READY")


func reload() -> Dictionary:
	return _announce(_archive.reload()) if _archive != null else _failure(&"REPLAY_ARCHIVE_NOT_READY")


func import_json(encoded: String) -> Dictionary:
	return _announce(_archive.import_json(encoded)) if _archive != null else _failure(&"REPLAY_ARCHIVE_NOT_READY")


func import_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0 or file.get_length() > Package.MAX_PACKAGE_BYTES:
		return _failure(&"REPLAY_PACKAGE_SIZE_INVALID")
	return import_json(file.get_as_text())


func export_recording(id: String) -> Dictionary:
	if _archive == null:
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	var encoded: Dictionary = _archive.export_json(id)
	if not encoded.ok:
		return encoded
	var directory := _root.path_join("exports")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure(&"REPLAY_EXPORT_FAILED")
	var path := directory.path_join(id + ".pwreplay.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure(&"REPLAY_EXPORT_FAILED")
	file.store_string(encoded.context.json)
	file.flush()
	if file.get_error() != OK:
		return _failure(&"REPLAY_EXPORT_FAILED")
	file.close()
	if FileAccess.get_file_as_string(path) != encoded.context.json:
		return _failure(&"REPLAY_EXPORT_FAILED")
	return _success({"path": path})


func remove(id: String) -> Dictionary:
	if _archive == null:
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	var result: Dictionary = _archive.remove(id)
	if result.ok and _selected == id:
		close_selection()
	return _announce(result)


func select(id: String) -> Dictionary:
	if _archive == null:
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	var loaded: Dictionary = _archive.load_replay(id)
	if not loaded.ok:
		return loaded
	var candidate := World.new()
	candidate.size = Vector2i(320, 180)
	add_child(candidate)
	var player := candidate.create_player()
	if player == null or not player.configure_replay_view_identity(loaded.context.replay.identity):
		candidate.queue_free()
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	var session := Session.new()
	var configured: Dictionary = session.configure(loaded.context.replay, player)
	if configured.ok:
		configured = session.seek(0)
	if not configured.ok:
		candidate.queue_free()
		return configured
	close_selection()
	_world = candidate
	_session = session
	_selected = id
	_atlas = Atlas.new()
	player.add_child(_atlas)
	if not _atlas.configure(str(loaded.context.replay.identity.character_id)):
		close_selection()
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	player.get_node("Visual").visible = false
	_world.transparent_bg = true
	_frame_camera()
	changed.emit()
	return _success()


func close_selection() -> void:
	_playing = false
	_remainder = 0.0
	_selected = ""
	_session = null
	if is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_atlas = null


func seek(index: int) -> Dictionary:
	if _session == null or index < 0 or index >= int(_session.snapshot().frame_count):
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	var result: Dictionary = _session.seek(index)
	if result.ok:
		_remainder = 0.0
		_frame_camera()
		changed.emit()
	return result


func set_speed(speed: float) -> Dictionary:
	if speed not in [0.5, 1.0, 2.0]:
		return _failure(&"REPLAY_CONTROL_INVALID")
	_speed = speed
	changed.emit()
	return _success()


func set_playing(value: bool) -> Dictionary:
	if _session == null:
		return _failure(&"REPLAY_VIEW_TARGET_INVALID")
	if value and snapshot().cursor == snapshot().frame_count - 1:
		var rewound := seek(0)
		if not rewound.ok:
			return rewound
	_playing = value
	changed.emit()
	return _success()


func advance(delta: float) -> Dictionary:
	if not is_finite(delta) or delta < 0.0:
		return _failure(&"REPLAY_CONTROL_INVALID")
	if not _playing:
		return _success()
	var accumulated := _remainder + delta * 60.0 * _speed
	var steps := int(minf(floorf(accumulated), 2147483647.0))
	if steps == 0:
		_remainder = accumulated
		return _success()
	var state := snapshot()
	var next := mini(int(state.cursor) + steps, int(state.frame_count) - 1)
	var result := seek(next)
	if not result.ok:
		_playing = false
		rejected.emit(result.code)
		return result
	_remainder = accumulated - floorf(accumulated)
	_playing = next < int(state.frame_count) - 1
	changed.emit()
	return result


func _frame_camera() -> void:
	var player := current_player()
	if player != null:
		_world.canvas_transform = Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(_world.size) / 2.0 - player.global_position * 2.0)
		var state := &"idle"
		match player.action_state.current_state:
			Actions.State.ATTACK_WINDUP, Actions.State.ATTACK_ACTIVE, Actions.State.ATTACK_RECOVERY:
				state = &"attack"
			Actions.State.DASH:
				state = &"move"
			Actions.State.TIME_CAST:
				state = &"cast"
			Actions.State.HITSTUN:
				state = &"hurt"
			Actions.State.DEAD:
				state = &"death"
			_:
				if player.velocity.length_squared() > 0.01:
					state = &"move"
		if is_instance_valid(_atlas):
			_atlas.present(state, player.get("_last_move_direction"), float(player.get("_runtime_frame")) / 60.0, false, bool(GameState.get_setting("reduced_motion", false)))


func _announce(result: Dictionary) -> Dictionary:
	if result.ok:
		changed.emit()
	else:
		rejected.emit(result.code)
	return result


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
