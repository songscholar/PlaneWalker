extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossRuntime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var path := "res://scripts/enemies/launch/forest_arena_runtime.gd"
	suite.assert_true(FileAccess.file_exists(path), "authoritative Forest roots domain exists")
	if FileAccess.file_exists(path):
		var runtime: RefCounted = load(path).new()
		var parser := Definition.new()
		parser.configure(Content.boss("forest_heart"))
		var identity := {"run_id": "run-roots", "hostile_source_id": "forest-root-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
		suite.assert_true(runtime.configure(parser.runtime_projection(), identity).ok, "Forest arena binds actual authored six-root recipe")
		var initial: Dictionary = runtime.snapshot()
		suite.assert_equal(initial.roots.size(), 6, "Forest owns exactly six independently destructible roots")
		for row: Dictionary in initial.roots:
			suite.assert_true(row.current_hp == 100.0 and row.radius_px == 12.0, "root HP and native radius preserve authored data")
		var fact := {"fact_id": "first-break", "run_id": "run-roots", "owner_source_id": "forest-root-owner", "construct_id": "forest_root:0", "runtime_frame": 1, "amount": 200.0}
		suite.assert_equal(runtime.accept_damage_fact(fact).get("amount"), 100.0, "root overkill clamps to independent authored HP")
		suite.assert_true(not runtime.accept_damage_fact(fact).ok, "root rejects duplicate weapon receipt")
		suite.assert_true(not runtime.can_restore_snapshot(runtime.snapshot(), true), "accepted cold boundary rejects next-frame staged root damage")
		for frame: int in range(1, 46):
			suite.assert_true(runtime.advance_frame(frame), "root exposure lifetime accepts sequential frames")
			suite.assert_true(runtime.is_exposed(), "root break exposes body for all45 accepted frames")
		suite.assert_true(runtime.advance_frame(46) and not runtime.is_exposed(), "root exposure ends after its full45-frame lifetime")
		suite.assert_true(runtime.accept_phase_retirement(46).ok, "P2 deterministically retires three surviving roots")
		var current: Dictionary = runtime.snapshot()
		suite.assert_equal(current.phase_retirement.root_ids, ["forest_root:1", "forest_root:2", "forest_root:3"], "P2 skips already broken roots and selects stable surviving slots")
		suite.assert_true(current.roots[0].broken and not current.roots[0].retired, "P2 never resurrects or reclassifies an already destroyed root")
		suite.assert_true(not runtime.accept_phase_retirement(46).ok, "phase retirement cannot repeat")
		suite.assert_true(runtime.restore_snapshot(current), "strict Forest root state restores exactly")
		var integer_damage := current.duplicate(true)
		integer_damage.damage_claims[0].amount = 100
		suite.assert_true(runtime.can_restore_snapshot(integer_damage), "root retirement accepts equivalent numeric damage after structured serialization")
		for mutation: String in ["hp", "position", "unknown", "retirement", "exposure"]:
			var forged := current.duplicate(true)
			match mutation:
				"hp": forged.roots[0].current_hp = 1.0
				"position": forged.roots[4].position.x += 1.0
				"unknown": forged.roots[0].extra = true
				"retirement": forged.phase_retirement.root_ids.reverse()
				"exposure": forged.exposure_through_frame += 1
			suite.assert_true(not runtime.can_restore_snapshot(forged), "root cold state rejects forged " + mutation)
		var ordering: RefCounted = load(path).new()
		ordering.configure(parser.runtime_projection(), identity)
		ordering.advance_frame(1)
		ordering.accept_phase_retirement(1)
		var later := fact.duplicate(true)
		later.fact_id = "same-frame-after-phase"
		later.construct_id = "forest_root:3"
		later.amount = 100
		suite.assert_true(ordering.accept_damage_fact(later).ok, "a surviving root may break after retirement in the same accepted frame")
		suite.assert_true(ordering.can_restore_snapshot(ordering.snapshot(), true), "retirement preserves the exact earlier claim boundary within the same frame")
		var malformed := current.duplicate(true)
		malformed.damage_claims[0].runtime_frame = "invalid"
		suite.assert_true(not runtime.can_restore_snapshot(malformed), "retirement rejects malformed damage receipts without interpreting them")
		_test_conversion_tail(parser.runtime_projection(), identity)
	suite.finish(get_tree())


func _test_conversion_tail(definition: Dictionary, identity: Dictionary) -> void:
	var runtime := BossRuntime.new()
	runtime.configure(definition, identity)
	var fact := {"fact_id": "tail-root-break", "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "construct_id": "forest_root:0", "runtime_frame": 1, "amount": 100.0}
	runtime.accept_arena_damage_fact(fact)
	runtime.advance_frame(1, Actions.context(1), false)
	suite.assert_true(runtime.extend_character_boss_exposure(21, 10), "actual root exposure grants the existing Character conversion endpoint")
	for frame: int in range(2, 46):
		runtime.advance_frame(frame, Actions.context(frame), false)
		suite.assert_true(runtime.snapshot().conversion.claims[0].state == "pending" and runtime.snapshot().conversion.claims[0].remaining_frames == 10, "root exposure preserves all Character tail frames")
	var checkpoint := runtime.snapshot()
	suite.assert_true(runtime.can_restore_native_snapshot(checkpoint), "root-specific pending Character tail has exact cold provenance")
	var forged := checkpoint.duplicate(true)
	forged.conversion.claims[0].state = "active"
	suite.assert_true(not runtime.can_restore_native_snapshot(forged), "cold root exposure cannot consume the Character tail early")
	runtime.advance_frame(46, Actions.context(46), false)
	suite.assert_true(runtime.snapshot().conversion.claims[0].state == "active", "Character tail activates only after the full root window")
	fact.fact_id = "second-tail-root-break"
	fact.construct_id = "forest_root:1"
	fact.runtime_frame = 46
	runtime.accept_arena_damage_fact(fact)
	suite.assert_true(runtime.snapshot().conversion.claims[0].state == "pending" and runtime.snapshot().conversion.claims[0].remaining_frames == 10, "a new root break immediately preserves an already active Character tail")
	for frame: int in range(47, 91):
		runtime.advance_frame(frame, Actions.context(frame), false)
	runtime.advance_frame(91, Actions.context(91), false)
	suite.assert_true(runtime.snapshot().conversion.claims[0].state == "active" and runtime.snapshot().conversion.claims[0].remaining_frames == 10, "second root window never spends preserved conversion time")
	for frame: int in range(92, 101):
		runtime.advance_frame(frame, Actions.context(frame), false)
		suite.assert_true(runtime.is_exposed(), "preserved Character tail remains positive for its complete ten frames")
	runtime.advance_frame(101, Actions.context(101), false)
	suite.assert_true(not runtime.is_exposed() and runtime.snapshot().conversion.claims.is_empty(), "Character tail ends once after its complete remaining lifetime")
