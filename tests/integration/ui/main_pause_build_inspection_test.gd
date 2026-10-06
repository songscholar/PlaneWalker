extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	GameState.save_path = OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("pause_build/save.json")
	var main := Main.instantiate()
	add_child(main)
	await _frames(3)
	main.get_node("HubFlowCoordinator").hide_hub()
	main.call("_show_start_menu")
	var config: Dictionary = main.call("_build_run_config")
	config.seed = 20261006
	suite.assert_true(main.call("_launch_run", config, false), "actual Main starts the deterministic run for pause acceptance")
	await _frames(3)
	main.call("_pause_run")
	var accepted_at_pause: Dictionary = main.get_node("RunRuntimeHost/HudLayer").call("latest_state")
	await _frames(2)
	var pause := main.get_node("PauseMenu")
	var button: Button = pause.get("build_button")
	suite.assert_true(get_tree().paused and pause.visible, "actual Main pauses its run before build inspection")
	suite.assert_true(button != null and not button.disabled, "actual Main supplies the accepted HUD snapshot to pause inspection")
	if button == null or button.disabled:
		var diagnostic_host := main.get_node("RunRuntimeHost")
		var native: Dictionary = diagnostic_host.call("runtime_snapshot")
		var projected = diagnostic_host.get("_projector").project(native, diagnostic_host.get("_facade").call("current_room_definition"), diagnostic_host.call("_player_ui_snapshot"), diagnostic_host.call("_boss_ui_snapshot"), int(native.get("run_time_ms", 0)), {"show_pause": get_tree().paused})
		print("PAUSE_INSPECTION_DIAGNOSTIC ", JSON.stringify({"presentation_enabled": diagnostic_host.get("_presentation_enabled"), "active_run_id": diagnostic_host.get("_active_run_id"), "projection_ok": projected.ok, "projection_code": projected.code, "projection_context": projected.context, "accepted": diagnostic_host.get_node("HudLayer").call("latest_state")}))
	if button != null and not button.disabled:
		var host := main.get_node("RunRuntimeHost")
		var snapshot: Dictionary = host.call("runtime_snapshot")
		button.grab_focus()
		button.pressed.emit()
		await _frames(2)
		var inspector := pause.get_node("BuildInspector") as Control
		suite.assert_true(inspector.visible, "actual Main exposes current equipment and content inspection")
		suite.assert_equal(inspector.call("view_state"), accepted_at_pause, "actual Main inspection presents the exact snapshot accepted when pause opened")
		suite.assert_equal(host.call("runtime_snapshot"), snapshot, "reading the build leaves all paused runtime state unchanged")
		inspector.get("back_button").pressed.emit()
		await _frames(2)
		suite.assert_true(get_tree().paused and pause.visible and not inspector.visible, "closing inspection preserves the pause state")
		suite.assert_equal(get_viewport().gui_get_focus_owner(), button, "actual Main returns focus to build inspection entry")
	main.call("_resume_run")
	suite.assert_true(not get_tree().paused, "actual Main resumes normally after build inspection")
	main.queue_free()
	await _frames(3)
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
