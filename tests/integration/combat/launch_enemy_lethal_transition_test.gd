extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for id: String in ["chrono_guard", "eternal_hound"]:
		await _test_native_lethal(id)
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
