extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		var parser := Definition.new()
		suite.assert_true(parser.configure(row).ok, "cache fixture resolves authentic Boss " + row.id)
		var definition := parser.runtime_projection()
		var identity := Actions.identity()
		identity.seed = 42
		var runtime := Runtime.new()
		suite.assert_true(runtime.configure(definition, identity).ok, "Boss cache begins with accepted configuration")
		var original := runtime.snapshot()
		suite.assert_true(runtime.can_restore_snapshot(original), "exact original snapshot passes full cold validation")
		var entries: Variant = runtime.get("_snapshot_validation_cache")
		suite.assert_true(entries is Array and entries.size() > 0 and entries.size() <= 4, "each Boss retains at most four validated exact snapshots")
		if not entries is Array:
			continue
		for entry: Dictionary in entries:
			suite.assert_true(entry.get("context") is PackedByteArray and entry.get("snapshot") is PackedByteArray, "cache retains detached typed configuration and snapshot bytes")
		for _repeat: int in range(8):
			suite.assert_true(runtime.can_restore_snapshot(original), "repeated exact accepted snapshot stays restorable")
		for kind: String in ["schema_float", "frame_float", "terminal_number", "phase_float", "foreign_identity", "foreign_digest", "extra_field", "duplicate_claim", "negative_hp"]:
			var changed := original.duplicate(true)
			match kind:
				"schema_float": changed.schema_version = float(changed.schema_version)
				"frame_float": changed.runtime_frame = float(changed.runtime_frame)
				"terminal_number": changed.terminal = 0
				"phase_float": changed.mechanism_state.phase_index = 0.0
				"foreign_identity": changed.identity.hostile_source_id = "foreign-owner"
				"foreign_digest": changed.definition_digest = "foreign-definition"
				"extra_field": changed.unexpected = true
				"duplicate_claim": changed.mechanism_state.damage_claims = ["same", "same"]
				"negative_hp": changed.mechanism_state.hp_current = -1.0
			var before_size: int = runtime.get("_snapshot_validation_cache").size()
			var cold: bool = runtime.call("_can_restore_snapshot_uncached", changed)
			suite.assert_equal(runtime.can_restore_snapshot(changed), cold, "warm cache preserves cold typed verdict for " + kind)
			if not cold:
				suite.assert_equal(runtime.get("_snapshot_validation_cache").size(), before_size, "negative verdict never populates cache")
			suite.assert_equal(runtime.snapshot(), original, "validation does not mutate accepted domain state")
		var exported := original.duplicate(true)
		exported.mechanism_state.health_claims.append("caller-mutation")
		suite.assert_true(runtime.can_restore_snapshot(original), "caller mutation cannot poison retained positive bytes")
		for frame: int in range(1, 9):
			suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "actual Boss advances unique accepted frame")
			var accepted := runtime.snapshot()
			suite.assert_equal(runtime.can_restore_snapshot(accepted), runtime.call("_can_restore_snapshot_uncached", accepted), "every new frame preserves full cold validation verdict")
			suite.assert_true(runtime.get("_snapshot_validation_cache").size() <= 4, "successive accepted frames keep bounded storage")
		suite.assert_true(runtime.restore_snapshot(original) and runtime.snapshot() == original, "cached historical boundary restores exact complete domain state")
		var retained := runtime.snapshot()
		var threads: Array[Thread] = []
		for _worker: int in range(3):
			var thread := Thread.new()
			threads.append(thread)
			suite.assert_equal(thread.start(func() -> bool:
				for _step: int in range(12):
					if not runtime.can_restore_snapshot(retained):
						return false
					var forged := retained.duplicate(true)
					forged.terminal = 0
					if runtime.can_restore_snapshot(forged):
						return false
				return true), OK, "parallel read-only validation worker starts")
		for thread: Thread in threads:
			suite.assert_true(thread.wait_to_finish(), "concurrent validation preserves authentic and forged verdicts")
		suite.assert_true(runtime.get("_snapshot_validation_cache").size() <= 4 and runtime.snapshot() == retained, "concurrent cache stays bounded without domain mutations")
		var alternate := identity.duplicate(true)
		alternate.hostile_source_id = "other-boss-owner"
		suite.assert_true(runtime.configure(definition, alternate).ok and not runtime.can_restore_snapshot(original), "reconfiguration cannot admit a previous owner's cached snapshot")
		suite.assert_true(runtime.configure(definition, identity).ok and runtime.can_restore_snapshot(original), "authentic owner reconfiguration restores cold validation")
		if row.id != "time_sovereign":
			suite.assert_true(runtime.configure_arena_origin({"x": 16.0, "y": 0.0}), "initial arena can bind another real origin")
			suite.assert_equal(runtime.can_restore_snapshot(original), runtime.call("_can_restore_snapshot_uncached", original), "origin changes cannot reuse a verdict from the prior arena")
			var shifted := runtime.snapshot()
			suite.assert_true(runtime.can_restore_snapshot(shifted), "shifted actual arena gets independently accepted")
			var context_before: PackedByteArray = runtime.call("_snapshot_validation_context")
			runtime.get("_arena_origin").x += 1.0
			suite.assert_true(runtime.call("_snapshot_validation_context") != context_before, "full live arena configuration participates in exact cache context")
			suite.assert_equal(runtime.can_restore_snapshot(shifted), runtime.call("_can_restore_snapshot_uncached", shifted), "changed live configuration preserves the cold verdict")
		_test_native_boundary(suite, runtime, definition, identity, row.id)
	suite.finish(get_tree())


func _test_native_boundary(suite: RefCounted, runtime: RefCounted, definition: Dictionary, identity: Dictionary, boss_id: String) -> void:
	if boss_id != "forest_heart":
		return
	runtime.configure(definition, identity)
	var auxiliary: RefCounted = runtime.get("_forest_auxiliary")
	if auxiliary.consume_flower("forest_healing_flower:0", "player:1", 1, 10.0).get("ok", false):
		var staged: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.can_restore_snapshot(staged), "general restore accepts an authored staged next-frame auxiliary event")
		suite.assert_true(not runtime.can_restore_native_snapshot(staged), "positive general cache cannot bypass native accepted-boundary validation")
	else:
		suite.assert_true(false, "native-boundary fixture must stage a genuine flower event")
