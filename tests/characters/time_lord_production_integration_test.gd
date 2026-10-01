extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var registry := ContentRegistryScript.new()
	var report: RefCounted = registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(not report.call("has_blocking_errors"), "Time Lord fixture loads Base Pack")
	if not report.call("has_blocking_errors"):
		await _test_hold_owner_commits_infusion(registry)
	_suite.finish(get_tree())


func _test_hold_owner_commits_infusion(registry: RefCounted) -> void:
	var player := PlayerScene.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(player.reset_runtime_state(), "Time Lord fixture resets")
	_suite.assert_true(player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "time_lord",
		"character_profile": registry.call(
			"resolve_character_runtime_profile", &"time_lord", &"LAUNCH"
		),
		"character_talents": [],
		"weapon_id": "sword",
		"weapon_profile": registry.call(
			"resolve_weapon_runtime_profile", &"sword", &"LAUNCH"
		),
		"enabled_time_skills": [&"stop", &"rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}), "Time Lord Launch loadout configures")

	var manager: Node = player.get_node("TimeManager")
	manager.set("energy", manager.get("max_energy"))
	var energy_before := float(manager.get("energy"))
	_suite.assert_true(
		player.advance_action_frame(_character_intent(&"pressed", 0)),
		"hold press advances"
	)
	var owner_after_press: Dictionary = player.character_input_owner_snapshot()
	_suite.assert_true(bool(owner_after_press.get("active", false)), "hold press latches a deterministic owner")
	for held_frames: int in range(1, 13):
		_suite.assert_true(
			player.advance_action_frame(_character_intent(&"held", held_frames)),
			"owned hold frame %d advances" % held_frames
		)
	_suite.assert_true(
		player.advance_action_frame(_character_intent(&"released", 12)),
		"owned release advances"
	)
	var accepted := player.priority_arbitration_snapshot().get("accepted", {}) as Dictionary
	_suite.assert_equal(
		StringName(str(accepted.get("id", ""))),
		&"character_skill",
		"release commits the Time Lord character skill"
	)
	_suite.assert_true(
		not bool(player.character_input_owner_snapshot().get("active", true)),
		"release clears the hold owner"
	)
	_suite.assert_close(
		float(manager.get("energy")),
		energy_before - 10.0,
		"Infusion spends its exact ten energy through the Player transaction"
	)

	player.queue_free()
	await get_tree().process_frame


func _character_intent(edge: StringName, held_frames: int) -> Dictionary:
	return {
		"character": [{
			"id": &"character_skill",
			"edge": edge,
			"held_frames": held_frames,
			"mode": &"hold",
		}],
	}
