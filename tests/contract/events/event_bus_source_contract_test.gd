extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PRODUCTION_ROOTS: Array[String] = [
	"res://autoload",
	"res://scripts",
]
const FORBIDDEN: Array[String] = [
	"EventBus.publish(",
	"EventBus.publish_deferred(",
	"EventBus.subscribe(",
	"EventBus.unsubscribe(",
	"var _handlers",
	"var _deferred_events",
	"func publish(",
	"func publish_deferred(",
	"func subscribe(",
	"func unsubscribe(",
]
const STATE_CHANGING_PATHS: Array[String] = [
	"res://scripts/application/run_orchestrator.gd",
	"res://scripts/application/run_runtime_facade.gd",
	"res://scripts/application/run_runtime_host.gd",
	"res://scripts/dungeon/encounter_runner.gd",
	"res://scripts/dungeon/room_controller.gd",
	"res://scripts/dungeon/room_runtime.gd",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var signal_names: Array[StringName] = []
	for signal_definition: Dictionary in EventBus.get_signal_list():
		signal_names.append(StringName(str(signal_definition.get("name", ""))))
	for required_signal: StringName in [
		&"weapon_action_committed",
		&"weapon_resource_changed",
		&"weapon_hit_confirmed",
	]:
		suite.assert_true(signal_names.has(required_signal), "EventBus exposes typed %s fact" % required_signal)
	var paths: Array[String] = []
	for root: String in PRODUCTION_ROOTS:
		_collect_gdscript_paths(root, paths)
	paths.sort()
	suite.assert_true(not paths.is_empty(), "event source contract discovers production GDScript")
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path)
		suite.assert_true(not source.is_empty(), "%s is readable" % path)
		for token: String in FORBIDDEN:
			suite.assert_true(
				not source.contains(token),
				"%s contains no generic EventBus token: %s" % [path, token]
			)

	for path: String in STATE_CHANGING_PATHS:
		var source := FileAccess.get_file_as_string(path)
		suite.assert_true(not source.is_empty(), "%s is readable" % path)
		for line: String in source.split("\n"):
			var stripped := line.strip_edges()
			if stripped.contains("EventBus.") and stripped.contains(".connect("):
				suite.assert_true(
					false,
					"%s has no state-changing EventBus connection: %s" % [path, stripped]
				)

	suite.finish(get_tree())


func _collect_gdscript_paths(root: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			var path := root.path_join(entry)
			if directory.current_is_dir():
				_collect_gdscript_paths(path, paths)
			elif entry.ends_with(".gd"):
				paths.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
