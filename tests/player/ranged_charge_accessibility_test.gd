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
	suite.assert_true(player.configure_loadout({
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
	}), "accessibility test explicitly equips Bow")
	suite.assert_true(
		player.weapon_action_coordinator != null,
		"accessible Bow input uses the shared weapon coordinator"
	)

	_set_charge_mode("hold")
	player.handle_ranged_input_for_test(true, false)
	var hold_pressed: Dictionary = player.weapon_presentation_snapshot()
	var hold_token := int(hold_pressed.get("token", 0))
	suite.assert_equal(hold_pressed.get("phase"), "HOLD", "hold press starts coordinator charge")
	suite.assert_true(hold_token > 0, "hold press allocates one action token")
	_advance(player, 9)
	player.handle_ranged_input_for_test(false, true)
	var hold_released: Dictionary = player.weapon_presentation_snapshot()
	suite.assert_equal(hold_released.get("phase"), "WINDUP", "hold release finalizes charge")
	suite.assert_equal(int(hold_released.get("token", 0)), hold_token, "hold release preserves the action token")
	player.cancel_transient_actions()

	_set_charge_mode("toggle")
	player.handle_ranged_input_for_test(true, false)
	var toggle_pressed: Dictionary = player.weapon_presentation_snapshot()
	var toggle_token := int(toggle_pressed.get("token", 0))
	suite.assert_equal(toggle_pressed.get("phase"), "HOLD", "first toggle press starts coordinator charge")
	player.handle_ranged_input_for_test(false, true)
	var toggle_physical_release: Dictionary = player.weapon_presentation_snapshot()
	suite.assert_equal(toggle_physical_release.get("phase"), "HOLD", "toggle physical release stays silent")
	suite.assert_equal(
		int(toggle_physical_release.get("token", 0)),
		toggle_token,
		"toggle physical release preserves the charge token"
	)
	_advance(player, 9)
	player.handle_ranged_input_for_test(true, false)
	var toggle_released: Dictionary = player.weapon_presentation_snapshot()
	suite.assert_equal(toggle_released.get("phase"), "WINDUP", "second toggle press releases charge")
	suite.assert_equal(int(toggle_released.get("token", 0)), toggle_token, "toggle release preserves the action token")
	player.cancel_transient_actions()

	suite.assert_true(
		player.try_action(&"ranged_attack"),
		"equipped Bow uses the same authoritative ranged action path"
	)
	suite.assert_equal(
		player.weapon_presentation_snapshot().get("phase"),
		"HOLD",
		"authoritative ranged action path enters shared HOLD"
	)

	GameState.persistent = _original_persistent.duplicate(true)
	player.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _set_charge_mode(mode: String) -> void:
	var settings: Dictionary = GameState.normalized_settings()
	settings["ranged_charge_mode"] = mode
	GameState.persistent["settings"] = settings


func _advance(player: Node, frames: int) -> void:
	for _frame: int in range(frames):
		player.advance_action_frame()
