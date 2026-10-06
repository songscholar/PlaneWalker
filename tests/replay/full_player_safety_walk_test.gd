extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var content = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not content.has_blocking_errors(), "safety boundary uses actual Launch content")
	var player := await Fixture.spawn(self, registry, suite, "full-player-safety-walk", 504)
	var snapshot: Dictionary = player.full_player_replay_snapshot()
	var original := var_to_bytes(snapshot)
	suite.assert_true(Replay.validate_full_player_snapshot(snapshot, snapshot.identity).ok, "actual Launch Player snapshot passes full validation")
	_boundaries(suite, Replay, snapshot)
	var path := OS.get_environment("PLANEWALKER_REPLAY_SAFETY_WALK_PROBE")
	if not path.is_empty():
		suite.assert_true(path.begins_with("res://build/"), "Replay instrumentation remains build-only")
		var probe: Script = load(path) if path.begins_with("res://build/") else null
		suite.assert_true(probe != null, "actual instrumented Recorder compiles")
		if probe != null:
			_boundaries(suite, probe, snapshot)
			_count_walks(suite, probe, snapshot)
	else:
		print("PLANEWALKER_REPLAY_SAFETY_WALK_PROBE ", JSON.stringify({"instrumented": false, "root_walk_count_certified": false}))
	suite.assert_equal(var_to_bytes(snapshot), original, "public validation preserves every typed caller byte")
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _boundaries(suite: RefCounted, implementation: Script, snapshot: Dictionary) -> void:
	var identity: Dictionary = snapshot.identity
	var reward: Dictionary = snapshot.reward_effect_state
	var talents: Dictionary = snapshot.live_talent_state
	suite.assert_equal(implementation.call("validate_full_player_identity", identity), identity, "standalone identity retains normalized result")
	suite.assert_true(implementation.call("validate_full_player_reward_effect_state", reward), "standalone reward accepts actual state")
	suite.assert_true(implementation.call("validate_full_player_live_talent_state", talents, identity), "standalone live talent accepts actual definitions and digests")
	var freed := Node.new()
	freed.free()
	var deeply_unsafe: Variant = RefCounted.new()
	for depth: int in range(48):
		deeply_unsafe = {"child": deeply_unsafe} if depth % 2 == 0 else [deeply_unsafe]
	for value: Variant in [self, freed, INF, NAN, PackedFloat64Array([INF]), deeply_unsafe]:
		for field: String in ["identity", "reward_effect_state", "live_talent_state"]:
			var forged := snapshot.duplicate(true)
			forged[field]["unsafe"] = value
			var full: Dictionary = implementation.call("validate_full_player_snapshot", forged, identity)
			suite.assert_equal(full.code, &"FULL_PLAYER_SNAPSHOT_UNSAFE", "deep unsafe value is refused at the full snapshot boundary: " + field)
			suite.assert_equal(full, Replay.validate_full_player_snapshot(forged, identity), "instrumented and actual unsafe rejection results match")
			_assert_standalone_refusal(suite, implementation, forged, field)
	var wrong_identity := identity.duplicate(true)
	wrong_identity.run_id = "foreign-full-player-safety-walk"
	suite.assert_equal(implementation.call("validate_full_player_snapshot", snapshot, wrong_identity), Replay.validate_full_player_snapshot(snapshot, wrong_identity), "expected identity ownership remains mandatory")
	for spec: Dictionary in [
		{"field": "action_state", "key": "frame", "value": int(snapshot.frame) + 1, "code": &"FULL_PLAYER_SNAPSHOT_CLOCK_MISMATCH"},
		{"field": "reward_effect_state", "key": "schema_version", "value": 1.0, "code": &"FULL_PLAYER_REWARD_EFFECT_STATE_INVALID"},
		{"field": "live_talent_state", "key": "modifier_digest", "value": "0".repeat(64), "code": &"FULL_PLAYER_LIVE_TALENT_STATE_INVALID"},
	]:
		var forged := snapshot.duplicate(true)
		forged[spec.field][spec.key] = spec.value
		var full: Dictionary = implementation.call("validate_full_player_snapshot", forged, identity)
		suite.assert_equal(full.code, spec.code, "safe tamper keeps its exact public rejection code")
		suite.assert_equal(full, Replay.validate_full_player_snapshot(forged, identity), "safe tamper keeps the actual public verdict")
	var safe_packed := snapshot.duplicate(true)
	safe_packed.weapon_replay_fact_baseline["packed"] = PackedByteArray([1, 2, 3])
	suite.assert_equal(implementation.call("validate_full_player_snapshot", safe_packed, identity), Replay.validate_full_player_snapshot(safe_packed, identity), "admitted packed bytes keep full validator semantics")


func _assert_standalone_refusal(suite: RefCounted, implementation: Script, snapshot: Dictionary, field: String) -> void:
	if field == "identity":
		suite.assert_equal(implementation.call("validate_full_player_identity", snapshot[field]), {}, "standalone identity independently refuses unsafe descendants")
	elif field == "reward_effect_state":
		suite.assert_true(not implementation.call("validate_full_player_reward_effect_state", snapshot[field]), "standalone reward independently refuses unsafe descendants")
	else:
		suite.assert_true(not implementation.call("validate_full_player_live_talent_state", snapshot[field], snapshot.identity), "standalone live talent independently refuses unsafe descendants")


func _count_walks(suite: RefCounted, probe: Script, snapshot: Dictionary) -> void:
	var counts := {}
	for operation: String in ["snapshot", "identity", "reward", "talents"]:
		probe.call("_pw_reset_replay_safety_walk_probe")
		if operation == "snapshot":
			suite.assert_equal(probe.call("validate_full_player_snapshot", snapshot, snapshot.identity), Replay.validate_full_player_snapshot(snapshot, snapshot.identity), "instrumentation preserves complete public snapshot verdict")
		elif operation == "identity":
			probe.call("validate_full_player_identity", snapshot.identity)
		elif operation == "reward":
			probe.call("validate_full_player_reward_effect_state", snapshot.reward_effect_state)
		else:
			probe.call("validate_full_player_live_talent_state", snapshot.live_talent_state, snapshot.identity)
		counts[operation] = probe.call("_pw_replay_safety_walk_probe_count")
		suite.assert_equal(counts[operation], 1, "Recorder initiates exactly one complete safety walk for " + operation)
	for field: String in ["identity", "reward_effect_state", "live_talent_state"]:
		var forged := snapshot.duplicate(true)
		if field == "identity":
			forged.identity.stats.max_hp = self
		elif field == "reward_effect_state":
			forged.reward_effect_state.health.current_hp = self
		else:
			forged.live_talent_state.modifiers["unsafe"] = self
		probe.call("_pw_reset_replay_safety_walk_probe")
		_assert_standalone_refusal(suite, probe, forged, field)
		suite.assert_equal(probe.call("_pw_replay_safety_walk_probe_count"), 1, "standalone unsafe refusal retains one independent safety walk for " + field)
	print("PLANEWALKER_REPLAY_SAFETY_WALK_PROBE ", JSON.stringify({"instrumented": true, "counts": counts, "snapshot_sha256": var_to_bytes(snapshot).hex_encode().sha256_text()}))
