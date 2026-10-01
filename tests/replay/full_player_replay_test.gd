extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")

var _suite
var _captured_time_facts: Array[Dictionary] = []


class FullPlayerPlaybackFailureTarget extends RefCounted:
	var identity: Dictionary = {}
	var snapshots: Array[Dictionary] = []
	var current_snapshot: Dictionary = {}
	var failure_mode := &""

	func configure(replay: Dictionary, initial_index: int, mode: StringName = &"") -> void:
		identity = (replay.get("identity", {}) as Dictionary).duplicate(true)
		for frame_value: Variant in replay.get("frames", []) as Array:
			snapshots.append(
				((frame_value as Dictionary).get("snapshot", {}) as Dictionary).duplicate(true)
			)
		current_snapshot = snapshots[initial_index].duplicate(true)
		failure_mode = mode

	func full_player_replay_identity() -> Dictionary:
		return identity.duplicate(true)

	func full_player_replay_snapshot() -> Dictionary:
		return current_snapshot.duplicate(true)

	func restore_full_player_replay_snapshot(snapshot: Dictionary) -> bool:
		current_snapshot = snapshot.duplicate(true)
		return true

	func advance_action_frame(_frame_intents: Dictionary = {}) -> bool:
		var next_frame := int(current_snapshot.get("frame", -1)) + 1
		for snapshot: Dictionary in snapshots:
			if int(snapshot.get("frame", -1)) != next_frame:
				continue
			current_snapshot = snapshot.duplicate(true)
			if failure_mode in [&"reject", &"drift"]:
				var player_state := current_snapshot.get("player_state", {}) as Dictionary
				player_state["position"] = (
					player_state.get("position", Vector2.ZERO) as Vector2
				) + Vector2(13.0, 0.0)
			return failure_mode != &"reject"
		return false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_full_player_active_rift_round_trip()
	await _test_full_player_identity_binds_movement_profile()
	await _test_full_player_v1_schema_is_explicitly_rejected()
	await _test_legacy_character_action_snapshot_is_migrated()
	await _test_full_player_replay_rejects_forged_semantics_and_facts()
	await _test_full_player_playback_failure_is_atomic()
	_suite.finish(get_tree())


func _test_full_player_v1_schema_is_explicitly_rejected() -> void:
	var source := await _spawn_player()
	var identity: Dictionary = source.full_player_replay_identity()
	var snapshot: Dictionary = source.full_player_replay_snapshot()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 1202).get("ok", false)),
		"v2 schema fixture starts recording"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			snapshot,
			_frame_intents(int(snapshot.get("frame", 0)), Vector2.ZERO, Vector2.RIGHT),
			[]
		).get("ok", false)),
		"v2 schema fixture records one checkpoint"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "v2 schema fixture finishes")
	var replay := (finished.get("replay", {}) as Dictionary).duplicate(true)
	_suite.assert_equal(
		ReplayRecorderScript.FULL_PLAYER_SCHEMA_VERSION,
		2,
		"full-player Replay schema advances for the incompatible identity extension"
	)
	_suite.assert_equal(
		ReplayRecorderScript.FULL_PLAYER_FRAME_SCHEMA_VERSION,
		2,
		"full-player frame schema advances with its snapshot contract"
	)
	_suite.assert_equal(
		ReplayRecorderScript.FULL_PLAYER_SNAPSHOT_SCHEMA_VERSION,
		2,
		"full-player snapshot schema advances for character action state"
	)
	_suite.assert_true(
		not snapshot.has("active_item_state"),
		"M1 schema v2 keeps its exact legacy snapshot field set"
	)
	_suite.assert_true(
		not snapshot.has("reward_effect_state")
		and not snapshot.has("live_talent_state"),
		"M1 schema v2 excludes Launch reward and live-talent sealing fields"
	)

	var legacy_replay := replay.duplicate(true)
	legacy_replay["schema_version"] = 1
	var legacy_replay_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		legacy_replay,
		identity
	)
	_suite.assert_equal(
		legacy_replay_rejected.get("code"),
		&"FULL_PLAYER_REPLAY_SCHEMA_VERSION_MISMATCH",
		"legacy v1 full-player Replay is rejected by schema version"
	)

	var legacy_frame := replay.duplicate(true)
	((legacy_frame["frames"] as Array)[0] as Dictionary)["schema_version"] = 1
	var legacy_frame_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		legacy_frame,
		identity
	)
	_suite.assert_equal(
		legacy_frame_rejected.get("code"),
		&"FULL_PLAYER_REPLAY_FRAME_INVALID",
		"legacy v1 full-player frame is rejected before digest validation"
	)

	var legacy_snapshot := replay.duplicate(true)
	var legacy_snapshot_frame := (legacy_snapshot["frames"] as Array)[0] as Dictionary
	(legacy_snapshot_frame["snapshot"] as Dictionary)["schema_version"] = 1
	var legacy_snapshot_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		legacy_snapshot,
		identity
	)
	_suite.assert_equal(
		legacy_snapshot_rejected.get("code"),
		&"FULL_PLAYER_SNAPSHOT_SCHEMA_MISMATCH",
		"legacy v1 full-player snapshot is rejected before digest validation"
	)
	await _free_player(source)


func _test_legacy_character_action_snapshot_is_migrated() -> void:
	var source := await _spawn_player()
	var recorder = ReplayRecorderScript.new()
	var identity: Dictionary = source.full_player_replay_identity()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 2201).get("ok", false)),
		"legacy character-action fixture starts"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			source.full_player_replay_snapshot(),
			_frame_intents(0, Vector2.ZERO, Vector2.RIGHT),
			[]
		).get("ok", false)),
		"legacy character-action fixture records frame zero"
	)
	for frame: int in range(1, 3):
		_suite.assert_true(
			_advance_and_record(
				source,
				recorder,
				_frame_intents(frame, Vector2.ZERO, Vector2.RIGHT),
				"legacy character-action frame %d" % frame
			),
			"legacy character-action frame %d records" % frame
		)
	var finished: Dictionary = recorder.finish_full_player_recording()
	var replay := finished.get("replay", {}) as Dictionary
	_suite.assert_true(bool(finished.get("ok", false)), "legacy character-action fixture finishes")
	var legacy_replay := _legacy_character_action_replay(replay)
	var caller_copy := legacy_replay.duplicate(true)
	var legacy_first_digest := str(
		((legacy_replay.get("frames", []) as Array)[0] as Dictionary).get("digest", "")
	)
	await _free_player(source)

	var target := await _spawn_player()
	var replay_player = ReplayPlayerScript.new()
	var loaded: Dictionary = replay_player.load_full_player_replay(
		legacy_replay,
		target.full_player_replay_identity()
	)
	_suite.assert_true(bool(loaded.get("ok", false)), "legacy nested action schema loads")
	_suite.assert_equal(
		legacy_replay,
		caller_copy,
		"legacy Replay migration does not mutate the caller-owned value"
	)
	var normalized_replay := replay_player.full_player_replay_snapshot()
	for frame_value: Variant in normalized_replay.get("frames", []) as Array:
		var normalized_action := (
			((frame_value as Dictionary).get("snapshot", {}) as Dictionary).get(
				"character_action_state",
				{}
			) as Dictionary
		)
		_suite.assert_equal(
			int(normalized_action.get("schema_version", 0)),
			2,
			"legacy character-action state is normalized to schema v2"
		)
		_suite.assert_equal(
			normalized_action.get("mastery_claims", null),
			[],
			"legacy character-action migration adds an empty mastery ledger"
		)
	_suite.assert_true(
		str(((normalized_replay["frames"] as Array)[0] as Dictionary).get("digest", ""))
		!= legacy_first_digest,
		"migration refreshes frame digests for the normalized snapshots"
	)
	_suite.assert_equal(
		str(normalized_replay.get("terminal_snapshot_digest", "")),
		ReplayRecorderScript.value_digest(
			((normalized_replay["frames"] as Array)[-1] as Dictionary).get("snapshot", {})
		),
		"migration refreshes the terminal snapshot digest"
	)
	_suite.assert_equal(
		str(normalized_replay.get("terminal_digest", "")),
		ReplayRecorderScript.full_player_terminal_digest(normalized_replay),
		"migration refreshes the terminal Replay digest"
	)
	var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
	_suite.assert_true(
		bool(replayed.get("ok", false)),
		"legacy nested action Replay restores and reaches terminal: %s" % str(replayed)
	)
	_suite.assert_equal(
		target.full_player_replay_snapshot(),
		((normalized_replay["frames"] as Array)[-1] as Dictionary).get("snapshot", {}),
		"legacy nested action Replay reaches the normalized terminal snapshot"
	)

	var direct_snapshot := (
		((legacy_replay.get("frames", []) as Array)[0] as Dictionary).get("snapshot", {})
		as Dictionary
	).duplicate(true)
	_suite.assert_true(
		target.restore_full_player_replay_snapshot(direct_snapshot),
		"Player direct restore normalizes a legacy nested action snapshot"
	)
	_suite.assert_equal(
		int((target.full_player_replay_snapshot()["character_action_state"] as Dictionary).get(
			"schema_version",
			0
		)),
		2,
		"Player direct restore installs the normalized action schema"
	)
	await _free_player(target)

	var unknown_schema := legacy_replay.duplicate(true)
	unknown_schema["frames"][0]["snapshot"]["character_action_state"]["schema_version"] = 99
	_rehash_full_player_replay(unknown_schema)
	var unknown_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		unknown_schema,
		identity
	)
	_suite.assert_equal(
		unknown_rejected.get("code"),
		&"FULL_PLAYER_CHARACTER_ACTION_STATE_SCHEMA_MISMATCH",
		"unknown nested action schema has a stable refusal code"
	)

	var malformed_v1 := legacy_replay.duplicate(true)
	malformed_v1["frames"][0]["snapshot"]["character_action_state"]["unexpected"] = true
	_rehash_full_player_replay(malformed_v1)
	var malformed_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		malformed_v1,
		identity
	)
	_suite.assert_equal(
		malformed_rejected.get("code"),
		&"FULL_PLAYER_CHARACTER_ACTION_STATE_FIELDS_MISMATCH",
		"malformed nested action v1 has a stable refusal code"
	)
	var tampered_v1 := legacy_replay.duplicate(true)
	tampered_v1["frames"][0]["snapshot"]["character_action_state"]["revision"] = 99
	var tampered_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		tampered_v1,
		identity
	)
	_suite.assert_equal(
		tampered_rejected.get("code"),
		&"FULL_PLAYER_FRAME_DIGEST_MISMATCH",
		"legacy content is authenticated before migration can refresh its digests"
	)

	var rollback_replay := legacy_replay.duplicate(true)
	rollback_replay["frames"][1]["snapshot"]["weapon_state"]["schema_version"] = 99
	_rehash_full_player_replay(rollback_replay)
	var rollback_target := await _spawn_player()
	var rollback_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(rollback_player.load_full_player_replay(
			rollback_replay,
			rollback_target.full_player_replay_identity()
		).get("ok", false)),
		"legacy rollback fixture loads before participant restoration"
	)
	_suite.assert_true(
		bool(rollback_player.restore_full_player_frame(rollback_target, 0).get("ok", false)),
		"legacy rollback fixture establishes frame zero"
	)
	var rollback_before: Dictionary = rollback_target.full_player_replay_snapshot()
	var failed_restore: Dictionary = rollback_player.restore_full_player_frame(rollback_target, 1)
	_suite.assert_equal(
		failed_restore.get("code"),
		&"FULL_PLAYER_REPLAY_RESTORE_REJECTED",
		"a later participant rejection preserves the stable restore refusal code"
	)
	_suite.assert_equal(
		rollback_target.full_player_replay_snapshot(),
		rollback_before,
		"a post-migration participant rejection rolls the real Player back atomically"
	)
	var cursor_restore: Dictionary = rollback_player.restore_full_player_frame(rollback_target)
	_suite.assert_true(
		bool(cursor_restore.get("ok", false)),
		"a post-migration participant rejection leaves the Replay cursor usable"
	)
	_suite.assert_equal(
		(cursor_restore.get("context", {}) as Dictionary).get("index"),
		0,
		"a post-migration participant rejection preserves the Replay cursor"
	)
	await _free_player(rollback_target)


func _test_full_player_active_rift_round_trip() -> void:
	var source := await _spawn_player()
	var recorder = ReplayRecorderScript.new()
	var identity: Dictionary = source.full_player_replay_identity()
	_suite.assert_true(not identity.is_empty(), "source exposes a full-player Replay identity")
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 731904).get("ok", false)),
		"full-player Recorder starts"
	)
	var initial_intents := _frame_intents(0, Vector2.ZERO, Vector2.RIGHT)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			source.full_player_replay_snapshot(),
			initial_intents,
			[]
		).get("ok", false)),
		"full-player Recorder captures the initial checkpoint"
	)

	var rift_intents := _frame_intents(1, Vector2.RIGHT, Vector2.UP)
	(rift_intents["time"] as Array).append({
		"id": &"time_rift",
		"edge": &"pressed",
		"held_frames": 0,
		"mode": &"press",
	})
	_suite.assert_true(
		_advance_and_record(source, recorder, rift_intents, "Rift commit frame"),
		"live Rift frame advances and records"
	)
	var active_checkpoint: Dictionary = source.full_player_replay_snapshot()
	var active_descriptor := _single_rift_descriptor(active_checkpoint)
	_suite.assert_true(not active_descriptor.is_empty(), "recorded checkpoint contains an active Rift")
	var payload_id := StringName(str(active_descriptor.get("payload_id", "")))
	var checkpoint_remaining := int(active_descriptor.get("remaining_frames", -1))
	var source_rift: Node = source.get_node("WorldPayloadAuthority").payload_node(payload_id)
	_suite.assert_true(source_rift != null, "live source owns the recorded Rift payload node")
	var stable_source_id := StringName(str(source_rift.get("_source_id")))

	for frame: int in range(2, 6):
		var intents := _frame_intents(
			frame,
			Vector2.RIGHT if frame <= 3 else Vector2.ZERO,
			Vector2.UP
		)
		_suite.assert_true(
			_advance_and_record(source, recorder, intents, "continuation frame %d" % frame),
			"live continuation frame %d records" % frame
		)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "full-player Recorder finishes")
	var replay := finished.get("replay", {}) as Dictionary
	_suite.assert_equal(
		replay.get("schema_id"),
		ReplayRecorderScript.FULL_PLAYER_SCHEMA_ID,
		"full-player Replay is isolated from the P11 weapon schema"
	)
	_suite.assert_equal(
		ReplayRecorderScript.SCHEMA_ID,
		"planewalker.weapon_runtime_replay",
		"P11 weapon Replay schema remains unchanged"
	)
	var frames := replay.get("frames", []) as Array
	_suite.assert_equal(frames.size(), 6, "every authoritative frame has a Replay entry")
	var rift_frame := frames[1] as Dictionary
	_suite.assert_equal(
		rift_frame.get("frame_intents"),
		rift_intents,
		"Replay frame preserves movement, aim, and Time/Rift semantic intents"
	)
	var rift_facts := rift_frame.get("verification_facts", []) as Array
	_suite.assert_equal(rift_facts.size(), 1, "Rift frame records one time_skill_committed fact")
	if not rift_facts.is_empty():
		var fact := rift_facts[0] as Dictionary
		_suite.assert_equal(str(fact.get("ability_id", "")), "rift", "committed fact names Rift")
		_suite.assert_equal(fact.get("frame"), 1, "committed fact binds the authoritative frame")
		_suite.assert_equal(str(fact.get("run_id", "")), str(identity["run_id"]), "committed fact binds the run")
	await _free_player(source)

	var replay_from_start := await _spawn_player()
	var player_from_start = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(player_from_start.load_full_player_replay(
			replay,
			replay_from_start.full_player_replay_identity()
		).get("ok", false)),
		"full-player Replay loads against an identical Player identity"
	)
	var replayed_from_start: Dictionary = player_from_start.replay_full_player_to_terminal(
		replay_from_start,
		0
	)
	_suite.assert_true(
		bool(replayed_from_start.get("ok", false)),
		"Replay from frame zero reproduces the Rift commit fact: %s" % str(replayed_from_start)
	)
	var terminal_snapshot := (frames[-1] as Dictionary).get("snapshot", {}) as Dictionary
	_suite.assert_equal(
		replay_from_start.full_player_replay_snapshot(),
		terminal_snapshot,
		"Replay from the initial checkpoint reaches the exact terminal full snapshot"
	)
	await _free_player(replay_from_start)

	var replay_from_rift := await _spawn_player()
	var player_from_rift = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(player_from_rift.load_full_player_replay(
			replay,
			replay_from_rift.full_player_replay_identity()
		).get("ok", false)),
		"active-Rift checkpoint Replay loads"
	)
	var restored: Dictionary = player_from_rift.restore_full_player_frame(replay_from_rift, 1)
	_suite.assert_true(
		bool(restored.get("ok", false)),
		"ReplayPlayer restores the checkpoint that already owns the active Rift"
	)
	var restored_descriptor := _single_rift_descriptor(
		replay_from_rift.full_player_replay_snapshot()
	)
	_suite.assert_equal(
		str(restored_descriptor.get("payload_id", "")),
		str(payload_id),
		"active Rift payload_id is stable across full-player restore"
	)
	_suite.assert_equal(
		int(restored_descriptor.get("remaining_frames", -1)),
		checkpoint_remaining,
		"active Rift remaining_frames is exact at the restored checkpoint"
	)
	var restored_rift: Node = replay_from_rift.get_node(
		"WorldPayloadAuthority"
	).payload_node(payload_id)
	_suite.assert_true(restored_rift != null, "restore reconstructs the active Rift node")
	if restored_rift != null:
		_suite.assert_equal(
			StringName(str(restored_rift.get("_source_id"))),
			stable_source_id,
			"active Rift stable source identity survives reconstruction"
		)
	var replayed_from_rift: Dictionary = player_from_rift.replay_full_player_to_terminal(
		replay_from_rift,
		1
	)
	_suite.assert_true(
		bool(replayed_from_rift.get("ok", false)),
		"active-Rift checkpoint advances to terminal: %s" % str(replayed_from_rift)
	)
	_suite.assert_equal(
		ReplayRecorderScript.value_digest(replay_from_rift.full_player_replay_snapshot()),
		str(replay.get("terminal_snapshot_digest", "")),
		"active-Rift continuation reaches the recorded terminal full snapshot digest"
	)
	_suite.assert_equal(
		replay_from_rift.full_player_replay_snapshot(),
		terminal_snapshot,
		"active-Rift continuation matches live state including remaining_frames"
	)

	await _free_player(replay_from_rift)


func _test_full_player_identity_binds_movement_profile() -> void:
	var source := await _spawn_player()
	source.stats.move_speed = 260.0
	var identity: Dictionary = source.full_player_replay_identity()
	_suite.assert_equal(
		float(identity.get("move_speed", -1.0)),
		260.0,
		"full-player identity seals the fixed-frame movement speed"
	)
	_suite.assert_equal(
		str(identity.get("character_profile_id", "")),
		"wanderer_m1_v1",
		"full-player identity seals the authoritative character profile"
	)
	_suite.assert_equal(
		identity.get("character_talent_ids", []),
		[],
		"full-player identity seals the selected character talents"
	)
	_suite.assert_equal(
		(identity.get("stats", {}) as Dictionary).get("move_speed"),
		260.0,
		"full-player identity seals the complete Stats projection"
	)
	_suite.assert_equal(
		identity.get("mobility", {}),
		source.mobility_snapshot(),
		"full-player identity seals profile-authoritative mobility"
	)
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 260).get("ok", false)),
		"movement-profile Replay starts"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			source.full_player_replay_snapshot(),
			_frame_intents(0, Vector2.ZERO, Vector2.RIGHT),
			[]
		).get("ok", false)),
		"movement-profile Replay records its checkpoint"
	)
	var starting_position: Vector2 = source.global_position
	_suite.assert_true(
		_advance_and_record(
			source,
			recorder,
			_frame_intents(1, Vector2.RIGHT, Vector2.RIGHT),
			"nonzero movement frame"
		),
		"nonzero movement frame records"
	)
	_suite.assert_true(
		not source.global_position.is_equal_approx(starting_position),
		"nonzero movement profile advances the Player"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	var replay := finished.get("replay", {}) as Dictionary
	_suite.assert_true(bool(finished.get("ok", false)), "movement-profile Replay finishes")
	await _free_player(source)

	var mismatched := await _spawn_player()
	mismatched.stats.move_speed = 120.0
	var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		replay,
		mismatched.full_player_replay_identity()
	)
	_suite.assert_equal(
		rejected.get("code"),
		&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH",
		"Replay rejects a Player with a different fixed-frame movement speed"
	)
	await _free_player(mismatched)

	var matching := await _spawn_player()
	matching.stats.move_speed = 260.0
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(replay_player.load_full_player_replay(
			replay,
			matching.full_player_replay_identity()
		).get("ok", false)),
		"Replay accepts an identical movement profile"
	)
	var replayed: Dictionary = replay_player.replay_full_player_to_terminal(matching, 0)
	_suite.assert_true(
		bool(replayed.get("ok", false)),
		"nonzero movement Replay reaches the exact terminal state: %s" % str(replayed)
	)
	await _free_player(matching)


func _test_full_player_replay_rejects_forged_semantics_and_facts() -> void:
	var source := await _spawn_player()
	var recorder = ReplayRecorderScript.new()
	var identity: Dictionary = source.full_player_replay_identity()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 88).get("ok", false)),
		"forgery fixture starts"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			source.full_player_replay_snapshot(),
			_frame_intents(0, Vector2.ZERO, Vector2.RIGHT),
			[]
		).get("ok", false)),
		"forgery fixture records initial state"
	)
	var rift_intents := _frame_intents(1, Vector2.ZERO, Vector2.RIGHT)
	(rift_intents["time"] as Array).append({
		"id": &"time_rift",
		"edge": &"pressed",
		"held_frames": 0,
		"mode": &"press",
	})
	_suite.assert_true(
		_advance_and_record(source, recorder, rift_intents, "forgery Rift frame"),
		"forgery fixture records Rift"
	)
	_suite.assert_true(
		_advance_and_record(
			source,
			recorder,
			_frame_intents(2, Vector2.ZERO, Vector2.RIGHT),
			"forgery empty continuation frame"
		),
		"forgery fixture records an empty continuation frame"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	var replay := finished.get("replay", {}) as Dictionary
	for fact_field: String in ["token", "generation", "frame", "run_id"]:
		var forged := replay.duplicate(true)
		var fact := forged["frames"][1]["verification_facts"][0] as Dictionary
		match fact_field:
			"run_id":
				fact[fact_field] = &"foreign-run"
			_:
				fact[fact_field] = int(fact[fact_field]) + 1
		_rehash_full_player_replay(forged)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			forged,
			identity
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_VERIFICATION_FACT_INVALID",
			"forged time_skill_committed %s is rejected after valid rehash" % fact_field
		)

	var forged_pressed_ability := replay.duplicate(true)
	forged_pressed_ability["frames"][1]["verification_facts"][0]["ability_id"] = &"stop"
	_rehash_full_player_replay(forged_pressed_ability)
	var pressed_ability_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_pressed_ability,
		identity
	)
	_suite.assert_equal(
		pressed_ability_rejected.get("code"),
		&"FULL_PLAYER_VERIFICATION_FACT_INVALID",
		"committed fact must match the pressed time intent"
	)

	var forged_disabled_ability := replay.duplicate(true)
	forged_disabled_ability["frames"][1]["verification_facts"][0]["ability_id"] = &"rewind"
	forged_disabled_ability["frames"][1]["frame_intents"]["time"][0]["id"] = &"time_rewind"
	_rehash_full_player_replay(forged_disabled_ability)
	var disabled_ability_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_disabled_ability,
		identity
	)
	_suite.assert_equal(
		disabled_ability_rejected.get("code"),
		&"FULL_PLAYER_VERIFICATION_FACT_INVALID",
		"committed fact must name an enabled time ability"
	)

	var forged_empty_frame_fact := replay.duplicate(true)
	var repeated_fact := (
		forged_empty_frame_fact["frames"][1]["verification_facts"][0] as Dictionary
	).duplicate(true)
	repeated_fact["frame"] = 2
	forged_empty_frame_fact["frames"][2]["verification_facts"] = [repeated_fact]
	_rehash_full_player_replay(forged_empty_frame_fact)
	var empty_frame_fact_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_empty_frame_fact,
		identity
	)
	_suite.assert_equal(
		empty_frame_fact_rejected.get("code"),
		&"FULL_PLAYER_VERIFICATION_FACT_INVALID",
		"an empty frame cannot repeat an active Rift commit fact"
	)

	for descriptor_field: String in ["source_token", "payload_generation"]:
		var forged_descriptor_identity := replay.duplicate(true)
		var descriptors := (
			forged_descriptor_identity["frames"][1]["snapshot"]["world_payload_state"]["descriptors"]
			as Array
		)
		(descriptors[0] as Dictionary)[descriptor_field] = (
			int((descriptors[0] as Dictionary)[descriptor_field]) + 1
		)
		_rehash_full_player_replay(forged_descriptor_identity)
		var descriptor_identity_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			forged_descriptor_identity,
			identity
		)
		_suite.assert_equal(
			descriptor_identity_rejected.get("code"),
			&"FULL_PLAYER_VERIFICATION_FACT_INVALID",
			"Rift fact binds descriptor %s" % descriptor_field
		)

	var forged_intents := replay.duplicate(true)
	forged_intents["frames"][1]["frame_intents"]["time"][0]["id"] = &"time_unknown"
	_rehash_full_player_replay(forged_intents)
	var intent_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_intents,
		identity
	)
	_suite.assert_equal(
		intent_rejected.get("code"),
		&"FULL_PLAYER_FRAME_INTENTS_INVALID",
		"forged semantic frame_intents are rejected after valid rehash"
	)
	var forged_mode := replay.duplicate(true)
	forged_mode["frames"][1]["frame_intents"]["time"][0]["mode"] = &"confirm"
	_rehash_full_player_replay(forged_mode)
	var mode_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_mode,
		identity
	)
	_suite.assert_equal(
		mode_rejected.get("code"),
		&"FULL_PLAYER_FRAME_INTENTS_INVALID",
		"Recorder validation matches Player's exact press/hold/toggle mode set"
	)
	await _free_player(source)


func _test_full_player_playback_failure_is_atomic() -> void:
	var source := await _spawn_player()
	var recorder = ReplayRecorderScript.new()
	var identity: Dictionary = source.full_player_replay_identity()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 412).get("ok", false)),
		"atomic failure Replay starts"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			source.full_player_replay_snapshot(),
			_frame_intents(0, Vector2.ZERO, Vector2.RIGHT),
			[]
		).get("ok", false)),
		"atomic failure Replay records its initial checkpoint"
	)
	for frame: int in range(1, 3):
		_suite.assert_true(
			_advance_and_record(
				source,
				recorder,
				_frame_intents(frame, Vector2.ZERO, Vector2.RIGHT),
				"atomic failure frame %d" % frame
			),
			"atomic failure frame %d records" % frame
		)
	var finished: Dictionary = recorder.finish_full_player_recording()
	var replay := finished.get("replay", {}) as Dictionary
	_suite.assert_true(bool(finished.get("ok", false)), "atomic failure Replay finishes")
	await _free_player(source)

	var frames := replay.get("frames", []) as Array
	var checkpoint_snapshot := (
		(frames[1] as Dictionary).get("snapshot", {}) as Dictionary
	).duplicate(true)
	for failure_case: Dictionary in [
		{"mode": &"reject", "code": &"FULL_PLAYER_REPLAY_FRAME_REJECTED"},
		{"mode": &"drift", "code": &"FULL_PLAYER_REPLAY_CHECKPOINT_MISMATCH"},
	]:
		var replay_player = ReplayPlayerScript.new()
		_suite.assert_true(
			bool(replay_player.load_full_player_replay(replay, identity).get("ok", false)),
			"%s failure fixture loads" % str(failure_case["mode"])
		)
		var target := FullPlayerPlaybackFailureTarget.new()
		target.configure(replay, 1, failure_case["mode"])
		_suite.assert_true(
			bool(replay_player.restore_full_player_frame(target, 1).get("ok", false)),
			"%s failure fixture establishes checkpoint one" % str(failure_case["mode"])
		)
		var failed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
		_suite.assert_equal(
			failed.get("code"),
			failure_case["code"],
			"%s failure reports the stable refusal code" % str(failure_case["mode"])
		)
		_suite.assert_equal(
			target.full_player_replay_snapshot(),
			checkpoint_snapshot,
			"%s failure restores the complete pre-playback target snapshot" % str(failure_case["mode"])
		)
		var cursor_probe := FullPlayerPlaybackFailureTarget.new()
		cursor_probe.configure(replay, 2)
		var cursor_restore: Dictionary = replay_player.restore_full_player_frame(cursor_probe)
		_suite.assert_true(
			bool(cursor_restore.get("ok", false)),
			"%s failure cursor remains restorable: %s" % [
				str(failure_case["mode"]),
				str(cursor_restore),
			]
		)
		_suite.assert_equal(
			(cursor_restore.get("context", {}) as Dictionary).get("index"),
			1,
			"%s failure preserves the original Replay cursor" % str(failure_case["mode"])
		)
		_suite.assert_equal(
			cursor_probe.full_player_replay_snapshot(),
			checkpoint_snapshot,
			"%s cursor still addresses the original checkpoint" % str(failure_case["mode"])
		)

	var forged_terminal_snapshot := replay.duplicate(true)
	var forged_terminal_frame := (
		forged_terminal_snapshot.get("frames", []) as Array
	)[-1] as Dictionary
	var forged_player_state := (
		forged_terminal_frame.get("snapshot", {}) as Dictionary
	).get("player_state", {}) as Dictionary
	forged_player_state["position"] = (
		forged_player_state.get("position", Vector2.ZERO) as Vector2
	) + Vector2(17.0, 0.0)
	forged_terminal_snapshot["terminal_snapshot_digest"] = ReplayRecorderScript.value_digest(
		forged_terminal_frame.get("snapshot", {})
	)
	forged_terminal_snapshot["terminal_digest"] = ReplayRecorderScript.full_player_terminal_digest(
		forged_terminal_snapshot
	)
	var snapshot_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_terminal_snapshot,
		identity
	)
	_suite.assert_equal(
		snapshot_rejected.get("code"),
		&"FULL_PLAYER_FRAME_DIGEST_MISMATCH",
		"terminal snapshot tampering is rejected even after outer digests are recomputed"
	)

	var forged_terminal_digest := replay.duplicate(true)
	forged_terminal_digest["terminal_snapshot_digest"] = "0".repeat(64)
	forged_terminal_digest["terminal_digest"] = ReplayRecorderScript.full_player_terminal_digest(
		forged_terminal_digest
	)
	var digest_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_terminal_digest,
		identity
	)
	_suite.assert_equal(
		digest_rejected.get("code"),
		&"FULL_PLAYER_REPLAY_TERMINAL_SNAPSHOT_DIGEST_MISMATCH",
		"terminal snapshot digest tampering is rejected after terminal rehash"
	)


func _advance_and_record(
	player: Node,
	recorder,
	frame_intents: Dictionary,
	label: String
) -> bool:
	_captured_time_facts.clear()
	if not EventBus.time_skill_committed.is_connected(_on_time_skill_committed):
		EventBus.time_skill_committed.connect(_on_time_skill_committed)
	var advanced := bool(player.advance_action_frame(frame_intents))
	if EventBus.time_skill_committed.is_connected(_on_time_skill_committed):
		EventBus.time_skill_committed.disconnect(_on_time_skill_committed)
	if not advanced:
		_suite.assert_true(false, "%s advances" % label)
		return false
	var recorded: Dictionary = recorder.record_full_player_frame(
		player.full_player_replay_snapshot(),
		frame_intents,
		_captured_time_facts
	)
	if not bool(recorded.get("ok", false)):
		_suite.assert_true(false, "%s records: %s" % [label, str(recorded)])
		return false
	return true


func _on_time_skill_committed(
	ability_id: StringName,
	token: int,
	generation: int,
	frame: int,
	run_id: StringName,
	context: Dictionary
) -> void:
	_captured_time_facts.append({
		"ability_id": ability_id,
		"token": token,
		"generation": generation,
		"frame": frame,
		"run_id": run_id,
		"context": context.duplicate(true),
	})


func _frame_intents(
	target_frame: int,
	movement: Vector2,
	aim: Vector2
) -> Dictionary:
	return {
		"dash": [],
		"time": [],
		"weapon": [],
		"character": [],
		"movement": movement,
		"aim": aim,
		"meta": {
			"source": "full_player_replay_test",
			"target_frame": target_frame,
			"frame": target_frame,
		},
	}


func _single_rift_descriptor(snapshot: Dictionary) -> Dictionary:
	var descriptors := (
		(snapshot.get("world_payload_state", {}) as Dictionary).get("descriptors", [])
		as Array
	)
	for descriptor_value: Variant in descriptors:
		if (
			descriptor_value is Dictionary
			and str((descriptor_value as Dictionary).get("handler_id", "")) == "time_rift"
		):
			return (descriptor_value as Dictionary).duplicate(true)
	return {}


func _rehash_full_player_replay(replay: Dictionary) -> void:
	for frame_value: Variant in replay.get("frames", []) as Array:
		(frame_value as Dictionary)["digest"] = ReplayRecorderScript.full_player_frame_digest(
			frame_value as Dictionary
		)
	replay["terminal_snapshot_digest"] = ReplayRecorderScript.value_digest(
		((replay.get("frames", []) as Array)[-1] as Dictionary).get("snapshot", {})
	)
	replay["terminal_digest"] = ReplayRecorderScript.full_player_terminal_digest(replay)


func _legacy_character_action_replay(replay: Dictionary) -> Dictionary:
	var legacy := replay.duplicate(true)
	for frame_value: Variant in legacy.get("frames", []) as Array:
		var action_state := (
			((frame_value as Dictionary).get("snapshot", {}) as Dictionary).get(
				"character_action_state",
				{}
			) as Dictionary
		)
		_suite.assert_equal(
			action_state.get("mastery_claims", []),
			[],
			"legacy fixture only removes an empty v2 mastery ledger"
		)
		action_state.erase("mastery_claims")
		action_state["schema_version"] = 1
	_rehash_full_player_replay(legacy)
	return legacy


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	# Script callbacks are enabled when the node enters the tree; disable them after add_child.
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(bool(player.reset_runtime_state()), "Player fixture resets")
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["rift", "stop"],
	}), "Player fixture configures Rift")
	var manager: Node = player.get_node("TimeManager")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	return player


func _free_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
