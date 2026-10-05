extends Node

signal changed
signal rejected(code: StringName)

const Host := preload("res://scripts/application/run_runtime_host.gd")
const StreamStore := preload("res://scripts/replay/run_replay_stream_store.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const MAX_COMBAT_FRAMES := 162000

var _host: Node
var _player: Node2D
var _store: RefCounted
var _root := ""
var _id := ""
var _run_id := ""
var _active := false
var _complete_eligible := true
var _sequence := 0
var _combat_frames := 0
var _committed_count := 0
var _pending_frame := -1
var _last_stamp := ""
var _buffer: Array[Dictionary] = []
var _latest: Dictionary = {}
var _failure: StringName = &""
var _write_thread: Thread
var _write_count := 0
var _failed_finish_pending := false


func configure(host: Node, storage: RefCounted, root_path: String) -> Dictionary:
	if _host != null or not host is Host or not storage is StreamStore or storage.snapshot().is_empty() or not is_inside_tree():
		return _failure_result(&"RUN_REPLAY_RECORDER_CONFIGURATION_INVALID")
	_host = host
	_store = storage
	_root = root_path
	process_mode = Node.PROCESS_MODE_ALWAYS
	return _success()


func store() -> RefCounted:
	return _store


func storage_root() -> String:
	return _root


func snapshot() -> Dictionary:
	return {"id": _id, "run_id": _run_id, "active": _active, "observation_count": _sequence, "committed_count": _committed_count, "buffered_count": _buffer.size(), "combat_frames": _combat_frames, "complete_eligible": _complete_eligible, "failure": _failure, "pending_write": _write_thread != null, "pending_write_count": _write_count}


func latest_observation() -> Dictionary:
	return _latest.duplicate(true)


func start(restored: bool = false) -> Dictionary:
	if _host == null or _active or _write_thread != null or _failed_finish_pending:
		return _failure_result(&"RUN_REPLAY_RECORDER_NOT_READY")
	var parts: Dictionary = _host.native_checkpoint_participants()
	var run: Dictionary = _host.runtime_snapshot()
	var player: Variant = parts.get("player")
	if not player is Node2D or not is_instance_valid(player) or str(run.get("config", {}).get("milestone", "")) not in ["LAUNCH", "EXPANSION"] or bool(parts.get("busy", true)):
		return _failure_result(&"RUN_REPLAY_RECORDER_NOT_READY")
	var begun: Dictionary = _store.begin(player.full_player_replay_identity(), int(run.run_seed))
	if not begun.ok:
		return begun
	_player = player
	_id = begun.context.id
	_run_id = str(run.run_id)
	_active = true
	_complete_eligible = not restored
	_sequence = 0
	_combat_frames = 0
	_committed_count = 0
	_pending_frame = -1
	_last_stamp = ""
	_buffer.clear()
	_latest.clear()
	_failure = &""
	# Connect after Launch's native driver so its authoritative publication finishes first.
	if _player.authoritative_frame_committed.is_connected(_on_frame):
		_player.authoritative_frame_committed.disconnect(_on_frame)
	_player.authoritative_frame_committed.connect(_on_frame)
	var captured := _observe("resume" if restored else "start")
	if not captured.ok:
		return _fail(captured.code)
	return _success({"id": _id})


func _on_frame(frame: int) -> void:
	if not _active:
		return
	if _pending_frame >= 0 or _combat_frames >= MAX_COMBAT_FRAMES:
		_fail(&"RUN_REPLAY_RECORDER_CAPACITY" if _combat_frames >= MAX_COMBAT_FRAMES else &"RUN_REPLAY_RECORDER_BOUNDARY_LOST")
		return
	var result := _observe("frame", frame)
	if not result.ok:
		if result.code == &"RUN_REPLAY_RECORDER_BOUNDARY_PENDING":
			_pending_frame = frame
			_retry_frame.call_deferred(frame)
		else:
			_fail(result.code)


func _retry_frame(frame: int) -> void:
	if not _active or _pending_frame != frame:
		return
	_pending_frame = -1
	if not is_instance_valid(_player) or int(_player.priority_arbitration_snapshot().frame) != frame:
		_fail(&"RUN_REPLAY_RECORDER_BOUNDARY_LOST")
		return
	var result := _observe("frame", frame)
	if not result.ok:
		_fail(result.code)


func observe_transition() -> Dictionary:
	if not _active or _pending_frame >= 0:
		return _failure_result(&"RUN_REPLAY_RECORDER_NOT_READY")
	var run: Dictionary = _host.runtime_snapshot()
	if str(run.get("run_id", "")) != _run_id:
		return finish("INTERRUPTED")
	var terminal := Phase.is_terminal(int(run.get("phase", -1)))
	if _stamp(run) == _last_stamp and not terminal:
		return _success()
	var result := _observe("terminal" if terminal else "transition")
	if not result.ok:
		return result if result.code == &"RUN_REPLAY_RECORDER_BOUNDARY_PENDING" else _fail(result.code)
	return finish("COMPLETE" if _complete_eligible else "INTERRUPTED") if terminal else result


func _process(_delta: float) -> void:
	_collect_write(false)
	if _failed_finish_pending and _write_thread == null:
		_store.finish(_id, "FAILED")
		_failed_finish_pending = false
	if _active:
		observe_transition()


func _observe(kind: String, frame: int = -1) -> Dictionary:
	var collected := _collect_write(false)
	if not collected.ok:
		return collected
	if _write_thread != null and _buffer.size() >= 120:
		return _fail(&"RUN_REPLAY_RECORDER_CAPACITY")
	if not _active or not is_instance_valid(_host) or not is_instance_valid(_player):
		return _failure_result(&"RUN_REPLAY_RECORDER_NOT_READY")
	var parts: Dictionary = _host.native_checkpoint_participants()
	if bool(parts.get("busy", true)):
		return _failure_result(&"RUN_REPLAY_RECORDER_BOUNDARY_PENDING")
	var run: Dictionary = _host.runtime_snapshot()
	var player: Dictionary = _player.native_replay_recording_snapshot()
	if str(run.get("run_id", "")) != _run_id or player.is_empty() or player.get("identity", {}).get("run_id") != _run_id or frame >= 0 and player.get("frame") != frame or not _player.validate_native_replay_recording_snapshot(player, player.get("identity", {})).ok:
		return _failure_result(&"RUN_REPLAY_RECORDER_STATE_INVALID")
	var runner: Node = parts.controller.encounter_runner()
	var native: Dictionary = runner.native_cold_snapshot() if runner.is_active() else {}
	if runner.is_active() and native.is_empty():
		return _failure_result(&"RUN_REPLAY_RECORDER_BOUNDARY_PENDING")
	var scene: Dictionary = {}
	if is_instance_valid(parts.get("scene_host")) and parts.scene_host.active_room() != null:
		scene = parts.scene_host.active_room().binding_snapshot()
	var cosmetic_id := ""
	if parts.get("profile") != null:
		cosmetic_id = parts.profile.equipped_cosmetic(str(player.identity.character_id))
	var observation := {"sequence": _sequence, "kind": kind, "player": player, "run": run, "native": native, "room": parts.runtime.snapshot(), "scene": scene, "publication": parts.publication, "cosmetic_id": cosmetic_id, "intents": _player.authoritative_frame_intents(int(player.frame)) if kind == "frame" else {}}
	_buffer.append(observation)
	_latest = observation
	_sequence += 1
	if kind == "frame":
		_combat_frames += 1
	_last_stamp = _stamp(run)
	if _sequence > StreamStore.MAX_OBSERVATIONS or _buffer.size() > 120:
		return _fail(&"RUN_REPLAY_RECORDER_CAPACITY")
	if _buffer.size() == 120:
		return _queue_write()
	changed.emit()
	return _success()


func flush() -> Dictionary:
	if not _active:
		return _failure_result(&"RUN_REPLAY_RECORDER_NOT_READY")
	var collected := _collect_write(true)
	if not collected.ok:
		return collected
	if _buffer.is_empty():
		return _success()
	var result: Dictionary = _store.append(_id, _buffer)
	if not result.ok:
		return _fail(result.code)
	_committed_count += _buffer.size()
	_buffer.clear()
	changed.emit()
	return _success()


func _queue_write() -> Dictionary:
	if _write_thread != null:
		return _success()
	var batch := _buffer
	_buffer = []
	_write_count = batch.size()
	_write_thread = Thread.new()
	# The immutable batch and store have one writer until this task is joined.
	if _write_thread.start(_store.append.bind(_id, batch)) != OK:
		_write_thread = null
		_write_count = 0
		return _fail(&"RUN_REPLAY_RECORDER_IO_FAILED")
	changed.emit()
	return _success()


func _collect_write(wait: bool) -> Dictionary:
	if _write_thread == null or not wait and _write_thread.is_alive():
		return _success()
	var result: Variant = _write_thread.wait_to_finish()
	_write_thread = null
	var count := _write_count
	_write_count = 0
	if not result is Dictionary or not result.get("ok", false):
		return _fail(result.get("code", &"RUN_REPLAY_RECORDER_IO_FAILED") if result is Dictionary else &"RUN_REPLAY_RECORDER_IO_FAILED")
	_committed_count += count
	changed.emit()
	return _success()


func finish(status: String = "INTERRUPTED") -> Dictionary:
	if not _active or status not in ["COMPLETE", "INTERRUPTED"] or status == "COMPLETE" and (not _complete_eligible or not Phase.is_terminal(int(_latest.get("run", {}).get("phase", -1)))):
		return _failure_result(&"RUN_REPLAY_RECORDER_STATE_INVALID")
	var flushed := flush()
	if not flushed.ok:
		return flushed
	var result: Dictionary = _store.finish(_id, status)
	if not result.ok:
		return _fail(result.code)
	_active = false
	_disconnect()
	changed.emit()
	return _success()


func _fail(code: StringName) -> Dictionary:
	if not _failure.is_empty():
		return _failure_result(_failure)
	_failure = code
	_active = false
	_complete_eligible = false
	_disconnect()
	_failed_finish_pending = _write_thread != null
	if not _failed_finish_pending:
		_store.finish(_id, "FAILED")
	rejected.emit(code)
	changed.emit()
	return _failure_result(code)


func _disconnect() -> void:
	if is_instance_valid(_player) and _player.authoritative_frame_committed.is_connected(_on_frame):
		_player.authoritative_frame_committed.disconnect(_on_frame)


func _exit_tree() -> void:
	if _active:
		finish("INTERRUPTED")
	_collect_write(true)
	if _failed_finish_pending:
		_store.finish(_id, "FAILED")
		_failed_finish_pending = false
	_disconnect()


static func _stamp(run: Dictionary) -> String:
	return "%s:%s:%s:%s:%s" % [run.get("run_id", ""), run.get("revision", -1), run.get("phase", -1), run.get("floor_plan", {}).get("floor_id", ""), run.get("floor_plan", {}).get("current_node_id", "")]


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


static func _failure_result(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
