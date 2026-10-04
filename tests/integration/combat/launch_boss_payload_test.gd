extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_forge_colossus.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_native_piercing()
	suite.finish(get_tree())


func _test_native_piercing() -> void:
	var players: Array[Node2D] = []
	for x: float in [160.0, 210.0]:
		var player := PlayerScene.instantiate() as Node2D
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		add_child(player)
		player.configure_run(&"run-p15")
		player.global_position = Vector2(x, 100.0)
		player.get_node("HealthComponent").defense = 0.0
		player.get_node("HealthComponent").current_hp = 100.0
		players.append(player)
	var actor := BossScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(100.0, 100.0)
	var parser := Boss.new()
	parser.configure(Content.boss("forge_colossus"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-forge", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "actual Forge binds its authored Boss runtime")
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for row: Dictionary in templates:
		if row.id == "room_combat_open_field":
			suite.assert_true(actor.configure_launch_room_motion(room, row).ok, "Forge projectile owns real native room bounds")
	var runtime: RefCounted = actor.get("_launch_runtime")
	actor.get_node("HealthComponent").current_hp = 700.0
	suite.assert_true(runtime.accept_damage_fact({"fact_id": "forge-phase-fixture".sha256_text(), "runtime_frame": 0, "target_source_id": "hostile-forge", "amount": 2100.0, "hp_after": 700.0}).ok, "fixture enters authored sword-form phase through accepted damage")
	for frame: int in range(1, 61):
		suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "full sixty-frame phase cue precedes sword-form action")
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15", 60) and effects.configure_native_payloads(native_root), "actual Boss effects bind the accepted room clock")
	var threats := Threats.new()
	var observation := {"runtime_frame": 60, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 160.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "first"}
	var started: Dictionary = runtime.request_action("forge_sword_wave", observation)
	suite.assert_true(started.ok, "authored Forge sword wave commits its complete warning")
	for fact: Dictionary in started.get("threat_facts", []):
		threats.register_fact(Coordinator.native_threat_fact(fact))
	await get_tree().physics_frame
	var rolled_back := false
	var spawned := false
	var retired := false
	var published: Array = []
	var listener := func(_info: RefCounted, target: Node, amount: float):
		if players.has(target):
			published.append([players.find(target), amount])
	EventBus.hit_confirmed.connect(listener)
	for frame: int in range(61, 128):
		var actor_checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var health_checkpoints: Array[Dictionary] = []
		for player: Node2D in players:
			health_checkpoints.append(player.get_node("HealthComponent").transaction_snapshot())
		var before := effects.snapshot()
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": threats, "actors": {"hostile-forge": actor}, "targets": {"first": players[0], "second": players[1]}}
		var observations := observation.duplicate(true)
		observations.runtime_frame = frame
		var prepared: Dictionary = actor.prepare_launch_frame(frame, observations)
		var effect: Dictionary = effects.prepare_effects([{"hostile_source_id": "hostile-forge", "batch": prepared.batch}], context) if prepared.ok else {"ok": false}
		suite.assert_true(prepared.ok and effect.ok, "real native sword wave prepares frame %d" % frame)
		if not prepared.ok or not effect.ok:
			if prepared.ok:
				actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(actor_checkpoint)
			for index: int in range(players.size()):
				players[index].get_node("HealthComponent").discard_transaction_snapshot(health_checkpoints[index])
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit(effect.ticket).ok, "native Boss and payload commit one candidate frame")
		if not rolled_back and players[0].get_node("HealthComponent").current_hp < 100.0:
			rolled_back = true
			suite.assert_equal(effects.native_payload_nodes()[0].get_collision_exceptions(), [players[0]], "accepted first penetration installs exact native collision exception")
			suite.assert_true(effects.rollback(effect.ticket) and actor.rollback_launch_frame(prepared.ticket) and actor.restore_launch_transaction_snapshot(actor_checkpoint), "rejected penetration compensates source, native projection and claims")
			for index: int in range(players.size()):
				suite.assert_true(players[index].get_node("HealthComponent").restore_transaction_snapshot(health_checkpoints[index]), "outer owner restores real target Health")
			suite.assert_equal(effects.snapshot(), before, "rejected first penetration restores all payload state")
			suite.assert_equal(effects.native_payload_nodes()[0].get_collision_exceptions(), [], "rejected penetration removes candidate collision exceptions")
			suite.assert_equal(published, [], "rejected penetrating hit publishes no damage")
			prepared = actor.prepare_launch_frame(frame, observations)
			effect = effects.prepare_effects([{"hostile_source_id": "hostile-forge", "batch": prepared.batch}], context)
			suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit(effect.ticket).ok, "same physical first contact retries once")
		suite.assert_true(actor.publish_launch_frame(prepared.ticket) and effects.publish_effect_observations(effect.ticket), "accepted sword wave publishes sealed observations")
		actor.discard_launch_transaction_snapshot(actor_checkpoint)
		for index: int in range(players.size()):
			players[index].get_node("HealthComponent").discard_transaction_snapshot(health_checkpoints[index])
		if not effects.payload_snapshot().projectiles.is_empty():
			spawned = true
			suite.assert_equal(effects.native_payload_nodes()[0].get_node("Sprite2D").texture.resource_path, "res://assets/production/hostile_effects/fire_projectile.png", "actual Forge sword wave uses its original fire raster")
		if spawned and effects.payload_snapshot().projectiles.is_empty():
			retired = true
			break
		await get_tree().physics_frame
	suite.assert_true(rolled_back and spawned and retired, "actual sword wave penetrates once and retires after its second physical body")
	suite.assert_equal(published, [[0, 30.0], [1, 30.0]], "two real Player bodies each receive one authored sword-wave hit")
	EventBus.hit_confirmed.disconnect(listener)
	actor.queue_free()
	room.queue_free()
	native_root.queue_free()
	for player: Node2D in players:
		player.queue_free()
	await get_tree().process_frame
