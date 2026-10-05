extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_ruin_king.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_wall()
	await _test_safe_activation()
	await _test_safe_activation(true)
	await _test_safe_activation(false, true)
	await _test_safe_activation(false, false, true)
	suite.finish(get_tree())


func _test_wall() -> void:
	var actor := _actor()
	actor.global_position = Vector2(320, 160)
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	move_child(room, 0)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "wall binds actual room bounds")
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-wall")
	player.global_position = Vector2(400, 160)
	suite.assert_true(actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 400)) > 0.0, "actual damage enters Ruin P2")
	var runtime: RefCounted = actor.get("_launch_runtime")
	# Only the phase-cue warmup is pure; the wall warning and every transition are native.
	for frame: int in range(1, 61):
		suite.assert_true(runtime.advance_frame(frame, _context(frame, actor, player), false).ok, "phase cue fixture advances")
	player.set("_runtime_frame", 60)
	actor._refresh_control_visual()
	var root := Node2D.new()
	add_child(root)
	var registry := Registry.new()
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-wall", 60) and effects.configure_native_payloads(root), "wall collapse uses shared native effect budget")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "wall binds accepted-frame participant")
	var committed: Dictionary = runtime.request_action("guardian_wall", _context(60, actor, player))
	suite.assert_true(committed.ok, "P2 wall starts full55-frame warning")
	for fact: Dictionary in committed.get("threat_facts", []):
		registry.register_fact(Actions.native_threat_fact(fact))
	var ready := true
	for frame: int in range(61, 116):
		await get_tree().physics_frame
		var before: Dictionary = actor.launch_runtime_snapshot()
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "wall prepares actual frame%d" % frame)
			bridge.rollback_frame(ticket)
			ready = false
			break
		if frame < 115:
			suite.assert_equal(actor.get_node("ArenaConstructs").get_child_count(), 4, "warning has no hidden physical wall")
		else:
			var state: Dictionary = actor.native_arena_snapshot()
			suite.assert_true(state.get("walls", []).size() == 2 and actor.get_node("ArenaConstructs").get_child_count() == 6, "first native active frame creates two actual HP150 wall segments")
			suite.assert_true(actor.global_position.x <= 291.0, "warning moves Boss clear of its frozen wall")
			suite.assert_true(bridge.rollback_frame(ticket), "wall creation compensates a refused sibling frame")
			suite.assert_equal(actor.launch_runtime_snapshot(), before, "rejection restores exact position, generation and arena")
			suite.assert_equal(actor.get_node("ArenaConstructs").get_child_count(), 4, "rejection removes uncommitted wall colliders")
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket), "same wall creation retries after compensation")
		suite.assert_true(_publish(bridge, ticket), "wall accepts actual frame%d" % frame)
	if ready and actor.native_arena_snapshot().get("walls", []).size() == 2:
		await _check_live_walls(actor, player, bridge, room, effects, registry)
	actor.queue_free()
	player.queue_free()
	room.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _check_live_walls(actor: Node2D, player: Node2D, bridge: RefCounted, room: Node2D, effects: RefCounted, registry: RefCounted) -> void:
	var arena := actor.get_node("ArenaConstructs")
	for index: int in range(4, 6):
		var wall := arena.get_child(index) as StaticBody2D
		var row: Dictionary = wall.native_construct_snapshot()
		suite.assert_true(row.current_hp == 150.0 and row.lifetime_frames == 600 and wall.get_node("CollisionShape2D").shape is RectangleShape2D, "wall projects authored HP, TTL and flat endpoint collider")
		suite.assert_equal(wall.get_node("CollisionShape2D").shape.size, Vector2(64, 12), "rectangular64px segment preserves exact32px endpoint passage")
		suite.assert_true(not wall.is_in_group("enemies") and not wall.is_in_group("bosses"), "wall never becomes another counted enemy")
	await _capture(actor, "intact")
	var wall := arena.get_child(4)
	var damage_before: Dictionary = actor.launch_runtime_snapshot()
	var damage_ticket: Dictionary = bridge.begin_frame(116)
	suite.assert_equal(wall.get_node("Hurtbox").receive_hit(_damage(player, 10, 150)), 150.0, "actual weapon collision destroys only the declared wall HP")
	suite.assert_equal(wall.get_node("Hurtbox").receive_hit(_damage(player, 10, 150)), 0.0, "wall rejects duplicate weapon identity")
	suite.assert_true(bridge.prepare_frame(damage_ticket) and bridge.rollback_frame(damage_ticket), "wall damage compensates a refused native frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), damage_before, "rejection restores wall HP and damage provenance")
	damage_ticket = bridge.begin_frame(116)
	suite.assert_equal(wall.get_node("Hurtbox").receive_hit(_damage(player, 10, 150)), 150.0, "same collision retries after rollback")
	suite.assert_true(bridge.prepare_frame(damage_ticket) and _publish(bridge, damage_ticket), "wall destruction accepts once")
	await _capture(actor, "broken")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var twin := _actor()
	twin.global_position = Vector2(320, 160)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			suite.assert_true(twin.configure_launch_room_motion(room, template).ok, "fresh wall Boss binds the same real room")
	var restored: bool = twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null)
	suite.assert_true(restored, "fresh Boss reconstructs native walls and damage")
	suite.assert_equal(twin.native_arena_snapshot(), actor.native_arena_snapshot(), "cold wall domain state stays exact")
	if restored:
		suite.assert_equal(twin.get_node("ArenaConstructs").get_child(4).collision_layer, 0, "cold restore never resurrects destroyed wall")
		for mutation: String in ["hp", "age", "shape", "generation", "unknown"]:
			var forged := cold.duplicate(true)
			match mutation:
				"hp": forged.actor.runtime.arena_state.walls[1].current_hp = 149.0
				"age": forged.actor.runtime.arena_state.walls[1].age += 1
				"shape": forged.actor.runtime.arena_state.walls[1].length_px = 65.0
				"generation": forged.actor.runtime.arena_state.wall_claims[0].attack_generation += 1
				"unknown": forged.actor.runtime.arena_state.walls[1].extra = true
			suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged wall cold state rejects: " + mutation)
	var historical := cold.duplicate(true)
	historical.actor.runtime.arena_state.schema_version = 1
	historical.actor.runtime.arena_state.erase("walls")
	historical.actor.runtime.arena_state.erase("wall_claims")
	historical.actor.runtime.arena_state.damage_claims = []
	suite.assert_true(twin.restore_native_cold_snapshot(historical, func(_binding: Dictionary): return null), "exact historical covers-only arena normalizes with empty walls")
	suite.assert_equal(twin.get_node("ArenaConstructs").get_child_count(), 4, "historical arena cannot inherit current wall nodes")
	twin.queue_free()
	await get_tree().process_frame
	# Keep later AI attacks out of this lifetime fixture, then enter the warned collapse.
	player.global_position = Vector2(1000, 1000)
	for frame: int in range(117, 756):
		if frame == 715:
			player.global_position = Vector2(320, 240)
		var before: Dictionary = actor.launch_runtime_snapshot()
		var effect_before: Dictionary = effects.snapshot()
		var threats_before: Array = registry.snapshot()
		var health_before: Dictionary = player.health.transaction_snapshot()
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "wall lifetime prepares frame%d" % frame)
			bridge.rollback_frame(ticket)
			player.health.discard_transaction_snapshot(health_before)
			break
		if frame in [715, 755]:
			suite.assert_true(bridge.rollback_frame(ticket) and player.health.restore_transaction_snapshot(health_before), "wall expiry and collapse damage compensate a refused whole frame")
			suite.assert_equal(actor.launch_runtime_snapshot(), before, "rejection restores complete wall age and retirement")
			suite.assert_equal(effects.snapshot(), effect_before, "rejection restores native collapse reservation and claims")
			suite.assert_equal(registry.snapshot(), threats_before, "rejection restores exact collapse warnings")
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket), "same wall lifetime transition retries after compensation")
		suite.assert_true(_publish(bridge, ticket), "native wall lifetime publishes frame%d" % frame)
		player.health.discard_transaction_snapshot(health_before)
		if frame == 714:
			suite.assert_true(arena.get_child(5).collision_layer == 1 and actor.native_arena_snapshot().walls[1].age == 599, "surviving wall retains actual collision for all600 accepted lifetime frames")
		if frame == 715:
			suite.assert_true(arena.get_child(5).collision_layer == 0 and actor.native_arena_snapshot().walls[1].expired, "TTL retirement removes actual wall collider")
			suite.assert_true(effects.semantic_snapshot().zones.size() == 1 and effects.semantic_snapshot().zones[0].phase == "WARNING", "only intact expiring wall reserves one40-frame physical collapse warning")
			await _capture(actor, "collapse-warning")
		if frame == 754:
			suite.assert_equal(player.health.current_hp, player.health.max_hp, "collapse never hits before all40 warning frames")
		if frame == 755:
			suite.assert_equal(player.health.current_hp, player.health.max_hp - 8.0, "authentic final collapse deals one authored8HP native hit")
			await _capture(actor, "collapsed")


func _test_safe_activation(edge: bool = false, exact_end: bool = false, retreat_edge: bool = false) -> void:
	var actor := _actor()
	actor.global_position = Vector2(320, 160)
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	move_child(room, 0)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "safe wall fixture binds actual room")
	if edge:
		actor.global_position.y = 25.0
	elif exact_end:
		actor.global_position.y = 242.0
	elif retreat_edge:
		actor.global_position.x = 24.0
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-wall")
	player.global_position = actor.global_position + Vector2(80, 0)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 400))
	var runtime: RefCounted = actor.get("_launch_runtime")
	for frame: int in range(1, 61):
		runtime.advance_frame(frame, _context(frame, actor, player), false)
	player.set("_runtime_frame", 60)
	actor._refresh_control_visual()
	var root := Node2D.new()
	add_child(root)
	var registry := Registry.new()
	var effects := Effects.new()
	effects.configure("run-wall", 60)
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	bridge.configure(player, registry, [actor], effects)
	var committed: Dictionary = runtime.request_action("guardian_wall", _context(60, actor, player))
	for fact: Dictionary in committed.get("threat_facts", []):
		registry.register_fact(Actions.native_threat_fact(fact))
	for frame: int in range(61, 117):
		if frame == 115 and not edge and not exact_end and not retreat_edge:
			player.global_position = Vector2(320, 240)
		elif frame == 116:
			player.global_position = Vector2(400, 160)
		await get_tree().physics_frame
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "occupied wall position delays safely at actual frame%d" % frame)
			bridge.rollback_frame(ticket)
			break
		suite.assert_true(_publish(bridge, ticket), "safe wall frame accepts")
		if frame == 115:
			if edge or retreat_edge:
				suite.assert_true(actor.native_arena_snapshot().walls.is_empty() and runtime.snapshot().action.phase == "IDLE", "unusable frozen geometry cancels after full warning instead of stalling permanently")
				suite.assert_equal(registry.snapshot().size(), 0, "unusable edge placement retires both actual frozen warnings")
			elif exact_end:
				suite.assert_equal(actor.native_arena_snapshot().walls.size(), 2, "legal endpoint exactly354px admits without an off-by-one perpetual warning")
			else:
				suite.assert_true(actor.native_arena_snapshot().walls.is_empty() and runtime.snapshot().action.phase == "WARNING" and runtime.snapshot().action.paused_frames == 1, "Player overlap preserves one extended full warning without spawning an encasing wall")
				suite.assert_equal(registry.snapshot().size(), 2, "both frozen wall segment warnings remain registered while occupied")
		if frame == 116:
			if edge or retreat_edge:
				suite.assert_true(runtime.snapshot().action.action_id != "guardian_wall" and runtime.snapshot().runtime_frame == 116, "native AI continues after safely declined edge placement")
			else:
				suite.assert_equal(actor.native_arena_snapshot().walls.size(), 2, "same frozen decision creates walls after Player clears their positions")
				if not actor.native_arena_snapshot().walls.is_empty():
					suite.assert_equal(actor.native_arena_snapshot().walls[0].spawn_frame, 115 if exact_end else 116, "safety deferral preserves full wall TTL from actual admitted frame")
	actor.queue_free()
	player.queue_free()
	room.queue_free()
	root.queue_free()
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
		for index: int in range(4, 6):
			var wall := actor.get_node("ArenaConstructs").get_child(index) as Node2D
			var colors: Dictionary = {}
			for y: int in range(int(wall.global_position.y) - 36, int(wall.global_position.y) + 36):
				for x: int in range(int(wall.global_position.x) - 14, int(wall.global_position.x) + 14):
					colors[pixels.get_pixelv(Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))).to_rgba32()] = true
			suite.assert_true(colors.size() >= 4, "native wall raster renders nonblank at " + str(resolution))
		var output := "res://build/visual-evidence/p15b-native-arena/ruin-wall-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native wall screenshot retained")


func _actor() -> Node2D:
	var actor := BossScene.instantiate() as Node2D
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var definition := Definition.new()
	definition.configure(Content.boss("ruin_king"))
	suite.assert_true(actor.configure_launch_definition(definition.runtime_projection(), {"run_id": "run-wall", "hostile_source_id": "hostile-wall", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "wall fixture binds authored Ruin Boss")
	return actor


func _context(frame: int, actor: Node2D, player: Node2D) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": actor.global_position.x, "y": actor.global_position.y}, "target_position": {"x": player.global_position.x, "y": player.global_position.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}


func _damage(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-wall", "target_id": "pending_wall", "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
