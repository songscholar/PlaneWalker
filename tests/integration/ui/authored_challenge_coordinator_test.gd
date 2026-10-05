extends "res://tests/integration/combat/authored_challenge_native_test.gd"

const CoordinatorSource := "res://scripts/modes/authored_challenge_coordinator.gd"


func _run() -> void:
	_suite = Suite.new()
	if not ResourceLoader.exists(CoordinatorSource):
		_suite.assert_true(false, "authored trials expose native set selection fixed visible commands controller pause and recovery")
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var fixture := _daily_fixture("authored-coordinator")
	var coordinator: Node2D = load(CoordinatorSource).new()
	add_child(coordinator)
	_suite.assert_true(coordinator.configure(_registry, fixture.service, fixture.root.path_join("authored")).ok and coordinator.open().ok, "actual native authored coordinator opens")
	_suite.assert_true(coordinator.panel().selector.item_count == 5, "actual menu selector contains all five authored trials")
	var menu: Dictionary = coordinator.panel().view_state()
	for damaged: Dictionary in _invalid_menu_projections(menu):
		_suite.assert_true(not coordinator.panel().render(damaged).ok, "malformed authored display facts are refused before native property access")
		_suite.assert_equal(coordinator.panel().view_state(), menu, "invalid authored projection preserves visible canonical menu")
	_suite.assert_true(coordinator.select_set("staff_resolve").ok, "valid authored set selection projects its actual fixed Build")
	_suite.assert_equal(coordinator.panel().view_state().selected_id, "staff_resolve", "panel uses selected canonical set")
	_suite.assert_true(not coordinator.select_set("invented").ok, "UI cannot select a fabricated authored trial")
	_suite.assert_true(coordinator.select_set("sword_timer").ok, "real sword trial is selected")
	var start := _authored_action(coordinator.panel(), "start")
	var retired: Callable = start.pressed.get_connections()[0].callable
	start.pressed.emit()
	await get_tree().process_frame
	var flow: Node = coordinator.runtime()
	_suite.assert_true(flow.is_active() and not coordinator.panel().visible, "actual Start launches native fixed-Build combat")
	retired.call()
	_suite.assert_equal(flow.snapshot().sequence, 1, "retired Start cannot admit another authored attempt")
	await _frames(3)
	var pause := InputEventJoypadButton.new()
	pause.button_index = JOY_BUTTON_START
	pause.pressed = true
	_suite.assert_true(coordinator.handle_input(pause) and coordinator.panel().visible, "controller Start pauses actual authored arena")
	var paused: Dictionary = flow.snapshot()
	await _frames(3)
	_suite.assert_equal(flow.snapshot(), paused, "controller pause freezes native accepted-frame timing")
	_suite.assert_true(_authored_action(coordinator.panel(), "resume").has_focus(), "pause exposes an actual focused Resume command")
	_authored_action(coordinator.panel(), "resume").pressed.emit()
	flow.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.has_pending_save() and coordinator.panel().visible and not coordinator.return_to_hub().ok, "native death persistence refusal keeps recovery panel and blocks exit")
	flow.set_fault_injector(Callable())
	_authored_action(coordinator.panel(), "retry").pressed.emit()
	_suite.assert_equal(flow.preview().history.sword_timer.size(), 1, "actual Retry publishes exactly one authentic death result")
	_suite.assert_true(coordinator.return_to_hub().ok and not coordinator.is_open(), "saved result releases the native coordinator")
	coordinator.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.finish(get_tree())


func _authored_action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _invalid_menu_projections(menu: Dictionary) -> Array[Dictionary]:
	var missing_name := menu.duplicate(true)
	missing_name.content_names.erase(missing_name.preview.sets[0].item_ids[0])
	var empty_loadout := menu.duplicate(true)
	empty_loadout.preview.sets[0].time_abilities = []
	var invalid_active := menu.duplicate(true)
	invalid_active.preview.active = {"stage_index": "invalid"}
	var invalid_history := menu.duplicate(true)
	invalid_history.preview.history.sword_timer = [{"status": "VICTORY"}]
	var invalid_best := menu.duplicate(true)
	invalid_best.preview.best.sword_timer = false
	var invalid_flag := menu.duplicate(true)
	invalid_flag.preview.pending = "pending"
	return [missing_name, empty_loadout, invalid_active, invalid_history, invalid_best, invalid_flag]
