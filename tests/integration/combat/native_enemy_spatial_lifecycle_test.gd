extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"

const Spatial := preload("res://scripts/enemies/launch/enemy_spatial_runtime.gd")
const Semantic := preload("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")


func _run() -> void:
	suite = Suite.new()
	await _wall_interaction()
	await _wall_interaction("void_web_weaver", "void_web_weaver.web_cage")
	await _link_interaction()
	await _portal_interaction(false)
	await _portal_interaction(true)
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		await _weapon_construct(weapon)
		await _weapon_construct(weapon, true)
	suite.finish(get_tree())


func _spatial_fixture(id: String, action_id: String, weapon: String = "sword") -> Dictionary:
	var f := await _fixture(id, 3)
	f.actors[1].global_position = Vector2(240, 130)
	f.actors[2].global_position = Vector2(400, 130)
	f.player.global_position = Vector2(430, 180)
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": f.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and f.player.configure_hostile_frame_participant(f.bridge), "actual spatial Player binds normal weapon and frame transaction")
	for actor: Node2D in [f.actors[1], f.actors[2]]:
		actor.get("_launch_runtime").add_control_source("spatial-fixture", "stop", 1200, 1.0)
	var owner: Node2D = f.actors[0]
	var started: Dictionary = owner.get("_launch_runtime").request_action(action_id, {"runtime_frame": 0, "source_position": _point(owner.global_position), "target_position": _point(f.player.global_position), "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
	suite.assert_true(started.ok, "actual spatial owner begins authored warning " + action_id)
	for fact: Dictionary in started.get("threat_facts", []):
		f.registry.register_fact(Actions.native_threat_fact(fact))
	owner.project_runtime_snapshot(owner.launch_runtime_snapshot())
	var warning := int(Content.action(action_id).warning_frames)
	await _spatial_frames(f, warning)
	suite.assert_true(not f.effects.semantic_snapshot().spatial.rows.is_empty(), "authored active frame reserves native spatial work")
	owner.get("_launch_runtime").add_control_source("spatial-fixture", "stop", 1200, 1.0)
	await _spatial_frames(f, warning * 2)
	suite.assert_true(Spatial.active_count(f.effects.semantic_snapshot().spatial) > 0, "full collision warning admits active physical spatial object")
	await _capture_spatial(f, action_id)
	return f


func _spatial_frames(f: Dictionary, through: int) -> bool:
	for frame: int in range(int(f.frame) + 1, through + 1):
		var accepted: bool = f.player.advance_action_frame({"aim": Vector2.RIGHT})
		suite.assert_true(accepted, "actual spatial accepted Player frame %d" % frame)
		if not accepted:
			return false
		f.frame = frame
		await get_tree().physics_frame
	return true


func _damage(player: Node2D, generation: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": player.current_run_id(), "target_id": &"pending_target", "hostile_source_id": &"player:fixture", "attack_generation": generation, "hit_index": 0, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "source": player, "attacker": player, "tags": []})


func _wall_interaction(id: String = "bramble_mage", action_id: String = "bramble_mage.bramble_cage") -> void:
	var f := await _spatial_fixture(id, action_id)
	var hp := float(Content.action(action_id).parameters.hit_points)
	var nodes: Array = f.effects.native_spatial_nodes()
	suite.assert_equal(nodes.size(), 3, "actual Bramble cage creates three independently destructible walls")
	if nodes.size() != 3:
		await _dispose(f)
		return
	var wall: Node2D = nodes[0]
	await _cold_spatial(f, "wall")
	f.player.global_position = wall.global_position + Vector2(0, 28)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.test_move(f.player.global_transform, Vector2(0, -40)), "active wall physically blocks actual Player displacement")
	f.player.global_position = Vector2(430, 180)
	suite.assert_true(not f.player.test_move(f.player.global_transform, Vector2(0, -60)), "three segment cage preserves an open passage wider than32px")
	var before: Dictionary = f.effects.snapshot()
	var hit := _damage(f.player, 90, 12.0)
	suite.assert_equal(wall.get_node("Hurtbox").receive_hit(hit), 12.0, "authenticated construct Hurtbox settles wall HP")
	suite.assert_equal(wall.get_node("Hurtbox").receive_hit(hit), 0.0, "same actual hit cannot spend wall HP twice")
	suite.assert_true(f.effects.restore_launch_transaction_snapshot(before), "wall HP and duplicate claims reconstruct from exact snapshot")
	suite.assert_equal(wall.get_node("Hurtbox").receive_hit(_damage(f.player, 91, 100.0)), hp, "lethal wall hit is capped at authored remaining HP")
	suite.assert_equal(wall.collision_layer, 0, "broken wall immediately retires physical collision")
	await _spatial_frames(f, int(f.frame) + 1)
	suite.assert_equal(f.effects.native_spatial_nodes().size(), 2, "accepted frame prunes broken wall native lease")
	await _dispose(f)


func _link_interaction() -> void:
	var f := await _spatial_fixture("void_web_weaver", "void_web_weaver.void_web")
	var rows: Array = f.effects.semantic_snapshot().spatial.rows
	await _cold_spatial(f, "link")
	suite.assert_equal(rows[0].recipients, ["summon-owner-1", "summon-owner-2"], "Web link chooses deterministic two legal ordinary or elite allies")
	for actor: Node2D in [f.actors[1], f.actors[2]]:
		suite.assert_close(actor.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0), 1.15, "live link grants authored strongest-only attack buff")
		suite.assert_close(actor.get("_launch_runtime").control_modifiers().movement_multiplier, 1.1, "live link grants authored strongest-only speed buff")
	f.actors[2].global_position = Vector2(420, 140)
	await _spatial_frames(f, int(f.frame) + 1)
	var link: Node2D = f.effects.native_spatial_nodes()[0]
	suite.assert_close(link.global_position.x, 330.0, "accepted link raster and Hurtbox follow recipients")
	suite.assert_equal(link.get_node("Hurtbox").receive_hit(_damage(f.player, 95, 100.0)), 15.0, "physical link target has authored15HP")
	for actor: Node2D in [f.actors[1], f.actors[2]]:
		suite.assert_close(actor.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0), 1.0, "breaking link removes attack buff immediately")
		suite.assert_close(actor.get("_launch_runtime").control_modifiers().movement_multiplier, 1.0, "breaking link removes speed buff immediately")
	await _dispose(f)


func _portal_interaction(enemy_only: bool) -> void:
	var f := await _spatial_fixture("plane_ripper", "plane_ripper.one_way_plane" if enemy_only else "plane_ripper.plane_rip")
	var row: Dictionary = f.effects.semantic_snapshot().spatial.rows[0]
	await _cold_spatial(f, "portal-enemy" if enemy_only else "portal-both")
	var entry := Vector2(float(row.geometry[0].origin.x), float(row.geometry[0].origin.y))
	var exit := Vector2(float(row.geometry[1].origin.x), float(row.geometry[1].origin.y))
	f.player.global_position = entry
	var before: Dictionary = f.effects.snapshot()
	var owner_before: Dictionary = f.actors[0].launch_runtime_snapshot()
	var player_before: Dictionary = f.player.weapon_replay_snapshot()
	f.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(f.player), "late native World refusal rejects actual portal frame")
	suite.assert_equal(f.effects.snapshot(), before, "portal refusal restores exact transit claims and native work")
	suite.assert_equal(f.actors[0].launch_runtime_snapshot(), owner_before, "portal refusal restores exact native owner")
	suite.assert_equal(f.player.weapon_replay_snapshot(), player_before, "portal refusal restores exact Player transaction")
	suite.assert_equal(f.player.global_position, entry, "portal refusal compensates actual physical Player position")
	f.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	await _spatial_frames(f, int(f.frame) + 1)
	suite.assert_equal(f.player.global_position, entry if enemy_only else exit + entry.direction_to(exit) * 24.0, "accepted portal retry obeys authored team rule")
	if not enemy_only:
		f.player.global_position = exit
		await _spatial_frames(f, int(f.frame) + 1)
		suite.assert_equal(f.player.global_position, exit, "portal transit cooldown blocks same actor before12frames")
		await _spatial_frames(f, int(f.frame) + 10)
		await _spatial_frames(f, int(f.frame) + 1)
		suite.assert_equal(f.player.global_position, entry + exit.direction_to(entry) * 24.0, "portal cooldown expires exactly after12acceptedframes")
	f.player.global_position = Vector2(500, 220)
	var owner: Node2D = f.actors[0]
	owner.get_node("Hurtbox").receive_hit(_damage(f.player, 99, 10000.0))
	await _spatial_frames(f, int(f.frame) + 1)
	suite.assert_equal(f.effects.semantic_snapshot().spatial.rows[0].phase, "COLLAPSE", "portal owner death starts finite45frame collapse")
	suite.assert_equal(f.effects.semantic_snapshot().zones.size(), 2, "portal death creates two authentic warned endpoint explosions")
	suite.assert_true(f.bridge.retire_actor(str(owner.hostile_source_id)), "native Driver retirement removes accepted terminal owner from future frame participants")
	await _spatial_frames(f, int(f.frame) + 45)
	suite.assert_equal(f.effects.native_spatial_nodes().size(), 0, "portal collapse retires native pair after exact45frames")
	await _dispose(f)


func _weapon_construct(weapon: String, wall: bool = false) -> void:
	var f := await _spatial_fixture("bramble_mage" if wall else "void_web_weaver", "bramble_mage.bramble_cage" if wall else "void_web_weaver.void_web", weapon)
	var node: Node2D = f.effects.native_spatial_nodes()[0]
	f.player.global_position = node.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary"), "normal " + weapon + " input attacks actual native link")
	f.frame += 1
	if weapon == "sword":
		f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
	for offset: int in range(120):
		if offset == 40 and weapon != "sword":
			f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		await _spatial_frames(f, int(f.frame) + 1)
	suite.assert_true(f.effects.semantic_snapshot().spatial.rows[0].hp < (30.0 if wall else 15.0), "normal " + weapon + " producer physically settles " + ("wall" if wall else "link") + " HP")
	f.player.cancel_transient_actions()
	await _dispose(f)


func _cold_spatial(f: Dictionary, label: String) -> void:
	var aggregate := {"effects": f.effects.snapshot(), "actors": []}
	for actor: Node2D in f.actors:
		aggregate.actors.append(actor.native_cold_snapshot(func(_source: Node): return {}))
	var encoded := Replay.encode_replay_json(aggregate)
	var catalog := ContentRegistry.new()
	catalog.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := ContentSnapshot.snapshot(catalog)
	var directory := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("native-enemy-spatial")
	if OS.get_environment("PLANEWALKER_TEST_DATA_DIR").is_empty():
		directory = ProjectSettings.globalize_path("res://build/test-data/native-enemy-spatial")
	var storage := Save.new()
	storage.configure(directory, "native-enemy-spatial", binding)
	suite.assert_true(encoded.ok and storage.save_profile("spatial", label, {"codec": encoded.json}).ok, "physical Save writes typed native spatial state " + label)
	var fresh := Save.new()
	fresh.configure(directory, "native-enemy-spatial", binding)
	var recovered: Variant = fresh.inspect_profile("spatial", label)
	suite.assert_true(recovered.ok, "fresh SaveService recovers physical native spatial checkpoint " + label)
	if not recovered.ok:
		return
	var decoded: Dictionary = Replay.decode_replay_json(recovered.payload.payload.codec).replay
	suite.assert_equal(decoded, aggregate, "typed Replay preserves exact physical spatial checkpoint")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := load(f.room.scene_file_path).instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var template := {}
	for record: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if record.id == "room_boss_time_sovereign":
			template = record
	var actors := {}
	for cold: Dictionary in decoded.actors:
		var actor := load("res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % str(cold.definition_id)).instantiate() as Node2D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(actor)
		actor.global_position = Vector2(float(cold.actor.position.x), float(cold.actor.position.y))
		var parser := Enemy.new()
		parser.configure(Content.enemy(str(cold.definition_id)))
		suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), cold.identity).ok and actor.configure_launch_room_motion(room, template).ok and actor.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh actual spatial owner reconstructs cold native actor")
		actors[str(actor.hostile_source_id)] = actor
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(player)
	player.configure_run(&"run-summon-lifecycle")
	player.global_position = f.player.global_position
	var root := Node2D.new()
	world.add_child(root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-summon-lifecycle", 0) and effects.configure_native_payloads(root) and effects.bind_native_targets(actors, {"player:1": player}), "fresh native spatial authority binds exact cold targets")
	suite.assert_true(effects.restore_launch_transaction_snapshot(decoded.effects), "fresh spatial authority restores physical walls links and portals")
	suite.assert_equal(effects.snapshot(), decoded.effects, "fresh spatial domain matches physical Save exactly")
	suite.assert_equal(effects.native_spatial_nodes().size(), f.effects.native_spatial_nodes().size(), "fresh spatial authority recreates exact physical object count")
	var forged: Dictionary = decoded.effects.duplicate(true)
	forged.semantics.spatial.rows[0].parameters.lifetime_frames += 1
	suite.assert_true(not effects.can_restore_launch_transaction_snapshot(forged), "cold spatial authority rejects authored lifetime tampering")
	var next_frame := int(decoded.effects.runtime_frame) + 1
	var wrappers: Array = []
	var tickets: Array = []
	var registry := Registry.new()
	var ids: Array = actors.keys()
	ids.sort()
	for id: String in ids:
		var actor: Node2D = actors[id]
		for fact: Dictionary in actor.native_cold_threat_facts():
			registry.register_fact(fact)
		var prepared: Dictionary = actor.prepare_launch_frame(next_frame, {"runtime_frame": next_frame, "source_position": _point(actor.global_position), "target_position": _point(player.global_position), "facing_direction": _point(actor.global_position.direction_to(player.global_position)), "target_id": "player:1"})
		suite.assert_true(prepared.ok, "fresh native spatial actor continues next accepted cold frame")
		tickets.append({"actor": actor, "ticket": prepared.ticket})
		wrappers.append({"hostile_source_id": id, "batch": prepared.batch})
	var routed: Dictionary = effects.prepare_effects(wrappers, {"run_id": "run-summon-lifecycle", "runtime_frame": next_frame, "threat_registry": registry, "actors": actors, "targets": {"player:1": player}})
	suite.assert_true(routed.ok, "fresh spatial authority accepts next physical cold frame")
	if routed.ok:
		for record: Dictionary in tickets:
			suite.assert_true(record.actor.commit_launch_frame(record.ticket), "fresh cold spatial actor commits")
		suite.assert_true(effects.commit(routed.ticket).ok, "fresh cold spatial effects commit")
		for record: Dictionary in tickets:
			suite.assert_true(record.actor.publish_launch_frame(record.ticket), "fresh cold spatial actor publishes")
		suite.assert_true(effects.publish_effect_observations(routed.ticket), "fresh cold spatial effects publish")
		await _spatial_frames(f, next_frame)
		suite.assert_equal(effects.snapshot(), f.effects.snapshot(), "fresh and continuing spatial worlds settle identically after physical Save")
	var historical: Dictionary = decoded.effects.duplicate(true)
	historical.semantics.schema_version = 1
	historical.semantics.erase("spatial")
	historical.semantics.statuses = historical.semantics.statuses.filter(func(status: Dictionary): return not str(status.id).begins_with("link_"))
	var migrated := Effects.normalize_transaction_snapshot(historical)
	suite.assert_true(not migrated.is_empty() and migrated.semantics.spatial.rows.is_empty(), "exact historical semantic schema1 creates no invented spatial work")
	suite.assert_true(effects.restore_launch_transaction_snapshot(historical), "fresh spatial authority restores exact historical checkpoint")
	suite.assert_equal(effects.native_spatial_nodes().size(), 0, "historical checkpoint retires current native spatial projections")
	suite.assert_true(effects.dispose_native_effects(), "fresh cold authority disposes spatial modifiers and physics leases")
	world.queue_free()
	await get_tree().process_frame


func _capture_spatial(f: Dictionary, label: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.world_2d = f.player.get_world_2d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var scale_value := minf(float(resolution.x) / 640.0, float(resolution.y) / 360.0)
		var inset := (Vector2(resolution) - Vector2(640, 360) * scale_value) * 0.5
		viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scale_value, 0.0, inset)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		for node: Node2D in f.effects.native_spatial_nodes():
			var colors := {}
			var center := Vector2i(node.global_position * scale_value + inset)
			var extent := ceili(12.0 * scale_value)
			for y: int in range(maxi(0, center.y - extent), mini(pixels.get_height(), center.y + extent)):
				for x: int in range(maxi(0, center.x - extent), mini(pixels.get_width(), center.x + extent)):
					colors[pixels.get_pixel(x, y).to_rgba32()] = true
			suite.assert_true(colors.size() >= 3, "actual spatial raster is nonblank at every supported resolution")
		var path := "res://build/visual-evidence/enemy-spatial/%s-%dx%d.png" % [label, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "actual spatial raster evidence retained")
		viewport.queue_free()
		await get_tree().process_frame
