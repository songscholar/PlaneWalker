extends Node

const FloorRuleEffectAuthorityScript := preload(
	"res://scripts/dungeon/floor_rule_effect_authority.gd"
)
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class ZoneHost:
	extends Node2D

	var room_id: String = "room_a"

	func active_room() -> Node2D:
		return self

	func floor_rule_configuration() -> Dictionary:
		return {
			"room_id": room_id,
			"zones": [
				{"id": "hazard", "bounds": {"x": 0.0, "y": 0.0, "width": 64.0, "height": 64.0}},
			],
			"safe_zone_ids": [],
		}

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var player := PlayerScene.instantiate()
	var zone_host := ZoneHost.new()
	add_child(player)
	add_child(zone_host)
	await get_tree().process_frame
	player.global_position = Vector2(32.0, 32.0)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.reset_runtime_state()

	var authority = FloorRuleEffectAuthorityScript.new()
	suite.assert_true(authority.configure(player, zone_host), "production authority accepts Player and RoomSceneHost contracts")
	var health: Node = player.get_node("HealthComponent")
	suite.assert_true(not (health.call("reward_effect_snapshot") as Dictionary).is_empty(), "health exposes a reversible authority snapshot")
	suite.assert_true(not (player.call("floor_rule_effect_snapshot") as Dictionary).is_empty(), "Player exposes a reversible floor-rule snapshot")
	health.current_hp = 20.0
	var damage := _damage_fact(45, 8.0)
	suite.assert_true(authority.commit_floor_rule_effects([damage]), "hazard damage batch commits")
	suite.assert_close(health.current_hp, 12.0, "hazard damage reaches the Player health authority")
	suite.assert_true(authority.commit_floor_rule_effects([damage]), "replayed fact is idempotently accepted")
	suite.assert_close(health.current_hp, 12.0, "replayed fact cannot damage twice")

	player.global_position = Vector2(128.0, 128.0)
	suite.assert_true(authority.commit_floor_rule_effects([_damage_fact(75, 8.0)]), "outside-zone fact commits as a no-op")
	suite.assert_close(health.current_hp, 12.0, "outside-zone fact cannot damage the Player")
	player.global_position = Vector2(32.0, 32.0)
	health.current_hp = 4.0
	suite.assert_true(authority.commit_floor_rule_effects([_damage_fact(105, 8.0)]), "nonlethal hazard commits at low health")
	suite.assert_close(health.current_hp, 1.0, "nonlethal hazard preserves the declared minimum HP")

	player.reset_runtime_state()
	player.global_position = Vector2(32.0, 32.0)
	var initial_modifier_snapshot: Dictionary = player.call("floor_rule_effect_snapshot")
	var apply_modifier := _modifier_fact(45, "apply", {
		"movement_multiplier": 0.85,
		"time_cost_multiplier": 1.15,
	})
	suite.assert_true(authority.commit_floor_rule_effects([apply_modifier]), "floor-rule modifier commits")
	suite.assert_close(player.get_action_movement_multiplier(), 0.85, "modifier changes Player movement")
	suite.assert_close(
		float(player.get_node("TimeManager").call("floor_rule_cost_multiplier")),
		1.15,
		"modifier changes Player time costs"
	)
	suite.assert_true(
		authority.commit_floor_rule_effects([_modifier_fact(195, "remove", {})]),
		"floor-rule cleanup commits"
	)
	suite.assert_equal(
		player.call("floor_rule_effect_snapshot"),
		initial_modifier_snapshot,
		"cleanup restores the exact transient modifier snapshot"
	)

	var before_invalid_hp := float(health.current_hp)
	var before_invalid_modifiers: Dictionary = player.call("floor_rule_effect_snapshot")
	suite.assert_true(
		not authority.commit_floor_rule_effects([_damage_fact(135, 4.0), {"forged": true}]),
		"invalid mixed batch fails closed"
	)
	suite.assert_close(health.current_hp, before_invalid_hp, "invalid batch preserves health")
	suite.assert_equal(
		player.call("floor_rule_effect_snapshot"),
		before_invalid_modifiers,
		"invalid batch preserves modifiers"
	)

	player.queue_free()
	zone_host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _damage_fact(runtime_frame: int, amount: float) -> Dictionary:
	return {
		"fact_type": "damage",
		"rule_id": "rule_crumbling_ground",
		"room_id": "room_a",
		"runtime_frame": runtime_frame,
		"cycle_index": 0,
		"zone_id": "hazard",
		"source_kind": "floor_rule",
		"source_id": "rule_crumbling_ground:room_a",
		"payload": {
			"amount": amount,
			"damage_type": "physical",
			"target_scope": "player_in_zone",
			"nonlethal": true,
			"minimum_remaining_hp": 1.0,
		},
	}


func _modifier_fact(runtime_frame: int, operation: String, values: Dictionary) -> Dictionary:
	return {
		"fact_type": "modifier",
		"rule_id": "rule_temporal_distortion",
		"room_id": "room_a",
		"runtime_frame": runtime_frame,
		"cycle_index": 0,
		"zone_id": "hazard",
		"source_kind": "floor_rule",
		"source_id": "rule_temporal_distortion:room_a",
		"payload": {
			"modifier_id": "temporal_distortion",
			"target_scope": "player_in_zone",
			"duration_frames": 150 if operation == "apply" else 0,
			"values": values.duplicate(true),
			"operation": operation,
		},
	}
