extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")

const M1_ARCHETYPE_SCORES := {
	"freeze_burst": 1,
	"rewind_echo": 0,
	"accelerated_combo": 0,
}
const LAUNCH_ARCHETYPE_SCORES := {
	"freeze_burst": 1,
	"rewind_echo": 0,
	"rift_trap": 0,
	"accelerated_combo": 0,
	"low_hp_void": 0,
	"perfect_guard": 0,
	"piercing_barrage": 0,
	"echo_legion": 0,
}

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()

	var combat := _load_json("res://tests/fixtures/ui/hud_combat.json")
	_set_build_domain(combat, M1_ARCHETYPE_SCORES, "freeze_burst")
	_suite.assert_true(not combat.is_empty(), "combat fixture loads")
	_suite.assert_true(RunViewStateScript.validate(combat).ok, "combat fixture validates")
	_suite.assert_equal(RunViewStateScript.SCHEMA_VERSION, 5, "active item union uses view-state schema 5")
	_suite.assert_equal(
		combat.get("active_item_state", {}).get("content_id"),
		"absolute_zero_device",
		"combat fixture carries the equipped active identity"
	)
	var missing_active_state := combat.duplicate(true)
	missing_active_state.erase("active_item_state")
	_suite.assert_true(not RunViewStateScript.validate(missing_active_state).ok, "active item state key is required")
	var cooldown_overflow := combat.duplicate(true)
	cooldown_overflow["active_item_state"]["cooldown_current"] = 901
	_suite.assert_true(not RunViewStateScript.validate(cooldown_overflow).ok, "active cooldown cannot exceed its maximum")
	var ready_with_cooldown := combat.duplicate(true)
	ready_with_cooldown["active_item_state"]["ready"] = true
	_suite.assert_true(not RunViewStateScript.validate(ready_with_cooldown).ok, "ready active cannot retain cooldown")

	var low_hp := _load_json("res://tests/fixtures/ui/hud_low_hp.json")
	_set_build_domain(low_hp, M1_ARCHETYPE_SCORES, "freeze_burst")
	_suite.assert_true(not low_hp.is_empty(), "low hp fixture loads")
	_suite.assert_true(RunViewStateScript.validate(low_hp).ok, "low hp fixture validates")

	var boss := _load_json("res://tests/fixtures/ui/hud_boss.json")
	var boss_scores := M1_ARCHETYPE_SCORES.duplicate(true)
	boss_scores["freeze_burst"] = 3
	boss_scores["rewind_echo"] = 1
	_set_build_domain(boss, boss_scores, "freeze_burst")
	_suite.assert_true(not boss.is_empty(), "boss fixture loads")
	_suite.assert_true(RunViewStateScript.validate(boss).ok, "boss fixture validates")
	_assert_slot_order(combat, ["stop", "rift"], ["time_stop", "time_rift"], "combat fixture")
	_assert_slot_order(low_hp, ["rift", "accelerate"], ["time_rift", "time_accelerate"], "low-hp fixture")
	_assert_slot_order(boss, ["rewind", "stop"], ["time_rewind", "time_stop"], "boss fixture")
	_assert_weapon_state(combat, "gun", "ammo", "time_load", "combat fixture")
	_assert_weapon_state(low_hp, "bow", "charge", "charging", "low-hp fixture")
	_assert_weapon_state(boss, "sword", "counter", "counter_ready", "boss fixture")
	_assert_character_state(combat, "time_lord", "codex_pages", "primer", "combat fixture")
	_assert_character_state(low_hp, "void_walker", "void_debt", "corruption", "low-hp fixture")
	_assert_character_state(boss, "time_guardian", "ward", "fortress", "boss fixture")
	var staff_state := combat.duplicate(true)
	staff_state["weapon_state"] = {
		"weapon_id": "staff",
		"action_id": "",
		"phase": "READY",
		"meter_kind": "mana",
		"meter_current": 74,
		"meter_max": 100,
		"status_id": "sequence_ready",
		"status_stacks": 1,
		"status_remaining": 180,
		"secondary_id": "element",
		"secondary_value": 1,
	}
	_suite.assert_true(RunViewStateScript.validate(staff_state).ok, "Staff Mana, element, and sequence window validate")
	var invalid_staff_element := staff_state.duplicate(true)
	invalid_staff_element["weapon_state"]["secondary_value"] = 4
	_suite.assert_true(not RunViewStateScript.validate(invalid_staff_element).ok, "unknown Staff element code is rejected")
	var expired_staff_sequence := staff_state.duplicate(true)
	expired_staff_sequence["weapon_state"]["status_remaining"] = 0
	_suite.assert_true(not RunViewStateScript.validate(expired_staff_sequence).ok, "Staff sequence-ready status requires remaining time")

	_assert_invalid(combat, "schema_version", null, "missing schema version is rejected", true)
	_assert_invalid(combat, "schema_version", 4, "pre-active-item schema is rejected")
	_assert_invalid(combat, "schema_version", 99, "unknown schema version is rejected")
	_assert_invalid(combat, "revision", -1, "negative revision is rejected")
	_assert_invalid(combat, "run_id", "", "empty run id is rejected")
	_assert_invalid(combat, "phase", "UNKNOWN", "unknown phase is rejected")

	var hp_over_max := combat.duplicate(true)
	hp_over_max["player"]["hp"] = 201.0
	_suite.assert_true(not RunViewStateScript.validate(hp_over_max).ok, "hp above maximum is rejected")

	var energy_over_max := combat.duplicate(true)
	energy_over_max["player"]["energy"] = 101.0
	_suite.assert_true(not RunViewStateScript.validate(energy_over_max).ok, "energy above maximum is rejected")

	var non_finite_hp := combat.duplicate(true)
	non_finite_hp["player"]["hp"] = NAN
	_suite.assert_true(not RunViewStateScript.validate(non_finite_hp).ok, "non-finite hp is rejected")

	var non_finite_cooldown := combat.duplicate(true)
	non_finite_cooldown["player"]["time_slots"][1]["cooldown"] = INF
	_suite.assert_true(not RunViewStateScript.validate(non_finite_cooldown).ok, "non-finite cooldown is rejected")

	var nan_cooldown := combat.duplicate(true)
	nan_cooldown["player"]["time_slots"][0]["cooldown"] = NAN
	_suite.assert_true(not RunViewStateScript.validate(nan_cooldown).ok, "NaN cooldown is rejected")

	var negative_cooldown := combat.duplicate(true)
	negative_cooldown["player"]["time_slots"][0]["cooldown"] = -0.01
	_suite.assert_true(not RunViewStateScript.validate(negative_cooldown).ok, "negative cooldown is rejected")

	var missing_slots := combat.duplicate(true)
	missing_slots["player"].erase("time_slots")
	_suite.assert_true(not RunViewStateScript.validate(missing_slots).ok, "missing time slots are rejected")

	var legacy_cooldowns := combat.duplicate(true)
	legacy_cooldowns["player"].erase("time_slots")
	legacy_cooldowns["player"]["cooldowns"] = {"time_stop": 0.0, "time_rift": 4.5}
	_suite.assert_true(not RunViewStateScript.validate(legacy_cooldowns).ok, "legacy cooldown dictionaries cannot replace time slots")

	var one_slot := combat.duplicate(true)
	one_slot["player"]["time_slots"].resize(1)
	_suite.assert_true(not RunViewStateScript.validate(one_slot).ok, "one time slot is rejected")

	var three_slots := combat.duplicate(true)
	three_slots["player"]["time_slots"].append({
		"ability_id": "rewind",
		"action_id": "time_rewind",
		"cooldown": 0.0,
	})
	_suite.assert_true(not RunViewStateScript.validate(three_slots).ok, "more than two time slots are rejected")

	var duplicate_ability := combat.duplicate(true)
	duplicate_ability["player"]["time_slots"][1] = {
		"ability_id": "stop",
		"action_id": "time_stop",
		"cooldown": 4.5,
	}
	_suite.assert_true(not RunViewStateScript.validate(duplicate_ability).ok, "duplicate canonical abilities are rejected")

	var duplicate_action := combat.duplicate(true)
	duplicate_action["player"]["time_slots"][1] = {
		"ability_id": "rift",
		"action_id": "time_stop",
		"cooldown": 4.5,
	}
	_suite.assert_true(not RunViewStateScript.validate(duplicate_action).ok, "duplicate action ids are rejected")

	var unknown_ability := combat.duplicate(true)
	unknown_ability["player"]["time_slots"][1]["ability_id"] = "unknown"
	unknown_ability["player"]["time_slots"][1]["action_id"] = "time_unknown"
	_suite.assert_true(not RunViewStateScript.validate(unknown_ability).ok, "unknown canonical abilities are rejected")

	var unknown_action := combat.duplicate(true)
	unknown_action["player"]["time_slots"][1]["action_id"] = "time_unknown"
	_suite.assert_true(not RunViewStateScript.validate(unknown_action).ok, "unknown action ids are rejected")

	var mismatched_pair := combat.duplicate(true)
	mismatched_pair["player"]["time_slots"][1]["action_id"] = "time_rewind"
	_suite.assert_true(not RunViewStateScript.validate(mismatched_pair).ok, "canonical and input action ids must match exactly")

	var missing_weapon_state := combat.duplicate(true)
	missing_weapon_state.erase("weapon_state")
	_suite.assert_true(not RunViewStateScript.validate(missing_weapon_state).ok, "missing weapon state is rejected")

	var unknown_weapon := combat.duplicate(true)
	unknown_weapon["weapon_state"]["weapon_id"] = "laser"
	_suite.assert_true(not RunViewStateScript.validate(unknown_weapon).ok, "unknown weapon is rejected")

	var mismatched_meter := combat.duplicate(true)
	mismatched_meter["weapon_state"]["meter_kind"] = "charge"
	_suite.assert_true(not RunViewStateScript.validate(mismatched_meter).ok, "weapon and meter combinations are validated")

	var unknown_status := combat.duplicate(true)
	unknown_status["weapon_state"]["status_id"] = "overpowered"
	_suite.assert_true(not RunViewStateScript.validate(unknown_status).ok, "unknown weapon status is rejected")

	var mismatched_status := combat.duplicate(true)
	mismatched_status["weapon_state"]["status_id"] = "perfect_reload"
	_suite.assert_true(not RunViewStateScript.validate(mismatched_status).ok, "status and meter combinations are validated")

	var negative_meter := combat.duplicate(true)
	negative_meter["weapon_state"]["meter_current"] = -1
	_suite.assert_true(not RunViewStateScript.validate(negative_meter).ok, "negative weapon meter is rejected")

	var nan_meter := combat.duplicate(true)
	nan_meter["weapon_state"]["meter_current"] = NAN
	_suite.assert_true(not RunViewStateScript.validate(nan_meter).ok, "NaN weapon meter is rejected")

	var infinite_maximum := combat.duplicate(true)
	infinite_maximum["weapon_state"]["meter_max"] = INF
	_suite.assert_true(not RunViewStateScript.validate(infinite_maximum).ok, "infinite weapon maximum is rejected")

	var zero_maximum := combat.duplicate(true)
	zero_maximum["weapon_state"]["meter_max"] = 0
	_suite.assert_true(not RunViewStateScript.validate(zero_maximum).ok, "zero weapon maximum is rejected")

	var meter_over_maximum := combat.duplicate(true)
	meter_over_maximum["weapon_state"]["meter_current"] = 7
	_suite.assert_true(not RunViewStateScript.validate(meter_over_maximum).ok, "weapon meter above maximum is rejected")

	var fractional_ammo := combat.duplicate(true)
	fractional_ammo["weapon_state"]["meter_current"] = 3.5
	_suite.assert_true(not RunViewStateScript.validate(fractional_ammo).ok, "fractional ammunition is rejected")

	var negative_status := combat.duplicate(true)
	negative_status["weapon_state"]["status_remaining"] = -1
	_suite.assert_true(not RunViewStateScript.validate(negative_status).ok, "negative status duration is rejected")

	var negative_stacks := combat.duplicate(true)
	negative_stacks["weapon_state"]["status_stacks"] = -1
	_suite.assert_true(not RunViewStateScript.validate(negative_stacks).ok, "negative status stacks are rejected")

	var missing_active_stack := combat.duplicate(true)
	missing_active_stack["weapon_state"]["status_stacks"] = 0
	_suite.assert_true(not RunViewStateScript.validate(missing_active_stack).ok, "active status requires an explicit stack")

	var infinite_secondary := combat.duplicate(true)
	infinite_secondary["weapon_state"]["secondary_id"] = "time_load"
	infinite_secondary["weapon_state"]["secondary_value"] = INF
	_suite.assert_true(not RunViewStateScript.validate(infinite_secondary).ok, "infinite secondary value is rejected")

	var empty_secondary_with_value := combat.duplicate(true)
	empty_secondary_with_value["weapon_state"]["secondary_value"] = 1
	_suite.assert_true(not RunViewStateScript.validate(empty_secondary_with_value).ok, "empty secondary id cannot carry a value")

	var unknown_secondary := combat.duplicate(true)
	unknown_secondary["weapon_state"]["secondary_id"] = "heat"
	unknown_secondary["weapon_state"]["secondary_value"] = 1
	_suite.assert_true(not RunViewStateScript.validate(unknown_secondary).ok, "unknown weapon secondary state is rejected")

	var unexpected_union_field := combat.duplicate(true)
	unexpected_union_field["weapon_state"]["ammo"] = 4
	_suite.assert_true(not RunViewStateScript.validate(unexpected_union_field).ok, "weapon-specific union fields are rejected")

	for legacy_field: String in ["weapon", "sword_state", "bow_state", "gun_state"]:
		var legacy_top_level := combat.duplicate(true)
		legacy_top_level[legacy_field] = {}
		_suite.assert_true(
			not RunViewStateScript.validate(legacy_top_level).ok,
			"legacy top-level %s is rejected" % legacy_field
		)
	var legacy_top_level_ammo := combat.duplicate(true)
	legacy_top_level_ammo["ammo"] = 4
	_suite.assert_true(not RunViewStateScript.validate(legacy_top_level_ammo).ok, "legacy top-level ammunition is rejected")

	var legacy_player_weapon := combat.duplicate(true)
	legacy_player_weapon["player"]["weapon"] = {}
	_suite.assert_true(not RunViewStateScript.validate(legacy_player_weapon).ok, "raw player weapon snapshots are rejected at the view boundary")

	var nested_weapon_union := combat.duplicate(true)
	nested_weapon_union["player"]["weapon_state"] = combat["weapon_state"].duplicate(true)
	_suite.assert_true(not RunViewStateScript.validate(nested_weapon_union).ok, "weapon union cannot be nested under player")

	var missing_character_state := combat.duplicate(true)
	missing_character_state.erase("character_state")
	_suite.assert_true(not RunViewStateScript.validate(missing_character_state).ok, "character state key is required even when M1 uses null")

	var m1_character_state := combat.duplicate(true)
	m1_character_state["character_state"] = null
	_suite.assert_true(RunViewStateScript.validate(m1_character_state).ok, "M1 compatibility may omit the Launch character HUD through null")

	var valid_character_states: Array[Dictionary] = [
		_character_state("wanderer", "waypoint_recall", "path_marks", 3, 5, "anchor", 1, 120, "path_progress", 2),
		_character_state("time_guardian", "chrono_fortress", "ward", 3, 3, "fortress", 1, 90, "", 0),
		_character_state("void_walker", "void_devour", "void_debt", 75, 100, "corruption", 1, 30, "corruption_threshold", 75),
		_character_state("primordial_knight", "realm_cleave", "resonance", 2, 3, "echo_pending", 2, 0, "pending_echoes", 2),
		_character_state("time_lord", "codex_dominion", "codex_pages", 2, 3, "primer", 1, 299, "primer", "stop"),
	]
	for character_state: Dictionary in valid_character_states:
		var candidate := combat.duplicate(true)
		candidate["character_state"] = character_state
		_suite.assert_true(RunViewStateScript.validate(candidate).ok, "%s character state validates" % character_state["character_id"])

	var invalid_character_cases: Array[Dictionary] = [
		{"field": "character_id", "value": "unknown", "label": "unknown character"},
		{"field": "meter_kind", "value": "ward", "label": "mismatched character meter"},
		{"field": "status_id", "value": "fortress", "label": "mismatched character status"},
		{"field": "meter_current", "value": NAN, "label": "NaN character meter"},
		{"field": "meter_max", "value": INF, "label": "infinite character maximum"},
		{"field": "meter_current", "value": -1, "label": "negative character meter"},
		{"field": "cooldown_current", "value": 721, "label": "character cooldown overflow"},
		{"field": "status_remaining", "value": -1, "label": "negative character status duration"},
	]
	for invalid_case: Dictionary in invalid_character_cases:
		var invalid_character := combat.duplicate(true)
		invalid_character["character_state"][str(invalid_case["field"])] = invalid_case["value"]
		_suite.assert_true(not RunViewStateScript.validate(invalid_character).ok, "%s is rejected" % invalid_case["label"])

	var invalid_primer := combat.duplicate(true)
	invalid_primer["character_state"]["secondary_value"] = "time_stop"
	_suite.assert_true(not RunViewStateScript.validate(invalid_primer).ok, "Primer requires a canonical ability id rather than an input action id")

	var legacy_character := combat.duplicate(true)
	legacy_character["codex_pages"] = 2
	_suite.assert_true(not RunViewStateScript.validate(legacy_character).ok, "legacy character-specific top-level fields are rejected")
	var nested_character := combat.duplicate(true)
	nested_character["player"]["character_state"] = combat["character_state"].duplicate(true)
	_suite.assert_true(not RunViewStateScript.validate(nested_character).ok, "character union cannot be nested under player")

	var room_outside_total := combat.duplicate(true)
	room_outside_total["room"]["index"] = 6
	_suite.assert_true(not RunViewStateScript.validate(room_outside_total).ok, "room outside total is rejected")

	var invalid_build_entry := combat.duplicate(true)
	invalid_build_entry["build"]["items"] = [""]
	_suite.assert_true(not RunViewStateScript.validate(invalid_build_entry).ok, "empty build ids are rejected")

	var launch_build := combat.duplicate(true)
	_set_build_domain(launch_build, LAUNCH_ARCHETYPE_SCORES, "freeze_burst")
	_suite.assert_true(RunViewStateScript.validate(launch_build).ok, "exact eight-key Launch archetype domain validates")

	var missing_archetype_score := combat.duplicate(true)
	missing_archetype_score["build"]["archetype_scores"].erase("accelerated_combo")
	_suite.assert_true(not RunViewStateScript.validate(missing_archetype_score).ok, "incomplete M1 archetype score domain is rejected")

	var unknown_archetype_score := combat.duplicate(true)
	unknown_archetype_score["build"]["archetype_scores"]["time_stop_burst"] = 1
	_suite.assert_true(not RunViewStateScript.validate(unknown_archetype_score).ok, "unknown archetype score keys are rejected")

	var negative_archetype_score := combat.duplicate(true)
	negative_archetype_score["build"]["archetype_scores"]["freeze_burst"] = -1
	_suite.assert_true(not RunViewStateScript.validate(negative_archetype_score).ok, "negative archetype scores are rejected")

	var invalid_archetype_score := combat.duplicate(true)
	invalid_archetype_score["build"]["archetype_scores"]["freeze_burst"] = INF
	_suite.assert_true(not RunViewStateScript.validate(invalid_archetype_score).ok, "non-finite archetype scores are rejected")

	var nan_archetype_score := combat.duplicate(true)
	nan_archetype_score["build"]["archetype_scores"]["freeze_burst"] = NAN
	_suite.assert_true(not RunViewStateScript.validate(nan_archetype_score).ok, "NaN archetype scores are rejected")

	var outside_dominant := combat.duplicate(true)
	outside_dominant["build"]["dominant_archetype"] = "rift_trap"
	_suite.assert_true(not RunViewStateScript.validate(outside_dominant).ok, "dominant archetype outside the score map is rejected")

	var internal_dominant := combat.duplicate(true)
	internal_dominant["build"]["dominant_archetype"] = "time_stop_burst"
	_suite.assert_true(not RunViewStateScript.validate(internal_dominant).ok, "internal mechanic tag cannot become dominant archetype")

	var copied := RunViewStateScript.copy_of(boss)
	_suite.assert_true(not copied.is_empty(), "valid time-slot state can be copied")
	if not copied.is_empty():
		copied["build"]["items"][0] = "changed"
		copied["boss"]["hp"] = 1.0
		copied["player"]["time_slots"][0]["ability_id"] = "changed"
		copied["player"]["time_slots"].reverse()
		copied["weapon_state"]["meter_current"] = 0
		_suite.assert_equal(boss["build"]["items"][0], "frozen_burst", "nested arrays are isolated")
		_suite.assert_close(float(boss["boss"]["hp"]), 315.0, "nested dictionaries are isolated")
		_assert_slot_order(boss, ["rewind", "stop"], ["time_rewind", "time_stop"], "source after copy mutation")
		_suite.assert_close(float(boss["weapon_state"]["meter_current"]), 1.0, "weapon state copy is isolated")

	_suite.finish(get_tree())


func _assert_invalid(base: Dictionary, key: String, value: Variant, label: String, erase_key: bool = false) -> void:
	var candidate := base.duplicate(true)
	if erase_key:
		candidate.erase(key)
	else:
		candidate[key] = value
	_suite.assert_true(not RunViewStateScript.validate(candidate).ok, label)


func _assert_slot_order(
	state: Dictionary,
	expected_abilities: Array,
	expected_actions: Array,
	label: String
) -> void:
	var player: Dictionary = state.get("player", {})
	var slots: Variant = player.get("time_slots")
	_suite.assert_true(slots is Array, "%s exposes a time-slot array" % label)
	if not slots is Array:
		return
	var actual_slots := slots as Array
	_suite.assert_equal(actual_slots.size(), 2, "%s exposes exactly two time slots" % label)
	if actual_slots.size() != 2:
		return
	var ability_ids: Array[String] = []
	var action_ids: Array[String] = []
	for slot: Variant in actual_slots:
		if not slot is Dictionary:
			continue
		ability_ids.append(str((slot as Dictionary).get("ability_id", "")))
		action_ids.append(str((slot as Dictionary).get("action_id", "")))
	_suite.assert_equal(ability_ids, expected_abilities, "%s preserves canonical ability order" % label)
	_suite.assert_equal(action_ids, expected_actions, "%s preserves input action order" % label)


func _assert_weapon_state(
	state: Dictionary,
	expected_weapon: String,
	expected_meter: String,
	expected_status: String,
	label: String
) -> void:
	var weapon_value: Variant = state.get("weapon_state")
	_suite.assert_true(weapon_value is Dictionary, "%s exposes a weapon-state union" % label)
	if not weapon_value is Dictionary:
		return
	var weapon := weapon_value as Dictionary
	_suite.assert_equal(weapon.get("weapon_id"), expected_weapon, "%s weapon id is canonical" % label)
	_suite.assert_equal(weapon.get("meter_kind"), expected_meter, "%s meter kind matches weapon" % label)
	_suite.assert_equal(weapon.get("status_id"), expected_status, "%s status id is validated" % label)


func _assert_character_state(
	state: Dictionary,
	expected_character: String,
	expected_meter: String,
	expected_status: String,
	label: String
) -> void:
	var character_value: Variant = state.get("character_state")
	_suite.assert_true(character_value is Dictionary, "%s exposes a character-state union" % label)
	if not character_value is Dictionary:
		return
	var character := character_value as Dictionary
	_suite.assert_equal(character.get("character_id"), expected_character, "%s character id is canonical" % label)
	_suite.assert_equal(character.get("meter_kind"), expected_meter, "%s character meter is canonical" % label)
	_suite.assert_equal(character.get("status_id"), expected_status, "%s character status is canonical" % label)


func _character_state(
	character_id: String,
	skill_id: String,
	meter_kind: String,
	meter_current: Variant,
	meter_max: Variant,
	status_id: String,
	status_stacks: int,
	status_remaining: Variant,
	secondary_id: String,
	secondary_value: Variant
) -> Dictionary:
	return {
		"character_id": character_id,
		"skill_id": skill_id,
		"phase": "READY",
		"cooldown_current": 120,
		"cooldown_max": 720,
		"meter_kind": meter_kind,
		"meter_current": meter_current,
		"meter_max": meter_max,
		"status_id": status_id,
		"status_stacks": status_stacks,
		"status_remaining": status_remaining,
		"secondary_id": secondary_id,
		"secondary_value": secondary_value,
	}


func _set_build_domain(state: Dictionary, scores: Dictionary, dominant_archetype: String) -> void:
	if state.is_empty() or not state.get("build") is Dictionary:
		return
	state["build"]["archetype_scores"] = scores.duplicate(true)
	state["build"]["dominant_archetype"] = dominant_archetype


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
