extends "res://tests/integration/combat/daily_boss_native_test.gd"

const Main := preload("res://scenes/main.tscn")


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_seed_main_profile("controller")
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var coordinator: Node = main.get_node_or_null("DailyBossCoordinator")
	_suite.assert_true(coordinator != null, "actual Main installs native daily coordinator")
	if coordinator == null:
		main.queue_free()
		await get_tree().process_frame
		_suite.finish(get_tree())
		return
	var hub: Node = main.get_node("HubFlowCoordinator")
	_suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "actual daily gateway is owned by authored council")
	var entry := _daily_action(hub.panel_view(), "daily_boss")
	_suite.assert_true(entry != null, "actual Hub gateway contains native daily entry")
	entry.pressed.emit()
	await get_tree().process_frame
	_suite.assert_true(coordinator.is_open() and not hub.is_hub_visible() and main.call("_content_mutation_locked"), "actual daily preview owns Main interaction and content lock")
	var start := _daily_action(coordinator.panel(), "start")
	_suite.assert_true(start != null and not start.disabled and start.has_focus(), "earned Profile receives actual focusable daily Start")
	var retired: Callable = start.pressed.get_connections()[0].callable
	start.pressed.emit()
	await get_tree().process_frame
	var flow: Node = coordinator.runtime()
	_suite.assert_true(flow.is_active() and not coordinator.panel().visible, "actual daily Start enters the fixed native encounter")
	var admitted: Dictionary = flow.snapshot().active
	retired.call()
	_suite.assert_equal(flow.snapshot().active.run_id, admitted.run_id, "retired daily Start cannot spend another attempt")
	await _frames(3)
	var pause := InputEventJoypadButton.new()
	pause.button_index = JOY_BUTTON_START
	pause.pressed = true
	_suite.assert_true(coordinator.handle_input(pause) and coordinator.panel().visible, "actual mapped controller Start pauses daily native combat")
	var paused: Dictionary = flow.snapshot()
	await _frames(3)
	_suite.assert_equal(flow.snapshot(), paused, "daily controller pause freezes actual accepted-frame timing")
	var resume := _daily_action(coordinator.panel(), "resume")
	_suite.assert_true(resume.has_focus(), "daily controller pause restores actual usable focus")
	resume.pressed.emit()
	flow.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.has_pending_save() and coordinator.panel().visible and not coordinator.return_to_hub().ok, "actual daily native death save failure keeps result and retry surface")
	flow.set_fault_injector(Callable())
	_daily_action(coordinator.panel(), "retry").pressed.emit()
	_suite.assert_true(not flow.has_pending_save() and flow.preview().results.size() == 1 and flow.preview().results[0].status == "DEFEAT", "actual native daily Retry stores one real death result")
	_suite.assert_true(coordinator.return_to_hub().ok and hub.is_hub_visible() and not coordinator.is_open(), "actual daily result restores Hub interaction")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	flow = main.get_node("DailyBossCoordinator").runtime()
	_suite.assert_equal(flow.preview().remaining_attempts, 2, "fresh Main physically retains daily admission and native death result")
	_suite.assert_equal(GameState.profile_runtime_service().snapshot().statistics.finished_runs, 1, "daily actual Main does not settle an ordinary Profile Run")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.finish(get_tree())


func _daily_action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null
