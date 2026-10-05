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
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const IDENTITY := {"run_id": "run-sweep", "hostile_source_id": "native-root-sweep", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_selected_root_cancel()
	for origin: Vector2 in [Vector2.ZERO, Vector2(80, 48)]:
		await _test_native_hit(origin)
	suite.finish(get_tree())


func _fixture(origin: Vector2) -> Dictionary:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.position = origin
	var actor := Boss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = room.get_node("EncounterAnchors/boss_primary").global_position
	var parser := Definition.new()
	parser.configure(Content.boss("forest_heart"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), IDENTITY).ok, "actual Forest sweep binds native owner")
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "actual Forest sweep binds translated production room")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-sweep")
	player.global_position = origin + Vector2(132, 104)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-sweep", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "native root sweep participates in accepted Player frames")
	var runtime: RefCounted = actor.get("_launch_runtime")
	var result: Dictionary = runtime.request_action("matriarch_root_sweep", _context(0, actor.global_position, player.global_position))
	suite.assert_true(result.ok, "native root sweep selects root while stationary trunk is out of range")
	for fact: Dictionary in result.get("threat_facts", []):
		suite.assert_true(registry.register_fact(Actions.native_threat_fact(fact)), "native root warning joins the real threat registry")
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	var telegraph := actor.get_node_or_null("RootSweepTelegraph")
	suite.assert_true(telegraph != null, "native Forest projects its actual root-owned cone warning")
	if telegraph != null:
		var visual: Dictionary = telegraph.get_snapshot()
		suite.assert_true(visual.visible and visual.origin == origin + Vector2(112, 104) and visual.attack_generation == 7 and visual.target_point == player.global_position, "native root warning matches its frozen accepted geometry")
	return {"room": room, "actor": actor, "player": player, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "runtime": runtime}


func _test_selected_root_cancel() -> void:
	var fixture := _fixture(Vector2.ZERO)
	var actor: Node2D = fixture.actor
	var player: Node2D = fixture.player
	var received_generations: Array[int] = []
	var damage_observer := func(info: RefCounted, target: Node, _amount: float) -> void:
		if target == player:
			received_generations.append(int(info.attack_generation))
	EventBus.damage_applied.connect(damage_observer)
	var before: Dictionary = actor.launch_runtime_snapshot()
	var threats: Array = fixture.registry.snapshot()
	var root := actor.get_node("ArenaConstructs").get_child(0)
	await _capture("warning")
	var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
	var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	var accessible: Dictionary = actor.get_node("RootSweepTelegraph").get_snapshot() if actor.has_node("RootSweepTelegraph") else {}
	suite.assert_true(accessible.get("high_contrast_danger", false) and accessible.get("visual_length") == 144.0, "actual rooted warning honors high contrast and enlarged danger presentation")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "danger accessibility preserves authoritative root geometry and damage")
	await _capture("warning-high-contrast")
	GameState.set_setting("high_contrast_danger", old_contrast)
	GameState.set_setting("enemy_telegraph_scale", old_scale)
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	var ticket: Dictionary = fixture.bridge.begin_frame(1)
	suite.assert_equal(root.get_node("Hurtbox").receive_hit(_damage(player)), 100.0, "actual weapon destroys the selected native root during its warning")
	suite.assert_true(fixture.runtime.snapshot().action.phase == "IDLE" and not fixture.registry.contains_point(player.global_position, 45), "selected-root break retires native warning and future hit geometry")
	var telegraph := actor.get_node_or_null("RootSweepTelegraph")
	suite.assert_true(telegraph != null and not telegraph.visible, "selected-root destruction clears its actual native warning immediately")
	suite.assert_true(fixture.bridge.prepare_frame(ticket) and fixture.bridge.rollback_frame(ticket), "cancelled native sweep compensates a refused frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "sweep refusal restores root HP and exact frozen ownership")
	suite.assert_equal(fixture.registry.snapshot(), threats, "sweep refusal restores the exact native registry")
	suite.assert_true(telegraph != null and telegraph.visible, "refused root destruction restores its native warning")
	ticket = fixture.bridge.begin_frame(1)
	root.get_node("Hurtbox").receive_hit(_damage(player))
	suite.assert_true(fixture.bridge.prepare_frame(ticket) and _publish(fixture.bridge, ticket), "same selected-root weapon identity retries and permanently cancels the segment")
	suite.assert_true(actor.native_arena_snapshot().roots[0].broken and root.collision_layer == 0, "accepted cancellation preserves permanent segment destruction")
	await _capture("cancelled")
	await _cold(fixture, false)
	for frame: int in range(2, 47):
		await get_tree().physics_frame
		ticket = fixture.bridge.begin_frame(frame)
		suite.assert_true(fixture.bridge.prepare_frame(ticket) and _publish(fixture.bridge, ticket), "cancelled segment accepts frame%d" % frame)
	suite.assert_true(not received_generations.has(7), "destroyed selected root never delivers its scheduled20 damage while later Boss actions continue")
	EventBus.damage_applied.disconnect(damage_observer)
	await _dispose(fixture)


func _test_native_hit(origin: Vector2) -> void:
	var fixture := _fixture(origin)
	var actor: Node2D = fixture.actor
	var player: Node2D = fixture.player
	suite.assert_equal(fixture.runtime.snapshot().action.committed_origin, {"x": origin.x + 112.0, "y": origin.y + 104.0}, "actual root warning preserves the production room translation")
	for frame: int in range(1, 45):
		await get_tree().physics_frame
		var ticket: Dictionary = fixture.bridge.begin_frame(frame)
		suite.assert_true(fixture.bridge.prepare_frame(ticket) and _publish(fixture.bridge, ticket), "native root warning accepts frame%d" % frame)
		suite.assert_equal(player.health.current_hp, player.health.max_hp, "native root sweep deals no damage before full45-frame warning")
		if frame == 5:
			await _cold(fixture, true)
	var health_checkpoint: Dictionary = player.health.transaction_snapshot()
	var ticket: Dictionary = fixture.bridge.begin_frame(45)
	suite.assert_true(fixture.bridge.prepare_frame(ticket), "native root sweep activates actual Health damage")
	suite.assert_equal(player.health.current_hp, player.health.max_hp - 20.0, "actual rooted cone delivers authored20 physical damage")
	suite.assert_true(fixture.bridge.rollback_frame(ticket), "actual root hit compensates a refused accepted Player frame")
	suite.assert_true(player.health.restore_transaction_snapshot(health_checkpoint), "outer Player owner restores its refused health transaction")
	suite.assert_equal(player.health.current_hp, player.health.max_hp, "refused native root hit restores actual Player HP")
	ticket = fixture.bridge.begin_frame(45)
	suite.assert_true(fixture.bridge.prepare_frame(ticket) and _publish(fixture.bridge, ticket), "same root active frame retries once")
	suite.assert_equal(player.health.current_hp, player.health.max_hp - 20.0, "native root hit applies once after retry")
	await _cold(fixture, false)
	ticket = fixture.bridge.begin_frame(46)
	suite.assert_true(fixture.bridge.prepare_frame(ticket) and _publish(fixture.bridge, ticket), "root active tail remains accepted")
	suite.assert_equal(player.health.current_hp, player.health.max_hp - 20.0, "root active tail cannot repeat the one-shot melee hit")
	await _dispose(fixture)


func _cold(fixture: Dictionary, historical: bool) -> void:
	var cold: Dictionary = fixture.actor.native_cold_snapshot(func(_source: Node): return {})
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	room.position = fixture.room.position
	var twin := Boss.instantiate() as Node2D
	twin.process_mode = Node.PROCESS_MODE_DISABLED
	twin.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(twin)
	twin.global_position = fixture.actor.global_position
	var parser := Definition.new()
	parser.configure(Content.boss("forest_heart"))
	twin.configure_launch_definition(parser.runtime_projection(), IDENTITY)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			twin.configure_launch_room_motion(room, template)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "isolated actual Forest reconstructs accepted owned sweep")
	suite.assert_equal(twin.launch_runtime_snapshot().runtime, fixture.actor.launch_runtime_snapshot().runtime, "native cold root ownership and frozen action stay exact")
	if cold.actor.runtime.action.action_id == "matriarch_root_sweep":
		var historical_claim := cold.duplicate(true)
		historical_claim.actor.runtime.arena_state.historical_sweep_generation = historical_claim.actor.runtime.action.geometry_generations[0]
		historical_claim.actor.runtime.arena_state.sweep_claims.clear()
		suite.assert_true(not twin.can_restore_native_cold_snapshot(historical_claim, func(_binding: Dictionary): return null), "native current root geometry cannot claim the historical trunk exemption")
	var forged := cold.duplicate(true)
	forged.actor.runtime.arena_state.arena_origin.x += 1.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "native cold sweep refuses an origin outside its validated room")
	if historical:
		var old_action: RefCounted = fixture.runtime._make_action(0, false)
		var target: Vector2 = fixture.actor.global_position + Vector2(20, 0)
		old_action.request_action("matriarch_root_sweep", _context(0, fixture.actor.global_position, target))
		for frame: int in range(1, int(cold.actor.runtime.runtime_frame) + 1):
			old_action.advance_frame(frame, _context(frame, fixture.actor.global_position, target))
		for version: int in [1, 2]:
			var legacy := cold.duplicate(true)
			legacy.actor.runtime.schema_version = version
			legacy.actor.runtime.action = old_action.snapshot()
			if version == 1:
				legacy.actor.runtime.erase("arena_state")
			else:
				legacy.actor.runtime.arena_state.schema_version = 1
				for field: String in ["arena_origin", "sweep_claims", "historical_sweep_generation"]:
					legacy.actor.runtime.arena_state.erase(field)
			suite.assert_true(twin.restore_native_cold_snapshot(legacy, func(_binding: Dictionary): return null), "nativeBoss%d historical trunk-origin warning migrates explicitly" % version)
			suite.assert_equal(twin.launch_runtime_snapshot().runtime.action.committed_origin, {"x": fixture.actor.global_position.x, "y": fixture.actor.global_position.y}, "historical migration preserves the already-committed trunk geometry")
			suite.assert_equal(twin.get_node("RootSweepTelegraph").get_snapshot().origin, fixture.actor.global_position, "historical native warning projects its retained trunk origin")
	world.queue_free()
	await get_tree().process_frame


func _capture(pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var output := "res://build/visual-evidence/p15b-native-arena/forest-root-sweep-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native root sweep screenshot retained")


func _dispose(fixture: Dictionary) -> void:
	fixture.effects.dispose_native_effects()
	for node: Node in [fixture.actor, fixture.player, fixture.root, fixture.room]:
		node.queue_free()
	await get_tree().process_frame


func _context(frame: int, source: Vector2, target: Vector2) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": source.x, "y": source.y}, "target_position": {"x": target.x, "y": target.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}


func _damage(player: Node2D) -> RefCounted:
	return Damage.from_plan({"run_id": "run-sweep", "target_id": "pending-root", "hostile_source_id": "player:sword", "attack_generation": 1, "action_token": 1, "amount": 100.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
