extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Arena := preload("res://scripts/enemies/launch/void_arena_runtime.gd")


func _ready() -> void:
	var suite := Suite.new()
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	var identity := {"run_id": "run-dead-heal", "hostile_source_id": "void-dead-heal", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	var arena := Arena.new()
	arena.configure(parser.runtime_projection(), identity)
	arena.accept_phase(2, 0)
	suite.assert_true(not arena.accept_player_heal(identity.run_id, "player:1", 0, 100.0, 30.0, false).ok, "dead Player receives no revival heal")
	suite.assert_true(arena.accept_player_heal(identity.run_id, "player:1", 0, 100.0, 0.0, false).ok, "dead Player permanently consumes P3heal without revival")
	suite.assert_true(not arena.player_heal_pending(), "dead P3heal never stays pending for external revival")
	suite.assert_true(not arena.accept_player_heal(identity.run_id, "player:1", 0, 100.0, 30.0, true).ok, "later external revival cannot replay one-shotP3heal")
	suite.assert_true(arena.can_restore_snapshot(arena.snapshot(), true), "zero deadheal receipt cold-reconstructs exact permanent consumption")
	suite.finish(get_tree())
