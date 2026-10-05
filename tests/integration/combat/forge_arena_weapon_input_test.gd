extends "res://tests/integration/combat/forge_arena_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var f := await _fixture()
		f.actor.process_mode = Node.PROCESS_MODE_INHERIT
		f.actor.set_physics_process(false)
		f.actor.global_position = Vector2(360, 280)
		f.player.process_mode = Node.PROCESS_MODE_INHERIT
		f.player.set_physics_process(false)
		f.player.get_node("TimeManager").set_process(false)
		f.player.get_node("RewindRecorder").set_process(false)
		suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": f.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "normal%sinput configures production Forge weapon source" % weapon)
		var anvil: Node2D = f.actor.get_node("ArenaConstructs/Anvil0")
		f.player.global_position = anvil.global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary"), "normal%sinput starts actual Forge anvil attack" % weapon)
		for frame: int in range(120):
			if frame == 40:
				f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "normal%sForge weapon frame%dcommits" % [weapon, frame])
			await get_tree().physics_frame
		suite.assert_true(anvil.native_construct_snapshot().current_hp < 120.0, "normal%sproduction input hits actual Forge anvil Hurtbox" % weapon)
		suite.assert_equal(f.actor.health.current_hp, 2800.0, "normal%sanvil damage preserves independent Boss bodyHP" % weapon)
		f.player.cancel_transient_actions()
		await _dispose(f)
	suite.finish(get_tree())
