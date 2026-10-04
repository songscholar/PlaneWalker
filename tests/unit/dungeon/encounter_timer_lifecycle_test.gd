extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Runner := preload("res://scripts/dungeon/encounter_runner.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var root := Node2D.new()
	add_child(root)
	var runner := Runner.new()
	root.add_child(runner)
	runner.process_mode = Node.PROCESS_MODE_PAUSABLE
	runner.configure(root)
	var warnings: Array = []
	var spawns: Array = []
	runner.spawn_warning_requested.connect(func(spawn: Dictionary, _duration: float): warnings.append(spawn.id))
	runner.spawn_requested.connect(func(spawn: Dictionary): spawns.append(spawn.id))
	var encounter := {"id": "timer-room", "waves": [{"id": "timer-wave", "delay_seconds": 0.08, "telegraph_seconds": 0.2, "spawns": [{"id": "timer-spawn", "enemy_id": "chaser"}]}]}
	runner.start_encounter(encounter, 1, 1)
	get_tree().paused = true
	await get_tree().process_frame
	suite.assert_equal(runner.find_children("*", "Timer", false, false).size(), 1, "each native phase owns one cancellable Timer")
	await get_tree().create_timer(0.15, true).timeout
	suite.assert_true(warnings.is_empty() and spawns.is_empty(), "paused gameplay cannot consume delay or telegraph time")
	get_tree().paused = false
	await get_tree().create_timer(0.1).timeout
	suite.assert_equal(warnings, ["timer-spawn"], "unpaused authored delay publishes one warning")
	suite.assert_true(spawns.is_empty(), "warning lasts its full authored duration")
	runner.cancel()
	await get_tree().process_frame
	suite.assert_equal(runner.find_children("*", "Timer", false, false).size(), 0, "cancel retires the owned timer immediately")
	root.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	suite.assert_true(spawns.is_empty(), "retired encounter cannot publish a delayed spawn")
	suite.finish(get_tree())
