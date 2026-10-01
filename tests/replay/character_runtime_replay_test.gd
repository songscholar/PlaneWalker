extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const LAUNCH_SCHEMA_VERSION := 4
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
			"%s Launch snapshot uses Player Replay schema 4" % label
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
			"%s Launch Replay root uses schema 4" % label
		)
		for frame_value: Variant in replay.get("frames", []) as Array:
			var frame := frame_value as Dictionary
			_suite.assert_equal(
				int(frame.get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s Launch Replay frame uses schema 4" % label
			)
			_suite.assert_equal(
				int((frame.get("snapshot", {}) as Dictionary).get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s embedded Launch snapshot uses schema 4" % label
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


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
