extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_chrono_guard.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_actual_zone_damage()
	suite.finish(get_tree())


func _test_actual_zone_damage() -> void:
	var actor := ActorScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(100.0, 100.0)
	var parser := Enemy.new()
	parser.configure(Content.enemy("chrono_guard"))
	var identity := Fixtures.identity()
	identity.hostile_source_id = "hostile:zone"
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "actual Chrono Guard configures authored semantic zone")
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(140.0, 100.0)
	var health := player.get_node("HealthComponent")
	health.current_hp = 100.0
	health.defense = 0.0
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15", 0) and effects.configure_native_payloads(native_root), "shared Router binds both native effect authorities")
	var threats := Threats.new()
	var observations := Fixtures.context()
	observations.source_position = {"x": 100.0, "y": 100.0}
	observations.target_position = {"x": 140.0, "y": 100.0}
	observations.target_id = "player"
	var started: Dictionary = actor.get("_launch_runtime").request_action("chrono_guard.rift_slash", observations)
	suite.assert_true(started.ok, "actual zone attack starts with complete primary warning")
	for fact: Dictionary in started.threat_facts:
		threats.register_fact(Actions.native_threat_fact(fact))
	var published: Array = []
	var listener := func(amount: float, hp: float): published.append([amount, hp])
	health.damaged.connect(listener)
	var completed := false
	await get_tree().physics_frame
	for frame: int in range(1, 36):
		var actor_checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var health_checkpoint: Dictionary = health.transaction_snapshot()
		var before := effects.snapshot()
		var registry_before: Array = threats.snapshot()
		observations.runtime_frame = frame
		var prepared: Dictionary = actor.prepare_launch_frame(frame, observations)
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": threats, "actors": {"hostile:zone": actor}, "targets": {"player": player}}
		var effect: Dictionary = effects.prepare_effects([{"hostile_source_id": "hostile:zone", "batch": prepared.batch}], context) if prepared.ok else {"ok": false}
		suite.assert_true(prepared.ok and effect.ok, "shared Router prepares actual zone frame %d: %s" % [frame, str(effect.get("context", {}))])
		if not prepared.ok or not effect.ok:
			if prepared.ok:
				actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(actor_checkpoint)
			health.restore_transaction_snapshot(health_checkpoint)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit(effect.ticket).ok, "shared Router applies one staged native zone frame")
		if frame < 35:
			suite.assert_equal(health.current_hp, 100.0, "complete zone warning deals no early native damage")
		else:
			completed = true
			suite.assert_equal(health.current_hp, 72.0, "actual slash corridor damages Player exactly once for twenty-eight")
			suite.assert_equal(effects.native_semantic_nodes().size(), 1, "shared Router owns one real native zone projection")
			suite.assert_equal(threats.snapshot().size(), registry_before.size() + 1, "secondary native corridor registers its full hostile envelope")
			suite.assert_equal(published, [], "candidate native zone damage publishes no observation")
			suite.assert_true(effects.rollback(effect.ticket) and actor.rollback_launch_frame(prepared.ticket), "rejected native zone compensates registry, status and projection")
			suite.assert_true(actor.restore_launch_transaction_snapshot(actor_checkpoint) and health.restore_transaction_snapshot(health_checkpoint), "native owners restore rejected actual damage")
			suite.assert_equal(effects.snapshot(), before, "zone rejection restores complete child authority checkpoints")
			suite.assert_equal(threats.snapshot(), registry_before, "zone rejection restores primary warning without orphaned facts")
			suite.assert_equal(effects.native_semantic_nodes().size(), 0, "zone rejection hides every candidate native projection")
			prepared = actor.prepare_launch_frame(frame, observations)
			effect = effects.prepare_effects([{"hostile_source_id": "hostile:zone", "batch": prepared.batch}], context)
			suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit(effect.ticket).ok, "same zone frame retries exactly once")
		suite.assert_true(actor.publish_launch_frame(prepared.ticket) and effects.publish_effect_observations(effect.ticket), "shared Router publishes sealed native zone frame")
		actor.discard_launch_transaction_snapshot(actor_checkpoint)
		health.discard_transaction_snapshot(health_checkpoint)
		await get_tree().physics_frame
	suite.assert_true(completed, "actual zone reaches its authored active frame")
	suite.assert_equal(published, [[28.0, 72.0]], "actual zone publishes exactly one accepted damage observation")
	health.damaged.disconnect(listener)
	actor.queue_free()
	player.queue_free()
	native_root.queue_free()
	await get_tree().process_frame
