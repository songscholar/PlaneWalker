extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixture := preload("res://tests/unit/enemies/launch_enemy_runtime_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene
	suite.assert_true(scene != null, "P15 Sentinel native raster scene exists")
	if scene != null:
		await _test_actor(scene)
	suite.finish(get_tree())


func _test_actor(scene: PackedScene) -> void:
	var actor := scene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var context := Actions.identity()
	context["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(Fixture.definition(), context).ok, "native actor accepts verified domain projection")
	actor.global_position = Vector2(100, 100)
	var sprite := actor.get_node("Sprite2D") as Sprite2D
	suite.assert_true(sprite.texture != null and sprite.texture.get_width() == 128, "native actor uses generated four-frame bitmap")
	suite.assert_true(not actor.get_node("Visual").visible, "compatibility polygon is hidden")
	suite.assert_true(actor.get_node("CollisionShape2D").shape != null and actor.get_node("Hurtbox/CollisionShape2D").shape != null, "actor has real body and hurtbox collision")
	var before: Dictionary = actor.launch_runtime_snapshot()
	actor._physics_process(4.0)
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "physics projection cannot advance gameplay")
	actor.apply_time_stop_source(&"stop:native", 3.0 / 60.0)
	actor.apply_weakpoint(2.0 / 60.0, 0.25)
	suite.assert_true(actor.apply_damage_vulnerability(&"vulnerability:native", 3, 0.20), "native vulnerability uses frame lifetime")
	var health := actor.get_node("HealthComponent")
	var info := Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 10.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"], "can_crit": false})
	suite.assert_true(info != null, "incoming native damage has stable immutable identity")
	health.take_damage(info)
	suite.assert_true(is_equal_approx(health.current_hp, 65.0), "HealthComponent resolves native weakpoint and vulnerability")
	var ticket_result: Dictionary = actor.prepare_launch_frame(1, Actions.context(1))
	suite.assert_true(ticket_result.ok, "native actor prepares accepted frame")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.runtime_frame, 0, "prepare does not advance live domain")
	suite.assert_true(actor.commit_launch_frame(ticket_result.ticket), "prepared actor frame commits")
	suite.assert_true(actor.is_time_stopped(), "committed Stop remains active")
	suite.assert_true(actor.rollback_launch_frame(ticket_result.ticket), "actor frame compensation restores state")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.runtime_frame, 0, "rollback restores accepted frame")
	suite.assert_true(actor.apply_elemental_status(&"burn", &"staff:a", 3, 60, 2.0, 30, -1.0, actor, actor), "actor accepts real elemental helper")
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	actor.clear_elemental_statuses()
	suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "native rollback restores elemental clocks and source references")
	suite.assert_true(actor.has_elemental_status(&"burn", &"staff:a", 3), "restored native burn remains owned")
	suite.assert_true(not actor.restore_launch_transaction_snapshot(checkpoint), "health compensation consumes frozen ledger checkpoint once")
	var discard_checkpoint: Dictionary = actor.launch_transaction_snapshot()
	suite.assert_true(actor.discard_launch_transaction_snapshot(discard_checkpoint), "unused native compensation checkpoint releases ledger ticket")
	var signals: Array = []
	actor.hostile_final_death.connect(func(source_id: StringName, receipt_id: String): signals.append([source_id, receipt_id]))
	health.take_damage(Damage.new(1000.0))
	suite.assert_equal(signals.size(), 1, "HealthComponent final death emits one stable encounter receipt")
	suite.assert_true(actor.launch_runtime_snapshot().runtime.terminal, "native death cancels authoritative domain")
	suite.assert_true(not actor.is_time_stopped(), "native final death clears control sources")
	suite.assert_equal(actor.elemental_status_snapshot().source_count, 0, "native final death clears elemental sources")
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
