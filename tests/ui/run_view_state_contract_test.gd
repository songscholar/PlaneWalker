extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()

	var combat := _load_json("res://tests/fixtures/ui/hud_combat.json")
	_suite.assert_true(not combat.is_empty(), "combat fixture loads")
	_suite.assert_true(RunViewStateScript.validate(combat).ok, "combat fixture validates")
	_suite.assert_equal(RunViewStateScript.SCHEMA_VERSION, 3, "weapon union uses view-state schema 3")

	var low_hp := _load_json("res://tests/fixtures/ui/hud_low_hp.json")
	_suite.assert_true(not low_hp.is_empty(), "low hp fixture loads")
	_suite.assert_true(RunViewStateScript.validate(low_hp).ok, "low hp fixture validates")

	var boss := _load_json("res://tests/fixtures/ui/hud_boss.json")
	_suite.assert_true(not boss.is_empty(), "boss fixture loads")
	_suite.assert_true(RunViewStateScript.validate(boss).ok, "boss fixture validates")
	_assert_slot_order(combat, ["stop", "rift"], ["time_stop", "time_rift"], "combat fixture")
	_assert_slot_order(low_hp, ["rift", "accelerate"], ["time_rift", "time_accelerate"], "low-hp fixture")
	_assert_slot_order(boss, ["rewind", "stop"], ["time_rewind", "time_stop"], "boss fixture")
	_assert_weapon_state(combat, "gun", "ammo", "time_load", "combat fixture")
	_assert_weapon_state(low_hp, "bow", "charge", "charging", "low-hp fixture")
	_assert_weapon_state(boss, "sword", "counter", "counter_ready", "boss fixture")

	_assert_invalid(combat, "schema_version", null, "missing schema version is rejected", true)
	_assert_invalid(combat, "schema_version", 2, "pre-weapon-union schema is rejected")
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

	var room_outside_total := combat.duplicate(true)
	room_outside_total["room"]["index"] = 6
	_suite.assert_true(not RunViewStateScript.validate(room_outside_total).ok, "room outside total is rejected")

	var invalid_build_entry := combat.duplicate(true)
	invalid_build_entry["build"]["items"] = [""]
	_suite.assert_true(not RunViewStateScript.validate(invalid_build_entry).ok, "empty build ids are rejected")

	var invalid_archetype_score := combat.duplicate(true)
	invalid_archetype_score["build"]["archetype_scores"]["time_stop_burst"] = INF
	_suite.assert_true(not RunViewStateScript.validate(invalid_archetype_score).ok, "non-finite archetype scores are rejected")

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
