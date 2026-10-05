extends "res://tests/integration/ui/authored_challenge_coordinator_test.gd"

const MainScene := preload("res://scenes/main.tscn")


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_seed_main_profile("authored-main")
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var coordinator: Node = main.get_node_or_null("AuthoredChallengeCoordinator")
	_suite.assert_true(coordinator != null, "actual Main installs the authored trial entry and return flow")
	if coordinator == null:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_suite.finish(get_tree())
		return
	var hub: Node = main.get_node("HubFlowCoordinator")
	_suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "authored native council exposes mode gateway")
	var entry := _authored_action(hub.panel_view(), "authored_challenges")
	_suite.assert_true(entry != null, "actual council gateway contains authored trials command")
	if entry == null:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_suite.finish(get_tree())
		return
	entry.pressed.emit()
	await get_tree().process_frame
	_suite.assert_true(coordinator.is_open() and not hub.is_hub_visible() and main._content_mutation_locked(), "actual authored menu owns Main interaction and content lock")
	_suite.assert_true(coordinator.panel().selector.has_focus() and coordinator.panel().selector.item_count == 5, "authored Main entry focuses actual five-set selector")
	var flow: Node = coordinator.runtime()
	var ordinary: Dictionary = GameState.profile_runtime_service().snapshot()
	var start := _authored_action(coordinator.panel(), "start")
	var retired: Callable = start.pressed.get_connections()[0].callable
	start.pressed.emit()
	await get_tree().process_frame
	retired.call()
	_suite.assert_true(flow.is_active() and not coordinator.panel().visible and flow.snapshot().sequence == 1, "actual Start and retired callback create exactly one native authored trial")
	await _frames(3)
	var pause := InputEventJoypadButton.new()
	pause.button_index = JOY_BUTTON_START
	pause.pressed = true
	main._unhandled_input(pause)
	_suite.assert_true(coordinator.panel().visible and flow.is_paused(), "actual Main dispatches controller Start to authored native pause")
	await get_tree().process_frame
	_suite.assert_true(_authored_action(coordinator.panel(), "resume").has_focus(), "actual authored native pause restores Resume focus")
	var saved_sequence: int = int(flow.snapshot().sequence)
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	coordinator.panel()._unhandled_input(back)
	await get_tree().process_frame
	_suite.assert_true(hub.is_hub_visible() and not coordinator.is_open() and not flow.is_active(), "controller B saves authored practice and returns actual Main to Hub")
	_suite.assert_true(flow.snapshot().active.continued, "actual save return classifies the reconstructed stage as practice")
	_suite.assert_true(hub.open_function("gateway").ok, "Hub remains usable after authored controller return")
	_authored_action(hub.panel_view(), "authored_challenges").pressed.emit()
	_authored_action(coordinator.panel(), "continue").pressed.emit()
	await _frames(3)
	_suite.assert_true(flow.is_active() and flow.snapshot().sequence == saved_sequence, "actual Continue reconstructs same physical authored sequence")
	flow.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.has_pending_save() and not coordinator.return_to_hub().ok and coordinator.panel().visible, "actual authored death save refusal retains the retry panel")
	flow.set_fault_injector(Callable())
	_authored_action(coordinator.panel(), "retry").pressed.emit()
	_suite.assert_true(coordinator.return_to_hub().ok and hub.is_hub_visible(), "actual result retry stores once and restores Hub")
	_suite.assert_equal(GameState.profile_runtime_service().snapshot(), ordinary, "authored actual Main leaves ordinary Profile unchanged")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.set("_profile_runtime", null)
	main = MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	flow = main.get_node("AuthoredChallengeCoordinator").runtime()
	_suite.assert_equal(flow.preview().history.sword_timer.size(), 1, "fresh Main physically reloads exactly one authored result")
	_suite.assert_true(flow.preview().history.sword_timer[0].continued and flow.preview().history.sword_timer[0].status == "DEFEAT", "fresh Main retains authored practice classification and actual death")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.finish(get_tree())
