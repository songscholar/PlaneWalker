extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation: Script = load("res://scripts/enemies/launch/ruin_debris_runtime.gd")
	suite.assert_true(implementation != null, "Ruin projectile landings own explicit debris runtime")
	if implementation != null:
		_test_runtime(implementation)
	suite.finish(get_tree())


func _test_runtime(implementation: Script) -> void:
	var runtime: RefCounted = implementation.new()
	var parameters: Dictionary = Content.boss("ruin_king").mechanisms
	suite.assert_true(runtime.configure("run-debris", 0, {"max_hp": float(parameters.debris_hp), "lifetime_frames": int(parameters.debris_lifetime_frames), "count_cap": int(parameters.debris_count_cap), "radius_px": 12.0}), "authored HP20 TTL480 cap4 compiles")
	var events: Array[Dictionary] = []
	for index: int in range(6):
		events.append(_impact(index))
	suite.assert_true(runtime.advance_frame(1, events, {}, 0, []).ok, "six accepted projectile landings reserve deterministic debris")
	suite.assert_equal(runtime.snapshot().rows.size(), 6, "every distinct landing retains its authoritative reservation")
	suite.assert_equal(runtime.snapshot().rows.filter(func(row: Dictionary): return row.phase == "ACTIVE").size(), 4, "at most four actual debris bodies activate")
	suite.assert_equal(runtime.snapshot().rows.filter(func(row: Dictionary): return row.phase == "PENDING").size(), 2, "full authored cap retains pending debris without consuming TTL")
	var state: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.can_restore_snapshot(state), "current debris ledger validates its exact geometry HP and clocks")
	var twin: RefCounted = implementation.new()
	twin.configure("run-debris", 0, {"max_hp": 20.0, "lifetime_frames": 480, "count_cap": 4, "radius_px": 12.0})
	suite.assert_true(twin.restore_snapshot(state), "fresh debris domain reconstructs all accepted reservations")
	var first: Dictionary = state.rows[0]
	var fact := {"fact_id": "player-hit-1", "run_id": "run-debris", "construct_id": first.id, "runtime_frame": 1, "amount": 20.0}
	suite.assert_equal(runtime.accept_damage_fact(fact).get("amount"), 20.0, "declared debris loses real twenty HP exactly once")
	suite.assert_true(not runtime.accept_damage_fact(fact).ok, "duplicate weapon identity cannot consume another debris")
	suite.assert_true(runtime.advance_frame(2, [], {}, 0, []).ok, "broken debris releases an authored body slot")
	suite.assert_equal(runtime.snapshot().rows[4].activated_frame, 2, "pending debris begins its complete TTL only after actual admission")
	suite.assert_true(runtime.restore_snapshot(state), "rejected hit/admission restores exact accepted debris state")
	suite.assert_equal(runtime.snapshot(), state, "debris rejection restores HP provenance and activation clocks")
	for frame: int in range(2, 481):
		suite.assert_true(runtime.advance_frame(frame, [], {}, 0, []).ok, "debris lifetime accepts sequential frame")
	suite.assert_equal(runtime.snapshot().rows[0].phase, "ACTIVE", "debris retains a collider through all480 lifetime frames")
	suite.assert_equal(runtime.snapshot().rows[0].age, 479, "debris age remains exact before expiry")
	suite.assert_true(runtime.advance_frame(481, [], {}, 0, []).ok, "accepted TTL boundary retires old bodies")
	suite.assert_equal(runtime.snapshot().rows[0].phase, "EXPIRED", "TTL480 removes old debris")
	suite.assert_equal(runtime.snapshot().rows[4].activated_frame, 481, "new pending bodies retain full lifetime after capacity release")
	for mutation: String in ["hp", "age", "point", "fields", "count", "overlap"]:
		var forged := state.duplicate(true)
		match mutation:
			"hp": forged.rows[0].current_hp = 19.0
			"age": forged.rows[0].age += 1
			"point": forged.rows[0].position.y = 180.0
			"fields": forged.rows[0].unknown = true
			"overlap": forged.rows[1].position = forged.rows[0].position.duplicate(true)
			"count":
				forged.rows[4].phase = "ACTIVE"
				forged.rows[4].activated_frame = 1
				forged.rows[4].position = {"x": 64.0, "y": 64.0}
		suite.assert_true(not twin.can_restore_snapshot(forged), "strict debris checkpoint refuses forged " + mutation)
	var crowded: RefCounted = implementation.new()
	crowded.configure("run-debris", 0, {"max_hp": 20.0, "lifetime_frames": 480, "count_cap": 4, "radius_px": 12.0})
	suite.assert_true(crowded.advance_frame(1, [_impact(0)], {}, 8, []).ok, "full shared eight-construct budget queues a landing")
	suite.assert_equal(crowded.snapshot().rows[0].phase, "PENDING", "other arena constructs consume the same admission budget")
	suite.assert_true(crowded.advance_frame(2, [], {}, 7, []).ok, "one freed shared construct slot admits the same landing")
	suite.assert_equal(crowded.snapshot().rows[0].activated_frame, 2, "shared-budget delay never spends pending lifetime")
	suite.assert_true(crowded.advance_frame(3, [], {}, 7, ["ruin-debris-owner"]).ok, "final Boss retirement closes active and pending debris")
	suite.assert_equal(crowded.snapshot().rows[0].phase, "RETIRED", "owned debris never survives final Boss retirement")


func _impact(index: int) -> Dictionary:
	return {"run_id": "run-debris", "source_id": "ruin-debris-owner", "generation": 7 + index, "hit_index": index, "runtime_frame": 1, "position": {"x": 480.0, "y": 120.0}, "bounds": {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}}
