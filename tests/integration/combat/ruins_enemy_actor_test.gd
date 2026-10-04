extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Definitions := preload("res://tests/unit/enemies/ruins_enemy_mechanisms_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var strider_scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_stone_shell_strider.tscn") as PackedScene
	suite.assert_true(strider_scene != null, "native Strider raster scene exists")
	if strider_scene != null:
		await _test_strider_health_and_compensation(strider_scene)
	var wraith_scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_ruins_wraith.tscn") as PackedScene
	suite.assert_true(wraith_scene != null, "native Wraith raster scene exists")
	if wraith_scene != null:
		await _test_wraith_health_interrupt(wraith_scene)
	suite.finish(get_tree())


func _actor(scene: PackedScene, definition: Dictionary) -> Node:
	var actor := scene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var identity := Actions.identity()
	identity["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "native Ruins species installs verified domain")
	actor.global_position = Vector2(100, 100)
	return actor


func _damage(generation: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1", "attack_generation": generation, "hit_index": 0, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})


func _test_strider_health_and_compensation(scene: PackedScene) -> void:
	var actor := await _actor(scene, Definitions.strider_definition())
	var health := actor.get_node("HealthComponent")
	health.take_damage(_damage(1, 20.0))
	suite.assert_equal(health.current_hp, 100.0, "first real Health hit precedes closed-shell reduction")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state.shell_remaining_frames, 120, "synchronous real hit stages species shell")
	health.take_damage(_damage(2, 20.0))
	suite.assert_equal(health.current_hp, 94.0, "second real Health hit resolves thirty-percent shell damage")
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var health_ticket: Dictionary = health.begin_frame_signal_transaction(1)
	health.take_damage(_damage(3, 10.0))
	var prepared: Dictionary = actor.prepare_launch_frame(1, Actions.context(1))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket), "native shell and Health damage join accepted-frame candidate")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state.shell_remaining_frames, 119, "native shell lifetime advances once per accepted frame")
	actor.rollback_launch_frame(prepared.ticket)
	health.rollback_frame_signal_transaction(health_ticket)
	suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "rejected shell frame restores Health and mechanism claims")
	suite.assert_equal(health.current_hp, 94.0, "shell compensation restores resolved HP")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state.damage_claims.size(), 2, "shell compensation removes rejected incoming damage claim")
	actor.queue_free()
	await get_tree().process_frame


func _test_wraith_health_interrupt(scene: PackedScene) -> void:
	var actor := await _actor(scene, Definitions.wraith_definition())
	var runtime: RefCounted = actor.get("_launch_runtime")
	suite.assert_true(runtime.request_action("ruins_wraith.spirit_detonation", Actions.context()).ok, "native Wraith commits warned detonation through real coordinator")
	var health := actor.get_node("HealthComponent")
	health.take_damage(_damage(1, 7.0))
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.phase, "WARNING", "seven real damage does not cancel warning")
	health.take_damage(_damage(2, 8.0))
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.phase, "IDLE", "fifteen accumulated real damage cancels warning synchronously")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state.stagger_remaining_frames, 30, "real Health damage enters bounded Wraith stagger")
	var before: Dictionary = actor.launch_runtime_snapshot()
	actor._physics_process(1.0)
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "native Wraith presentation cannot advance stagger")
	actor.queue_free()
	await get_tree().process_frame
