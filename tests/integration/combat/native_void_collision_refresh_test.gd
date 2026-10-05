extends "res://tests/integration/combat/void_arena_native_test.gd"

const NativeHitbox := preload("res://scripts/combat/hitbox.gd")
const RuinBoss := preload("res://data/content_packs/base/assets/bosses/launch/boss_ruin_king.tscn")
const RuinRoom := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_ruin_king.tscn")
const Arrow := preload("res://scenes/combat/player_arrow.tscn")
const GunProjectile := preload("res://scenes/combat/gun_projectile.tscn")
const StaffProjectile := preload("res://scenes/combat/staff_projectile.tscn")


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
	await _ruin_next_frame_contact()
	for weapon: String in ["bow", "gun", "staff"]:
		await _projectile_phase_contact(weapon)
	suite.finish(get_tree())


func _ruin_next_frame_contact() -> void:
	var room := RuinRoom.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := RuinBoss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.global_position = room.get_node("EncounterAnchors/boss_primary").global_position
	var parser := Definition.new()
	parser.configure(Content.boss("ruin_king"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-void-arena", "hostile_source_id": "ruin-contact-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "physical Ruin fixture binds accepted definition")
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_ruin_king":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "physical Ruin fixture binds actual room")
	var player := _contact_player("sword")
	var effects := Effects.new()
	effects.configure("run-void-arena")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "physical Ruin contact uses production frame checkpoint")
	var holder := actor.get_node("ArenaConstructs")
	var target := holder.get_child(0).get_node("Hurtbox") as Area2D
	var physical := await _physical_hit(target, player, 4, 78.0, holder, bridge)
	suite.assert_true(physical.get("physical_contact", false), "Ruin HP reduction comes from an actual physics query callback")
	suite.assert_equal(actor.native_arena_snapshot().covers[0].current_hp, 2.0, "physical contact synchronously commits finite Ruin cover HP")
	suite.assert_true(physical.get("next_frame_prepared", false), "immediate next physical frame flushes pending projection before production preparation")
	suite.assert_true(physical.get("next_frame_rolled_back", false), "immediate frame checkpoint remains valid for synchronous rollback")
	suite.assert_true(actor._native_geometry_matches_definition(), "immediate contact rollback retains exact accepted Ruin geometry")
	player.queue_free()
	actor.queue_free()
	room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _projectile_phase_contact(weapon: String) -> void:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.set_process(false)
	actor.set_physics_process(false)
	var player := _contact_player(weapon)
	var scene: PackedScene = {"bow": Arrow, "gun": GunProjectile, "staff": StaffProjectile}[weapon]
	var projectile := scene.instantiate() as Area2D
	projectile.process_mode = Node.PROCESS_MODE_ALWAYS
	var adapter: Node = player.get_node({"bow": "BowWeapon", "gun": "GunWeapon", "staff": "StaffWeapon"}[weapon])
	if weapon == "bow":
		projectile.damage = 4000.0
		projectile.action_token = 5
	elif weapon == "gun":
		suite.assert_true(projectile.configure_execution({"action_token": 5, "source_action_id": "normal_fire", "descriptor_id": "contact-gun", "outcome_index": 0, "deterministic_seed": 42, "damage": 4000.0, "base_attack": 4000.0, "speed": 760.0, "max_range_pixels": 960.0, "pierce": 0, "pierce_mode": "limited", "damage_type": Damage.DamageType.PHYSICAL, "time_damage_ratio": 0.0, "trail": {}, "time_interactions": [], "boss_conversion": {}, "resource_reward": {}, "action_claims": {}, "tags": ["weapon:gun"]}), "actual Gun contact fixture configures production execution")
	else:
		suite.assert_true(projectile.configure_execution({"action_token": 5, "generation": 5, "source_action_id": "arcane_bolt", "descriptor_id": "contact-staff", "outcome_index": 0, "deterministic_seed": 42, "element_id": "arcane", "damage": 4000.0, "base_attack": 4000.0, "speed": 560.0, "max_range_pixels": 768.0, "target_deduplication": "per_action_target", "effect_descriptor": {}, "combination": {}, "chain": {}}), "actual Staff contact fixture configures production execution")
	projectile.source = adapter
	projectile.owner_entity = player
	var holder := actor.get_node("VoidArenaConstructs")
	var target := actor.get_node("Hurtbox") as Area2D
	var observed := {}
	adapter.add_child(projectile)
	projectile.set_physics_process(false)
	projectile.area_entered.connect(func(area: Area2D):
		if area == target and observed.is_empty():
			observed["physical_contact"] = true
			observed["hp"] = actor.health.current_hp
			observed["during_children"] = holder.get_child_count()
	)
	projectile.global_position = target.global_position
	for _frame: int in range(6):
		await get_tree().physics_frame
		if not observed.is_empty():
			break
	suite.assert_true(observed.get("physical_contact", false), "actual %s signal delivers the phase-transition contact" % weapon)
	suite.assert_equal(observed.get("hp"), 600.0, "actual %s callback synchronously commits authenticated phase HP" % weapon)
	suite.assert_equal(observed.get("during_children"), 4, "actual %s callback defers native collision-body creation" % weapon)
	await get_tree().process_frame
	suite.assert_true(holder.get_child_count() == 8 and actor._native_geometry_matches_definition(), "post-query %s phase transition projects the exact native arena" % weapon)
	player.queue_free()
	actor.queue_free()
	room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _contact_player(weapon: String) -> Node2D:
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "contact fixture binds actual %s ownership" % weapon)
	player.global_position = Vector2(600, 160)
	return player


func _physical_hit(target: Area2D, player: Node2D, token: int, amount: float, holder: Node, next_bridge: RefCounted = null) -> Dictionary:
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
	if next_bridge != null:
		var ticket: Dictionary = next_bridge.begin_frame(1)
		observed["next_frame_prepared"] = not ticket.is_empty() and next_bridge.prepare_frame(ticket)
		observed["next_frame_rolled_back"] = not ticket.is_empty() and next_bridge.rollback_frame(ticket)
	await get_tree().process_frame
	sensor.queue_free()
	await get_tree().process_frame
	return observed
