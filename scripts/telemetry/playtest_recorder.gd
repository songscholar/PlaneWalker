class_name PlaytestRecorder
extends RefCounted

const PlaytestSessionSchemaScript := preload("res://scripts/telemetry/playtest_session_schema.gd")

var _active := false
var _session: Dictionary = {}


func start_session(metadata: Dictionary) -> Dictionary:
	if _active:
		return _failure("session-already-active")
	var metadata_errors := _validate_start_metadata(metadata)
	if not metadata_errors.is_empty():
		return {"ok": false, "errors": metadata_errors}

	var source := str(metadata.source)
	_session = {
		"schema_version": PlaytestSessionSchemaScript.VERSION,
		"session_id": _new_session_id(),
		"evidence": {
			"source": source,
			"synthetic": source == "synthetic",
			"collection_method": str(metadata.collection_method),
		},
		"build": {
			"version": str(metadata.build_version),
			"commit": str(metadata.commit).to_lower(),
			"content_version": str(metadata.content_version),
		},
		"run": {
			"seed": int(metadata.seed),
			"input_device": str(metadata.input_device),
		},
		"timing": {
			"started_at_utc": str(metadata.started_at_utc),
			"ended_at_utc": "",
			"duration_ms": 0,
		},
		"rooms": [],
		"damage": {"dealt": 0, "taken": 0, "hits_dealt": 0, "hits_taken": 0},
		"failures": [],
		"build_choices": [],
		"terminal_result": {},
	}
	_active = true
	return {"ok": true, "session_id": _session.session_id}


func record_room(room: Dictionary) -> Dictionary:
	if not _active:
		return _failure("no-active-session")
	var entered_at_ms := maxi(0, int(room.get("entered_at_ms", 0)))
	var completed_at_ms := maxi(entered_at_ms, int(room.get("completed_at_ms", entered_at_ms)))
	_session.rooms.append({
		"room_id": str(room.get("room_id", "")),
		"room_type": str(room.get("room_type", "")),
		"room_index": int(room.get("room_index", -1)),
		"entered_at_ms": entered_at_ms,
		"completed_at_ms": completed_at_ms,
		"duration_ms": completed_at_ms - entered_at_ms,
		"result": str(room.get("result", "")),
	})
	return {"ok": true}


func record_damage(dealt: int, taken: int, hits_dealt: int = 0, hits_taken: int = 0) -> Dictionary:
	if not _active:
		return _failure("no-active-session")
	_session.damage.dealt += maxi(0, dealt)
	_session.damage.taken += maxi(0, taken)
	_session.damage.hits_dealt += maxi(0, hits_dealt)
	_session.damage.hits_taken += maxi(0, hits_taken)
	return {"ok": true}


func record_failure(code: String, phase: String, room_index: int, at_ms: int) -> Dictionary:
	if not _active:
		return _failure("no-active-session")
	_session.failures.append({
		"code": code,
		"phase": phase,
		"room_index": room_index,
		"at_ms": maxi(0, at_ms),
	})
	return {"ok": true}


func record_build_choice(choice_type: String, choice_id: String, room_index: int, at_ms: int) -> Dictionary:
	if not _active:
		return _failure("no-active-session")
	_session.build_choices.append({
		"choice_type": choice_type,
		"choice_id": choice_id,
		"room_index": room_index,
		"at_ms": maxi(0, at_ms),
	})
	return {"ok": true}


func finish_session(result: Dictionary) -> Dictionary:
	if not _active:
		return _failure("no-active-session")
	var duration_ms := maxi(0, int(result.get("duration_ms", 0)))
	_session.timing.ended_at_utc = str(result.get("ended_at_utc", ""))
	_session.timing.duration_ms = duration_ms
	_session.terminal_result = {
		"outcome": str(result.get("outcome", "")),
		"floor": int(result.get("floor", 0)),
		"room_index": int(result.get("room_index", -1)),
		"duration_ms": duration_ms,
		"cause": str(result.get("cause", "")),
	}
	var errors: Array[Dictionary] = PlaytestSessionSchemaScript.validate(_session)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "session": snapshot()}
	_active = false
	return {"ok": true, "session": snapshot()}


func snapshot() -> Dictionary:
	return _session.duplicate(true)


func is_active() -> bool:
	return _active


func _validate_start_metadata(metadata: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for field: String in ["source", "collection_method", "build_version", "commit", "content_version", "seed", "input_device", "started_at_utc"]:
		if not metadata.has(field):
			errors.append({"code": "missing-field", "path": "$.%s" % field})
	var source := str(metadata.get("source", ""))
	var method := str(metadata.get("collection_method", ""))
	if source != "human" and source != "synthetic":
		errors.append({"code": "invalid-source", "path": "$.source"})
	elif source == "human" and not method in PlaytestSessionSchemaScript.HUMAN_COLLECTION_METHODS:
		errors.append({"code": "evidence-mismatch", "path": "$.collection_method"})
	elif source == "synthetic" and not method in PlaytestSessionSchemaScript.SYNTHETIC_COLLECTION_METHODS:
		errors.append({"code": "evidence-mismatch", "path": "$.collection_method"})
	if not str(metadata.get("input_device", "")) in PlaytestSessionSchemaScript.INPUT_DEVICES:
		errors.append({"code": "invalid-input-device", "path": "$.input_device"})
	return errors


func _new_session_id() -> String:
	var crypto := Crypto.new()
	return "pws_%s" % crypto.generate_random_bytes(16).hex_encode()


func _failure(code: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code}]}
