extends "res://tests/integration/combat/void_auxiliary_lifecycle_test.gd"

const TimeBoss := preload("res://data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn")
const TimeRoom := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_time_sovereign.tscn")


func _run() -> void:
	suite = Suite.new()
	var selected := OS.get_environment("PLANEWALKER_TIME_AUX_CASE")
	if selected in ["", "slash"]:
		await _slash_mark()
	if selected in ["", "bolt"]:
		await _bolt_impact()
	if selected in ["", "freeze"]:
		await _freeze_regeneration()
	if selected in ["", "collapse"]:
		await _collapse_energy()
	if selected in ["", "blink"]:
		await _blink_facing()
	suite.finish(get_tree())


func _open_case(phase_two: bool, position: Vector2) -> Dictionary:
	var room := TimeRoom.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	actor.global_position = Vector2(320, 180)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual Time auxiliary Player owns complete launch loadout")
	player.global_position = position
	player.health.defense = 0.0
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual Time auxiliary binds native frame authorities")
	suite.assert_true(player.configure_hostile_frame_participant(bridge), "actual Time auxiliary Player owns accepted native frame")
	var result := {"actor": actor, "player": player, "room": room, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "frame": 0, "start_hp": float(player.health.current_hp)}
	if phase_two:
		suite.assert_equal(actor.get_node("Hurtbox").receive_hit(_damage(player, 21, 850.0)), 850.0, "authentic native hit enters Time phase two")
		player.global_position = Vector2(900, 500)
		for frame: int in range(1, 61):
			suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "actual Time phase transition frame commits")
			result.frame = frame
		player.global_position = position
	return result


func _boss(room: Node2D) -> Node2D:
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_time_sovereign":
			suite.assert_true(room.bind_room({"id": "time-auxiliary-fixture", "template_id": template.id, "room_type": "boss"}, template, {"floor_id": "floor_time_rift", "palette_id": "palette_time_rift", "environment_rule_id": "rule_temporal_distortion", "room_seed": 42}).ok, "native Time auxiliary fixture binds actual production room artwork")
	var actor := TimeBoss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	room.get_parent().add_child(actor)
	actor.global_position = Vector2(320, 180)
	var parser := Definition.new()
	parser.configure(Content.boss("time_sovereign"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-void-arena", "hostile_source_id": "time-aux-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "actual Time auxiliary Boss uses canonical definition")
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_time_sovereign":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "actual Time auxiliary owns canonical room bounds")
	return actor


func _player_frames(context: Dictionary, through: int) -> void:
	for frame: int in range(int(context.frame) + 1, through + 1):
		var accepted: bool = context.player.advance_action_frame({"aim": Vector2.RIGHT})
		suite.assert_true(accepted, "actual Player accepts Time auxiliary frame %d" % frame)
		if not accepted:
			return
		context.frame = frame
		await get_tree().physics_frame


func _slash_mark() -> void:
	var context := _open_case(false, Vector2(350, 180))
	_request(context, "traitor_temporal_slash")
	await _player_frames(context, 34)
	suite.assert_true(context.actor.native_time_auxiliary_snapshot().get("marks", []).is_empty(), "complete35frame Slash warning installs no mark")
	var player_before: Dictionary = context.player.weapon_replay_snapshot()
	var owner_before: Dictionary = context.actor.launch_runtime_snapshot()
	var effects_before: Dictionary = context.effects.snapshot()
	context.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not context.player.advance_action_frame(), "late actual World refusal rejects native Slash mark")
	suite.assert_equal(context.player.weapon_replay_snapshot(), player_before, "actual Slash refusal restores exact Player state")
	suite.assert_equal(context.actor.launch_runtime_snapshot(), owner_before, "actual Slash refusal restores exact mark receipt")
	suite.assert_equal(context.effects.snapshot(), effects_before, "actual Slash refusal restores exact effect claims")
	context.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	await _player_frames(context, 35)
	var state: Dictionary = context.actor.native_time_auxiliary_snapshot()
	suite.assert_equal(state.get("marks", []).size(), 1, "real accepted Slash installs one finite mark")
	suite.assert_equal(context.player.health.current_hp, context.start_hp - 24.0, "first Slash loses approved24Health without amplifying itself")
	if not state.get("marks", []).is_empty():
		suite.assert_equal(state.marks[0].through_frame, 275, "actual mark lasts240accepted frames")
		await _capture_time_zones(context, "slash-mark")
		await _cold_time_owner(context)
	context.player.global_position = Vector2(900, 500)
	await _player_frames(context, 92)
	context.player.global_position = context.actor.global_position + Vector2(80, 0)
	_request(context, "traitor_chrono_bolt")
	context.player.global_position = Vector2(900, 500)
	await _player_frames(context, 180)
	context.player.global_position = Vector2(350, 180)
	context.actor.global_position = Vector2(320, 180)
	_request(context, "traitor_temporal_slash")
	await _player_frames(context, 215)
	suite.assert_true(is_equal_approx(context.player.health.current_hp, context.start_hp - 51.6), "subsequent actual Time damage consumes1.15mark before defense")
	suite.assert_equal(context.actor.native_time_auxiliary_snapshot().get("marks", []).size(), 1, "repeated actual Slash refreshes without stacking")
	context.player.health.acquire_invulnerability_source(&"mark-expiry")
	context.player.global_position = Vector2(900, 500)
	await _player_frames(context, 455)
	suite.assert_true(context.actor.native_time_auxiliary_snapshot().get("marks", []).is_empty(), "actual mark expires at exclusive finite boundary")
	suite.assert_equal(context.actor.native_time_damage_multiplier(str(context.bridge._player_target_id())), 1.0, "expired actual mark restores ordinary Time damage")
	context.player.configure_hostile_frame_participant(null)
	await _close_case(context)
	context = _open_case(false, Vector2(350, 180))
	_request(context, "traitor_temporal_slash")
	await _player_frames(context, 35)
	suite.assert_equal(context.actor.native_time_auxiliary_snapshot().marks.size(), 1, "death cleanup fixture owns an actual accepted mark")
	suite.assert_true(context.actor.get_node("Hurtbox").receive_hit(_damage(context.player, 22, 3000.0)) > 0.0 and context.actor.health.current_hp == 0.0, "actual native Boss death consumes original Health once")
	context.player.global_position = Vector2(900, 500)
	await _player_frames(context, 36)
	suite.assert_true(context.actor.native_time_auxiliary_snapshot().marks.is_empty(), "actual native death retires owned mark")
	var time_damage: RefCounted = _damage(context.player, 23, 1.0)
	time_damage.damage_type = Damage.DamageType.TIME
	suite.assert_equal(context.player.get_damage_taken_multiplier_for(time_damage), 1.0, "actual native death clears Player time damage modifier")
	suite.assert_true(not context.player.get_node("NativeTemporalMark").visible, "actual native death hides owned mark indicator")
	context.player.configure_hostile_frame_participant(null)
	await _close_case(context)
	context = _open_case(false, Vector2(350, 180))
	context.player.health.acquire_invulnerability_source(&"blocked-slash")
	_request(context, "traitor_temporal_slash")
	await _player_frames(context, 35)
	suite.assert_true(context.actor.native_time_auxiliary_snapshot().get("marks", []).is_empty(), "prevented real Slash cannot install mark")
	context.player.configure_hostile_frame_participant(null)
	await _close_case(context)


func _bolt_impact() -> void:
	var context := _open_case(false, Vector2(400, 180))
	_request(context, "traitor_chrono_bolt")
	await _player_frames(context, 32)
	suite.assert_equal(context.effects.native_payload_nodes().size(), 1, "authored Bolt warning creates one visible physical projectile")
	var pool := {}
	for _offset: int in range(90):
		await _player_frames(context, int(context.frame) + 1)
		var zones: Array = context.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "traitor_chrono_bolt.impact")
		if not zones.is_empty():
			pool = zones[0]
			break
	suite.assert_true(not pool.is_empty(), "real physical Bolt impact creates semantic slow zone")
	if not pool.is_empty():
		suite.assert_equal(pool.geometry.radius, 16.0, "actual Bolt impact uses authored r16")
		suite.assert_equal(pool.lifetime_frames, 180, "actual Bolt impact has finite180frame lifetime")
		suite.assert_equal(pool.damage, 0.0, "actual Bolt slow adds no unapproved damage")
		var forged := {"run_id": "run-void-arena", "hostile_source_id": str(context.actor.hostile_source_id), "attack_generation": 1000, "hit_index": 0, "runtime_frame": int(context.frame) + 1, "position": pool.geometry.origin.duplicate(true), "parameters": {"radius": 16.0, "lifetime_frames": 180, "damage": 0.0, "tick_frames": 60, "slow_multiplier": 0.7}}
		var before: Dictionary = context.effects.semantic_snapshot()
		var retired: Array[String] = []
		var refused: Dictionary = context.effects.get("_semantics").prepare_effects([], {"run_id": "run-void-arena", "runtime_frame": int(context.frame) + 1, "threat_registry": context.registry, "actors": {str(context.actor.hostile_source_id): context.actor}, "targets": {str(context.bridge._player_target_id()): context.player}}, 0, retired, 0, [forged])
		suite.assert_true(not refused.ok and context.effects.semantic_snapshot() == before, "unsealed synthetic contact cannot create native Bolt impact")
		context.player.global_position = Vector2(float(pool.geometry.origin.x), float(pool.geometry.origin.y))
		await _player_frames(context, int(context.frame) + 1)
		suite.assert_equal(context.player._floor_rule_movement_multiplier(), 0.7, "actual Player movement consumes impact slow")
		context.player.global_position += Vector2(0, 48)
		await _player_frames(context, int(context.frame) + 1)
		suite.assert_equal(context.player._floor_rule_movement_multiplier(), 1.0, "leaving actual Bolt slow restores native movement immediately")
		await _capture_time_zones(context, "bolt-impact")
		await _cold_time_owner(context)
		context.player.health.acquire_invulnerability_source(&"bolt-expiry")
		context.player.global_position = Vector2(900, 500)
		await _player_frames(context, int(pool.expires_frame) + 1)
		suite.assert_true(not context.effects.semantic_snapshot().zones.any(func(row: Dictionary): return row.id == pool.id), "actual Bolt impact retires after180accepted frames")
		suite.assert_equal(context.player._floor_rule_movement_multiplier(), 1.0, "Bolt retirement removes native slow")
	context.player.configure_hostile_frame_participant(null)
	await _close_case(context)


func _freeze_regeneration() -> void:
	var context := _open_case(true, Vector2(350, 180))
	context.player.health.acquire_invulnerability_source(&"freeze-regeneration")
	var ownership: Dictionary = context.player.loadout_runtime.snapshot()
	_request(context, "traitor_time_freeze")
	await _player_frames(context, 119)
	suite.assert_equal(context.player.time_manager.hostile_energy_regen_multiplier(), 1.0, "Freeze warning retains ordinary regeneration")
	var before: Dictionary = context.player.weapon_replay_snapshot()
	var modifiers: Dictionary = context.player.floor_rule_effect_snapshot()
	context.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not context.player.advance_action_frame(), "late actual World refusal rejects Freeze modifier activation")
	suite.assert_equal(context.player.weapon_replay_snapshot(), before, "Freeze refusal restores exact actual Player frame state")
	suite.assert_equal(context.player.floor_rule_effect_snapshot(), modifiers, "Freeze refusal restores exact Player modifiers")
	suite.assert_equal(context.player.time_manager.hostile_energy_regen_multiplier(), 1.0, "Freeze refusal restores actual regeneration multiplier")
	context.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	await _player_frames(context, 120)
	suite.assert_equal(context.player.time_manager.hostile_energy_regen_multiplier(), 0.5, "active native Freeze applies authored regeneration floor")
	suite.assert_equal(context.player._floor_rule_movement_multiplier(), 0.4, "active native Freeze preserves authored movement slow")
	context.player.time_manager.energy = 50.0
	var expected: float = 50.0 + float(context.player.time_manager.energy_regen) * 0.5
	await _player_frames(context, 180)
	suite.assert_true(is_equal_approx(context.player.time_manager.energy, expected), "real fixed frame regeneration grants half of normalpersecond")
	suite.assert_equal(context.player.loadout_runtime.snapshot(), ownership, "native Freeze retains all paid time inputs")
	await _capture_time_zones(context, "freeze")
	await _cold_time_owner(context)
	context.player.global_position = Vector2(500, 180)
	await _player_frames(context, 182)
	suite.assert_equal(context.player.time_manager.hostile_energy_regen_multiplier(), 1.0, "leaving Freeze clears owned regeneration immediately")
	context.player.global_position = Vector2(350, 180)
	await _player_frames(context, 183)
	suite.assert_true(context.player.try_action(&"time_slot_1"), "normal Stop command remains available inside Freeze")
	await _player_frames(context, 184)
	context.player.configure_hostile_frame_participant(null)
	suite.assert_true(context.effects.dispose_native_effects(), "disposing native Freeze completes owned effect cleanup")
	suite.assert_equal(context.player.time_manager.hostile_energy_regen_multiplier(), 1.0, "disposing native Freeze clears regeneration modifier")
	await _close_case(context)


func _collapse_energy() -> void:
	for energy: float in [100.0, 5.0, 0.5]:
		var context := _open_case(false, Vector2(350, 180))
		context.player.configure_hostile_frame_participant(null)
		var runtime: RefCounted = context.actor.get("_launch_runtime")
		for frame: int in range(1, 14401):
			var observation := {"runtime_frame": frame, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 350.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": str(context.bridge._player_target_id())}
			var advanced: Dictionary = runtime.advance_frame(frame, observation, false)
			if not advanced.ok:
				suite.assert_true(false, "authored Collapse accepted clock prepares enrage: %s" % str(advanced))
				break
		context.effects.dispose_native_effects()
		context.effects = Effects.new()
		context.effects.configure("run-void-arena", 14400)
		context.effects.configure_native_payloads(context.root)
		context.player.set("_runtime_frame", 14400)
		context.bridge = Bridge.new()
		suite.assert_true(context.bridge.configure(context.player, context.registry, [context.actor], context.effects), "actual Collapse frame authorities bind accepted enrage clock")
		context.frame = 14400
		_request(context, "traitor_enrage_collapse")
		_frames(context, 14474)
		context.player.time_manager.energy = energy
		var before: Dictionary = context.player.time_manager.resource_state(&"time_energy")
		var hp: Dictionary = context.player.health.transaction_snapshot()
		var owner: Dictionary = context.actor.launch_runtime_snapshot()
		var observations: Array = []
		context.player.time_manager.energy_changed.connect(func(current: float, _maximum: float): observations.append(current))
		var ticket: Dictionary = context.bridge.begin_frame(14475)
		suite.assert_true(context.bridge.prepare_frame(ticket), "actual native Collapse accepted hit prepares energy receipt")
		suite.assert_true(context.bridge.rollback_frame(ticket) and context.player.health.restore_transaction_snapshot(hp), "refused native Collapse compensates actual HP and energy")
		suite.assert_equal(context.player.time_manager.resource_state(&"time_energy"), before, "refused Collapse restores exact resource revision")
		suite.assert_equal(context.actor.launch_runtime_snapshot(), owner, "refused Collapse restores accepted hit receipt")
		suite.assert_true(observations.is_empty(), "refused Collapse publishes no early resource signal")
		_frames(context, 14475)
		suite.assert_equal(context.player.time_manager.energy, maxf(1.0, energy - 10.0) if energy >= 1.0 else energy, "accepted Collapse drains at most10and preserves positive energy")
		await _close_case(context)


func _blink_facing() -> void:
	for blocked: bool in [false, true]:
		var context := _open_case(false, Vector2(350, 180))
		var blocker: StaticBody2D
		if blocked:
			blocker = StaticBody2D.new()
			blocker.collision_layer = 1
			blocker.collision_mask = 4
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(32, 32)
			shape.shape = rectangle
			blocker.add_child(shape)
			add_child(blocker)
			blocker.global_position = Vector2(350, 132)
		var started: Dictionary = context.actor.get("_launch_runtime").request_action("traitor_blink", {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 350.0, "y": 180.0}, "facing_direction": {"x": 0.0, "y": 1.0}, "target_id": str(context.bridge._player_target_id())})
		suite.assert_true(started.ok, "actual Blink locks independent Player facing")
		if started.ok:
			suite.assert_equal(started.threat_facts[0].origin, {"x": 350.0, "y": 132.0}, "Blink warning marks48px behind locked Player facing")
			for fact: Dictionary in started.threat_facts:
				context.registry.register_fact(Actions.native_threat_fact(fact))
		await get_tree().physics_frame
		await _player_frames(context, 34)
		suite.assert_equal(context.actor.global_position, Vector2(320, 180), "Blink complete warning preserves original body position")
		await _player_frames(context, 35)
		suite.assert_equal(context.actor.global_position, Vector2(320, 180) if blocked else Vector2(350, 132), "Blink arrival respects physical obstacle and body-safe landing")
		suite.assert_equal(context.player.health.current_hp, context.start_hp, "actual Blink cannot deal an instant boosted hit")
		context.player.global_position = Vector2(900, 500)
		await _player_frames(context, 85)
		context.player.global_position = Vector2(350, 180)
		context.actor.global_position = Vector2(320, 180) if blocked else Vector2(350, 132)
		_request(context, "traitor_temporal_slash")
		await _player_frames(context, 119)
		suite.assert_equal(context.player.health.current_hp, context.start_hp, "post Blink Slash preserves all35warning frames")
		await _player_frames(context, 120)
		suite.assert_equal(context.player.health.current_hp, context.start_hp - 24.0, "post Blink Slash deals normal authored damage after complete warning")
		if is_instance_valid(blocker):
			blocker.queue_free()
		context.player.configure_hostile_frame_participant(null)
		await _close_case(context)


func _cold_time_owner(context: Dictionary) -> void:
	var cold: Dictionary = context.actor.native_cold_snapshot(func(_source: Node): return {})
	var aggregate := {"actor": cold, "effects": context.effects.snapshot(), "modifiers": context.player.floor_rule_effect_snapshot(), "player": context.player.full_player_replay_snapshot(), "registry": context.registry.snapshot()}
	var encoded := Replay.encode_replay_json(aggregate)
	var catalog := ContentRegistry.new()
	catalog.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := ContentSnapshot.snapshot(catalog)
	var path := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("time-auxiliary")
	if OS.get_environment("PLANEWALKER_TEST_DATA_DIR").is_empty():
		path = ProjectSettings.globalize_path("res://build/test-data/time-auxiliary")
	var storage := Save.new()
	storage.configure(path, "test-time-auxiliary", binding)
	suite.assert_true(encoded.ok and storage.save_profile("time_auxiliary", "base", {"codec": encoded.json}).ok, "physical Save retains regular Time auxiliary aggregate")
	var recovered: Variant = storage.inspect_profile("time_auxiliary", "base")
	suite.assert_true(recovered.ok, "physical Save recovers regular Time auxiliary aggregate")
	if not recovered.ok:
		return
	var decoded: Dictionary = Replay.decode_replay_json(recovered.payload.payload.codec).replay
	suite.assert_equal(decoded, aggregate, "physical Save and typed Replay preserve exact Time auxiliary state")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := TimeRoom.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var twin := _boss(room)
	suite.assert_true(twin.restore_native_cold_snapshot(decoded.actor, func(_binding: Dictionary): return null), "fresh native Time Boss restores auxiliary receipt")
	suite.assert_equal(twin.native_time_auxiliary_snapshot(), context.actor.native_time_auxiliary_snapshot(), "fresh Boss reconstructs exact finite marks")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(player)
	player.configure_run(&"run-void-arena")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and player.restore_full_player_replay_snapshot(decoded.player), "fresh native Player restores exact paid loadout and accepted frame")
	var root := Node2D.new()
	world.add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	effects.bind_native_targets({str(twin.hostile_source_id): twin}, {str(context.bridge._player_target_id()): player})
	suite.assert_true(effects.restore_launch_transaction_snapshot(decoded.effects), "fresh native Effects restore Bolt and Freeze projections")
	suite.assert_equal(player.floor_rule_effect_snapshot(), decoded.modifiers, "fresh Effects restore exact regeneration and movement modifiers")
	var registry := Registry.new()
	for fact: Dictionary in decoded.registry:
		suite.assert_true(registry.register_fact(fact), "fresh native threat registry restores retained warning")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [twin], effects) and player.configure_hostile_frame_participant(bridge), "fresh native frame authority binds reconstructed auxiliary owners")
	await get_tree().physics_frame
	await _player_frames(context, int(context.frame) + 1)
	suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "fresh auxiliary branch accepts same next Player frame")
	suite.assert_equal(twin.native_cold_snapshot(func(_source: Node): return {}), context.actor.native_cold_snapshot(func(_source: Node): return {}), "cold auxiliary Boss continuation matches uninterrupted accepted frame")
	suite.assert_equal(effects.snapshot(), context.effects.snapshot(), "cold auxiliary Effects continuation matches uninterrupted accepted frame")
	suite.assert_equal(player.full_player_replay_snapshot(), context.player.full_player_replay_snapshot(), "cold auxiliary Player continuation matches uninterrupted accepted frame")
	player.configure_hostile_frame_participant(null)
	effects.dispose_native_effects()
	world.queue_free()
	await get_tree().process_frame


func _capture_time_zones(context: Dictionary, name: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.world_2d = context.actor.get_world_2d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var scale_value := minf(float(resolution.x) / 640.0, float(resolution.y) / 360.0)
		var inset := (Vector2(resolution) - Vector2(640, 360) * scale_value) * 0.5
		viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scale_value, 0.0, inset)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		var colors := {}
		var centers: Array[Vector2] = []
		for zone: Node2D in context.effects.native_semantic_nodes():
			centers.append(zone.global_position)
		if name == "slash-mark":
			var indicator := context.player.get_node("NativeTemporalMark") as Sprite2D
			suite.assert_true(indicator.visible and indicator.texture != null, "accepted native mark owns visible production raster indicator")
			centers.append(indicator.global_position)
		for position: Vector2 in centers:
			var center := Vector2i(position * scale_value + inset)
			for y: int in range(center.y - 12, center.y + 12):
				for x: int in range(center.x - 12, center.x + 12):
					colors[pixels.get_pixel(x, y).to_rgba32()] = true
		suite.assert_true(colors.size() >= 3, "native Time auxiliary zone raster is nonblank at supported resolution")
		var path := "res://build/visual-evidence/time-auxiliary/%s-%dx%d.png" % [name, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "native Time auxiliary raster is retained")
		viewport.queue_free()
		await get_tree().process_frame
