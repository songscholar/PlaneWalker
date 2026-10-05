extends "res://tests/integration/combat/boss_arena_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var actor := _actor()
		actor.process_mode = Node.PROCESS_MODE_INHERIT
		actor.set_physics_process(false)
		var player := _player()
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.set_physics_process(false)
		player.get_node("TimeManager").set_process(false)
		player.get_node("RewindRecorder").set_process(false)
		suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "normal%sinput configures authentic Ruin construct source" % weapon)
		var cover: Node2D = actor.get_node("ArenaConstructs/Cover0")
		player.global_position = cover.global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}) and player.try_action(&"weapon_primary"), "normal%sinput accepts real Ruin cover attack" % weapon)
		for frame: int in range(120):
			if frame == 40:
				player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "normal%sRuin cover action frame%dcommits" % [weapon, frame])
			await get_tree().physics_frame
		suite.assert_true(cover.native_construct_snapshot().current_hp < 80.0, "normal%sproduction input hits real Ruin cover Hurtbox" % weapon)
		suite.assert_equal(actor.health.current_hp, 800.0, "normal%scover damage leaves independently owned Boss body HP exact" % weapon)
		player.cancel_transient_actions()
		player.queue_free()
		actor.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	suite.finish(get_tree())
