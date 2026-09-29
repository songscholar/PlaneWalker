extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const AccessibilityRuntimeScript := preload("res://scripts/accessibility/accessibility_runtime.gd")
const SubtitlePresenterScript := preload("res://scripts/accessibility/subtitle_presenter.gd")

const EXPECTED_DEFAULTS := {
	"locale": "zh_CN",
	"master_volume": 0.85,
	"master_muted": false,
	"music_volume": 0.80,
	"sfx_volume": 0.90,
	"dialogue_volume": 0.90,
	"camera_shake_enabled": true,
	"hit_flash_enabled": true,
	"reduced_motion": false,
	"text_scale": 1.0,
	"high_contrast_danger": false,
	"subtitles_enabled": true,
	"subtitle_scale": 1.0,
	"ranged_charge_mode": "hold",
	"damage_received_multiplier": 1.0,
	"enemy_telegraph_scale": 1.0,
}

var _original_save_path: String
var _original_persistent: Dictionary
var _test_root: String


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_original_save_path = GameState.save_path
	_original_persistent = GameState.persistent.duplicate(true)
	_test_root = _unique_test_root()
	_remove_tree(_test_root)

	GameState.save_path = _test_root.path_join("legacy.json")
	GameState.reset_persistent_data(true)
	suite.assert_equal(GameState.normalized_settings(), EXPECTED_DEFAULTS, "all Current accessibility defaults are exposed")

	var service = SaveServiceScript.new()
	var configured = service.configure(_service_root(), "0.4.0-dev", _content_snapshot())
	suite.assert_true(configured.ok, "historical settings fixture service configures")
	var historical_settings := {
		"locale": "en",
		"master_volume": 0.65,
		"master_muted": false,
		"camera_shake_enabled": false,
		"hit_flash_enabled": true,
		"reduced_motion": true,
	}
	suite.assert_true(service.save_settings(historical_settings).ok, "historical six-field settings save")
	GameState.persistent = {}
	suite.assert_true(GameState.load_persistent(), "historical six-field settings load")
	var historical_normalized := EXPECTED_DEFAULTS.duplicate(true)
	for setting_id: String in historical_settings:
		historical_normalized[setting_id] = historical_settings[setting_id]
	suite.assert_equal(GameState.normalized_settings(), historical_normalized, "missing accessibility fields receive exact defaults")

	for setting_id: String in EXPECTED_DEFAULTS.keys():
		var expected: Variant = EXPECTED_DEFAULTS[setting_id]
		if setting_id == "text_scale":
			expected = 1.5
		elif setting_id == "subtitle_scale":
			expected = 1.25
		elif setting_id == "ranged_charge_mode":
			expected = "toggle"
		elif setting_id == "damage_received_multiplier":
			expected = 0.6
		elif setting_id == "enemy_telegraph_scale":
			expected = 1.5
		elif setting_id == "music_volume":
			expected = 0.35
		elif setting_id == "high_contrast_danger":
			expected = true
		suite.assert_true(GameState.set_setting(setting_id, expected), "%s persists" % setting_id)

	var saved := GameState.normalized_settings()
	GameState.persistent = {}
	suite.assert_true(GameState.load_persistent(), "expanded settings reload")
	suite.assert_equal(GameState.normalized_settings(), saved, "every expanded setting survives restart")

	var ui_root := Control.new()
	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	ui_root.add_child(title_label)
	var subtitle_presenter = SubtitlePresenterScript.new()
	ui_root.add_child(subtitle_presenter)
	add_child(ui_root)
	var accessibility = AccessibilityRuntimeScript.new()
	add_child(accessibility)
	await get_tree().process_frame
	accessibility.apply_to_tree(ui_root)
	suite.assert_equal(accessibility.settings_snapshot()["text_scale"], 1.5, "text scale applies immediately")
	suite.assert_equal(title_label.get_theme_font_size("font_size"), 24, "title text scales from its base size")
	accessibility.apply_to_tree(ui_root)
	suite.assert_equal(title_label.get_theme_font_size("font_size"), 24, "reapplying text scale is not cumulative")
	suite.assert_close(accessibility.damage_received_multiplier(), 0.6, "damage assist is available to gameplay composition")
	suite.assert_close(accessibility.enemy_telegraph_scale(), 1.5, "telegraph scale is available to presentation")

	suite.assert_true(GameState.set_setting("text_scale", 1.25), "runtime text scale update persists")
	suite.assert_equal(title_label.get_theme_font_size("font_size"), 20, "setting changes rescale from the stored base")
	suite.assert_true(GameState.set_setting("subtitles_enabled", false), "subtitle disable persists")
	subtitle_presenter.present(&"TEST_SUBTITLE", 1.0)
	suite.assert_true(not subtitle_presenter.visible, "disabled subtitles remain hidden")
	suite.assert_true(GameState.set_setting("subtitles_enabled", true), "subtitle enable persists")
	suite.assert_true(GameState.set_setting("text_scale", 1.5), "general text scale can differ from subtitle scale")
	suite.assert_true(GameState.set_setting("subtitle_scale", 1.25), "subtitle scale persists")
	subtitle_presenter.present(&"TEST_SUBTITLE", 1.0, &"TEST_SPEAKER")
	suite.assert_true(subtitle_presenter.visible, "enabled subtitles are visible without spoken audio")
	suite.assert_equal(subtitle_presenter.get_snapshot_for_test()["font_size"], 20, "subtitle scale remains independent from general UI text scale")
	suite.assert_true(AudioServer.get_bus_index(&"Music") >= 0, "Music bus exists")
	suite.assert_true(AudioServer.get_bus_index(&"SFX") >= 0, "SFX bus exists")
	suite.assert_true(AudioServer.get_bus_index(&"Dialogue") >= 0, "Dialogue bus exists")
	var music_bus := AudioServer.get_bus_index(&"Music")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	suite.assert_close(
		AudioServer.get_bus_volume_db(music_bus),
		linear_to_db(0.35),
		"Music volume maps deterministically from linear settings"
	)
	suite.assert_true(GameState.set_setting("master_muted", true), "master mute persists")
	suite.assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "master mute applies to Master")
	suite.assert_true(not AudioServer.is_bus_mute(sfx_bus), "master mute does not mutate the SFX bus mute flag")
	suite.assert_true(GameState.set_setting("master_muted", false), "master unmute persists")

	accessibility.queue_free()
	ui_root.queue_free()
	await get_tree().process_frame

	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	_remove_tree(_test_root)
	suite.finish(get_tree())


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("accessibility_settings_%d" % Time.get_ticks_usec())


func _service_root() -> String:
	return GameState.save_path.get_base_dir().path_join("plane_walker").path_join("save")


func _content_snapshot() -> Dictionary:
	var packs: Array = [{
		"pack_id": "base",
		"pack_version": "0.4.0-dev",
		"schema_version": 1,
		"fingerprint_sha256": "1".repeat(64),
	}]
	return {
		"aggregate_sha256": SaveEnvelopeScript.content_snapshot_digest(packs),
		"packs": packs,
	}


func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			_remove_tree(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
