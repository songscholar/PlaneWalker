extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	suite.assert_true(parsed is Array, "weapon profile catalog parses for Gun contract")
	if parsed is Array:
		var gun := _entry(parsed, "id", "gun_launch_v1")
		_test_actions(suite, gun)
		_test_payloads(suite, gun)
		_test_interactions(suite, gun)
	suite.finish(get_tree())


func _test_actions(suite, gun: Dictionary) -> void:
	suite.assert_equal(gun.get("availability"), ["LAUNCH", "EXPANSION"], "Gun remains Launch/Expansion isolated")
	var actions: Array = gun.get("actions", [])
	_assert_action(suite, actions, "normal_fire", 3, 1, 8, 0, 1.0)
	_assert_action(suite, actions, "aimed_fire", 8, 1, 12, 0, 1.0)
	_assert_action(suite, actions, "shotgun_fire", 8, 2, 20, 0, 2.0)
	_assert_action(suite, actions, "reload", 8, 32, 8, 0, 0.0)
	_assert_action(suite, actions, "time_load", 8, 1, 4, 360, 25.0)
	_assert_action(suite, actions, "void_penetration", 18, 3, 25, 720, 65.0)
	var normal := _entry(actions, "action_id", "normal_fire")
	var aimed := _entry(actions, "action_id", "aimed_fire")
	var ultimate := _entry(actions, "action_id", "void_penetration")
	suite.assert_equal(int(normal.get("maximum_hold_frames", -1)), 17, "normal fire owns hold frames zero through seventeen")
	suite.assert_equal(int(aimed.get("hold_threshold_frames", -1)), 18, "aimed fire begins at frame eighteen")
	suite.assert_equal(int(ultimate.get("hold_threshold_frames", -1)), 60, "Void Penetration requires sixty held frames")


func _test_payloads(suite, gun: Dictionary) -> void:
	var payloads: Array = gun.get("payloads", [])
	var normal: Dictionary = _entry(payloads, "payload_id", "gun_normal_bullet").get("parameters", {})
	suite.assert_close(float(normal.get("damage_multiplier", -1.0)), 1.0, "normal fire damage is authoritative")
	suite.assert_close(float(normal.get("speed_tiles_per_second", -1.0)), 40.0, "normal bullet speed is forty tiles per second")
	suite.assert_close(float(normal.get("maximum_range_tiles", -1.0)), 15.0, "normal bullet range is fifteen tiles")

	var aimed: Dictionary = _entry(payloads, "payload_id", "gun_aimed_bullet").get("parameters", {})
	suite.assert_close(float(aimed.get("damage_multiplier", -1.0)), 2.5, "aimed fire damage is authoritative")
	suite.assert_close(float(aimed.get("critical_chance_bonus", -1.0)), 0.20, "aimed fire gains twenty percent critical chance")
	suite.assert_equal(int(aimed.get("pierce", -1)), 1, "aimed fire pierces one enemy")

	var shotgun: Dictionary = _entry(payloads, "payload_id", "gun_shotgun_pellets").get("parameters", {})
	suite.assert_close(float(shotgun.get("damage_multiplier", -1.0)), 0.7, "each shotgun pellet deals seventy percent attack")
	suite.assert_equal(int(shotgun.get("count", -1)), 8, "shotgun emits eight pellets")
	suite.assert_close(float(shotgun.get("spread_degrees", -1.0)), 45.0, "shotgun spans plus or minus forty-five degrees")

	var reload: Dictionary = _entry(payloads, "payload_id", "gun_reload_transaction").get("parameters", {})
	suite.assert_equal(int(reload.get("total_frames", -1)), 48, "reload lasts forty-eight frames")
	suite.assert_equal(int(reload.get("perfect_start_frame", -1)), 28, "perfect reload begins at frame twenty-eight")
	suite.assert_equal(int(reload.get("perfect_end_frame", -1)), 36, "perfect reload uses a half-open frame thirty-six boundary")
	suite.assert_equal(int(reload.get("normal_fill", -1)), 6, "normal reload fills six rounds")
	suite.assert_equal(int(reload.get("perfect_fill", -1)), 7, "perfect reload fills seven rounds")

	var time_load: Dictionary = _entry(payloads, "payload_id", "gun_time_load_buff").get("parameters", {})
	suite.assert_equal(int(time_load.get("duration_frames", -1)), 300, "Time Load lasts three hundred frames")
	suite.assert_close(float(time_load.get("action_frame_multiplier", -1.0)), 0.60, "Time Load applies forty percent faster future action frames")
	suite.assert_close(float(time_load.get("time_damage_multiplier", -1.0)), 0.15, "Time Load adds fifteen percent attack as time damage")

	var ultimate: Dictionary = _entry(payloads, "payload_id", "gun_void_round").get("parameters", {})
	suite.assert_close(float(ultimate.get("damage_multiplier", -1.0)), 15.0, "Void Penetration deals fifteen-times attack")
	suite.assert_close(float(ultimate.get("void_damage_ratio", -1.0)), 0.60, "Void Penetration is sixty percent void")
	suite.assert_close(float(ultimate.get("time_damage_ratio", -1.0)), 0.40, "Void Penetration is forty percent time")
	suite.assert_equal(bool(ultimate.get("unlimited_pierce", false)), true, "Void Penetration has unlimited pierce")
	suite.assert_equal(int(ultimate.get("trail_duration_frames", -1)), 300, "Void trail lasts five seconds")


func _test_interactions(suite, gun: Dictionary) -> void:
	var interactions: Dictionary = gun.get("time_interactions", {})
	var stop: Dictionary = interactions.get("stop", {}).get("parameters", {})
	suite.assert_close(float(stop.get("explosion_radius_tiles", -1.0)), 2.0, "Stop aimed burst radius is two tiles")
	suite.assert_close(float(stop.get("explosion_damage_multiplier", -1.0)), 1.0, "Stop aimed burst deals one attack as time damage")
	suite.assert_equal(int(stop.get("stop_extension_frames", -1)), 30, "Stop aimed burst extends Stop by thirty frames")
	var rewind: Dictionary = interactions.get("rewind", {}).get("parameters", {})
	suite.assert_equal(int(rewind.get("window_frames", -1)), 120, "Rewind free-shot window lasts two seconds")
	suite.assert_equal(bool(rewind.get("ammo_free", false)), true, "Rewind shot is ammo-free")
	suite.assert_close(float(rewind.get("damage_multiplier", -1.0)), 1.5, "Rewind shot deals one-and-a-half damage")
	var accelerate: Dictionary = interactions.get("accelerate", {}).get("parameters", {})
	suite.assert_equal(int(accelerate.get("recovery_delta_frames", 0)), -4, "Accelerate removes four recovery frames")
	suite.assert_close(float(accelerate.get("ammo_cost_multiplier", -1.0)), 0.5, "Accelerate halves ammunition cost before ceiling")
	var rift: Dictionary = interactions.get("rift", {}).get("parameters", {})
	suite.assert_equal(int(rift.get("duration_frames", -1)), 90, "Rift interaction trail lasts ninety frames")
	suite.assert_equal(int(rift.get("tick_interval_frames", -1)), 30, "Rift interaction trail ticks every thirty frames")
	var boss: Dictionary = gun.get("boss_interactions", {}).get("chrono_warden", {})
	suite.assert_equal(str(boss.get("type", "")), "poise_conversion", "Chrono Warden uses Gun poise conversion")
	suite.assert_close(float(boss.get("parameters", {}).get("poise_multiplier", -1.0)), 1.1, "Gun poise conversion multiplier is authoritative")


func _assert_action(
	suite,
	actions: Array,
	action_id: String,
	windup: int,
	active: int,
	recovery: int,
	cooldown: int,
	resource_cost: float
) -> void:
	var action := _entry(actions, "action_id", action_id)
	suite.assert_equal(int(action.get("windup_frames", -1)), windup, "%s windup is authoritative" % action_id)
	suite.assert_equal(int(action.get("active_frames", -1)), active, "%s active frames are authoritative" % action_id)
	suite.assert_equal(int(action.get("recovery_frames", -1)), recovery, "%s recovery is authoritative" % action_id)
	suite.assert_equal(int(action.get("cooldown_frames", 0)), cooldown, "%s cooldown is authoritative" % action_id)
	var costs: Dictionary = action.get("resource_costs", {})
	if resource_cost > 0.0:
		var key := "ammo" if action_id in ["normal_fire", "aimed_fire", "shotgun_fire"] else "time_energy"
		suite.assert_close(float(costs.get(key, -1.0)), resource_cost, "%s resource cost is authoritative" % action_id)
	else:
		suite.assert_true(costs.is_empty(), "%s has no resource cost" % action_id)


func _entry(entries: Variant, key: String, expected: String) -> Dictionary:
	if not entries is Array:
		return {}
	for value: Variant in entries as Array:
		if value is Dictionary and str((value as Dictionary).get(key, "")) == expected:
			return (value as Dictionary).duplicate(true)
	return {}
