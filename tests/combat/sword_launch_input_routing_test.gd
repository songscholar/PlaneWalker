extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured: bool = player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260930,
		"weapon_profile": _profile_definition(),
	})
	suite.assert_true(configured, "PlayerController equips the authoritative Launch Sword profile")
	if configured:
		suite.assert_equal(
			player.call("_weapon_semantic_input_mode", &"weapon_secondary"),
			&"press",
			"Guard is honestly routed as a timed press action"
		)
		suite.assert_true(player.try_action(&"weapon_secondary"), "Guard pressed edge commits through the real PlayerController")
		var committed: Dictionary = player.weapon_action_coordinator.snapshot()
		suite.assert_equal(committed.get("phase"), "WINDUP", "Guard press enters its authored windup")
		suite.assert_true(
			not bool(player.call("_submit_weapon_intent", &"weapon_secondary", &"held")),
			"press-mode Guard filters held edges before Coordinator submission"
		)
		suite.assert_equal(player.weapon_action_coordinator.snapshot(), committed, "filtered held edge cannot mutate the committed Guard")
		suite.assert_true(
			not bool(player.call("_submit_weapon_intent", &"weapon_secondary", &"released")),
			"press-mode Guard filters released edges before Coordinator submission"
		)
		suite.assert_equal(player.weapon_action_coordinator.snapshot(), committed, "filtered release edge cannot produce STALE_HOLD_EDGE or mutate Guard")
		var restored_player := PlayerScene.instantiate()
		restored_player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(restored_player)
		await get_tree().process_frame
		var restored_configured: bool = restored_player.configure_loadout(_launch_config())
		suite.assert_true(restored_configured, "strict restore fixture equips a second Launch Sword")
		if restored_configured:
			suite.assert_true(
				restored_player.weapon_action_coordinator.restore_snapshot(committed),
				"real Coordinator restores a valid Launch Sword WINDUP snapshot"
			)
			suite.assert_equal(
				restored_player.weapon_action_coordinator.snapshot(),
				committed,
				"Coordinator restore reinstalls Sword runtime, resources, plan, phase, and token exactly"
			)
			var forged := committed.duplicate(true)
			(forged["runtime"]["launch_adapter"] as Dictionary)["guard_active"] = true
			var before_forged: Dictionary = restored_player.weapon_action_coordinator.snapshot()
			suite.assert_true(
				not restored_player.weapon_action_coordinator.restore_snapshot(forged),
				"Coordinator rejects an impossible WINDUP snapshot with active Guard state"
			)
			suite.assert_equal(
				restored_player.weapon_action_coordinator.snapshot(),
				before_forged,
				"rejected Sword restore preserves the prior Coordinator and runtime atomically"
			)
		restored_player.queue_free()
		await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _profile_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == "sword_launch_v1":
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260930,
		"weapon_profile": _profile_definition(),
	}
