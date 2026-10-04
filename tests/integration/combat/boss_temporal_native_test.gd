extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_time_sovereign.tscn")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_native_rewind(false)
	await _test_native_rewind(true)
	suite.finish(get_tree())


func _test_native_rewind(blocked_landing: bool) -> void:
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(460.0, 100.0)
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 4
	var blocker_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(32.0, 80.0)
	blocker_shape.shape = rectangle
	blocker.add_child(blocker_shape)
	add_child(blocker)
	blocker.global_position = Vector2(131.0 if blocked_landing else 280.0, 100.0)
	var actor := BossScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(400.0, 100.0)
	var parser := Boss.new()
	parser.configure(Content.boss("time_sovereign"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-temporal", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "actual Time Sovereign binds deterministic runtime")
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for row: Dictionary in templates:
		if row.id == "room_boss_time_sovereign":
			suite.assert_true(actor.configure_launch_room_motion(room, row).ok, "actual Time Sovereign owns its authored arena bounds")
	var runtime: RefCounted = actor.get("_launch_runtime")
	for frame: int in range(1, 211):
		var observation := Actions.context(frame)
		observation.source_position = {"x": 100.0 + frame % 60, "y": 100.0}
		suite.assert_true(runtime.advance_frame(frame, observation, false).ok, "native fixture retains accepted historical position")
		if frame == 150:
			runtime.accept_damage_fact({"fact_id": "native-temporal-damage", "runtime_frame": frame, "target_source_id": "hostile-temporal", "amount": 1000.0, "hp_after": 1000.0})
	actor.get_node("HealthComponent").current_hp = 1000.0
	actor.global_position = Vector2(400.0, 100.0)
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15", 210) and effects.configure_native_payloads(native_root), "native Boss mechanism owner binds history clock")
	var threats := Threats.new()
	var observations := {"runtime_frame": 210, "source_position": {"x": 400.0, "y": 100.0}, "target_position": {"x": 460.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
	var started: Dictionary = runtime.request_action("traitor_self_rewind", observations)
	suite.assert_true(started.ok, "actual Boss commits complete historical landing warning")
	for fact: Dictionary in started.get("threat_facts", []):
		threats.register_fact(Coordinator.native_threat_fact(fact))
	await get_tree().physics_frame
	var health := actor.get_node("HealthComponent")
	var published: Array = []
	var listener := func(amount: float, hp: float): published.append([amount, hp])
	health.healed.connect(listener)
	var completed := false
	for frame: int in range(211, 281):
		var actor_checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var before := effects.snapshot()
		observations.runtime_frame = frame
		observations.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
		var prepared: Dictionary = actor.prepare_launch_frame(frame, observations)
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": threats, "actors": {"hostile-temporal": actor}, "targets": {"player": player}}
		var effect: Dictionary = effects.prepare_effects([{"hostile_source_id": "hostile-temporal", "batch": prepared.batch}], context) if prepared.ok else {"ok": false}
		suite.assert_true(prepared.ok and effect.ok, "native self rewind prepares exact authored frame %d: actor=%s effect=%s" % [frame, str(prepared.get("context", {})), str(effect.get("context", {}))])
		if not prepared.ok or not effect.ok:
			if prepared.ok:
				actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(actor_checkpoint)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit(effect.ticket).ok, "native self rewind commits one staged frame")
		if frame == 280:
			completed = true
			suite.assert_equal(health.current_hp, 1150.0, "real Boss Health heals exactly one capped historical amount")
			suite.assert_equal(actor.global_position, Vector2(400.0 if blocked_landing else 131.0, 100.0), "real CharacterBody rejects occupied landing or bypasses travel-path obstacles")
			suite.assert_equal(runtime.snapshot().mechanism_state.hp_current, health.current_hp, "real Health and Boss domain agree after healing")
			suite.assert_equal(published, [], "candidate self rewind publishes no healing observation")
			suite.assert_true(effects.rollback(effect.ticket) and actor.rollback_launch_frame(prepared.ticket) and actor.restore_launch_transaction_snapshot(actor_checkpoint), "rejected native rewind restores Health, position, history and healing budget")
			suite.assert_equal(actor.global_position, Vector2(400.0, 100.0), "native rewind rejection restores the exact original body position")
			suite.assert_equal(health.current_hp, 1000.0, "native rewind rejection restores real Boss Health")
			suite.assert_equal(effects.snapshot(), before, "native rewind rejection restores the complete effect owner")
			prepared = actor.prepare_launch_frame(frame, observations)
			effect = effects.prepare_effects([{"hostile_source_id": "hostile-temporal", "batch": prepared.batch}], context)
			suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit(effect.ticket).ok, "same historical landing and healing retries once")
		suite.assert_true(actor.publish_launch_frame(prepared.ticket) and effects.publish_effect_observations(effect.ticket), "accepted native rewind publishes sealed observations")
		actor.discard_launch_transaction_snapshot(actor_checkpoint)
		await get_tree().physics_frame
	suite.assert_true(completed, "actual native seventy-frame rewind reaches one accepted restoration")
	suite.assert_equal(published, [[150.0, 1150.0]], "actual native rewind publishes exactly one capped healing observation")
	health.healed.disconnect(listener)
	actor.queue_free()
	room.queue_free()
	native_root.queue_free()
	player.queue_free()
	blocker.queue_free()
	await get_tree().process_frame
