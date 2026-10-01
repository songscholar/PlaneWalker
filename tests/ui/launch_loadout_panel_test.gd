extends Node

const LaunchLoadoutPanelScene := preload("res://scenes/ui/launch_loadout_panel.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CHARACTERS: Array[String] = [
	"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
]
const WEAPONS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_PAIRS: Array[Array] = [
	["stop", "rewind"],
	["stop", "rift"],
	["stop", "accelerate"],
	["rewind", "rift"],
	["rewind", "accelerate"],
	["rift", "accelerate"],
]
const TEST_WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(640, 360),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(3440, 1440),
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
	var captured_button := Button.new()
	captured_button.name = "CapturedButton"
	captured_button.focus_mode = Control.FOCUS_ALL
	add_child(captured_button)
	var panel := LaunchLoadoutPanelScene.instantiate() as Control
	panel.call("configure", restore_button)
	panel.connect("launch_requested", _on_launch_requested)
	add_child(panel)
	await _frames(2)

	var panel_root := panel.get_node("SafeArea/Center/PanelRoot") as Control
	var title_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/TitleLabel") as Label
	var warning_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/WarningLabel") as Label
	var character_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/CharacterOption") as OptionButton
	var weapon_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/WeaponOption") as OptionButton
	var time_pair_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/TimePairOption") as OptionButton
	var description_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/DescriptionLabel") as Label
	var summary_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SummaryLabel") as Label
	var start_button := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/ButtonRow/StartButton") as Button
	var status_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/StatusLabel") as Label
	var back_button := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/ButtonRow/BackButton") as Button

	_suite.assert_true(not panel.visible, "Launch loadout panel starts hidden")
	_suite.assert_true(title_label.text.contains("Launch"), "English title identifies the Launch loadout")
	_suite.assert_true(warning_label.text.contains("local"), "English warning preserves local-verification scope")
	_suite.assert_equal(character_option.item_count, CHARACTERS.size(), "all five characters have a player-facing option")
	_suite.assert_equal(weapon_option.item_count, WEAPONS.size(), "all five weapons have a player-facing option")
	_suite.assert_equal(time_pair_option.item_count, TIME_PAIRS.size(), "all six legal time pairs have a player-facing option")
	_suite.assert_true(description_label.custom_minimum_size.y > 0.0, "description has a fixed-height layout budget")
	_suite.assert_true(description_label.text.contains("balanced"), "selected character description is visible")

	captured_button.grab_focus()
	panel.call("open_panel")
	await _frames(2)
	_suite.assert_true(panel.visible, "Launch loadout panel opens")
	for window_size: Vector2i in TEST_WINDOW_SIZES:
		get_window().size = window_size
		await _frames(3)
		_assert_layout_for_window(panel, panel_root, focus_controls(panel), window_size)
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), character_option, "opening focuses the character selector")

	var focus_controls: Array[Control] = focus_controls(panel)
	for index: int in range(focus_controls.size()):
		var next := focus_controls[(index + 1) % focus_controls.size()]
		_suite.assert_equal(
			focus_controls[index].focus_neighbor_bottom,
			focus_controls[index].get_path_to(next),
			"Launch focus ring links control %d downward" % index
		)

	for character_index: int in range(CHARACTERS.size()):
		for weapon_index: int in range(WEAPONS.size()):
			for pair_index: int in range(TIME_PAIRS.size()):
				character_option.select(character_index)
				weapon_option.select(weapon_index)
				time_pair_option.select(pair_index)
				panel.call("refresh_selection")
				start_button.pressed.emit()
				await get_tree().process_frame
				var request_index := (
					character_index * WEAPONS.size() * TIME_PAIRS.size()
					+ weapon_index * TIME_PAIRS.size()
					+ pair_index
				)
				_suite.assert_equal(_received_configs.size(), request_index + 1, "loadout %d emits one request" % request_index)
				if _received_configs.size() <= request_index:
					continue
				_assert_config(
					_received_configs[request_index],
					CHARACTERS[character_index],
					WEAPONS[weapon_index],
					TIME_PAIRS[pair_index],
					"loadout %d" % request_index
				)

	_suite.assert_true(summary_label.text.contains("/"), "selection summary is visible without exposing internal fields")
	_received_configs[0]["weapon_id"] = "forged"
	character_option.select(0)
	weapon_option.select(0)
	time_pair_option.select(0)
	start_button.pressed.emit()
	await get_tree().process_frame
	_suite.assert_equal(_received_configs.size(), 151, "a loadout can be requested again")
	if _received_configs.size() == 151:
		_assert_config(_received_configs[150], "wanderer", "sword", TIME_PAIRS[0], "fresh selection copy")

	panel.call("show_start_rejected")
	await get_tree().process_frame
	_suite.assert_equal(status_label.text, tr("UI_LAUNCH_START_REJECTED"), "Launch start rejection is localized")

	character_option.select(3)
	weapon_option.select(2)
	time_pair_option.select(4)
	panel.call("refresh_selection")
	var selected_ids := [
		character_option.get_item_metadata(character_option.selected),
		weapon_option.get_item_metadata(weapon_option.selected),
		time_pair_option.get_item_metadata(time_pair_option.selected),
	]
	TranslationServer.set_locale("zh_CN")
	await _frames(2)
	get_window().size = Vector2i(640, 360)
	await _frames(3)
	_assert_layout_for_window(panel, panel_root, focus_controls(panel), Vector2i(640, 360))
	_suite.assert_true(title_label.text.contains("启动"), "Chinese title redraws")
	_suite.assert_true(character_option.get_item_text(3).contains("原初骑士"), "Chinese character options redraw")
	_suite.assert_true(weapon_option.get_item_text(2).contains("枪"), "Chinese weapon options redraw")
	_suite.assert_true(time_pair_option.get_item_text(4).contains("时间加速"), "Chinese time-pair options redraw")
	_suite.assert_equal(
		[
			character_option.get_item_metadata(character_option.selected),
			weapon_option.get_item_metadata(weapon_option.selected),
			time_pair_option.get_item_metadata(time_pair_option.selected),
		],
		selected_ids,
		"localization refresh preserves the three selected stable IDs"
	)

	panel.call("close_panel")
	await _frames(2)
	_suite.assert_true(not panel.visible, "closing hides Launch panel")
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), restore_button, "closing restores Launch button focus")

	panel.queue_free()
	restore_button.queue_free()
	captured_button.queue_free()
	await _frames(2)
	TranslationServer.set_locale(original_locale)
	get_window().size = original_window_size
	_suite.finish(get_tree())


func focus_controls(panel: Control) -> Array[Control]:
	return [
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/CharacterOption") as Control,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/WeaponOption") as Control,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/TimePairOption") as Control,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/ButtonRow/StartButton") as Control,
		panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/ButtonRow/BackButton") as Control,
	]


func _assert_layout_for_window(
	panel: Control,
	panel_root: Control,
	controls: Array[Control],
	window_size: Vector2i
) -> void:
	_suite.assert_equal(get_window().size, window_size, "%s window size is applied" % window_size)
	var safe_area := panel.get_node("SafeArea") as Control
	var safe_rect := safe_area.get_global_rect()
	var panel_rect := panel_root.get_global_rect()
	_suite.assert_true(
		safe_rect.encloses(panel_rect),
		"%s keeps the Launch panel inside the logical safe area" % window_size
	)
	var screen_transform := get_viewport().get_screen_transform()
	var screen_position := screen_transform * panel_rect.position
	var screen_end := screen_transform * panel_rect.end
	var screen_rect := Rect2(screen_position, screen_end - screen_position)
	_suite.assert_true(
		Rect2(Vector2.ZERO, Vector2(window_size)).encloses(screen_rect),
		"%s keeps the Launch panel inside the physical window" % window_size
	)
	for control: Control in controls:
		_suite.assert_true(
			panel_rect.encloses(control.get_global_rect()),
			"%s keeps %s inside the Launch panel" % [window_size, control.name]
		)


func _assert_config(actual: Dictionary, character_id: String, weapon_id: String, pair: Array, label: String) -> void:
	_suite.assert_equal(actual.get("schema_version"), 1, "%s uses run schema one" % label)
	_suite.assert_equal(actual.get("milestone"), "LAUNCH", "%s uses Launch availability" % label)
	_suite.assert_equal(actual.get("character_id"), character_id, "%s uses the selected character" % label)
	_suite.assert_equal(actual.get("weapon_id"), weapon_id, "%s uses the selected weapon" % label)
	_suite.assert_equal(actual.get("enabled_time_skills"), pair, "%s uses the selected time pair" % label)
	_suite.assert_equal(actual.get("difficulty"), "normal", "%s uses normal difficulty" % label)
	_suite.assert_true(not actual.has("seed"), "%s leaves seed ownership to Main" % label)
	_suite.assert_true(not actual.has("accessibility_assists"), "%s leaves assists ownership to Main" % label)


func _on_launch_requested(config: Dictionary) -> void:
	_received_configs.append(config)


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame
