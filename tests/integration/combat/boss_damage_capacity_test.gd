extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Identity := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_void_throne.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	var scaled := Definition.difficulty_projection(parser.runtime_projection(), 3.0, 2.0)
	suite.assert_true(scaled.ok, "minimum-hit gate uses the actual maximum endless Boss difficulty")
	var actor := _actor(scaled.definition, suite)
	var first := _damage(1)
	var accepted := 0
	for generation: int in range(1, 9001):
		var result: float = actor.health.take_damage(_damage(generation))
		if not is_equal_approx(result, 1.0):
			suite.assert_close(result, 1.0, "actual native minimum damage remains admissible at component %d" % generation)
			break
		accepted += 1
		if generation == 513:
			var before: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
			suite.assert_close(actor.health.take_damage(first), 0.0, "earliest accepted damage remains spent after historical 512 boundary")
			suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), before, "repeated oldest component cannot change native HP or cold state")
			var encoded := Replay.encode_replay_json(before)
			var fresh := _actor(scaled.definition, suite)
			suite.assert_true(encoded.ok and fresh.restore_native_cold_snapshot(Replay.decode_replay_json(encoded.json).replay, func(_binding: Dictionary): return null), "fresh actual Boss reconstructs an extended typed damage ledger")
			suite.assert_close(fresh.health.take_damage(first), 0.0, "fresh cold reconstruction retains earliest settled identity")
			suite.assert_equal(fresh.native_cold_snapshot(func(_node: Node): return {}), before, "cold reconstruction and duplicate refusal preserve exact native state")
			fresh.queue_free()
	suite.assert_equal(accepted, 9000, "all 9000 minimum native components can defeat maximum endless HP")
	suite.assert_close(actor.health.current_hp, 0.0, "maximum endless Boss reaches actual zero Health")
	suite.assert_true(actor.launch_runtime_snapshot().runtime.terminal, "minimum-hit completion retires the actual Boss domain")
	if is_instance_valid(actor):
		actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _actor(definition: Dictionary, suite) -> Node2D:
	var actor := BossScene.instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(320, 144)
	var identity := Identity.identity()
	identity.seed = 42
	identity.hostile_source_id = "boss-capacity"
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actual maximum difficulty Void Boss configures")
	suite.assert_close(actor.health.max_hp, 9000.0, "actual maximum endless Boss owns 9000 Health")
	return actor


func _damage(generation: int) -> RefCounted:
	return Damage.from_plan({"run_id": "run-p15", "target_id": "boss-capacity", "hostile_source_id": "domain:minimum-hit", "attack_generation": generation, "action_token": generation, "amount": 0.001, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
