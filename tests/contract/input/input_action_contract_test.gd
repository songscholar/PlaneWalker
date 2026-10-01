extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const InputActionContractScript := preload("res://scripts/input/input_action_contract.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var missing_bindings: Array[Dictionary] = InputActionContractScript.missing_required_bindings()
	_suite.assert_equal(
		missing_bindings,
		[],
		"every required action has keyboard/mouse and controller bindings"
	)
	_suite.assert_equal(
		InputActionContractScript.missing_semantic_bindings(),
		[],
		"every semantic weapon/time/character slot has keyboard/mouse and controller bindings"
	)
	for retired_time_action: StringName in [
		&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate",
	]:
		_suite.assert_true(
			not InputActionContractScript.required_actions().has(retired_time_action),
			"fixed legacy time action is not a current binding requirement: %s" % retired_time_action
		)
		_suite.assert_true(
			InputActionContractScript.legacy_profile_actions().has(retired_time_action),
			"schema-one compatibility retains legacy action identity: %s" % retired_time_action
		)

	var expected_controller_bindings := {
		&"move_up": ["axis:1:-1", "button:11"],
		&"move_down": ["axis:1:1", "button:12"],
		&"move_left": ["axis:0:-1", "button:13"],
		&"move_right": ["axis:0:1", "button:14"],
		&"attack": ["button:2"],
		&"heavy_attack": ["button:3"],
		&"ranged_attack": ["axis:5:1"],
		&"dash": ["button:1"],
		&"time_stop": ["button:9"],
		&"time_rewind": ["button:10"],
		&"time_rift": ["axis:4:1"],
		&"time_accelerate": ["button:8"],
		&"interact": ["button:0"],
		&"pause": ["button:6"],
	}
	var expected_semantic_controller_bindings := {
		&"weapon_primary": ["button:2"],
		&"weapon_secondary": ["button:3"],
		&"weapon_utility": ["button:4"],
		&"weapon_skill": ["button:5"],
		&"weapon_ultimate": ["button:7"],
		&"time_slot_1": ["button:9"],
		&"time_slot_2": ["button:10"],
		&"character_skill": ["button:8"],
		&"active_item": ["button:15"],
	}
	_suite.assert_true(
		InputActionContractScript.semantic_actions().has(&"active_item"),
		"active item is a first-class semantic action"
	)
	for action: StringName in expected_controller_bindings:
		_suite.assert_equal(
			InputActionContractScript.controller_binding_ids(action),
			expected_controller_bindings[action],
			"%s keeps its default controller grammar" % action
		)
	for action: StringName in expected_semantic_controller_bindings:
		_suite.assert_equal(
			InputActionContractScript.controller_binding_ids(action),
			expected_semantic_controller_bindings[action],
			"%s has a stable semantic controller binding" % action
		)

	for movement_action: StringName in [
		&"move_up",
		&"move_down",
		&"move_left",
		&"move_right",
	]:
		_suite.assert_close(
			InputMap.action_get_deadzone(movement_action),
			0.25,
			"%s uses the shared analog deadzone" % movement_action
		)

	_suite.finish(get_tree())
