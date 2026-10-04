extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_stone_shell_strider.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Definitions := preload("res://tests/unit/enemies/ruins_enemy_mechanisms_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var domain: RefCounted = Runtime.new()
	suite.assert_true(domain.has_method("charge_contact_fact"), "native charge derives authenticated contact facts from its committed action")
	if domain.has_method("charge_contact_fact"):
		_test_charge_motion_and_stop(domain)
		await _test_native_contact_and_wall(false)
		await _test_native_contact_and_wall(true)
	suite.finish(get_tree())


func _identity() -> Dictionary:
	var identity := Actions.identity()
	identity["seed"] = 42
	return identity


func _context(frame: int, position: Vector2 = Vector2(100, 100)) -> Dictionary:
	var result := Actions.context(frame)
	result.source_position = {"x": position.x, "y": position.y}
	result.target_position = {"x": 148.0, "y": 100.0}
	return result


func _test_charge_motion_and_stop(domain: RefCounted) -> void:
	suite.assert_true(domain.configure(Definitions.strider_definition(), _identity()).ok, "charge domain consumes actual Strider action")
	domain.request_action("stone_shell_strider.shell_charge", _context(0))
	var position := Vector2(100, 100)
	for frame: int in range(1, 30):
		suite.assert_equal(domain.motion_for_frame(frame, _context(frame, position)).displacement, {"x": 0.0, "y": 0.0}, "complete charge warning remains stationary")
		domain.advance_frame(frame, _context(frame, position), false)
	var first_motion: Dictionary = domain.motion_for_frame(30, _context(30, position))
	suite.assert_equal(first_motion.displacement, {"x": 4.0, "y": 0.0}, "charge begins at the first active frame using authored speed")
	domain.add_control_source("stop:charge", "stop", 2, 1.0)
	for frame: int in range(30, 32):
		suite.assert_equal(domain.motion_for_frame(frame, _context(frame, position)).displacement, {"x": 0.0, "y": 0.0}, "Stop postpones actual charge movement")
		domain.advance_frame(frame, _context(frame, position), false)
	for frame: int in range(32, 44):
		var motion: Dictionary = domain.motion_for_frame(frame, _context(frame, position))
		position += Vector2(motion.displacement.x, motion.displacement.y)
		domain.advance_frame(frame, _context(frame, position), false)
	suite.assert_equal(position, Vector2(148, 100), "twelve active frames traverse exactly the authored forty-eight pixels")
	suite.assert_equal(domain.motion_for_frame(44, _context(44, position)).displacement, {"x": 0.0, "y": 0.0}, "recovery cannot continue charge travel")
	suite.assert_true(domain.charge_contact_fact(43, "foreign-target").is_empty(), "charge contact cannot redirect its committed target")


func _test_native_contact_and_wall(with_wall: bool) -> void:
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(148, 100)
	var actor := ActorScene.instantiate()
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.configure_launch_definition(Definitions.strider_definition(), _identity())
	actor.global_position = Vector2(100, 100)
	var wall: StaticBody2D
	if with_wall:
		wall = StaticBody2D.new()
		wall.collision_layer = 1
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(4, 64)
		collider.shape = shape
		wall.add_child(collider)
		add_child(wall)
		wall.global_position = Vector2(120, 100)
	await get_tree().physics_frame
	var registry: RefCounted = Registry.new()
	var started: Dictionary = actor.get("_launch_runtime").request_action("stone_shell_strider.shell_charge", _context(0))
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(Coordinator.native_threat_fact(fact))
	var effects: RefCounted = Effects.new()
	effects.configure("run-p15")
	var health := player.get_node("HealthComponent")
	var initial_hp: float = health.current_hp
	var hits: Array = []
	var observer := func(_info: RefCounted, target: Node, amount: float):
		if target == player:
			hits.append(amount)
	EventBus.hit_confirmed.connect(observer)
	var retried_contact := false
	for frame: int in range(1, 43):
		var checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var player_checkpoint: Dictionary = health.transaction_snapshot()
		var before_hp: float = health.current_hp
		var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(frame, actor.global_position))
		suite.assert_true(prepared.ok, "native Strider prepares charge warning, contact, and recovery")
		if not prepared.ok:
			actor.restore_launch_transaction_snapshot(checkpoint)
			health.discard_transaction_snapshot(player_checkpoint)
			break
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": {"hostile:test-a": actor}, "targets": {"player:1": player}}
		var effect: Dictionary = effects.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
		suite.assert_true(effect.ok, "native charge effect resolves only authenticated sealed contact")
		if not effect.ok:
			actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(checkpoint)
			health.discard_transaction_snapshot(player_checkpoint)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "real charge motion and contact Health commit")
		if frame == 30:
			suite.assert_equal(health.current_hp, initial_hp, "charge warning envelope does not cause instant full-corridor damage")
		if health.current_hp < before_hp and not retried_contact:
			retried_contact = true
			suite.assert_equal(hits, [], "charge contact damage remains unpublished before acceptance")
			suite.assert_true(effects.rollback_effects(effect.ticket) and actor.rollback_launch_frame(prepared.ticket), "rejected charge contact compensates claims and native motion")
			suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint) and health.restore_transaction_snapshot(player_checkpoint), "charge contact restores both real Health checkpoints")
			suite.assert_equal(health.current_hp, initial_hp, "rejected charge contact restores exact target HP")
			checkpoint = actor.launch_transaction_snapshot()
			player_checkpoint = health.transaction_snapshot()
			prepared = actor.prepare_launch_frame(frame, _context(frame, actor.global_position))
			effect = effects.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
			suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "exact charge contact frame retries deterministically")
		suite.assert_true(actor.publish_launch_frame(prepared.ticket) and effects.publish_effect_observations(effect.ticket), "native charge observations publish once after acceptance")
		actor.discard_launch_transaction_snapshot(checkpoint)
		health.discard_transaction_snapshot(player_checkpoint)
	if with_wall:
		suite.assert_equal(health.current_hp, initial_hp, "real wall stops charge and protects Player behind its warning envelope")
		suite.assert_equal(hits, [], "blocked charge emits zero hit observations")
		suite.assert_true(actor.global_position.x < 108.0, "native Strider body cannot cross the real wall")
	else:
		suite.assert_equal(health.current_hp, initial_hp - 15.0, "authored charge settles fifteen damage once on actual contact")
		suite.assert_equal(hits, [15.0], "repeated active-frame overlap cannot repeat charge damage")
		suite.assert_true(retried_contact and actor.global_position.x > 120.0, "real charge reaches its Player collision and exercises rollback retry")
	EventBus.hit_confirmed.disconnect(observer)
	actor.queue_free()
	player.queue_free()
	if wall != null:
		wall.queue_free()
	await get_tree().process_frame
