extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Health := preload("res://scripts/combat/health_component.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")

class StagingAttacker:
	extends Node
	var captures: Array[Dictionary] = []

	func stage_frame_damage_observation(info: RefCounted, target: Node, _amount: float) -> bool:
		var health := target.get_node("HealthComponent")
		captures.append(health.published_damage_observation_context(info))
		return true

var suite
var _events: Array = []
var _hit_contexts: Array[Dictionary] = []
var _owner: Node2D
var _health: Node
var _attacker: StagingAttacker
var _reenter := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	_health = Health.new()
	suite.assert_true(_health.has_method("published_damage_observation_context"), "Health frame transaction exposes immutable per-hit settlement observation")
	if not _health.has_method("published_damage_observation_context"):
		_health.free()
		suite.finish(get_tree())
		return
	_owner = Node2D.new()
	_health.name = "HealthComponent"
	_owner.add_child(_health)
	add_child(_owner)
	_attacker = StagingAttacker.new()
	add_child(_attacker)
	suite.assert_true(_health.configure_run(&"health-frame-run"), "real Health owns stable run identity")
	EventBus.damage_about_to_apply.connect(_on_about)
	EventBus.hit_confirmed.connect(_on_hit)
	EventBus.damage_applied.connect(_on_applied)
	_health.damaged.connect(_on_damaged)
	_test_legacy_synchronous_semantics()
	_test_buffered_multi_hit_and_reentrant_publication()
	_test_rollback_has_zero_public_observations()
	_test_discard_sealed_late_observations()
	EventBus.damage_about_to_apply.disconnect(_on_about)
	EventBus.hit_confirmed.disconnect(_on_hit)
	EventBus.damage_applied.disconnect(_on_applied)
	_owner.queue_free()
	_attacker.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _reset() -> void:
	_health.current_hp = 100.0
	_health.dead = false
	_events.clear()
	_hit_contexts.clear()
	_attacker.captures.clear()


func _test_legacy_synchronous_semantics() -> void:
	_reset()
	_health.take_damage(_damage(10.0, 1))
	suite.assert_equal(_events, ["about", "damaged", "hit", "applied"], "legacy direct Health emits the original synchronous order")
	suite.assert_equal(_attacker.captures, [], "legacy Health does not call frame-only internal staging")
	suite.assert_equal(_hit_contexts, [{}], "legacy observer accessor is empty outside a staged settlement")


func _test_buffered_multi_hit_and_reentrant_publication() -> void:
	_reset()
	var ticket: Dictionary = _health.begin_frame_signal_transaction(1)
	_health.take_damage(_damage(10.0, 2))
	_health.take_damage(_damage(20.0, 3))
	suite.assert_equal(_health.current_hp, 70.0, "real damage commits inside native buffer")
	suite.assert_equal(_events, [], "unpublished frame emits no combat observations")
	suite.assert_equal(_attacker.captures.size(), 2, "attacker stages internal facts once at each settlement")
	if _attacker.captures.size() == 2:
		suite.assert_equal(_attacker.captures[0].hp_before, 100.0, "first internal hit captures original HP")
		suite.assert_equal(_attacker.captures[0].hp_after, 90.0, "first internal hit captures its own HP result")
		suite.assert_equal(_attacker.captures[1].hp_before, 90.0, "second internal hit captures intermediate HP")
		suite.assert_equal(_attacker.captures[1].hp_after, 70.0, "second internal hit captures final HP")
		suite.assert_true(not _attacker.captures[0].internal_observation_recorded, "internal staging exposes pre-recorded context")
	var publication: Dictionary = _health.prepare_frame_signal_publication(ticket)
	suite.assert_true(_health.finalize_frame_signal_publication(publication), "staged frame seals native publication")
	_reenter = true
	_health.publish_prepared_frame_signals()
	suite.assert_equal(_hit_contexts.size(), 3, "reentrant hit cannot discard a sealed sibling hit")
	if _hit_contexts.size() == 3:
		suite.assert_true(_hit_contexts[0].internal_observation_recorded and _hit_contexts[1].internal_observation_recorded, "public hit marks already-recorded internal work")
		suite.assert_equal(_hit_contexts[0].hp_after, 90.0, "public first hit does not read live final HP")
		suite.assert_equal(_hit_contexts[1].hp_after, 70.0, "sealed second hit retains immutable original result")
		suite.assert_equal(_hit_contexts[2].hp_after, 65.0, "reentrant hit publishes after the original batch")
	suite.assert_equal(_health.published_damage_observation_context(_damage(1.0, 20)), {}, "accessor does not leak the last observer context")


func _test_rollback_has_zero_public_observations() -> void:
	_reset()
	var checkpoint: Dictionary = _health.transaction_snapshot()
	var ticket: Dictionary = _health.begin_frame_signal_transaction(2)
	_health.take_damage(_damage(200.0, 5))
	suite.assert_true(_health.dead, "lethal state commits while publication remains buffered")
	suite.assert_equal(_events, [], "lethal preparation emits no combat or damaged observation")
	suite.assert_true(_health.rollback_frame_signal_transaction(ticket), "native observation buffer rolls back")
	suite.assert_true(_health.restore_transaction_snapshot(checkpoint), "external Health owner restores HP and ledger")
	_health.publish_prepared_frame_signals()
	suite.assert_equal(_health.current_hp, 100.0, "rollback restores real HP")
	suite.assert_true(not _health.dead, "rollback restores live state")
	suite.assert_equal(_events, [], "discarded frame publishes zero public observations")


func _damage(amount: float, generation: int) -> RefCounted:
	return Damage.from_plan({"run_id": "health-frame-run", "target_id": "target:a", "hostile_source_id": "source:a", "attack_generation": generation, "hit_index": 0, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["enemy:melee"], "can_crit": false, "attacker": _attacker, "source": _attacker})


func _test_discard_sealed_late_observations() -> void:
	_reset()
	var checkpoint: Dictionary = _health.transaction_snapshot()
	var ticket: Dictionary = _health.begin_frame_signal_transaction(3)
	_health.take_damage(_damage(10.0, 6))
	var publication: Dictionary = _health.prepare_frame_signal_publication(ticket)
	suite.assert_true(_health.finalize_frame_signal_publication(publication), "late world settlement begins after native publication finalization")
	_health.take_damage(_damage(5.0, 7))
	suite.assert_equal(_events, [], "late prepublication damage remains staged")
	suite.assert_true(_health.discard_finalized_frame_signal_publication(publication), "rejected world settlement discards finalized health publication")
	suite.assert_true(_health.restore_transaction_snapshot(checkpoint), "late world damage HP compensates")
	var next_ticket: Dictionary = _health.begin_frame_signal_transaction(4)
	var next_publication: Dictionary = _health.prepare_frame_signal_publication(next_ticket)
	_health.finalize_frame_signal_publication(next_publication)
	_health.publish_prepared_frame_signals()
	suite.assert_equal(_events, [], "discarded late observations cannot leak into the next accepted frame")


func _on_about(_info: RefCounted, target: Node) -> void:
	if target == _owner:
		_events.append("about")


func _on_damaged(_amount: float, _hp: float) -> void:
	_events.append("damaged")


func _on_hit(info: RefCounted, target: Node, _amount: float) -> void:
	if target != _owner:
		return
	_events.append("hit")
	_hit_contexts.append(_health.published_damage_observation_context(info))
	if _reenter:
		_reenter = false
		_health.take_damage(_damage(5.0, 4))


func _on_applied(_info: RefCounted, target: Node, _amount: float) -> void:
	if target == _owner:
		_events.append("applied")
