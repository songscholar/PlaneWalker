extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Codec := preload("res://scripts/progression/build_share_codec.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var hub: Node = main.get_node_or_null("HubFlowCoordinator")
	suite.assert_true(hub != null, "actual Main configures Hub for sharing")
	if hub == null:
		await _dispose(main)
		suite.finish(get_tree())
		return
	suite.assert_true(hub.travel("hub_craft").ok and hub.open_function("meditation").ok, "actual meditation opens")
	var panel: Control = hub.panel_view()
	var field: LineEdit = panel.find_child("ShareCode", true, false)
	suite.assert_true(field != null, "native meditation provides portable share field")
	if field == null:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var service: RefCounted = GameState.profile_runtime_service()
	var save: RefCounted = GameState.get("_save_service")
	var original: Dictionary = service.snapshot()
	var input: LineEdit = panel.find_child("BuildName", true, false)
	input.text = "Native Share"
	_action(hub, "build_save").pressed.emit()
	suite.assert_equal(service.snapshot().build_library.size(), 1, "native naming saves source")
	var source_id: String = service.snapshot().build_library[0].id
	var export_action := _action(hub, "build_export:" + source_id)
	suite.assert_true(export_action != null, "actual saved build has export control")
	if export_action == null:
		await _dispose(main)
		suite.finish(get_tree())
		return
	export_action.pressed.emit()
	field = panel.find_child("ShareCode", true, false)
	var code: String = field.text
	suite.assert_true(Codec.decode(code).ok, "native export delivers real canonical share code")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set("A".repeat(1025))
		_action(hub, "share_paste").pressed.emit()
		suite.assert_equal(field.text, code, "oversized physical clipboard paste preserves previous code")
		DisplayServer.clipboard_set(code)
		_action(hub, "share_paste").pressed.emit()
		suite.assert_equal(field.text, code, "actual clipboard paste loads portable code")
		_action(hub, "share_copy").pressed.emit()
		suite.assert_equal(DisplayServer.clipboard_get(), code, "actual copy control writes selected share code")
	var before: Dictionary = service.snapshot()
	var import_action := _action(hub, "build_import")
	save.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	import_action.pressed.emit()
	suite.assert_equal(service.snapshot(), before, "native failed import preserves Profile")
	suite.assert_equal((panel.find_child("ShareCode", true, false) as LineEdit).text, code, "failed save keeps entered code for retry")
	suite.assert_true(panel.error_label.visible and not _action(hub, "build_import").disabled, "native failure recovers available import action")
	save.set_fault_injector(Callable())
	var retired: Callable = import_action.pressed.get_connections()[0].callable
	import_action.pressed.emit()
	retired.call()
	suite.assert_equal(service.snapshot().build_library.size(), 2, "native successful retry and retired callback import only once")
	suite.assert_equal(service.snapshot().revision, int(before.revision) + 1, "native share import writes one revision")
	field = panel.find_child("ShareCode", true, false)
	suite.assert_equal(field.text, code, "successful import keeps selectable portable code")
	suite.assert_equal(service.snapshot().chronos_shards, original.chronos_shards, "native sharing cannot transfer currency")
	await get_tree().process_frame
	field.grab_focus()
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), field, "native share field belongs to actual controller focus scope")
	suite.assert_true(not field.focus_next.is_empty() and not field.focus_previous.is_empty(), "share text input participates in linked controller ring")
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	down = InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = false
	Input.parse_input_event(down)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), _action(hub, "build_import"), "physical controller down moves from share field to its import action")
	for locale: String in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		await get_tree().process_frame
		field = panel.find_child("ShareCode", true, false)
		suite.assert_equal(field.text, code, "locale update retains entered share code")
		suite.assert_true(field.placeholder_text != "UI_SHARE_CODE", "native share placeholder is localized")
		var button := _action(hub, "build_import")
		suite.assert_true(button.text != "UI_SHARE_IMPORT", "native import action is localized")
	await _dispose(main)
	suite.finish(get_tree())


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _action(hub: Node, id: String) -> Button:
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null
