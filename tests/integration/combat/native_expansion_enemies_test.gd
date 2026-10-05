extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"

const Expansion := preload("res://scripts/enemies/expansion/expansion_enemy_definition.gd")
const ExpansionScene := preload("res://scenes/enemies/expansion_hostile_actor.tscn")
const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _run() -> void:
	suite = Suite.new()
	for id: String in Expansion.IDS:
		await _actual_enemy(id)
	await _actual_enemy("cinder_drake", 1)
	suite.finish(get_tree())


func _fixture(id: String, _count: int = 1, _affixes: Array[String] = []) -> Dictionary:
	var room := load("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn").instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template := {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == "room_combat_open_field":
			template = row
	for floor: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json")):
		if int(floor.order) == Expansion.floor_index(id):
			suite.assert_true(room.bind_room({"id": "expansion-native-" + id, "template_id": template.id, "room_type": "combat"}, template, {"floor_id": floor.id, "palette_id": floor.palette_id, "environment_rule_id": floor.environment_rule_id, "room_seed": 42}).ok, "Expansion native fixture binds its actual production floor artwork")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-expansion-native")
	player.global_position = Vector2(400, 180)
	var actor := ExpansionScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var parser := Expansion.new()
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/temporal_frontiers/content/enemies.json")):
		if row.id == id:
			suite.assert_true(parser.configure(row).ok, "actual Expansion source parses")
	suite.assert_true(actor.configure_expansion_visual("res://data/content_packs/temporal_frontiers/assets/" + id + ".png"), "actual Expansion authored sprite loads")
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-expansion-native", "hostile_source_id": "expansion-owner", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}).ok and actor.configure_launch_room_motion(room, template).ok, "actual Expansion native Actor binds shared production room")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-expansion-native", 0) and effects.configure_native_payloads(root) and effects.configure_native_summon_room(room, template), "Expansion uses real payload and room authorities")
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual Expansion Actor participates in native frame boundary")
	await get_tree().physics_frame
	return {"room": room, "actors": [actor], "player": player, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "frame": 0, "definition": parser.snapshot()}


func _actual_enemy(id: String, action_index: int = 0) -> void:
	var f := await _fixture(id)
	var actor: Node2D = f.actors[0]
	var action: Dictionary = f.definition.actions[action_index]
	f.player.global_position = actor.global_position + Vector2(48, 0)
	if id in ["parallax_guard", "prism_seer"] or action.handler_id == "projectile_volley":
		f.player.global_position = actor.global_position + Vector2(100, 0)
	suite.assert_true(_start(f, action.id), "real Expansion Actor commits authored attack " + id)
	if id == "parallax_guard":
		f.player.global_position = actor.global_position + Vector2(90, -29)
	elif id == "prism_seer":
		f.player.global_position = actor.global_position + Vector2(90, -33)
	actor.apply_time_stop_source(&"expansion_native_stop", 3.0 / 60.0)
	for _frame: int in range(3):
		suite.assert_true(_step(f), "native Expansion Stop preserves accepted shared frame")
	var snapshot: Dictionary = actor.launch_runtime_snapshot()
	suite.assert_equal(snapshot.runtime.action.paused_frames, 3, "native Expansion warning is extended exactly by Stop")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var twin := await _fixture(id)
	var typed: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(cold).json).replay
	suite.assert_true(twin.actors[0].restore_native_cold_snapshot(typed, func(_binding: Dictionary): return null), "typed native Expansion cold Actor restores exact authored warning")
	var forged := typed.duplicate(true)
	forged.actor.runtime.mechanism_state.last_action_id = "foreign.attack"
	suite.assert_true(not twin.actors[0].can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "native Expansion cold Actor refuses foreign species action")
	await _dispose(twin)
	var hp_before: float = f.player.health.current_hp
	var accepted := true
	for _frame: int in range(int(action.warning_frames) + int(action.active_frames) + 90):
		accepted = _step(f) and accepted
		if action_index == 1 and int(f.frame) <= int(action.warning_frames) + 3:
			var expected_lanes := 3 if int(f.frame) == int(action.warning_frames) + 3 else 0
			suite.assert_equal(f.effects.payload_snapshot().projectiles.size(), expected_lanes, "Cinder fan creates all three native projectiles only after its complete paused warning")
			if expected_lanes == 3:
				suite.assert_equal(f.effects.native_payload_nodes().size(), 3, "Cinder fan projects three real physical projectile bodies")
		if action_index == 0 and _frame == int(action.warning_frames) + 8:
			await _capture_expansion(f, id)
		if not accepted:
			break
	suite.assert_true(accepted, "all real Expansion warning/payload frames accept " + id)
	suite.assert_true(f.player.health.current_hp < hp_before, "authentic Expansion physical payload accepts Player HP loss " + action.id)
	actor.apply_time_rift(&"expansion_native_rift", 0.4)
	suite.assert_equal(float(actor.get("_launch_runtime").control_modifiers().movement_multiplier), 0.4, "real Expansion Actor accepts Rift movement control")
	actor.clear_time_rift(&"expansion_native_rift")
	suite.assert_equal(float(actor.get("_launch_runtime").control_modifiers().movement_multiplier), 1.0, "real Expansion Actor clears source-owned Rift")
	var info := Damage.from_plan({"run_id": "run-expansion-native", "target_id": "expansion-owner", "hostile_source_id": "player:1", "attack_generation": 900, "action_token": 900, "amount": 100000.0, "damage_type": Damage.DamageType.PHYSICAL, "source": f.player, "attacker": f.player, "tags": ["weapon:sword"], "can_crit": false})
	suite.assert_true(actor.health.take_damage(info) > 0.0 and actor.health.dead and actor.launch_runtime_snapshot().runtime.terminal, "actual Expansion body accepts authenticated terminal weapon damage " + id)
	await _dispose(f)


func _capture_expansion(f: Dictionary, id: String) -> void:
	var directory := OS.get_environment("PLANEWALKER_VISUAL_EVIDENCE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.world_2d = f.actors[0].get_world_2d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var scale_value := minf(float(resolution.x) / 640.0, float(resolution.y) / 360.0)
		var inset := (Vector2(resolution) - Vector2(640, 360) * scale_value) * 0.5
		viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scale_value, 0.0, inset)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		var center := Vector2i(f.actors[0].global_position * scale_value + inset)
		var colors := {}
		var extent := ceili(18.0 * scale_value)
		for y: int in range(center.y - extent, center.y + extent):
			for x: int in range(center.x - extent, center.x + extent):
				colors[pixels.get_pixel(x, y).to_rgba32()] = true
		suite.assert_true(colors.size() >= 4, "actual Expansion sprite raster is nonblank at supported resolution")
		suite.assert_equal(pixels.save_png(directory.path_join("%s-%dx%d.png" % [id, resolution.x, resolution.y])), OK, "actual Expansion visual evidence saves")
		viewport.queue_free()
		await get_tree().process_frame
