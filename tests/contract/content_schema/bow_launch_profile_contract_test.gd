extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var catalog_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	suite.assert_true(catalog_value is Array, "weapon profile catalog parses as an array")
	if catalog_value is Array:
		var catalog: Array = catalog_value
		_test_candidate_isolation(suite, _profile(catalog, "bow_candidate_v1"))
		_test_launch_actions(suite, _profile(catalog, "bow_launch_v1"))
		_test_launch_payloads(suite, _profile(catalog, "bow_launch_v1"))
		_test_time_and_boss_interactions(suite, _profile(catalog, "bow_launch_v1"))
	suite.finish(get_tree())


func _test_candidate_isolation(suite, candidate: Dictionary) -> void:
	suite.assert_equal(candidate.get("availability"), ["NEXT"], "Candidate remains NEXT-only")
	var action := _entry(candidate.get("actions", []), "action_id", "candidate_draw")
	suite.assert_equal(int(action.get("hold_threshold_frames", -1)), 9, "Candidate minimum charge remains nine frames")
	suite.assert_equal(int(action.get("maximum_hold_frames", -1)), 54, "Candidate maximum charge remains fifty-four frames")
	suite.assert_equal(int(action.get("cooldown_frames", -1)), 21, "Candidate cooldown remains twenty-one frames")
	suite.assert_equal(str(action.get("payload_id", "")), "bow_candidate_arrow", "Candidate payload identity remains isolated")
	var resource := _entry(candidate.get("resources", []), "resource_id", "charge")
	suite.assert_close(float(resource.get("maximum", -1.0)), 54.0, "Candidate charge resource remains fifty-four frames")
	var payload := _entry(candidate.get("payloads", []), "payload_id", "bow_candidate_arrow")
	var parameters: Dictionary = payload.get("parameters", {})
	suite.assert_close(float(parameters.get("damage_multiplier", -1.0)), 0.75, "Candidate minimum damage remains frozen")
	suite.assert_close(float(parameters.get("maximum_damage_multiplier", -1.0)), 1.75, "Candidate maximum damage remains frozen")
	suite.assert_close(float(parameters.get("speed", -1.0)), 440.0, "Candidate minimum speed remains frozen")
	suite.assert_close(float(parameters.get("maximum_speed", -1.0)), 680.0, "Candidate maximum speed remains frozen")
	suite.assert_close(float(parameters.get("full_charge_ratio", -1.0)), 0.98, "Candidate full-charge ratio remains frozen")
	suite.assert_close(float(parameters.get("full_charge_energy", -1.0)), 6.0, "Candidate energy reward remains frozen")
	suite.assert_true(_entry(candidate.get("actions", []), "action_id", "precision_draw").is_empty(), "Launch actions do not leak into Candidate")


func _test_launch_actions(suite, launch: Dictionary) -> void:
	suite.assert_equal(launch.get("availability"), ["LAUNCH", "EXPANSION"], "Launch Bow remains milestone-isolated")
	var actions: Array = launch.get("actions", [])
	suite.assert_equal(
		_action_ids(actions),
		["precision_draw", "scatter_shot", "focus_step", "temporal_arrow", "starfall_arrow_rain"],
		"Launch Bow exposes the five approved action ids"
	)

	var primary := _entry(actions, "action_id", "precision_draw")
	suite.assert_equal(str(primary.get("semantic_action", "")), "weapon_primary", "Precision Draw owns primary")
	suite.assert_equal(str(primary.get("activation_mode", "")), "release", "Precision Draw releases the coordinator HOLD")
	suite.assert_equal(int(primary.get("hold_threshold_frames", -1)), 0, "Precision Draw starts at zero held frames")
	suite.assert_equal(int(primary.get("maximum_hold_frames", -1)), 228, "Precision Draw auto-releases at frame 228")
	suite.assert_close(float(primary.get("movement_multiplier", -1.0)), 0.40, "Precision Draw applies the charging movement penalty")

	var scatter := _entry(actions, "action_id", "scatter_shot")
	_assert_action_timing(suite, scatter, 10, 3, 18, 120, "Scatter Shot")

	var focus_step := _entry(actions, "action_id", "focus_step")
	suite.assert_equal(str(focus_step.get("semantic_action", "")), "weapon_utility", "Focus Step owns utility")
	suite.assert_equal(int(focus_step.get("cooldown_frames", 0)), 0, "Focus Step has no undeclared cooldown")

	var temporal_arrow := _entry(actions, "action_id", "temporal_arrow")
	_assert_action_timing(suite, temporal_arrow, 12, 2, 16, 300, "Temporal Arrow")
	suite.assert_close(float(temporal_arrow.get("resource_costs", {}).get("time_energy", -1.0)), 30.0, "Temporal Arrow costs thirty Time Energy")

	var starfall := _entry(actions, "action_id", "starfall_arrow_rain")
	_assert_action_timing(suite, starfall, 20, 90, 25, 900, "Starfall")
	suite.assert_close(float(starfall.get("resource_costs", {}).get("time_energy", -1.0)), 70.0, "Starfall costs seventy Time Energy")


func _test_launch_payloads(suite, launch: Dictionary) -> void:
	var payloads: Array = launch.get("payloads", [])
	var primary := _entry(payloads, "payload_id", "bow_launch_arrow")
	var primary_parameters: Dictionary = primary.get("parameters", {})
	suite.assert_equal(int(primary_parameters.get("full_charge_frames", -1)), 48, "Launch Bow reaches full charge at frame forty-eight")
	suite.assert_equal(int(primary_parameters.get("auto_release_frames", -1)), 228, "Launch Bow holds full charge through frame 228")
	suite.assert_close(float(primary_parameters.get("charge_movement_multiplier", -1.0)), 0.40, "Launch Bow charge movement is forty percent")
	suite.assert_close(float(primary_parameters.get("full_charge_movement_multiplier", -1.0)), 0.20, "Launch Bow full-hold movement is twenty percent")
	var tiers: Array = primary_parameters.get("charge_tiers", [])
	suite.assert_equal(tiers.size(), 4, "Launch Bow declares four charge outcomes")
	_assert_charge_tier(suite, tiers, "quick", 0, 14, 6, 2, 10, 0.8)
	_assert_charge_tier(suite, tiers, "power", 15, 29, 4, 2, 14, 1.8)
	_assert_charge_tier(suite, tiers, "piercing", 30, 47, 4, 2, 16, 2.8)
	_assert_charge_tier(suite, tiers, "full", 48, 228, 4, 2, 20, 4.5)

	var scatter := _entry(payloads, "payload_id", "bow_scatter")
	var scatter_parameters: Dictionary = scatter.get("parameters", {})
	suite.assert_close(float(scatter_parameters.get("damage_multiplier", -1.0)), 0.6, "Scatter arrow multiplier is authoritative")
	suite.assert_equal(int(scatter_parameters.get("count", -1)), 5, "Scatter emits five arrows")
	suite.assert_close(float(scatter_parameters.get("spread_degrees", -1.0)), 30.0, "Scatter spans plus or minus thirty degrees")

	var focus_step := _entry(payloads, "payload_id", "bow_focus_step")
	var focus_parameters: Dictionary = focus_step.get("parameters", {})
	suite.assert_close(float(focus_parameters.get("distance", -1.0)), 96.0, "Focus Step moves ninety-six pixels")
	suite.assert_equal(str(focus_parameters.get("direction", "")), "opposite_aim", "Focus Step moves opposite the aim direction")
	suite.assert_equal(str(focus_parameters.get("collision_mode", "")), "swept", "Focus Step uses swept collision")
	suite.assert_equal(int(focus_parameters.get("invulnerability_frames", -1)), 0, "Focus Step grants no invulnerability")

	var temporal_arrow := _entry(payloads, "payload_id", "bow_temporal_arrow")
	var temporal_parameters: Dictionary = temporal_arrow.get("parameters", {})
	suite.assert_equal(str(temporal_parameters.get("damage_type", "")), "time", "Temporal Arrow deals Time damage")
	suite.assert_equal(bool(temporal_parameters.get("unlimited_pierce", false)), true, "Temporal Arrow has unlimited penetration")
	suite.assert_equal(int(temporal_parameters.get("trail_duration_frames", -1)), 300, "Temporal Arrow trail lasts three hundred frames")
	suite.assert_equal(int(temporal_parameters.get("trail_tick_interval_frames", -1)), 30, "Temporal Arrow trail ticks every thirty frames")

	var starfall := _entry(payloads, "payload_id", "bow_starfall")
	var starfall_parameters: Dictionary = starfall.get("parameters", {})
	suite.assert_equal(int(starfall_parameters.get("wave_count", -1)), 10, "Starfall schedules ten waves")
	suite.assert_equal(int(starfall_parameters.get("wave_interval_frames", -1)), 9, "Starfall schedules waves nine frames apart")
	suite.assert_equal(int(starfall_parameters.get("arrows_per_wave", -1)), 3, "Starfall emits three arrows per wave")


func _test_time_and_boss_interactions(suite, launch: Dictionary) -> void:
	var interactions: Dictionary = launch.get("time_interactions", {})
	var stop_parameters: Dictionary = interactions.get("stop", {}).get("parameters", {})
	suite.assert_equal(bool(stop_parameters.get("requires_full_charge", false)), true, "Stop burst requires full charge")
	suite.assert_close(float(stop_parameters.get("explosion_damage_multiplier", -1.0)), 2.0, "Stop full-charge explosion is two-times attack")
	suite.assert_equal(int(stop_parameters.get("stop_extension_frames", -1)), 60, "Stop full-charge hit extends Stop by sixty frames")

	var rewind_parameters: Dictionary = interactions.get("rewind", {}).get("parameters", {})
	suite.assert_equal(int(rewind_parameters.get("echo_count", -1)), 3, "Rewind creates three phantom arrows")
	suite.assert_close(float(rewind_parameters.get("damage_multiplier", -1.0)), 0.5, "Rewind phantom arrows deal half damage")
	suite.assert_close(float(rewind_parameters.get("spacing_degrees", -1.0)), 15.0, "Rewind phantom arrows use fifteen-degree spacing")

	var accelerate_parameters: Dictionary = interactions.get("accelerate", {}).get("parameters", {})
	suite.assert_close(float(accelerate_parameters.get("charge_rate_multiplier", -1.0)), 2.0, "Accelerate doubles Bow charge rate")
	suite.assert_equal(int(accelerate_parameters.get("quick_shot_recovery_delta_frames", 0)), -6, "Accelerate removes six quick-shot recovery frames")

	var rift_parameters: Dictionary = interactions.get("rift", {}).get("parameters", {})
	suite.assert_equal(bool(rift_parameters.get("unlimited_pierce", false)), true, "Rift grants full-charge unlimited penetration")
	suite.assert_close(float(rift_parameters.get("detonation_radius_multiplier", -1.0)), 1.5, "Rift detonation expands the area by one-and-a-half")
	suite.assert_close(float(rift_parameters.get("detonation_damage_multiplier", -1.0)), 1.5, "Rift detonation deals one-and-a-half attack Time damage")

	var boss: Dictionary = launch.get("boss_interactions", {}).get("chrono_warden", {})
	suite.assert_equal(str(boss.get("type", "")), "recovery_exposure_poise_conversion", "Chrono Warden maps Bow control to its public pressure states")
	var boss_parameters: Dictionary = boss.get("parameters", {})
	suite.assert_equal(bool(boss_parameters.get("interrupt_active_attack", true)), false, "Bow cannot interrupt a committed Boss active attack")
	suite.assert_equal(
		boss_parameters.get("conversion_outcomes"),
		["recovery_extension", "exposure_extension", "poise_damage"],
		"Chrono Warden conversion declares recovery, exposure, and poise outcomes"
	)


func _assert_action_timing(
	suite,
	action: Dictionary,
	windup: int,
	active: int,
	recovery: int,
	cooldown: int,
	label: String
) -> void:
	suite.assert_equal(int(action.get("windup_frames", -1)), windup, "%s windup is authoritative" % label)
	suite.assert_equal(int(action.get("active_frames", -1)), active, "%s active window is authoritative" % label)
	suite.assert_equal(int(action.get("recovery_frames", -1)), recovery, "%s recovery is authoritative" % label)
	suite.assert_equal(int(action.get("cooldown_frames", -1)), cooldown, "%s cooldown is authoritative" % label)


func _assert_charge_tier(
	suite,
	tiers: Array,
	tier_id: String,
	minimum_frames: int,
	maximum_frames: int,
	windup: int,
	active: int,
	recovery: int,
	damage_multiplier: float
) -> void:
	var tier := _entry(tiers, "tier_id", tier_id)
	suite.assert_equal(int(tier.get("minimum_frames", -1)), minimum_frames, "%s tier minimum is authoritative" % tier_id)
	suite.assert_equal(int(tier.get("maximum_frames", -1)), maximum_frames, "%s tier maximum is authoritative" % tier_id)
	suite.assert_equal(int(tier.get("windup_frames", -1)), windup, "%s tier windup is authoritative" % tier_id)
	suite.assert_equal(int(tier.get("active_frames", -1)), active, "%s tier active window is authoritative" % tier_id)
	suite.assert_equal(int(tier.get("recovery_frames", -1)), recovery, "%s tier recovery is authoritative" % tier_id)
	suite.assert_close(float(tier.get("damage_multiplier", -1.0)), damage_multiplier, "%s tier damage is authoritative" % tier_id)


func _profile(catalog: Array, profile_id: String) -> Dictionary:
	return _entry(catalog, "id", profile_id)


func _entry(entries: Array, key: String, expected: String) -> Dictionary:
	for value: Variant in entries:
		if value is Dictionary and str((value as Dictionary).get(key, "")) == expected:
			return (value as Dictionary).duplicate(true)
	return {}


func _action_ids(actions: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in actions:
		if value is Dictionary:
			result.append(str((value as Dictionary).get("action_id", "")))
	return result
