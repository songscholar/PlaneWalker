extends "res://tests/integration/combat/void_auxiliary_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	await _status("voidking_void_bolt", false, "movement_multiplier", 0.65, 120)
	await _status("voidking_void_grasp", false, "movement_multiplier", 0.4, 90)
	await _status("voidking_devour", true, "attack_multiplier", 0.85, 180)
	await _tear()
	await _vortex()
	await _phase_zone_retirement()
	await _phase_projectile_retirement()
	await _tentacle_exposure()
	await _death_retirement()
	await _released_owner_disposal()
	suite.finish(get_tree())


func _status(action: String, phase_two: bool, modifier: String, multiplier: float, duration: int) -> void:
	var context := _open_case(phase_two, Vector2(350, 180))
	context.player.health.defense = 0.0
	var ownership: Dictionary = context.player.loadout_runtime.snapshot()
	var attack_before: float = context.player.get_effective_attack()
	var modifiers_before: Dictionary = context.player.floor_rule_effect_snapshot()
	_request(context, action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var installed := false
	for _offset: int in range(180):
		var frame: int = int(context.frame) + 1
		var hp_before: Dictionary = context.player.health.transaction_snapshot()
		var owner_before: Dictionary = context.actor.launch_runtime_snapshot()
		var ticket: Dictionary = context.bridge.begin_frame(frame)
		if not context.bridge.prepare_frame(ticket):
			suite.assert_true(false, "actual %s prepares frame %d" % [action, frame])
			break
		var statuses: Array = context.actor.native_void_auxiliary_snapshot().statuses
		if not statuses.is_empty():
			suite.assert_true(context.bridge.rollback_frame(ticket) and context.player.health.restore_transaction_snapshot(hp_before), "actual status compensates late native refusal")
			suite.assert_equal(context.actor.launch_runtime_snapshot(), owner_before, "status rollback restores exact owner receipt")
			suite.assert_equal(context.player.floor_rule_effect_snapshot(), modifiers_before, "status rollback restores Player modifiers")
			_frames(context, frame)
			installed = true
			break
		suite.assert_true(_publish(context.bridge, ticket), "status warning or native projectile accepts frame")
		context.frame = frame
	suite.assert_true(installed, "actual %s Health loss installs finite status" % action)
	if installed:
		var status: Dictionary = context.actor.native_void_auxiliary_snapshot().statuses[0]
		suite.assert_equal(status.multiplier, multiplier, "actual status uses approved multiplier")
		suite.assert_equal(status.through_frame - status.start_frame, duration, "actual status uses approved finite duration")
		if modifier == "movement_multiplier":
			suite.assert_equal(context.player._floor_rule_movement_multiplier(), multiplier, "actual Player movement consumes source owned slow")
		else:
			suite.assert_equal(context.player.get_effective_attack(), attack_before * multiplier, "actual weapon attack consumes Devour output multiplier")
		suite.assert_equal(context.player.loadout_runtime.snapshot(), ownership, "actual Void debuff preserves weapon and time ownership")
		await _cold_owner(context)
		context.player.health.acquire_invulnerability_source(&"status-expiry")
		context.player.global_position = Vector2(900, 500)
		context.player.apply_floor_rule_modifier(&"foreign-status", &"retained", &"apply", {"movement_multiplier": 0.9})
		_frames(context, int(status.through_frame) - 1)
		suite.assert_equal(context.actor.native_void_auxiliary_snapshot().statuses.size(), 1, "source status remains through its last accepted frame")
		_frames(context, int(status.through_frame))
		suite.assert_true(context.actor.native_void_auxiliary_snapshot().statuses.is_empty(), "source status expires at exclusive boundary")
		suite.assert_true(not context.player.floor_rule_effect_snapshot().modifiers.has("void_auxiliary:%s|status" % str(context.actor.hostile_source_id)), "expired status removes native modifier")
		suite.assert_true(context.player.floor_rule_effect_snapshot().modifiers.has("foreign-status|retained"), "status expiry preserves other source ownership")
		suite.assert_equal(context.player.get_effective_attack(), attack_before, "status expiry restores actual weapon attack")
	await _close_case(context)


func _tear() -> void:
	var context := _open_case(false, Vector2(350, 180))
	context.player.health.defense = 0.0
	_request(context, "voidking_plane_tear")
	context.player.global_position = Vector2(500, 180)
	_frames(context, 137)
	var finals: Array = context.effects.snapshot().semantics.zones.filter(func(row: Dictionary): return row.action_id == "void_throne.tear_final")
	suite.assert_true(finals.size() == 1 and finals[0].phase == "WARNING" and finals[0].warning_frames == 40 and finals[0].geometry.radius == 32.0, "real Tear creates independently warned r32 final burst")
	suite.assert_equal(finals[0].geometry.origin, {"x": 480.0, "y": 180.0}, "real Tear final burst uses frozen line endpoint")
	var hp: float = context.player.health.current_hp
	_frames(context, 176)
	suite.assert_equal(context.player.health.current_hp, hp, "actual Tear final burst waits full 40 frames")
	_frames(context, 177)
	suite.assert_equal(context.player.health.current_hp, hp - 25.0, "actual Tear final burst deals approved 25 Void damage")
	_frames(context, 178)
	suite.assert_true(context.effects.snapshot().semantics.zones.filter(func(row: Dictionary): return row.action_id == "void_throne.tear_final").is_empty(), "actual final burst retires after one damage frame")
	await _close_case(context)


func _vortex() -> void:
	var context := _open_case(true, Vector2(400, 180))
	context.player.health.defense = 0.0
	_request(context, "voidking_vortex")
	_frames(context, 120)
	var zones: Array = context.effects.snapshot().semantics.zones
	suite.assert_true(zones.size() == 1 and zones[0].pull_parameters == {"speed": 32.0, "inner_radius": 24.0, "inner_damage": 40.0}, "actual vortex retains approved pull and inner contact")
	suite.assert_equal(context.player._floor_rule_pull_velocity(), Vector2(-32, 0), "actual vortex applies capped native pull")
	context.player.action_state.reset_runtime_state()
	var position: Vector2 = context.player.global_position
	context.player._apply_frame_movement(Vector2.RIGHT)
	suite.assert_true(context.player.global_position.x > position.x, "normal outward Player movement escapes stronger than vortex pull")
	context.player.global_position = Vector2(343, 180)
	var hp: float = context.player.health.current_hp
	_frames(context, 121)
	suite.assert_equal(context.player.health.current_hp, hp - 40.0, "actual contact inside r24 loses 40 Health")
	_frames(context, 122)
	suite.assert_equal(context.player.health.current_hp, hp - 40.0, "vortex inner contact cannot award a second damage claim")
	context.player.health.acquire_invulnerability_source(&"vortex-expiry")
	context.player.global_position = Vector2(400, 180)
	_frames(context, 239)
	suite.assert_equal(context.player._floor_rule_pull_velocity(), Vector2(-32, 0), "vortex pull remains on its last finite frame")
	_frames(context, 240)
	suite.assert_equal(context.player._floor_rule_pull_velocity(), Vector2.ZERO, "vortex expiry clears native pull")
	await _close_case(context)


func _phase_zone_retirement() -> void:
	var context := _open_case(false, Vector2(350, 180))
	context.player.health.acquire_invulnerability_source(&"phase-zones")
	_request(context, "voidking_plane_tear")
	_frames(context, 47)
	suite.assert_equal(context.effects.snapshot().semantics.zones.size(), 1, "real phase transition starts with one active Tear")
	suite.assert_equal(context.actor.get_node("Hurtbox").receive_hit(_damage(context.player, 30, 2500.0)), 1500.0, "real body Health loss enters P2")
	_frames(context, 48)
	suite.assert_true(context.effects.snapshot().semantics.zones.is_empty(), "Void phase transition retires source owned native zones")
	suite.assert_equal(context.player._floor_rule_movement_multiplier(), 1.0, "Void phase transition removes zone slow")
	await _close_case(context)


func _phase_projectile_retirement() -> void:
	var context := _open_case(false, Vector2(440, 180))
	context.player.health.defense = 0.0
	_request(context, "voidking_void_bolt")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_frames(context, 28)
	var before_payloads: Dictionary = context.effects.payload_snapshot()
	suite.assert_equal(before_payloads.projectiles.size(), 1, "phase boundary starts with one committed native Void bolt")
	suite.assert_equal(context.effects.native_payload_nodes().size(), 1, "committed Void bolt owns one physical projectile body")
	var hp_before: float = context.player.health.current_hp
	suite.assert_equal(context.actor.get_node("Hurtbox").receive_hit(_damage(context.player, 30, 2500.0)), 1500.0, "body damage enters P2 while an earlier Void bolt is in flight")
	var owner_before: Dictionary = context.actor.launch_runtime_snapshot()
	var ticket: Dictionary = context.bridge.begin_frame(29)
	var prepared: bool = context.bridge.prepare_frame(ticket)
	suite.assert_true(prepared, "Void phase retirement prepares its physical projectile boundary")
	if prepared:
		suite.assert_true(context.effects.payload_snapshot().projectiles.is_empty() and context.effects.native_payload_nodes().is_empty(), "Void phase retirement removes retired casts' physical projectile work")
		suite.assert_true(context.bridge.rollback_frame(ticket), "late refusal restores phase-retired native Void projectile")
		suite.assert_equal(context.effects.payload_snapshot(), before_payloads, "phase rollback restores the exact projectile domain")
		suite.assert_equal(context.effects.native_payload_nodes().size(), 1, "phase rollback reconstructs the physical projectile body")
		suite.assert_equal(context.actor.launch_runtime_snapshot(), owner_before, "phase rollback preserves the exact retired auxiliary receipt")
	_frames(context, 29)
	suite.assert_true(context.effects.payload_snapshot().projectiles.is_empty() and context.effects.native_payload_nodes().is_empty(), "accepted Void phase boundary retires both domain and native projectile")
	await _cold_owner(context)
	_frames(context, 80)
	suite.assert_equal(context.frame, 80, "retired Void bolt cannot refuse a later physical frame")
	suite.assert_equal(context.player.health.current_hp, hp_before, "retired Void cast cannot apply delayed damage or status")
	suite.assert_true(context.actor.native_void_auxiliary_snapshot().statuses.is_empty(), "retired Void bolt cannot publish a new slow receipt")
	await _close_case(context)


func _tentacle_exposure() -> void:
	var context := _open_case(true, Vector2(400, 180))
	context.player.health.acquire_invulnerability_source(&"tentacle")
	_request(context, "voidking_tentacle_lash")
	_frames(context, 95)
	suite.assert_true(context.actor._launch_runtime.is_exposed(), "actual Tentacle active frame exposes Boss body")
	_frames(context, 124)
	suite.assert_true(context.actor._launch_runtime.is_exposed(), "actual Tentacle exposure retains exactly 30 accepted frames")
	_frames(context, 125)
	suite.assert_true(not context.actor._launch_runtime.is_exposed(), "actual Tentacle exposure expires after frame 30")
	await _close_case(context)


func _death_retirement() -> void:
	var context := _open_case(true, Vector2(350, 180))
	_request(context, "voidking_devour")
	_frames(context, 135)
	suite.assert_equal(context.actor.native_void_auxiliary_snapshot().statuses.size(), 1, "actual terminal test owns active output debuff")
	context.player.apply_floor_rule_modifier(&"foreign-status", &"retained", &"apply", {"movement_multiplier": 0.9})
	context.actor.health.lose_health(100000.0, context.player)
	_frames(context, 136)
	suite.assert_true(context.actor.native_void_auxiliary_snapshot().terminal and context.actor.native_void_auxiliary_snapshot().statuses.is_empty(), "actual final Boss death retires finite auxiliary ledger")
	suite.assert_true(not context.player.floor_rule_effect_snapshot().modifiers.has("void_auxiliary:%s|status" % str(context.actor.hostile_source_id)), "actual final Boss death removes native owned output modifier")
	suite.assert_true(context.player.floor_rule_effect_snapshot().modifiers.has("foreign-status|retained"), "actual terminal cleanup preserves foreign modifier ownership")
	await _close_case(context)


func _released_owner_disposal() -> void:
	var context := _open_case(true, Vector2(350, 180))
	_request(context, "voidking_devour")
	_frames(context, 135)
	context.player.apply_floor_rule_modifier(&"foreign-status", &"retained", &"apply", {"movement_multiplier": 0.9})
	context.actor.queue_free()
	await get_tree().process_frame
	suite.assert_true(context.effects.dispose_native_effects(), "released native Boss cannot block room disposal")
	suite.assert_true(not context.player.floor_rule_effect_snapshot().modifiers.has("void_auxiliary:void-arena-owner|status"), "room disposal clears finite Void status after owner release")
	suite.assert_true(context.player.floor_rule_effect_snapshot().modifiers.has("foreign-status|retained"), "released owner disposal preserves foreign modifiers")
	for key: String in ["player", "room", "root"]:
		context[key].queue_free()
	await get_tree().process_frame


func _cold_owner(context: Dictionary) -> void:
	var cold: Dictionary = context.actor.native_cold_snapshot(func(_source: Node): return {})
	suite.assert_true(context.actor.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "actual status receipt belongs to accepted native cold boundary")
	var aggregate := {"actor": cold, "effects": context.effects.snapshot(), "energy": context.player.time_manager.resource_state(&"time_energy"), "modifiers": context.player.floor_rule_effect_snapshot()}
	var encoded := Replay.encode_replay_json(aggregate)
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := ContentSnapshot.snapshot(registry)
	var storage := Save.new()
	var path := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("void-auxiliary")
	if OS.get_environment("PLANEWALKER_TEST_DATA_DIR").is_empty():
		path = ProjectSettings.globalize_path("res://build/test-data/void-auxiliary")
	storage.configure(path, "test-void-auxiliary", binding)
	suite.assert_true(encoded.ok and storage.save_profile("void_auxiliary", "base", {"codec": encoded.json}).ok, "physical SaveService writes typed auxiliary and resource receipts")
	var fresh_storage := Save.new()
	fresh_storage.configure(path, "test-void-auxiliary", binding)
	var recovered: Variant = fresh_storage.inspect_profile("void_auxiliary", "base")
	suite.assert_true(recovered.ok, "fresh physical SaveService recovers finite native auxiliary state")
	if not recovered.ok:
		return
	var decoded: Dictionary = Replay.decode_replay_json(recovered.payload.payload.codec).replay
	suite.assert_equal(decoded, aggregate, "physical Save and typed Replay preserve exact auxiliary aggregate")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var twin := _boss(room)
	suite.assert_true(twin.restore_native_cold_snapshot(decoded.actor, func(_binding: Dictionary): return null), "fresh actual Boss reconstructs finite status receipt")
	suite.assert_equal(twin.native_void_auxiliary_snapshot(), context.actor.native_void_auxiliary_snapshot(), "fresh actual Boss restores identical finite auxiliary ledger")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(player)
	player.configure_run(&"run-void-arena")
	suite.assert_true(player.time_manager.restore_resource_state(&"time_energy", decoded.energy, false), "fresh actual Player restores exact native resource revision")
	var root := Node2D.new()
	world.add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	suite.assert_true(effects.bind_native_targets({str(twin.hostile_source_id): twin}, {str(context.bridge._player_target_id()): player}), "fresh actual effects bind cold Player and source identities")
	suite.assert_true(effects.restore_launch_transaction_snapshot(decoded.effects), "fresh actual effects reconstruct finite native payloads and statuses")
	suite.assert_equal(player.floor_rule_effect_snapshot(), decoded.modifiers, "fresh native effects restore actual Player debuff from owner receipts")
	suite.assert_true(effects.dispose_native_effects(), "fresh reconstructed effects dispose without leaking source modifiers")
	world.queue_free()
	await get_tree().process_frame
