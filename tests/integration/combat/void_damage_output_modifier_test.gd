extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Player := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	var suite := Suite.new()
	var player := Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"void-output")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "outputmodifier fixture uses actual Launchownership")
	var before: Dictionary = player.floor_rule_effect_snapshot()
	var attack: float = player.get_effective_attack()
	var loadout: Dictionary = player.loadout_runtime.snapshot()
	suite.assert_true(player.apply_floor_rule_modifier(&"void_auxiliary:boss", &"status", &"apply", {"attack_multiplier": 0.85}), "sourceowned native Void outputmodifier accepts authored0.85")
	suite.assert_equal(player.get_effective_attack(), attack * 0.85, "actual Player weapon boundary applies reduced damageoutput")
	suite.assert_equal(player.loadout_runtime.snapshot(), loadout, "devour preserves actual itemweapon and time ownership")
	suite.assert_true(player.restore_floor_rule_effect_snapshot(before) and player.get_effective_attack() == attack, "outputmodifier compensates exact sourceowned checkpoint")
	suite.assert_true(not player.apply_floor_rule_modifier(&"void_auxiliary:boss", &"status", &"apply", {"attack_multiplier": 0.0}) and not player.apply_floor_rule_modifier(&"void_auxiliary:boss", &"status", &"apply", {"attack_multiplier": INF}), "zero and nonfinite output values failclosed")
	player.apply_floor_rule_modifier(&"void_auxiliary:boss", &"status", &"apply", {"movement_multiplier": 0.65})
	player.apply_floor_rule_modifier(&"launch_semantic", &"movement", &"apply", {"movement_multiplier": 0.5})
	suite.assert_equal(player._floor_rule_movement_multiplier(), 0.5, "native hostile overlap uses strongest slow once")
	player.apply_floor_rule_modifier(&"void_auxiliary:second-boss", &"status", &"apply", {"movement_multiplier": 0.4})
	suite.assert_equal(player._floor_rule_movement_multiplier(), 0.4, "multiple hostile sources preserve movement floor")
	player.apply_floor_rule_modifier(&"outside_floor_rule", &"movement", &"apply", {"movement_multiplier": 0.8})
	suite.assert_close(player._floor_rule_movement_multiplier(), 0.32, "independent floor rule retains existing multiplicative behavior")
	player.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
