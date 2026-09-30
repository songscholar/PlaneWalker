extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const PROFILE_IDS: Array[String] = [
	"sword_launch_v1",
	"bow_launch_v1",
	"gun_launch_v1",
	"staff_launch_v1",
	"gauntlets_launch_v1",
]
const REAL_RUNTIME_CASES: Array[Dictionary] = [
	{"weapon_id": "sword", "profile_id": "sword_launch_v1", "milestone": "LAUNCH", "action_id": "attack", "semantic_action": "weapon_primary", "expected_hold": true},
	{"weapon_id": "bow", "profile_id": "bow_launch_v1", "milestone": "LAUNCH", "action_id": "weapon_primary", "semantic_action": "weapon_primary", "expected_hold": true},
	{"weapon_id": "gun", "profile_id": "gun_launch_v1", "milestone": "LAUNCH", "action_id": "weapon_primary", "semantic_action": "weapon_primary", "expected_hold": true},
	{"weapon_id": "staff", "profile_id": "staff_launch_v1", "milestone": "LAUNCH", "action_id": "weapon_skill", "semantic_action": "weapon_skill", "expected_hold": false},
	{"weapon_id": "gauntlets", "profile_id": "gauntlets_launch_v1", "milestone": "LAUNCH", "action_id": "weapon_skill", "semantic_action": "weapon_skill", "expected_hold": false},
]


class CheckpointDriftTarget extends RefCounted:
	var snapshots_by_frame: Dictionary = {}
	var current: Dictionary = {}
	var drift_frame: int = -1

	func configure(snapshots: Array[Dictionary], next_drift_frame: int) -> void:
		snapshots_by_frame.clear()
		for snapshot: Dictionary in snapshots:
			snapshots_by_frame[int(snapshot.get("frame", -1))] = snapshot.duplicate(true)
		drift_frame = next_drift_frame

	func restore_weapon_replay_snapshot(snapshot: Dictionary) -> bool:
		current = snapshot.duplicate(true)
		return true

	func weapon_replay_snapshot() -> Dictionary:
		return current.duplicate(true)

	func apply_weapon_replay_event(_event: Dictionary) -> bool:
		return true

	func advance_action_frame() -> void:
		var next_frame := int(current.get("frame", -1)) + 1
		if not snapshots_by_frame.has(next_frame):
			return
		current = (snapshots_by_frame[next_frame] as Dictionary).duplicate(true)
		if next_frame == drift_frame:
			current["runtime"]["state"]["value"] = 999


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var profiles := _load_profiles(suite)
	_test_five_weapon_round_trip(suite, profiles)
	_test_profile_identity_and_digest(suite, profiles)
	_test_corruption_and_incompatibility_fail_closed(suite, profiles)
	_test_token_and_generation_monotonicity(suite, profiles)
	_test_loaded_replay_monotonicity(suite, profiles)
	_test_reset_has_no_state_leak(suite, profiles)
	_test_terminal_summary_is_deterministic(suite, profiles)
	_test_native_variant_json_codec_round_trip(suite, profiles)
	_test_event_stream_validation(suite, profiles)
	_test_external_fact_event_validation(suite, profiles)
	_test_recorder_output_contracts(suite, profiles)
	_test_capture_prefix_root_is_canonical(suite)
	_test_event_prefix_binding(suite, profiles)
	_test_replay_to_terminal_validates_each_checkpoint(suite, profiles)
	await _test_restore_truncates_future_captured_events(suite, profiles)
	await _test_real_five_weapon_runtime_round_trip_and_restore(suite, profiles)
	suite.finish(get_tree())


func _test_five_weapon_round_trip(suite, profiles: Dictionary) -> void:
	suite.assert_equal(ReplayRecorderScript.SCHEMA_VERSION, 6, "event-prefix binding uses replay schema v6")
	suite.assert_equal(ReplayRecorderScript.SNAPSHOT_SCHEMA_VERSION, 3, "event-prefix binding uses snapshot schema v3")
	for profile_id: String in PROFILE_IDS:
		var profile: Dictionary = profiles.get(profile_id, {})
		if profile.is_empty():
			continue
		var recorder = ReplayRecorderScript.new()
		var started: Dictionary = recorder.start_recording(profile, 4242)
		suite.assert_true(bool(started.get("ok", false)), "%s replay starts: %s" % [profile_id, str(started)])
		var expected_snapshots: Array[Dictionary] = [
			_snapshot(profile, 10, 1, 1, {"state": "active", "value": 3}),
			_snapshot(profile, 11, 0, 1, {"state": "ready", "value": 3}),
			_snapshot(profile, 12, 2, 2, {"state": "active", "value": 7}),
		]
		for expected: Dictionary in expected_snapshots:
			var recorded: Dictionary = recorder.record_snapshot(expected)
			suite.assert_true(
				bool(recorded.get("ok", false)),
				"%s records frame %d" % [profile_id, int(expected.get("frame", -1))]
			)
		var finished: Dictionary = recorder.finish_recording()
		suite.assert_true(bool(finished.get("ok", false)), "%s replay finishes: %s" % [profile_id, str(finished)])
		var replay: Dictionary = finished.get("replay", {})
		suite.assert_equal(replay.get("schema_id"), ReplayRecorderScript.SCHEMA_ID, "%s schema id" % profile_id)
		suite.assert_equal(replay.get("schema_version"), ReplayRecorderScript.SCHEMA_VERSION, "%s schema version" % profile_id)
		suite.assert_equal(replay.get("profile_id"), profile_id, "%s profile id" % profile_id)
		suite.assert_equal(replay.get("profile_version"), 1, "%s profile version" % profile_id)
		suite.assert_equal(str(replay.get("profile_digest", "")).length(), 64, "%s profile digest" % profile_id)

		var encoded: Dictionary = ReplayRecorderScript.encode_replay_json(replay)
		suite.assert_true(bool(encoded.get("ok", false)), "%s replay encodes with the native Variant JSON codec" % profile_id)
		var player = ReplayPlayerScript.new()
		var loaded: Dictionary = player.load_replay_json(str(encoded.get("json", "")), profile)
		suite.assert_true(bool(loaded.get("ok", false)), "%s replay loads: %s" % [profile_id, str(loaded)])
		suite.assert_equal(player.frame_count(), expected_snapshots.size(), "%s frame count round-trips" % profile_id)
		for index: int in range(expected_snapshots.size()):
			suite.assert_equal(
				ReplayRecorderScript.value_digest(player.frame_at(index).get("snapshot", {})),
				ReplayRecorderScript.value_digest(expected_snapshots[index]),
				"%s frame %d snapshot round-trips" % [profile_id, index]
			)


func _test_profile_identity_and_digest(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("gun_launch_v1", {})
	if profile.is_empty():
		return
	var reordered := _reverse_dictionary(profile)
	var digest := ReplayRecorderScript.profile_digest(profile)
	suite.assert_equal(digest.length(), 64, "profile digest is SHA-256 hex")
	suite.assert_equal(
		ReplayRecorderScript.profile_digest(reordered),
		digest,
		"profile digest ignores Dictionary insertion order"
	)
	var integer_version := profile.duplicate(true)
	integer_version["profile_version"] = int(profile.get("profile_version", 0))
	suite.assert_equal(
		ReplayRecorderScript.profile_digest(integer_version),
		digest,
		"profile digest normalizes integer-valued JSON numbers"
	)
	var recorder = ReplayRecorderScript.new()
	var started: Dictionary = recorder.start_recording(profile, 7)
	suite.assert_true(bool(started.get("ok", false)), "identity fixture starts: %s" % str(started))
	var wrong_identity := _snapshot(profile, 1, 1, 1, {})
	wrong_identity["runtime"]["profile_id"] = "forged_profile"
	suite.assert_true(
		not bool(recorder.record_snapshot(wrong_identity).get("ok", false)),
		"snapshot profile identity mismatch fails closed"
	)
	suite.assert_equal(recorder.recorded_frame_count(), 0, "rejected identity appends no frame")
	var missing_version := _snapshot(profile, 1, 1, 1, {})
	missing_version["runtime"].erase("profile_version")
	suite.assert_true(
		not bool(recorder.record_snapshot(missing_version).get("ok", false)),
		"snapshot missing profile version fails closed"
	)
	var legacy_snapshot := _snapshot(profile, 1, 1, 1, {})
	legacy_snapshot["schema_version"] = ReplayRecorderScript.SNAPSHOT_SCHEMA_VERSION - 1
	var legacy_result: Dictionary = recorder.record_snapshot(legacy_snapshot)
	suite.assert_true(not bool(legacy_result.get("ok", false)), "legacy frame snapshot schema fails closed")
	suite.assert_equal(
		legacy_result.get("code"),
		&"SNAPSHOT_SCHEMA_MISMATCH",
		"legacy frame snapshot uses the stable schema refusal code"
	)


func _test_corruption_and_incompatibility_fail_closed(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("staff_launch_v1", {})
	if profile.is_empty():
		return
	var replay := _build_replay(profile, [
		_snapshot(profile, 20, 4, 8, {"mana": 80, "element": "fire"}),
		_snapshot(profile, 21, 4, 8, {"mana": 80, "element": "fire"}),
	])
	if replay.is_empty():
		suite.assert_true(false, "corruption fixture replay builds")
		return
	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, profile).get("ok", false)), "valid corruption fixture loads")

	var corrupt := replay.duplicate(true)
	corrupt["frames"][0]["snapshot"]["runtime"]["state"]["mana"] = 999
	suite.assert_true(not bool(player.load_replay(corrupt, profile).get("ok", false)), "corrupt frame digest fails closed")
	suite.assert_true(not player.is_loaded(), "failed reload clears the previously loaded replay")
	suite.assert_equal(player.frame_count(), 0, "failed reload exposes no stale frames")

	var missing := replay.duplicate(true)
	missing.erase("profile_digest")
	suite.assert_true(not bool(player.load_replay(missing, profile).get("ok", false)), "missing required replay field fails closed")
	suite.assert_true(not player.is_loaded(), "missing-field load leaves player empty")

	var wrong_schema := replay.duplicate(true)
	wrong_schema["schema_version"] = ReplayRecorderScript.SCHEMA_VERSION + 1
	suite.assert_true(not bool(player.load_replay(wrong_schema, profile).get("ok", false)), "unknown replay schema version fails closed")
	var legacy_schema := replay.duplicate(true)
	legacy_schema["schema_version"] = ReplayRecorderScript.SCHEMA_VERSION - 1
	var legacy_schema_result: Dictionary = player.load_replay(legacy_schema, profile)
	suite.assert_true(not bool(legacy_schema_result.get("ok", false)), "legacy v5 replay schema version fails closed")
	suite.assert_equal(
		legacy_schema_result.get("code"),
		&"REPLAY_SCHEMA_VERSION_MISMATCH",
		"legacy v5 replay envelope uses the stable schema refusal code"
	)

	var wrong_profile_version := profile.duplicate(true)
	wrong_profile_version["profile_version"] = int(profile.get("profile_version", 0)) + 1
	suite.assert_true(
		not bool(player.load_replay(replay, wrong_profile_version).get("ok", false)),
		"expected profile version mismatch fails closed"
	)

	var wrong_profile_digest := profile.duplicate(true)
	wrong_profile_digest["tags"] = ["locally_modified"]
	suite.assert_true(
		not bool(player.load_replay(replay, wrong_profile_digest).get("ok", false)),
		"expected profile digest mismatch fails closed"
	)


func _test_token_and_generation_monotonicity(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("gauntlets_launch_v1", {})
	if profile.is_empty():
		return
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 99)
	suite.assert_true(
		bool(recorder.record_snapshot(_snapshot(profile, 1, 2, 4, {})).get("ok", false)),
		"monotonic fixture records first action"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(_snapshot(profile, 2, 0, 4, {})).get("ok", false)),
		"idle token zero does not lower the committed token floor"
	)
	suite.assert_true(
		not bool(recorder.record_snapshot(_snapshot(profile, 3, 2, 4, {})).get("ok", false)),
		"a completed token cannot be resurrected after READY"
	)
	suite.assert_true(
		not bool(recorder.record_snapshot(_snapshot(profile, 3, 1, 4, {})).get("ok", false)),
		"positive token regression fails closed"
	)
	suite.assert_true(
		not bool(recorder.record_snapshot(_snapshot(profile, 3, 3, 3, {})).get("ok", false)),
		"generation regression fails closed"
	)
	suite.assert_equal(recorder.recorded_frame_count(), 2, "monotonicity failures append no frames")
	suite.assert_true(
		bool(recorder.record_snapshot(_snapshot(profile, 3, 3, 5, {})).get("ok", false)),
		"greater token and generation remain recordable after rejection"
	)


func _test_loaded_replay_monotonicity(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("gauntlets_launch_v1", {})
	if profile.is_empty():
		return
	var replay := _build_replay(profile, [
		_snapshot(profile, 10, 2, 4, {"combo": 4}),
		_snapshot(profile, 11, 3, 5, {"combo": 5}),
	])
	if replay.is_empty():
		suite.assert_true(false, "loaded monotonicity fixture replay builds")
		return
	var player = ReplayPlayerScript.new()

	var token_regression := replay.duplicate(true)
	token_regression["frames"][1]["token"] = 1
	token_regression["frames"][1]["snapshot"]["token"] = 1
	_rehash_replay(token_regression)
	var token_result: Dictionary = player.load_replay(token_regression, profile)
	suite.assert_true(not bool(token_result.get("ok", false)), "loaded replay rejects positive token regression")
	suite.assert_equal(token_result.get("code"), &"TOKEN_NOT_MONOTONIC", "loaded token regression has stable refusal code")
	suite.assert_true(not player.is_loaded(), "token regression leaves player empty")

	var token_resurrection := _build_replay(profile, [
		_snapshot(profile, 20, 2, 4, {"combo": 4}),
		_snapshot(profile, 21, 0, 4, {"combo": 4}),
		_snapshot(profile, 22, 3, 5, {"combo": 5}),
	])
	token_resurrection["frames"][2]["token"] = 2
	token_resurrection["frames"][2]["snapshot"]["token"] = 2
	_rehash_replay(token_resurrection)
	var resurrection_result: Dictionary = player.load_replay(token_resurrection, profile)
	suite.assert_true(not bool(resurrection_result.get("ok", false)), "loaded replay rejects token 2 to READY to token 2 resurrection")
	suite.assert_equal(resurrection_result.get("code"), &"TOKEN_NOT_MONOTONIC", "token resurrection uses the stable monotonic refusal code")

	var generation_regression := replay.duplicate(true)
	generation_regression["frames"][1]["generation"] = 3
	generation_regression["frames"][1]["snapshot"]["generation"] = 3
	_rehash_replay(generation_regression)
	var generation_result: Dictionary = player.load_replay(generation_regression, profile)
	suite.assert_true(not bool(generation_result.get("ok", false)), "loaded replay rejects generation regression")
	suite.assert_equal(
		generation_result.get("code"),
		&"GENERATION_NOT_MONOTONIC",
		"loaded generation regression has stable refusal code"
	)
	suite.assert_true(not player.is_loaded(), "generation regression leaves player empty")


func _test_reset_has_no_state_leak(suite, profiles: Dictionary) -> void:
	var first_profile: Dictionary = profiles.get("sword_launch_v1", {})
	var second_profile: Dictionary = profiles.get("bow_launch_v1", {})
	if first_profile.is_empty() or second_profile.is_empty():
		return
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(first_profile, 1)
	recorder.record_snapshot(_snapshot(first_profile, 1, 1, 1, {"combo": 2}))
	recorder.reset()
	suite.assert_true(not recorder.is_recording(), "recorder reset clears recording flag")
	suite.assert_equal(recorder.recorded_frame_count(), 0, "recorder reset clears frames")
	suite.assert_equal(recorder.recording_identity(), {}, "recorder reset clears profile identity")
	suite.assert_true(not bool(recorder.finish_recording().get("ok", false)), "recorder reset clears finished replay cache")
	suite.assert_true(bool(recorder.start_recording(second_profile, 2).get("ok", false)), "recorder restarts after reset")
	recorder.record_snapshot(_snapshot(second_profile, 1, 1, 1, {"charge": 48}))
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	suite.assert_equal(replay.get("profile_id"), "bow_launch_v1", "restarted recorder retains only new identity")
	suite.assert_equal(replay.get("frame_count"), 1, "restarted recorder retains only new frames")

	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, second_profile).get("ok", false)), "reset player fixture loads")
	player.reset()
	suite.assert_true(not player.is_loaded(), "player reset clears loaded flag")
	suite.assert_equal(player.frame_count(), 0, "player reset clears frames")
	suite.assert_equal(player.summary(), {}, "player reset clears summary")
	suite.assert_equal(player.current_frame(), {}, "player reset clears cursor state")


func _test_terminal_summary_is_deterministic(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("gun_launch_v1", {})
	if profile.is_empty():
		return
	var snapshots: Array[Dictionary] = [
		_snapshot(profile, 100, 5, 7, {"ammo": 6, "reload": "idle"}),
		_snapshot(profile, 101, 5, 7, {"reload": "idle", "ammo": 6}),
		_snapshot(profile, 102, 6, 8, {"ammo": 5, "reload": "idle"}),
	]
	var first := _build_replay(profile, snapshots)
	var second := _build_replay(profile, snapshots)
	suite.assert_equal(
		first.get("terminal_digest"),
		second.get("terminal_digest"),
		"identical replay inputs produce the same terminal digest"
	)
	var first_player = ReplayPlayerScript.new()
	var second_player = ReplayPlayerScript.new()
	first_player.load_replay(first, profile)
	second_player.load_replay(second, profile)
	suite.assert_equal(first_player.summary(), second_player.summary(), "terminal summaries are deterministic")
	var changed_snapshots := snapshots.duplicate(true)
	changed_snapshots[2]["runtime"]["state"]["ammo"] = 4
	var changed := _build_replay(profile, changed_snapshots)
	suite.assert_true(
		changed.get("terminal_digest") != first.get("terminal_digest"),
		"terminal digest changes when authoritative state changes"
	)


func _test_native_variant_json_codec_round_trip(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("bow_launch_v1", {})
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 8080)
	var snapshot := _snapshot(profile, 1, 1, 1, {
		"aim_direction": Vector2(0.25, -0.75),
		"target_point": Vector2(144.5, 72.25),
		"weapon_id": &"bow",
	})
	suite.assert_true(bool(recorder.record_snapshot(snapshot).get("ok", false)), "native Variant codec fixture records")
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	var encoded: Dictionary = ReplayRecorderScript.encode_replay_json(replay)
	suite.assert_true(bool(encoded.get("ok", false)), "ReplayRecorder encodes a native Variant replay into JSON")
	var player = ReplayPlayerScript.new()
	var loaded: Dictionary = player.load_replay_json(str(encoded.get("json", "")), profile)
	suite.assert_true(bool(loaded.get("ok", false)), "ReplayPlayer decodes and loads the native Variant JSON envelope")
	var restored_state: Dictionary = player.frame_at(0).get("snapshot", {}).get("runtime", {}).get("state", {})
	suite.assert_equal(restored_state.get("aim_direction"), Vector2(0.25, -0.75), "Vector2 aim direction survives JSON round-trip exactly")
	suite.assert_equal(restored_state.get("target_point"), Vector2(144.5, 72.25), "Vector2 target point survives JSON round-trip exactly")
	suite.assert_equal(typeof(restored_state.get("weapon_id")), TYPE_STRING_NAME, "StringName survives JSON round-trip as its native Variant type")
	var tampered_envelope: Dictionary = JSON.parse_string(str(encoded.get("json", "")))
	tampered_envelope["payload"] = str(tampered_envelope["payload"]) + "A"
	var tampered_result: Dictionary = player.load_replay_json(JSON.stringify(tampered_envelope), profile)
	suite.assert_true(not bool(tampered_result.get("ok", false)), "native Variant JSON payload corruption fails closed")
	suite.assert_equal(tampered_result.get("code"), &"REPLAY_CODEC_DIGEST_MISMATCH", "codec corruption has a stable refusal code")
	suite.assert_true(not player.is_loaded(), "failed native Variant reload clears the previously loaded replay")


func _test_event_stream_validation(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("sword_launch_v1", {})
	if profile.is_empty():
		return
	var pressed_event := {
		"schema_version": ReplayRecorderScript.EVENT_SCHEMA_VERSION,
		"frame": 1,
		"sequence": 1,
		"capture_sequence": 1,
		"event_type": "weapon_intent",
		"payload": {
			"semantic_action": "weapon_primary",
			"edge": "pressed",
			"held_frames": 0,
			"context": {"aim_direction": Vector2.RIGHT},
		},
	}
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 9001)
	recorder.record_snapshot(_snapshot(profile, 0, 0, 1, {"state": "ready"}))
	recorder.record_snapshot(_snapshot_with_event_prefix(
		_snapshot(profile, 2, 1, 1, {"state": "active"}),
		[pressed_event],
		1
	))
	suite.assert_true(bool(recorder.record_event(pressed_event).get("ok", false)), "normalized replay event records")
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, profile).get("ok", false)), "valid normalized event stream loads")

	var corrupted := replay.duplicate(true)
	corrupted["events"][0]["payload"]["context"]["aim_direction"] = Vector2.LEFT
	corrupted["terminal_digest"] = ReplayRecorderScript.terminal_digest(corrupted)
	var corrupted_result: Dictionary = player.load_replay(corrupted, profile)
	suite.assert_true(not bool(corrupted_result.get("ok", false)), "corrupted event digest fails closed")
	suite.assert_equal(corrupted_result.get("code"), &"EVENT_DIGEST_MISMATCH", "corrupted event uses the stable refusal code")

	var legacy_event_schema := replay.duplicate(true)
	legacy_event_schema["events"][0]["schema_version"] = 2
	_rehash_replay(legacy_event_schema)
	var legacy_event_schema_result: Dictionary = player.load_replay(legacy_event_schema, profile)
	suite.assert_true(not bool(legacy_event_schema_result.get("ok", false)), "legacy v2 replay event schema fails closed")
	suite.assert_equal(
		legacy_event_schema_result.get("code"),
		&"INVALID_REPLAY_EVENT",
		"legacy v2 replay event uses the stable schema refusal code"
	)

	var unknown := replay.duplicate(true)
	unknown["events"][0]["payload"]["semantic_action"] = "weapon_unknown"
	_rehash_replay(unknown)
	var unknown_result: Dictionary = player.load_replay(unknown, profile)
	suite.assert_true(not bool(unknown_result.get("ok", false)), "unknown replay event fails closed")
	suite.assert_equal(unknown_result.get("code"), &"INVALID_REPLAY_EVENT", "unknown event uses the stable refusal code")

	var capture_gap := replay.duplicate(true)
	capture_gap["events"][0]["capture_sequence"] = 3
	_rehash_replay(capture_gap)
	var capture_gap_result: Dictionary = player.load_replay(capture_gap, profile)
	suite.assert_true(not bool(capture_gap_result.get("ok", false)), "rehashed replay rejects a capture-sequence gap")
	suite.assert_equal(capture_gap_result.get("code"), &"EVENT_CAPTURE_SEQUENCE_GAP", "capture-sequence gap has a stable refusal code")


func _test_external_fact_event_validation(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("sword_launch_v1", {})
	if profile.is_empty():
		return
	var fact_event := {
		"schema_version": ReplayRecorderScript.EVENT_SCHEMA_VERSION,
		"frame": 1,
		"sequence": 1,
		"capture_sequence": 1,
		"event_type": "external_fact",
		"payload": {
			"fact_type": "combat_damage",
			"fact_id": "combat_damage:1:1:1",
			"weapon_id": "sword",
			"action_token": 1,
			"action_generation": 1,
			"data": {
				"target_path": "../ReplayTarget",
				"health_path": "HealthComponent",
				"hp_before": 100.0,
				"hp_after": 72.0,
				"resolved_damage": 28.0,
				"target_dead_after": false,
				"state_before_digest": ReplayRecorderScript.value_digest(
					_snapshot(profile, 1, 1, 1, {"state": "active"})
				),
				"state_after": _snapshot(profile, 1, 1, 1, {"state": "active", "hit": true}),
			},
		},
	}
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 9011)
	recorder.record_snapshot(_snapshot(profile, 0, 0, 1, {"state": "ready"}))
	recorder.record_snapshot(_snapshot_with_event_prefix(
		_snapshot(profile, 2, 1, 1, {"state": "active"}),
		[fact_event],
		1
	))
	suite.assert_true(bool(recorder.record_event(fact_event).get("ok", false)), "strict external combat fact records")
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, profile).get("ok", false)), "strict external combat fact loads")

	var forged_nested_prefix := replay.duplicate(true)
	forged_nested_prefix["events"][0]["payload"]["data"]["state_after"]["event_prefix_root"] = "0".repeat(64)
	_rehash_replay(forged_nested_prefix)
	var forged_nested_prefix_result: Dictionary = player.load_replay(
		forged_nested_prefix,
		profile
	)
	suite.assert_true(
		not bool(forged_nested_prefix_result.get("ok", false)),
		"rehashed external fact with a forged nested state_after prefix fails at load"
	)
	suite.assert_equal(
		forged_nested_prefix_result.get("code"),
		&"REPLAY_EVENT_PREFIX_MISMATCH",
		"forged nested event prefix has a stable refusal code"
	)

	var malformed := replay.duplicate(true)
	malformed["events"][0]["payload"]["data"]["resolved_damage"] = -1.0
	_rehash_replay(malformed)
	var malformed_result: Dictionary = player.load_replay(malformed, profile)
	suite.assert_true(not bool(malformed_result.get("ok", false)), "negative resolved damage fails closed at replay load")
	suite.assert_equal(malformed_result.get("code"), &"INVALID_REPLAY_EVENT", "malformed external fact uses stable refusal code")

	var unknown := replay.duplicate(true)
	unknown["events"][0]["payload"]["fact_type"] = "invented_external_fact"
	_rehash_replay(unknown)
	var unknown_result: Dictionary = player.load_replay(unknown, profile)
	suite.assert_true(not bool(unknown_result.get("ok", false)), "unknown external fact type fails closed")
	suite.assert_equal(unknown_result.get("code"), &"INVALID_REPLAY_EVENT", "unknown external fact uses stable refusal code")


func _test_recorder_output_contracts(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("sword_launch_v1", {})
	var wrong_profile: Dictionary = profiles.get("bow_launch_v1", {})
	if profile.is_empty() or wrong_profile.is_empty():
		return

	var fact_event := _combat_damage_event(profile, 1, 1, 1)
	var valid_fact_event := fact_event.duplicate(true)
	var identity_recorder = ReplayRecorderScript.new()
	identity_recorder.start_recording(profile, 9021)
	identity_recorder.record_snapshot(_snapshot(profile, 0, 0, 1, {"state": "ready"}))
	identity_recorder.record_snapshot(_snapshot_with_event_prefix(
		_snapshot(profile, 2, 1, 1, {"state": "active"}),
		[valid_fact_event],
		1
	))
	fact_event["payload"]["data"]["state_after"] = _snapshot(
		wrong_profile,
		1,
		1,
		1,
		{"state": "active", "hit": true}
	)
	var wrong_identity_result: Dictionary = identity_recorder.record_event(fact_event)
	suite.assert_true(
		not bool(wrong_identity_result.get("ok", false)),
		"recorder rejects an external fact whose state_after belongs to another profile"
	)
	suite.assert_equal(
		wrong_identity_result.get("code"),
		&"INVALID_REPLAY_EVENT",
		"wrong-profile state_after uses the stable event refusal code"
	)
	fact_event["payload"]["data"]["state_after"] = _snapshot(
		profile,
		1,
		1,
		1,
		{"state": "active", "hit": true}
	)
	suite.assert_true(
		bool(identity_recorder.record_event(fact_event).get("ok", false)),
		"wrong-profile rejection appends no event and preserves the next event sequence"
	)
	var identity_replay: Dictionary = identity_recorder.finish_recording().get("replay", {})
	var identity_player = ReplayPlayerScript.new()
	suite.assert_true(
		bool(identity_player.load_replay(identity_replay, profile).get("ok", false)),
		"recorder output remains loadable after rejecting a wrong-profile event"
	)
	var forged_state_identity := identity_replay.duplicate(true)
	forged_state_identity["events"][0]["payload"]["data"]["state_after"] = _snapshot(
		wrong_profile,
		1,
		1,
		1,
		{"state": "active", "hit": true}
	)
	_rehash_replay(forged_state_identity)
	var forged_state_result: Dictionary = identity_player.load_replay(
		forged_state_identity,
		profile
	)
	suite.assert_true(
		not bool(forged_state_result.get("ok", false)),
		"ReplayPlayer rejects a rehashed event with wrong-profile state_after"
	)
	suite.assert_equal(
		forged_state_result.get("code"),
		&"INVALID_REPLAY_EVENT",
		"forged state_after identity fails during replay load"
	)
	var forged_weapon_identity := identity_replay.duplicate(true)
	forged_weapon_identity["events"][0]["payload"]["weapon_id"] = str(
		wrong_profile.get("weapon_id", "")
	)
	_rehash_replay(forged_weapon_identity)
	var forged_weapon_result: Dictionary = identity_player.load_replay(
		forged_weapon_identity,
		profile
	)
	suite.assert_true(
		not bool(forged_weapon_result.get("ok", false)),
		"ReplayPlayer rejects a rehashed event with the wrong payload weapon_id"
	)
	suite.assert_equal(
		forged_weapon_result.get("code"),
		&"INVALID_REPLAY_EVENT",
		"forged payload weapon identity fails during replay load"
	)
	var weapon_identity_recorder = ReplayRecorderScript.new()
	weapon_identity_recorder.start_recording(profile, 9023)
	weapon_identity_recorder.record_snapshot(_snapshot(profile, 0, 0, 1, {"state": "ready"}))
	weapon_identity_recorder.record_snapshot(_snapshot(profile, 2, 1, 1, {"state": "active"}))
	var wrong_weapon_event := _combat_damage_event(profile, 1, 1, 1)
	wrong_weapon_event["payload"]["weapon_id"] = str(wrong_profile.get("weapon_id", ""))
	var wrong_weapon_result: Dictionary = weapon_identity_recorder.record_event(wrong_weapon_event)
	suite.assert_true(
		not bool(wrong_weapon_result.get("ok", false)),
		"recorder rejects an external fact whose payload weapon_id belongs to another profile"
	)
	suite.assert_equal(
		wrong_weapon_result.get("code"),
		&"INVALID_REPLAY_EVENT",
		"wrong payload weapon identity uses the stable event refusal code"
	)

	for range_case: Dictionary in [
		{"label": "before the first snapshot", "event_frame": 9},
		{"label": "after the last snapshot", "event_frame": 13},
	]:
		var range_recorder = ReplayRecorderScript.new()
		range_recorder.start_recording(profile, 9022)
		range_recorder.record_snapshot(_snapshot(profile, 10, 0, 1, {"state": "ready"}))
		range_recorder.record_snapshot(_snapshot(profile, 12, 1, 1, {"state": "active"}))
		var out_of_range_event := _intent_event(int(range_case["event_frame"]), 1, 1)
		suite.assert_true(
			bool(range_recorder.record_event(out_of_range_event).get("ok", false)),
			"range fixture records the event before final frame bounds are checked"
		)
		var range_finish: Dictionary = range_recorder.finish_recording()
		suite.assert_true(
			not bool(range_finish.get("ok", false)),
			"recorder refuses an event %s" % str(range_case["label"])
		)
		suite.assert_equal(
			range_finish.get("code"),
			&"REPLAY_EVENT_FRAME_RANGE_MISMATCH",
			"out-of-range event uses the stable recorder refusal code"
		)

	var snapshot_identity := ReplayRecorderScript.profile_identity(profile)
	for integer_case: Dictionary in [
		{"label": "snapshot schema_version", "path": "schema_version", "value": 2.0},
		{"label": "snapshot frame", "path": "frame", "value": 0.0},
		{"label": "snapshot token", "path": "token", "value": 0.0},
		{"label": "snapshot generation", "path": "generation", "value": 1.0},
		{"label": "snapshot profile_version", "path": "profile_version", "value": 1.0},
	]:
		var float_snapshot := _snapshot(profile, 0, 0, 1, {"state": "ready"})
		if str(integer_case["path"]) == "profile_version":
			float_snapshot["profile_id"] = str(profile.get("id", ""))
		float_snapshot[str(integer_case["path"])] = integer_case["value"]
		var snapshot_validation: Dictionary = ReplayRecorderScript.validate_snapshot(
			float_snapshot,
			snapshot_identity
		)
		suite.assert_true(
			not bool(snapshot_validation.get("ok", false)),
			"%s rejects an integer-valued float" % str(integer_case["label"])
		)

	for event_integer_case: Dictionary in [
		{"label": "event frame", "field": "frame"},
		{"label": "event sequence", "field": "sequence"},
		{"label": "event capture_sequence", "field": "capture_sequence"},
	]:
		var float_event := _intent_event(1, 1, 1)
		float_event[str(event_integer_case["field"])] = float(
			float_event[str(event_integer_case["field"])]
		)
		suite.assert_equal(
			ReplayRecorderScript.validate_event(float_event, snapshot_identity),
			{},
			"%s rejects an integer-valued float" % str(event_integer_case["label"])
		)
	var float_held_event := _intent_event(1, 1, 1)
	float_held_event["payload"]["held_frames"] = 0.0
	suite.assert_equal(
		ReplayRecorderScript.validate_event(float_held_event, snapshot_identity),
		{},
		"event held_frames rejects an integer-valued float"
	)


func _test_replay_to_terminal_validates_each_checkpoint(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("sword_launch_v1", {})
	if profile.is_empty():
		return
	var snapshots: Array[Dictionary] = [
		_snapshot(profile, 0, 0, 1, {"state": "ready", "value": 0}),
		_snapshot(profile, 1, 1, 1, {"state": "active", "value": 1}),
		_snapshot(profile, 2, 0, 1, {"state": "ready", "value": 2}),
	]
	var replay := _build_replay(profile, snapshots)
	var replay_player = ReplayPlayerScript.new()
	suite.assert_true(bool(replay_player.load_replay(replay, profile).get("ok", false)), "checkpoint validation fixture loads")
	var target := CheckpointDriftTarget.new()
	target.configure(snapshots, 1)
	var result: Dictionary = replay_player.replay_to_terminal(target, 0)
	suite.assert_true(not bool(result.get("ok", false)), "intermediate checkpoint drift fails even when terminal state would converge")
	suite.assert_equal(result.get("code"), &"REPLAY_CHECKPOINT_MISMATCH", "checkpoint drift has a stable refusal code")


func _test_capture_prefix_root_is_canonical(suite) -> void:
	var capture_one := _intent_event(12, 2, 1)
	var capture_two := _intent_event(12, 1, 2)
	capture_two["payload"]["semantic_action"] = "weapon_secondary"
	var root_in_capture_order := ReplayRecorderScript.event_prefix_root(
		[capture_one, capture_two],
		2
	)
	var root_in_playback_order := ReplayRecorderScript.event_prefix_root(
		[capture_two, capture_one],
		2
	)
	suite.assert_equal(root_in_playback_order, root_in_capture_order, "event-prefix root sorts by capture_sequence, not playback order")
	suite.assert_equal(root_in_capture_order.length(), 64, "event-prefix root is SHA-256")

	var changed_sequence := capture_one.duplicate(true)
	changed_sequence["sequence"] = 99
	suite.assert_equal(
		ReplayRecorderScript.event_prefix_root([changed_sequence], 1),
		ReplayRecorderScript.event_prefix_root([capture_one], 1),
		"derived playback sequence does not affect the capture-prefix root"
	)
	var changed_payload := capture_one.duplicate(true)
	changed_payload["payload"]["edge"] = "released"
	suite.assert_true(
		ReplayRecorderScript.event_prefix_root([changed_payload], 1)
			!= ReplayRecorderScript.event_prefix_root([capture_one], 1),
		"authoritative event payload changes the capture-prefix root"
	)
	suite.assert_equal(
		ReplayRecorderScript.event_prefix_root([], 0),
		ReplayRecorderScript.event_prefix_root([], 0),
		"empty event prefix has one canonical root"
	)


func _test_event_prefix_binding(suite, profiles: Dictionary) -> void:
	var profile: Dictionary = profiles.get("sword_launch_v1", {})
	if profile.is_empty():
		return
	var prefix_event := _intent_event(1, 1, 1)
	var prefix_events: Array[Dictionary] = [prefix_event]
	var snapshots: Array[Dictionary] = [
		_snapshot(profile, 0, 0, 1, {"state": "ready"}),
		_snapshot_with_event_prefix(
			_snapshot(profile, 2, 1, 1, {"state": "active"}),
			prefix_events,
			1
		),
	]
	var recorder = ReplayRecorderScript.new()
	suite.assert_true(bool(recorder.start_recording(profile, 9090).get("ok", false)), "event-prefix fixture starts")
	for snapshot: Dictionary in snapshots:
		suite.assert_true(bool(recorder.record_snapshot(snapshot).get("ok", false)), "event-prefix checkpoint records")
	suite.assert_true(bool(recorder.record_event(prefix_event).get("ok", false)), "event-prefix fixture records its bound event")
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	var replay_player = ReplayPlayerScript.new()
	suite.assert_true(bool(replay_player.load_replay(replay, profile).get("ok", false)), "matching checkpoint event prefix loads")

	var forged_root := replay.duplicate(true)
	forged_root["frames"][1]["snapshot"]["event_prefix_root"] = ReplayRecorderScript.event_prefix_root([], 0)
	_rehash_replay(forged_root)
	var forged_root_result: Dictionary = replay_player.load_replay(forged_root, profile)
	suite.assert_true(not bool(forged_root_result.get("ok", false)), "rehashed checkpoint with a forged event-prefix root fails closed")
	suite.assert_equal(forged_root_result.get("code"), &"REPLAY_EVENT_PREFIX_MISMATCH", "forged event-prefix root has a stable refusal code")

	var forged_count := replay.duplicate(true)
	forged_count["frames"][1]["snapshot"]["event_prefix_count"] = 0
	_rehash_replay(forged_count)
	var forged_count_result: Dictionary = replay_player.load_replay(forged_count, profile)
	suite.assert_true(not bool(forged_count_result.get("ok", false)), "rehashed checkpoint with a forged event-prefix count fails closed")
	suite.assert_equal(forged_count_result.get("code"), &"REPLAY_EVENT_PREFIX_MISMATCH", "forged event-prefix count has a stable refusal code")

	var oversized_count := replay.duplicate(true)
	oversized_count["frames"][1]["snapshot"]["event_prefix_count"] = 2
	_rehash_replay(oversized_count)
	var oversized_count_result: Dictionary = replay_player.load_replay(oversized_count, profile)
	suite.assert_true(not bool(oversized_count_result.get("ok", false)), "checkpoint prefix count cannot exceed the replay event count")
	suite.assert_equal(oversized_count_result.get("code"), &"REPLAY_EVENT_PREFIX_MISMATCH", "oversized prefix count has a stable refusal code")

	var future_event_prefix := replay.duplicate(true)
	future_event_prefix["frames"][0]["snapshot"] = _snapshot_with_event_prefix(
		future_event_prefix["frames"][0]["snapshot"],
		prefix_events,
		1
	)
	_rehash_replay(future_event_prefix)
	var future_event_result: Dictionary = replay_player.load_replay(future_event_prefix, profile)
	suite.assert_true(not bool(future_event_result.get("ok", false)), "checkpoint cannot bind an event captured at a future frame")
	suite.assert_equal(future_event_result.get("code"), &"REPLAY_EVENT_PREFIX_MISMATCH", "future event prefix has a stable refusal code")


func _test_restore_truncates_future_captured_events(suite, profiles: Dictionary) -> void:
	var runtime_case := REAL_RUNTIME_CASES[0]
	var player := await _spawn_runtime_player(suite, runtime_case, profiles)
	if player == null:
		return

	var captured_payload := {
		"semantic_action": "weapon_primary",
		"edge": "pressed",
		"held_frames": 0,
		"context": {},
	}
	suite.assert_equal(
		int(player.call("_append_weapon_replay_event", "weapon_intent", captured_payload)),
		1,
		"capture rollback fixture records event 1"
	)
	var branch_point: Dictionary = player.weapon_replay_snapshot()
	suite.assert_equal(
		int(player.call("_append_weapon_replay_event", "weapon_intent", captured_payload)),
		2,
		"capture rollback fixture records event 2"
	)
	suite.assert_equal(player.weapon_replay_events().size(), 2, "fixture contains two captured events")
	suite.assert_true(
		player.restore_weapon_replay_snapshot(branch_point),
		"restoring a checkpoint whose bound prefix matches the local capture log succeeds"
	)
	suite.assert_equal(
		player.weapon_replay_events().size(),
		1,
		"restoring a capture frontier truncates events from the abandoned recording branch"
	)

	suite.assert_equal(
		int(player.call("_append_weapon_replay_event", "weapon_intent", captured_payload)),
		2,
		"the restored branch assigns the replacement event the next capture id"
	)
	var branched_events: Array[Dictionary] = player.weapon_replay_events()
	suite.assert_equal(branched_events.size(), 2, "replacement branch contains exactly two authoritative events")
	suite.assert_equal(int(branched_events[0].get("capture_sequence", 0)), 1, "branch preserves the first capture id")
	suite.assert_equal(int(branched_events[1].get("capture_sequence", 0)), 2, "replacement action receives the next unique capture id")

	var forged_branch := branch_point.duplicate(true)
	var different_event := branched_events[0].duplicate(true)
	different_event["payload"]["edge"] = "released"
	forged_branch["event_prefix_root"] = ReplayRecorderScript.event_prefix_root([different_event], 1)
	var before_forged_restore := ReplayRecorderScript.value_digest(player.weapon_replay_snapshot())
	var events_before_forged_restore: Array[Dictionary] = player.weapon_replay_events()
	suite.assert_true(
		not player.restore_weapon_replay_snapshot(forged_branch),
		"local restore rejects a checkpoint bound to a different event prefix"
	)
	suite.assert_equal(
		ReplayRecorderScript.value_digest(player.weapon_replay_snapshot()),
		before_forged_restore,
		"event-prefix rejection preserves the authoritative runtime state"
	)
	suite.assert_equal(player.weapon_replay_events(), events_before_forged_restore, "event-prefix rejection preserves the local event log")

	await _free_runtime_player(player)


func _test_real_five_weapon_runtime_round_trip_and_restore(suite, profiles: Dictionary) -> void:
	for runtime_case: Dictionary in REAL_RUNTIME_CASES:
		var source := await _spawn_runtime_player(suite, runtime_case, profiles)
		if source == null:
			continue
		var profile: Dictionary = source.loadout_runtime.weapon_profile_snapshot()
		var recorder = ReplayRecorderScript.new()
		suite.assert_true(bool(recorder.start_recording(profile, 424242).get("ok", false)), "%s real runtime replay starts" % runtime_case["weapon_id"])
		suite.assert_true(source.has_method("weapon_replay_snapshot"), "%s exposes the PlayerController replay snapshot contract" % runtime_case["weapon_id"])
		var checkpoints := _record_real_runtime_checkpoints(suite, source, runtime_case, recorder)
		if checkpoints.size() < 5:
			await _free_runtime_player(source)
			continue
		var source_events: Array[Dictionary] = source.weapon_replay_events()
		for event: Dictionary in source_events:
			var event_recorded: Dictionary = recorder.record_event(event)
			suite.assert_true(bool(event_recorded.get("ok", false)), "%s records normalized replay event: %s" % [runtime_case["weapon_id"], str(event_recorded)])
		var ready_after: Dictionary = checkpoints[-1]
		var replay: Dictionary = recorder.finish_recording().get("replay", {})
		var encoded: Dictionary = ReplayRecorderScript.encode_replay_json(replay)
		suite.assert_true(bool(encoded.get("ok", false)), "%s real replay encodes through the native Variant codec" % runtime_case["weapon_id"])
		for checkpoint_index: int in range(1, checkpoints.size() - 1):
			var checkpoint: Dictionary = checkpoints[checkpoint_index]
			var checkpoint_phase := str(checkpoint.get("phase", ""))
			var replay_player = ReplayPlayerScript.new()
			var loaded: Dictionary = replay_player.load_replay_json(str(encoded.get("json", "")), profile)
			suite.assert_true(bool(loaded.get("ok", false)), "%s %s replay loads successfully" % [runtime_case["weapon_id"], checkpoint_phase])
			var loaded_again: Dictionary = replay_player.load_replay_json(str(encoded.get("json", "")), profile)
			suite.assert_true(bool(loaded_again.get("ok", false)), "%s %s replay reloads successfully" % [runtime_case["weapon_id"], checkpoint_phase])
			var target := await _spawn_runtime_player(suite, runtime_case, profiles)
			if target == null:
				continue
			suite.assert_true(bool(replay_player.restore_frame(target, 0).get("ok", false)), "%s %s restores the initial READY frame" % [runtime_case["weapon_id"], checkpoint_phase])
			var restored: Dictionary = replay_player.restore_frame(target, checkpoint_index)
			suite.assert_true(bool(restored.get("ok", false)), "%s restores %s checkpoint: %s" % [runtime_case["weapon_id"], checkpoint_phase, str(restored)])
			suite.assert_equal(
				target.weapon_replay_events().size(),
				int(checkpoint.get("event_prefix_count", -1)),
				"%s %s ReplayPlayer installs the verified checkpoint event prefix" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			suite.assert_equal(
				ReplayRecorderScript.value_digest(target.weapon_replay_snapshot()),
				ReplayRecorderScript.value_digest(checkpoint),
				"%s %s authoritative digest matches after restore" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			suite.assert_equal(
				target.time_manager.resource_state(&"time_energy"),
				(checkpoint.get("time_manager_state", {}) as Dictionary).get("time_energy_state", {}),
				"%s %s restores exact time-energy current, maximum, and revision" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			suite.assert_equal(
				ReplayRecorderScript.value_digest(_replay_fact_projection(target.weapon_replay_snapshot())),
				ReplayRecorderScript.value_digest(_replay_fact_projection(checkpoint)),
				"%s %s payload, reward, and resource facts match" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			var facts_before_repeat := ReplayRecorderScript.value_digest(_replay_fact_projection(target.weapon_replay_snapshot()))
			suite.assert_true(bool(replay_player.restore_frame(target, checkpoint_index).get("ok", false)), "%s %s repeat restore is idempotent" % [runtime_case["weapon_id"], checkpoint_phase])
			suite.assert_equal(
				ReplayRecorderScript.value_digest(_replay_fact_projection(target.weapon_replay_snapshot())),
				facts_before_repeat,
				"%s %s repeat restore emits no duplicate authoritative facts" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			var invalid := checkpoint.duplicate(true)
			invalid["player_weapon_state"]["next_token_floor"] = 0
			var before_invalid := ReplayRecorderScript.value_digest(target.weapon_replay_snapshot())
			suite.assert_true(not target.restore_weapon_replay_snapshot(invalid), "%s %s invalid player state fails closed" % [runtime_case["weapon_id"], checkpoint_phase])
			suite.assert_equal(ReplayRecorderScript.value_digest(target.weapon_replay_snapshot()), before_invalid, "%s %s invalid restore is atomic" % [runtime_case["weapon_id"], checkpoint_phase])
			_assert_strict_player_replay_state_validation(
				suite,
				target,
				checkpoint,
				str(runtime_case["weapon_id"]),
				"%s %s" % [runtime_case["weapon_id"], checkpoint_phase]
			)

			var replayed_terminal: Dictionary = replay_player.replay_to_terminal(target, checkpoint_index)
			suite.assert_true(bool(replayed_terminal.get("ok", false)), "%s %s ReplayPlayer reaches READY: %s" % [runtime_case["weapon_id"], checkpoint_phase, str(replayed_terminal)])
			suite.assert_equal(
				ReplayRecorderScript.value_digest(target.weapon_replay_snapshot()),
				ReplayRecorderScript.value_digest(ready_after),
				"%s %s continuation reaches the recorded terminal digest" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			suite.assert_equal(
				ReplayRecorderScript.value_digest(_replay_fact_projection(target.weapon_replay_snapshot())),
				ReplayRecorderScript.value_digest(_replay_fact_projection(ready_after)),
				"%s %s continuation preserves final facts exactly once" % [runtime_case["weapon_id"], checkpoint_phase]
			)
			var terminal_facts_before_repeat := ReplayRecorderScript.value_digest(_replay_fact_projection(target.weapon_replay_snapshot()))
			suite.assert_true(bool(replay_player.replay_to_terminal(target, checkpoint_index).get("ok", false)), "%s %s terminal replay is idempotent" % [runtime_case["weapon_id"], checkpoint_phase])
			suite.assert_equal(ReplayRecorderScript.value_digest(_replay_fact_projection(target.weapon_replay_snapshot())), terminal_facts_before_repeat, "%s %s repeated terminal replay has no duplicate facts" % [runtime_case["weapon_id"], checkpoint_phase])
			replay_player.reset()
			suite.assert_true(not bool(replay_player.restore_frame(target, 0).get("ok", false)), "%s replay reset exposes no stale restorable frame" % runtime_case["weapon_id"])
			target.reset_runtime_state()
			_assert_runtime_reset_is_clean(suite, target, str(runtime_case["weapon_id"]))
			await _free_runtime_player(target)
		await _free_runtime_player(source)


func _record_real_runtime_checkpoints(
	suite,
	source: Node,
	runtime_case: Dictionary,
	recorder
) -> Array[Dictionary]:
	var checkpoints: Array[Dictionary] = []
	var recorded_phases: Dictionary = {}
	var ready_before: Dictionary = source.weapon_replay_snapshot()
	if bool(recorder.record_snapshot(ready_before).get("ok", false)):
		checkpoints.append(ready_before)
	else:
		suite.assert_true(false, "%s records initial READY" % runtime_case["weapon_id"])
		return checkpoints

	source.advance_action_frame()
	if not source.try_action(StringName(runtime_case["action_id"])):
		suite.assert_true(false, "%s submits a representative action" % runtime_case["weapon_id"])
		return checkpoints
	var submitted: Dictionary = source.weapon_replay_snapshot()
	var submitted_phase := str(submitted.get("phase", ""))
	if submitted_phase in ["HOLD", "WINDUP", "ACTIVE", "RECOVERY"]:
		_record_runtime_checkpoint(suite, recorder, checkpoints, recorded_phases, submitted, str(runtime_case["weapon_id"]))
	if submitted_phase == "HOLD":
		source.advance_action_frame()
		var released := bool(source.call(
			"_submit_weapon_intent",
			StringName(str(runtime_case["semantic_action"])),
			&"released"
		))
		suite.assert_true(released, "%s releases the representative hold" % runtime_case["weapon_id"])
		var released_snapshot: Dictionary = source.weapon_replay_snapshot()
		_record_runtime_checkpoint(suite, recorder, checkpoints, recorded_phases, released_snapshot, str(runtime_case["weapon_id"]))

	var remaining_frames := 4096
	while str(source.weapon_replay_snapshot().get("phase", "")) != "READY" and remaining_frames > 0:
		source.advance_action_frame()
		var current: Dictionary = source.weapon_replay_snapshot()
		var current_phase := str(current.get("phase", ""))
		if current_phase in ["HOLD", "WINDUP", "ACTIVE", "RECOVERY"]:
			_record_runtime_checkpoint(suite, recorder, checkpoints, recorded_phases, current, str(runtime_case["weapon_id"]))
		remaining_frames -= 1
	suite.assert_true(remaining_frames > 0, "%s source action reaches READY" % runtime_case["weapon_id"])
	var ready_after: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(bool(recorder.record_snapshot(ready_after).get("ok", false)), "%s records terminal READY" % runtime_case["weapon_id"])
	checkpoints.append(ready_after)
	for phase: String in ["WINDUP", "ACTIVE", "RECOVERY"]:
		suite.assert_true(recorded_phases.has(phase), "%s records %s checkpoint" % [runtime_case["weapon_id"], phase])
	if bool(runtime_case["expected_hold"]):
		suite.assert_true(recorded_phases.has("HOLD"), "%s records HOLD checkpoint" % runtime_case["weapon_id"])
	return checkpoints


func _record_runtime_checkpoint(
	suite,
	recorder,
	checkpoints: Array[Dictionary],
	recorded_phases: Dictionary,
	snapshot: Dictionary,
	weapon_id: String
) -> void:
	var phase := str(snapshot.get("phase", ""))
	if recorded_phases.has(phase):
		return
	var recorded: Dictionary = recorder.record_snapshot(snapshot)
	suite.assert_true(bool(recorded.get("ok", false)), "%s records %s checkpoint: %s" % [weapon_id, phase, str(recorded)])
	if bool(recorded.get("ok", false)):
		recorded_phases[phase] = true
		checkpoints.append(snapshot.duplicate(true))


func _replay_fact_projection(snapshot: Dictionary) -> Dictionary:
	var coordinator := snapshot.get("coordinator", {}) as Dictionary
	var state := snapshot.get("player_weapon_state", {}) as Dictionary
	return {
		"runtime": (coordinator.get("runtime", {}) as Dictionary).duplicate(true),
		"resource_transaction": (coordinator.get("resource_transaction", {}) as Dictionary).duplicate(true),
		"action_reward_claims": (state.get("action_reward_claims", {}) as Dictionary).duplicate(true),
		"action_ids_by_token": (state.get("action_ids_by_token", {}) as Dictionary).duplicate(true),
		"action_generations_by_token": (state.get("action_generations_by_token", {}) as Dictionary).duplicate(true),
		"action_token_order": (state.get("action_token_order", []) as Array).duplicate(true),
		"hit_fact_claims": (state.get("hit_fact_claims", {}) as Dictionary).duplicate(true),
		"resource_fact_state": (state.get("resource_fact_state", {}) as Dictionary).duplicate(true),
	}


func _assert_strict_player_replay_state_validation(
	suite,
	target: Node,
	checkpoint: Dictionary,
	weapon_id: String,
	label: String
) -> void:
	var canonical_state := checkpoint.get("player_weapon_state", {}) as Dictionary
	var token_order := canonical_state.get("action_token_order", []) as Array
	if token_order.is_empty():
		return
	var tracked_token := int(token_order[-1])
	var tracked_generation := int(
		(canonical_state.get("action_generations_by_token", {}) as Dictionary).get(tracked_token, 0)
	)
	var invalid_cases: Array[Dictionary] = []

	var stale_floor := checkpoint.duplicate(true)
	stale_floor["player_weapon_state"]["next_token_floor"] = tracked_token
	invalid_cases.append({"label": "tracked token at next-token floor", "snapshot": stale_floor})

	var wrong_generation := checkpoint.duplicate(true)
	wrong_generation["player_weapon_state"]["action_generations_by_token"][tracked_token] = tracked_generation + 100
	invalid_cases.append({"label": "token generation mapping drift", "snapshot": wrong_generation})

	var forged_claim := checkpoint.duplicate(true)
	forged_claim["player_weapon_state"]["action_reward_claims"]["999999:forged_reward"] = true
	invalid_cases.append({"label": "reward claim for unknown token", "snapshot": forged_claim})

	var reversed_order := checkpoint.duplicate(true)
	var forged_token := maxi(
		tracked_token + 1,
		int(canonical_state.get("next_token_floor", tracked_token + 1))
	)
	reversed_order["player_weapon_state"]["action_ids_by_token"][forged_token] = "forged_action"
	reversed_order["player_weapon_state"]["action_generations_by_token"][forged_token] = tracked_generation + 1
	reversed_order["player_weapon_state"]["action_token_order"] = [forged_token] + token_order.duplicate()
	reversed_order["player_weapon_state"]["next_token_floor"] = forged_token + 1
	invalid_cases.append({"label": "non-increasing token order", "snapshot": reversed_order})

	var mismatched_time_energy := checkpoint.duplicate(true)
	mismatched_time_energy["time_manager_state"]["time_energy_state"]["revision"] = int(
		mismatched_time_energy["time_manager_state"]["time_energy_state"]["revision"]
	) + 1
	invalid_cases.append({
		"label": "time-manager and coordinator energy authority drift",
		"snapshot": mismatched_time_energy,
	})

	var legacy_snapshot := checkpoint.duplicate(true)
	legacy_snapshot["schema_version"] = 1
	invalid_cases.append({"label": "legacy player snapshot schema", "snapshot": legacy_snapshot})

	for invalid_case: Dictionary in invalid_cases:
		var before_digest := ReplayRecorderScript.value_digest(target.weapon_replay_snapshot())
		suite.assert_true(
			not target.restore_weapon_replay_snapshot(invalid_case["snapshot"]),
			"%s rejects %s" % [label, invalid_case["label"]]
		)
		suite.assert_equal(
			ReplayRecorderScript.value_digest(target.weapon_replay_snapshot()),
			before_digest,
			"%s %s rejection is atomic" % [label, invalid_case["label"]]
		)
	if weapon_id == "staff":
		_assert_staff_adapter_descriptor_binding(suite, target, checkpoint, label)


func _assert_staff_adapter_descriptor_binding(
	suite,
	target: Node,
	checkpoint: Dictionary,
	label: String
) -> void:
	var coordinator := checkpoint.get("coordinator", {}) as Dictionary
	var runtime := coordinator.get("runtime", {}) as Dictionary
	var adapter := runtime.get("adapter_snapshot", {}) as Dictionary
	var adapter_phase := str(adapter.get("phase_state", ""))
	var invalid_cases: Array[Dictionary] = []
	if adapter_phase == "prepared":
		var prepared_payloads := adapter.get("prepared_payloads", []) as Array
		if not prepared_payloads.is_empty():
			var forged_position := checkpoint.duplicate(true)
			forged_position["coordinator"]["runtime"]["adapter_snapshot"]["prepared_payloads"][0]["global_position"] += Vector2(384.0, -192.0)
			invalid_cases.append({
				"label": "prepared Staff payload position drift",
				"snapshot": forged_position,
			})
	elif adapter_phase == "released":
		var owned_payloads := adapter.get("owned_payloads", []) as Array
		if not owned_payloads.is_empty():
			var forged_identity := checkpoint.duplicate(true)
			forged_identity["coordinator"]["runtime"]["adapter_snapshot"]["owned_payloads"][0]["execution"]["descriptor_id"] = "forged_staff_payload"
			invalid_cases.append({
				"label": "released Staff payload descriptor drift",
				"snapshot": forged_identity,
			})

			var forged_execution := checkpoint.duplicate(true)
			var execution: Dictionary = forged_execution["coordinator"]["runtime"]["adapter_snapshot"]["owned_payloads"][0]["execution"]
			if execution.has("damage"):
				execution["damage"] = float(execution["damage"]) + 1000.0
			else:
				execution["base_attack"] = float(execution.get("base_attack", 0.0)) + 1000.0
			invalid_cases.append({
				"label": "released Staff payload execution drift",
				"snapshot": forged_execution,
			})

			var forged_count := checkpoint.duplicate(true)
			var forged_owned: Array = forged_count["coordinator"]["runtime"]["adapter_snapshot"]["owned_payloads"]
			var injected := (forged_owned[0] as Dictionary).duplicate(true)
			injected["execution"]["descriptor_id"] = "injected_staff_payload"
			injected["execution"]["status_source_id"] = StringName(
				"staff:%d:injected_staff_payload:%d" % [
					int(injected.get("token", 0)),
					int((injected.get("execution", {}) as Dictionary).get("outcome_index", 0)),
				]
			)
			forged_owned.append(injected)
			invalid_cases.append({
				"label": "released Staff payload count injection",
				"snapshot": forged_count,
			})
	for invalid_case: Dictionary in invalid_cases:
		var before_digest := ReplayRecorderScript.value_digest(target.weapon_replay_snapshot())
		suite.assert_true(
			not target.restore_weapon_replay_snapshot(invalid_case["snapshot"]),
			"%s rejects %s" % [label, invalid_case["label"]]
		)
		suite.assert_equal(
			ReplayRecorderScript.value_digest(target.weapon_replay_snapshot()),
			before_digest,
			"%s %s rejection is atomic" % [label, invalid_case["label"]]
		)


func _assert_runtime_reset_is_clean(suite, target: Node, weapon_id: String) -> void:
	var reset_snapshot: Dictionary = target.weapon_replay_snapshot()
	var reset_state: Dictionary = reset_snapshot.get("player_weapon_state", {})
	var coordinator := reset_snapshot.get("coordinator", {}) as Dictionary
	var resource_transaction := coordinator.get("resource_transaction", {}) as Dictionary
	suite.assert_equal(reset_snapshot.get("phase"), "READY", "%s runtime reset returns READY" % weapon_id)
	suite.assert_equal(reset_snapshot.get("token"), 0, "%s runtime reset clears the active token" % weapon_id)
	suite.assert_equal(resource_transaction.get("cooldowns"), {}, "%s runtime reset clears cooldowns" % weapon_id)
	suite.assert_equal(resource_transaction.get("committed_tokens"), {}, "%s runtime reset clears committed token ledger" % weapon_id)
	suite.assert_equal(reset_state.get("action_reward_claims"), {}, "%s runtime reset clears reward claims" % weapon_id)
	suite.assert_equal(reset_state.get("action_ids_by_token"), {}, "%s runtime reset clears token action ids" % weapon_id)
	suite.assert_equal(reset_state.get("action_generations_by_token"), {}, "%s runtime reset clears token generations" % weapon_id)
	suite.assert_equal(reset_state.get("action_token_order"), [], "%s runtime reset clears token order" % weapon_id)
	suite.assert_equal(reset_state.get("hit_fact_claims"), {}, "%s runtime reset clears hit claims" % weapon_id)
	suite.assert_equal(reset_state.get("next_token_floor"), coordinator.get("next_token"), "%s runtime reset synchronizes the committed token floor" % weapon_id)
	suite.assert_equal(reset_state.get("combo_timeout_frames"), 0, "%s runtime reset clears combo timeout" % weapon_id)


func _spawn_runtime_player(suite, runtime_case: Dictionary, profiles: Dictionary) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var profile: Dictionary = profiles.get(str(runtime_case["profile_id"]), {})
	var config := {
		"schema_version": 1,
		"milestone": str(runtime_case["milestone"]),
		"character_id": "wanderer",
		"weapon_id": str(runtime_case["weapon_id"]),
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 424242,
		"weapon_profile": profile.duplicate(true),
	}
	if not player.configure_loadout(config):
		suite.assert_true(false, "%s real runtime player configures" % runtime_case["weapon_id"])
		await _free_runtime_player(player)
		return null
	return player


func _free_runtime_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.cancel_transient_actions()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _build_replay(profile: Dictionary, snapshots: Array[Dictionary]) -> Dictionary:
	var recorder = ReplayRecorderScript.new()
	if not bool(recorder.start_recording(profile, 123456).get("ok", false)):
		return {}
	for snapshot: Dictionary in snapshots:
		if not bool(recorder.record_snapshot(snapshot).get("ok", false)):
			return {}
	var result: Dictionary = recorder.finish_recording()
	return (result.get("replay", {}) as Dictionary).duplicate(true)


func _intent_event(frame: int, sequence: int, capture_sequence: int) -> Dictionary:
	return {
		"schema_version": ReplayRecorderScript.EVENT_SCHEMA_VERSION,
		"frame": frame,
		"sequence": sequence,
		"capture_sequence": capture_sequence,
		"event_type": "weapon_intent",
		"payload": {
			"semantic_action": "weapon_primary",
			"edge": "pressed",
			"held_frames": 0,
			"context": {},
		},
	}


func _combat_damage_event(
	profile: Dictionary,
	frame: int,
	sequence: int,
	capture_sequence: int
) -> Dictionary:
	return {
		"schema_version": ReplayRecorderScript.EVENT_SCHEMA_VERSION,
		"frame": frame,
		"sequence": sequence,
		"capture_sequence": capture_sequence,
		"event_type": "external_fact",
		"payload": {
			"fact_type": "combat_damage",
			"fact_id": "combat_damage:%d:%d:%d" % [frame, sequence, capture_sequence],
			"weapon_id": str(profile.get("weapon_id", "")),
			"action_token": 1,
			"action_generation": 1,
			"data": {
				"target_path": "../ReplayTarget",
				"health_path": "HealthComponent",
				"hp_before": 100.0,
				"hp_after": 72.0,
				"resolved_damage": 28.0,
				"target_dead_after": false,
				"state_before_digest": ReplayRecorderScript.value_digest(
					_snapshot(profile, frame, 1, 1, {"state": "active"})
				),
				"state_after": _snapshot(
					profile,
					frame,
					1,
					1,
					{"state": "active", "hit": true}
				),
			},
		},
	}


func _rehash_replay(replay: Dictionary) -> void:
	for frame_value: Variant in replay.get("frames", []):
		if frame_value is Dictionary:
			(frame_value as Dictionary)["digest"] = ReplayRecorderScript.frame_digest(frame_value)
	for event_value: Variant in replay.get("events", []):
		if event_value is Dictionary:
			(event_value as Dictionary)["digest"] = ReplayRecorderScript.event_digest(event_value)
	replay["terminal_digest"] = ReplayRecorderScript.terminal_digest(replay)


func _snapshot(
	profile: Dictionary,
	frame: int,
	token: int,
	generation: int,
	state: Dictionary
) -> Dictionary:
	return {
		"schema_version": ReplayRecorderScript.SNAPSHOT_SCHEMA_VERSION,
		"event_prefix_count": 0,
		"event_prefix_root": ReplayRecorderScript.event_prefix_root([], 0),
		"weapon_id": str(profile.get("weapon_id", "")),
		"frame": frame,
		"token": token,
		"generation": generation,
		"phase": "READY" if token == 0 else "ACTIVE",
		"runtime": {
			"schema_version": 1,
			"weapon_id": str(profile.get("weapon_id", "")),
			"profile_id": str(profile.get("id", "")),
			"profile_version": int(profile.get("profile_version", 0)),
			"state": state.duplicate(true),
		},
	}


func _snapshot_with_event_prefix(
	snapshot: Dictionary,
	events: Array[Dictionary],
	count: int
) -> Dictionary:
	var result := snapshot.duplicate(true)
	result["event_prefix_count"] = count
	result["event_prefix_root"] = ReplayRecorderScript.event_prefix_root(events, count)
	return result


func _load_profiles(suite) -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	suite.assert_true(file != null, "weapon runtime profile catalog opens")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	suite.assert_true(parsed is Array, "weapon runtime profile catalog parses")
	if not parsed is Array:
		return {}
	var profiles: Dictionary = {}
	for value: Variant in parsed:
		if value is Dictionary:
			profiles[str((value as Dictionary).get("id", ""))] = (value as Dictionary).duplicate(true)
	for profile_id: String in PROFILE_IDS:
		suite.assert_true(profiles.has(profile_id), "catalog contains %s" % profile_id)
	return profiles


func _reverse_dictionary(source: Dictionary) -> Dictionary:
	var keys := source.keys()
	keys.reverse()
	var result: Dictionary = {}
	for key: Variant in keys:
		result[key] = source[key]
	return result
