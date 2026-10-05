extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://data/content_packs/base/assets/bosses/launch/boss_forest_heart.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_forest_heart.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := Boss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = room.get_node("EncounterAnchors/boss_primary").global_position
	var parser := Definition.new()
	parser.configure(Content.boss("forest_heart"))
	actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-roots", "hostile_source_id": "forest-root-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			actor.configure_launch_room_motion(room, template)
	suite.assert_equal(actor.native_arena_snapshot().get("roots", []).size(), 6, "actual Forest Boss creates six native authoritative roots")
	if not actor.native_arena_snapshot().get("roots", []).is_empty():
		await _capture(actor, "intact")
		await _check_native(actor, room)
	actor.queue_free()
	room.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _check_native(actor: Node2D, room: Node2D) -> void:
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-roots")
	player.global_position = Vector2(600, 160)
	player.health.acquire_invulnerability_source(&"roots-fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-roots", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual roots join native accepted Boss frames")
	var arena := actor.get_node("ArenaConstructs")
	var first := arena.get_child(0)
	suite.assert_true(first is StaticBody2D and not first.is_in_group("enemies") and not first.is_in_group("bosses"), "actual root is an uncounted native arena body")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var ticket: Dictionary = bridge.begin_frame(1)
	suite.assert_equal(first.get_node("Hurtbox").receive_hit(_damage(player, 1, 100.0)), 100.0, "actual root weapon hit breaks onlyHP100")
	suite.assert_equal(first.get_node("Hurtbox").receive_hit(_damage(player, 1, 100.0)), 0.0, "actual root weapon collision deduplicates")
	suite.assert_equal(actor.health.current_hp, 1400.0, "root damage never becomes trunk damage")
	suite.assert_true(bridge.prepare_frame(ticket) and bridge.rollback_frame(ticket), "root destruction compensates a refused native frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "root compensation restores exact state and claims")
	suite.assert_equal(first.collision_layer, 1, "root compensation restores its physical collider")
	ticket = bridge.begin_frame(1)
	first.get_node("Hurtbox").receive_hit(_damage(player, 1, 100.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "same root break accepts after compensation")
	suite.assert_true(first.collision_layer == 0 and actor.get("_launch_runtime").is_exposed(), "accepted root break removes collider and exposes trunk")
	await _check_cold(actor, "P1")
	for frame: int in range(2, 46):
		await get_tree().physics_frame
		ticket = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket) or not _publish(bridge, ticket):
			suite.assert_true(false, "actual root exposure accepts sequential frame%d" % frame)
			bridge.rollback_frame(ticket)
			break
		suite.assert_true(actor.get("_launch_runtime").is_exposed(), "native root break exposes the trunk for all45 accepted frames")
	before = actor.launch_runtime_snapshot()
	ticket = bridge.begin_frame(46)
	suite.assert_equal(actor.get_node("Hurtbox").receive_hit(_damage(player, 2, 600.0)), 600.0, "always-hittable trunk receives direct authenticated weapon damage")
	var phase_prepared: bool = bridge.prepare_frame(ticket)
	var phase_rolled_back: bool = bridge.rollback_frame(ticket)
	suite.assert_true(phase_prepared and phase_rolled_back, "actualP2 retirement compensates a refused native frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "P2 refusal restores exact root and Boss domains")
	suite.assert_equal(actor.health.current_hp, 1400.0, "P2 refusal restores actual trunk health")
	suite.assert_equal(arena.get_child(1).collision_layer, 1, "P2 refusal restores the surviving root collider")
	ticket = bridge.begin_frame(46)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 2, 600.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual trunk damage retriesP2 with deterministic permanent root retirement")
	suite.assert_true(not actor.get("_launch_runtime").is_exposed(), "native root exposure expires after its full45-frame window")
	suite.assert_equal(actor.native_arena_snapshot().phase_retirement.root_ids, ["forest_root:1", "forest_root:2", "forest_root:3"], "realP2 skips permanently broken roots")
	suite.assert_equal(actor.health.current_hp, 800.0, "P2 retry applies trunk damage exactly once")
	await _check_cold(actor, "P2")
	await _capture(actor, "retired")
	var untouched: Dictionary = actor.launch_runtime_snapshot()
	var root_position: Vector2 = arena.get_child(4).global_position
	arena.get_child(4).global_position.x += 1.0
	var direction := actor.global_position.direction_to(player.global_position)
	var context := {"runtime_frame": 47, "source_position": {"x": actor.global_position.x, "y": actor.global_position.y}, "target_position": {"x": player.global_position.x, "y": player.global_position.y}, "facing_direction": {"x": direction.x, "y": direction.y}, "target_id": "player:1"}
	suite.assert_true(not actor.prepare_launch_frame(47, context).ok, "tampered native root geometry rejects accepted frame preparation")
	suite.assert_equal(arena.get_child(4).get_node("Hurtbox").receive_hit(_damage(player, 4, 100.0)), 0.0, "tampered native root geometry rejects weapon settlement")
	suite.assert_equal(actor.launch_runtime_snapshot(), untouched, "root geometry refusal leaves exact authoritative state unchanged")
	arena.get_child(4).global_position = root_position
	ticket = bridge.begin_frame(47)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 3, 800.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual Forest owner death accepts terminal root retirement")
	for body: StaticBody2D in arena.get_children():
		suite.assert_true(body.collision_layer == 0 and body.get_node("Hurtbox").collision_layer == 0 and not body.visible, "terminal Forest leaves no root collision or reward target")
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _check_cold(actor: Node2D, phase: String) -> void:
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var twin := Boss.instantiate() as Node2D
	twin.process_mode = Node.PROCESS_MODE_DISABLED
	twin.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(twin)
	twin.global_position = actor.global_position
	var parser := Definition.new()
	parser.configure(Content.boss("forest_heart"))
	twin.configure_launch_definition(parser.runtime_projection(), actor.get("_launch_identity"))
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			twin.configure_launch_room_motion(room, template)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh actual Forest reconstructs current " + phase + " root cold state")
	suite.assert_equal(twin.native_arena_snapshot(), actor.native_arena_snapshot(), "root cold HP, break and exposure stay exact")
	suite.assert_equal(twin.get_node("ArenaConstructs").get_child(0).collision_layer, 0, "cold Forest never resurrects a destroyed root")
	for mutation: String in ["hp", "exposure", "phase"]:
		var forged := cold.duplicate(true)
		match mutation:
			"hp": forged.actor.runtime.arena_state.roots[4].current_hp -= 1.0
			"exposure": forged.actor.runtime.arena_state.exposure_through_frame += 1
			"phase": forged.actor.runtime.arena_state.phase_retirement = {}
		if mutation != "phase" or phase == "P2":
			suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "native root cold state rejects forged " + mutation)
	var historical := cold.duplicate(true)
	historical.actor.runtime.schema_version = 1
	historical.actor.runtime.erase("arena_state")
	historical.actor.runtime.erase("forest_auxiliary")
	suite.assert_true(twin.restore_native_cold_snapshot(historical, func(_binding: Dictionary): return null), "exact historical Forest schema1 receives explicit " + phase + " arena migration")
	var migrated: Dictionary = twin.native_arena_snapshot()
	suite.assert_true(migrated.damage_claims.is_empty() and not migrated.roots[0].broken, "historical rootless schema migrates to declared undamaged roots")
	suite.assert_equal(migrated.phase_retirement.get("root_ids", []), ["forest_root:0", "forest_root:1", "forest_root:2"] if phase == "P2" else [], "historicalP2 default deterministically retires the first three surviving roots")
	world.queue_free()
	await get_tree().process_frame


func _capture(actor: Node2D, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		for node: Node2D in actor.get_node("ArenaConstructs").get_children():
			var colors: Dictionary = {}
			for y: int in range(int(node.global_position.y) - 16, int(node.global_position.y) + 16):
				for x: int in range(int(node.global_position.x) - 16, int(node.global_position.x) + 16):
					colors[pixels.get_pixelv(Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))).to_rgba32()] = true
			suite.assert_true(colors.size() >= 4, "actual Forest root raster renders nonblank at " + str(resolution))
		var output := "res://build/visual-evidence/p15b-native-arena/forest-roots-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual Forest roots screenshot retained")


func _damage(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-roots", "target_id": "pending-root", "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
