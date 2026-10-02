extends Node

const MainScene := preload("res://scenes/main.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	var room_scene_host: Node = main.get_node_or_null("LaunchRoomSceneHost")
	suite.assert_true(room_scene_host != null, "Main owns the production Launch RoomSceneHost")
	var started = host.call("start_run", _launch_config())
	suite.assert_true(started.ok, "Main production host starts a Launch run")
	if started.ok and room_scene_host != null:
		var choices: Array = host.call("route_choices")
		suite.assert_true(not choices.is_empty(), "Launch run exposes an initial route")
		if not choices.is_empty():
			var selected = host.call(
				"select_route",
				StringName(str((choices[0] as Dictionary).get("edge_id", "")))
			)
			suite.assert_true(selected.ok, "Main production route streams and confirms its room scene")
			var active_room: Node2D = room_scene_host.call("active_room")
			suite.assert_true(active_room != null, "Main production route exposes the active room")
			var state: Dictionary = host.call("runtime_snapshot")
			var rule_state := state.get("floor_rule_state", {}) as Dictionary
			suite.assert_true(not rule_state.is_empty(), "Main production route configures its floor rule")
			if active_room != null and not rule_state.is_empty():
				var warning = host.get("_facade").call(
					"advance_floor_rule_frame",
					44,
					{},
					int(state["revision"])
				)
				suite.assert_true(warning.ok, "Main production rule reaches its final warning frame")
				var warning_state := host.call("runtime_snapshot") as Dictionary
				var warning_rule_state := warning_state.get("floor_rule_state", {}) as Dictionary
				var zone := _zone_by_id(
					warning_rule_state,
					str(warning_rule_state.get("active_zone_id", ""))
				)
				suite.assert_true(not zone.is_empty(), "active floor rule selects a scheduled hazard zone")
				if not zone.is_empty():
					var bounds := zone["bounds"] as Dictionary
					var player := main.get_node("CombatRoom01/Player") as Node2D
					player.global_position = active_room.to_global(Vector2(
						float(bounds["x"]) + float(bounds["width"]) * 0.5,
						float(bounds["y"]) + float(bounds["height"]) * 0.5
					))
					var health: Node = player.get_node("HealthComponent")
					health.current_hp = health.max_hp
					var hp_before := float(health.current_hp)
					var advanced = host.get("_facade").call(
						"advance_floor_rule_frame",
						45,
						{},
						int(warning.new_revision)
					)
					suite.assert_true(advanced.ok, "Main production authority accepts the first active hazard frame")
					suite.assert_true(float(health.current_hp) < hp_before, "Main production hazard reaches Player health")

					var second_started = host.call("start_run", _launch_config())
					suite.assert_true(second_started.ok, "same-seed second Launch run starts")
					suite.assert_equal(
						int((room_scene_host.call("active_snapshot") as Dictionary).get("instance_id", -1)),
						0,
						"new run clears the prior RoomSceneHost runtime scene"
					)
					var effect_authority: Variant = host.get("_floor_rule_effect_authority")
					suite.assert_true(
						effect_authority is Object
						and (effect_authority as Object).has_method("is_configured")
						and bool((effect_authority as Object).call("is_configured")),
						"new run preserves FloorRuleEffectAuthority configuration"
					)
					if second_started.ok:
						var second_choices: Array = host.call("route_choices")
						suite.assert_true(not second_choices.is_empty(), "same-seed second run exposes its first route")
						if not second_choices.is_empty():
							var second_selected = host.call(
								"select_route",
								StringName(str((second_choices[0] as Dictionary).get("edge_id", "")))
							)
							suite.assert_true(second_selected.ok, "same-seed second run streams its first room")
							var second_room: Node2D = room_scene_host.call("active_room")
							var second_state: Dictionary = host.call("runtime_snapshot")
							var second_warning = host.get("_facade").call(
								"advance_floor_rule_frame",
								44,
								{},
								int(second_state["revision"])
							)
							suite.assert_true(second_warning.ok, "same-seed second rule reaches its final warning frame")
							var second_warning_state := host.call("runtime_snapshot") as Dictionary
							var second_rule_state := second_warning_state.get("floor_rule_state", {}) as Dictionary
							var second_zone := _zone_by_id(
								second_rule_state,
								str(second_rule_state.get("active_zone_id", ""))
							)
							if second_selected.ok and second_warning.ok and second_room != null and not second_zone.is_empty():
								var second_bounds := second_zone["bounds"] as Dictionary
								player.global_position = second_room.to_global(Vector2(
									float(second_bounds["x"]) + float(second_bounds["width"]) * 0.5,
									float(second_bounds["y"]) + float(second_bounds["height"]) * 0.5
								))
								health.current_hp = health.max_hp
								var second_hp_before := float(health.current_hp)
								var second_advanced = host.get("_facade").call(
									"advance_floor_rule_frame",
									45,
									{},
									int(second_warning.new_revision)
								)
								suite.assert_true(second_advanced.ok, "same-seed second run accepts its first hazard frame")
								suite.assert_true(
									float(health.current_hp) < second_hp_before,
									"effect-id reset lets the same-seed second-run hazard apply"
								)

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _zone_by_id(rule_state: Dictionary, zone_id: String) -> Dictionary:
	for zone_value: Variant in rule_state.get("zones", []):
		if zone_value is Dictionary and str((zone_value as Dictionary).get("id", "")) == zone_id:
			return (zone_value as Dictionary).duplicate(true)
	return {}


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20261002,
		"accessibility_assists": {
			"damage_received_multiplier": 1.0,
			"enemy_telegraph_scale": 1.0,
		},
	}
