extends Node

const InputRemapPanelScene := preload("res://scenes/ui/input_remap_panel.tscn")
const InputRemapServiceScript := preload("res://scripts/input/input_remap_service.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _test_root: String
var _default_profile: Dictionary


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_root = _unique_test_root()
	_remove_tree(_test_root)
	var service = InputRemapServiceScript.new()
	service.configure(_test_root)
	_suite.assert_true(bool(service.load_or_defaults().get("ok", false)), "remap fixture loads defaults")
	_default_profile = service.snapshot_profile()

	var restore_button := Button.new()
	restore_button.name = "RestoreButton"
	restore_button.text = "Restore"
	restore_button.focus_mode = Control.FOCUS_ALL
	add_child(restore_button)
	var panel := InputRemapPanelScene.instantiate()
	panel.call("configure", service, restore_button)
	add_child(panel)
	await get_tree().process_frame

	panel.call("open_panel")
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: VBoxContainer = panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows")
	_suite.assert_equal(rows.get_child_count(), 15, "panel renders the complete schema-three remap profile")
	for semantic_row: String in [
		"Row_weapon_primary", "Row_weapon_secondary", "Row_weapon_utility",
		"Row_weapon_skill", "Row_weapon_ultimate", "Row_time_slot_1", "Row_time_slot_2",
		"Row_character_skill",
	]:
		_suite.assert_true(rows.has_node(semantic_row), "panel exposes semantic remap row %s" % semantic_row)
	_suite.assert_true(not rows.has_node("Row_attack"), "legacy Attack row leaves the schema two UI")
	_suite.assert_equal(
		panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_weapon_primary/ActionLabel").text,
		tr("INPUT_ACTION_WEAPON_PRIMARY"),
		"semantic primary row uses its localized display name"
	)
	_suite.assert_equal(
		panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_time_slot_1/ActionLabel").text,
		tr("INPUT_ACTION_TIME_SLOT_1"),
		"time slot row uses its localized display name"
	)
	_suite.assert_equal(
		panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_character_skill/ActionLabel").text,
		tr("INPUT_ACTION_CHARACTER_SKILL"),
		"character skill row uses its localized display name"
	)
	_suite.assert_true(panel.get_node("SafeArea/PanelRoot").size.x <= 608.0, "panel fits horizontal safe area")
	_suite.assert_true(panel.get_node("SafeArea/PanelRoot").size.y <= 328.0, "panel fits vertical safe area")
	var first_binding := rows.get_child(0).get_node("KeyboardMouseBinding") as Button
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), first_binding, "opening focuses the first binding")
	var move_up_controller := panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_move_up/ControllerBinding") as Button
	_suite.assert_equal(move_up_controller.text, "Left Stick Up / D-pad Up", "controller labels use readable directional names")

	var attack_controller := panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_weapon_primary/ControllerBinding") as Button
	var heavy_controller := panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_weapon_secondary/ControllerBinding") as Button
	attack_controller.pressed.emit()
	await get_tree().process_frame
	_suite.assert_true(panel.get_node("CaptureOverlay").visible, "binding button opens capture overlay")
	Input.parse_input_event(_joy_button(JOY_BUTTON_Y))
	await get_tree().process_frame
	_suite.assert_equal(attack_controller.text, "Y", "captured Y remaps Primary controller")
	_suite.assert_equal(heavy_controller.text, "X", "conflict swap moves X to Secondary")
	_suite.assert_equal(panel.get_node("SafeArea/PanelRoot/Layout/StatusLabel").text, tr("UI_BINDING_CONFLICT_SWAPPED"), "swap is disclosed")

	var before_cancel := service.snapshot_profile()
	attack_controller.pressed.emit()
	await get_tree().process_frame
	Input.parse_input_event(_joy_button(JOY_BUTTON_B))
	await get_tree().process_frame
	_suite.assert_true(not panel.get_node("CaptureOverlay").visible, "B cancels capture")
	_suite.assert_equal(service.snapshot_profile(), before_cancel, "capture cancellation does not mutate bindings")

	panel.get_node("SafeArea/PanelRoot/Layout/Footer/ResetAllButton").pressed.emit()
	await get_tree().process_frame
	_suite.assert_equal(service.snapshot_profile(), _default_profile, "Reset All restores the Task 1 defaults")
	_suite.assert_equal(attack_controller.text, "X", "Reset All refreshes Primary label")
	_suite.assert_equal(heavy_controller.text, "Y", "Reset All refreshes Secondary label")

	restore_button.grab_focus()
	await get_tree().process_frame
	panel.call("open_panel")
	await get_tree().process_frame
	panel.call("close_panel")
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), restore_button, "closing restores the pause-menu owner")

	panel.queue_free()
	restore_button.queue_free()
	await get_tree().process_frame
	_remove_tree(_test_root)
	_restore_input_map()
	_suite.finish(get_tree())


func _joy_button(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button_index
	event.pressed = true
	return event


func _restore_input_map() -> void:
	var restore = InputRemapServiceScript.new()
	restore.configure(_unique_test_root())
	restore.load_or_defaults()


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("input_remap_panel_%d" % Time.get_ticks_usec())


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
