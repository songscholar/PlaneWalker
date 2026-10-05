extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://data/content_packs/base/assets/bosses/launch/boss_void_throne.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_void_throne.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	var has_native_void: bool = actor.has_method("native_void_arena_snapshot")
	suite.assert_true(actor.has_method("native_void_arena_snapshot"), "actual Void Boss must expose authoritative native pillars and cores")
	if actor.has_method("native_void_arena_snapshot"):
		await _check_native(actor, room)
	actor.queue_free()
	await get_tree().process_frame
	if has_native_void:
		for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
			await _normal_weapon(room, weapon)
		for health_case: String in ["capped", "full", "dead"]:
			await _heal_boundary(room, health_case)
	room.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _normal_weapon(room: Node2D, weapon: String) -> void:
	var actor := _boss(room)
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.set_process(false)
	actor.set_physics_process(false)
	var player := Player.instantiate() as Node2D
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-void-arena")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual%sloadout binds native construct weapon producer" % weapon)
	var pillar: Node2D = actor.get_node("VoidArenaConstructs").get_child(0)
	player.global_position = pillar.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}) and player.try_action(&"weapon_primary"), "normal%sinput accepts actual construct attack" % weapon)
	for frame: int in range(120):
		if frame == 40:
			player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "normal%sconstruct action frame%dcommits" % [weapon, frame])
		await get_tree().physics_frame
	suite.assert_true(actor.native_void_arena_snapshot().pillars[0].current_hp < 120.0, "normal%sproduction input hits real pillar Hurtbox" % weapon)
	player.cancel_transient_actions()
	player.queue_free()
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _heal_boundary(room: Node2D, health_case: String) -> void:
	var actor := _boss(room)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-void-arena")
	player.global_position = Vector2(600, 160)
	if health_case == "dead":
		player.health.lose_health(player.health.max_hp, actor)
	elif health_case == "capped":
		player.health.lose_health(5.0, actor)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "real%sPlayer joins native Void healing boundary" % health_case)
	var ticket: Dictionary = bridge.begin_frame(1)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 4000.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "real%sPlayer never prevents accepted P3 frame" % health_case)
	var heal: Dictionary = actor.native_void_arena_snapshot().player_heal
	if health_case == "dead":
		suite.assert_true(player.health.dead and player.health.current_hp == 0.0 and heal.get("amount", -1.0) == 0.0 and not actor._launch_runtime.void_player_heal_pending(), "Void P3 consumes a zero heal without reviving a dead Player")
	else:
		suite.assert_equal(player.health.current_hp, player.health.max_hp, "Void P3 caps%sactual Health gain" % health_case)
		suite.assert_equal(heal.get("amount", -1.0), 5.0 if health_case == "capped" else 0.0, "Void P3 records%sactual capped amount exactly once" % health_case)
	effects.dispose_native_effects()
	player.queue_free()
	actor.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _boss(room: Node2D) -> Node2D:
	var actor := Boss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	room.get_parent().add_child(actor)
	actor.global_position = room.get_node("EncounterAnchors/boss_primary").global_position
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-void-arena", "hostile_source_id": "void-arena-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_void_throne":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "actual Void constructs bind authored room geometry")
	return actor


func _check_native(actor: Node2D, room: Node2D) -> void:
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	player.global_position = Vector2(600, 160)
	player.health.current_hp = 50.0
	player.health.acquire_invulnerability_source(&"void-fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "actual Void constructs join accepted native Boss frames")
	var holder := actor.get_node("VoidArenaConstructs")
	suite.assert_equal(holder.get_child_count(), 4, "actual initial arena has four physical pillars")
	await _capture(actor, room, player, "pillars")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var player_before: Dictionary = player.health.transaction_snapshot()
	var healed_hp: float = 50.0 + player.health.max_hp * 0.3
	var ticket: Dictionary = bridge.begin_frame(1)
	suite.assert_equal(actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 4000.0)), 2400.0, "actual reachable outerbody accepts authored0.60damage")
	suite.assert_true(bridge.prepare_frame(ticket), "actualP3 prepares one Health heal and four native cores")
	suite.assert_equal(player.health.current_hp, healed_hp, "P3 actual HealthComponent heals thirtypercentmaximum once")
	suite.assert_true(bridge.rollback_frame(ticket), "P3 Player heal and native corecreation compensate a refused frame")
	suite.assert_true(player.health.restore_transaction_snapshot(player_before), "outer Player transaction restores refused P3 healing")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "refusedP3 restores exact Boss and arena state")
	suite.assert_equal(player.health.current_hp, 50.0, "refusedP3 restores actual PlayerHP")
	suite.assert_equal(holder.get_child_count(), 4, "refusedP3 removes staged native cores")
	ticket = bridge.begin_frame(1)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 4000.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actualP3 retries one committed heal and four cores")
	suite.assert_equal(player.health.current_hp, healed_hp, "acceptedP3 heals exactlyonce afterrollback")
	suite.assert_equal(holder.get_child_count(), 8, "actualP3 retains pillars as debris and creates four cores")
	if holder.get_child_count() != 8:
		effects.dispose_native_effects()
		player.queue_free()
		root.queue_free()
		await get_tree().process_frame
		return
	for index: int in range(4):
		suite.assert_equal(holder.get_child(index).collision_layer, 0, "P3 oldpillar debris never obstructs or damages")
	var core := holder.get_child(4)
	before = actor.launch_runtime_snapshot()
	ticket = bridge.begin_frame(2)
	suite.assert_equal(core.get_node("Hurtbox").receive_hit(_damage(player, 2, 100.0)), 100.0, "actual corecollision consumes its exactHP100")
	suite.assert_equal(actor.health.current_hp, 500.0, "actual corebreak loses exactly100bodyHP through HealthComponent")
	suite.assert_equal(core.get_node("Hurtbox").receive_hit(_damage(player, 2, 100.0)), 0.0, "duplicate actual corehit never loses bodyHPtwice")
	suite.assert_true(bridge.prepare_frame(ticket), "actual corebreak prepares native frame boundary")
	var refused_publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(not refused_publication.is_empty() and bridge.finalize_frame_publication(refused_publication) and bridge.rollback_frame(ticket), "actual corebreak compensates after finalized publication is refused")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "corebreak refusal restores physicalHPand exposureclaims")
	suite.assert_equal(core.collision_layer, 1, "corebreak refusal restores actual bodycollider")
	ticket = bridge.begin_frame(2)
	core.get_node("Hurtbox").receive_hit(_damage(player, 2, 100.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual corebreak retries onebodyloss")
	suite.assert_equal(actor.health.current_hp, 500.0, "accepted corebodyloss remains exactly100")
	suite.assert_equal(player.health.current_hp, healed_hp, "later corebreaks never repeatP3healing")
	await _cold(actor)
	await _capture(actor, room, player, "core-break")
	var position: Vector2 = holder.get_child(5).global_position
	holder.get_child(5).global_position.x += 1.0
	suite.assert_equal(holder.get_child(5).get_node("Hurtbox").receive_hit(_damage(player, 3, 100.0)), 0.0, "tampered physicalcore rejects actual weapon settlement")
	holder.get_child(5).global_position = position
	ticket = bridge.begin_frame(3)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 4, 1000.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual ownerdeath retires all Void arena bodies")
	for body: Node2D in holder.get_children():
		suite.assert_true(body.collision_layer == 0 and body.get_node("Hurtbox").collision_layer == 0 and not body.visible, "terminal Void leaves no constructcollision or rewardtarget")
	effects.dispose_native_effects()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _cold(actor: Node2D) -> void:
	var original: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var encoded := Replay.encode_replay_json(original)
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := ContentSnapshot.snapshot(registry)
	var storage_root := ProjectSettings.globalize_path("res://build/test-data/void-arena")
	var storage := Save.new()
	storage.configure(storage_root, "test-void-arena", binding)
	suite.assert_true(encoded.ok and storage.save_profile("void_schema5", "base", {"codec": encoded.json}).ok, "actual SaveService retains typed native Void phase/core/heal aggregate")
	var fresh := Save.new()
	fresh.configure(storage_root, "test-void-arena", binding)
	var recovered: Variant = fresh.inspect_profile("void_schema5", "base")
	suite.assert_true(recovered.ok, "fresh physical SaveService recovers native Void aggregate")
	if not recovered.ok:
		return
	var cold: Dictionary = Replay.decode_replay_json(recovered.payload.payload.codec).replay
	suite.assert_equal(cold, original, "physical native Void recovery preserves exact typed claims and Health state")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var twin := _boss(room)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh actual Void reconstructs phase/core/healclaims")
	suite.assert_equal(twin.native_void_arena_snapshot(), actor.native_void_arena_snapshot(), "fresh native Void retains exact finitecore ownership")
	suite.assert_equal(twin.get_node("VoidArenaConstructs").get_child(4).collision_layer, 0, "cold reconstruction never resurrects a broken core")
	var forged := cold.duplicate(true)
	forged.actor.runtime.void_arena_state.player_heal.amount += 1.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "native cold restore refuses fabricated Playerhealing")
	world.queue_free()
	await get_tree().process_frame


func _capture(actor: Node2D, room: Node2D, player: Node2D, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.world_2d = actor.get_world_2d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var scale_value := minf(float(resolution.x) / 640.0, float(resolution.y) / 360.0)
		var inset := (Vector2(resolution) - Vector2(640, 360) * scale_value) * 0.5
		add_child(viewport)
		var parents: Array[Node] = [room.get_parent(), actor.get_parent(), player.get_parent()]
		for body: Node2D in [room, actor, player]:
			body.reparent(viewport)
		await get_tree().process_frame
		await get_tree().process_frame
		viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scale_value, 0.0, inset)
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		suite.assert_equal(pixels.get_size(), resolution, "native Void capture has the exact requested resolution")
		for body: Node2D in actor.get_node("VoidArenaConstructs").get_children():
			var colors: Dictionary = {}
			for y: int in range(int(body.global_position.y) - 24, int(body.global_position.y) + 16):
				for x: int in range(int(body.global_position.x) - 24, int(body.global_position.x) + 24):
					colors[pixels.get_pixelv(Vector2i(Vector2(x, y) * scale_value + inset)).to_rgba32()] = true
			suite.assert_true(colors.size() >= 4, "actual Void construct raster is nonblank at " + str(resolution))
		var path := "res://build/visual-evidence/void-arena/native-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "native Void arena capture is retained")
		for index: int in range(3):
			([room, actor, player][index] as Node2D).reparent(parents[index])
		viewport.queue_free()
		await get_tree().process_frame


func _damage(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-void-arena", "target_id": "pending-void", "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
