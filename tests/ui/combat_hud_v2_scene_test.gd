extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const HudScene := preload("res://scenes/ui/combat_hud_v2.tscn")
const FixturesScript := preload("res://scripts/ui/fixtures/run_view_state_fixtures.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var original_phase: int = GameState.phase
	var hud := HudScene.instantiate()
	add_child(hud)
	await get_tree().process_frame

	var combat := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_combat.json")
	var result = hud.render(combat)
	_suite.assert_true(result.ok, "combat state renders")
	_suite.assert_close(hud.hp_bar.max_value, 200.0, "hp maximum renders")
	_suite.assert_close(hud.hp_bar.value, 160.0, "hp current renders")
	_suite.assert_close(hud.energy_bar.max_value, 100.0, "energy maximum renders")
	_suite.assert_close(hud.energy_bar.value, 72.0, "energy current renders")
	_suite.assert_equal(hud.room_label.text, "1 / 5", "room progress renders")
	_suite.assert_true(hud.stop_label.text.contains("READY"), "ready skill state renders")
	_suite.assert_true(hud.rewind_label.text.contains("4.5"), "cooldown skill state renders")
	_suite.assert_true(not hud.low_hp_indicator.visible, "normal hp hides danger indicator")
	_suite.assert_true(not hud.boss_panel.visible, "combat state hides boss panel")

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

	var next_run := combat.duplicate(true)
	next_run["run_id"] = "fixture-run-two"
	next_run["revision"] = 0
	_suite.assert_true(hud.render(next_run).ok, "new run id resets the revision baseline")
	_suite.assert_equal(GameState.phase, original_phase, "render leaves gameplay phase unchanged")
	_suite.assert_true(hud.get_node_or_null("Player") == null, "standalone hud has no player dependency")

	hud.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())
