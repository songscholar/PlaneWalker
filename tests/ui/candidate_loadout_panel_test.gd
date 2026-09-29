extends Node

const CandidateLoadoutPanelScene := preload("res://scenes/ui/candidate_loadout_panel.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const EXPECTED_PRESETS := [
	{
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
	},
	{
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
	},
	{
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "accelerate"],
	},
]

var _suite
var _received_configs: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var original_locale := str(TranslationServer.get_locale())
	var original_window_size := get_window().size
	get_window().size = Vector2i(640, 360)
	TranslationServer.set_locale("en")

	var restore_button := Button.new()
	restore_button.name = "RestoreButton"
	restore_button.focus_mode = Control.FOCUS_ALL
	add_child(restore_button)
	var panel := CandidateLoadoutPanelScene.instantiate() as Control
	panel.call("configure", restore_button)
	panel.connect("candidate_requested", _on_candidate_requested)
	add_child(panel)
	await _frames(2)

	var panel_root := panel.get_node("SafeArea/Center/PanelRoot") as Control
	var title_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/TitleLabel") as Label
	var warning_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/WarningLabel") as Label
	var status_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/StatusLabel") as Label
	var buttons: Array[Button] = [
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/BowButton") as Button,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/RiftButton") as Button,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/AccelerateButton") as Button,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/BackButton") as Button,
	]

	_suite.assert_true(not panel.visible, "candidate panel starts hidden")
	_suite.assert_true(title_label.text.contains("Candidate"), "English title explicitly labels the Candidate route")
	_suite.assert_true(warning_label.text.contains("not formally promoted"), "English warning says candidates are not promoted")

	restore_button.grab_focus()
	panel.call("open_panel")
	await _frames(2)
	_suite.assert_true(panel.visible, "candidate panel opens")
	var panel_rect := panel_root.get_global_rect()
	_suite.assert_true(panel_rect.position.x >= 16.0 and panel_rect.position.y >= 16.0, "candidate panel respects the 16px safe area")
	_suite.assert_true(panel_rect.end.x <= 624.0 and panel_rect.end.y <= 344.0, "candidate panel fits the 640x360 safe area")
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), buttons[0], "opening focuses Bow candidate")
	for index: int in range(buttons.size()):
		var next := buttons[(index + 1) % buttons.size()]
		_suite.assert_equal(
			buttons[index].focus_neighbor_bottom,
			buttons[index].get_path_to(next),
			"candidate focus ring links button %d downward" % index
		)

	for index: int in range(3):
		buttons[index].pressed.emit()
		await get_tree().process_frame
		_suite.assert_equal(_received_configs.size(), index + 1, "preset %d emits one request" % index)
		if _received_configs.size() <= index:
			continue
		_assert_preset(_received_configs[index], EXPECTED_PRESETS[index], "preset %d" % index)

	_received_configs[0]["weapon_id"] = "forged"
	_received_configs[0]["enabled_time_skills"][0] = "accelerate"
	buttons[0].pressed.emit()
	await get_tree().process_frame
	_suite.assert_equal(_received_configs.size(), 4, "Bow can be requested again")
	if _received_configs.size() == 4:
		_assert_preset(_received_configs[3], EXPECTED_PRESETS[0], "fresh Bow copy")

	panel.call("show_start_rejected")
	await get_tree().process_frame
	_suite.assert_true(panel.visible, "start rejection leaves candidate panel open")
	_suite.assert_equal(status_label.text, tr("UI_CANDIDATE_START_REJECTED"), "start rejection is localized")

	TranslationServer.set_locale("zh_CN")
	await _frames(2)
	_suite.assert_true(warning_label.text.contains("未正式晋升"), "Chinese warning explicitly says candidates are not promoted")
	_suite.assert_true(buttons[0].text.contains("弓"), "locale changes redraw preset labels")

	panel.call("close_panel")
	await _frames(2)
	_suite.assert_true(not panel.visible, "closing hides candidate panel")
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), restore_button, "closing restores Candidate Lab focus")

	panel.queue_free()
	restore_button.queue_free()
	await _frames(2)
	TranslationServer.set_locale(original_locale)
	get_window().size = original_window_size
	_suite.finish(get_tree())


func _assert_preset(actual: Dictionary, expected: Dictionary, label: String) -> void:
	_suite.assert_equal(actual.get("schema_version"), 1, "%s uses run schema one" % label)
	_suite.assert_equal(actual.get("milestone"), expected["milestone"], "%s uses NEXT" % label)
	_suite.assert_equal(actual.get("character_id"), expected["character_id"], "%s uses Wanderer" % label)
	_suite.assert_equal(actual.get("weapon_id"), expected["weapon_id"], "%s uses the frozen weapon" % label)
	_suite.assert_equal(actual.get("enabled_time_skills"), expected["enabled_time_skills"], "%s uses the frozen time pair" % label)
	_suite.assert_equal(actual.get("difficulty"), "normal", "%s uses normal difficulty" % label)
	_suite.assert_true(not actual.has("seed"), "%s leaves seed ownership to Main" % label)
	_suite.assert_true(not actual.has("accessibility_assists"), "%s leaves assists ownership to Main" % label)


func _on_candidate_requested(config: Dictionary) -> void:
	_received_configs.append(config)


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame
