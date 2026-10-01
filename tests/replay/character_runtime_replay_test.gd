extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const LAUNCH_SCHEMA_VERSION := 5
const CHARACTER_IDS: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]

var _suite
var _registry: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(not report.call("has_blocking_errors"), "Replay matrix loads the Base Pack")
	if not report.call("has_blocking_errors"):
		await _test_five_character_round_trips()
		await _test_active_item_round_trip_and_tamper_rejection()
		await _test_legacy_launch_v4_migrates_empty_active_state()
	_suite.finish(get_tree())


func _test_five_character_round_trips() -> void:
	for character_index: int in range(CHARACTER_IDS.size()):
		var character_id := CHARACTER_IDS[character_index]
		var source := await _spawn_launch_player(character_id, 4100 + character_index)
		var identity: Dictionary = source.full_player_replay_identity()
		var initial: Dictionary = source.full_player_replay_snapshot()
		var label := str(character_id)
		_suite.assert_equal(
			int(initial.get("schema_version", 0)),
			LAUNCH_SCHEMA_VERSION,
			"%s Launch snapshot uses Player Replay schema 5" % label
		)
		_suite.assert_true(
			initial.get("active_item_state") is Dictionary,
			"%s Launch snapshot includes authoritative active-item state" % label
		)

		var recorder = ReplayRecorderScript.new()
		_suite.assert_true(
			bool(recorder.start_full_player_recording(identity, 4100 + character_index).get("ok", false)),
			"%s Launch Replay recording starts" % label
		)
		_suite.assert_true(
			bool(recorder.record_full_player_frame(
				initial,
				_frame_intents(int(initial.get("frame", 0))),
				[]
			).get("ok", false)),
			"%s records the initial Launch checkpoint" % label
		)
		_suite.assert_true(source.advance_action_frame({}), "%s advances one fixed frame" % label)
		var terminal: Dictionary = source.full_player_replay_snapshot()
		_suite.assert_true(
			bool(recorder.record_full_player_frame(
				terminal,
				_frame_intents(int(terminal.get("frame", 0))),
				[]
			).get("ok", false)),
			"%s records the terminal Launch checkpoint" % label
		)
		var finished: Dictionary = recorder.finish_full_player_recording()
		_suite.assert_true(bool(finished.get("ok", false)), "%s Launch Replay finishes" % label)
		var replay := finished.get("replay", {}) as Dictionary
		_suite.assert_equal(
			int(replay.get("schema_version", 0)),
			LAUNCH_SCHEMA_VERSION,
			"%s Launch Replay root uses schema 5" % label
		)
		for frame_value: Variant in replay.get("frames", []) as Array:
			var frame := frame_value as Dictionary
			_suite.assert_equal(
				int(frame.get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s Launch Replay frame uses schema 5" % label
			)
			_suite.assert_equal(
				int((frame.get("snapshot", {}) as Dictionary).get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s embedded Launch snapshot uses schema 5" % label
			)

		var target := await _spawn_launch_player(character_id, 4100 + character_index)
		var replay_player = ReplayPlayerScript.new()
		_suite.assert_true(
			bool(replay_player.load_full_player_replay(
				replay,
				target.full_player_replay_identity()
			).get("ok", false)),
			"%s Launch Replay loads against the same character identity" % label
		)
		var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
		_suite.assert_true(
			bool(replayed.get("ok", false)),
			"%s Launch Replay reaches the terminal checkpoint" % label
		)
		_suite.assert_equal(
			target.full_player_replay_snapshot(),
			terminal,
			"%s Launch Replay restores the exact terminal state" % label
		)

		var mismatched_id := CHARACTER_IDS[(character_index + 1) % CHARACTER_IDS.size()]
		var mismatched := await _spawn_launch_player(mismatched_id, 4100 + character_index)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			replay,
			mismatched.full_player_replay_identity()
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH",
			"%s Replay rejects a different Launch character profile" % label
		)

		await _free_player(mismatched)
		await _free_player(target)
		await _free_player(source)


func _test_active_item_round_trip_and_tamper_rejection() -> void:
	var source := await _spawn_launch_player(&"wanderer", 5201)
	var active_definition: Dictionary = _registry.call(
		"get_content",
		&"absolute_zero_device"
	)
	_suite.assert_true(
		bool(source.equip_active_item(active_definition).get("ok", false)),
		"Launch Replay fixture equips Absolute Zero Device"
	)
	var time_manager: Node = source.get_node("TimeManager")
	time_manager.set("energy", float(time_manager.get("max_energy")))
	var activated: Dictionary = source.activate_equipped_active_item({"is_boss_target": true})
	_suite.assert_true(bool(activated.get("ok", false)), "Launch Replay fixture activates its item")

	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5201).get("ok", false)),
		"active-item Launch Replay recording starts"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"active-item Launch Replay records the activated checkpoint"
	)
	_suite.assert_true(source.advance_action_frame({}), "active-item fixture advances one frame")
	var terminal: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			terminal,
			_frame_intents(int(terminal.get("frame", 0))),
			[]
		).get("ok", false)),
		"active-item Launch Replay records its terminal checkpoint"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "active-item Launch Replay finishes")
	var replay := (finished.get("replay", {}) as Dictionary).duplicate(true)
	var terminal_active := terminal.get("active_item_state", {}) as Dictionary
	_suite.assert_true(
		int(terminal_active.get("cooldown_end_frame", -1)) > int(terminal_active.get("current_frame", -1)),
		"recorded active item retains a non-zero cooldown"
	)
	_suite.assert_equal(terminal_active.get("next_token"), 2, "recorded active item retains token progress")
	_suite.assert_equal(terminal_active.get("generation"), 1, "recorded active item retains generation")
	_suite.assert_true(
		not (terminal_active.get("handler_state", {}) as Dictionary).is_empty(),
		"recorded active item retains handler state"
	)
	await _free_player(source)

	var target := await _spawn_launch_player(&"wanderer", 5201)
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(replay_player.load_full_player_replay(
			replay,
			target.full_player_replay_identity()
		).get("ok", false)),
		"active-item Launch Replay loads"
	)
	var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
	_suite.assert_true(
		bool(replayed.get("ok", false)),
		"active-item Launch Replay reaches terminal: %s" % str(replayed)
	)
	_suite.assert_equal(
		target.active_item_snapshot(),
		terminal_active,
		"active-item runtime restores cooldown, token, generation, handler, and receipts exactly"
	)
	await _free_player(target)

	for tamper: Dictionary in [
		{"field": "cooldown", "value": 1},
		{"field": "handler", "value": "forged_handler"},
		{"field": "token", "value": 1},
		{"field": "generation", "value": 99},
	]:
		var forged := replay.duplicate(true)
		var forged_active := (
			((forged["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
		)["active_item_state"] as Dictionary
		match str(tamper["field"]):
			"cooldown":
				forged_active["cooldown_end_frame"] = int(
					forged_active["cooldown_end_frame"]
				) + 1
			"handler":
				(forged_active["definition"] as Dictionary)["active_handler_id"] = tamper["value"]
			"token":
				forged_active["next_token"] = tamper["value"]
			"generation":
				forged_active["generation"] = tamper["value"]
		_rehash_full_player_replay(forged)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			forged,
			identity
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_ACTIVE_ITEM_STATE_INVALID",
			"forged active-item %s is rejected after authenticated Replay validation" % tamper["field"]
		)

	var atomic_target := await _spawn_launch_player(&"wanderer", 5201)
	var before: Dictionary = atomic_target.full_player_replay_snapshot()
	var forged_snapshot := initial.duplicate(true)
	var forged_snapshot_active := forged_snapshot["active_item_state"] as Dictionary
	(forged_snapshot_active["definition"] as Dictionary)["active_handler_id"] = "forged_handler"
	_suite.assert_true(
		not atomic_target.restore_full_player_replay_snapshot(forged_snapshot),
		"direct full-player restore rejects forged active-item state"
	)
	_suite.assert_equal(
		atomic_target.full_player_replay_snapshot(),
		before,
		"forged active-item restore leaves the target unchanged"
	)
	await _free_player(atomic_target)

	var rollback_replay := replay.duplicate(true)
	((rollback_replay["frames"] as Array)[1] as Dictionary)["snapshot"]["weapon_state"]["schema_version"] = 99
	_rehash_full_player_replay(rollback_replay)
	var rollback_target := await _spawn_launch_player(&"wanderer", 5201)
	_suite.assert_true(
		bool(rollback_target.equip_active_item(
			_registry.call("get_content", &"paradox_beacon")
		).get("ok", false)),
		"rollback fixture equips a distinct active item"
	)
	var rollback_before: Dictionary = rollback_target.full_player_replay_snapshot()
	var rollback_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(rollback_player.load_full_player_replay(
			rollback_replay,
			rollback_target.full_player_replay_identity()
		).get("ok", false)),
		"active-item rollback fixture loads before participant restore"
	)
	var failed_restore: Dictionary = rollback_player.restore_full_player_frame(rollback_target, 1)
	_suite.assert_equal(
		failed_restore.get("code"),
		&"FULL_PLAYER_REPLAY_RESTORE_REJECTED",
		"later participant rejection keeps the stable restore refusal code"
	)
	_suite.assert_equal(
		rollback_target.full_player_replay_snapshot(),
		rollback_before,
		"later participant rejection rolls active-item installation back atomically"
	)
	await _free_player(rollback_target)


func _test_legacy_launch_v4_migrates_empty_active_state() -> void:
	var source := await _spawn_launch_player(&"time_guardian", 5301)
	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5301).get("ok", false)),
		"legacy Launch fixture starts current recording"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"legacy Launch fixture records an empty active slot"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "legacy Launch fixture finishes")
	var legacy := (finished.get("replay", {}) as Dictionary).duplicate(true)
	legacy["schema_version"] = 4
	for frame_value: Variant in legacy.get("frames", []) as Array:
		var frame := frame_value as Dictionary
		frame["schema_version"] = 4
		var snapshot := frame.get("snapshot", {}) as Dictionary
		snapshot["schema_version"] = 4
		snapshot.erase("active_item_state")
	_rehash_full_player_replay(legacy)
	var caller_copy := legacy.duplicate(true)
	var unauthenticated := legacy.duplicate(true)
	var unauthenticated_player_state := (
		((unauthenticated["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["player_state"] as Dictionary
	unauthenticated_player_state["position"] = (
		unauthenticated_player_state.get("position", Vector2.ZERO) as Vector2
	) + Vector2.ONE
	var unauthenticated_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		unauthenticated,
		identity
	)
	_suite.assert_equal(
		unauthenticated_rejected.get("code"),
		&"FULL_PLAYER_FRAME_DIGEST_MISMATCH",
		"legacy Launch content is authenticated before migration can refresh digests"
	)
	await _free_player(source)

	var target := await _spawn_launch_player(&"time_guardian", 5301)
	var replay_player = ReplayPlayerScript.new()
	var loaded: Dictionary = replay_player.load_full_player_replay(
		legacy,
		target.full_player_replay_identity()
	)
	_suite.assert_true(bool(loaded.get("ok", false)), "trusted legacy Launch v4 Replay migrates")
	_suite.assert_equal(legacy, caller_copy, "legacy Launch migration preserves caller-owned Replay")
	var normalized := replay_player.full_player_replay_snapshot()
	_suite.assert_equal(normalized.get("schema_version"), 5, "legacy Launch root migrates to schema 5")
	var normalized_frame := (normalized.get("frames", []) as Array)[0] as Dictionary
	_suite.assert_equal(normalized_frame.get("schema_version"), 5, "legacy Launch frame migrates to schema 5")
	var normalized_snapshot := normalized_frame.get("snapshot", {}) as Dictionary
	_suite.assert_equal(normalized_snapshot.get("schema_version"), 5, "legacy Launch snapshot migrates to schema 5")
	_suite.assert_equal(
		normalized_snapshot.get("active_item_state"),
		_empty_active_item_state(),
		"legacy Launch snapshot receives the explicit empty active-item default"
	)
	_suite.assert_equal(
		normalized_frame.get("digest"),
		ReplayRecorderScript.full_player_frame_digest(normalized_frame),
		"legacy Launch migration refreshes the frame digest"
	)
	_suite.assert_equal(
		normalized.get("terminal_digest"),
		ReplayRecorderScript.full_player_terminal_digest(normalized),
		"legacy Launch migration refreshes the terminal digest"
	)
	await _free_player(target)


func _spawn_launch_player(character_id: StringName, seed_value: int) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(
		player.configure_loadout({
			"schema_version": 1,
			"milestone": "LAUNCH",
			"character_id": str(character_id),
			"character_profile": _registry.call(
				"resolve_character_runtime_profile", character_id, &"LAUNCH"
			),
			"character_talents": [],
			"weapon_id": "sword",
			"weapon_profile": _registry.call(
				"resolve_weapon_runtime_profile", &"sword", &"LAUNCH"
			),
			"enabled_time_skills": [&"stop", &"rewind"],
			"difficulty": "normal",
			"seed": seed_value,
		}),
		"%s Launch Replay fixture configures" % str(character_id)
	)
	return player


func _frame_intents(frame: int) -> Dictionary:
	return {
		"dash": [],
		"time": [],
		"weapon": [],
		"character": [],
		"movement": Vector2.ZERO,
		"aim": Vector2.RIGHT,
		"meta": {
			"source": "character_runtime_replay_test",
			"target_frame": frame,
			"frame": frame,
		},
	}


func _empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


func _rehash_full_player_replay(replay: Dictionary) -> void:
	for frame_value: Variant in replay.get("frames", []) as Array:
		var frame := frame_value as Dictionary
		frame["digest"] = ReplayRecorderScript.full_player_frame_digest(frame)
	var frames := replay.get("frames", []) as Array
	if not frames.is_empty():
		replay["terminal_snapshot_digest"] = ReplayRecorderScript.value_digest(
			(frames[-1] as Dictionary).get("snapshot", {})
		)
	replay["terminal_digest"] = ReplayRecorderScript.full_player_terminal_digest(replay)


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
