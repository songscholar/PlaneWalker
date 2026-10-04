extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FixturesScript := preload("res://tests/ui/p14_panel_fixtures.gd")

var panel_kind := ""
var panel_scene := ""
var command_signal := ""
var _suite: RefCounted
var _commands: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	get_viewport().size = Vector2i(640, 360)
	_suite.assert_true(ResourceLoader.exists(panel_scene), "player-facing dungeon panel scene exists")
	if not ResourceLoader.exists(panel_scene):
		_suite.finish(get_tree())
		return
	var packed := load(panel_scene) as PackedScene
	var panel := packed.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame
	_suite.assert_true(panel.has_method("render"), "panel consumes immutable projected ViewState")
	if not panel.has_method("render"):
		panel.queue_free()
		await get_tree().process_frame
		_suite.finish(get_tree())
		return
	var previous := Button.new()
	previous.text = "Previous"
	add_child(previous)
	previous.grab_focus()
	await get_tree().process_frame
	var state := FixturesScript.for_kind(panel_kind)
	var result: RefCounted = panel.call("render", state)
	_suite.assert_true(result.ok, "valid projected state renders: %s" % str(result.context))
	if not result.ok:
		panel.queue_free()
		previous.queue_free()
		await get_tree().process_frame
		_suite.finish(get_tree())
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(panel.visible, "render opens the panel")
	var root: PanelContainer = panel.get("panel_root")
	_suite.assert_true(root.size.x <= 608.1 and root.size.y <= 328.1, "native panel stays inside the 640x360 safe area")
	var controls: Array = panel.call("action_controls")
	_suite.assert_true(not controls.is_empty(), "controller has reachable actions")
	var eligible: Button
	for value: Button in controls:
		if not value.disabled:
			eligible = value
			break
	_suite.assert_true(eligible != null, "controller has an available action")
	_suite.assert_true(get_viewport().gui_get_focus_owner() != null, "opening restores usable controller focus")
	await _exercise_controller(panel)
	var malformed := state.duplicate(true)
	malformed["private_domain_state"] = {"secret": true}
	_suite.assert_true(not panel.call("render", malformed).ok, "unexpected projected fields fail closed")
	_suite.assert_equal(panel.call("view_state"), state, "rejected state leaves presentation byte-identical")
	state["revision"] = 99
	_suite.assert_equal(int(panel.call("view_state")["revision"]), 4, "panel owns a deep copy rather than domain references")
	if panel_kind != "map":
		panel.connect(command_signal, _capture_command)
		eligible.pressed.emit()
		_suite.assert_equal(_commands.size(), 1, "one controller activation emits one semantic command")
		_suite.assert_equal(_commands[0], _expected_command(), "commands preserve the projected identity and authority revision")
		eligible.pressed.emit()
		_suite.assert_equal(_commands.size(), 1, "pending submission prevents double command")
		panel.call("show_rejection", "UI_RETRY")
		await get_tree().process_frame
		_suite.assert_true(not eligible.disabled, "rejected command restores the eligible action")
		eligible.pressed.emit()
		_suite.assert_equal(_commands.size(), 2, "rejection permits a corrected retry")
	if panel_kind in ["route", "merchant", "event", "room"]:
		_suite.assert_true(_has_disabled_reason(panel), "unavailable options retain their visible reason")
	var count_before_refresh := _commands.size()
	var refreshed := FixturesScript.for_kind(panel_kind)
	refreshed["revision"] = 5
	_suite.assert_true(panel.call("render", refreshed).ok, "a newer authoritative state can replace the view")
	if panel_kind != "map":
		eligible.pressed.emit()
		_suite.assert_equal(_commands.size(), count_before_refresh, "removed controls cannot submit into a newer revision")
	await get_tree().process_frame
	await get_tree().process_frame
	var old_locale := TranslationServer.get_locale()
	for locale: String in ["zh", "en"]:
		TranslationServer.set_locale(locale)
		await get_tree().process_frame
		await get_tree().process_frame
		_suite.assert_true(root.size.x <= 608.1 and root.size.y <= 328.1, "localized panels keep the fixed safe area")
		_suite.assert_equal(int(panel.call("view_state")["revision"]), 5, "locale changes cannot mutate authority revisions")
		_suite.assert_true(get_viewport().gui_get_focus_owner() != null, "locale changes recover controller focus")
	TranslationServer.set_locale(old_locale)
	await get_tree().process_frame
	await get_tree().process_frame
	await _extra_checks(panel)
	panel.call("close_panel")
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(not panel.visible, "back closes the panel")
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), previous, "closing restores the previous controller focus")
	panel.queue_free()
	previous.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.finish(get_tree())


func _capture_command(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	_commands.append([a, b, c])


func _expected_command() -> Array:
	match panel_kind:
		"route": return [&"left-edge", 4, null]
		"merchant": return [&"purchase_reward", &"offer-a", 4]
		"event": return [&"event_chronal_altar", &"commit", 4]
		"room": return [&"heal", 4, null]
		"transition": return [4, null, null]
	return []


func _extra_checks(_panel: Control) -> void:
	pass


func _exercise_controller(panel: Control) -> void:
	var controls: Array[Control] = []
	for control: Control in panel.call("action_controls"):
		if not (control as Button).disabled:
			controls.append(control)
	var back: Button = panel.get("back_button")
	if not controls.has(back):
		controls.append(back)
	controls[0].grab_focus()
	for index: int in range(controls.size()):
		_suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[index], "controller traverses every available action in explicit order")
		var pressed := InputEventAction.new()
		pressed.action = &"ui_down"
		pressed.pressed = true
		Input.parse_input_event(pressed)
		var released := InputEventAction.new()
		released.action = &"ui_down"
		released.pressed = false
		Input.parse_input_event(released)
		await get_tree().process_frame
		await get_tree().process_frame
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[0], "controller ring wraps without a mouse or keyboard focus escape")


func _has_disabled_reason(panel: Node) -> bool:
	for child: Node in panel.find_children("DisabledReason*", "Label", true, false):
		if not (child as Label).text.is_empty() and (child as Label).visible:
			return true
	return false
