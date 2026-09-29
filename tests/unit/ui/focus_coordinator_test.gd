extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	await _test_nested_modal_restore(suite)
	await _test_invalid_controls_and_escape_recovery(suite)
	await _test_non_top_close_and_freed_owner(suite)
	_test_link_ring(suite)
	suite.finish(get_tree())


func _test_nested_modal_restore(suite) -> void:
	var fixture := _fixture()
	var base_button: Button = fixture["base_button"]
	var selection: Control = fixture["selection"]
	var option_one: Button = fixture["option_one"]
	var pause: Control = fixture["pause"]
	var resume_button: Button = fixture["resume_button"]
	base_button.grab_focus()
	FocusCoordinator.open_scope(selection, option_one)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), option_one, "selection receives initial focus")
	FocusCoordinator.open_scope(pause, resume_button)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), resume_button, "pause takes focus")
	FocusCoordinator.close_scope(pause)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), option_one, "closing pause restores selection")
	FocusCoordinator.close_scope(selection)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), base_button, "closing selection restores base focus")
	fixture["root"].queue_free()
	await get_tree().process_frame


func _test_invalid_controls_and_escape_recovery(suite) -> void:
	var fixture := _fixture()
	var selection: Control = fixture["selection"]
	var option_one: Button = fixture["option_one"]
	var option_two: Button = fixture["option_two"]
	var outside: Button = fixture["base_button"]
	option_one.visible = false
	FocusCoordinator.open_scope(selection, option_one)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), option_two, "hidden initial focus falls back to a valid descendant")
	option_two.disabled = true
	outside.grab_focus()
	FocusCoordinator.recover(selection, option_one)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), null, "recovery refuses hidden and disabled controls")
	option_one.visible = true
	FocusCoordinator.recover(selection, option_one)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), option_one, "recovery returns escaped focus to the active scope")
	FocusCoordinator.close_scope(selection)
	fixture["root"].queue_free()
	await get_tree().process_frame


func _test_non_top_close_and_freed_owner(suite) -> void:
	var fixture := _fixture()
	var base_button: Button = fixture["base_button"]
	var selection: Control = fixture["selection"]
	var option_one: Button = fixture["option_one"]
	var pause: Control = fixture["pause"]
	var resume_button: Button = fixture["resume_button"]
	base_button.grab_focus()
	FocusCoordinator.open_scope(selection, option_one)
	await get_tree().process_frame
	FocusCoordinator.open_scope(pause, resume_button)
	await get_tree().process_frame
	FocusCoordinator.close_scope(selection)
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), resume_button, "closing a non-top scope preserves top focus")
	base_button.queue_free()
	FocusCoordinator.close_scope(pause)
	await get_tree().process_frame
	suite.assert_equal(FocusCoordinator.active_scope(), null, "closing top scope tolerates a freed previous owner")
	fixture["root"].queue_free()
	await get_tree().process_frame


func _test_link_ring(suite) -> void:
	var fixture := _fixture()
	var option_one: Button = fixture["option_one"]
	var option_two: Button = fixture["option_two"]
	FocusCoordinator.link_ring([option_one, option_two], true)
	suite.assert_equal(option_one.focus_neighbor_right, option_one.get_path_to(option_two), "horizontal ring links forward")
	suite.assert_equal(option_one.focus_neighbor_left, option_one.get_path_to(option_two), "horizontal ring wraps backward")
	suite.assert_equal(option_two.focus_next, option_two.get_path_to(option_one), "ring wraps focus_next")
	suite.assert_equal(option_one.focus_previous, option_one.get_path_to(option_two), "ring wraps focus_previous")
	fixture["root"].queue_free()


func _fixture() -> Dictionary:
	var root := Control.new()
	root.name = "FocusFixture"
	add_child(root)
	var base_button := Button.new()
	base_button.name = "BaseButton"
	root.add_child(base_button)
	var selection := VBoxContainer.new()
	selection.name = "Selection"
	root.add_child(selection)
	var option_one := Button.new()
	option_one.name = "OptionOne"
	selection.add_child(option_one)
	var option_two := Button.new()
	option_two.name = "OptionTwo"
	selection.add_child(option_two)
	var pause := VBoxContainer.new()
	pause.name = "Pause"
	root.add_child(pause)
	var resume_button := Button.new()
	resume_button.name = "ResumeButton"
	pause.add_child(resume_button)
	return {
		"root": root,
		"base_button": base_button,
		"selection": selection,
		"option_one": option_one,
		"option_two": option_two,
		"pause": pause,
		"resume_button": resume_button,
	}
