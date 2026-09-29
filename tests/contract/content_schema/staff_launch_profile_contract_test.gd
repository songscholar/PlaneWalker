extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	suite.assert_true(parsed is Array, "weapon profile catalog parses for Staff contract")
	if parsed is Array:
		var staff := _entry(parsed, "id", "staff_launch_v1")
		_test_identity_and_actions(suite, staff)
		_test_element_payload(suite, staff)
		_test_skill_and_ultimate_payloads(suite, staff)
		_test_time_and_boss_interactions(suite, staff)
	suite.finish(get_tree())


func _test_identity_and_actions(suite, staff: Dictionary) -> void:
	suite.assert_equal(staff.get("availability"), ["LAUNCH", "EXPANSION"], "Staff remains Launch/Expansion isolated")
	var resources: Array = staff.get("resources", [])
	var mana := _entry(resources, "resource_id", "mana")
	suite.assert_close(float(mana.get("minimum", -1.0)), 0.0, "Mana minimum is zero")
	suite.assert_close(float(mana.get("maximum", -1.0)), 100.0, "Mana maximum is one hundred")
	suite.assert_close(float(mana.get("initial", -1.0)), 100.0, "Staff starts with full Mana")
	suite.assert_close(float(mana.get("regen_per_second", -1.0)), 3.0, "Mana regenerates at three per second")

	var actions: Array = staff.get("actions", [])
	_assert_action(suite, actions, "arcane_bolt", 4, 1, 10, 0.0)
	_assert_action(suite, actions, "charged_element", 8, 2, 16, 18.0)
	_assert_action(suite, actions, "element_cycle", 1, 1, 2, 0.0)
	_assert_action(suite, actions, "planar_collapse", 12, 6, 20, 30.0)
	_assert_action(suite, actions, "primordial_wrath", 20, 20, 30, 60.0)
	var basic := _entry(actions, "action_id", "arcane_bolt")
	var charged := _entry(actions, "action_id", "charged_element")
	var ultimate := _entry(actions, "action_id", "primordial_wrath")
	suite.assert_equal(int(basic.get("maximum_hold_frames", -1)), 29, "basic spell owns hold frames zero through twenty-nine")
	suite.assert_equal(int(charged.get("hold_threshold_frames", -1)), 30, "charged element begins at frame thirty")
	suite.assert_equal(int(ultimate.get("hold_threshold_frames", -1)), 60, "Primordial Wrath requires sixty held frames")


func _test_element_payload(suite, staff: Dictionary) -> void:
	var payloads: Array = staff.get("payloads", [])
	var payload := _entry(payloads, "payload_id", "staff_element_cast")
	var parameters: Dictionary = payload.get("parameters", {})
	suite.assert_equal(parameters.get("elements"), ["fire", "ice", "lightning"], "Staff element order is authoritative")
	suite.assert_equal(parameters.get("costs"), {"fire": 20.0, "ice": 25.0, "lightning": 18.0}, "charged element Mana costs are authoritative")
	suite.assert_equal(int(parameters.get("combo_window_frames", -1)), 300, "ordered combination window lasts three hundred frames")
	suite.assert_close(float(parameters.get("mana_return_ratio", -1.0)), 0.02, "damage restores two percent Mana")
	suite.assert_close(float(parameters.get("mana_return_cap_per_outcome", -1.0)), 5.0, "each hit or tick has a five-Mana return cap")

	var definitions: Array = parameters.get("element_definitions", [])
	var fire := _entry(definitions, "element_id", "fire")
	suite.assert_close(float(fire.get("damage_multiplier", -1.0)), 4.0, "Fire charged spell damage is authoritative")
	suite.assert_close(float(fire.get("explosion_radius_tiles", -1.0)), 2.5, "Fire explosion radius is authoritative")
	suite.assert_equal(int(fire.get("burn_duration_frames", -1)), 240, "Fire burn lasts four seconds")
	suite.assert_equal(int(fire.get("burn_tick_interval_frames", -1)), 30, "Fire burn ticks every half second")
	suite.assert_close(float(fire.get("burn_damage_multiplier", -1.0)), 0.10, "Fire burn tick damage is authoritative")

	var ice := _entry(definitions, "element_id", "ice")
	suite.assert_close(float(ice.get("damage_multiplier", -1.0)), 2.5, "Ice charged spell damage is authoritative")
	suite.assert_close(float(ice.get("zone_radius_tiles", -1.0)), 3.0, "Ice field radius is authoritative")
	suite.assert_equal(int(ice.get("zone_duration_frames", -1)), 300, "Ice field lasts five seconds")
	suite.assert_close(float(ice.get("move_speed_multiplier", -1.0)), 0.50, "Ice field halves movement speed")
	suite.assert_close(float(ice.get("attack_speed_multiplier", -1.0)), 0.70, "Ice field reduces attack speed by thirty percent")
	suite.assert_equal(int(ice.get("freeze_duration_frames", -1)), 60, "Ice field completion freezes ordinary targets for one second")

	var lightning := _entry(definitions, "element_id", "lightning")
	suite.assert_close(float(lightning.get("damage_multiplier", -1.0)), 3.0, "Lightning charged spell damage is authoritative")
	suite.assert_close(float(lightning.get("speed_tiles_per_second", -1.0)), 40.0, "Lightning projectile speed is authoritative and constructible")
	suite.assert_equal(int(lightning.get("additional_target_count", -1)), 3, "Lightning chains to three additional targets")
	suite.assert_close(float(lightning.get("chain_range_tiles", -1.0)), 4.0, "Lightning chain range is four tiles")
	suite.assert_close(float(lightning.get("chain_damage_multiplier", -1.0)), 0.70, "Lightning chain deals seventy percent damage")
	suite.assert_equal(int(lightning.get("shock_duration_frames", -1)), 180, "Shock lasts three seconds")

	var combinations: Array = parameters.get("combinations", [])
	suite.assert_equal(combinations.size(), 6, "Staff declares all six ordered element combinations")
	_assert_combo(suite, combinations, "fire", "ice", "steam_burst", 15.0)
	_assert_combo(suite, combinations, "fire", "lightning", "blazing_storm", 20.0)
	_assert_combo(suite, combinations, "ice", "lightning", "crystal_thunder", 18.0)
	_assert_combo(suite, combinations, "ice", "fire", "reverse_steam", 15.0)
	_assert_combo(suite, combinations, "lightning", "fire", "thunder_flare", 20.0)
	_assert_combo(suite, combinations, "lightning", "ice", "thunder_crystal", 18.0)


func _test_skill_and_ultimate_payloads(suite, staff: Dictionary) -> void:
	var payloads: Array = staff.get("payloads", [])
	var collapse: Dictionary = _entry(payloads, "payload_id", "staff_planar_collapse").get("parameters", {})
	suite.assert_close(float(collapse.get("damage_multiplier", -1.0)), 3.2, "Plane Collapse damage remains frozen")
	suite.assert_equal(int(collapse.get("duration_frames", -1)), 180, "Plane Collapse zone lasts three seconds")
	suite.assert_close(float(collapse.get("radius_tiles", -1.0)), 4.0, "Plane Collapse radius is four tiles")
	suite.assert_equal(int(collapse.get("ordinary_freeze_frames", -1)), 120, "Plane Collapse freezes ordinary targets for two seconds")
	suite.assert_close(float(collapse.get("boss_slow_multiplier", -1.0)), 0.30, "Plane Collapse maps Boss control to seventy percent slow")

	var ultimate: Dictionary = _entry(payloads, "payload_id", "staff_primordial_wrath").get("parameters", {})
	suite.assert_equal(int(ultimate.get("count", -1)), 20, "Primordial Wrath emits twenty seeded outcomes")
	suite.assert_equal(int(ultimate.get("tick_interval_frames", -1)), 6, "Primordial Wrath resolves every six frames")
	suite.assert_close(float(ultimate.get("radius_tiles", -1.0)), 5.0, "Primordial Wrath radius is five tiles")
	suite.assert_equal(bool(ultimate.get("cast_invulnerability", false)), true, "Primordial Wrath grants cast invulnerability")
	suite.assert_equal(str(ultimate.get("seed_channel", "")), "staff_primordial_wrath", "Primordial Wrath uses a stable seed channel")


func _test_time_and_boss_interactions(suite, staff: Dictionary) -> void:
	var interactions: Dictionary = staff.get("time_interactions", {})
	var stop: Dictionary = interactions.get("stop", {}).get("parameters", {})
	suite.assert_close(float(stop.get("area_multiplier", -1.0)), 1.5, "Stop expands controlled fields by one-and-a-half")
	suite.assert_close(float(stop.get("duration_multiplier", -1.0)), 1.5, "Stop extends controlled fields by one-and-a-half")
	var rewind: Dictionary = interactions.get("rewind", {}).get("parameters", {})
	suite.assert_equal(int(rewind.get("window_frames", -1)), 120, "Rewind Staff window lasts two seconds")
	suite.assert_equal(bool(rewind.get("mana_free", false)), true, "Rewind charged cast is Mana-free")
	suite.assert_close(float(rewind.get("damage_multiplier", -1.0)), 1.3, "Rewind charged cast gains thirty percent damage")
	suite.assert_equal(bool(rewind.get("one_cast_claim", false)), true, "Rewind benefit is claimed by one charged cast")
	var accelerate: Dictionary = interactions.get("accelerate", {}).get("parameters", {})
	suite.assert_equal(int(accelerate.get("hold_threshold_frames", -1)), 15, "Accelerate charged Staff threshold is fifteen frames")
	suite.assert_close(float(accelerate.get("mana_multiplier", -1.0)), 0.7, "Accelerate reduces Mana cost by thirty percent")
	var rift: Dictionary = interactions.get("rift", {}).get("parameters", {})
	suite.assert_close(float(rift.get("area_multiplier", -1.0)), 1.3, "Rift expands Staff combination areas")
	suite.assert_close(float(rift.get("time_damage_multiplier", -1.0)), 0.5, "Rift adds half attack as Time damage")

	var boss: Dictionary = staff.get("boss_interactions", {}).get("chrono_warden", {})
	suite.assert_equal(str(boss.get("type", "")), "control_conversion", "Chrono Warden uses Staff control conversion")
	var boss_parameters: Dictionary = boss.get("parameters", {})
	suite.assert_equal(bool(boss_parameters.get("interrupt_active_attack", true)), false, "Staff control cannot interrupt a committed Boss attack")
	suite.assert_equal(int(boss_parameters.get("freeze_delay_frames", -1)), 12, "Boss freeze converts to twelve delay frames")
	suite.assert_equal(int(boss_parameters.get("blind_delay_frames", -1)), 8, "Boss blind converts to eight delay frames")


func _assert_action(
	suite,
	actions: Array,
	action_id: String,
	windup: int,
	active: int,
	recovery: int,
	mana_cost: float
) -> void:
	var action := _entry(actions, "action_id", action_id)
	suite.assert_equal(int(action.get("windup_frames", -1)), windup, "%s windup is authoritative" % action_id)
	suite.assert_equal(int(action.get("active_frames", -1)), active, "%s active frames are authoritative" % action_id)
	suite.assert_equal(int(action.get("recovery_frames", -1)), recovery, "%s recovery is authoritative" % action_id)
	var costs: Dictionary = action.get("resource_costs", {})
	if mana_cost > 0.0:
		suite.assert_close(float(costs.get("mana", -1.0)), mana_cost, "%s Mana cost is authoritative" % action_id)
	else:
		suite.assert_true(not costs.has("mana"), "%s has no Mana cost" % action_id)


func _assert_combo(
	suite,
	combinations: Array,
	first: String,
	second: String,
	combo_id: String,
	extra_mana: float
) -> void:
	var found: Dictionary = {}
	for value: Variant in combinations:
		if not value is Dictionary:
			continue
		var candidate := value as Dictionary
		if str(candidate.get("first", "")) == first and str(candidate.get("second", "")) == second:
			found = candidate.duplicate(true)
			break
	suite.assert_equal(str(found.get("combo_id", "")), combo_id, "%s to %s combination identity is authoritative" % [first, second])
	suite.assert_close(float(found.get("extra_mana", -1.0)), extra_mana, "%s to %s extra Mana is authoritative" % [first, second])


func _entry(entries: Variant, key: String, expected: String) -> Dictionary:
	if not entries is Array:
		return {}
	for value: Variant in entries as Array:
		if value is Dictionary and str((value as Dictionary).get(key, "")) == expected:
			return (value as Dictionary).duplicate(true)
	return {}
