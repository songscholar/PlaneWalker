extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const RuntimePath := "res://scripts/enemies/launch/void_arena_runtime.gd"


func _ready() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(RuntimePath), "Void pillars and two finite core rounds need an authenticated arena domain")
	if not ResourceLoader.exists(RuntimePath):
		suite.finish(get_tree())
		return
	var parser := Definition.new()
	parser.configure(Fixtures.boss("void_throne"))
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var implementation: Script = load(RuntimePath)
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "Void domain binds the authored Boss definition")
	var initial: Dictionary = runtime.snapshot()
	suite.assert_equal(initial.pillars.size(), 4, "four HP120 pillars start as physical cover")
	suite.assert_true(initial.cores.is_empty(), "plane cores cannot exist before P3")
	var fact := _damage(identity, "pillar-first", "void_cover_pillar:0", 0, 80.0)
	suite.assert_true(runtime.accept_damage_fact(fact).ok, "accepted actual weapon loss spends pillar HP")
	suite.assert_equal(runtime.snapshot().pillars[0].current_hp, 40.0, "pillar actual accepted HP is retained")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.accept_damage_fact(fact).ok and runtime.snapshot() == before, "duplicate damage refuses without mutation")
	suite.assert_true(runtime.accept_phase(1, 0).ok, "P2 retires all pillars into harmless debris")
	suite.assert_true(runtime.snapshot().pillars.all(func(row: Dictionary): return row.debris), "P2 debris is nondamaging and no longer hittable")
	suite.assert_true(not runtime.accept_damage_fact(_damage(identity, "retired-pillar", "void_cover_pillar:1", 0, 10.0)).ok, "retired cover cannot spend weapon hits")
	suite.assert_true(runtime.accept_phase(2, 0).ok, "P3 starts the first four-core round")
	suite.assert_equal(runtime.snapshot().cores.size(), 4, "P3 produces four HP100 reachable cores")
	suite.assert_true(runtime.player_heal_pending(), "P3 offers one real HealthComponent heal")
	suite.assert_true(not runtime.accept_player_heal("wrong-run", "player:1", 0, 100.0, 30.0, true).ok, "P3 heal rejects a foreign run")
	suite.assert_true(not runtime.accept_player_heal(identity.run_id, "player:1", 0, 100.0, 30.0, false).ok, "P3 cannot revive an already dead Player")
	suite.assert_true(runtime.accept_player_heal(identity.run_id, "player:1", 0, 100.0, 12.0, true).ok, "P3 retains an actual capped partial HealthComponent heal")
	suite.assert_true(not runtime.player_heal_pending() and not runtime.accept_player_heal(identity.run_id, "player:1", 0, 100.0, 1.0, true).ok, "P3 healing is single use")
	for slot: int in range(4):
		var result: Dictionary = runtime.accept_damage_fact(_damage(identity, "core-first-%d" % slot, "void_plane_core:1:%d" % slot, 0, 1000.0))
		suite.assert_true(result.ok and result.broken and result.body_damage == 100.0 and result.interrupt_denial, "each first-round core grants exactly100bodydamage and denial interruption")
	suite.assert_equal(runtime.snapshot().core_break_claims.size(), 4, "first round contains four authenticated core breaks")
	suite.assert_equal(runtime.snapshot().exposure_through_frame, 119, "all-four round grants exactly120frames of exposure")
	for frame: int in range(1, 600):
		runtime.advance_frame(frame)
	suite.assert_equal(runtime.snapshot().rounds_started, 1, "cores never regenerate before600frames")
	suite.assert_true(runtime.advance_frame(600), "exact sequential frame accepts second-round regeneration")
	suite.assert_equal(runtime.snapshot().rounds_started, 2, "exactlyone regenerated round is permitted")
	suite.assert_true(runtime.snapshot().cores.all(func(row: Dictionary): return row.current_hp == 100.0 and not row.broken and row.round == 2), "new cores have fresh HP and distinct round identity")
	suite.assert_true(not runtime.accept_damage_fact(_damage(identity, "stale-round-hit", "void_plane_core:1:0", 600, 100.0)).ok, "old core identity cannot damage the regenerated round")
	for slot: int in range(4):
		var result: Dictionary = runtime.accept_damage_fact(_damage(identity, "core-second-%d" % slot, "void_plane_core:2:%d" % slot, 600, 100.0))
		suite.assert_true(result.ok and result.body_damage == 100.0, "second core round grants bounded authentic body loss")
	for frame: int in range(601, 1201):
		runtime.advance_frame(frame)
	suite.assert_equal(runtime.snapshot().rounds_started, 2, "a third round cannot regenerate")
	suite.assert_equal(runtime.snapshot().core_break_claims.size(), 8, "bodydamage is capped at eight core breaks")
	var retained: Dictionary = runtime.snapshot()
	var cold: RefCounted = implementation.new()
	cold.configure(definition, identity)
	suite.assert_true(cold.restore_snapshot(retained) and cold.snapshot() == retained, "fresh arena reconstructs every event and regeneration exactly")
	var forged := retained.duplicate(true)
	forged.cores[0].current_hp = 1.0
	suite.assert_true(not cold.restore_snapshot(forged) and cold.snapshot() == retained, "cold restore refuses core HP detached from accepted loss")
	forged = retained.duplicate(true)
	forged.player_heal.amount += 1.0
	suite.assert_true(not cold.restore_snapshot(forged), "cold restore refuses healing detached from actual Health receipt")
	forged = retained.duplicate(true)
	forged.rounds_started = 3
	suite.assert_true(not cold.restore_snapshot(forged), "cold restore cannot fabricate a third core round")
	forged = retained.duplicate(true)
	forged.events[2].runtime_frame = 1
	suite.assert_true(not cold.restore_snapshot(forged), "cold restore validates chronological event prefixes")
	var pending: RefCounted = implementation.new()
	pending.configure(definition, identity)
	suite.assert_true(pending.accept_phase(2, 1).ok, "a single lethal phase hit may directly enterP3 in the next accepted frame")
	suite.assert_true(pending.can_restore_snapshot(pending.snapshot()) and not pending.can_restore_snapshot(pending.snapshot(), true), "future phase claims restore only inside the uncommitted frame boundary")
	suite.assert_true(pending.advance_frame(1) and pending.can_restore_snapshot(pending.snapshot(), true), "committed phase frame validates its exact event prefix")
	var migrated: Dictionary = pending.initial_at_frame(600, false, 2)
	suite.assert_true(migrated.phase_index == 2 and migrated.rounds_started == 1 and migrated.events.size() == 1 and migrated.core_break_claims.is_empty(), "historical corelessP3 gains declared initial cores without fabricated break receipts")
	suite.assert_true(pending.restore_snapshot(migrated), "explicit historical arena defaults remain strict and reproducible")
	runtime.retire()
	suite.assert_true(runtime.snapshot().terminal and not runtime.advance_frame(1201), "terminal arena retires all further effects")
	suite.assert_true(not runtime.accept_damage_fact(_damage(identity, "post-death", "void_plane_core:2:1", 1200, 100.0)).ok, "terminal core damage cannot publish")
	suite.finish(get_tree())


func _damage(identity: Dictionary, id: String, construct: String, frame: int, amount: float) -> Dictionary:
	return {"fact_id": id, "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "construct_id": construct, "runtime_frame": frame, "amount": amount}
