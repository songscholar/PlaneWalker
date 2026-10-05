extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const RuntimePath := "res://scripts/enemies/launch/forest_auxiliary_runtime.gd"


func _ready() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(RuntimePath), "Forest sacs flowers seed cage erosion and drain require authoritative auxiliary domain")
	if not ResourceLoader.exists(RuntimePath):
		suite.finish(get_tree())
		return
	var parser := Definition.new()
	parser.configure(Fixtures.boss("forest_heart"))
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var implementation: Script = load(RuntimePath)
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "Forest auxiliary binds canonical authored definition")
	var initial: Dictionary = runtime.snapshot()
	suite.assert_equal(initial.sacs.size(), 4, "four actual HP30 sacs exist")
	suite.assert_equal(initial.flowers.size(), 3, "three one-use healing flowers exist")
	var selected: Dictionary = runtime.select_seed_sac({"x": 180.0, "y": 140.0})
	suite.assert_true(not selected.is_empty(), "seed selects deterministic nearest live sac")
	suite.assert_true(runtime.reserve_seed(7, selected.id, 0).ok, "real seed warning retains selected sac identity")
	var fact := {"fact_id": "destroy-marked-sac", "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "construct_id": selected.id, "runtime_frame": 0, "amount": 30.0}
	suite.assert_true(runtime.accept_damage_fact(fact).ok, "actual weapon damage destroys HP30 marked sac")
	suite.assert_true(not runtime.seed_burst(7, 0).ok, "destroying marked sac cancels its owned burst")
	suite.assert_true(not runtime.accept_damage_fact(fact).ok, "same real hit cannot damage a sac twice")
	suite.assert_true(runtime.consume_flower("forest_healing_flower:0", "player:1", 0, 13.0).ok, "flower retains actual partial heal once")
	suite.assert_true(not runtime.consume_flower("forest_healing_flower:0", "player:1", 0, 7.0).ok, "spent flower cannot heal again")
	var cage := _cage_geometry()
	suite.assert_true(runtime.spawn_cage(20, 0, cage, 1.0).ok, "three HP50 cage walls bind exact warned geometry")
	suite.assert_equal(runtime.snapshot().cages.size(), 3, "cage has exactly three native wall reservations")
	suite.assert_equal(runtime.cage_requests(0).size(), 1, "inner cage pulse receives its independent30-frame warning")
	for frame: int in range(1, 261):
		suite.assert_true(runtime.advance_frame(frame), "Forest auxiliary accepts exact sequential frame")
	suite.assert_equal(runtime.cage_requests(260).size(), 3, "cage expiration reserves three independently warned collapses")
	for frame: int in range(261, 301):
		runtime.advance_frame(frame)
	suite.assert_true(runtime.snapshot().cages.all(func(row: Dictionary): return row.expired), "native cage bodies expire after exactly300frames")
	suite.assert_true(runtime.accept_drain_receipt("drain0", 30, 0, 300, 60.0, 60.0).ok, "drain budgets authentic accepted loss")
	suite.assert_equal(runtime.drain_allowance(30, 60.0), 20.0, "drain heal cap is80percast")
	suite.assert_true(not runtime.accept_drain_receipt("drain1-forged", 30, 1, 300, 60.0, 21.0).ok, "drain refuses fabricated healing beyond remaining cast cap")
	suite.assert_true(runtime.accept_drain_receipt("drain1", 30, 1, 300, 60.0, 20.0).ok, "remaining actual-loss heal completes cast cap")
	suite.assert_true(runtime.accept_drain_receipt("drain2", 31, 0, 300, 80.0, 80.0).ok, "second authentic drain follows independent cast cap")
	suite.assert_equal(runtime.drain_allowance(32, 80.0), 40.0, "drain encounter cap is200")
	suite.assert_true(runtime.accept_erosion(40, 300).ok and runtime.accept_erosion(41, 300).ok, "two warned erosion decisions commit")
	suite.assert_true(not runtime.accept_erosion(42, 300).ok and runtime.snapshot().erosion_steps == 2, "edge erosion saturates at two16pxsteps")
	suite.assert_true(runtime.reserve_seed(50, "forest_spore_sac:1", 300).ok and runtime.cancel_seed(50, 300).ok, "primary interruption retains explicit seed cancellation")
	suite.assert_true(not runtime.seed_burst(50, 300).ok, "interrupted primary cannot leave an armed sac")
	var retained: Dictionary = runtime.snapshot()
	var cold: RefCounted = implementation.new()
	cold.configure(definition, identity)
	suite.assert_true(cold.restore_snapshot(retained) and cold.snapshot() == retained, "fresh Forest auxiliary reconstructs event-owned cold state")
	var forged := retained.duplicate(true)
	forged.sacs[1].current_hp -= 1.0
	suite.assert_true(not cold.restore_snapshot(forged) and cold.snapshot() == retained, "cold state cannot invent sac damage detached from accepted event")
	forged = retained.duplicate(true)
	forged.drain_healed_total += 1.0
	suite.assert_true(not cold.restore_snapshot(forged), "cold state cannot invent drain spending")
	suite.finish(get_tree())


func _cage_geometry() -> Array:
	var result: Array = []
	for row: Dictionary in [{"x": 280.0, "y": 160.0, "dx": 0.0, "dy": 1.0, "length": 48.0}, {"x": 328.0, "y": 160.0, "dx": 0.0, "dy": 1.0, "length": 48.0}, {"x": 280.0, "y": 208.0, "dx": 1.0, "dy": 0.0, "length": 16.0}]:
		result.append({"origin": {"x": row.x, "y": row.y}, "aim_direction": {"x": row.dx, "y": row.dy}, "length": row.length, "radius": 5.0})
	return result
