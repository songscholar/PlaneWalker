extends Node

signal changed
signal rejected(code: StringName)

const PlayerLibrary := preload("res://scripts/replay/player_replay_library.gd")
const RunLibrary := preload("res://scripts/replay/run_replay_library.gd")
const Stream := preload("res://scripts/replay/run_replay_stream_store.gd")

var _players: Node
var _runs: Node
var _selected: Node


func configure(root_path: String, game_version: String, binding: Dictionary, profile_id: String, save_domain: String) -> Dictionary:
	if _players != null:
		return _failure()
	var library := PlayerLibrary.new()
	add_child(library)
	var result: Dictionary = library.configure(root_path, game_version, binding, profile_id, save_domain)
	if not result.ok:
		library.queue_free()
		return result
	_players = library
	_connect(library)
	return result


func attach_stream_store(storage: RefCounted, registry: RefCounted) -> Dictionary:
	if _runs != null:
		return _failure()
	var library := RunLibrary.new()
	add_child(library)
	var result: Dictionary = library.configure(storage, registry)
	if not result.ok:
		library.queue_free()
		return result
	_runs = library
	_connect(library)
	return result


func _connect(library: Node) -> void:
	library.changed.connect(func(): changed.emit())
	library.rejected.connect(func(code: StringName): rejected.emit(code))


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = _players.rows() if _players != null else []
	if _runs != null:
		for row: Dictionary in _runs.rows():
			row.id = "run:" + str(row.id)
			result.append(row)
	return result


func snapshot() -> Dictionary:
	if _selected == null:
		return {"selected_id": "", "cursor": -1, "frame_count": 0, "playing": false, "speed": 1.0}
	var value: Dictionary = _selected.snapshot()
	if _selected == _runs and not str(value.selected_id).is_empty():
		value.selected_id = "run:" + str(value.selected_id)
	return value


func current_world() -> SubViewport:
	return _selected.current_world() if _selected != null else null


func current_player() -> Node2D:
	return _selected.current_player() if _selected != null else null


func select(id: String) -> Dictionary:
	var library: Node = _runs if id.begins_with("run:") else _players
	if library == null:
		return _failure()
	var result: Dictionary = library.select(id.trim_prefix("run:") if library == _runs else id)
	if result.ok:
		if _selected != null and _selected != library:
			_selected.close_selection()
		_selected = library
		changed.emit()
	return result


func close_selection() -> void:
	if _selected != null:
		_selected.close_selection()
	_selected = null


func reload() -> Dictionary:
	var result: Dictionary = _players.reload() if _players != null else _failure()
	if result.ok and _runs != null:
		result = _runs.reload()
	return result


func store(replay: Dictionary) -> Dictionary:
	return _players.store(replay) if _players != null else _failure()


func import_json(encoded: String) -> Dictionary:
	var value: Variant = JSON.parse_string(encoded)
	if value is Dictionary and value.get("schema_id") == "planewalker.run_replay_package":
		return _runs.import_json(encoded) if _runs != null else _failure()
	return _players.import_json(encoded) if _players != null else _failure()


func import_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > Stream.MAX_PACKAGE_BYTES:
		return _failure()
	return import_json(file.get_as_text())


func remove(id: String) -> Dictionary:
	var library: Node = _runs if id.begins_with("run:") else _players
	if library == null:
		return _failure()
	var result: Dictionary = library.remove(id.trim_prefix("run:") if library == _runs else id)
	if result.ok and library == _selected and str(library.snapshot().selected_id).is_empty():
		_selected = null
	changed.emit()
	return result


func export_recording(id: String) -> Dictionary:
	var library: Node = _runs if id.begins_with("run:") else _players
	return library.export_recording(id.trim_prefix("run:") if library == _runs else id) if library != null else _failure()


func seek(index: int) -> Dictionary:
	return _selected.seek(index) if _selected != null else _failure()


func seek_transition(direction: int) -> Dictionary:
	return _selected.seek_transition(direction) if _selected == _runs and _runs != null else _failure()


func set_speed(speed: float) -> Dictionary:
	return _selected.set_speed(speed) if _selected != null else _failure()


func set_playing(value: bool) -> Dictionary:
	return _selected.set_playing(value) if _selected != null else ({"ok": true, "code": &"OK", "context": {}} if not value else _failure())


func advance(delta: float) -> Dictionary:
	return _selected.advance(delta) if _selected != null else {"ok": true, "code": &"OK", "context": {}}


static func _failure() -> Dictionary:
	return {"ok": false, "code": &"REPLAY_VIEW_TARGET_INVALID", "context": {}}
