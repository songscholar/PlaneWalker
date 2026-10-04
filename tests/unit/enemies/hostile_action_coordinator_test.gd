extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var implementation = load("res://scripts/enemies/launch/hostile_action_coordinator.gd")
	suite.assert_true(implementation != null, "fixed-frame hostile coordinator exists")
	if implementation == null:
		suite.finish(get_tree())
		return
	_test_boundaries(suite, implementation)
	_test_rejection_and_restore(suite, implementation)
	_test_multi_hit_and_replay(suite, implementation)
	_test_quantized_geometry(suite, implementation)
	_test_paused_clock_preserves_hit_and_geometry(suite, implementation)
	_test_registered_geometry_matches_authored_sweep_and_target_offsets(suite, implementation)
	suite.finish(get_tree())


func _configured(suite: RefCounted, implementation: Script) -> RefCounted:
	var coordinator: RefCounted = implementation.new()
	suite.assert_true(coordinator.configure(Fixtures.definition(), Fixtures.identity()).get("ok", false), "coordinator configures real action")
	return coordinator


func _test_boundaries(suite: RefCounted, implementation: Script) -> void:
	var coordinator := _configured(suite, implementation)
	var committed: Dictionary = coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	suite.assert_true(committed.get("ok", false), "action commits warning")
	if not committed.get("ok", false):
		return
	suite.assert_equal(committed.threat_facts.size(), 2, "two cones receive independent registry facts")
	suite.assert_equal(committed.threat_facts[0].attack_generation, 7, "root generation starts at supplied floor")
	suite.assert_equal(committed.threat_facts[1].attack_generation, 8, "second primitive allocates distinct generation")
	suite.assert_equal(coordinator.snapshot().next_generation_floor, 9, "both geometry generations consumed")
	for frame: int in range(1, 30):
		var changed := Fixtures.context(frame)
		changed.target_position = {"x": 50.0, "y": 250.0}
		var result: Dictionary = coordinator.advance_frame(frame, changed)
		suite.assert_true(result.ok, "sequential warning frame accepts")
		suite.assert_equal(result.hit_facts, [], "warning frame cannot hit")
	suite.assert_equal(coordinator.snapshot().committed_target, {"x": 120.0, "y": 100.0}, "warning freezes target")
	var active: Dictionary = coordinator.advance_frame(30, Fixtures.context(30))
	suite.assert_equal(active.phase, "ACTIVE", "first active edge is frame 30")
	suite.assert_equal(active.hit_facts.size(), 1, "paired-cone union produces one logical hit")
	if active.hit_facts.size() == 1:
		suite.assert_equal(active.hit_facts[0].attack_generation, 7, "logical hit uses root identity")
		suite.assert_equal(active.hit_facts[0].geometry.size(), 2, "logical hit preserves geometry union")
	for frame: int in range(31, 38):
		suite.assert_equal(coordinator.advance_frame(frame, Fixtures.context(frame)).hit_facts, [], "single hit never repeats during overlap")
	suite.assert_equal(coordinator.advance_frame(38, Fixtures.context(38)).phase, "RECOVERY", "active interval ends before frame 38")
	for frame: int in range(39, 63):
		coordinator.advance_frame(frame, Fixtures.context(frame))
	var retired: Dictionary = coordinator.advance_frame(63, Fixtures.context(63))
	suite.assert_equal(retired.phase, "IDLE", "recovery edge is frame 63")
	suite.assert_equal(retired.retired_generations, [7, 8], "recovery retires every geometry fact")
	suite.assert_true(not coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context(63)).ok, "cooldown still blocks early repeat")
	for frame: int in range(64, 150):
		coordinator.advance_frame(frame, Fixtures.context(frame))
	coordinator.advance_frame(150, Fixtures.context(150))
	suite.assert_true(coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context(150)).ok, "cooldown edge permits repeat")


func _test_rejection_and_restore(suite: RefCounted, implementation: Script) -> void:
	var coordinator := _configured(suite, implementation)
	coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	var before: Dictionary = coordinator.snapshot()
	for frame: int in [0, 2, -1]:
		suite.assert_true(not coordinator.advance_frame(frame, Fixtures.context(frame)).ok, "nonsequential frame rejects")
		suite.assert_equal(coordinator.snapshot(), before, "rejected frame has no state mutation")
	var invalid := Fixtures.context(1)
	invalid.target_position.x = NAN
	suite.assert_true(not coordinator.advance_frame(1, invalid).ok, "nonfinite frame observation rejects")
	suite.assert_equal(coordinator.snapshot(), before, "invalid observation is pure")
	suite.assert_true(not coordinator.request_action("unknown", Fixtures.context()).ok, "unknown action rejects")
	suite.assert_equal(coordinator.snapshot(), before, "unknown action is pure")
	var isolated: Dictionary = coordinator.snapshot()
	isolated.committed_target.x = 999.0
	suite.assert_equal(coordinator.snapshot(), before, "snapshot is deeply isolated")
	for field: String in before:
		var missing := before.duplicate(true)
		missing.erase(field)
		suite.assert_true(not coordinator.can_restore_snapshot(missing), "restore requires " + field)
	var corrupt := before.duplicate(true)
	corrupt.phase = "ACTIVE"
	suite.assert_true(not coordinator.restore_snapshot(corrupt), "inconsistent phase rejects")
	suite.assert_equal(coordinator.snapshot(), before, "failed restore is pure")
	corrupt = before.duplicate(true)
	corrupt.next_generation_floor = 7
	suite.assert_true(not coordinator.can_restore_snapshot(corrupt), "restore generation cannot overlap committed facts")
	corrupt = before.duplicate(true)
	corrupt.resolved_hit_indices = [0]
	suite.assert_true(not coordinator.can_restore_snapshot(corrupt), "warning cannot claim a future hit")
	corrupt = before.duplicate(true)
	corrupt.committed_target.x += 1.0
	suite.assert_true(not coordinator.can_restore_snapshot(corrupt), "committed geometry seal rejects target tampering")
	var cancel: Dictionary = coordinator.cancel(&"room_exit")
	suite.assert_true(cancel.ok, "cancellation accepts")
	suite.assert_equal(cancel.retired_generations, [7, 8], "cancel retires all owned primitives")
	suite.assert_equal(coordinator.snapshot().phase, "IDLE", "cancel clears action")
	suite.assert_equal(coordinator.cancel(&"room_exit").retired_generations, [], "repeated cancel retires nothing twice")
	suite.assert_true(coordinator.restore_snapshot(before), "valid snapshot restores")
	suite.assert_equal(coordinator.snapshot(), before, "snapshot restores exactly")
	var bad_definition := Fixtures.definition()
	bad_definition.actions[0].handler_id = "unknown"
	suite.assert_true(not coordinator.configure(bad_definition, Fixtures.identity()).ok, "invalid configure rejects")
	suite.assert_equal(coordinator.snapshot(), {}, "failed configure clears prior state")


func _test_multi_hit_and_replay(suite: RefCounted, implementation: Script) -> void:
	var definition := Fixtures.definition()
	definition.actions[0].active_frames = 16
	definition.actions[0].hit_schedule = [
		{"offset_frame": 0, "hit_index": 0, "damage": 8.0, "damage_type": "physical"},
		{"offset_frame": 12, "hit_index": 1, "damage": 8.0, "damage_type": "physical"},
	]
	var original: RefCounted = implementation.new()
	suite.assert_true(original.configure(definition, Fixtures.identity()).ok, "multi-hit coordinator configures")
	original.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	for frame: int in range(1, 35):
		original.advance_frame(frame, Fixtures.context(frame))
	var checkpoint: Dictionary = original.snapshot()
	var replay: RefCounted = implementation.new()
	replay.configure(definition, Fixtures.identity())
	suite.assert_true(replay.restore_snapshot(checkpoint), "mid-active checkpoint restores")
	var second_hit_count := 0
	for frame: int in range(35, 72):
		var first: Dictionary = original.advance_frame(frame, Fixtures.context(frame))
		var repeated: Dictionary = replay.advance_frame(frame, Fixtures.context(frame))
		suite.assert_equal(repeated, first, "Replay accepts identical frame facts")
		suite.assert_equal(replay.snapshot(), original.snapshot(), "Replay retains identical domain state")
		second_hit_count += first.hit_facts.size()
	suite.assert_equal(second_hit_count, 1, "restored schedule emits only the unresolved second hit")


func _test_quantized_geometry(suite: RefCounted, implementation: Script) -> void:
	var coordinator := _configured(suite, implementation)
	var observation := Fixtures.context()
	observation.source_position = {"x": 100.001, "y": 100.003}
	observation.target_position = {"x": 115.007, "y": 109.013}
	var committed: Dictionary = coordinator.request_action("shattered_sentinel.shield_sweep", observation)
	suite.assert_true(committed.ok, "fractional source and target commit")
	suite.assert_true(coordinator.can_restore_snapshot(coordinator.snapshot()), "quantized aiming geometry restores without drift")
	for fact: Dictionary in committed.get("threat_facts", []):
		var native: Dictionary = implementation.native_threat_fact(fact)
		suite.assert_true(not native.is_empty(), "native fact uses existing strict telegraph contract")
		suite.assert_true(native.get("origin") is Vector2, "native registration has Vector2 geometry")
	var corrupted: Dictionary = committed.threat_facts[0].duplicate(true)
	corrupted.origin.x = INF
	suite.assert_equal(implementation.native_threat_fact(corrupted), {}, "nonfinite native geometry rejects")


func _test_paused_clock_preserves_hit_and_geometry(suite: RefCounted, implementation: Script) -> void:
	var coordinator := _configured(suite, implementation)
	coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	var before: Dictionary = coordinator.snapshot()
	suite.assert_true(before.has("paused_frames"), "coordinator snapshot records paused action frames")
	if not before.has("paused_frames"):
		return
	for frame: int in range(1, 31):
		coordinator.advance_frame(frame, Fixtures.context(frame))
	for frame: int in [31, 32]:
		var paused: Dictionary = coordinator.advance_frame(frame, Fixtures.context(frame), true)
		suite.assert_true(paused.ok, "paused clock still accepts sequential runtime frames")
		suite.assert_equal(paused.hit_facts, [], "paused first-active offset does not repeat a hit")
		suite.assert_equal(paused.effect_requests, [], "paused first-active offset does not repeat semantic effects")
		suite.assert_equal(paused.threat_extensions.size(), 2, "every fixed primitive extends exactly once per paused frame")
		suite.assert_equal(paused.threat_extensions[0].new_through_frame, 62 + frame - 30, "expiry extension matches exact paused time")
	var checkpoint: Dictionary = coordinator.snapshot()
	suite.assert_equal(checkpoint.paused_frames, 2, "paused frame count is bounded state")
	suite.assert_equal(checkpoint.committed_target, before.committed_target, "Stop preserves committed target")
	suite.assert_equal(checkpoint.geometry_generations, before.geometry_generations, "Stop preserves generations")
	suite.assert_true(coordinator.can_restore_snapshot(checkpoint), "mid-Stop snapshot restores consistently")
	var replay := _configured(suite, implementation)
	suite.assert_true(replay.restore_snapshot(checkpoint), "second coordinator restores paused schedule")
	for frame: int in range(33, 66):
		var original: Dictionary = coordinator.advance_frame(frame, Fixtures.context(frame))
		suite.assert_equal(replay.advance_frame(frame, Fixtures.context(frame)), original, "paused schedule resumes identically")
		suite.assert_equal(original.hit_facts, [], "resolved first hit remains consumed after resume")
	suite.assert_equal(coordinator.snapshot().phase, "IDLE", "paused recovery retires at shifted exact edge")


func _test_registered_geometry_matches_authored_sweep_and_target_offsets(suite: RefCounted, implementation: Script) -> void:
	var coordinator := _configured(suite, implementation)
	var committed: Dictionary = coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	var registry := Registry.new()
	for fact: Dictionary in committed.threat_facts:
		registry.register_fact(implementation.native_threat_fact(fact))
	suite.assert_true(registry.contains_point(Vector2(120, 100), 30), "paired sweep includes its forward target without a central hole")
	suite.assert_true(registry.contains_point(Vector2(100, 120), 30), "paired sweep includes right side of intended half-plane")
	suite.assert_true(registry.contains_point(Vector2(100, 80), 30), "paired sweep includes left side of intended half-plane")
	suite.assert_true(not registry.contains_point(Vector2(80, 100), 30), "paired sweep retains a reachable rear safe side")
	var definition := Fixtures.definition()
	definition.actions[0].geometry = [{"shape": "target_circle", "origin_offset": {"x": 32.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": 8.0, "length": 0.0}]
	coordinator.configure(definition, Fixtures.identity())
	committed = coordinator.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	registry.clear()
	registry.register_fact(implementation.native_threat_fact(committed.threat_facts[0]))
	suite.assert_true(registry.contains_point(Vector2(152, 100), 30), "target circle uses its authored offset target")
	suite.assert_true(not registry.contains_point(Vector2(120, 100), 30), "offset circle does not silently damage the original target")
