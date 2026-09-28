extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const MainScene := preload("res://scenes/main.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_assert_project_settings()
	await _assert_scene_contract()
	_suite.finish(get_tree())


func _assert_project_settings() -> void:
	_suite.assert_equal(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		640,
		"logical width is 640"
	)
	_suite.assert_equal(
		ProjectSettings.get_setting("display/window/size/viewport_height"),
		360,
		"logical height is 360"
	)
	_suite.assert_equal(
		ProjectSettings.get_setting("display/window/stretch/mode"),
		"canvas_items",
		"2D stretch is enabled"
	)
	_suite.assert_equal(
		ProjectSettings.get_setting("display/window/stretch/scale_mode"),
		"integer",
		"integer scaling prevents blur"
	)


func _assert_scene_contract() -> void:
	get_window().size = Vector2i(640, 360)
	var main := MainScene.instantiate()
	var adapter := main.get_node_or_null("RuntimeV2Adapter")
	if adapter != null:
		adapter.set("enabled", false)
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var room := main.get_node("CombatRoom01")
	var camera := room.get_node_or_null("PixelCanvasCamera") as Camera2D
	_suite.assert_true(camera != null, "combat room provides the pixel-canvas camera")
	if camera != null:
		_suite.assert_equal(camera.position, Vector2(640.0, 360.0), "camera centers the 1280x720 greybox")
		_suite.assert_equal(camera.zoom, Vector2(0.5, 0.5), "camera fits the greybox into 640x360")
		_suite.assert_true(camera.enabled, "pixel-canvas camera is enabled")

	_assert_control_fits(main.get_node("StartMenu/Panel"), "start menu fits 640x360")
	_assert_control_fits(main.get_node("RunEndOverlay/Panel"), "run-end panel fits 640x360")
	_assert_control_fits(main.get_node("PauseMenu/Panel"), "pause panel fits 640x360")
	_suite.assert_true((main.get_node("StartMenu") as CanvasLayer).layer > 20, "start menu renders above gameplay UI")
	_suite.assert_true((main.get_node("RunEndOverlay") as CanvasLayer).layer > 20, "run-end overlay renders above gameplay UI")
	_suite.assert_true((main.get_node("PauseMenu") as CanvasLayer).layer > 20, "pause menu renders above gameplay UI")
	_assert_control_fits(room.get_node("RewardSelection/Panel"), "legacy reward fallback fits 640x360")
	_assert_control_fits(room.get_node("CurseSelection/Panel"), "legacy curse fallback fits 640x360")
	_assert_control_fits(room.get_node("EventSelection/Panel"), "legacy event fallback fits 640x360")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_control_fits(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	_suite.assert_true(rect.position.x >= -0.5, label + " on the left")
	_suite.assert_true(rect.position.y >= -0.5, label + " on the top")
	_suite.assert_true(rect.end.x <= 640.5, label + " on the right")
	_suite.assert_true(rect.end.y <= 360.5, label + " on the bottom")
