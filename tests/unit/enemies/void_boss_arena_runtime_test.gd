extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")


func _ready() -> void:
	var suite := Suite.new()
	var parser := Definition.new()
	parser.configure(Fixtures.boss("void_throne"))
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	suite.assert_true(runtime.snapshot().has("void_arena_state"), "actual Boss runtime must own strict Void pillar and core state")
	if not runtime.snapshot().has("void_arena_state"):
		suite.finish(get_tree())
		return
	suite.assert_true(runtime.accept_damage_fact({"fact_id": "enter-p3", "runtime_frame": 1, "target_source_id": identity.hostile_source_id, "amount": 2500.0, "hp_after": 500.0}).ok, "authentic bodyloss directly transitions toP3")
	suite.assert_equal(runtime.snapshot().void_arena_state.cores.size(), 4, "actual P3 body transition creates four plane cores")
	suite.assert_true(runtime.advance_frame(1, Actions.context(1), false).ok, "actual core-bearing Boss accepts the Player frame")
	for frame: int in range(2, 62):
		runtime.advance_frame(frame, Actions.context(frame), false)
	var historical := runtime.snapshot()
	historical.schema_version = 1
	historical.erase("void_arena_state")
	historical.erase("void_auxiliary")
	historical.erase("void_half_index")
	suite.assert_true(runtime.request_action("voidking_existence_denial", Actions.context(61)).ok, "actual denial owns a fully warned attackgeneration")
	var result: Dictionary = runtime.accept_void_arena_damage({"fact_id": "break-core", "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "construct_id": "void_plane_core:1:0", "runtime_frame": 62, "amount": 100.0})
	suite.assert_true(result.ok and result.body_damage == 100.0 and not result.retired_generations.is_empty(), "accepted corebreak interrupts the actual denial generation")
	suite.assert_equal(runtime.snapshot().action.phase, "IDLE", "denial interruption removes its committed warning")
	suite.assert_true(runtime.is_exposed() and runtime.species_damage_taken_multiplier() == 1.5, "actual core exposure changes outerbody multiplier from0.6to1.5")
	suite.assert_true(runtime.extend_character_boss_exposure(30, 10), "actual core exposure preserves Character conversion")
	suite.assert_true(runtime.advance_frame(62, Actions.context(62), false).ok, "core interruption commits at its actual Player boundary")
	var state := runtime.snapshot()
	var cold := Runtime.new()
	cold.configure(definition, identity)
	suite.assert_true(cold.restore_snapshot(state) and cold.snapshot() == state and cold.can_restore_native_snapshot(state), "fresh actual Boss reconstructs corebreak and interrupted generation")
	var forged := state.duplicate(true)
	forged.void_arena_state.cores[1].current_hp = 0.0
	suite.assert_true(not cold.restore_snapshot(forged) and cold.snapshot() == state, "Boss restore refuses forged coredamage atomically")
	forged = state.duplicate(true)
	forged.void_arena_state.phase_index = 1
	suite.assert_true(not cold.restore_snapshot(forged), "Bossphase and arena-phase must agree")
	var normalized: Dictionary = cold.normalize_native_snapshot(historical)
	suite.assert_true(not normalized.is_empty() and normalized.void_arena_state.core_break_claims.is_empty() and normalized.void_arena_state.cores.size() == 4, "historical Boss schema1 receives explicit corelessP3 defaults")
	suite.finish(get_tree())
