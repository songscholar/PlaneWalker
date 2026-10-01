extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const HudScene := preload("res://scenes/ui/combat_hud_v2.tscn")
const HUD_VIEW_PATH := "res://scripts/ui/views/combat_hud_view.gd"
const M1_ARCHETYPE_SCORES := {
	"freeze_burst": 1,
	"rewind_echo": 0,
	"accelerated_combo": 0,
}

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
	var skill_content := hud.get_node("HudRoot/SafeArea/HudLayout/SkillPanel/SkillContent")
	_suite.assert_true(skill_content.get_node_or_null("StopLabel") == null, "legacy StopLabel node is removed")
	_suite.assert_true(skill_content.get_node_or_null("RewindLabel") == null, "legacy RewindLabel node is removed")
	var slot_one := skill_content.get_node_or_null("AbilitySlot1Label") as Label
	var slot_two := skill_content.get_node_or_null("AbilitySlot2Label") as Label
	_suite.assert_true(slot_one != null, "first generic ability-slot label exists")
	_suite.assert_true(slot_two != null, "second generic ability-slot label exists")
	var exported_slot_labels: Variant = hud.get("skill_slot_labels")
	_suite.assert_true(exported_slot_labels is Array, "HUD exposes generic skill-slot labels")
	if exported_slot_labels is Array:
		var labels := exported_slot_labels as Array
		_suite.assert_equal(labels.size(), 2, "HUD exposes exactly two generic skill-slot labels")
		if labels.size() == 2:
			_suite.assert_true(labels[0] == slot_one, "first exported slot follows scene order")
			_suite.assert_true(labels[1] == slot_two, "second exported slot follows scene order")
	var weapon_panel := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/WeaponPanel") as PanelContainer
	var weapon_name_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponNameLabel") as Label
	var weapon_meter_bar := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponMeterBar") as ProgressBar
	var weapon_meter_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponMeterLabel") as Label
	var weapon_status_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponStatusLabel") as Label
	_suite.assert_true(weapon_panel != null, "generic weapon panel exists")
	_suite.assert_true(weapon_name_label != null, "generic weapon name label exists")
	_suite.assert_true(weapon_meter_bar != null, "generic weapon meter bar exists")
	_suite.assert_true(weapon_meter_label != null, "generic weapon meter label exists")
	_suite.assert_true(weapon_status_label != null, "generic weapon status label exists")
	var character_panel := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/CharacterPanel") as PanelContainer
	var character_name_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterNameLabel") as Label
	var character_meter_bar := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterMeterBar") as ProgressBar
	var character_meter_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterMeterLabel") as Label
	var character_status_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterStatusLabel") as Label
	var character_cooldown_label := hud.get_node_or_null("HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterCooldownLabel") as Label
	_suite.assert_true(character_panel != null, "generic character panel exists")
	_suite.assert_true(character_name_label != null, "generic character name label exists")
	_suite.assert_true(character_meter_bar != null, "generic character meter bar exists")
	_suite.assert_true(character_meter_label != null, "generic character meter label exists")
	_suite.assert_true(character_status_label != null, "generic character status label exists")
	_suite.assert_true(character_cooldown_label != null, "generic character cooldown label exists")
	var hud_source := _read_text(HUD_VIEW_PATH)
	_suite.assert_true(
		hud_source.contains('archetype.to_upper() + "_NAME"'),
		"HUD resolves dominant archetypes through the authoritative ARCHETYPE_<ID>_NAME key"
	)

	var combat := _load_json("res://tests/fixtures/ui/hud_combat.json")
	_set_build_domain(combat, M1_ARCHETYPE_SCORES, "freeze_burst")
	var combat_input := combat.duplicate(true)
	var result = hud.render(combat)
	_suite.assert_true(result.ok, "combat state renders")
	_suite.assert_close(hud.hp_bar.max_value, 200.0, "hp maximum renders")
	_suite.assert_close(hud.hp_bar.value, 160.0, "hp current renders")
	_suite.assert_close(hud.energy_bar.max_value, 100.0, "energy maximum renders")
	_suite.assert_close(hud.energy_bar.value, 72.0, "energy current renders")
	_suite.assert_equal(hud.room_label.text, "1 / 5", "room progress renders")
	_suite.assert_true(hud.build_label.text.contains(tr("ARCHETYPE_FREEZE_BURST_NAME")), "build label uses the localized archetype name")
	_suite.assert_true(not hud.build_label.text.contains("freeze_burst"), "build label never exposes the raw archetype id")
	if weapon_name_label != null and weapon_meter_bar != null and weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_equal(weapon_name_label.text, tr("WEAPON_GUN_NAME"), "Gun name is localized")
		_suite.assert_close(weapon_meter_bar.max_value, 6.0, "Gun ammo maximum renders")
		_suite.assert_close(weapon_meter_bar.value, 4.0, "Gun current ammo renders")
		_suite.assert_true(weapon_meter_label.text.contains("4 / 6"), "Gun ammo renders as current over maximum")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_TIME_LOAD")), "Gun Time Load status renders")
		_suite.assert_true(weapon_status_label.text.contains("3.0"), "Gun Time Load remaining duration renders")
		_suite.assert_true(not weapon_name_label.text.contains("normal_fire"), "weapon name never leaks action id")
		_suite.assert_true(not weapon_meter_label.text.contains("normal_fire"), "weapon meter never leaks action id")
		_suite.assert_true(not weapon_status_label.text.contains("normal_fire"), "weapon status never leaks action id")
	if character_panel != null and character_name_label != null and character_meter_bar != null and character_meter_label != null and character_status_label != null and character_cooldown_label != null:
		_suite.assert_true(character_panel.visible, "Launch character state shows the generic panel")
		_suite.assert_equal(character_name_label.text, tr("CHARACTER_TIME_LORD_NAME"), "character name is localized")
		_suite.assert_close(character_meter_bar.max_value, 3.0, "Codex Page maximum renders")
		_suite.assert_close(character_meter_bar.value, 2.0, "Codex Page current value renders")
		_suite.assert_true(character_meter_label.text.contains("2 / 3"), "character meter renders current over maximum")
		_suite.assert_true(character_status_label.text.contains(tr("TIME_ABILITY_STOP_NAME")), "Primer renders its localized ability")
		_suite.assert_true(character_status_label.text.contains("5.0"), "Primer duration renders in seconds")
		_suite.assert_true(character_cooldown_label.text.contains("2.0"), "character cooldown renders in seconds")
		_suite.assert_true(not character_name_label.text.contains("time_lord"), "character name never leaks internal id")
		_suite.assert_true(not character_meter_label.text.contains("codex_pages"), "character meter never leaks internal id")
		_suite.assert_true(not character_status_label.text.contains("primer"), "character status never leaks internal id")
	if slot_one != null and slot_two != null:
		_suite.assert_true(slot_one.text.contains(tr("TIME_ABILITY_STOP_NAME")), "first slot renders localized Stop name")
		_suite.assert_true(slot_one.text.contains(tr("HUD_WEAPON_READY")), "ready skill state renders")
		_suite.assert_true(slot_two.text.contains(tr("TIME_ABILITY_RIFT_NAME")), "second slot renders localized Rift name")
		_suite.assert_true(slot_two.text.contains("4.5"), "cooldown skill state renders")
		_suite.assert_true(slot_two.text.contains(tr("HUD_WEAPON_COOLDOWN_FMT").get_slice("%", 0).strip_edges()), "cooldown wording is localized")
		_suite.assert_true(not slot_one.text.begins_with("Q"), "slot text does not hard-code the legacy Q hint")
		_suite.assert_true(not slot_two.text.begins_with("E"), "slot text does not hard-code the legacy E hint")
		_suite.assert_true(not slot_one.text.contains("time_stop"), "slot text does not leak the input action id")
		_suite.assert_true(not slot_two.text.contains("time_rift"), "slot text does not leak the input action id")
	_suite.assert_true(not hud.low_hp_indicator.visible, "normal hp hides danger indicator")
	_suite.assert_true(not hud.boss_panel.visible, "combat state hides boss panel")
	_assert_control_fits(hud.hud_root, hud.hud_root, "HUD root fits 640x360")
	_assert_control_fits(hud.hud_root, hud.get_node("HudRoot/SafeArea/HudLayout/RoomPanel"), "room panel fits 640x360")
	_assert_control_fits(hud.hud_root, hud.get_node("HudRoot/SafeArea/HudLayout/PlayerPanel"), "player panel fits 640x360")
	_assert_control_fits(hud.hud_root, hud.get_node("HudRoot/SafeArea/HudLayout/SkillPanel"), "skill panel fits 640x360")
	if weapon_panel != null:
		_assert_control_fits(hud.hud_root, weapon_panel, "weapon panel fits 640x360")
	if character_panel != null:
		_assert_control_fits(hud.hud_root, character_panel, "character panel fits 640x360")

	var cached_archetype_id := str(hud.latest_state()["build"]["dominant_archetype"])
	TranslationServer.set_locale("zh_CN")
	await get_tree().process_frame
	if slot_one != null and slot_two != null:
		_suite.assert_true(slot_one.text.contains("时间停止"), "locale change redraws cached Stop name")
		_suite.assert_true(slot_one.text.contains("就绪"), "locale change redraws cached ready state")
		_suite.assert_true(slot_two.text.contains("时间裂隙"), "locale change redraws cached Rift name")
		_suite.assert_true(slot_two.text.contains("冷却"), "locale change redraws cached cooldown state")
	_suite.assert_true(hud.build_label.text.contains("流派"), "locale change redraws cached build label")
	_suite.assert_true(hud.build_label.text.contains(tr("ARCHETYPE_FREEZE_BURST_NAME")), "locale change redraws the localized archetype name")
	_suite.assert_equal(hud.latest_state()["build"]["dominant_archetype"], cached_archetype_id, "locale refresh preserves the cached stable archetype id")
	if weapon_name_label != null and weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_equal(weapon_name_label.text, "枪", "locale change redraws Gun name")
		_suite.assert_true(weapon_meter_label.text.contains("弹药"), "locale change redraws Gun ammo meter")
		_suite.assert_true(weapon_status_label.text.contains("时间装填"), "locale change redraws Time Load status")
	if character_name_label != null and character_meter_label != null and character_status_label != null and character_cooldown_label != null:
		_suite.assert_equal(character_name_label.text, "时之领主", "locale change redraws character name")
		_suite.assert_true(character_meter_label.text.contains("秘典页"), "locale change redraws character meter")
		_suite.assert_true(character_status_label.text.contains("引式"), "locale change redraws character status")
		_suite.assert_true(character_cooldown_label.text.contains("冷却"), "locale change redraws character cooldown")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	if slot_one != null:
		_suite.assert_true(slot_one.text.contains("Ready"), "locale can switch back without a newer view revision")

	var duplicate_result = hud.render(combat)
	_suite.assert_true(not duplicate_result.ok, "same revision is rejected")
	_suite.assert_equal(duplicate_result.code, &"STALE_REVISION", "same revision reports stable error code")

	var low_hp := _load_json("res://tests/fixtures/ui/hud_low_hp.json")
	var low_hp_scores := M1_ARCHETYPE_SCORES.duplicate(true)
	low_hp_scores["freeze_burst"] = 2
	_set_build_domain(low_hp, low_hp_scores, "freeze_burst")
	_suite.assert_true(hud.render(low_hp).ok, "newer low hp state renders")
	_suite.assert_true(hud.low_hp_indicator.visible, "low hp state shows danger indicator")
	if slot_one != null and slot_two != null:
		_suite.assert_true(slot_one.text.contains(tr("TIME_ABILITY_RIFT_NAME")), "first slot updates from fixture order")
		_suite.assert_true(slot_two.text.contains(tr("TIME_ABILITY_ACCELERATE_NAME")), "second slot updates from fixture order")
	if weapon_name_label != null and weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_equal(weapon_name_label.text, tr("WEAPON_BOW_NAME"), "Bow fixture renders localized weapon name")
		_suite.assert_true(weapon_meter_label.text.contains("30 / 48"), "Bow charge meter renders")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_CHARGING")), "Bow charging status renders")

	var older_result = hud.render(combat)
	_suite.assert_true(not older_result.ok, "older revision is rejected")
	_suite.assert_equal(older_result.code, &"STALE_REVISION", "older revision reports stable error code")

	var boss := _load_json("res://tests/fixtures/ui/hud_boss.json")
	var boss_scores := M1_ARCHETYPE_SCORES.duplicate(true)
	boss_scores["freeze_burst"] = 3
	boss_scores["rewind_echo"] = 1
	_set_build_domain(boss, boss_scores, "freeze_burst")
	_suite.assert_true(hud.render(boss).ok, "boss state renders")
	_suite.assert_true(hud.boss_panel.visible, "boss state shows boss panel")
	_suite.assert_close(hud.boss_hp_bar.max_value, 420.0, "boss hp maximum renders")
	_suite.assert_close(hud.boss_hp_bar.value, 315.0, "boss hp current renders")
	_suite.assert_true(hud.boss_phase_label.text.contains("2 / 3"), "boss phase renders")
	if slot_one != null and slot_two != null:
		_suite.assert_true(slot_one.text.contains(tr("TIME_ABILITY_REWIND_NAME")), "boss fixture first slot preserves Rewind order")
		_suite.assert_true(slot_two.text.contains(tr("TIME_ABILITY_STOP_NAME")), "boss fixture second slot preserves Stop order")
	if weapon_name_label != null and weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_equal(weapon_name_label.text, tr("WEAPON_SWORD_NAME"), "Sword fixture renders localized weapon name")
		_suite.assert_true(weapon_meter_label.text.contains("1 / 1"), "Sword counter meter renders")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_COUNTER_READY")), "Sword counter readiness renders")
	_assert_control_fits(hud.hud_root, hud.boss_panel, "boss panel fits 640x360")
	for resolution: Vector2i in [
		Vector2i(640, 360),
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1080),
	]:
		await _assert_layout_at_resolution(hud, weapon_panel, resolution)

	var next_run := combat.duplicate(true)
	next_run["run_id"] = "fixture-run-two"
	next_run["revision"] = 0
	next_run["weapon_state"] = {
		"weapon_id": "gun",
		"action_id": "reload",
		"phase": "RECOVERY",
		"meter_kind": "reload",
		"meter_current": 40,
		"meter_max": 48,
		"status_id": "perfect_reload",
		"status_stacks": 1,
		"status_remaining": 0,
		"secondary_id": "time_load",
		"secondary_value": 300,
	}
	_suite.assert_true(hud.render(next_run).ok, "new run id resets the revision baseline")
	if weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_true(weapon_meter_label.text.contains("40 / 48"), "perfect reload keeps the reload meter visible")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_PERFECT_RELOAD")), "perfect reload has an explicit localized status")
		_suite.assert_true(not weapon_status_label.text.contains("reload"), "perfect reload status does not expose the internal action id")
	var staff_run := combat.duplicate(true)
	staff_run["run_id"] = "fixture-staff-run"
	staff_run["revision"] = 0
	staff_run["weapon_state"] = {
		"weapon_id": "staff",
		"action_id": "primordial_wrath",
		"phase": "RECOVERY",
		"meter_kind": "mana",
		"meter_current": 74,
		"meter_max": 100,
		"status_id": "sequence_ready",
		"status_stacks": 1,
		"status_remaining": 180,
		"secondary_id": "element",
		"secondary_value": 1,
	}
	_suite.assert_true(hud.render(staff_run).ok, "Staff weapon state renders")
	if weapon_name_label != null and weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_equal(weapon_name_label.text, tr("WEAPON_STAFF_NAME"), "Staff name is localized")
		_suite.assert_true(weapon_meter_label.text.contains("74 / 100"), "Staff Mana meter renders")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_SEQUENCE_READY")), "Staff sequence-ready status renders")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_ELEMENT_FIRE")), "Staff current element renders")
		_suite.assert_true(weapon_status_label.text.contains("3.0"), "Staff sequence duration renders in seconds")
		_suite.assert_true(not weapon_status_label.text.contains("primordial_wrath"), "Staff HUD does not expose the internal action id")
	var gauntlets_run := combat.duplicate(true)
	gauntlets_run["run_id"] = "fixture-gauntlets-run"
	gauntlets_run["revision"] = 0
	gauntlets_run["weapon_state"] = {
		"weapon_id": "gauntlets",
		"action_id": "",
		"phase": "READY",
		"meter_kind": "combo",
		"meter_current": 15,
		"meter_max": 30,
		"status_id": "combo_active",
		"status_stacks": 1,
		"status_remaining": 120,
		"secondary_id": "combo",
		"secondary_value": 15,
	}
	_suite.assert_true(hud.render(gauntlets_run).ok, "Gauntlets weapon state renders")
	if weapon_name_label != null and weapon_meter_label != null and weapon_status_label != null:
		_suite.assert_equal(weapon_name_label.text, tr("WEAPON_GAUNTLETS_NAME"), "Gauntlets name is localized")
		_suite.assert_true(weapon_meter_label.text.contains("15 / 30"), "Gauntlets Combo meter renders")
		_suite.assert_true(weapon_status_label.text.contains(tr("HUD_WEAPON_STATUS_COMBO_ACTIVE")), "Gauntlets active Combo status renders")
		_suite.assert_true(not weapon_status_label.text.contains("gauntlets"), "Gauntlets HUD does not expose an internal identifier")
	var m1_run := combat.duplicate(true)
	m1_run["run_id"] = "fixture-m1-character-run"
	m1_run["revision"] = 0
	m1_run["character_state"] = null
	_suite.assert_true(hud.render(m1_run).ok, "M1 compatibility state renders")
	if character_panel != null:
		_suite.assert_true(not character_panel.visible, "M1 compatibility hides the Launch character HUD")
	_suite.assert_equal(combat, combat_input, "render treats the supplied snapshot as immutable input")
	var latest: Dictionary = hud.latest_state()
	if not latest.is_empty():
		latest["player"]["time_slots"][0]["ability_id"] = "changed"
		latest["player"]["time_slots"].reverse()
		var latest_again: Dictionary = hud.latest_state()
		_suite.assert_equal(latest_again["player"]["time_slots"][0]["ability_id"], "stop", "latest state deep-copies slot dictionaries")
		_suite.assert_equal(latest_again["player"]["time_slots"][1]["ability_id"], "rift", "latest state preserves configured slot order")
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


func _assert_layout_at_resolution(hud: CanvasLayer, weapon_panel: PanelContainer, resolution: Vector2i) -> void:
	get_window().size = resolution
	await get_tree().process_frame
	await get_tree().process_frame
	var label := "%dx%d" % [resolution.x, resolution.y]
	var safe_area := hud.get_node("HudRoot/SafeArea") as Control
	var room_panel := hud.get_node("HudRoot/SafeArea/HudLayout/RoomPanel") as Control
	var player_panel := hud.get_node("HudRoot/SafeArea/HudLayout/PlayerPanel") as Control
	var skill_panel := hud.get_node("HudRoot/SafeArea/HudLayout/SkillPanel") as Control
	var character_panel := hud.get_node("HudRoot/SafeArea/HudLayout/CharacterPanel") as Control
	_assert_control_fits(hud.hud_root, safe_area, "safe area fits %s" % label)
	_assert_control_fits(safe_area, room_panel, "room panel fits safe area at %s" % label)
	_assert_control_fits(safe_area, player_panel, "player panel fits safe area at %s" % label)
	_assert_control_fits(safe_area, skill_panel, "skill panel fits safe area at %s" % label)
	_assert_control_fits(safe_area, character_panel, "character panel fits safe area at %s" % label)
	if weapon_panel != null:
		_assert_control_fits(safe_area, weapon_panel, "weapon panel fits safe area at %s" % label)
		_suite.assert_true(
			not weapon_panel.get_global_rect().intersects(hud.boss_panel.get_global_rect()),
			"weapon and boss panels do not overlap at %s" % label
		)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_suite.assert_true(file != null, "%s opens" % path)
	if file == null:
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	_suite.assert_equal(error, OK, "%s parses" % path)
	if error != OK or not json.data is Dictionary:
		return {}
	return (json.data as Dictionary).duplicate(true)


func _set_build_domain(state: Dictionary, scores: Dictionary, dominant_archetype: String) -> void:
	if state.is_empty() or not state.get("build") is Dictionary:
		return
	state["build"]["archetype_scores"] = scores.duplicate(true)
	state["build"]["dominant_archetype"] = dominant_archetype


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var contents := file.get_as_text()
	file.close()
	return contents
