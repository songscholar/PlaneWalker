extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Fixture := preload("res://tests/unit/enemies/launch_enemy_runtime_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := await _actor()
	suite.assert_true(actor.has_method("can_publish_launch_frame"), "native actor preflights sealed publication")
	await _test_metadata_compensation(actor)
	await _test_same_frame_lethal_compensation(actor)
	await _test_stale_health_and_action_interrupt(actor)
	actor.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _actor() -> Node:
	var actor := Scene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var context := Actions.identity()
	context["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(Fixture.definition(), context).ok, "real native actor configures")
	actor.global_position = Vector2(100, 100)
	return actor


func _test_metadata_compensation(actor: Node) -> void:
	actor.set_meta("elemental_status_seed_initialized", 17)
	actor.set_meta("elemental_status_seed_material", "old-seed")
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	actor.set_meta("bow_time_erosion_sources", {"bow:1": {"stacks": 2, "time_damage_taken_per_stack": 0.15}})
	actor.set_meta("planewalker_replay_external_fact_claims", {"external:1": "digest"})
	actor.set_meta("elemental_status_seed_initialized", 23)
	actor.set_meta("elemental_status_seed_material", "new-seed")
	suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "frame-start actor compensation restores native weapon mutations")
	suite.assert_true(not actor.has_meta("bow_time_erosion_sources"), "bow erosion created in rejected frame is removed")
	suite.assert_true(not actor.has_meta("planewalker_replay_external_fact_claims"), "Replay target claim created in rejected frame is removed")
	suite.assert_equal(actor.get_meta("elemental_status_seed_initialized"), 17, "staff seed identity restores")
	suite.assert_equal(actor.get_meta("elemental_status_seed_material"), "old-seed", "staff seed material restores")


func _test_same_frame_lethal_compensation(actor: Node) -> void:
	var health := actor.get_node("HealthComponent")
	actor.apply_time_stop_source(&"stop:lethal", 3.0 / 60.0)
	actor.apply_elemental_status(&"burn", &"staff:lethal", 1, 30, 1.0, 30)
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var signal_ticket: Dictionary = health.begin_frame_signal_transaction(1)
	var receipts: Array = []
	var callback := func(source: StringName, receipt: String) -> void: receipts.append([source, receipt])
	actor.hostile_final_death.connect(callback)
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1", "attack_generation": 4, "action_token": 4, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"], "can_crit": false}))
	suite.assert_true(health.dead, "Player lethal damage stages native dead state before publication")
	var prepared: Dictionary = actor.prepare_launch_frame(1, Actions.context(1))
	suite.assert_true(prepared.ok, "same-frame lethal actor prepares terminal cancellation instead of rejecting Player frame")
	if prepared.ok:
		suite.assert_equal(prepared.batch.hit_facts, [], "same-frame defeated actor emits no attack")
		suite.assert_equal(prepared.batch.status_tick_requests, [], "same-frame defeated actor emits no burn tick")
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "native terminal candidate commits")
		suite.assert_true(actor.launch_runtime_snapshot().runtime.terminal, "terminal domain commits before public final-death receipt")
		suite.assert_equal(receipts, [], "terminal domain emits no premature defeat receipt")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "terminal actor candidate compensates")
	suite.assert_true(health.rollback_frame_signal_transaction(signal_ticket), "lethal native Health buffer compensates")
	suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "frame-start actor Health checkpoint restores life")
	suite.assert_true(health.is_alive() and actor.is_in_group("enemies"), "lethal rollback retains counted live body")
	suite.assert_true(not actor.launch_runtime_snapshot().runtime.terminal, "lethal rollback restores active domain")
	suite.assert_true(actor.is_time_stopped() and actor.has_elemental_status(&"burn", &"staff:lethal", 1), "lethal rollback restores original control and status ownership")
	suite.assert_equal(receipts, [], "lethal rollback publishes zero final receipts")
	actor.hostile_final_death.disconnect(callback)
	actor.clear_time_stop_source(&"stop:lethal")
	actor.clear_elemental_statuses()


func _test_stale_health_and_action_interrupt(actor: Node) -> void:
	var health := actor.get_node("HealthComponent")
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var prepared: Dictionary = actor.prepare_launch_frame(1, Actions.context(1))
	suite.assert_true(prepared.ok, "live candidate prepares after lethal compensation")
	if prepared.ok:
		health.current_hp -= 1.0
		suite.assert_true(not actor.can_commit_launch_frame(prepared.ticket), "Health mutation after observation invalidates actor candidate")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "stale candidate discards without losing external state")
	suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "external Health compensation restores frame start")
	actor.cancel_active_attack()
	suite.assert_true(not actor.launch_runtime_snapshot().runtime.terminal, "weapon interruption keeps actor domain live")
