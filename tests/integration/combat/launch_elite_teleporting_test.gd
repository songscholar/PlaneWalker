extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Player := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var room := _room()
	var actor := _actor(room)
	for frame: int in range(1, 480):
		_tick(actor, frame)
	suite.assert_true(actor.launch_affix_runtime_snapshot().get("teleporting", {}).get("reservations", []).is_empty(), "native relocation cannot reserve before its complete480-frame interval")
	actor.cancel_active_attack()
	suite.assert_true(actor.get("_launch_runtime").request_action("shattered_sentinel.shield_sweep", _context(actor, 479)).ok, "authored primary warning commits independently before affix departure")
	var primary: Dictionary = actor.launch_runtime_snapshot().runtime.action.duplicate(true)
	_tick(actor, 480)
	var state: Dictionary = actor.launch_affix_runtime_snapshot()
	suite.assert_true(state.has("teleporting") and not state.get("teleporting", {}).is_empty(), "native Teleporting owns an accepted-frame relocation reservation")
	if not state.has("teleporting"):
		actor.queue_free()
		room.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_equal(state.teleporting.phase, "DEPARTURE", "native interval begins its complete departure warning")
	suite.assert_equal(state.teleporting.remaining_frames, 30, "native departure owns thirty warning frames")
	var origin: Vector2 = actor.global_position
	var landing := Vector2(state.teleporting.reservations.back().landing.x, state.teleporting.reservations.back().landing.y)
	suite.assert_true(origin.distance_to(landing) >= 47.999 and origin.distance_to(landing) <= 80.001, "seeded native landing retains authored forty-eight to eighty pixel displacement")
	for frame: int in range(481, 510):
		_tick(actor, frame)
		suite.assert_equal(actor.global_position, origin, "departure cannot relocate early at frame%d" % frame)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 1, "departure retains its final warned accepted frame")
	var before: Dictionary = actor.launch_transaction_snapshot()
	var prepared: Dictionary = actor.prepare_launch_frame(510, _context(actor, 510))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket) and actor.rollback_launch_frame(prepared.ticket), "native arrival candidate compensates before publication")
	suite.assert_equal(actor.launch_transaction_snapshot(), before, "arrival refusal restores exact transform and reservation")
	_tick(actor, 510)
	suite.assert_equal(actor.global_position, landing, "complete departure relocates actual native body to its reserved safe landing")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 30, "arrival owns its complete thirty-frame recovery")
	for frame: int in range(511, 540):
		_tick(actor, frame)
		suite.assert_equal(actor.global_position, landing, "arrival recovery holds actual native body at frame%d" % frame)
	_tick(actor, 540)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.phase, "IDLE", "native recovery releases only after thirty full arrival frames")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.paused_frames, int(primary.paused_frames) + 60, "departure and arrival each pause primary action for exactly thirty frames")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.commit_frame, primary.commit_frame, "affix relocation cannot recommit the primary warning")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.geometry_generations, primary.geometry_generations, "affix reservation cannot steal primary damage generations")
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {})).json).replay
	var twin := _actor(room)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed cold Teleporting reconstructs exact accepted reservation history")
	suite.assert_equal(twin.native_cold_snapshot(func(_source: Node): return {}), actor.native_cold_snapshot(func(_source: Node): return {}), "cold Teleporting retains exact physical and domain state")
	await _physical_roundtrip(actor)
	for target: Node in [actor, twin, room]:
		target.queue_free()
	await get_tree().process_frame
	await _test_pause_seed_and_history()
	await _test_dynamic_collision_boundary()
	await _test_blocked_reservation_and_rift()
	await _test_actual_player_frame()
	await _test_terminal_reservation()
	await _test_presentation()
	suite.finish(get_tree())


func _room() -> Node2D:
	var room: Node2D = Room.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	return room


func _template() -> Dictionary:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for row: Dictionary in rows:
		if row.id == "room_combat_open_field":
			return row
	return {}


func _actor(room: Node2D, revision: int = -1, companion: String = "") -> Node2D:
	var actor: Node2D = Scene.instantiate()
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var affixes: Array = [Content.affix("teleporting")]
	if not companion.is_empty():
		affixes.append(Content.affix(companion))
	var configured: Dictionary = actor.configure_launch_affixes(affixes, 3) if revision < 0 else actor.configure_launch_affixes(affixes, 3, revision)
	suite.assert_true(configured.ok, "authored Teleporting compiles before native elite species")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Actions.identity()
	identity.seed = 42
	identity.hostile_source_id = "teleport-test"
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok and actor.configure_launch_room_motion(room, _template()).ok, "native Teleporting owns actual species and validated room bounds")
	return actor


func _context(actor: Node2D, frame: int, near: bool = true) -> Dictionary:
	var context := Actions.context(frame)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + (10.0 if near else 20000.0), "y": actor.global_position.y}
	return context


func _tick(actor: Node2D, frame: int, near: bool = false) -> void:
	var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(actor, frame, near))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket) and actor.publish_launch_frame(prepared.ticket), "native Teleporting accepts frame%d: %s" % [frame, prepared.get("context", {})])


func _test_pause_seed_and_history() -> void:
	var room := _room()
	var actor := _actor(room)
	var twin := _actor(room)
	var nullified := _actor(room, -1, "nullified")
	var historical := _actor(room, 5)
	for frame: int in range(1, 481):
		for target: Node2D in [actor, twin, nullified, historical]:
			_tick(target, frame, true)
	suite.assert_equal(twin.launch_affix_runtime_snapshot(), actor.launch_affix_runtime_snapshot(), "same seed and actual room choose exact native reservation")
	suite.assert_true(not historical.launch_affix_runtime_snapshot().has("teleporting"), "historical revision five cannot silently gain native teleport state")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var forged := cold.duplicate(true)
	forged.actor.affix_runtime.teleporting.reservations.back().landing.x += 1.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged non-authored landing cannot restore through native cold boundary")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.teleporting.remaining_frames = 29
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold state cannot shorten the complete departure warning")
	suite.assert_true(twin.restore_native_cold_snapshot(Replay.decode_replay_json(Replay.encode_replay_json(cold).json).replay, func(_binding: Dictionary): return null), "typed mid-warning cold restores exact reserved safe landing")
	actor.apply_time_stop_source(&"stop:teleport", 10.0 / 60.0)
	nullified.apply_time_stop_source(&"stop:teleport-nullified", 3.0)
	var origin := actor.global_position
	for frame: int in range(481, 491):
		_tick(actor, frame, true)
		suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 30, "Stop pauses departure without spending warning at frame%d" % frame)
		suite.assert_equal(actor.global_position, origin, "Stop keeps the actual reserved origin")
	_tick(actor, 491, true)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 29, "departure resumes on first frame after accepted Stop expiry")
	suite.assert_true(actor.apply_elemental_status(&"freeze", &"staff:teleport", 1, 5, 0.0), "actual native teleport accepts bounded elemental freeze")
	for frame: int in range(492, 497):
		_tick(actor, frame, true)
		suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 29, "elemental freeze retains departure budget for every accepted frozen frame")
	_tick(actor, 497, true)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 28, "departure resumes after actual elemental freeze expires")
	for frame: int in range(481, 511):
		_tick(nullified, frame, true)
	suite.assert_equal(nullified.launch_affix_runtime_snapshot().teleporting.remaining_frames, 30, "compatible Nullified retains complete departure during its authored delay")
	_tick(nullified, 511, true)
	suite.assert_equal(nullified.launch_affix_runtime_snapshot().teleporting.remaining_frames, 29, "Nullified vulnerability cannot truncate native departure")
	for frame: int in range(481, 511):
		_tick(twin, frame, true)
	suite.assert_equal(twin.launch_affix_runtime_snapshot().teleporting.phase, "ARRIVAL", "cold warning branch reaches actual bounded arrival")
	await _physical_roundtrip(actor)
	for target: Node in [actor, twin, nullified, historical, room]:
		target.queue_free()
	await get_tree().process_frame


func _wall(position: Vector2, size: Vector2 = Vector2(48, 48)) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = position
	return wall


func _test_dynamic_collision_boundary() -> void:
	var room := _room()
	var actor := _actor(room)
	for frame: int in range(1, 510):
		_tick(actor, frame, true)
	var state: Dictionary = actor.launch_affix_runtime_snapshot().teleporting
	var landing := Vector2(state.reservations.back().landing.x, state.reservations.back().landing.y)
	var origin := actor.global_position
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var prepared: Dictionary = actor.prepare_launch_frame(510, _context(actor, 510))
	var wall := _wall(landing)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(not actor.can_commit_launch_frame(prepared.ticket) and not actor.commit_launch_frame(prepared.ticket), "late destination obstacle refuses prepared native arrival before commit")
	suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "refused collision commit retires private native candidate")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "late collision refusal preserves exact body and original reservation")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	prepared = actor.prepare_launch_frame(510, _context(actor, 510))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket), "collision-cleared original arrival can commit")
	wall = _wall(landing)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(not actor.can_publish_launch_frame(prepared.ticket) and not actor.publish_launch_frame(prepared.ticket), "late destination obstacle also refuses committed arrival publication")
	suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "late publication refusal restores prior reserved origin")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "late publication refusal compensates transform and exact reservation")
	_tick(actor, 510, true)
	suite.assert_equal(actor.global_position, origin, "unsafe fixed landing cannot teleport actual body through new collision")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.reservations.back().outcome, "BLOCKED", "accepted obstructed arrival records safe in-place recovery")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.remaining_frames, 30, "blocked arrival still retains the complete authored recovery")
	for target: Node in [wall, actor, room]:
		target.queue_free()
	await get_tree().process_frame


func _test_blocked_reservation_and_rift() -> void:
	var room := _room()
	var actor := _actor(room)
	actor.apply_time_rift(&"rift:teleport", 0.4)
	for frame: int in range(1, 480):
		_tick(actor, frame, true)
	var origin := actor.global_position
	var walls: Array[Node] = []
	for index: int in range(8):
		walls.append(_wall(origin + Vector2.RIGHT.rotated(index * TAU / 8.0) * 64.0, Vector2(40, 40)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_tick(actor, 480, true)
	var receipt: Dictionary = actor.launch_affix_runtime_snapshot().teleporting.reservations.back()
	suite.assert_equal(receipt.outcome, "SKIPPED", "fully blocked collision-safe candidate set records bounded skipped reservation")
	suite.assert_true(receipt.landing.is_empty(), "no safe candidate cannot fabricate a landing beyond native room authority")
	suite.assert_equal(actor.global_position, origin, "blocked reservation leaves actual native body at its safe origin")
	for wall: Node in walls:
		wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for frame: int in range(481, 961):
		_tick(actor, frame, true)
	receipt = actor.launch_affix_runtime_snapshot().teleporting.reservations.back()
	suite.assert_equal(receipt.sequence, 2, "skipped interval cannot cause unbounded early teleport retries")
	suite.assert_equal(receipt.outcome, "RESERVED", "next complete interval retries native safe candidate reservation")
	var landing := Vector2(receipt.landing.x, receipt.landing.y)
	for frame: int in range(961, 991):
		_tick(actor, frame, true)
	suite.assert_equal(actor.global_position, landing, "actual Rift retains exact reserved teleport displacement after complete warning")
	suite.assert_true(origin.distance_to(landing) >= 47.999 and origin.distance_to(landing) <= 80.001, "Rift cannot shorten the authored native teleport distance floor")
	for target: Node in [actor, room]:
		target.queue_free()
	await get_tree().process_frame


func _test_actual_player_frame() -> void:
	var room := _room()
	var actor := _actor(room)
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	player.health.acquire_invulnerability_source(&"teleport-fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "real Player binds complete native Teleporting accepted-frame participant")
	for frame: int in range(1, 480):
		suite.assert_true(player.advance_action_frame(), "actual Player accepts native teleport interval frame%d" % frame)
	for boundary: int in [480, 510]:
		var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
		var player_before: Dictionary = player.full_player_replay_snapshot()
		player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
		suite.assert_true(not player.advance_action_frame(), "late World refuses native teleport boundary%d" % boundary)
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "late World restores exact native reservation and physical transform")
		suite.assert_equal(player.full_player_replay_snapshot(), player_before, "late teleport refusal restores complete actual Player snapshot")
		player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
		suite.assert_true(player.advance_action_frame(), "native teleport boundary retries its exact original accepted frame")
		if boundary == 480:
			for frame: int in range(481, 510):
				suite.assert_true(player.advance_action_frame(), "actual Player retains complete native departure frame%d" % frame)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.reservations.size(), 1, "real Player rejection retry cannot duplicate native reservation identity")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().teleporting.reservations.back().outcome, "LANDED", "real Player publishes only actual safe landing after complete warning")
	player.configure_hostile_frame_participant(null)
	for target: Node in [actor, player, root, room]:
		target.queue_free()
	await get_tree().process_frame


func _physical_roundtrip(actor: Node2D) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var state: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var encoded := Replay.encode_replay_json(state)
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("elite_teleporting")
	var binding := ContentSnapshot.snapshot(registry)
	var storage := Save.new()
	storage.configure(root, "test-teleporting", binding)
	suite.assert_true(encoded.ok and storage.save_profile("teleporting_v6", "base", {"codec": encoded.json}).ok, "physical SaveService retains typed actual teleport reservation")
	var fresh := Save.new()
	fresh.configure(root, "test-teleporting", binding)
	var primary: Variant = fresh.inspect_profile("teleporting_v6", "base")
	suite.assert_true(primary.ok and Replay.decode_replay_json(primary.payload.payload.codec).replay == state, "fresh physical recovery retains exact native teleport aggregate")


func _test_terminal_reservation() -> void:
	var room := _room()
	var actor := _actor(room)
	for frame: int in range(1, 481):
		_tick(actor, frame, true)
	var info := Damage.from_plan({"run_id": "run-p15", "target_id": "teleport-test", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false})
	suite.assert_true(actor.get_node("HealthComponent").take_damage(info) > 0.0, "actual Health admits native terminal damage during departure")
	var state: Dictionary = actor.launch_affix_runtime_snapshot()
	suite.assert_true(state.terminal and state.teleporting.reservations.back().outcome == "CANCELLED" and state.teleporting.phase == "IDLE", "actual final death cancels reserved landing and recovery authority")
	suite.assert_true(not actor.get_node("EliteTeleportCue").visible, "native final death retires independent teleport warning projection")
	suite.assert_true(not actor.native_cold_snapshot(func(_source: Node): return {}).is_empty(), "terminal cancellation remains a valid typed cold native state")
	suite.assert_true(not actor.prepare_launch_frame(481, _context(actor, 481)).ok, "terminal elite cannot revive a reserved teleport in a later frame")
	for target: Node in [actor, room]:
		target.queue_free()
	await get_tree().process_frame


func _test_presentation() -> void:
	var room := _room()
	var actor := _actor(room, -1, "shielded")
	for frame: int in range(1, 481):
		_tick(actor, frame, true)
	var cue: Node = actor.get_node_or_null("EliteTeleportCue")
	suite.assert_true(cue != null and cue.visible and cue.get_snapshot().phase == "DEPARTURE", "actual native departure owns authored double-arrow and safe landing outline")
	if cue != null:
		await _capture(actor, "departure")
		var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
		var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
		var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
		GameState.set_setting("high_contrast_danger", true)
		GameState.set_setting("enemy_telegraph_scale", 1.5)
		actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "teleport accessibility never mutates accepted reservation")
		suite.assert_true(cue.get_snapshot().high_contrast and cue.get_snapshot().visual_scale == 1.5, "double arrow and landing warning honor danger accessibility settings")
		suite.assert_true(cue.position.distance_to(actor.get_node("EliteShieldCue").position) >= 40.0, "compatible enlarged teleport and shield icons retain separate geometry")
		await _capture(actor, "departure-high-contrast")
		for frame: int in range(481, 511):
			_tick(actor, frame, true)
		suite.assert_equal(cue.get_snapshot().phase, "ARRIVAL", "actual safe landing projects distinct arrival recovery outline")
		await _capture(actor, "arrival-high-contrast")
		GameState.set_setting("high_contrast_danger", old_contrast)
		GameState.set_setting("enemy_telegraph_scale", old_scale)
	for target: Node in [actor, room]:
		target.queue_free()
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
		suite.assert_equal(pixels.get_size(), resolution, "native teleport capture retains requested viewport")
		var ratio := resolution.x / 640.0
		var cue: Node2D = actor.get_node("EliteTeleportCue")
		var centre: Vector2 = cue.global_position * ratio
		var radius := Vector2(15, 12) * cue.scale * ratio
		var visible_pixels := 0
		for y: int in range(maxi(0, int(centre.y - radius.y)), mini(pixels.get_height(), int(centre.y + radius.y))):
			for x: int in range(maxi(0, int(centre.x - radius.x)), mini(pixels.get_width(), int(centre.x + radius.x))):
				var ink := pixels.get_pixel(x, y)
				if (ink.r > 0.85 and ink.g > 0.85 and ink.b > 0.85) if cue.get_snapshot().high_contrast else (ink.r < 0.60 and ink.g > 0.80 and ink.b > 0.60):
					visible_pixels += 1
		suite.assert_true(visible_pixels > 10, "native teleport double-arrow pixels render inside actual icon bounds")
		var output := "res://build/visual-evidence/native-elite-affixes/teleporting-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native Teleporting screenshot retained")
