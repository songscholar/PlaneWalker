extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const GAME_STATE_PATH := "res://autoload/game_state.gd"
const RUN_BUILD_STATE_PATH := "res://scripts/progression/run_build_state.gd"
const RUN_ORCHESTRATOR_PATH := "res://scripts/application/run_orchestrator.gd"
const RUN_STATE_PATH := "res://scripts/application/run_state.gd"
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


class CountingBuildState:
	extends RefCounted

	var base: RefCounted
	var application_count := 0
	var last_definition: Dictionary = {}

	func _init(source: RefCounted) -> void:
		base = source

	func apply_definition(definition: Dictionary) -> Dictionary:
		application_count += 1
		last_definition = definition.duplicate(true)
		return base.call("apply_definition", definition)

	func transaction_snapshot() -> Dictionary:
		return base.call("transaction_snapshot")


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
	_assert_build_definition_authority(suite)
	_test_build_definition_delegation(suite)
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


func _assert_build_definition_authority(suite) -> void:
	var build_source := _read_text(RUN_BUILD_STATE_PATH)
	var orchestrator_source := _read_text(RUN_ORCHESTRATOR_PATH)
	var state_source := _read_text(RUN_STATE_PATH)
	suite.assert_true(not build_source.is_empty(), "RunBuildState source is readable")
	suite.assert_true(not orchestrator_source.is_empty(), "RunOrchestrator source is readable")
	suite.assert_true(not state_source.is_empty(), "RunState source is readable")
	suite.assert_true(
		build_source.contains("func apply_definition("),
		"RunBuildState owns the single resolved-definition application boundary"
	)
	suite.assert_true(
		orchestrator_source.contains("_state.apply_reward_definition(definition)"),
		"RunOrchestrator delegates selected definitions through the RunState transaction boundary"
	)
	suite.assert_equal(
		state_source.count("build_state.apply_definition("), 1,
		"RunState has one resolved-definition application call to BuildState authority"
	)
	for legacy_route: String in [
		"build_state.record_item(",
		"build_state.record_blessing(",
		"build_state.record_curse(",
		"build_state.record_talent(",
	]:
		suite.assert_true(
			not orchestrator_source.contains(legacy_route),
			"RunOrchestrator no longer branches build scoring through %s" % legacy_route
		)


func _test_build_definition_delegation(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	var state: RefCounted = orchestrator.get("_state")
	var authority := CountingBuildState.new(state.get("build_state"))
	state.set("build_state", authority)
	var definition := {
		"id": "authority_item", "category": "item",
		"archetype": "freeze_burst", "effects": {"damage_multiplier": 1.25},
	}
	var applied: Dictionary = orchestrator.call("_record_selected_definition", definition)
	suite.assert_true(bool(applied.get("ok", false)), "wrapped reward delegation accepts a valid definition")
	suite.assert_equal(authority.application_count, 1, "wrapped reward delegates to BuildState exactly once")
	suite.assert_equal(authority.last_definition, definition, "wrapped reward preserves the complete resolved definition")
	var before := authority.transaction_snapshot()
	suite.assert_equal(before["reward_history"], [definition], "only BuildState records the resolved reward")
	var empty_result: Dictionary = orchestrator.call("_record_selected_definition", {})
	suite.assert_true(bool(empty_result.get("ok", false)), "empty compatibility resolution remains a no-op")
	suite.assert_equal(authority.application_count, 1, "empty compatibility resolution never invokes BuildState")
	var rejected: Dictionary = orchestrator.call("_record_selected_definition", {
		"id": "invalid_reward", "category": "unknown", "effects": {},
	})
	suite.assert_true(not bool(rejected.get("ok", false)), "wrapped delegation propagates authority rejection")
	suite.assert_equal(authority.application_count, 2, "rejected definition is checked once by BuildState")
	suite.assert_equal(authority.transaction_snapshot(), before, "authority rejection preserves the complete build snapshot")


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
