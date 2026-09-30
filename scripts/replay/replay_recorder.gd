class_name ReplayRecorder
extends RefCounted

const SCHEMA_ID := "planewalker.weapon_runtime_replay"
const SCHEMA_VERSION := 6
const SNAPSHOT_SCHEMA_VERSION := 3
const EVENT_SCHEMA_VERSION := 3
const EVENT_PREFIX_SCHEMA_ID := "planewalker.weapon_runtime_replay.event_prefix"
const EVENT_PREFIX_SCHEMA_VERSION := 1
const SHA256_LENGTH := 64
const JSON_CODEC_ID := "planewalker.godot_variant.base64"
const JSON_CODEC_VERSION := 1
const MAX_JSON_PAYLOAD_BYTES := 16 * 1024 * 1024
const HP_ABSOLUTE_EPSILON := 0.0001

const REPLAY_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"seed",
	"weapon_id",
	"profile_id",
	"profile_version",
	"profile_digest",
	"frames",
	"events",
	"frame_count",
	"event_count",
	"first_frame",
	"last_frame",
	"terminal_digest",
]
const FRAME_FIELDS: Array[String] = [
	"frame",
	"token",
	"generation",
	"snapshot",
	"digest",
]
const EVENT_FIELDS: Array[String] = [
	"schema_version",
	"frame",
	"sequence",
	"capture_sequence",
	"event_type",
	"payload",
	"digest",
]
const NORMALIZED_EVENT_FIELDS: Array[String] = [
	"schema_version",
	"frame",
	"sequence",
	"capture_sequence",
	"event_type",
	"payload",
]
const INTENT_EVENT_FIELDS: Array[String] = [
	"semantic_action",
	"edge",
	"held_frames",
	"context",
]
const EXTERNAL_FACT_FIELDS: Array[String] = [
	"fact_type",
	"fact_id",
	"weapon_id",
	"action_token",
	"action_generation",
	"data",
]
const VALID_EVENT_TYPES: Array[String] = ["weapon_intent", "external_fact"]
const VALID_EVENT_ACTIONS: Array[String] = [
	"weapon_primary",
	"weapon_secondary",
	"weapon_utility",
	"weapon_skill",
	"weapon_ultimate",
]
const VALID_EVENT_EDGES: Array[String] = ["pressed", "held", "released"]
const VALID_EXTERNAL_FACT_TYPES: Array[String] = [
	"combat_damage",
	"weapon_hit_claim",
	"weapon_payload_result",
	"weapon_resource_reward",
	"time_interaction_claim",
	"time_stop_extension",
]
const TIME_REPLAY_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"time_energy_state",
	"stop_active",
	"stop_source_sequence",
	"stop_source_id",
	"stop_remaining",
	"stop_extension_frames",
	"stop_extension_tokens",
	"rewind_window_remaining",
	"rewind_window_generation",
	"rewind_window_claimed",
]
const TIME_ENERGY_STATE_FIELDS: Array[String] = [
	"ok",
	"code",
	"resource_id",
	"current",
	"minimum",
	"maximum",
	"revision",
	"context",
]

var _recording := false
var _identity: Dictionary = {}
var _seed := 0
var _frames: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _last_frame := -1
var _last_event_frame := -1
var _last_event_sequence := 0
var _capture_sequences: Dictionary = {}
var _last_event_prefix_count := 0
var _last_positive_token := 0
var _last_token := 0
var _last_generation := 0
var _finished_replay: Dictionary = {}


func start_recording(profile: Dictionary, seed: int = 0) -> Dictionary:
	reset()
	var identity := profile_identity(profile)
	if identity.is_empty():
		return _failure(&"INVALID_PROFILE_IDENTITY", {
			"profile_id": profile.get("id"),
			"weapon_id": profile.get("weapon_id"),
			"profile_version": profile.get("profile_version"),
			"profile_version_type": typeof(profile.get("profile_version")),
			"digest_length": profile_digest(profile).length(),
		})
	if seed < 0:
		return _failure(&"INVALID_SEED")
	_identity = identity
	_seed = seed
	_recording = true
	var result := _success({"identity": recording_identity()})
	result["identity"] = recording_identity()
	return result


func begin(profile: Dictionary, seed: int = 0) -> Dictionary:
	return start_recording(profile, seed)


func record_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _recording:
		return _failure(&"NOT_RECORDING")
	var validation := validate_snapshot(snapshot, _identity)
	if not bool(validation.get("ok", false)):
		return validation
	var frame := int(snapshot.get("frame", -1))
	var token := int(snapshot.get("token", -1))
	var generation := int(snapshot.get("generation", -1))
	var event_prefix_count := int(snapshot.get("event_prefix_count", -1))
	if frame <= _last_frame:
		return _failure(&"FRAME_NOT_MONOTONIC", {"frame": frame, "last_frame": _last_frame})
	if generation < _last_generation:
		return _failure(
			&"GENERATION_NOT_MONOTONIC",
			{"generation": generation, "last_generation": _last_generation}
		)
	if token > 0 and token < _last_positive_token:
		return _failure(
			&"TOKEN_NOT_MONOTONIC",
			{"token": token, "last_positive_token": _last_positive_token}
		)
	if token > 0 and _last_token == 0 and _last_positive_token > 0 and token <= _last_positive_token:
		return _failure(
			&"TOKEN_NOT_MONOTONIC",
			{"token": token, "last_positive_token": _last_positive_token, "reason": "completed_token_reused"}
		)
	if event_prefix_count < _last_event_prefix_count:
		return _failure(&"REPLAY_EVENT_PREFIX_REGRESSION", {
			"event_prefix_count": event_prefix_count,
			"last_event_prefix_count": _last_event_prefix_count,
		})

	var entry := {
		"frame": frame,
		"token": token,
		"generation": generation,
		"snapshot": snapshot.duplicate(true),
	}
	entry["digest"] = frame_digest(entry)
	if str(entry["digest"]).length() != SHA256_LENGTH:
		return _failure(&"FRAME_DIGEST_FAILED")
	_frames.append(entry.duplicate(true))
	_last_frame = frame
	_last_generation = generation
	_last_token = token
	_last_event_prefix_count = event_prefix_count
	if token > 0:
		_last_positive_token = token
	return _success({"frame": frame, "digest": entry["digest"]})


func record_frame(snapshot: Dictionary) -> Dictionary:
	return record_snapshot(snapshot)


func record_event(event: Dictionary) -> Dictionary:
	if not _recording:
		return _failure(&"NOT_RECORDING")
	var normalized := validate_event(event, _identity)
	if normalized.is_empty():
		return _failure(&"INVALID_REPLAY_EVENT")
	var frame := int(normalized["frame"])
	var sequence := int(normalized["sequence"])
	var capture_sequence := int(normalized["capture_sequence"])
	if frame < _last_event_frame:
		return _failure(&"EVENT_FRAME_NOT_MONOTONIC", {"frame": frame, "last_frame": _last_event_frame})
	if sequence != _last_event_sequence + 1:
		return _failure(&"EVENT_SEQUENCE_NOT_MONOTONIC", {
			"sequence": sequence,
			"expected": _last_event_sequence + 1,
		})
	if _capture_sequences.has(capture_sequence):
		return _failure(&"EVENT_CAPTURE_SEQUENCE_DUPLICATE", {"capture_sequence": capture_sequence})
	var entry := normalized.duplicate(true)
	entry["digest"] = event_digest(entry)
	if not _is_sha256(entry["digest"]):
		return _failure(&"EVENT_DIGEST_FAILED")
	_events.append(entry)
	_last_event_frame = frame
	_last_event_sequence = sequence
	_capture_sequences[capture_sequence] = true
	return _success({"frame": frame, "digest": entry["digest"]})


func finish_recording() -> Dictionary:
	if not _recording:
		if not _finished_replay.is_empty():
			var cached_result := _success({"replay": _finished_replay.duplicate(true)})
			cached_result["replay"] = _finished_replay.duplicate(true)
			return cached_result
		return _failure(&"NOT_RECORDING")
	if _frames.is_empty():
		return _failure(&"EMPTY_REPLAY")
	var stream_validation := _validate_recorded_stream()
	if not bool(stream_validation.get("ok", false)):
		return stream_validation

	var replay := {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"seed": _seed,
		"weapon_id": str(_identity["weapon_id"]),
		"profile_id": str(_identity["profile_id"]),
		"profile_version": int(_identity["profile_version"]),
		"profile_digest": str(_identity["profile_digest"]),
		"frames": _frames.duplicate(true),
		"events": _events.duplicate(true),
		"frame_count": _frames.size(),
		"event_count": _events.size(),
		"first_frame": int(_frames[0]["frame"]),
		"last_frame": int(_frames[-1]["frame"]),
	}
	replay["terminal_digest"] = terminal_digest(replay)
	if str(replay["terminal_digest"]).length() != SHA256_LENGTH:
		return _failure(&"TERMINAL_DIGEST_FAILED")
	_finished_replay = replay.duplicate(true)
	_recording = false
	var result := _success({"replay": replay.duplicate(true)})
	result["replay"] = replay.duplicate(true)
	return result


func _validate_recorded_stream() -> Dictionary:
	var first_frame := int(_frames[0].get("frame", -1))
	var last_frame := int(_frames[-1].get("frame", -1))
	for index: int in range(_frames.size()):
		var frame_entry := _frames[index]
		var snapshot_value: Variant = frame_entry.get("snapshot")
		if not snapshot_value is Dictionary:
			return _failure(&"INVALID_REPLAY_SNAPSHOT", {"index": index})
		var snapshot := snapshot_value as Dictionary
		var snapshot_validation := validate_snapshot(snapshot, _identity)
		if not bool(snapshot_validation.get("ok", false)):
			return _failure(
				&"INVALID_REPLAY_SNAPSHOT",
				{"index": index, "reason": snapshot_validation.get("code")}
			)
		for field: String in ["frame", "token", "generation"]:
			if frame_entry.get(field) != snapshot.get(field):
				return _failure(
					&"REPLAY_FRAME_SNAPSHOT_MISMATCH",
					{"index": index, "field": field}
				)
		if (
			not _is_sha256(frame_entry.get("digest"))
			or str(frame_entry["digest"]) != frame_digest(frame_entry)
		):
			return _failure(&"FRAME_DIGEST_MISMATCH", {"index": index})

	for index: int in range(_events.size()):
		var event := _events[index]
		var normalized := event.duplicate(true)
		normalized.erase("digest")
		if validate_event(normalized, _identity).is_empty():
			return _failure(&"INVALID_REPLAY_EVENT", {"index": index})
		var event_frame := int(event.get("frame", -1))
		if event_frame < first_frame or event_frame > last_frame:
			return _failure(
				&"REPLAY_EVENT_FRAME_RANGE_MISMATCH",
				{"index": index, "frame": event_frame, "first_frame": first_frame, "last_frame": last_frame}
			)
		if not _is_sha256(event.get("digest")) or str(event["digest"]) != event_digest(event):
			return _failure(&"EVENT_DIGEST_MISMATCH", {"index": index})
	for expected_capture_sequence: int in range(1, _events.size() + 1):
		if not _capture_sequences.has(expected_capture_sequence):
			return _failure(
				&"EVENT_CAPTURE_SEQUENCE_GAP",
				{"capture_sequence": expected_capture_sequence}
			)
	for index: int in range(_events.size()):
		if not event_state_after_prefix_matches(_events[index], _events):
			return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"event_index": index})

	var previous_prefix_count := 0
	for index: int in range(_frames.size()):
		var frame_entry := _frames[index]
		var snapshot := frame_entry.get("snapshot", {}) as Dictionary
		var prefix_count := int(snapshot.get("event_prefix_count", -1))
		if prefix_count < previous_prefix_count:
			return _failure(&"REPLAY_EVENT_PREFIX_REGRESSION", {"index": index})
		if not event_prefix_matches(snapshot, _events):
			return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": index})
		var prefix_capture_sequences: Dictionary = {}
		var ordered := _events_in_capture_order(_events)
		for prefix_index: int in range(prefix_count):
			var prefix_event := ordered[prefix_index]
			if int(prefix_event.get("frame", -1)) > int(frame_entry.get("frame", -1)):
				return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": index})
			prefix_capture_sequences[int(prefix_event.get("capture_sequence", 0))] = true
		for event: Dictionary in _events:
			if (
				int(event.get("frame", -1)) < int(frame_entry.get("frame", -1))
				and not prefix_capture_sequences.has(int(event.get("capture_sequence", 0)))
			):
				return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": index})
		previous_prefix_count = prefix_count
	if int((_frames[-1].get("snapshot", {}) as Dictionary).get("event_prefix_count", -1)) != _events.size():
		return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": _frames.size() - 1})
	return _success()


func finish() -> Dictionary:
	return finish_recording()


func reset() -> void:
	_recording = false
	_identity.clear()
	_seed = 0
	_frames.clear()
	_events.clear()
	_last_frame = -1
	_last_event_frame = -1
	_last_event_sequence = 0
	_capture_sequences.clear()
	_last_event_prefix_count = 0
	_last_positive_token = 0
	_last_token = 0
	_last_generation = 0
	_finished_replay.clear()


func is_recording() -> bool:
	return _recording


func recorded_frame_count() -> int:
	return _frames.size()


func recording_identity() -> Dictionary:
	return _identity.duplicate(true)


func summary() -> Dictionary:
	if _finished_replay.is_empty():
		return {}
	return replay_summary(_finished_replay)


static func profile_identity(profile: Dictionary) -> Dictionary:
	if not _is_non_empty_string(profile.get("id")):
		return {}
	if not _is_non_empty_string(profile.get("weapon_id")):
		return {}
	if not _is_positive_integral_number(profile.get("profile_version")):
		return {}
	var digest := profile_digest(profile)
	if digest.length() != SHA256_LENGTH:
		return {}
	return {
		"weapon_id": str(profile["weapon_id"]),
		"profile_id": str(profile["id"]),
		"profile_version": int(profile["profile_version"]),
		"profile_digest": digest,
	}


static func profile_digest(profile: Dictionary) -> String:
	if profile.is_empty() or not replay_value_is_safe(profile):
		return ""
	var digest_source := profile.duplicate(true)
	digest_source.erase("profile_digest")
	return value_digest(digest_source)


static func frame_digest(frame_entry: Dictionary) -> String:
	for field: String in ["frame", "token", "generation", "snapshot"]:
		if not frame_entry.has(field):
			return ""
	return value_digest({
		"frame": frame_entry["frame"],
		"token": frame_entry["token"],
		"generation": frame_entry["generation"],
		"snapshot": frame_entry["snapshot"],
	})


static func event_digest(event_entry: Dictionary) -> String:
	for field: String in NORMALIZED_EVENT_FIELDS:
		if not event_entry.has(field):
			return ""
	return value_digest({
		"schema_version": event_entry["schema_version"],
		"frame": event_entry["frame"],
		"sequence": event_entry["sequence"],
		"capture_sequence": event_entry["capture_sequence"],
		"event_type": event_entry["event_type"],
		"payload": event_entry["payload"],
	})


static func capture_event_digest(event_entry: Dictionary) -> String:
	for field: String in ["schema_version", "frame", "capture_sequence", "event_type", "payload"]:
		if not event_entry.has(field):
			return ""
	if (
		typeof(event_entry.get("schema_version")) != TYPE_INT
		or int(event_entry["schema_version"]) != EVENT_SCHEMA_VERSION
		or not _is_non_negative_integer(event_entry.get("frame"))
		or not _is_positive_integer(event_entry.get("capture_sequence"))
		or typeof(event_entry.get("event_type")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(event_entry["event_type"]) not in VALID_EVENT_TYPES
		or not event_entry.get("payload") is Dictionary
		or not replay_value_is_safe(event_entry.get("payload"))
	):
		return ""
	return value_digest({
		"schema_version": event_entry["schema_version"],
		"frame": event_entry["frame"],
		"capture_sequence": event_entry["capture_sequence"],
		"event_type": event_entry["event_type"],
		"payload": event_entry["payload"],
	})


static func event_prefix_root(events: Array, count: int = -1) -> String:
	var prefix_count := events.size() if count < 0 else count
	if prefix_count < 0 or prefix_count > events.size():
		return ""
	var ordered := _events_in_capture_order(events)
	var capture_event_digests: Array[String] = []
	for index: int in range(prefix_count):
		var event := ordered[index]
		if int(event.get("capture_sequence", 0)) != index + 1:
			return ""
		var digest := capture_event_digest(event)
		if not _is_sha256(digest):
			return ""
		capture_event_digests.append(digest)
	return value_digest({
		"schema_id": EVENT_PREFIX_SCHEMA_ID,
		"schema_version": EVENT_PREFIX_SCHEMA_VERSION,
		"event_count": prefix_count,
		"capture_event_digests": capture_event_digests,
	})


static func event_prefix_matches(snapshot: Dictionary, events: Array) -> bool:
	if (
		typeof(snapshot.get("event_prefix_count")) != TYPE_INT
		or int(snapshot["event_prefix_count"]) < 0
		or not _is_sha256(snapshot.get("event_prefix_root"))
	):
		return false
	var count := int(snapshot["event_prefix_count"])
	return count <= events.size() and str(snapshot["event_prefix_root"]) == event_prefix_root(events, count)


static func event_state_after_prefix_matches(event: Dictionary, events: Array) -> bool:
	if str(event.get("event_type", "")) != "external_fact":
		return true
	var payload_value: Variant = event.get("payload")
	if not payload_value is Dictionary:
		return false
	var fact_type := str((payload_value as Dictionary).get("fact_type", ""))
	if fact_type in ["time_interaction_claim", "time_stop_extension"]:
		return true
	var data_value: Variant = (payload_value as Dictionary).get("data")
	if not data_value is Dictionary:
		return false
	var state_after_value: Variant = (data_value as Dictionary).get("state_after")
	if not state_after_value is Dictionary:
		return false
	var state_after := state_after_value as Dictionary
	var expected_count := int(event.get("capture_sequence", 0)) - 1
	return (
		expected_count >= 0
		and int(state_after.get("event_prefix_count", -1)) == expected_count
		and event_prefix_matches(state_after, events)
	)


static func _events_in_capture_order(events: Array) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			return []
		ordered.append((event_value as Dictionary).duplicate(true))
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("capture_sequence", 0)) < int(right.get("capture_sequence", 0))
	)
	return ordered


static func terminal_digest(replay: Dictionary) -> String:
	var frame_digests: Array[String] = []
	var frames_value: Variant = replay.get("frames")
	if not frames_value is Array:
		return ""
	for frame_value: Variant in frames_value:
		if not frame_value is Dictionary:
			return ""
		var digest_value: Variant = (frame_value as Dictionary).get("digest")
		if not _is_sha256(digest_value):
			return ""
		frame_digests.append(str(digest_value))
	var event_digests: Array[String] = []
	var events_value: Variant = replay.get("events")
	if not events_value is Array:
		return ""
	for event_value: Variant in events_value:
		if not event_value is Dictionary:
			return ""
		var digest_value: Variant = (event_value as Dictionary).get("digest")
		if not _is_sha256(digest_value):
			return ""
		event_digests.append(str(digest_value))
	return value_digest({
		"schema_id": replay.get("schema_id"),
		"schema_version": replay.get("schema_version"),
		"seed": replay.get("seed"),
		"weapon_id": replay.get("weapon_id"),
		"profile_id": replay.get("profile_id"),
		"profile_version": replay.get("profile_version"),
		"profile_digest": replay.get("profile_digest"),
		"frame_count": replay.get("frame_count"),
		"event_count": replay.get("event_count"),
		"first_frame": replay.get("first_frame"),
		"last_frame": replay.get("last_frame"),
		"frame_digests": frame_digests,
		"event_digests": event_digests,
	})


static func replay_summary(replay: Dictionary) -> Dictionary:
	if replay.is_empty():
		return {}
	return {
		"schema_id": replay.get("schema_id"),
		"schema_version": replay.get("schema_version"),
		"seed": replay.get("seed"),
		"weapon_id": replay.get("weapon_id"),
		"profile_id": replay.get("profile_id"),
		"profile_version": replay.get("profile_version"),
		"profile_digest": replay.get("profile_digest"),
		"frame_count": replay.get("frame_count"),
		"event_count": replay.get("event_count"),
		"first_frame": replay.get("first_frame"),
		"last_frame": replay.get("last_frame"),
		"terminal_digest": replay.get("terminal_digest"),
	}


static func encode_replay_json(replay: Dictionary) -> Dictionary:
	if replay.is_empty() or not replay_value_is_safe(replay):
		return _failure(&"UNSAFE_REPLAY")
	var payload_bytes := var_to_bytes(replay)
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_JSON_PAYLOAD_BYTES:
		return _failure(&"REPLAY_CODEC_SIZE_INVALID", {"bytes": payload_bytes.size()})
	var payload := Marshalls.raw_to_base64(payload_bytes)
	if payload.is_empty():
		return _failure(&"REPLAY_CODEC_ENCODE_FAILED")
	var envelope := {
		"codec_id": JSON_CODEC_ID,
		"codec_version": JSON_CODEC_VERSION,
		"payload": payload,
		"payload_digest": payload.sha256_text(),
	}
	var result := _success({"json": JSON.stringify(envelope, "", true, true)})
	result["json"] = str(result["context"]["json"])
	return result


static func decode_replay_json(encoded_json: String) -> Dictionary:
	if encoded_json.is_empty() or encoded_json.to_utf8_buffer().size() > MAX_JSON_PAYLOAD_BYTES * 2:
		return _failure(&"REPLAY_CODEC_SIZE_INVALID")
	var parsed_value: Variant = JSON.parse_string(encoded_json)
	if not parsed_value is Dictionary:
		return _failure(&"REPLAY_CODEC_ENVELOPE_INVALID")
	var envelope := parsed_value as Dictionary
	if (
		envelope.size() != 4
		or envelope.get("codec_id") != JSON_CODEC_ID
		or not _is_positive_integral_number(envelope.get("codec_version"))
		or int(envelope.get("codec_version", -1)) != JSON_CODEC_VERSION
		or typeof(envelope.get("payload")) != TYPE_STRING
		or not _is_sha256(envelope.get("payload_digest"))
	):
		return _failure(&"REPLAY_CODEC_ENVELOPE_INVALID")
	var payload := str(envelope["payload"])
	if payload.sha256_text() != str(envelope["payload_digest"]):
		return _failure(&"REPLAY_CODEC_DIGEST_MISMATCH")
	var payload_bytes := Marshalls.base64_to_raw(payload)
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_JSON_PAYLOAD_BYTES:
		return _failure(&"REPLAY_CODEC_PAYLOAD_INVALID")
	var replay_value: Variant = bytes_to_var(payload_bytes)
	if not replay_value is Dictionary or not replay_value_is_safe(replay_value):
		return _failure(&"REPLAY_CODEC_PAYLOAD_INVALID")
	var replay := (replay_value as Dictionary).duplicate(true)
	var result := _success({"replay": replay})
	result["replay"] = replay.duplicate(true)
	return result


static func validate_snapshot(snapshot: Dictionary, expected_identity: Dictionary) -> Dictionary:
	if snapshot.is_empty() or not replay_value_is_safe(snapshot):
		return _failure(&"UNSAFE_SNAPSHOT")
	if not _is_positive_integer(snapshot.get("schema_version")):
		return _failure(&"SNAPSHOT_SCHEMA_MISSING")
	if int(snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _failure(&"SNAPSHOT_SCHEMA_MISMATCH")
	if (
		not _is_non_negative_integer(snapshot.get("event_prefix_count"))
		or not _is_sha256(snapshot.get("event_prefix_root"))
	):
		return _failure(&"SNAPSHOT_EVENT_PREFIX_INVALID")
	if not _is_non_negative_integer(snapshot.get("frame")):
		return _failure(&"INVALID_FRAME")
	if not _is_non_negative_integer(snapshot.get("token")):
		return _failure(&"INVALID_TOKEN")
	if not _is_positive_integer(snapshot.get("generation")):
		return _failure(&"INVALID_GENERATION")
	if not _is_non_empty_string(snapshot.get("weapon_id")):
		return _failure(&"SNAPSHOT_WEAPON_MISSING")

	var snapshot_identity := _snapshot_identity(snapshot)
	if snapshot_identity.is_empty():
		return _failure(&"SNAPSHOT_PROFILE_IDENTITY_MISSING")
	for field: String in ["weapon_id", "profile_id", "profile_version"]:
		if snapshot_identity.get(field) != expected_identity.get(field):
			return _failure(
				&"SNAPSHOT_PROFILE_MISMATCH",
				{"field": field, "expected": expected_identity.get(field), "actual": snapshot_identity.get(field)}
			)
	return _success()


static func validate_event(event: Dictionary, expected_identity: Dictionary = {}) -> Dictionary:
	if not _has_exact_fields_static(event, NORMALIZED_EVENT_FIELDS) or not replay_value_is_safe(event):
		return {}
	if (
		typeof(event.get("schema_version")) != TYPE_INT
		or int(event["schema_version"]) != EVENT_SCHEMA_VERSION
		or not _is_non_negative_integer(event.get("frame"))
		or not _is_positive_integer(event.get("sequence"))
		or not _is_positive_integer(event.get("capture_sequence"))
		or typeof(event.get("event_type")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(event["event_type"]) not in VALID_EVENT_TYPES
		or not event.get("payload") is Dictionary
	):
		return {}
	var event_type := str(event["event_type"])
	var payload := event["payload"] as Dictionary
	if event_type == "weapon_intent":
		if not _valid_intent_payload(payload):
			return {}
	else:
		if not _valid_external_fact_payload(payload):
			return {}
		if not expected_identity.is_empty():
			if str(payload.get("weapon_id", "")) != str(expected_identity.get("weapon_id", "")):
				return {}
			var fact_type := str(payload.get("fact_type", ""))
			var data := payload.get("data", {}) as Dictionary
			if (
				fact_type not in ["time_interaction_claim", "time_stop_extension"]
				and data.has("state_after")
			):
				var state_after_value: Variant = data.get("state_after")
				if not state_after_value is Dictionary:
					return {}
				var state_after := state_after_value as Dictionary
				if (
					not bool(validate_snapshot(state_after, expected_identity).get("ok", false))
					or int(state_after.get("frame", -1)) != int(event["frame"])
				):
					return {}
	return {
		"schema_version": EVENT_SCHEMA_VERSION,
		"frame": int(event["frame"]),
		"sequence": int(event["sequence"]),
		"capture_sequence": int(event["capture_sequence"]),
		"event_type": event_type,
		"payload": payload.duplicate(true),
	}


static func _valid_intent_payload(payload: Dictionary) -> bool:
	return (
		_has_exact_fields_static(payload, INTENT_EVENT_FIELDS)
		and typeof(payload.get("semantic_action")) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(payload["semantic_action"]) in VALID_EVENT_ACTIONS
		and typeof(payload.get("edge")) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(payload["edge"]) in VALID_EVENT_EDGES
		and _is_non_negative_integer(payload.get("held_frames"))
		and payload.get("context") is Dictionary
	)


static func _valid_external_fact_payload(payload: Dictionary) -> bool:
	if (
		not _has_exact_fields_static(payload, EXTERNAL_FACT_FIELDS)
		or typeof(payload.get("fact_type")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(payload["fact_type"]) not in VALID_EXTERNAL_FACT_TYPES
		or not _is_non_empty_string(payload.get("fact_id"))
		or str(payload["fact_id"]).length() > 256
		or not _is_non_empty_string(payload.get("weapon_id"))
		or not _is_positive_integer(payload.get("action_token"))
		or not _is_positive_integer(payload.get("action_generation"))
		or not payload.get("data") is Dictionary
	):
		return false
	var data := payload["data"] as Dictionary
	match str(payload["fact_type"]):
		"combat_damage":
			return _valid_combat_damage_fact(data)
		"weapon_hit_claim":
			return _valid_state_keyframe_fact(
				data,
				["target_path", "state_before_digest", "state_after"]
			)
		"weapon_payload_result":
			return (
				_is_positive_integer(data.get("payload_generation"))
				and _valid_state_keyframe_fact(
				data,
				[
					"result",
					"payload_generation",
					"state_before_digest",
					"state_after",
				]
				)
			)
		"weapon_resource_reward":
			return _valid_resource_reward_fact(data)
		"time_interaction_claim":
			return _valid_time_interaction_claim_fact(data)
		"time_stop_extension":
			return _valid_time_stop_extension_fact(data, int(payload["action_token"]))
	return false


static func _valid_combat_damage_fact(data: Dictionary) -> bool:
	const FIELDS: Array[String] = [
		"target_path",
		"health_path",
		"hp_before",
		"hp_after",
		"resolved_damage",
		"target_dead_after",
		"state_before_digest",
		"state_after",
	]
	if (
		not _has_exact_fields_static(data, FIELDS)
		or not _is_non_empty_string(data.get("target_path"))
		or str(data["target_path"]).length() > 512
		or not _is_non_empty_string(data.get("health_path"))
		or str(data["health_path"]).length() > 512
		or typeof(data.get("target_dead_after")) != TYPE_BOOL
		or not _is_sha256(data.get("state_before_digest"))
		or not data.get("state_after") is Dictionary
	):
		return false
	for field: String in ["hp_before", "hp_after", "resolved_damage"]:
		if typeof(data.get(field)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[field])):
			return false
	var hp_before := float(data["hp_before"])
	var hp_after := float(data["hp_after"])
	var resolved_damage := float(data["resolved_damage"])
	return (
		hp_before >= 0.0
		and hp_after >= 0.0
		and resolved_damage > 0.0
		and absf(maxf(0.0, hp_before - resolved_damage) - hp_after)
			<= HP_ABSOLUTE_EPSILON
		and bool(data["target_dead_after"]) == (hp_after <= 0.0)
	)


static func _valid_state_keyframe_fact(data: Dictionary, fields: Array[String]) -> bool:
	if not _has_exact_fields_static(data, fields) or not data.get("state_after") is Dictionary:
		return false
	if data.has("state_before_digest") and not _is_sha256(data.get("state_before_digest")):
		return false
	if data.has("target_path") and not _is_non_empty_string(data.get("target_path")):
		return false
	return not data.has("result") or data.get("result") is Dictionary


static func _valid_resource_reward_fact(data: Dictionary) -> bool:
	const FIELDS: Array[String] = [
		"claim_id",
		"reward_id",
		"amount",
		"energy_before",
		"energy_after",
		"maximum",
		"energy_revision_before",
		"state_before_digest",
		"state_after",
	]
	if (
		not _valid_state_keyframe_fact(data, FIELDS)
		or typeof(data.get("claim_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(data.get("reward_id", "")) != "time_energy"
		or not _is_positive_integer(data.get("energy_revision_before"))
	):
		return false
	for field: String in ["amount", "energy_before", "energy_after", "maximum"]:
		if typeof(data.get(field)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[field])):
			return false
	var state_after := data["state_after"] as Dictionary
	var time_energy_state := _time_energy_state_from_snapshot(state_after)
	if time_energy_state.is_empty():
		return false
	var expected_after := minf(
		float(data["maximum"]),
		float(data["energy_before"]) + float(data["amount"])
	)
	return (
		float(data["amount"]) > 0.0
		and float(data["maximum"]) > 0.0
		and float(data["energy_before"]) >= 0.0
		and float(data["energy_after"]) > float(data["energy_before"])
		and float(data["energy_after"]) <= float(data["maximum"])
		and is_equal_approx(float(data["energy_after"]), expected_after)
		and is_equal_approx(float(time_energy_state.get("current", -1.0)), expected_after)
		and is_equal_approx(
			float(time_energy_state.get("maximum", -1.0)),
			float(data["maximum"])
		)
		and int(time_energy_state.get("revision", 0)) == int(data["energy_revision_before"]) + 1
	)


static func _time_energy_state_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var time_manager_value: Variant = snapshot.get("time_manager_state")
	var coordinator_value: Variant = snapshot.get("coordinator")
	if not time_manager_value is Dictionary or not coordinator_value is Dictionary:
		return {}
	var time_energy_value: Variant = (time_manager_value as Dictionary).get("time_energy_state")
	var transaction_value: Variant = (coordinator_value as Dictionary).get("resource_transaction")
	if not time_energy_value is Dictionary or not transaction_value is Dictionary:
		return {}
	var external_accounts_value: Variant = (transaction_value as Dictionary).get("external_accounts")
	if not external_accounts_value is Dictionary:
		return {}
	var coordinator_energy_value: Variant = (external_accounts_value as Dictionary).get(
		"time_energy"
	)
	if (
		not coordinator_energy_value is Dictionary
		or (coordinator_energy_value as Dictionary) != (time_energy_value as Dictionary)
		or not _valid_time_energy_state(time_energy_value as Dictionary)
	):
		return {}
	return (time_energy_value as Dictionary).duplicate(true)


static func _valid_time_interaction_claim_fact(data: Dictionary) -> bool:
	const FIELDS: Array[String] = [
		"interaction_id",
		"generation",
		"state_before",
		"state_after",
	]
	if (
		not _has_exact_fields_static(data, FIELDS)
		or str(data.get("interaction_id", "")) != "bow_rewind_echo"
		or not _is_positive_integer(data.get("generation"))
		or not data.get("state_before") is Dictionary
		or not data.get("state_after") is Dictionary
	):
		return false
	var before := data["state_before"] as Dictionary
	var after := data["state_after"] as Dictionary
	if not _valid_time_replay_snapshot(before) or not _valid_time_replay_snapshot(after):
		return false
	for field: String in [
		"time_energy_state",
		"stop_active",
		"stop_source_sequence",
		"stop_source_id",
		"stop_remaining",
		"stop_extension_frames",
		"stop_extension_tokens",
	]:
		if before[field] != after[field]:
			return false
	var generation := int(data["generation"])
	return (
		float(before["rewind_window_remaining"]) > 0.0
		and int(before["rewind_window_generation"]) == generation
		and not bool(before["rewind_window_claimed"])
		and float(after["rewind_window_remaining"]) == 0.0
		and int(after["rewind_window_generation"]) == generation
		and bool(after["rewind_window_claimed"])
	)


static func _valid_time_stop_extension_fact(data: Dictionary, action_token: int) -> bool:
	const FIELDS: Array[String] = ["extension_frames", "state_before", "state_after"]
	if (
		not _has_exact_fields_static(data, FIELDS)
		or not _is_positive_integer(data.get("extension_frames"))
		or action_token <= 0
		or not data.get("state_before") is Dictionary
		or not data.get("state_after") is Dictionary
	):
		return false
	var before := data["state_before"] as Dictionary
	var after := data["state_after"] as Dictionary
	if not _valid_time_replay_snapshot(before) or not _valid_time_replay_snapshot(after):
		return false
	for field: String in [
		"time_energy_state",
		"stop_active",
		"stop_source_sequence",
		"stop_source_id",
		"rewind_window_remaining",
		"rewind_window_generation",
		"rewind_window_claimed",
	]:
		if before[field] != after[field]:
			return false
	if not bool(before["stop_active"]) or not bool(after["stop_active"]):
		return false
	var before_frames := int(before["stop_extension_frames"])
	var granted := mini(int(data["extension_frames"]), 60 - before_frames)
	if granted <= 0 or int(after["stop_extension_frames"]) != before_frames + granted:
		return false
	if not is_equal_approx(
		float(after["stop_remaining"]),
		float(before["stop_remaining"]) + float(granted) / 60.0
	):
		return false
	var before_tokens := before["stop_extension_tokens"] as Dictionary
	var expected_tokens := before_tokens.duplicate(true)
	if expected_tokens.has(action_token):
		return false
	expected_tokens[action_token] = true
	return (after["stop_extension_tokens"] as Dictionary) == expected_tokens


static func _valid_time_replay_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields_static(value, TIME_REPLAY_SNAPSHOT_FIELDS):
		return false
	if (
		not _is_positive_integer(value.get("schema_version"))
		or int(value["schema_version"]) != 2
		or not value.get("time_energy_state") is Dictionary
		or not _valid_time_energy_state(value["time_energy_state"] as Dictionary)
		or typeof(value.get("stop_active")) != TYPE_BOOL
		or not _is_non_negative_integer(value.get("stop_source_sequence"))
		or typeof(value.get("stop_source_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value.get("stop_remaining")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["stop_remaining"]))
		or float(value["stop_remaining"]) < 0.0
		or not _is_non_negative_integer(value.get("stop_extension_frames"))
		or int(value["stop_extension_frames"]) > 60
		or not value.get("stop_extension_tokens") is Dictionary
		or typeof(value.get("rewind_window_remaining")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["rewind_window_remaining"]))
		or float(value["rewind_window_remaining"]) < 0.0
		or not _is_non_negative_integer(value.get("rewind_window_generation"))
		or typeof(value.get("rewind_window_claimed")) != TYPE_BOOL
	):
		return false
	var stop_active := bool(value["stop_active"])
	if stop_active != (not str(value["stop_source_id"]).is_empty()):
		return false
	if stop_active:
		if int(value["stop_source_sequence"]) <= 0 or float(value["stop_remaining"]) <= 0.0:
			return false
	elif not is_zero_approx(float(value["stop_remaining"])):
		return false
	var tokens := value["stop_extension_tokens"] as Dictionary
	for token_value: Variant in tokens.keys():
		if (
			typeof(token_value) != TYPE_INT
			or int(token_value) <= 0
			or typeof(tokens[token_value]) != TYPE_BOOL
			or not bool(tokens[token_value])
		):
			return false
	if not stop_active and (int(value["stop_extension_frames"]) != 0 or not tokens.is_empty()):
		return false
	var rewind_remaining := float(value["rewind_window_remaining"])
	var rewind_generation := int(value["rewind_window_generation"])
	var rewind_claimed := bool(value["rewind_window_claimed"])
	if rewind_remaining > 0.0 and (rewind_generation <= 0 or rewind_claimed):
		return false
	if rewind_claimed and (rewind_generation <= 0 or not is_zero_approx(rewind_remaining)):
		return false
	if rewind_generation == 0 and (not is_zero_approx(rewind_remaining) or rewind_claimed):
		return false
	return true


static func _valid_time_energy_state(value: Dictionary) -> bool:
	if not _has_exact_fields_static(value, TIME_ENERGY_STATE_FIELDS):
		return false
	for field: String in ["current", "minimum", "maximum"]:
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field])):
			return false
	return (
		typeof(value["ok"]) == TYPE_BOOL
		and bool(value["ok"])
		and typeof(value["code"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(value["code"]) == "OK"
		and typeof(value["resource_id"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(value["resource_id"]) == "time_energy"
		and float(value["minimum"]) == 0.0
		and float(value["maximum"]) > 0.0
		and float(value["current"]) >= 0.0
		and float(value["current"]) <= float(value["maximum"])
		and _is_positive_integer(value["revision"])
		and value["context"] is Dictionary
		and (value["context"] as Dictionary).is_empty()
	)


static func _has_exact_fields_static(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func value_digest(value: Variant) -> String:
	if not replay_value_is_safe(value):
		return ""
	return _canonical_value(value).sha256_text()


static func replay_value_is_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			return true
		TYPE_RECT2, TYPE_RECT2I, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_PLANE:
			return true
		TYPE_QUATERNION, TYPE_AABB, TYPE_BASIS, TYPE_PROJECTION, TYPE_COLOR:
			return true
		TYPE_ARRAY:
			for item: Variant in value as Array:
				if not replay_value_is_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
					return false
				if not replay_value_is_safe((value as Dictionary)[key]):
					return false
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return true
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			for numeric_value: Variant in value:
				if not is_finite(float(numeric_value)):
					return false
			return true
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return true
	return false


static func _snapshot_identity(snapshot: Dictionary) -> Dictionary:
	var root_profile_id: Variant = snapshot.get("profile_id")
	var root_profile_version: Variant = snapshot.get("profile_version")
	var runtime_value: Variant = snapshot.get("runtime")
	var runtime: Dictionary = runtime_value if runtime_value is Dictionary else {}
	var runtime_profile_id: Variant = runtime.get("profile_id")
	var runtime_profile_version: Variant = runtime.get("profile_version")
	var profile_id: Variant = root_profile_id if root_profile_id != null else runtime_profile_id
	var profile_version: Variant = root_profile_version if root_profile_version != null else runtime_profile_version
	if not _is_non_empty_string(profile_id) or not _is_positive_integer(profile_version):
		return {}
	if root_profile_id != null and runtime_profile_id != null and str(root_profile_id) != str(runtime_profile_id):
		return {}
	if (
		root_profile_version != null
		and runtime_profile_version != null
		and int(root_profile_version) != int(runtime_profile_version)
	):
		return {}
	var weapon_id := str(snapshot.get("weapon_id", ""))
	if runtime.has("weapon_id") and str(runtime.get("weapon_id", "")) != weapon_id:
		return {}
	return {
		"weapon_id": weapon_id,
		"profile_id": str(profile_id),
		"profile_version": int(profile_version),
	}


static func _canonical_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "n;"
		TYPE_BOOL:
			return "b:%d;" % [1 if bool(value) else 0]
		TYPE_INT:
			return "i:%d;" % int(value)
		TYPE_FLOAT:
			var numeric := float(value)
			if numeric == floorf(numeric):
				return "i:%d;" % int(numeric)
			return "f:%s;" % ("0" if numeric == 0.0 else String.num_scientific(numeric))
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value)
			return "s:%d:%s;" % [text.to_utf8_buffer().size(), text]
		TYPE_ARRAY:
			var result := "a:%d:[" % (value as Array).size()
			for item: Variant in value as Array:
				result += _canonical_value(item)
			return result + "]"
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			var encoded_keys: Array[String] = []
			var values_by_key: Dictionary = {}
			for key: Variant in dictionary.keys():
				var encoded_key := _canonical_value(key)
				encoded_keys.append(encoded_key)
				values_by_key[encoded_key] = dictionary[key]
			encoded_keys.sort()
			var result := "d:%d:{" % encoded_keys.size()
			for encoded_key: String in encoded_keys:
				result += encoded_key + _canonical_value(values_by_key[encoded_key])
			return result + "}"
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return "p%d:%s;" % [typeof(value), str(value)]
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var result := "p%d:[" % typeof(value)
			for numeric_value: Variant in value:
				result += _canonical_value(float(numeric_value))
			return result + "]"
		TYPE_PACKED_STRING_ARRAY:
			var result := "p%d:[" % typeof(value)
			for text_value: Variant in value:
				result += _canonical_value(str(text_value))
			return result + "]"
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var result := "p%d:[" % typeof(value)
			for vector_value: Variant in value:
				result += "v:%s;" % var_to_str(vector_value)
			return result + "]"
	return "v%d:%s;" % [typeof(value), var_to_str(value)]


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


static func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}


static func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and not str(value).is_empty()


static func _is_positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 1


static func _is_non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


static func _is_positive_integral_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric) and numeric >= 1.0


static func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != SHA256_LENGTH:
		return false
	for character: String in str(value):
		if character not in "0123456789abcdef":
			return false
	return true
