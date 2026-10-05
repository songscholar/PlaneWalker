extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://data/content_packs/base/assets/bosses/launch/boss_ruin_king.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const PayloadRuntime := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Ledger := preload("res://scripts/dungeon/launch_encounter_frame_authority.gd")
var suite: RefCounted
var _encounter: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := Boss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 160)
	var parser := Definition.new()
	parser.configure(Content.boss("ruin_king"))
	actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-debris", "hostile_source_id": "ruin-debris-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	move_child(room, 0)
	_add_obstacle(room)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			actor.configure_launch_room_motion(room, template)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-debris")
	player.global_position = Vector2(400, 160)
	player.health.acquire_invulnerability_source(&"debris-fixture")
	actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 400.0))
	var runtime: RefCounted = actor.get("_launch_runtime")
	for frame: int in range(1, 61):
		runtime.advance_frame(frame, _context(frame, actor, player), false)
	player.set("_runtime_frame", 60)
	actor._refresh_control_visual()
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-debris", 60)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	bridge.configure(player, registry, [actor], effects)
	_encounter = _new_encounter()
	for frame: int in range(20, 61):
		_encounter.advance_frame(frame)
	suite.assert_true(_encounter.register_spawned("ruin_spawn", "ruin-debris-owner"), "real encounter binds actual Ruin source")
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): _encounter.notify_entity_defeated(str(source), receipt))
	var ledger := Ledger.new()
	suite.assert_true(ledger.configure(_encounter, effects) and bridge.configure_encounter_authority(ledger), "native accepted frames include actual encounter pending-work ownership")
	var decision: Dictionary = runtime.request_action("guardian_debris_barrage", _context(60, actor, player))
	suite.assert_true(decision.ok, "authored P2 barrage commits its actual forty-frame warning")
	for fact: Dictionary in decision.get("threat_facts", []):
		registry.register_fact(Actions.native_threat_fact(fact))
	player.global_position = Vector2(600, 160)
	for frame: int in range(61, 191):
		await get_tree().physics_frame
		var before: Dictionary = effects.snapshot()
		var actor_before: Dictionary = actor.launch_runtime_snapshot()
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "actual debris flight prepares accepted frame%d" % frame)
			bridge.rollback_frame(ticket)
			break
		if frame == 100:
			suite.assert_equal(effects.payload_snapshot().get("schema_version"), 2, "actual authored barrage explicitly upgrades payload schema1 to2")
			suite.assert_equal(effects.payload_snapshot().get("arena_debris", {}).get("rows", []).size(), 0, "flying projectiles cannot create premature ground obstacles")
			_check_payload_versions(effects.payload_snapshot())
		if frame == 190:
			var obstacle := room.get_node("DebrisPhysicalObstacle") as Node2D
			var obstacle_position := obstacle.global_position
			for landing: Node2D in effects.native_debris_nodes():
				if landing.native_construct_snapshot().activated_frame == frame:
					obstacle.global_position = landing.global_position
					break
			await get_tree().physics_frame
			suite.assert_true(bridge.prepare_frame_publication(ticket).is_empty(), "late physical room obstruction rejects publication of the sealed landing")
			obstacle.global_position = obstacle_position
			await get_tree().physics_frame
			suite.assert_true(bridge.rollback_frame(ticket), "actual landing refusal compensates native projectile and construct candidates")
			suite.assert_equal(effects.snapshot(), before, "refused landing restores exact effects and debris ledger")
			suite.assert_equal(actor.launch_runtime_snapshot(), actor_before, "refused landing restores exact actual Boss")
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket), "same native landing frame retries")
		suite.assert_true(_publish(bridge, ticket), "actual debris frame accepts")
	var debris: Dictionary = effects.payload_snapshot().get("arena_debris", {})
	suite.assert_true(not debris.is_empty() and debris.get("rows", []).size() > 0, "actual blocked or expired barrage creates authoritative debris")
	if not debris.is_empty() and effects.has_method("native_debris_nodes"):
		var payload_checker := PayloadRuntime.new()
		payload_checker.configure("run-debris", 60)
		var forged: Dictionary = effects.payload_snapshot()
		var receipt: Dictionary = forged.debris_impacts[0]
		var endpoint := PayloadRuntime._vector(receipt.projectile_definition.origin) + PayloadRuntime._vector(receipt.projectile_definition.direction) * float(receipt.projectile_definition.range_px)
		receipt.event.position = {"x": endpoint.x, "y": endpoint.y}
		forged.arena_debris.rows[0].event.position = receipt.event.position.duplicate(true)
		suite.assert_true(not payload_checker.can_restore_snapshot(forged), "cold landing rejects physically impossible full-range travel before its speed budget")
		var nodes: Array = effects.native_debris_nodes()
		var retained: Dictionary = effects.snapshot()
		suite.assert_true(not effects.configure("other-run", 0), "live debris prevents resetting its owning authority to another run")
		suite.assert_equal(effects.snapshot(), retained, "refused reconfiguration retains exact effect and arena state")
		suite.assert_equal(nodes.size(), 4, "actual six-projectile barrage fills only the authored four-body cap")
		for node: Node2D in nodes:
			suite.assert_true(node.global_position.distance_to(Vector2(560, 64)) > 76.0, "actual landing keeps48px clearance from an arbitrary physical room obstacle")
		suite.assert_equal(effects.work_snapshot().records.size(), 6, "four active and two pending debris remain owned construct work")
		for work_id: String in effects.work_snapshot().records:
			suite.assert_true(work_id.length() <= 64 and effects.work_snapshot().records[work_id].kind == "construct", "debris work fits the actual encounter ledger contract")
		await _capture(nodes, "intact")
		await _check_cold_continuation(actor, player, effects, registry, bridge)
		await _check_shared_wall_budget(actor, player, effects, registry, bridge)
		nodes = effects.native_debris_nodes()
		if not nodes.is_empty():
			var node: Node2D = nodes[0]
			var stable_key: String = node.stable_entity_key()
			suite.assert_true(not node.is_in_group("enemies") and not node.is_in_group("bosses"), "actual debris never becomes counted room reward work")
			var before: Dictionary = effects.snapshot()
			var health_ticket: Dictionary = player.health.begin_frame_signal_transaction(257)
			var hit_ticket: Dictionary = bridge.begin_frame(257)
			suite.assert_equal(node.get_node("Hurtbox").receive_hit(_damage(player, 30, 20.0)), 20.0, "actual weapon Hurtbox removes only authored twenty debris HP")
			suite.assert_equal(node.get_node("Hurtbox").receive_hit(_damage(player, 30, 20.0)), 0.0, "real debris collision rejects duplicate weapon identity")
			suite.assert_equal(node.collision_layer, 0, "accepted debris destruction removes actual body collision")
			suite.assert_true(bridge.prepare_frame(hit_ticket) and bridge.rollback_frame(hit_ticket), "real debris break compensates a rejected native frame")
			suite.assert_true(player.health.rollback_frame_signal_transaction(health_ticket), "refused debris hit closes the actual outer Player frame")
			suite.assert_equal(effects.snapshot(), before, "debris refusal restores exact HP, work ownership and damage claims")
			for restored_node: Node2D in effects.native_debris_nodes():
				if restored_node.stable_entity_key() == stable_key:
					node = restored_node
			suite.assert_equal(node.collision_layer, 1, "debris refusal restores its actual collider")
			health_ticket = player.health.begin_frame_signal_transaction(257)
			hit_ticket = bridge.begin_frame(257)
			suite.assert_equal(node.get_node("Hurtbox").receive_hit(_damage(player, 30, 20.0)), 20.0, "same real debris hit retries after compensation")
			suite.assert_true(bridge.prepare_frame(hit_ticket) and _publish(bridge, hit_ticket), "real debris destruction accepts once")
			var health_publication: Dictionary = player.health.prepare_frame_signal_publication(health_ticket)
			suite.assert_true(player.health.finalize_frame_signal_publication(health_publication), "accepted debris hit finalizes the actual outer Player frame")
			player.health.publish_prepared_frame_signals()
			suite.assert_equal(_encounter.snapshot().pending_work, effects.work_snapshot().records, "accepted debris damage retires old work before admitting its pending replacement")
			for row: Dictionary in effects.payload_snapshot().arena_debris.rows:
				if row.activated_frame == 257:
					suite.assert_equal(row.age, 0, "pending actual debris starts full480-frame lifetime only after capacity is released")
			actor.get_node("Hurtbox").receive_hit(_damage(player, 90, 1000.0))
			await get_tree().physics_frame
			var death_ticket: Dictionary = bridge.begin_frame(258)
			suite.assert_true(bridge.prepare_frame(death_ticket) and _publish(bridge, death_ticket), "actual owner death retires active and pending native debris")
			suite.assert_equal(effects.native_debris_nodes().size(), 0, "dead Boss leaves no retained actual debris collision")
			for work: Dictionary in effects.work_snapshot().records.values():
				suite.assert_true(work.kind != "construct", "terminal debris never blocks room completion through orphaned construct work")
			suite.assert_equal(_encounter.snapshot().pending_work, effects.work_snapshot().records, "actual room ledger has no orphaned debris after owner death")
	actor.queue_free()
	player.queue_free()
	root.queue_free()
	room.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _check_payload_versions(current: Dictionary) -> void:
	var fresh := PayloadRuntime.new()
	fresh.configure(str(current.run_id), int(current.initial_frame))
	suite.assert_true(fresh.restore_snapshot(current), "fresh pure payload restores authored schema2 during actual flight")
	suite.assert_equal(fresh.snapshot(), current, "schema2 restore retains exact new recipe and domain state")
	for mutation: String in ["root", "recipe", "domain", "incomplete", "downgrade"]:
		var forged := current.duplicate(true)
		match mutation:
			"root": forged.extra = true
			"recipe": forged.projectiles[0].definition.debris_recipe.extra = true
			"domain": forged.arena_debris.extra = true
			"incomplete": forged.erase("debris_impacts")
			"downgrade": forged.schema_version = 1
		suite.assert_true(not fresh.can_restore_snapshot(forged), "payload rejects unsupported version shape: " + mutation)
	var historical := current.duplicate(true)
	historical.schema_version = 1
	historical.erase("arena_debris")
	historical.erase("debris_impacts")
	for row: Dictionary in historical.projectiles:
		var old_id: String = row.id
		row.definition.erase("debris_recipe")
		row.id = PayloadRuntime._id(row.definition)
		row.control.identity.hostile_source_id = row.id
		for claim: Dictionary in historical.claims:
			if claim.id == old_id:
				claim.id = row.id
	suite.assert_true(fresh.restore_snapshot(historical), "exact historical schema1 projectile definition remains supported")
	suite.assert_equal(fresh.snapshot(), historical, "historical restore never silently adds new arena behavior")
	for frame: int in range(int(historical.runtime_frame) + 1, 191):
		suite.assert_true(fresh.advance_frame(frame, {"targets": {}, "projectile_contacts": {}}).ok, "historical authored flight advances")
	suite.assert_equal(fresh.snapshot().schema_version, 1, "historical landing retains exact original schema1 behavior")
	suite.assert_true(not fresh.snapshot().has("arena_debris"), "historical barrage cannot acquire unrecorded debris")


func _check_cold_continuation(actor: Node2D, player: Node2D, effects: RefCounted, registry: RefCounted, bridge: RefCounted) -> void:
	var world := SubViewport.new()
	world.size = Vector2i(640, 360)
	world.world_2d = World2D.new()
	add_child(world)
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	_add_obstacle(room)
	var twin := Boss.instantiate() as Node2D
	twin.process_mode = Node.PROCESS_MODE_DISABLED
	twin.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(twin)
	twin.global_position = actor.global_position
	var parser := Definition.new()
	parser.configure(Content.boss("ruin_king"))
	twin.configure_launch_definition(parser.runtime_projection(), actor.get("_launch_identity"))
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			twin.configure_launch_room_motion(room, template)
	suite.assert_true(twin.restore_native_cold_snapshot(actor.native_cold_snapshot(func(_source: Node): return {}), func(_binding: Dictionary): return null), "fresh actual Boss cold-restores without projectile instance references")
	var next_player := Player.instantiate() as Node2D
	next_player.process_mode = Node.PROCESS_MODE_DISABLED
	next_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(next_player)
	next_player.configure_run(&"run-debris")
	next_player.set("_runtime_frame", 190)
	next_player.global_position = player.global_position
	next_player.health.acquire_invulnerability_source(&"debris-fixture")
	var root := Node2D.new()
	world.add_child(root)
	var next_effects := Effects.new()
	next_effects.configure("run-debris", 60)
	next_effects.configure_native_payloads(root)
	suite.assert_true(next_effects.restore_launch_transaction_snapshot(effects.snapshot()), "fresh native effect authority reconstructs active debris bodies and pending receipts")
	var next_registry := Registry.new()
	var next_bridge := Bridge.new()
	suite.assert_true(next_bridge.configure(next_player, next_registry, [twin], next_effects) and next_bridge._restore_registry(registry.snapshot()), "fresh actual bridge binds exact cold arena and threats")
	var next_encounter := _new_encounter()
	suite.assert_true(next_encounter.restore_snapshot(_encounter.snapshot()), "fresh cold encounter restores exact active and pending debris work")
	var next_ledger := Ledger.new()
	suite.assert_true(next_ledger.configure(next_encounter, next_effects) and next_bridge.configure_encounter_authority(next_ledger), "fresh native continuation owns the original encounter ledger")
	for frame: int in range(191, 201):
		await get_tree().physics_frame
		for participant: RefCounted in [bridge, next_bridge]:
			var ticket: Dictionary = participant.begin_frame(frame)
			suite.assert_true(participant.prepare_frame(ticket) and _publish(participant, ticket), "original and fresh actual debris continuation accepts")
		suite.assert_equal(twin.launch_runtime_snapshot(), actor.launch_runtime_snapshot(), "fresh actual Boss continuation stays deterministic")
		suite.assert_equal(next_effects.snapshot(), effects.snapshot(), "fresh native debris continuation stays exact")
		suite.assert_equal(next_registry.snapshot(), registry.snapshot(), "fresh arena threats continue deterministically")
		suite.assert_equal(next_encounter.snapshot(), _encounter.snapshot(), "fresh cold room work continues deterministically")
	world.queue_free()
	await get_tree().process_frame


func _check_shared_wall_budget(actor: Node2D, player: Node2D, effects: RefCounted, registry: RefCounted, bridge: RefCounted) -> void:
	var runtime: RefCounted = actor.get("_launch_runtime")
	var cancelled: Dictionary = runtime.cancel_action(&"debris-fixture-wall-selection")
	for generation: int in cancelled.get("retired_generations", []):
		registry.retire(actor.get("hostile_source_id"), generation)
	player.global_position = actor.global_position + Vector2(80, 0)
	var decision: Dictionary = runtime.request_action("guardian_wall", _context(200, actor, player))
	suite.assert_true(decision.ok, "actual wall decision shares active cover and debris budget")
	for fact: Dictionary in decision.get("threat_facts", []):
		registry.register_fact(Actions.native_threat_fact(fact))
	player.global_position = Vector2(600, 160)
	for frame: int in range(201, 256):
		await get_tree().physics_frame
		var ticket: Dictionary = bridge.begin_frame(frame)
		suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual shared-budget warning advances")
	suite.assert_equal(effects.arena_debris_active_count(), 4, "full shared budget retains all four actual debris")
	suite.assert_true(actor.native_arena_snapshot().walls.is_empty() and runtime.snapshot().action.phase == "WARNING", "full eight-construct budget defers the warned pair without overflow")
	for index: int in range(2):
		var cover := actor.get_node("ArenaConstructs").get_child(index)
		suite.assert_equal(cover.get_node("Hurtbox").receive_hit(_damage(player, 40 + index, 80.0)), 80.0, "real cover break releases one shared native construct slot")
	await get_tree().physics_frame
	var ticket: Dictionary = bridge.begin_frame(256)
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "capacity release admits the original warned wall decision")
	suite.assert_equal(actor.native_arena_snapshot().walls.size(), 2, "two released slots admit two actual walls")
	if actor.native_arena_snapshot().walls.size() == 2:
		suite.assert_equal(actor.native_arena_snapshot().walls[0].spawn_frame, 256, "budget deferral starts full wall TTL only on admitted frame")
		suite.assert_equal(actor.native_arena_snapshot().walls[0].age, 0, "pending wall never spends its lifetime")


func _capture(nodes: Array, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		for node: Node2D in nodes:
			var colors: Dictionary = {}
			for y: int in range(int(node.global_position.y) - 24, int(node.global_position.y) + 12):
				for x: int in range(int(node.global_position.x) - 12, int(node.global_position.x) + 12):
					colors[pixels.get_pixelv(Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))).to_rgba32()] = true
			suite.assert_true(colors.size() >= 4, "actual debris raster renders nonblank at " + str(resolution))
		var output := "res://build/visual-evidence/p15b-native-arena/ruin-debris-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual debris screenshot retained")


func _add_obstacle(room: Node2D) -> void:
	var body := StaticBody2D.new()
	body.name = "DebrisPhysicalObstacle"
	body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	collision.shape = circle
	body.add_child(collision)
	room.add_child(body)
	body.global_position = Vector2(560, 64)


func _new_encounter() -> RefCounted:
	var runtime := Encounter.new()
	var definition := {"id": "boss_encounter_ruin_king_adapter_v1", "floor_id": "floor_ruins_of_remnant", "recipe_id": "ruin_king", "room_type": "boss", "waves": [{"id": "ruin_wave", "delay_frames": 0, "warning_frames": 40, "spawns": [{"id": "ruin_spawn", "enemy_id": "ruin_king", "spawn_slot_id": "boss_primary", "spawn_offset": {"x": 0.0, "y": 0.0}, "elite": false, "affix_ids": [], "mechanism_ids": []}]}]}
	suite.assert_true(runtime.configure(definition, {"run_id": "run-debris", "room_id": "node-debris", "runtime_frame": 19, "encounter_generation": 1}).ok, "Ruin debris fixture uses canonical actual boss encounter grammar")
	return runtime


func _context(frame: int, actor: Node2D, player: Node2D) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": actor.global_position.x, "y": actor.global_position.y}, "target_position": {"x": player.global_position.x, "y": player.global_position.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}


func _damage(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-debris", "target_id": "pending", "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
