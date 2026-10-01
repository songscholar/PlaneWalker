extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CASES: Array[Dictionary] = [
	{
		"profile_id": "wanderer_m1_v1",
		"character_id": "wanderer",
		"milestone": "M1",
		"stats": {
			"max_hp": 200.0,
			"attack": 30.0,
			"defense": 0.0,
			"move_speed": 220.0,
			"attack_speed": 1.0,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5,
			"time_energy_max": 100.0,
			"time_energy_regen": 2.0,
		},
		"mobility": {
			"dash_duration_frames": 17,
			"dash_cooldown_frames": 27,
			"dash_speed": 520.0,
			"dash_cost_kind": "none",
			"dash_cost": 0.0,
			"dash_invulnerable_frames": 12,
		},
	},
	{
		"profile_id": "wanderer_launch_v1",
		"character_id": "wanderer",
		"milestone": "LAUNCH",
		"stats": {
			"max_hp": 200.0,
			"attack": 30.0,
			"defense": 0.0,
			"move_speed": 220.0,
			"attack_speed": 1.0,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5,
			"time_energy_max": 100.0,
			"time_energy_regen": 2.0,
		},
		"mobility": {
			"dash_duration_frames": 17,
			"dash_cooldown_frames": 27,
			"dash_speed": 520.0,
			"dash_cost_kind": "none",
			"dash_cost": 0.0,
			"dash_invulnerable_frames": 12,
		},
	},
	{
		"profile_id": "time_guardian_launch_v1",
		"character_id": "time_guardian",
		"milestone": "LAUNCH",
		"stats": {
			"max_hp": 240.0,
			"attack": 27.0,
			"defense": 10.0,
			"move_speed": 190.0,
			"attack_speed": 0.9,
			"crit_chance": 0.04,
			"crit_multiplier": 1.5,
			"time_energy_max": 120.0,
			"time_energy_regen": 2.0,
		},
		"mobility": {
			"dash_duration_frames": 18,
			"dash_cooldown_frames": 30,
			"dash_speed": 500.0,
			"dash_cost_kind": "none",
			"dash_cost": 0.0,
			"dash_invulnerable_frames": 12,
		},
	},
	{
		"profile_id": "void_walker_launch_v1",
		"character_id": "void_walker",
		"milestone": "LAUNCH",
		"stats": {
			"max_hp": 160.0,
			"attack": 32.0,
			"defense": 0.0,
			"move_speed": 235.0,
			"attack_speed": 1.05,
			"crit_chance": 0.08,
			"crit_multiplier": 1.6,
			"time_energy_max": 90.0,
			"time_energy_regen": 2.0,
		},
		"mobility": {
			"dash_duration_frames": 15,
			"dash_cooldown_frames": 24,
			"dash_speed": 560.0,
			"dash_cost_kind": "none",
			"dash_cost": 0.0,
			"dash_invulnerable_frames": 11,
		},
	},
	{
		"profile_id": "primordial_knight_launch_v1",
		"character_id": "primordial_knight",
		"milestone": "LAUNCH",
		"stats": {
			"max_hp": 230.0,
			"attack": 31.0,
			"defense": 8.0,
			"move_speed": 200.0,
			"attack_speed": 0.9,
			"crit_chance": 0.05,
			"crit_multiplier": 1.55,
			"time_energy_max": 110.0,
			"time_energy_regen": 2.0,
		},
		"mobility": {
			"dash_duration_frames": 18,
			"dash_cooldown_frames": 30,
			"dash_speed": 490.0,
			"dash_cost_kind": "none",
			"dash_cost": 0.0,
			"dash_invulnerable_frames": 10,
		},
	},
	{
		"profile_id": "time_lord_launch_v1",
		"character_id": "time_lord",
		"milestone": "LAUNCH",
		"stats": {
			"max_hp": 175.0,
			"attack": 24.0,
			"defense": 2.0,
			"move_speed": 205.0,
			"attack_speed": 0.95,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5,
			"time_energy_max": 160.0,
			"time_energy_regen": 4.0,
		},
		"mobility": {
			"dash_duration_frames": 16,
			"dash_cooldown_frames": 27,
			"dash_speed": 520.0,
			"dash_cost_kind": "none",
			"dash_cost": 0.0,
			"dash_invulnerable_frames": 12,
		},
	},
]

const POLLUTED_STATS := {
	"max_hp": 13.0,
	"attack": 777.0,
	"defense": 99.0,
	"move_speed": 333.0,
	"attack_speed": 3.0,
	"crit_chance": 0.75,
	"crit_multiplier": 4.0,
	"time_energy_max": 17.0,
	"time_energy_regen": 9.0,
}
const POLLUTED_MOBILITY := {
	"dash_duration_frames": 9,
	"dash_cooldown_frames": 11,
	"dash_speed": 333.0,
	"dash_cost_kind": "none",
	"dash_cost": 0.0,
	"dash_invulnerable_frames": 3,
}

var _suite
var _registry: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(not report.has_blocking_errors(), "profile reconstruction fixture loads base content")
	await _test_all_six_profiles_reconstruct_fresh_state_atomically()
	_suite.finish(get_tree())


func _test_all_six_profiles_reconstruct_fresh_state_atomically() -> void:
	for case: Dictionary in PROFILE_CASES:
		await _test_profile_case(case)


func _test_profile_case(case: Dictionary) -> void:
	var profile_id := str(case["profile_id"])
	var expected_stats := (case["stats"] as Dictionary).duplicate(true)
	var expected_mobility := (case["mobility"] as Dictionary).duplicate(true)
	var config := _profile_config(case)
	_suite.assert_true(not config.is_empty(), "%s resolves authoritative character and weapon profiles" % profile_id)
	if config.is_empty():
		return
	_suite.assert_equal(
		(config["character_profile"] as Dictionary).get("base_stats", {}),
		expected_stats,
		"%s fixture pins the exact base-stats row" % profile_id
	)
	_suite.assert_equal(
		_normalized_profile_mobility(
			(config["character_profile"] as Dictionary).get("mobility", {}) as Dictionary
		),
		expected_mobility,
		"%s fixture pins every exact mobility field" % profile_id
	)

	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(config), "%s first fresh activation succeeds" % profile_id)
	_assert_committed_profile_state(player, case, "first activation")

	var first_stats: Resource = player.stats
	var health: Node = player.get_node("HealthComponent")
	var time_manager: Node = player.get_node("TimeManager")
	_suite.assert_true(player.stats.apply_profile(POLLUTED_STATS), "%s accepts valid run-local stat pollution fixture" % profile_id)
	_suite.assert_true(player.apply_mobility_profile(POLLUTED_MOBILITY), "%s accepts valid run-local mobility pollution fixture" % profile_id)
	health.max_hp = 13.0
	health.current_hp = 1.0
	health.dead = true
	time_manager.max_energy = 17.0
	time_manager.energy = 1.0
	time_manager.energy_regen = 9.0

	_suite.assert_true(player.configure_loadout(config), "%s second fresh activation succeeds" % profile_id)
	_suite.assert_true(player.stats != first_stats, "%s second activation allocates a fresh Stats authority" % profile_id)
	_assert_committed_profile_state(player, case, "second activation after pollution")

	var before_forgery: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(not before_forgery.is_empty(), "%s exposes a complete rollback snapshot" % profile_id)
	var committed_stats: Resource = player.stats
	var forged_stats := config.duplicate(true)
	(forged_stats["character_profile"] as Dictionary)["base_stats"]["attack"] = (
		float(expected_stats["attack"]) + 100.0
	)
	_suite.assert_true(not player.configure_loadout(forged_stats), "%s rejects forged base stats" % profile_id)
	_suite.assert_true(player.stats == committed_stats, "%s forged stats preserve the committed Stats authority" % profile_id)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before_forgery,
		"%s forged stats preserve the complete Player snapshot" % profile_id
	)

	var forged_mobility := config.duplicate(true)
	(forged_mobility["character_profile"] as Dictionary)["mobility"]["dash_speed"] = (
		float(expected_mobility["dash_speed"]) + 100.0
	)
	_suite.assert_true(not player.configure_loadout(forged_mobility), "%s rejects forged mobility" % profile_id)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before_forgery,
		"%s forged mobility preserves the complete Player snapshot" % profile_id
	)

	var missing_stat := config.duplicate(true)
	(missing_stat["character_profile"] as Dictionary)["base_stats"].erase("crit_multiplier")
	_suite.assert_true(not player.configure_loadout(missing_stat), "%s rejects a missing numeric stat instead of falling back" % profile_id)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before_forgery,
		"%s missing stat preserves the complete Player snapshot" % profile_id
	)

	var missing_mobility := config.duplicate(true)
	(missing_mobility["character_profile"] as Dictionary)["mobility"].erase("dash_cooldown_frames")
	_suite.assert_true(not player.configure_loadout(missing_mobility), "%s rejects missing mobility instead of using Player constants" % profile_id)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before_forgery,
		"%s missing mobility preserves the complete Player snapshot" % profile_id
	)
	await _free_player(player)


func _assert_committed_profile_state(player: Node, case: Dictionary, phase: String) -> void:
	var profile_id := str(case["profile_id"])
	var label_prefix := "%s %s" % [profile_id, phase]
	var expected_stats := case["stats"] as Dictionary
	var expected_mobility := case["mobility"] as Dictionary
	_suite.assert_equal(player.stats.snapshot(), expected_stats, "%s installs exact base stats" % label_prefix)
	_suite.assert_equal(player.mobility_snapshot(), expected_mobility, "%s installs exact mobility" % label_prefix)
	_suite.assert_equal(
		str(player.loadout_runtime.character_profile_id()),
		profile_id,
		"%s commits the exact character profile identity" % label_prefix
	)
	_suite.assert_equal(
		str(player.loadout_runtime.character_id()),
		str(case["character_id"]),
		"%s commits the exact character identity" % label_prefix
	)
	var health: Node = player.get_node("HealthComponent")
	var time_manager: Node = player.get_node("TimeManager")
	_suite.assert_close(float(health.max_hp), float(expected_stats["max_hp"]), "%s synchronizes maximum HP" % label_prefix)
	_suite.assert_close(float(health.current_hp), float(expected_stats["max_hp"]), "%s restores current HP" % label_prefix)
	_suite.assert_true(not bool(health.dead), "%s clears the prior-run dead state" % label_prefix)
	_suite.assert_close(float(health.defense), float(expected_stats["defense"]), "%s synchronizes defense" % label_prefix)
	_suite.assert_close(float(time_manager.max_energy), float(expected_stats["time_energy_max"]), "%s synchronizes maximum Time Energy" % label_prefix)
	_suite.assert_close(float(time_manager.energy), float(expected_stats["time_energy_max"]), "%s restores current Time Energy" % label_prefix)
	_suite.assert_close(float(time_manager.energy_regen), float(expected_stats["time_energy_regen"]), "%s synchronizes Time Energy regeneration" % label_prefix)
	var identity: Dictionary = player.full_player_replay_identity()
	_suite.assert_equal(identity.get("stats", {}), expected_stats, "%s seals exact stats into Replay identity" % label_prefix)
	_suite.assert_equal(identity.get("mobility", {}), expected_mobility, "%s seals exact mobility into Replay identity" % label_prefix)


func _profile_config(case: Dictionary) -> Dictionary:
	var profile_id := StringName(str(case["profile_id"]))
	var character_profile: Dictionary = _registry.call("get_character_runtime_profile", profile_id)
	var milestone := StringName(str(case["milestone"]))
	var weapon_profile: Dictionary = _registry.call(
		"resolve_weapon_runtime_profile", &"sword", milestone
	)
	if character_profile.is_empty() or weapon_profile.is_empty():
		return {}
	return {
		"schema_version": 1,
		"milestone": str(milestone),
		"character_id": str(case["character_id"]),
		"character_profile": character_profile,
		"character_talents": [],
		"weapon_id": "sword",
		"weapon_profile": weapon_profile,
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}


func _normalized_profile_mobility(value: Dictionary) -> Dictionary:
	return {
		"dash_duration_frames": int(value.get("dash_duration_frames", 0)),
		"dash_cooldown_frames": int(value.get("dash_cooldown_frames", 0)),
		"dash_speed": float(value.get("dash_speed", 0.0)),
		"dash_cost_kind": str(value.get("dash_cost_kind", "")),
		"dash_cost": float(value.get("dash_cost", 0.0)),
		"dash_invulnerable_frames": int(value.get("dash_invulnerable_frames", 0)),
	}


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	return player


func _free_player(player: Node) -> void:
	await get_tree().create_timer(0.65).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
