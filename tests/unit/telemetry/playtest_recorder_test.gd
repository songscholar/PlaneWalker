extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlaytestRecorderScript := preload("res://scripts/telemetry/playtest_recorder.gd")
const PlaytestSessionSchemaScript := preload("res://scripts/telemetry/playtest_session_schema.gd")
const PlaytestSerializerScript := preload("res://scripts/telemetry/playtest_serializer.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_human_session_recording(suite)
	_test_synthetic_provenance_cannot_be_overridden(suite)
	_test_serializer_round_trip(suite)
	_test_serializer_appends_jsonl_records(suite)
	suite.finish(get_tree())


func _test_human_session_recording(suite) -> void:
	var recorder = PlaytestRecorderScript.new()
	var started: Dictionary = recorder.start_session({
		"source": "human",
		"collection_method": "observed_playtest",
		"build_version": "0.4.0-dev",
		"commit": "a1b2c3d4",
		"content_version": "m1-wave4",
		"seed": 4242,
		"input_device": "keyboard_mouse",
		"started_at_utc": "2026-09-28T08:00:00Z",
	})
	suite.assert_true(bool(started.get("ok", false)), "valid metadata starts a session")

	recorder.record_room({
		"room_id": "combat_01",
		"room_type": "combat",
		"room_index": 0,
		"entered_at_ms": 0,
		"completed_at_ms": 45000,
		"result": "cleared",
	})
	recorder.record_damage(480, 25, 12, 2)
	recorder.record_build_choice("item", "volatile_clock", 0, 46000)
	recorder.record_failure("near_death", "combat", 0, 40000)
	var finished: Dictionary = recorder.finish_session({
		"outcome": "completed",
		"floor": 1,
		"room_index": 4,
		"duration_ms": 300000,
		"cause": "boss_defeated",
		"ended_at_utc": "2026-09-28T08:05:00Z",
	})

	suite.assert_true(bool(finished.get("ok", false)), "complete session validates")
	var session: Dictionary = finished.get("session", {})
	suite.assert_true(str(session.get("session_id", "")).begins_with("pws_"), "session id is anonymous")
	suite.assert_equal(session.get("schema_version"), "1.0.0", "session schema is versioned")
	suite.assert_equal(session.get("evidence", {}).get("synthetic"), false, "human recording is marked non-synthetic")
	suite.assert_equal(session.get("rooms", [])[0].get("duration_ms"), 45000, "room duration is derived")
	suite.assert_equal(session.get("damage", {}).get("taken"), 25, "damage aggregate is recorded")
	suite.assert_equal(session.get("build_choices", [])[0].get("choice_id"), "volatile_clock", "build choice is recorded")
	suite.assert_equal(session.get("terminal_result", {}).get("outcome"), "completed", "terminal result is recorded")
	suite.assert_equal(PlaytestSessionSchemaScript.validate(session), [], "recorded session matches schema")


func _test_synthetic_provenance_cannot_be_overridden(suite) -> void:
	var recorder = PlaytestRecorderScript.new()
	var result: Dictionary = recorder.start_session({
		"source": "synthetic",
		"synthetic": false,
		"collection_method": "automated_fixture",
		"build_version": "0.4.0-dev",
		"commit": "a1b2c3d4",
		"content_version": "m1-wave4",
		"seed": 7,
		"input_device": "automation",
		"started_at_utc": "2026-09-28T08:00:00Z",
	})

	suite.assert_true(bool(result.get("ok", false)), "synthetic session can start")
	suite.assert_equal(
		recorder.snapshot().get("evidence", {}).get("synthetic"),
		true,
		"source controls synthetic marker instead of caller override"
	)


func _test_serializer_round_trip(suite) -> void:
	var session := {
		"schema_version": "1.0.0",
		"session_id": "pws_00000000000000000000000000000001",
		"evidence": {"source": "synthetic", "synthetic": true, "collection_method": "automated_fixture"},
	}
	var line: String = PlaytestSerializerScript.to_json_line(session)
	var parsed: Dictionary = PlaytestSerializerScript.from_json_line(line)
	suite.assert_equal(parsed.get("ok"), true, "JSONL line parses")
	suite.assert_equal(parsed.get("value"), session, "JSONL serialization round trips")
	suite.assert_equal(
		PlaytestSerializerScript.from_json_line("not json").get("ok"),
		false,
		"invalid JSONL is rejected"
	)


func _test_serializer_appends_jsonl_records(suite) -> void:
	var test_data_dir := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if test_data_dir.is_empty():
		test_data_dir = OS.get_temp_dir().path_join("planewalker-tests")
	var path := test_data_dir.path_join("playtest_recorder_test_%d.jsonl" % Time.get_ticks_usec())
	var absolute_path := path
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	var first := {"session_id": "pws_00000000000000000000000000000001"}
	var second := {"session_id": "pws_00000000000000000000000000000002"}

	var first_write: Dictionary = PlaytestSerializerScript.append_json_line(path, first)
	var second_write: Dictionary = PlaytestSerializerScript.append_json_line(path, second)

	suite.assert_equal(
		first_write.get("ok"),
		true,
		"first JSONL record appends: result=%s path=%s" % [first_write, absolute_path]
	)
	suite.assert_equal(
		second_write.get("ok"),
		true,
		"second JSONL record appends: result=%s path=%s" % [second_write, absolute_path]
	)
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "JSONL output can be opened")
	if file != null:
		var lines := file.get_as_text().strip_edges().split("\n")
		suite.assert_equal(lines.size(), 2, "each appended session occupies one line")
		file.close()
	DirAccess.remove_absolute(absolute_path)
