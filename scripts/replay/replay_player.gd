class_name ReplayPlayer
extends RefCounted

const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")

var _replay: Dictionary = {}
var _cursor := -1
var _full_player_replay: Dictionary = {}
var _full_player_cursor := -1


func load_replay(replay: Dictionary, expected_profile: Dictionary) -> Dictionary:
	reset()
	var expected_identity := ReplayRecorderScript.profile_identity(expected_profile)
	if expected_identity.is_empty():
		return _failure(&"INVALID_EXPECTED_PROFILE", {
			"profile_id": expected_profile.get("id"),
			"weapon_id": expected_profile.get("weapon_id"),
			"profile_version": expected_profile.get("profile_version"),
			"profile_version_type": typeof(expected_profile.get("profile_version")),
			"digest_length": ReplayRecorderScript.profile_digest(expected_profile).length(),
		})
	var validation := _validate_replay(replay, expected_identity)
	if not bool(validation.get("ok", false)):
		return validation
	var migrated := ReplayRecorderScript.migrate_legacy_v6_time_snapshots(replay)
	var migrated_validation := _validate_replay(migrated, expected_identity)
	if not bool(migrated_validation.get("ok", false)):
		return _failure(&"REPLAY_MIGRATION_INVALID", {
			"reason": migrated_validation.get("code", &"INVALID_REPLAY"),
		})
	_replay = migrated.duplicate(true)
	_cursor = -1
	return _success({"summary": summary()})


func load(replay: Dictionary, expected_profile: Dictionary) -> Dictionary:
	return load_replay(replay, expected_profile)


func load_replay_json(encoded_json: String, expected_profile: Dictionary) -> Dictionary:
	reset()
	var decoded: Dictionary = ReplayRecorderScript.decode_replay_json(encoded_json)
	if not bool(decoded.get("ok", false)):
		return decoded
	return load_replay((decoded.get("replay", {}) as Dictionary).duplicate(true), expected_profile)


func reset() -> void:
	_replay.clear()
	_cursor = -1


func unload() -> void:
	reset()


func is_loaded() -> bool:
	return not _replay.is_empty()


func frame_count() -> int:
	if not is_loaded():
		return 0
	return int(_replay.get("frame_count", 0))


func frame_at(index: int) -> Dictionary:
	if not is_loaded() or index < 0 or index >= frame_count():
		return {}
	var frames: Array = _replay.get("frames", [])
	return (frames[index] as Dictionary).duplicate(true)


func current_frame() -> Dictionary:
	return frame_at(_cursor)


func next_frame() -> Dictionary:
	if not is_loaded() or _cursor + 1 >= frame_count():
		return {}
	_cursor += 1
	return current_frame()


func seek_to_frame(frame_number: int) -> Dictionary:
	if not is_loaded() or frame_number < 0:
		return {}
	var frames: Array = _replay.get("frames", [])
	for index: int in range(frames.size()):
		var frame: Dictionary = frames[index]
		if int(frame.get("frame", -1)) == frame_number:
			_cursor = index
			return frame.duplicate(true)
	return {}


func summary() -> Dictionary:
	return ReplayRecorderScript.replay_summary(_replay)


func replay_snapshot() -> Dictionary:
	return _replay.duplicate(true)


func load_full_player_replay(
	replay: Dictionary,
	expected_identity: Dictionary
) -> Dictionary:
	reset_full_player_replay()
	var identity := ReplayRecorderScript.validate_full_player_identity(expected_identity)
	if identity.is_empty():
		return _failure(&"FULL_PLAYER_EXPECTED_IDENTITY_INVALID")
	var validation := _validate_full_player_replay(replay, identity)
	if not bool(validation.get("ok", false)):
		return validation
	var normalization := ReplayRecorderScript.normalize_full_player_replay(replay)
	if not bool(normalization.get("ok", false)):
		return normalization
	var normalized_replay := (
		(normalization.get("context", {}) as Dictionary).get("replay", {}) as Dictionary
	)
	var normalized_validation := _validate_full_player_replay(normalized_replay, identity)
	if not bool(normalized_validation.get("ok", false)):
		return _failure(&"FULL_PLAYER_REPLAY_MIGRATION_INVALID", {
			"reason": normalized_validation.get(
				"code",
				&"FULL_PLAYER_REPLAY_SNAPSHOT_INVALID"
			),
		})
	_full_player_replay = normalized_replay.duplicate(true)
	_full_player_cursor = -1
	return _success({"summary": full_player_summary()})


func load_full_player_replay_json(
	encoded_json: String,
	expected_identity: Dictionary
) -> Dictionary:
	reset_full_player_replay()
	var decoded: Dictionary = ReplayRecorderScript.decode_replay_json(encoded_json)
	if not bool(decoded.get("ok", false)):
		return decoded
	return load_full_player_replay(
		(decoded.get("replay", {}) as Dictionary).duplicate(true),
		expected_identity
	)


func reset_full_player_replay() -> void:
	_full_player_replay.clear()
	_full_player_cursor = -1


func is_full_player_replay_loaded() -> bool:
	return not _full_player_replay.is_empty()


func full_player_frame_count() -> int:
	return int(_full_player_replay.get("frame_count", 0)) if is_full_player_replay_loaded() else 0


func full_player_frame_at(index: int) -> Dictionary:
	if index < 0 or index >= full_player_frame_count():
		return {}
	var frames := _full_player_replay.get("frames", []) as Array
	return (frames[index] as Dictionary).duplicate(true)


func full_player_summary() -> Dictionary:
	return ReplayRecorderScript.full_player_replay_summary(_full_player_replay)


func full_player_replay_snapshot() -> Dictionary:
	return _full_player_replay.duplicate(true)


func restore_full_player_frame(target: Object, index: int = -1) -> Dictionary:
	if not is_full_player_replay_loaded():
		return _failure(&"FULL_PLAYER_REPLAY_NOT_LOADED")
	var target_validation := _validate_full_player_target(target)
	if not bool(target_validation.get("ok", false)):
		return target_validation
	var frame_index := _full_player_cursor if index < 0 else index
	var frame_entry := full_player_frame_at(frame_index)
	if frame_entry.is_empty():
		return _failure(&"FULL_PLAYER_REPLAY_FRAME_NOT_FOUND", {"index": frame_index})
	var expected_snapshot := (
		frame_entry.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var before_value: Variant = target.call("full_player_replay_snapshot")
	if not before_value is Dictionary:
		return _failure(&"FULL_PLAYER_REPLAY_TARGET_INVALID")
	var before := (before_value as Dictionary).duplicate(true)
	if not bool(target.call(
		"restore_full_player_replay_snapshot",
		expected_snapshot.duplicate(true)
	)):
		return _failure(&"FULL_PLAYER_REPLAY_RESTORE_REJECTED", {"index": frame_index})
	var actual_value: Variant = target.call("full_player_replay_snapshot")
	if not actual_value is Dictionary or actual_value != expected_snapshot:
		var rolled_back := _rollback_full_player_target(target, before)
		return _failure(
			&"FULL_PLAYER_REPLAY_RESTORE_MISMATCH" if rolled_back
			else &"FULL_PLAYER_REPLAY_ROLLBACK_FAILED",
			{"index": frame_index}
		)
	_full_player_cursor = frame_index
	return _success({
		"index": frame_index,
		"digest": str(frame_entry.get("digest", "")),
	})


func replay_full_player_to_terminal(
	target: Object,
	checkpoint_index: int = -1
) -> Dictionary:
	if not is_full_player_replay_loaded():
		return _failure(&"FULL_PLAYER_REPLAY_NOT_LOADED")
	var target_validation := _validate_full_player_target(target)
	if not bool(target_validation.get("ok", false)):
		return target_validation
	var before_value: Variant = target.call("full_player_replay_snapshot")
	if not before_value is Dictionary:
		return _failure(&"FULL_PLAYER_REPLAY_TARGET_INVALID")
	var before := (before_value as Dictionary).duplicate(true)
	var cursor_before := _full_player_cursor
	var frame_index := _full_player_cursor if checkpoint_index < 0 else checkpoint_index
	var restored := restore_full_player_frame(target, frame_index)
	if not bool(restored.get("ok", false)):
		return restored
	for next_index: int in range(frame_index + 1, full_player_frame_count()):
		var expected_entry := full_player_frame_at(next_index)
		var expected_frame := int(expected_entry.get("frame", -1))
		var advance_result := _advance_full_player_target(
			target,
			expected_entry.get("frame_intents", {}) as Dictionary
		)
		if not bool(advance_result.get("ok", false)):
				return _full_player_playback_failure(
					target,
					before,
					cursor_before,
					&"FULL_PLAYER_REPLAY_FRAME_REJECTED",
				{"index": next_index, "frame": expected_frame}
			)
		var observed_facts := advance_result.get("verification_facts", []) as Array
		var expected_facts := expected_entry.get("verification_facts", []) as Array
		if observed_facts != expected_facts:
				return _full_player_playback_failure(
					target,
					before,
					cursor_before,
					&"FULL_PLAYER_REPLAY_VERIFICATION_FACT_MISMATCH",
				{
					"index": next_index,
					"frame": expected_frame,
					"expected_digest": ReplayRecorderScript.value_digest(expected_facts),
					"actual_digest": ReplayRecorderScript.value_digest(observed_facts),
				}
			)
		var actual_value: Variant = target.call("full_player_replay_snapshot")
		var expected_snapshot := expected_entry.get("snapshot", {}) as Dictionary
		if not actual_value is Dictionary or actual_value != expected_snapshot:
			var actual_snapshot := actual_value as Dictionary if actual_value is Dictionary else {}
			var drift_fields := _full_player_snapshot_drift_fields(
				expected_snapshot,
				actual_snapshot
			)
			var player_state_drift_fields: Array[String] = []
			if "player_state" in drift_fields:
				player_state_drift_fields = _full_player_snapshot_drift_fields(
					expected_snapshot.get("player_state", {}) as Dictionary,
					actual_snapshot.get("player_state", {}) as Dictionary
				)
				return _full_player_playback_failure(
					target,
					before,
					cursor_before,
					&"FULL_PLAYER_REPLAY_CHECKPOINT_MISMATCH",
				{
					"index": next_index,
					"frame": expected_frame,
					"expected_digest": ReplayRecorderScript.value_digest(expected_snapshot),
					"actual_digest": ReplayRecorderScript.value_digest(actual_value),
					"drift_fields": drift_fields,
					"player_state_drift_fields": player_state_drift_fields,
				}
			)
	_full_player_cursor = full_player_frame_count() - 1
	var terminal := full_player_frame_at(_full_player_cursor)
	var terminal_snapshot_value: Variant = target.call("full_player_replay_snapshot")
	if (
		not terminal_snapshot_value is Dictionary
		or ReplayRecorderScript.value_digest(terminal_snapshot_value)
			!= str(_full_player_replay.get("terminal_snapshot_digest", ""))
	):
		return _full_player_playback_failure(
			target,
			before,
			cursor_before,
			&"FULL_PLAYER_REPLAY_TERMINAL_DIGEST_MISMATCH",
			{}
		)
	return _success({
		"index": _full_player_cursor,
		"digest": str(terminal.get("digest", "")),
		"terminal_snapshot_digest": str(
			_full_player_replay.get("terminal_snapshot_digest", "")
		),
	})


func _advance_full_player_target(
	target: Object,
	frame_intents: Dictionary
) -> Dictionary:
	var observed_facts: Array[Dictionary] = []
	var observer := func(
		ability_id: StringName,
		token: int,
		generation: int,
		frame: int,
		run_id: StringName,
		context: Dictionary
	) -> void:
		observed_facts.append({
			"ability_id": ability_id,
			"token": token,
			"generation": generation,
			"frame": frame,
			"run_id": run_id,
			"context": context.duplicate(true),
		})
	EventBus.time_skill_committed.connect(observer)
	var result_value: Variant = target.call(
		"advance_action_frame",
		frame_intents.duplicate(true)
	)
	if EventBus.time_skill_committed.is_connected(observer):
		EventBus.time_skill_committed.disconnect(observer)
	return {
		"ok": typeof(result_value) == TYPE_BOOL and bool(result_value),
		"verification_facts": observed_facts,
	}


func _validate_full_player_target(target: Object) -> Dictionary:
	if (
		target == null
		or not target.has_method("full_player_replay_identity")
		or not target.has_method("full_player_replay_snapshot")
		or not target.has_method("restore_full_player_replay_snapshot")
		or not target.has_method("advance_action_frame")
	):
		return _failure(&"FULL_PLAYER_REPLAY_TARGET_INVALID")
	var identity_value: Variant = target.call("full_player_replay_identity")
	if not identity_value is Dictionary:
		return _failure(&"FULL_PLAYER_REPLAY_TARGET_INVALID")
	if identity_value != _full_player_replay.get("identity", {}):
		return _failure(&"FULL_PLAYER_REPLAY_TARGET_IDENTITY_MISMATCH")
	return _success()


func _rollback_full_player_target(target: Object, before: Dictionary) -> bool:
	return (
		bool(target.call("restore_full_player_replay_snapshot", before.duplicate(true)))
		and target.call("full_player_replay_snapshot") == before
	)


func _full_player_snapshot_drift_fields(
	expected: Dictionary,
	actual: Dictionary
) -> Array[String]:
	var fields: Array[String] = []
	for key_value: Variant in expected.keys():
		var key := str(key_value)
		if not actual.has(key_value) or actual[key_value] != expected[key_value]:
			fields.append(key)
	for key_value: Variant in actual.keys():
		var key := str(key_value)
		if not expected.has(key_value) and key not in fields:
			fields.append(key)
	fields.sort()
	return fields


func _full_player_playback_failure(
	target: Object,
	before: Dictionary,
	cursor_before: int,
	code: StringName,
	context: Dictionary
) -> Dictionary:
	if not _rollback_full_player_target(target, before):
		return _failure(&"FULL_PLAYER_REPLAY_ROLLBACK_FAILED", context)
	_full_player_cursor = cursor_before
	return _failure(code, context)


func replay_to_terminal(target: Object, checkpoint_index: int = -1) -> Dictionary:
	if not is_loaded():
		return _failure(&"REPLAY_NOT_LOADED")
	if (
		target == null
		or not target.has_method("restore_weapon_replay_snapshot")
		or not target.has_method("weapon_replay_snapshot")
		or not target.has_method("apply_weapon_replay_event")
		or not target.has_method("advance_action_frame")
	):
		return _failure(&"REPLAY_TARGET_INVALID")
	var terminal_frame := frame_at(frame_count() - 1)
	var terminal_snapshot_value: Variant = terminal_frame.get("snapshot")
	if not terminal_snapshot_value is Dictionary:
		return _failure(&"INVALID_REPLAY_SNAPSHOT")
	var terminal_snapshot := terminal_snapshot_value as Dictionary
	var current_value: Variant = target.call("weapon_replay_snapshot")
	if current_value is Dictionary and current_value == terminal_snapshot:
		_cursor = frame_count() - 1
		return _success({"index": _cursor, "digest": str(terminal_frame.get("digest", ""))})

	var frame_index := _cursor if checkpoint_index < 0 else checkpoint_index
	var restored := restore_frame(target, frame_index)
	if not bool(restored.get("ok", false)):
		return restored
	var checkpoint := frame_at(frame_index)
	var checkpoint_frame := int(checkpoint.get("frame", -1))
	var captured_sequences := _checkpoint_capture_sequences(checkpoint)
	var events := _replay.get("events", []) as Array
	var event_index := 0
	while event_index < events.size():
		var historical_event := events[event_index] as Dictionary
		var historical_frame := int(historical_event.get("frame", -1))
		var already_captured := (
			historical_frame < checkpoint_frame
			or captured_sequences.has(int(historical_event.get("capture_sequence", 0)))
		)
		if not already_captured:
			break
		event_index += 1

	for next_frame_index: int in range(frame_index + 1, frame_count()):
		var expected_entry := frame_at(next_frame_index)
		var expected_frame := int(expected_entry.get("frame", -1))
		while event_index < events.size():
			var event_value: Variant = events[event_index]
			if not event_value is Dictionary:
				return _failure(&"INVALID_REPLAY_EVENT", {"index": event_index})
			var event := event_value as Dictionary
			var event_frame := int(event.get("frame", -1))
			if event_frame > expected_frame:
				break
			if captured_sequences.has(int(event.get("capture_sequence", 0))):
				event_index += 1
				continue
			var advanced_to_event := _advance_replay_target_to_frame(target, event_frame)
			if not bool(advanced_to_event.get("ok", false)):
				return _failure(
					&"REPLAY_EVENT_FRAME_MISMATCH",
					{"frame": event_frame, "index": event_index}
				)
			var normalized_event := event.duplicate(true)
			normalized_event.erase("digest")
			if not bool(target.call("apply_weapon_replay_event", normalized_event)):
				var payload := normalized_event.get("payload", {}) as Dictionary
				return _failure(&"REPLAY_EVENT_REJECTED", {
					"frame": event_frame,
					"index": event_index,
					"event_type": str(normalized_event.get("event_type", "")),
					"fact_type": str(payload.get("fact_type", "")),
				})
			event_index += 1

		var advanced_to_checkpoint := _advance_replay_target_to_frame(target, expected_frame)
		if not bool(advanced_to_checkpoint.get("ok", false)):
			return _failure(
				&"REPLAY_CHECKPOINT_FRAME_MISMATCH",
				{"frame": expected_frame, "index": next_frame_index}
			)
		var actual_snapshot := advanced_to_checkpoint.get("snapshot", {}) as Dictionary
		var expected_snapshot_value: Variant = expected_entry.get("snapshot")
		if not expected_snapshot_value is Dictionary:
			return _failure(&"INVALID_REPLAY_SNAPSHOT", {"index": next_frame_index})
		var expected_snapshot := expected_snapshot_value as Dictionary
		if actual_snapshot != expected_snapshot:
			return _failure(&"REPLAY_CHECKPOINT_MISMATCH", {
				"index": next_frame_index,
				"frame": expected_frame,
				"expected_digest": ReplayRecorderScript.value_digest(expected_snapshot),
				"actual_digest": ReplayRecorderScript.value_digest(actual_snapshot),
			})
	_cursor = frame_count() - 1
	return _success({"index": _cursor, "digest": str(terminal_frame.get("digest", ""))})


func _checkpoint_capture_sequences(frame_entry: Dictionary) -> Dictionary:
	var snapshot_value: Variant = frame_entry.get("snapshot")
	if not snapshot_value is Dictionary:
		return {}
	var count_value: Variant = (snapshot_value as Dictionary).get("event_prefix_count")
	if typeof(count_value) != TYPE_INT or int(count_value) < 0:
		return {}
	var ordered := _events_in_capture_order(_replay.get("events", []) as Array)
	var sequences: Dictionary = {}
	for index: int in range(mini(int(count_value), ordered.size())):
		sequences[int(ordered[index].get("capture_sequence", 0))] = true
	return sequences


func _advance_replay_target_to_frame(target: Object, expected_frame: int) -> Dictionary:
	var snapshot_value: Variant = target.call("weapon_replay_snapshot")
	if not snapshot_value is Dictionary:
		return {"ok": false}
	var snapshot := snapshot_value as Dictionary
	var current_frame := int(snapshot.get("frame", -1))
	if current_frame > expected_frame:
		return {"ok": false}
	while current_frame < expected_frame:
		if not _advance_target_frame(target, current_frame + 1):
			return {"ok": false}
		snapshot_value = target.call("weapon_replay_snapshot")
		if not snapshot_value is Dictionary:
			return {"ok": false}
		snapshot = snapshot_value as Dictionary
		var next_frame := int(snapshot.get("frame", -1))
		if next_frame <= current_frame:
			return {"ok": false}
		current_frame = next_frame
	if current_frame != expected_frame:
		return {"ok": false}
	return {"ok": true, "snapshot": snapshot.duplicate(true)}


func _advance_target_frame(target: Object, _target_frame: int) -> bool:
	if not target.has_method("advance_action_frame"):
		return false
	var method_signature: Dictionary = {}
	for method_value: Variant in target.get_method_list():
		if (
			method_value is Dictionary
			and str((method_value as Dictionary).get("name", "")) == "advance_action_frame"
		):
			method_signature = (method_value as Dictionary).duplicate(true)
			break
	if method_signature.is_empty():
		return false
	var arguments_value: Variant = method_signature.get("args", [])
	var default_arguments_value: Variant = method_signature.get("default_args", [])
	if not arguments_value is Array or not default_arguments_value is Array:
		return false
	var arguments := arguments_value as Array
	var default_arguments := default_arguments_value as Array
	var required_argument_count := maxi(arguments.size() - default_arguments.size(), 0)
	var call_result: Variant = null
	if arguments.is_empty():
		call_result = target.call("advance_action_frame")
	elif required_argument_count <= 1:
		call_result = target.call("advance_action_frame", {})
	else:
		return false
	if typeof(call_result) == TYPE_BOOL:
		return bool(call_result)
	return true


func restore_frame(target: Object, index: int = -1) -> Dictionary:
	if not is_loaded():
		return _failure(&"REPLAY_NOT_LOADED")
	if (
		target == null
		or (
			not target.has_method("restore_weapon_replay_snapshot")
			and not target.has_method("restore_snapshot")
		)
	):
		return _failure(&"REPLAY_TARGET_INVALID")
	var frame_index := _cursor if index < 0 else index
	var frame := frame_at(frame_index)
	if frame.is_empty():
		return _failure(&"REPLAY_FRAME_NOT_FOUND", {"index": frame_index})
	var snapshot_value: Variant = frame.get("snapshot")
	if not snapshot_value is Dictionary:
		return _failure(&"INVALID_REPLAY_SNAPSHOT", {"index": frame_index})
	var snapshot := (snapshot_value as Dictionary).duplicate(true)
	var restored := false
	if target.has_method("restore_weapon_replay_snapshot_with_event_prefix"):
		var prefix := _verified_event_prefix(snapshot)
		if not bool(prefix.get("ok", false)):
			return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": frame_index})
		restored = bool(target.call(
			"restore_weapon_replay_snapshot_with_event_prefix",
			snapshot,
			(prefix.get("events", []) as Array).duplicate(true)
		))
	elif int(snapshot.get("event_prefix_count", -1)) == 0:
		var restore_method := (
			&"restore_weapon_replay_snapshot"
			if target.has_method("restore_weapon_replay_snapshot")
			else &"restore_snapshot"
		)
		restored = bool(target.call(restore_method, snapshot))
	else:
		return _failure(&"REPLAY_TARGET_EVENT_PREFIX_UNSUPPORTED", {"index": frame_index})
	if not restored:
		return _failure(&"REPLAY_RESTORE_REJECTED", {"index": frame_index})
	_cursor = frame_index
	return _success({"index": frame_index, "digest": str(frame.get("digest", ""))})


func _validate_replay(replay: Dictionary, expected_identity: Dictionary) -> Dictionary:
	if replay.is_empty() or not ReplayRecorderScript.replay_value_is_safe(replay):
		return _failure(&"UNSAFE_REPLAY")
	if not _has_exact_fields(replay, ReplayRecorderScript.REPLAY_FIELDS):
		return _failure(&"REPLAY_FIELDS_MISMATCH")
	if replay.get("schema_id") != ReplayRecorderScript.SCHEMA_ID:
		return _failure(&"REPLAY_SCHEMA_ID_MISMATCH")
	if (
		not ReplayRecorderScript._is_positive_integer(replay.get("schema_version"))
		or int(replay.get("schema_version", -1)) != ReplayRecorderScript.SCHEMA_VERSION
	):
		return _failure(&"REPLAY_SCHEMA_VERSION_MISMATCH")
	if not ReplayRecorderScript._is_non_negative_integer(replay.get("seed")):
		return _failure(&"INVALID_REPLAY_SEED")
	for field: String in ["weapon_id", "profile_id", "profile_version", "profile_digest"]:
		if replay.get(field) != expected_identity.get(field):
			return _failure(
				&"REPLAY_PROFILE_MISMATCH",
				{"field": field, "expected": expected_identity.get(field), "actual": replay.get(field)}
			)

	var frames_value: Variant = replay.get("frames")
	if not frames_value is Array or (frames_value as Array).is_empty():
		return _failure(&"INVALID_REPLAY_FRAMES")
	var frames := frames_value as Array
	if (
		not ReplayRecorderScript._is_non_negative_integer(replay.get("frame_count"))
		or int(replay.get("frame_count", -1)) != frames.size()
	):
		return _failure(&"REPLAY_FRAME_COUNT_MISMATCH")
	var events_value: Variant = replay.get("events")
	if not events_value is Array:
		return _failure(&"INVALID_REPLAY_EVENTS")
	var events := events_value as Array
	if (
		not ReplayRecorderScript._is_non_negative_integer(replay.get("event_count"))
		or int(replay.get("event_count", -1)) != events.size()
	):
		return _failure(&"REPLAY_EVENT_COUNT_MISMATCH")
	var validation_replay := ReplayRecorderScript.migrate_legacy_v6_time_snapshots(
		replay
	)
	var validation_frames_value: Variant = validation_replay.get("frames")
	var validation_events_value: Variant = validation_replay.get("events")
	if (
		not validation_frames_value is Array
		or not validation_events_value is Array
		or (validation_frames_value as Array).size() != frames.size()
		or (validation_events_value as Array).size() != events.size()
	):
		return _failure(&"REPLAY_MIGRATION_INVALID")
	var validation_frames := validation_frames_value as Array
	var validation_events := validation_events_value as Array

	var last_frame := -1
	var last_positive_token := 0
	var last_token := 0
	var last_generation := 0
	for index: int in range(frames.size()):
		var frame_value: Variant = frames[index]
		if not frame_value is Dictionary:
			return _failure(&"INVALID_REPLAY_FRAME", {"index": index})
		var frame := frame_value as Dictionary
		if not _has_exact_fields(frame, ReplayRecorderScript.FRAME_FIELDS):
			return _failure(&"REPLAY_FRAME_FIELDS_MISMATCH", {"index": index})
		var snapshot_value: Variant = frame.get("snapshot")
		if not snapshot_value is Dictionary:
			return _failure(&"INVALID_REPLAY_SNAPSHOT", {"index": index})
		var snapshot := snapshot_value as Dictionary
		var validation_frame_value: Variant = validation_frames[index]
		if not validation_frame_value is Dictionary:
			return _failure(&"INVALID_REPLAY_FRAME", {"index": index})
		var validation_snapshot_value: Variant = (
			validation_frame_value as Dictionary
		).get("snapshot")
		if not validation_snapshot_value is Dictionary:
			return _failure(&"INVALID_REPLAY_SNAPSHOT", {"index": index})
		var snapshot_validation := ReplayRecorderScript.validate_snapshot(
			validation_snapshot_value as Dictionary,
			expected_identity
		)
		if not bool(snapshot_validation.get("ok", false)):
			var validation_code := snapshot_validation.get("code", &"") as StringName
			if validation_code in [
				&"REPLAY_TIME_SNAPSHOT_INVALID",
				&"REPLAY_TIME_SNAPSHOT_SCHEMA_UNSUPPORTED",
			]:
				var validation_context := (
					snapshot_validation.get("context", {}) as Dictionary
				).duplicate(true)
				validation_context["index"] = index
				return _failure(validation_code, validation_context)
			return _failure(
				&"INVALID_REPLAY_SNAPSHOT",
				{"index": index, "reason": snapshot_validation.get("code")}
			)
		for field: String in ["frame", "token", "generation"]:
			if frame.get(field) != snapshot.get(field):
				return _failure(&"REPLAY_FRAME_SNAPSHOT_MISMATCH", {"index": index, "field": field})
		var frame_number := int(frame["frame"])
		var token := int(frame["token"])
		var generation := int(frame["generation"])
		if frame_number <= last_frame:
			return _failure(&"FRAME_NOT_MONOTONIC", {"index": index})
		if generation < last_generation:
			return _failure(&"GENERATION_NOT_MONOTONIC", {"index": index})
		if token > 0 and token < last_positive_token:
			return _failure(&"TOKEN_NOT_MONOTONIC", {"index": index})
		if token > 0 and last_token == 0 and last_positive_token > 0 and token <= last_positive_token:
			return _failure(&"TOKEN_NOT_MONOTONIC", {"index": index, "reason": "completed_token_reused"})
		if not ReplayRecorderScript._is_sha256(frame.get("digest")):
			return _failure(&"INVALID_FRAME_DIGEST", {"index": index})
		if str(frame["digest"]) != ReplayRecorderScript.frame_digest(frame):
			return _failure(&"FRAME_DIGEST_MISMATCH", {"index": index})
		last_frame = frame_number
		last_generation = generation
		last_token = token
		if token > 0:
			last_positive_token = token

	var last_event_frame := -1
	var last_event_sequence := 0
	var capture_sequences: Dictionary = {}
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if not event_value is Dictionary:
			return _failure(&"INVALID_REPLAY_EVENT", {"index": index})
		var event := event_value as Dictionary
		if not _has_exact_fields(event, ReplayRecorderScript.EVENT_FIELDS):
			return _failure(&"REPLAY_EVENT_FIELDS_MISMATCH", {"index": index})
		var validation_event_value: Variant = validation_events[index]
		if not validation_event_value is Dictionary:
			return _failure(&"INVALID_REPLAY_EVENT", {"index": index})
		var normalized := (validation_event_value as Dictionary).duplicate(true)
		normalized.erase("digest")
		if ReplayRecorderScript.validate_event(normalized, expected_identity).is_empty():
			return _failure(&"INVALID_REPLAY_EVENT", {"index": index})
		var event_frame := int(event["frame"])
		if event_frame < last_event_frame:
			return _failure(&"EVENT_FRAME_NOT_MONOTONIC", {"index": index})
		var event_sequence := int(event.get("sequence", 0))
		var capture_sequence := int(event.get("capture_sequence", 0))
		if event_sequence != last_event_sequence + 1:
			return _failure(&"EVENT_SEQUENCE_NOT_MONOTONIC", {"index": index})
		if capture_sequences.has(capture_sequence):
			return _failure(&"EVENT_CAPTURE_SEQUENCE_DUPLICATE", {"index": index})
		if not ReplayRecorderScript._is_sha256(event.get("digest")):
			return _failure(&"INVALID_EVENT_DIGEST", {"index": index})
		if str(event["digest"]) != ReplayRecorderScript.event_digest(event):
			return _failure(&"EVENT_DIGEST_MISMATCH", {"index": index})
		last_event_frame = event_frame
		last_event_sequence = event_sequence
		capture_sequences[capture_sequence] = true
	for expected_capture_sequence: int in range(1, events.size() + 1):
		if not capture_sequences.has(expected_capture_sequence):
			return _failure(
				&"EVENT_CAPTURE_SEQUENCE_GAP",
				{"capture_sequence": expected_capture_sequence}
			)
	for index: int in range(events.size()):
		if not ReplayRecorderScript.event_state_after_prefix_matches(
			events[index] as Dictionary,
			events
		):
			return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"event_index": index})

	var previous_prefix_count := 0
	for index: int in range(frames.size()):
		var frame := frames[index] as Dictionary
		var snapshot := frame.get("snapshot", {}) as Dictionary
		var prefix := _verified_event_prefix(snapshot, events)
		if not bool(prefix.get("ok", false)):
			return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": index})
		var prefix_events := prefix.get("events", []) as Array
		var prefix_count := int(snapshot.get("event_prefix_count", -1))
		if prefix_count < previous_prefix_count:
			return _failure(&"REPLAY_EVENT_PREFIX_REGRESSION", {"index": index})
		previous_prefix_count = prefix_count
		var prefix_capture_sequences: Dictionary = {}
		for event_value: Variant in prefix_events:
			if (
				not event_value is Dictionary
				or int((event_value as Dictionary).get("frame", -1)) > int(frame.get("frame", -1))
			):
				return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": index})
			prefix_capture_sequences[int((event_value as Dictionary).get("capture_sequence", 0))] = true
		for event_value: Variant in events:
			var event := event_value as Dictionary
			if (
				int(event.get("frame", -1)) < int(frame.get("frame", -1))
				and not prefix_capture_sequences.has(int(event.get("capture_sequence", 0)))
			):
				return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": index})
	var terminal_snapshot := (frames[-1] as Dictionary).get("snapshot", {}) as Dictionary
	if int(terminal_snapshot.get("event_prefix_count", -1)) != events.size():
		return _failure(&"REPLAY_EVENT_PREFIX_MISMATCH", {"index": frames.size() - 1})

	if (
		not ReplayRecorderScript._is_non_negative_integer(replay.get("first_frame"))
		or int(replay.get("first_frame", -1)) != int((frames[0] as Dictionary)["frame"])
	):
		return _failure(&"REPLAY_FIRST_FRAME_MISMATCH")
	if (
		not ReplayRecorderScript._is_non_negative_integer(replay.get("last_frame"))
		or int(replay.get("last_frame", -1)) != int((frames[-1] as Dictionary)["frame"])
	):
		return _failure(&"REPLAY_LAST_FRAME_MISMATCH")
	if not events.is_empty() and (
		int((events[0] as Dictionary).get("frame", -1)) < int(replay.get("first_frame", -1))
		or int((events[-1] as Dictionary).get("frame", -1)) > int(replay.get("last_frame", -1))
	):
		return _failure(&"REPLAY_EVENT_FRAME_RANGE_MISMATCH")
	if not ReplayRecorderScript._is_sha256(replay.get("terminal_digest")):
		return _failure(&"INVALID_TERMINAL_DIGEST")
	if str(replay["terminal_digest"]) != ReplayRecorderScript.terminal_digest(replay):
		return _failure(&"TERMINAL_DIGEST_MISMATCH")
	return _success()


func _validate_full_player_replay(
	replay: Dictionary,
	expected_identity: Dictionary
) -> Dictionary:
	if replay.is_empty() or not ReplayRecorderScript.replay_value_is_safe(replay):
		return _failure(&"FULL_PLAYER_REPLAY_UNSAFE")
	if not _has_exact_fields(replay, ReplayRecorderScript.FULL_PLAYER_REPLAY_FIELDS):
		return _failure(&"FULL_PLAYER_REPLAY_FIELDS_MISMATCH")
	if replay.get("schema_id") != ReplayRecorderScript.FULL_PLAYER_SCHEMA_ID:
		return _failure(&"FULL_PLAYER_REPLAY_SCHEMA_ID_MISMATCH")
	if (
		not ReplayRecorderScript._is_positive_integer(replay.get("schema_version"))
		or int(replay["schema_version"]) != ReplayRecorderScript.FULL_PLAYER_SCHEMA_VERSION
	):
		return _failure(&"FULL_PLAYER_REPLAY_SCHEMA_VERSION_MISMATCH")
	if not ReplayRecorderScript._is_non_negative_integer(replay.get("seed")):
		return _failure(&"FULL_PLAYER_REPLAY_SEED_INVALID")
	var identity_value: Variant = replay.get("identity")
	if not identity_value is Dictionary:
		return _failure(&"FULL_PLAYER_REPLAY_IDENTITY_INVALID")
	var identity := ReplayRecorderScript.validate_full_player_identity(
		identity_value as Dictionary
	)
	if identity.is_empty() or identity != expected_identity:
		return _failure(&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH")
	if (
		not ReplayRecorderScript._is_sha256(replay.get("identity_digest"))
		or str(replay["identity_digest"])
			!= ReplayRecorderScript.value_digest(identity)
	):
		return _failure(&"FULL_PLAYER_REPLAY_IDENTITY_DIGEST_MISMATCH")
	var frames_value: Variant = replay.get("frames")
	if not frames_value is Array or (frames_value as Array).is_empty():
		return _failure(&"FULL_PLAYER_REPLAY_FRAMES_INVALID")
	var frames := frames_value as Array
	if (
		not ReplayRecorderScript._is_positive_integer(replay.get("frame_count"))
		or int(replay["frame_count"]) != frames.size()
	):
		return _failure(&"FULL_PLAYER_REPLAY_FRAME_COUNT_MISMATCH")
	var previous_frame := -1
	var previous_snapshot: Dictionary = {}
	for index: int in range(frames.size()):
		var frame_value: Variant = frames[index]
		if not frame_value is Dictionary:
			return _failure(&"FULL_PLAYER_REPLAY_FRAME_INVALID", {"index": index})
		var entry := frame_value as Dictionary
		if not _has_exact_fields(entry, ReplayRecorderScript.FULL_PLAYER_FRAME_FIELDS):
			return _failure(&"FULL_PLAYER_REPLAY_FRAME_FIELDS_MISMATCH", {"index": index})
		if (
			not ReplayRecorderScript._is_positive_integer(entry.get("schema_version"))
			or int(entry["schema_version"])
				!= ReplayRecorderScript.FULL_PLAYER_FRAME_SCHEMA_VERSION
			or not ReplayRecorderScript._is_non_negative_integer(entry.get("frame"))
		):
			return _failure(&"FULL_PLAYER_REPLAY_FRAME_INVALID", {"index": index})
		var frame := int(entry["frame"])
		if previous_frame >= 0 and frame != previous_frame + 1:
			return _failure(&"FULL_PLAYER_FRAME_GAP", {
				"index": index,
				"frame": frame,
				"expected": previous_frame + 1,
			})
		var intents_value: Variant = entry.get("frame_intents")
		if (
			not intents_value is Dictionary
			or not ReplayRecorderScript.validate_full_player_frame_intents(
				intents_value as Dictionary
			)
		):
			return _failure(&"FULL_PLAYER_FRAME_INTENTS_INVALID", {"index": index})
		var meta := (intents_value as Dictionary).get("meta", {}) as Dictionary
		for frame_key: String in ["frame", "target_frame"]:
			if meta.has(frame_key) and int(meta[frame_key]) != frame:
				return _failure(&"FULL_PLAYER_FRAME_INTENTS_INVALID", {
					"index": index,
					"field": frame_key,
				})
		var snapshot_value: Variant = entry.get("snapshot")
		if not snapshot_value is Dictionary:
			return _failure(&"FULL_PLAYER_REPLAY_SNAPSHOT_INVALID", {"index": index})
		var snapshot := snapshot_value as Dictionary
		var snapshot_validation := ReplayRecorderScript.validate_full_player_snapshot(
			snapshot,
			expected_identity
		)
		if not bool(snapshot_validation.get("ok", false)):
			return _failure(
				snapshot_validation.get("code", &"FULL_PLAYER_REPLAY_SNAPSHOT_INVALID") as StringName,
				{"index": index}
			)
		if int(snapshot.get("frame", -1)) != frame:
			return _failure(&"FULL_PLAYER_REPLAY_FRAME_SNAPSHOT_MISMATCH", {"index": index})
		var facts_value: Variant = entry.get("verification_facts")
		if not facts_value is Array or (facts_value as Array).size() > 1:
			return _failure(&"FULL_PLAYER_VERIFICATION_FACT_INVALID", {"index": index})
		for fact_value: Variant in facts_value as Array:
			if (
				not fact_value is Dictionary
				or not ReplayRecorderScript.validate_full_player_time_skill_fact(
					fact_value as Dictionary,
					snapshot,
					expected_identity,
					intents_value as Dictionary,
					previous_snapshot
				)
			):
				return _failure(&"FULL_PLAYER_VERIFICATION_FACT_INVALID", {"index": index})
		if (
			not ReplayRecorderScript._is_sha256(entry.get("digest"))
			or str(entry["digest"])
				!= ReplayRecorderScript.full_player_frame_digest(entry)
		):
			return _failure(&"FULL_PLAYER_FRAME_DIGEST_MISMATCH", {"index": index})
		previous_frame = frame
		previous_snapshot = snapshot.duplicate(true)
	if (
		not ReplayRecorderScript._is_non_negative_integer(replay.get("first_frame"))
		or int(replay["first_frame"]) != int((frames[0] as Dictionary)["frame"])
	):
		return _failure(&"FULL_PLAYER_REPLAY_FIRST_FRAME_MISMATCH")
	if (
		not ReplayRecorderScript._is_non_negative_integer(replay.get("last_frame"))
		or int(replay["last_frame"]) != int((frames[-1] as Dictionary)["frame"])
	):
		return _failure(&"FULL_PLAYER_REPLAY_LAST_FRAME_MISMATCH")
	var terminal_snapshot := (
		(frames[-1] as Dictionary).get("snapshot", {}) as Dictionary
	)
	if (
		not ReplayRecorderScript._is_sha256(replay.get("terminal_snapshot_digest"))
		or str(replay["terminal_snapshot_digest"])
			!= ReplayRecorderScript.value_digest(terminal_snapshot)
	):
		return _failure(&"FULL_PLAYER_REPLAY_TERMINAL_SNAPSHOT_DIGEST_MISMATCH")
	if (
		not ReplayRecorderScript._is_sha256(replay.get("terminal_digest"))
		or str(replay["terminal_digest"])
			!= ReplayRecorderScript.full_player_terminal_digest(replay)
	):
		return _failure(&"FULL_PLAYER_REPLAY_TERMINAL_DIGEST_MISMATCH")
	return _success()


func _verified_event_prefix(snapshot: Dictionary, events_value: Variant = null) -> Dictionary:
	if (
		typeof(snapshot.get("event_prefix_count")) != TYPE_INT
		or int(snapshot["event_prefix_count"]) < 0
		or not ReplayRecorderScript._is_sha256(snapshot.get("event_prefix_root"))
	):
		return {"ok": false}
	var events: Array = (
		_replay.get("events", []) as Array
		if events_value == null
		else events_value as Array
	)
	var count := int(snapshot["event_prefix_count"])
	var ordered := _events_in_capture_order(events)
	if count > ordered.size():
		return {"ok": false}
	var prefix: Array[Dictionary] = []
	for index: int in range(count):
		var normalized := ordered[index].duplicate(true)
		normalized.erase("digest")
		prefix.append(normalized)
	if str(snapshot["event_prefix_root"]) != ReplayRecorderScript.event_prefix_root(prefix, count):
		return {"ok": false}
	return {"ok": true, "events": prefix}


func _events_in_capture_order(events: Array) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			ordered.append((event_value as Dictionary).duplicate(true))
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("capture_sequence", 0)) < int(right.get("capture_sequence", 0))
	)
	return ordered


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
