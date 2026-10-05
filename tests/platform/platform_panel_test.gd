extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Rules := preload("res://scripts/platform/platform_rules.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var panel_path := "res://scripts/platform/platform_panel.gd"
	suite.assert_true(ResourceLoader.exists(panel_path), "platform has a native usable panel")
	if not ResourceLoader.exists(panel_path):
		suite.finish(get_tree())
		return
	var catalog := Fixtures.catalog()
	var binding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/pack_snapshots/base_a.json"))
	var root := Paths.resolve_default("user://platform_panel", "platform_panel")
	var save := Save.new()
	save.configure(root.path_join("profiles"), "test-p24", binding)
	save.enable_meta_profile(catalog)
	suite.assert_true(save.save_profile("owner", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "physical Profile fixture is committed")
	var service := Service.new()
	suite.assert_true(service.configure(catalog, save, "owner", "base").ok, "real Profile service loads physical fixture")
	var initial_profile_payload := service.payload()
	var provider: RefCounted = load("res://scripts/platform/offline_platform_provider.gd").new()
	provider.configure(root.path_join("platform"), "test-p24", binding, "owner", "base")
	provider.unlock_achievement("first_run")
	var panel: Control = load(panel_path).new()
	add_child(panel)
	await get_tree().process_frame
	suite.assert_true(panel.configure(provider, service).ok and panel.open().ok and panel.is_open(), "actual panel configures and opens from provider and Profile")
	suite.assert_true(panel.view_state().model.achievements.has("first_run"), "native panel renders durable achievements")
	var input: LineEdit = panel.find_child("DisplayName", true, false)
	suite.assert_true(input != null, "identity has a real text input")
	if input != null:
		input.text = "Native Walker"
	var rename: Button = _button(panel, "rename")
	suite.assert_true(rename != null, "identity exposes durable save action")
	if rename != null:
		rename.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(provider.identity().context.display_name, "Native Walker", "native button writes durable display name")
	var stale: Button = _button(panel, "rename")
	var revision: int = panel.view_state().revision
	suite.assert_true(panel.select_section("storage").ok, "storage section is reachable")
	if is_instance_valid(stale):
		stale.pressed.emit()
	suite.assert_equal(provider.identity().context.display_name, "Native Walker", "stale callback cannot change identity")
	suite.assert_equal(panel.submit_command("backup_profile", {}, revision).code, &"STALE_REVISION", "stale direct command is refused")
	var backup: Button = _button(panel, "backup_profile")
	suite.assert_true(backup != null, "storage offers actual Profile backup")
	if backup != null:
		backup.pressed.emit()
	await get_tree().process_frame
	var stored: Dictionary = provider.cloud_read("profile_backup")
	suite.assert_true(stored.ok and panel.view_state().model.cloud.size() == 1, "backup button commits visible physical cloud cache")
	var coordinator: RefCounted = panel.coordinator()
	var decoded: Dictionary = coordinator.decode_profile_backup(stored.context.value)
	suite.assert_true(decoded.ok, "local backup decodes with verified digests: " + str(decoded.code))
	if decoded.ok:
		suite.assert_true(Rules.same(decoded.context.payload, service.payload()), "backup contains exact JSON state of current authoritative Profile")
	var exported: Dictionary = panel.submit_command("export_profile", {}, int(panel.view_state().revision))
	suite.assert_true(exported.ok and FileAccess.file_exists(exported.context.path), "panel exports current Profile as a real local artifact")
	var fresh: RefCounted = load("res://scripts/platform/offline_platform_provider.gd").new()
	fresh.configure(root.path_join("platform"), "test-p24", binding, "owner", "base")
	suite.assert_true(fresh.cloud_read("profile_backup").ok and fresh.identity().context.display_name == "Native Walker", "native actions survive cold restart")
	suite.assert_equal(service.payload(), initial_profile_payload, "backup/export preserve gameplay Profile")
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_DPAD_DOWN
	event.pressed = true
	suite.assert_true(panel.handle_input(event), "controller can navigate the native panel")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	var closes := {"count": 0}
	panel.closed.connect(func(): closes.count += 1)
	suite.assert_true(panel.handle_input(cancel) and not panel.is_open() and closes.count == 1, "controller cancel closes exactly once")
	suite.assert_true(not panel.handle_input(cancel), "closed panel does not consume input")
	suite.assert_true(panel.open().ok and panel.select_section("community").ok, "panel can reopen community view")
	suite.assert_equal(panel.view_state().model.friends, [], "native offline friends stay an honest empty state")
	panel.close_panel()
	panel.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _button(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if control is Button and control.get_meta("action_id", "") == id:
			return control
	return null
