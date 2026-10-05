extends "res://tests/modes/endless_checkpoint_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_install_translations()
	var path := "res://scripts/modes/endless_coordinator.gd"
	_suite.assert_true(ResourceLoader.exists(path), "Endless must expose actual focused controller pause and recovery controls")
	if not ResourceLoader.exists(path):
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var fixture := _fixture("coordinator")
	var coordinator: Node2D = load(path).new()
	add_child(coordinator)
	_suite.assert_true(coordinator.configure(_registry, fixture.service, fixture.root.path_join("modes")).ok and coordinator.open(REQUEST).ok, "Endless opens actual native controller menu")
	await get_tree().process_frame
	var start := _action(coordinator.panel(), "start")
	_suite.assert_true(start != null and start.has_focus(), "Start receives native initial focus")
	start.pressed.emit()
	await get_tree().process_frame
	var flow: Node = coordinator.runtime()
	_suite.assert_true(flow.is_active() and not coordinator.panel().visible, "focused Start launches real five-floor dungeon")
	var pause := InputEventJoypadButton.new()
	pause.button_index = JOY_BUTTON_START
	pause.pressed = true
	_suite.assert_true(coordinator.handle_input(pause) and coordinator.panel().visible and flow.is_paused(), "actual controller Start opens Endless pause")
	var before: Dictionary = flow.snapshot()
	await get_tree().physics_frame
	_suite.assert_equal(flow.snapshot(), before, "controller pause freezes native Endless clock")
	_suite.assert_true(_action(coordinator.panel(), "resume").has_focus(), "Resume owns actual controller focus")
	_action(coordinator.panel(), "resume").pressed.emit()
	flow.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	var returned: Dictionary = coordinator.return_to_hub()
	_suite.assert_true(not returned.ok and coordinator.is_open() and coordinator.panel().visible, "failed return preserves focused recovery and native dungeon")
	flow.set_fault_injector(Callable())
	_action(coordinator.panel(), "retry").pressed.emit()
	_suite.assert_true(not coordinator.is_open() and not flow.is_active(), "focused retry closes only after actual durable return")
	coordinator.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.finish(get_tree())


func _action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _install_translations() -> void:
	var source := FileAccess.open("res://scripts/modes/endless_localization.csv", FileAccess.READ)
	var header := source.get_csv_line()
	var translated := Translation.new()
	var locale := TranslationServer.get_locale()
	var column := header.find(locale)
	if column < 1:
		column = 1
	translated.set_locale(locale)
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() == header.size():
			translated.add_message(row[0], row[column])
	TranslationServer.add_translation(translated)
