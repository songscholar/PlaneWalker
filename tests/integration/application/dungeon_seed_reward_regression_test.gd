extends Node

const RunnerScript := preload("res://tools/dungeon/dungeon_simulation_runner.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	for seed_value: int in [20261002, 20261006, 20261022, 20261024]:
		var runner = RunnerScript.new()
		var player: Node = PlayerScene.instantiate()
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		player.set_physics_process(false)
		player.get_node("TimeManager").set_process(false)
		player.get_node("RewindRecorder").set_process(false)
		var initialized: Dictionary = runner.initialize(runner.launch_config(seed_value), player)
		suite.assert_true(bool(initialized.get("ok", false)), "reward regression initializes seed %d" % seed_value)
		suite.assert_true(player.configure_loadout(runner.player_config()), "reward regression configures actual Player")
		var result: Dictionary = await runner.run_five_floors()
		suite.assert_equal(result.get("failures", []), [], "five-floor reward path commits and refreshes seed %d" % seed_value)
		suite.assert_true(bool(result.get("victory", false)), "reward regression reaches victory seed %d" % seed_value)
		player.queue_free()
		await get_tree().process_frame
	suite.finish(get_tree())
