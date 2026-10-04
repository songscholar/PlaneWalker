extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for id: String in ["chrono_guard", "eternal_hound"]:
		await _test_native_lethal(id)
		await _test_buffered_recovery(id)
	suite.finish(get_tree())


func _hit(generation: int) -> RefCounted:
	return Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"], "can_crit": false})


func _test_native_lethal(id: String) -> void:
	var scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene
	var actor := scene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var definition := Definition.new()
	definition.configure(Content.enemy(id))
	var identity := Fixtures.identity()
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(definition.runtime_projection(), identity).ok, "native lethal actor configures: " + id)
	var health := actor.get_node("HealthComponent")
	var receipts: Array = []
	var observations: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): receipts.append([source, receipt]))
	health.damaged.connect(func(_amount: float, hp: float):
		observations.append({"hp": hp, "state": actor.launch_runtime_snapshot().runtime.mechanism_state.duplicate(true)})
		if observations.size() == 1:
			health.take_damage(_hit(99))
	)
	var incoming := _hit(1)
	var before: Dictionary = actor.launch_runtime_snapshot()
	if actor.has_method("prepare_hostile_lethal_transition"):
		var decision: Dictionary = actor.prepare_hostile_lethal_transition(incoming, 1000.0)
		suite.assert_equal(actor.launch_runtime_snapshot(), before, "lethal preparation is observation-only")
		suite.assert_true(not actor.commit_hostile_lethal_transition(incoming, 1000.0, decision), "caller cannot invoke unowned Health lethal commit")
	health.take_damage(incoming)
	suite.assert_true(not health.dead and health.current_hp == 1.0, "first actual lethal holds native HP at one: " + id)
	suite.assert_equal(receipts.size(), 0, "nonterminal lethal emits zero counted death receipts")
	suite.assert_equal(observations.size(), 1, "same lethal signal publication cannot reenter native damage")
	if not health.dead:
		var state: Dictionary = actor.launch_runtime_snapshot().runtime.mechanism_state
		var flag := "revival_used" if id == "chrono_guard" else "dormancy_used"
		suite.assert_true(state[flag] and observations[0].state[flag], "once-only flag is consumed before damaged observation")
		suite.assert_true(actor.is_in_group("enemies"), "nonterminal body remains counted")
		var checkpoint: Dictionary = actor.launch_transaction_snapshot()
		if id == "chrono_guard":
			health.take_damage(_hit(2))
			suite.assert_true(health.dead, "second Guard lethal follows default final death")
			suite.assert_equal(receipts.size(), 1, "final Guard death has one authenticated receipt")
		else:
			health.take_damage(_hit(2))
			suite.assert_true(not health.dead and health.current_hp == 1.0, "dormant Hound body cannot bypass destructible sigil")
			suite.assert_equal(receipts.size(), 0, "dormant body does not clear room")
		actor.discard_launch_transaction_snapshot(checkpoint)
	actor.queue_free()
	await get_tree().process_frame


func _test_buffered_recovery(id: String) -> void:
	var actor := (load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene).instantiate()
	add_child(actor)
	var definition := Definition.new()
	definition.configure(Content.enemy(id))
	var identity := Fixtures.identity()
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(definition.runtime_projection(), identity).ok, "buffered recovery source configures")
	actor.global_position = Vector2(100, 100)
	actor.apply_time_stop_source(&"buffered-recovery-stop", 20.0)
	var health: Node = actor.get_node("HealthComponent")
	var duration := 90 if id == "chrono_guard" else 300
	var timer := "recovery_remaining_frames" if id == "chrono_guard" else "dormancy_remaining_frames"
	var restored_hp := 54.0 if id == "chrono_guard" else 35.0
	var observations: Array = []
	var heals: Array = []
	var receipts: Array = []
	health.damaged.connect(func(_amount: float, hp: float): observations.append(hp))
	health.healed.connect(func(amount: float, hp: float): heals.append([amount, hp]))
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): receipts.append([source, receipt]))
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	for frame: int in range(1, duration + 2):
		var signal_ticket: Dictionary = {}
		if frame == 1:
			var before: Dictionary = actor.launch_runtime_snapshot()
			var checkpoint: Dictionary = actor.launch_transaction_snapshot()
			signal_ticket = health.begin_frame_signal_transaction(frame)
			health.take_damage(_hit(1))
			var first: Dictionary = actor.prepare_launch_frame(frame, Fixtures.context(frame))
			suite.assert_true(first.ok, "same lethal fixed frame prepares")
			if first.ok:
				suite.assert_equal(first.ticket.after.runtime.mechanism_state[timer], duration, "lethal frame retains full authored recovery duration: " + id)
				actor.rollback_launch_frame(first.ticket)
			suite.assert_true(health.rollback_frame_signal_transaction(signal_ticket), "buffered lethal observation rolls back")
			suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "lethal flag and Health roll back together")
			suite.assert_equal(actor.launch_runtime_snapshot(), before, "lethal rollback restores exact native state")
			suite.assert_equal(observations.size(), 0, "rolled-back lethal never publishes damage")
			actor.discard_launch_transaction_snapshot(checkpoint)
			signal_ticket = health.begin_frame_signal_transaction(frame)
			health.take_damage(_hit(1))
		var prepared: Dictionary = actor.prepare_launch_frame(frame, Fixtures.context(frame))
		suite.assert_true(prepared.ok, "buffered recovery advances sequential native frame")
		if not prepared.ok:
			break
		suite.assert_true(prepared.batch.hit_facts.is_empty(), "Stop does not pause recovery or enable attacks")
		var routed: Dictionary = effects.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": {"hostile:test-a": actor}, "targets": {}})
		suite.assert_true(routed.ok, "actual recovery request reaches native semantic Router")
		if not routed.ok:
			actor.rollback_launch_frame(prepared.ticket)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "recovery actor commits")
		suite.assert_true(effects.commit_effects(routed.ticket).ok, "native recovery Health sink commits")
		actor.publish_launch_frame(prepared.ticket)
		effects.publish_effects(routed.ticket)
		if not signal_ticket.is_empty():
			var publication: Dictionary = health.prepare_frame_signal_publication(signal_ticket)
			suite.assert_true(health.finalize_frame_signal_publication(publication), "accepted lethal frame finalizes damage observation")
			health.publish_prepared_frame_signals()
		var expected_remaining: int = maxi(0, duration - frame + 1)
		suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state[timer], expected_remaining, "recovery measures full elapsed frames after lethal: " + id)
		suite.assert_equal(health.current_hp, 1.0 if frame <= duration else restored_hp, "native HP restores exactly after authored interval: " + id)
	suite.assert_equal(observations, [1.0], "retried lethal publishes exactly once")
	suite.assert_equal(heals, [[restored_hp - 1.0, restored_hp]], "recovery publishes one actual native gain")
	suite.assert_equal(receipts.size(), 0, "recovery retains counted parent throughout")
	health.take_damage(_hit(2))
	suite.assert_true(health.dead, "accepted recovery cannot grant a second nonterminal lethal")
	suite.assert_equal(receipts.size(), 1, "second lethal publishes one counted final receipt")
	actor.queue_free()
	root.queue_free()
	await get_tree().process_frame
