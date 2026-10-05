extends "res://tests/integration/combat/void_arena_native_test.gd"

const NativeHitbox := preload("res://scripts/combat/hitbox.gd")


func _run() -> void:
	suite = Suite.new()
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.set_process(false)
	actor.set_physics_process(false)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "collision refresh fixture binds actual Sword ownership")
	player.global_position = Vector2(600, 160)
	var holder := actor.get_node("VoidArenaConstructs")
	var phase_hit := await _physical_hit(actor.get_node("Hurtbox"), player, 1, 4000.0, holder)
	suite.assert_true(phase_hit.get("physical_contact", false), "phase transition comes from an actual physics query callback")
	suite.assert_equal(phase_hit.get("loss"), 2400.0, "actual physics contact commits the authenticated phase transition")
	suite.assert_equal(phase_hit.get("during_children"), 4, "query callback does not create new native collision bodies")
	suite.assert_equal(holder.get_child_count(), 8, "deferred native projection creates four phase-three cores before the next frame")
	suite.assert_true(actor._native_geometry_matches_definition(), "post-query native geometry exactly matches accepted Void phase state")
	if holder.get_child_count() == 8:
		var core := holder.get_child(4)
		var core_hit := await _physical_hit(core.get_node("Hurtbox"), player, 2, 100.0, holder)
		suite.assert_true(core_hit.get("physical_contact", false), "core break comes from an actual physics query callback")
		suite.assert_equal(core_hit.get("loss"), 100.0, "actual core contact consumes its exact finite HP")
		suite.assert_true(actor.health.current_hp == 500.0 and core.collision_layer == 0 and actor._native_geometry_matches_definition(), "post-query core break retires its collider and commits one body loss")
	var terminal_hit := await _physical_hit(actor.get_node("Hurtbox"), player, 3, 1000.0, holder)
	suite.assert_true(terminal_hit.get("physical_contact", false) and actor.health.dead, "actual physical final contact reaches authenticated death")
	for construct: Node2D in holder.get_children():
		suite.assert_true(construct.collision_layer == 0 and construct.get_node("Hurtbox").collision_layer == 0 and not construct.visible, "post-query terminal refresh retires every native construct")
	player.queue_free()
	actor.queue_free()
	room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _physical_hit(target: Area2D, player: Node2D, token: int, amount: float, holder: Node) -> Dictionary:
	var observed := {}
	var sensor := NativeHitbox.new()
	sensor.process_mode = Node.PROCESS_MODE_ALWAYS
	sensor.collision_layer = 0
	sensor.collision_mask = 4
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	collider.shape = circle
	sensor.add_child(collider)
	player.get_node("SwordWeapon").add_child(sensor)
	var owner_actor: Node = target.get_parent() if target.get_parent().get("health") != null else target.get_parent().get("_boss")
	var hp_before: float = owner_actor.health.current_hp
	sensor.area_entered.connect(func(area: Area2D):
		if area == target and observed.is_empty():
			observed["physical_contact"] = true
			observed["loss"] = hp_before - owner_actor.health.current_hp
			observed["during_children"] = holder.get_child_count()
	)
	sensor.global_position = target.global_position
	sensor.activate(_damage(player, token, amount))
	for _frame: int in range(6):
		await get_tree().physics_frame
		if not observed.is_empty():
			break
	await get_tree().process_frame
	sensor.queue_free()
	await get_tree().process_frame
	return observed
