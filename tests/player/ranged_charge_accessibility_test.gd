extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _original_persistent: Dictionary


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_original_persistent = GameState.persistent.duplicate(true)
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var bow: Node = player.bow_weapon

	_set_charge_mode("hold")
	player.handle_ranged_input_for_test(true, false)
	suite.assert_true(bow.is_charging(), "hold press starts ranged charge")
	player.handle_ranged_input_for_test(false, true)
	suite.assert_true(not bow.is_charging(), "hold release ends ranged charge")
	bow._process(1.0)

	_set_charge_mode("toggle")
	player.handle_ranged_input_for_test(true, false)
	suite.assert_true(bow.is_charging(), "first toggle press starts charge")
	player.handle_ranged_input_for_test(false, true)
	suite.assert_true(bow.is_charging(), "toggle release edge does not end charge")
	player.handle_ranged_input_for_test(true, false)
	suite.assert_true(not bow.is_charging(), "second toggle press releases charge")

	suite.assert_true(
		not player.try_action(&"ranged_attack"),
		"direct M1 ranged command remains gated outside the accessibility input path"
	)

	GameState.persistent = _original_persistent.duplicate(true)
	player.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _set_charge_mode(mode: String) -> void:
	var settings: Dictionary = GameState.normalized_settings()
	settings["ranged_charge_mode"] = mode
	GameState.persistent["settings"] = settings
