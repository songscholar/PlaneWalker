extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const HudScene := preload("res://scenes/ui/combat_hud_v2.tscn")
const FixturesScript := preload("res://scripts/ui/fixtures/run_view_state_fixtures.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var original_locale := str(TranslationServer.get_locale())
	var original_window_size := get_window().size
	get_window().size = Vector2i(640, 360)
	TranslationServer.set_locale("en")
	var hud := HudScene.instantiate()
	add_child(hud)
	await get_tree().process_frame

	var combat := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_combat.json")
	var combat_input := combat.duplicate(true)
	var result = hud.render(combat)
	_suite.assert_true(result.ok, "combat state renders")
	_suite.assert_close(hud.hp_bar.max_value, 200.0, "hp maximum renders")
	_suite.assert_close(hud.hp_bar.value, 160.0, "hp current renders")
	_suite.assert_close(hud.energy_bar.max_value, 100.0, "energy maximum renders")
	_suite.assert_close(hud.energy_bar.value, 72.0, "energy current renders")
	_suite.assert_equal(hud.room_label.text, "1 / 5", "room progress renders")
	_suite.assert_true(hud.stop_label.text.contains("Ready"), "ready skill state renders")
	_suite.assert_true(hud.rewind_label.text.contains("4.5"), "cooldown skill state renders")
	_suite.assert_true(not hud.low_hp_indicator.visible, "normal hp hides danger indicator")
	_suite.assert_true(not hud.boss_panel.visible, "combat state hides boss panel")
	_assert_control_fits(hud.hud_root, hud.hud_root, "HUD root fits 640x360")
	_assert_control_fits(hud.hud_root, hud.get_node("HudRoot/SafeArea/HudLayout/RoomPanel"), "room panel fits 640x360")
	_assert_control_fits(hud.hud_root, hud.get_node("HudRoot/SafeArea/HudLayout/PlayerPanel"), "player panel fits 640x360")
	_assert_control_fits(hud.hud_root, hud.get_node("HudRoot/SafeArea/HudLayout/SkillPanel"), "skill panel fits 640x360")

	TranslationServer.set_locale("zh_CN")
	await get_tree().process_frame
	_suite.assert_true(hud.stop_label.text.contains("就绪"), "locale change redraws cached ready state")
	_suite.assert_true(hud.build_label.text.contains("流派"), "locale change redraws cached build label")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	_suite.assert_true(hud.stop_label.text.contains("Ready"), "locale can switch back without a newer view revision")

	var duplicate_result = hud.render(combat)
	_suite.assert_true(not duplicate_result.ok, "same revision is rejected")
	_suite.assert_equal(duplicate_result.code, &"STALE_REVISION", "same revision reports stable error code")

	var low_hp := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_low_hp.json")
	_suite.assert_true(hud.render(low_hp).ok, "newer low hp state renders")
	_suite.assert_true(hud.low_hp_indicator.visible, "low hp state shows danger indicator")

	var older_result = hud.render(combat)
	_suite.assert_true(not older_result.ok, "older revision is rejected")
	_suite.assert_equal(older_result.code, &"STALE_REVISION", "older revision reports stable error code")

	var boss := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_boss.json")
	_suite.assert_true(hud.render(boss).ok, "boss state renders")
	_suite.assert_true(hud.boss_panel.visible, "boss state shows boss panel")
	_suite.assert_close(hud.boss_hp_bar.max_value, 420.0, "boss hp maximum renders")
	_suite.assert_close(hud.boss_hp_bar.value, 315.0, "boss hp current renders")
	_suite.assert_true(hud.boss_phase_label.text.contains("2 / 3"), "boss phase renders")
	_assert_control_fits(hud.hud_root, hud.boss_panel, "boss panel fits 640x360")

	var next_run := combat.duplicate(true)
	next_run["run_id"] = "fixture-run-two"
	next_run["revision"] = 0
	_suite.assert_true(hud.render(next_run).ok, "new run id resets the revision baseline")
	_suite.assert_equal(combat, combat_input, "render treats the supplied snapshot as immutable input")
	_suite.assert_true(hud.get_node_or_null("Player") == null, "standalone hud has no player dependency")

	hud.queue_free()
	await get_tree().process_frame
	TranslationServer.set_locale(original_locale)
	get_window().size = original_window_size
	_suite.finish(get_tree())


func _assert_control_fits(root: Control, control: Control, label: String) -> void:
	var root_rect := root.get_global_rect()
	var control_rect := control.get_global_rect()
	_suite.assert_true(control_rect.position.x >= root_rect.position.x, "%s left edge" % label)
	_suite.assert_true(control_rect.position.y >= root_rect.position.y, "%s top edge" % label)
	_suite.assert_true(control_rect.end.x <= root_rect.end.x, "%s right edge" % label)
	_suite.assert_true(control_rect.end.y <= root_rect.end.y, "%s bottom edge" % label)
