extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Remap := preload("res://scripts/input/input_remap_service.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/onboarding/tutorial_projector.gd") as Script
	suite.assert_true(implementation != null, "tutorial projector reads current InputMap bindings")
	if implementation != null:
		_test_bindings(implementation)
	suite.finish(get_tree())


func _test_bindings(implementation: Script) -> void:
	var service := Remap.new()
	service.configure()
	var projector: RefCounted = implementation.new()
	suite.assert_true(projector.configure(service).ok, "projector binds real input label service")
	var movement: Dictionary = projector.project(["move", "dash"], "keyboard_mouse", "rewind")
	suite.assert_true(movement.ok, "semantic actions project with keyboard family")
	if movement.ok:
		suite.assert_equal(movement.context.actions[0].bindings.size(), 4, "movement shows four actual direction bindings")
	var saved := InputMap.action_get_events(&"weapon_primary")
	InputMap.action_erase_events(&"weapon_primary")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	InputMap.action_add_event(&"weapon_primary", key)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_Y
	InputMap.action_add_event(&"weapon_primary", button)
	var keyboard: Dictionary = projector.project(["weapon_primary"], "keyboard_mouse", "stop")
	var controller: Dictionary = projector.project(["weapon_primary"], "controller", "stop")
	suite.assert_true(keyboard.ok and controller.ok, "both input families project after InputMap remap")
	if keyboard.ok and controller.ok:
		suite.assert_equal(keyboard.context.actions[0].bindings[0].labels, ["P"], "keyboard hint follows actual remapped key")
		suite.assert_equal(controller.context.actions[0].bindings[0].labels, ["Y"], "controller hint follows actual remapped button")
	InputMap.action_erase_events(&"weapon_primary")
	for event: InputEvent in saved:
		InputMap.action_add_event(&"weapon_primary", event)
	var time: Dictionary = projector.project(["time_slot_1", "boss_conversion"], "controller", "rift")
	suite.assert_true(time.ok, "time and scene facts project without synthetic controls")
	if time.ok:
		suite.assert_equal(time.context.actions[0].ability_id, "rift", "time hint carries selected first-slot ability")
		suite.assert_equal(time.context.actions[0].bindings[0].action_id, "time_slot_1", "time label uses the actual remappable slot")
		suite.assert_true(time.context.actions[1].bindings.is_empty(), "Boss conversion fact invents no keyboard key")
	suite.assert_true(not projector.project(["fake"], "keyboard_mouse", "stop").ok, "unknown semantic control refuses")
	suite.assert_true(not projector.project(["dash"], "mobile", "stop").ok, "unknown family refuses")
	suite.assert_true(not projector.project(["time_slot_1"], "controller", "fake").ok, "unknown first time ability refuses")
