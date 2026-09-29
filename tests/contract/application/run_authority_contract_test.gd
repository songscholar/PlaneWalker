extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const GAME_STATE_PATH := "res://autoload/game_state.gd"
const PRODUCTION_ROOTS: Array[String] = [
	"res://autoload",
	"res://scripts",
	"res://scenes",
	"res://tools/m1",
]
const FORBIDDEN_GAME_STATE_TOKENS: Array[String] = [
	"enum GamePhase",
	"var phase:",
	"var current_floor:",
	"var current_room:",
	"var run_seed:",
	"var run_timer:",
	"var death_count:",
	"var current_run:",
	"var last_run_result:",
	"var build_state:",
	"func _process(",
	"func start_run(",
	"func end_run(",
	"func fail_run(",
	"func add_run_",
	"func set_curse_offer_pending(",
	"func is_curse_offer_pending(",
	"func set_current_room_type(",
	"func get_current_room_type(",
	"func get_dominant_archetype(",
	"func get_build_state_snapshot(",
	"func get_run_kill_count(",
	"func set_phase(",
	"RunBuildStateScript",
	"EventBus.",
]
const FORBIDDEN_PRODUCTION_TOKENS: Array[String] = [
	"GameState.phase",
	"GameState.current_floor",
	"GameState.current_room",
	"GameState.run_seed",
	"GameState.run_timer",
	"GameState.current_run",
	"GameState.last_run_result",
	"GameState.build_state",
	"GameState.set_phase",
	"GameState.start_run",
	"GameState.end_run",
	"GameState.fail_run",
	"LegacyRunAdapter",
	"allow_legacy_runtime",
	"RewardSelection",
	"CurseSelection",
	"EventSelection",
	"CombatHUD",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var source := _read_text(GAME_STATE_PATH)
	suite.assert_true(not source.is_empty(), "GameState source is readable")
	for token: String in FORBIDDEN_GAME_STATE_TOKENS:
		suite.assert_true(
			not source.contains(token),
			"GameState owns no live-run authority token: %s" % token
		)
	suite.assert_true(
		source.contains("func record_run_summary(result: Dictionary) -> bool:"),
		"GameState exposes only a narrow persisted run-summary helper"
	)
	_assert_production_authority(suite)
	_test_profile_summary_persistence(suite)
	suite.finish(get_tree())


func _assert_production_authority(suite) -> void:
	var paths: Array[String] = []
	for root: String in PRODUCTION_ROOTS:
		_collect_source_paths(root, paths)
	paths.sort()
	suite.assert_true(not paths.is_empty(), "run-authority contract discovers production sources")
	for path: String in paths:
		var source := _read_text(path)
		for token: String in FORBIDDEN_PRODUCTION_TOKENS:
			suite.assert_true(
				not source.contains(token),
				"%s contains no retired run-authority token: %s" % [path, token]
			)


func _test_profile_summary_persistence(suite) -> void:
	var original_save_path: String = GameState.save_path
	var original_persistent: Dictionary = GameState.persistent.duplicate(true)
	var test_root := _unique_test_root()
	GameState.save_path = test_root.path_join("legacy.json")
	GameState.reset_persistent_data(true)
	var result := {
		"result": "floor_cleared",
		"floor": 2,
		"rooms_cleared": 5,
		"current_room": 6,
		"run_time": 42.5,
		"kills": 9,
		"rewards": [{"id": "echo_blade"}],
		"blessings": [{"id": "still_water"}],
		"talent_choices": [{"id": "second_hand"}],
		"curses": [{"id": "glass_clock"}],
	}
	suite.assert_true(GameState.record_run_summary(result), "profile summary saves through its narrow helper")
	result["rewards"][0]["id"] = "mutated"
	suite.assert_equal(GameState.persistent.get("runs_completed"), 1, "profile summary increments completed runs")
	suite.assert_equal(GameState.persistent.get("victories"), 1, "profile summary records a completed floor")
	suite.assert_equal(GameState.persistent.get("best_rooms_cleared"), 5, "profile summary records the best room count")
	suite.assert_equal(
		GameState.persistent.get("last_run_summary", {}).get("rewards", [])[0].get("id"),
		"echo_blade",
		"profile summary owns a deep copy of terminal result collections"
	)
	GameState.persistent = {}
	suite.assert_true(GameState.load_persistent(), "profile summary reloads from the compatibility save service")
	suite.assert_equal(GameState.persistent.get("last_run_summary", {}).get("kills"), 9.0, "profile summary fields survive reload")

	GameState.save_path = original_save_path
	GameState.persistent = original_persistent
	_remove_tree(test_root)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var contents := file.get_as_text()
	file.close()
	return contents


func _collect_source_paths(root: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			var path := root.path_join(entry)
			if directory.current_is_dir():
				_collect_source_paths(path, output)
			elif entry.get_extension() in ["gd", "tscn"]:
				output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("run_authority_contract_%d" % Time.get_ticks_usec())


func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			_remove_tree(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
