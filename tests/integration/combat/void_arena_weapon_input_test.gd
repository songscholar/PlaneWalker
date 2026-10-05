extends "res://tests/integration/combat/void_auxiliary_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var context := _open_case(false, Vector2(350, 180))
		context.actor.process_mode = Node.PROCESS_MODE_INHERIT
		context.actor.set_physics_process(false)
		context.player.process_mode = Node.PROCESS_MODE_INHERIT
		context.player.set_physics_process(false)
		context.player.get_node("TimeManager").set_process(false)
		context.player.get_node("RewindRecorder").set_process(false)
		context.player.health.acquire_invulnerability_source(&"void-weapon-fixture")
		suite.assert_true(context.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": context.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "normal %s input configures production Void weapon" % weapon)
		suite.assert_true(context.player.configure_hostile_frame_participant(context.bridge), "normal %s input shares native Player and Boss frame" % weapon)
		var pillar: Node2D = context.actor.get_node("VoidArenaConstructs").get_child(0)
		context.player.global_position = pillar.global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		suite.assert_true(context.player.advance_action_frame({"aim": Vector2.RIGHT}) and context.player.try_action(&"weapon_primary"), "normal %s input starts actual Void pillar attack" % weapon)
		for frame: int in range(120):
			if frame == 40:
				context.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			var accepted: bool = context.player.advance_action_frame({"aim": Vector2.RIGHT})
			suite.assert_true(accepted, "normal %s native Void frame %d accepts" % [weapon, frame])
			if not accepted:
				break
			await get_tree().physics_frame
		suite.assert_true(pillar.native_construct_snapshot().current_hp < 120.0, "normal %s production input damages actual Void pillar Hurtbox" % weapon)
		context.player.cancel_transient_actions()
		suite.assert_true(context.player.configure_hostile_frame_participant(null), "normal weapon input detaches native frame authority")
		await _close_case(context)
	suite.finish(get_tree())
