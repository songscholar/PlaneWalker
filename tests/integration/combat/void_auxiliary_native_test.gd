extends "res://tests/integration/combat/void_arena_native_test.gd"

const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")


func _run() -> void:
	suite = Suite.new()
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	actor.global_position = Vector2(320, 180)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	player.global_position = Vector2(350, 180)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual Void auxiliary uses native Health settlement")
	var context := {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 350.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": bridge._player_target_id()}
	var requested: Dictionary = actor._launch_runtime.request_action("voidking_scepter_strike", context)
	suite.assert_true(requested.ok, "actual Scepter reserves normal native attack")
	for fact: Dictionary in requested.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	for frame: int in range(1, 28):
		var ticket: Dictionary = bridge.begin_frame(frame)
		suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual Scepter warning accepts%d" % frame)
	var hp_before := float(player.health.current_hp)
	var player_before: Dictionary = player.health.transaction_snapshot()
	var before: Dictionary = actor.launch_runtime_snapshot()
	var ticket: Dictionary = bridge.begin_frame(28)
	suite.assert_true(bridge.prepare_frame(ticket), "actual Scepter damage and burn prepare")
	suite.assert_true(player.health.current_hp < hp_before, "actual Scepter loses real Health")
	suite.assert_equal(actor._launch_runtime.void_auxiliary_snapshot().burns.size(), 1, "actual accepted Scepter Health loss installs finiteburn")
	suite.assert_true(bridge.rollback_frame(ticket), "late refusal compensates actual Health loss and Voidburn")
	suite.assert_true(player.health.restore_transaction_snapshot(player_before), "outer Player transaction compensates refused native Healthloss")
	suite.assert_equal(player.health.current_hp, hp_before, "refusal compensates actual Player Health")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "refusal compensates owner burnreceipt")
	ticket = bridge.begin_frame(28)
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual Scepter retries sameframe once")
	suite.assert_equal(actor._launch_runtime.void_auxiliary_snapshot().burns.size(), 1, "accepted retry retains one sourceownedburn")
	var burned_hp := float(player.health.current_hp)
	for frame: int in range(29, 59):
		ticket = bridge.begin_frame(frame)
		suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual finite burn advancesframe%d" % frame)
	suite.assert_equal(player.health.current_hp, burned_hp - 2.0, "sourceowned burn actually damages Player2after30frames")
	player.global_position = Vector2(900, 500)
	for frame: int in range(59, 209):
		ticket = bridge.begin_frame(frame)
		suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual finite burn retains accepted frame %d" % frame)
	suite.assert_equal(player.health.current_hp, burned_hp - 12.0, "actual Scepter burn has six authored damage ticks through frame 180")
	ticket = bridge.begin_frame(209)
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual burn lifetime accepts next frame")
	suite.assert_true(actor.native_void_auxiliary_snapshot().burns.is_empty(), "actual burn retires after its sixth finite tick")
	effects.dispose_native_effects()
	actor.queue_free()
	player.queue_free()
	root.queue_free()
	room.queue_free()
	await get_tree().process_frame
	await _native_pickup()
	await _overlapping_pickups()
	suite.finish(get_tree())


func _open_case(phase_two: bool, position: Vector2) -> Dictionary:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_void_throne":
			suite.assert_true(room.bind_room({"id": "void-auxiliary-fixture", "template_id": template.id, "room_type": "boss"}, template, {"floor_id": "floor_throne_of_void", "palette_id": "palette_throne_of_void", "environment_rule_id": "rule_collapsing_plane", "room_seed": 42}).ok, "native auxiliary fixture binds actual production room artwork")
	var actor := _boss(room)
	actor.global_position = Vector2(320, 180)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	player.global_position = position
	if phase_two:
		suite.assert_equal(actor.get_node("Hurtbox").receive_hit(_damage(player, 21, 2500.0)), 1500.0, "actual bodyhit enters VoidP2forauxiliary case")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "native auxiliarycase binds actual authorities")
	var result := {"actor": actor, "player": player, "room": room, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "frame": 0}
	if phase_two:
		player.global_position = Vector2(900, 500)
		_frames(result, 60)
		player.global_position = position
	return result


func _frames(context: Dictionary, through: int) -> void:
	for frame: int in range(int(context.frame) + 1, through + 1):
		var ticket: Dictionary = context.bridge.begin_frame(frame)
		var accepted: bool = context.bridge.prepare_frame(ticket) and _publish(context.bridge, ticket)
		suite.assert_true(accepted, "native auxiliarycase acceptsframe%d" % frame)
		if not accepted:
			context.bridge.rollback_frame(ticket)
			return
		context.frame = frame


func _request(context: Dictionary, action: String) -> void:
	var cancelled: Dictionary = context.actor._launch_runtime.cancel_action(&"fixture_exact_authored_action")
	for generation: int in cancelled.retired_generations:
		context.registry.retire(context.actor.hostile_source_id, generation)
	var source: Vector2 = context.actor.global_position
	var target: Vector2 = context.player.global_position
	var requested: Dictionary = context.actor._launch_runtime.request_action(action, {"runtime_frame": int(context.frame), "source_position": {"x": source.x, "y": source.y}, "target_position": {"x": target.x, "y": target.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": context.bridge._player_target_id()})
	suite.assert_true(requested.ok, "native auxiliarycase requests actual" + action)
	for fact: Dictionary in requested.get("threat_facts", []):
		suite.assert_true(context.registry.register_fact(Actions.native_threat_fact(fact)), "native auxiliarycase publishes actual frozenwarning")


func _close_case(context: Dictionary) -> void:
	suite.assert_true(context.effects.dispose_native_effects(), "native auxiliary disposal removes sourceownedwork")
	for key: String in ["actor", "player", "room", "root"]:
		context[key].queue_free()
	await get_tree().process_frame


func _native_pickup() -> void:
	var context := _open_case(true, Vector2(350, 180))
	_request(context, "voidking_shard_projection")
	_frames(context, 88)
	var state: Dictionary = context.actor.native_void_auxiliary_snapshot()
	suite.assert_equal(state.pickups.size(), 4, "actual eightshardcast retains fourpickup constructs")
	suite.assert_true(context.actor.has_node("VoidAuxiliaryPickups") and context.actor.get_node("VoidAuxiliaryPickups").get_child_count() == 4, "fouractual native pickup nodes use finitedomain projection")
	if not state.pickups.is_empty():
		context.player.global_position = Vector2(float(state.pickups[0].position.x), float(state.pickups[0].position.y))
		context.player.time_manager.energy = 98.0
		var publications := [0]
		context.player.time_manager.energy_changed.connect(func(_current: float, _maximum: float): publications[0] += 1)
		var resource_before: Dictionary = context.player.time_manager.resource_state(&"time_energy")
		var owner_before: Dictionary = context.actor.launch_runtime_snapshot()
		var ticket: Dictionary = context.bridge.begin_frame(89)
		suite.assert_true(context.bridge.prepare_frame(ticket), "actual pickup energy receipt prepares before publication")
		suite.assert_equal(context.player.time_manager.energy, 100.0, "actual pickup applies capped energy during owned transaction")
		suite.assert_equal(publications[0], 0, "unaccepted pickup emits no early resource signal")
		suite.assert_true(context.bridge.rollback_frame(ticket), "late refusal compensates native pickup resource")
		suite.assert_equal(context.player.time_manager.resource_state(&"time_energy"), resource_before, "pickup rollback restores energy and revision exactly")
		suite.assert_equal(context.actor.launch_runtime_snapshot(), owner_before, "pickup rollback restores domain and native geometry")
		suite.assert_equal(publications[0], 0, "pickup rollback emits no resource signal")
		_frames(context, 89)
		suite.assert_equal(context.player.time_manager.energy, 100.0, "actual native pickup gives capped2ofauthored5energy")
		suite.assert_equal(publications[0], 1, "accepted pickup publishes its energy once")
		suite.assert_true(context.actor.native_void_auxiliary_snapshot().pickups[0].used, "authenticated realPlayerresource receipt consumes pickup once")
		_frames(context, 90)
		suite.assert_equal(context.player.time_manager.energy, 100.0, "native picked shard cannot award twice")
		context.player.global_position = Vector2(float(state.pickups[1].position.x), float(state.pickups[1].position.y))
		_frames(context, 91)
		suite.assert_true(context.actor.native_void_auxiliary_snapshot().pickups[1].used, "full energy still consumes one real pickup")
		suite.assert_equal(publications[0], 1, "zero gain pickup does not publish a resource change")
		context.player.global_position = Vector2(600, 320)
		context.player.health.acquire_invulnerability_source(&"pickup-expiry")
		_frames(context, 268)
		suite.assert_equal(context.actor.get_node("VoidAuxiliaryPickups").get_child_count(), 0, "unused native shards expire at exclusive 180 frame boundary")
	await _close_case(context)


func _overlapping_pickups() -> void:
	var context := _open_case(true, Vector2(80, 16))
	context.actor.global_position = Vector2(32, 32)
	context.actor._refresh_native_arena()
	_request(context, "voidking_shard_projection")
	_frames(context, 88)
	context.player.global_position = Vector2(24, 24)
	context.player.time_manager.energy = 90.0
	_frames(context, 89)
	suite.assert_equal(context.player.time_manager.energy, 95.0, "coalesced edge pickups admit one resource receipt per frame")
	_frames(context, 90)
	suite.assert_equal(context.player.time_manager.energy, 100.0, "second coalesced pickup is accepted on the next frame")
	await _close_case(context)
