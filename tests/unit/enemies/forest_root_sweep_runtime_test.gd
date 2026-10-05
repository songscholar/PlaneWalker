extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
var suite: RefCounted
const IDENTITY := {"run_id": "run-root-sweep", "hostile_source_id": "forest-sweep-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var runtime := _runtime()
	var request: Dictionary = runtime.request_action("matriarch_root_sweep", _context(0, Vector2(132, 104)))
	suite.assert_true(request.ok, "actual authored sweep selects a nearby root even when the stationary trunk is out of range")
	if request.ok:
		suite.assert_equal(request.threat_facts[0].origin, {"x": 112.0, "y": 104.0}, "sweep warning originates from the selected living root")
		var committed: Dictionary = runtime.snapshot()
		suite.assert_true(not committed.arena_state.get("sweep_claims", []).is_empty(), "root sweep retains explicit ownership provenance")
		if not committed.arena_state.get("sweep_claims", []).is_empty():
			suite.assert_equal(committed.arena_state.sweep_claims[0].root_id, "forest_root:0", "sweep ownership binds the stable selected segment")
		var damage: Dictionary = runtime.accept_arena_damage_fact(_damage("forest_root:0", 0, "cancel-root"))
		suite.assert_true(damage.ok and damage.get("retired_generations", []) == [7] and runtime.snapshot().action.phase == "IDLE", "breaking the selected root cancels its entire committed segment")
		suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "cancelled root sweep remains a closed accepted checkpoint")
		suite.assert_true(runtime.restore_snapshot(committed), "refused root damage restores the exact owned warning")
		suite.assert_equal(runtime.snapshot(), committed, "root sweep compensation preserves frozen geometry and receipt")
	runtime = _runtime()
	var tied: Dictionary = runtime.request_action("matriarch_root_sweep", _context(0, Vector2(176, 104)))
	suite.assert_true(tied.ok and tied.threat_facts[0].origin == {"x": 112.0, "y": 104.0}, "equidistant surviving roots select the lowest stable slot")
	runtime = _runtime()
	runtime.accept_arena_damage_fact(_damage("forest_root:0", 0, "before-root"))
	var surviving: Dictionary = runtime.request_action("matriarch_root_sweep", _context(0, Vector2(176, 104)))
	suite.assert_true(surviving.ok and surviving.threat_facts[0].origin == {"x": 240.0, "y": 104.0}, "permanently broken roots cannot own a new sweep")
	runtime = _runtime()
	for slot: int in range(6):
		runtime.accept_arena_damage_fact(_damage("forest_root:%d" % slot, 0, "all-roots:%d" % slot))
	var exhausted: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.request_action("matriarch_root_sweep", _context(0, Vector2(340, 144))).ok, "all broken roots disable the sweep permanently")
	suite.assert_equal(runtime.snapshot(), exhausted, "unavailable rooted sweep consumes no decision, generation or cooldown")
	_test_lifecycle_and_receipts()
	_test_translated_and_historical()
	suite.finish(get_tree())


func _test_lifecycle_and_receipts() -> void:
	var runtime := _runtime()
	runtime.request_action("matriarch_root_sweep", _context(0, Vector2(132, 104)))
	for frame: int in range(1, 45):
		var result: Dictionary = runtime.advance_frame(frame, _context(frame, Vector2(600, 320)), false)
		suite.assert_true(result.ok and result.hit_facts.is_empty() and runtime.snapshot().action.phase == "WARNING", "root sweep retains its full45-frame frozen warning")
	var active: Dictionary = runtime.advance_frame(45, _context(45, Vector2(600, 320)), false)
	suite.assert_true(active.ok and active.hit_facts.size() == 1 and active.hit_facts[0].damage == 20.0, "P1 root sweep activates only after45 warning frames with authored20 damage")
	suite.assert_equal(active.hit_facts[0].geometry[0].target_point, {"x": 132.0, "y": 104.0}, "late Player movement never retargets the committed root segment")
	var accepted: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.can_restore_native_snapshot(accepted), "current active root sweep is an accepted cold boundary")
	var claimed_historical := accepted.duplicate(true)
	claimed_historical.arena_state.historical_sweep_generation = claimed_historical.action.geometry_generations[0]
	claimed_historical.arena_state.sweep_claims.clear()
	suite.assert_true(not runtime.can_restore_native_snapshot(claimed_historical), "current rooted cast cannot bypass ownership by claiming a historical trunk generation")
	for mutation: String in ["owner", "target", "generation", "origin", "prefix", "phase", "unknown"]:
		var forged := accepted.duplicate(true)
		match mutation:
			"owner": forged.arena_state.sweep_claims[0].root_id = "forest_root:1"
			"target": forged.arena_state.sweep_claims[0].target_position.x += 1.0
			"generation": forged.arena_state.sweep_claims[0].attack_generation += 1
			"origin": forged.arena_state.arena_origin.x += 1.0
			"prefix": forged.arena_state.sweep_claims[0].damage_claim_count = 1
			"phase": forged.arena_state.sweep_claims[0].phase_retirement_applied = true
			"unknown": forged.arena_state.sweep_claims[0].extra = true
		suite.assert_true(not runtime.can_restore_native_snapshot(forged), "active owned sweep rejects forged " + mutation)
	var other: Dictionary = runtime.accept_arena_damage_fact(_damage("forest_root:1", 45, "unselected"))
	suite.assert_true(other.ok and not other.has("retired_generations") and runtime.snapshot().action.phase == "ACTIVE", "unselected root break preserves the committed active segment")
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "same-frame later root break retains the earlier sweep prefix")
	var broken: Dictionary = runtime.accept_arena_damage_fact(_damage("forest_root:0", 45, "selected-active"))
	suite.assert_true(broken.ok and broken.retired_generations == [7], "selected root destruction also retires an already-active segment")
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "selected root active cancellation restores without resurrecting it")
	var ordering := _runtime()
	ordering.accept_arena_damage_fact(_damage("forest_root:0", 0, "before-commit"))
	ordering.request_action("matriarch_root_sweep", _context(0, Vector2(176, 104)))
	var with_prefix: Dictionary = ordering.snapshot()
	suite.assert_true(ordering.can_restore_native_snapshot(with_prefix), "same-frame earlier damage prefix reconstructs surviving-root selection")
	with_prefix.arena_state.sweep_claims[0].damage_claim_count = 0
	suite.assert_true(not ordering.can_restore_native_snapshot(with_prefix), "omitting same-frame earlier damage cannot reassign a root")
	var p2 := _runtime()
	p2.accept_damage_fact({"fact_id": "phase", "target_source_id": IDENTITY.hostile_source_id, "runtime_frame": 0, "amount": 600.0, "hp_after": 800.0})
	for frame: int in range(1, 61):
		p2.advance_frame(frame, _context(frame, Vector2(484, 256)), false)
	suite.assert_true(p2.request_action("matriarch_root_sweep", _context(60, Vector2(484, 256))).ok, "actualP2 selects a nonretired root after its full transition")
	for frame: int in range(61, 105):
		p2.advance_frame(frame, _context(frame, Vector2(484, 256)), false)
	var p2_active: Dictionary = p2.advance_frame(105, _context(105, Vector2(484, 256)), false)
	suite.assert_true(p2_active.ok and p2_active.hit_facts[0].damage == 26.0 and p2.can_restore_native_snapshot(p2.snapshot()), "P2 root sweep retains authored26 damage and accepted retirement provenance")
	var automatic := _runtime()
	var selection: Dictionary = automatic.advance_frame(1, _context(1, Vector2(112, 100)))
	suite.assert_true(selection.ok and automatic.snapshot().action.action_id == "matriarch_root_sweep" and automatic.snapshot().action.committed_origin == {"x": 112.0, "y": 104.0}, "automatic selection measures distance from a surviving root")


func _test_translated_and_historical() -> void:
	var runtime := _runtime(Vector2(80, 48))
	var translated: Dictionary = runtime.request_action("matriarch_root_sweep", _context(0, Vector2(212, 152)))
	suite.assert_true(translated.ok and translated.threat_facts[0].origin == {"x": 192.0, "y": 152.0}, "translated room origin preserves local stable roots and world warning")
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "translated sweep origin is exact in current cold state")
	for version: int in [1, 2]:
		var legacy_owner := _runtime()
		legacy_owner.request_action("matriarch_root_sweep", _context(0, Vector2(340, 144)))
		var historical: Dictionary = legacy_owner.snapshot()
		var legacy_action: RefCounted = legacy_owner._make_action(0, false)
		legacy_action.request_action("matriarch_root_sweep", _context(0, Vector2(340, 144)))
		historical.action = legacy_action.snapshot()
		historical.schema_version = version
		if version == 1:
			historical.erase("arena_state")
		else:
			historical.arena_state.schema_version = 1
			for field: String in ["arena_origin", "sweep_claims", "historical_sweep_generation"]:
				historical.arena_state.erase(field)
		var normalized: Dictionary = legacy_owner.normalize_native_snapshot(historical)
		suite.assert_true(not normalized.is_empty() and normalized.schema_version == 3 and normalized.arena_state.schema_version == 2, "explicit historicalBoss%d migrates its active trunk-origin sweep" % version)
		if not normalized.is_empty():
			suite.assert_true(legacy_owner.restore_snapshot(normalized), "historical trunk warning restores through strict current schema")
			for frame: int in range(1, 46):
				legacy_owner.advance_frame(frame, _context(frame, Vector2(340, 144)), false)
			suite.assert_true(legacy_owner.snapshot().action.phase == "ACTIVE" and legacy_owner.can_restore_native_snapshot(legacy_owner.snapshot()), "historical sweep completes its original full warning with preserved generation")
		for mutation: String in ["fractional", "missing", "future", "partial_arena"]:
			var forged := historical.duplicate(true)
			match mutation:
				"fractional": forged.schema_version = float(version)
				"missing": forged.erase("action")
				"future": forged.schema_version = 4
				"partial_arena":
					forged.schema_version = 3
					forged["arena_state"] = {"schema_version": 2}
			suite.assert_true(legacy_owner.normalize_native_snapshot(forged).is_empty(), "historical migration rejects " + mutation)


func _runtime(origin: Vector2 = Vector2.ZERO) -> RefCounted:
	var parser := Definition.new()
	parser.configure(Content.boss("forest_heart"))
	var runtime := Runtime.new()
	runtime.configure_arena_origin({"x": origin.x, "y": origin.y})
	runtime.configure(parser.runtime_projection(), IDENTITY)
	return runtime


func _context(frame: int, target: Vector2) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": 320.0, "y": 144.0}, "target_position": {"x": target.x, "y": target.y}, "facing_direction": {"x": -1.0, "y": 0.0}, "target_id": "player:1"}


func _damage(id: String, frame: int, fact_id: String) -> Dictionary:
	return {"fact_id": fact_id, "run_id": IDENTITY.run_id, "owner_source_id": IDENTITY.hostile_source_id, "construct_id": id, "runtime_frame": frame, "amount": 100.0}
