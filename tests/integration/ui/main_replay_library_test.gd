extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var library: Node = main.get_node_or_null("ReplayLibrary")
	var panel: Control = main.get_node_or_null("ReplayLibraryLayer/ReplayLibraryPanel")
	suite.assert_true(library != null and panel != null, "actual Main owns physical replay library and native viewer")
	if library == null or panel == null:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var hub: Node = main.get_node("HubFlowCoordinator")
	var profile: Dictionary = GameState.profile_runtime_service().snapshot()
	var replay := await Fixture.record(self, main.runtime_host.content_registry(), suite, "main-library", 506)
	var stored: Dictionary = library.store(replay)
	suite.assert_true(stored.ok, "production replay library physically retains actual Player recording")
	suite.assert_true(hub.travel("hub_council").ok and hub.open_function("archive").ok, "authored archive exposes replay entry")
	var entry: Button
	for action: Control in hub.panel_view().action_controls():
		if str(action.get_meta("action_id", "")) == "replay_library":
			entry = action
	suite.assert_true(entry != null, "actual Archive contains native replay command")
	if entry != null:
		var retired: Callable = entry.pressed.get_connections()[0].callable
		entry.pressed.emit()
		await get_tree().process_frame
		suite.assert_true(panel.visible and not hub.is_hub_visible(), "replay viewing owns native interaction")
		suite.assert_true(main.call("_content_mutation_locked"), "open replay binds active content and prevents reload")
		suite.assert_true(not hub.travel("hub_craft").ok, "hidden Hub cannot travel during replay")
		suite.assert_true(FocusCoordinator.active_scope() == panel, "replay viewer owns controller focus")
		suite.assert_true(library.select(stored.context.id).ok and library.seek(3).ok, "actual Main displays an archived frame")
		var target: Node2D = library.current_player()
		var cancel := InputEventJoypadButton.new()
		cancel.button_index = JOY_BUTTON_B
		cancel.pressed = true
		Input.parse_input_event(cancel)
		await get_tree().process_frame
		cancel.pressed = false
		Input.parse_input_event(cancel)
		await get_tree().process_frame
		suite.assert_true(hub.is_hub_visible() and hub.panel_view().visible, "closing replay restores the Archive")
		suite.assert_true(FocusCoordinator.active_scope() == hub.panel_view(), "Archive regains controller focus")
		suite.assert_true(not is_instance_valid(target) and library.current_player() == null, "Main viewer close releases private actual Player")
		suite.assert_true(not main.call("_content_mutation_locked"), "closed replay releases content mutation lock")
		retired.call()
		suite.assert_true(not panel.visible, "retired Archive callback cannot reopen replay")
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile, "replay navigation and seeking preserve live progression")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	library = main.get_node("ReplayLibrary")
	suite.assert_equal(library.rows().size(), 1, "fresh Main reloads the physical replay archive")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
