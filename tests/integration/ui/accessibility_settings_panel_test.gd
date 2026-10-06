extends Node

const AccessibilitySettingsPanelScene := preload("res://scenes/ui/accessibility_settings_panel.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const EXPECTED_CONTROL_TYPES := {
	"master_volume": "HSlider",
	"music_volume": "HSlider",
	"sfx_volume": "HSlider",
	"dialogue_volume": "HSlider",
	"master_muted": "CheckButton",
	"camera_shake_enabled": "CheckButton",
	"hit_flash_enabled": "CheckButton",
	"reduced_motion": "CheckButton",
	"text_scale": "OptionButton",
	"high_contrast_danger": "CheckButton",
	"subtitles_enabled": "CheckButton",
	"subtitle_scale": "OptionButton",
	"ranged_charge_mode": "OptionButton",
	"damage_received_multiplier": "OptionButton",
	"enemy_telegraph_scale": "OptionButton",
}

const CHANGED_VALUES := {
	"master_volume": 0.42,
	"music_volume": 0.33,
	"sfx_volume": 0.27,
	"dialogue_volume": 0.61,
	"master_muted": true,
	"camera_shake_enabled": false,
	"hit_flash_enabled": false,
	"reduced_motion": true,
	"text_scale": 1.5,
	"high_contrast_danger": true,
	"subtitles_enabled": false,
	"subtitle_scale": 1.25,
	"ranged_charge_mode": "toggle",
	"damage_received_multiplier": 0.6,
	"enemy_telegraph_scale": 1.5,
}

var _suite
var _original_save_path: String
var _original_persistent: Dictionary
var _test_root: String


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_original_save_path = GameState.save_path
	_original_persistent = GameState.persistent.duplicate(true)
	_test_root = _unique_test_root()
	_remove_tree(_test_root)
	GameState.save_path = _test_root.path_join("legacy.json")
	GameState.reset_persistent_data(true)
	get_window().size = Vector2i(640, 360)

	var restore_button := Button.new()
	restore_button.name = "RestoreButton"
	restore_button.focus_mode = Control.FOCUS_ALL
	add_child(restore_button)
	var panel := AccessibilitySettingsPanelScene.instantiate()
	panel.call("configure", restore_button)
	add_child(panel)
	await _frames(2)

	restore_button.grab_focus()
	panel.call("open_panel")
	await _frames(2)
	var panel_root := panel.get_node("SafeArea/PanelRoot") as Control
	var scroll := panel.get_node("SafeArea/PanelRoot/Layout/Scroll") as ScrollContainer
	_suite.assert_true(panel.visible, "accessibility settings panel opens")
	_suite.assert_true(panel_root.position.x >= 16.0 and panel_root.position.y >= 16.0, "panel respects the 16px safe-area origin")
	_suite.assert_true(panel_root.size.x <= 608.0 and panel_root.size.y <= 328.0, "panel fits the 640x360 16px safe area")
	_suite.assert_true(scroll != null, "settings rows use a ScrollContainer")
	_suite.assert_true(
		(panel.get_node("SafeArea/PanelRoot/Layout/AssistExplanation") as Label).text == tr("UI_ACCESSIBILITY_ASSIST_EXPLANATION"),
		"assist explanation uses neutral localized wording"
	)

	var controls: Array[Control] = []
	for setting_id: String in EXPECTED_CONTROL_TYPES:
		var control := panel.call("get_setting_control", setting_id) as Control
		_suite.assert_true(control != null, "%s has a setting control" % setting_id)
		if control == null:
			continue
		_suite.assert_equal(control.get_class(), EXPECTED_CONTROL_TYPES[setting_id], "%s uses the expected control type" % setting_id)
		_suite.assert_equal(control.focus_mode, Control.FOCUS_ALL, "%s participates in controller focus" % setting_id)
		controls.append(control)

	_suite.assert_equal(controls.size(), 15, "panel exposes all fifteen requested settings")
	if not controls.is_empty():
		var back_button := panel.get_node("SafeArea/PanelRoot/Layout/Footer/BackButton") as Button
		_suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[0], "opening focuses the first setting")
		_suite.assert_true(not controls[0].focus_neighbor_bottom.is_empty(), "controller focus ring links downward")
		var tabs := panel.find_child("SettingsTabs", true, false) as TabBar
		_suite.assert_true(tabs != null and tabs.focus_mode == Control.FOCUS_ALL, "category navigation is reachable by controller")
		_suite.assert_equal(controls[-1].focus_neighbor_bottom, controls[-1].get_path_to(tabs), "controller focus ring reaches categories after the final setting")
		_suite.assert_equal(tabs.focus_neighbor_bottom, tabs.get_path_to(back_button), "category navigation retains a reachable Back command")
		_suite.assert_equal(back_button.focus_neighbor_bottom, back_button.get_path_to(controls[0]), "controller focus ring wraps from Back to the first setting")

	for setting_id: String in CHANGED_VALUES:
		var control := panel.call("get_setting_control", setting_id) as Control
		_apply_value(control, CHANGED_VALUES[setting_id])
		await get_tree().process_frame
		_suite.assert_equal(GameState.get_setting(setting_id), CHANGED_VALUES[setting_id], "%s changes through GameState" % setting_id)

	panel.call("close_panel")
	await _frames(2)
	_suite.assert_true(not panel.visible, "close hides the settings panel")
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), restore_button, "closing restores the previous focus owner")

	GameState.persistent = {}
	_suite.assert_true(GameState.load_persistent(), "settings reload from persistent storage")
	for setting_id: String in CHANGED_VALUES:
		_suite.assert_equal(GameState.get_setting(setting_id), CHANGED_VALUES[setting_id], "%s survives reload" % setting_id)

	panel.queue_free()
	restore_button.queue_free()
	await get_tree().process_frame
	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	_remove_tree(_test_root)
	_suite.finish(get_tree())


func _apply_value(control: Control, value: Variant) -> void:
	if control is HSlider:
		(control as HSlider).value = float(value) * 100.0
		return
	if control is CheckButton:
		(control as CheckButton).button_pressed = bool(value)
		return
	if control is OptionButton:
		var option := control as OptionButton
		for index: int in range(option.item_count):
			if option.get_item_metadata(index) == value:
				option.select(index)
				option.item_selected.emit(index)
				return
		_suite.assert_true(false, "option contains requested value %s" % str(value))


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("accessibility_settings_panel_%d" % Time.get_ticks_usec())


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
