extends Node

signal changed
signal rejected(code: StringName)

const World := preload("res://scripts/replay/run_replay_world.gd")
const Stream := preload("res://scripts/replay/run_replay_stream_store.gd")

var _store: RefCounted
var _registry: RefCounted
var _world: SubViewport
var _selected := ""
var _cursor := -1
var _count := 0
var _playing := false
var _speed := 1.0
var _remainder := 0.0
var _bookmarks: Array = []


func configure(storage: RefCounted, registry: RefCounted) -> Dictionary:
	if _store != null or not storage is Stream or registry == null or not is_inside_tree():
		return _failure(&"RUN_REPLAY_VIEW_INVALID")
	_store = storage
	_registry = registry
	return _success()


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _store == null:
		return result
	for row: Dictionary in _store.rows():
		var projected := row.duplicate(true)
		projected.frame_count = row.observation_count
		projected.first_frame = 0
		projected.last_frame = maxi(0, int(row.observation_count) - 1)
		projected.kind = "run"
		result.append(projected)
	return result


func snapshot() -> Dictionary:
	return {"selected_id": _selected, "cursor": _cursor, "frame_count": _count, "playing": _playing, "speed": _speed, "bookmarks": _bookmarks.duplicate(true)}


func current_world() -> SubViewport:
	return _world


func current_player() -> Node2D:
	return _world.get_node_or_null("Player") if is_instance_valid(_world) else null


func reload() -> Dictionary:
	return _announce(_store.reload()) if _store != null else _failure(&"RUN_REPLAY_VIEW_INVALID")


func select(id: String) -> Dictionary:
	if _store == null:
		return _failure(&"RUN_REPLAY_VIEW_INVALID")
	var row: Dictionary = {}
	for candidate: Dictionary in rows():
		if candidate.id == id:
			row = candidate
	if row.is_empty() or int(row.observation_count) == 0:
		return _failure(&"RUN_REPLAY_VIEW_INVALID")
	var read: Dictionary = _store.read(id, 0)
	var bookmarks: Dictionary = _store.transition_rows(id)
	if not read.ok or not bookmarks.ok:
		return read if not read.ok else bookmarks
	var candidate := World.new()
	add_child(candidate)
	var projected: Dictionary = candidate.present_observation(read.context.observation, _registry)
	if not projected.ok:
		candidate.queue_free()
		return projected
	close_selection()
	_world = candidate
	_selected = id
	_count = int(row.observation_count)
	_cursor = 0
	_bookmarks = bookmarks.context.rows.duplicate(true)
	changed.emit()
	return _success()


func seek(index: int) -> Dictionary:
	if not is_instance_valid(_world) or index < 0 or index >= _count:
		return _failure(&"RUN_REPLAY_VIEW_INVALID")
	var read: Dictionary = _store.read(_selected, index)
	if not read.ok:
		return read
	var projected: Dictionary = _world.present_observation(read.context.observation, _registry)
	if projected.ok:
		_cursor = index
		_remainder = 0.0
		changed.emit()
	return projected


func seek_transition(direction: int) -> Dictionary:
	if direction not in [-1, 1]:
		return _failure(&"REPLAY_CONTROL_INVALID")
	var next := _count - 1 if direction == 1 else 0
	for row: Dictionary in _bookmarks:
		if direction == 1 and int(row.sequence) > _cursor:
			next = int(row.sequence)
			break
		if direction == -1 and int(row.sequence) < _cursor:
			next = int(row.sequence)
	return seek(next)


func close_selection() -> void:
	_playing = false
	_selected = ""
	_cursor = -1
	_count = 0
	_remainder = 0.0
	_bookmarks.clear()
	if is_instance_valid(_world):
		_world.queue_free()
	_world = null


func set_speed(speed: float) -> Dictionary:
	if speed not in [0.5, 1.0, 2.0]:
		return _failure(&"REPLAY_CONTROL_INVALID")
	_speed = speed
	changed.emit()
	return _success()


func set_playing(value: bool) -> Dictionary:
	if _selected.is_empty():
		return _success() if not value else _failure(&"RUN_REPLAY_VIEW_INVALID")
	if value and _cursor == _count - 1:
		var result := seek(0)
		if not result.ok:
			return result
	_playing = value
	changed.emit()
	return _success()


func advance(delta: float) -> Dictionary:
	if not is_finite(delta) or delta < 0.0:
		return _failure(&"REPLAY_CONTROL_INVALID")
	if not _playing:
		return _success()
	var accumulated := _remainder + delta * 60.0 * _speed
	if accumulated < 1.0:
		_remainder = accumulated
		return _success()
	var result := seek(mini(_cursor + int(minf(floorf(accumulated), 2147483647.0)), _count - 1))
	if result.ok:
		_remainder = accumulated - floorf(accumulated)
	_playing = result.ok and _cursor < _count - 1
	return _announce(result)


func remove(id: String) -> Dictionary:
	var result: Dictionary = _store.remove(id)
	if result.ok and id == _selected:
		close_selection()
	return _announce(result)


func import_json(encoded: String) -> Dictionary:
	return _announce(_store.import_json(encoded))


func import_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > Stream.MAX_PACKAGE_BYTES:
		return _failure(&"RUN_REPLAY_PACKAGE_INVALID")
	return import_json(file.get_as_text())


func export_recording(id: String) -> Dictionary:
	var encoded: Dictionary = _store.export_json(id)
	if not encoded.ok:
		return encoded
	var directory: String = str(_store.storage_identity().chunk_directory).path_join("exports")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure(&"REPLAY_EXPORT_FAILED")
	var path := directory.path_join(id + ".pwrun.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure(&"REPLAY_EXPORT_FAILED")
	file.store_string(encoded.context.json)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(path) != encoded.context.json:
		return _failure(&"REPLAY_EXPORT_FAILED")
	return _success({"path": path})


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
