extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const RUNTIMES := {
	"void_throne": preload("res://scripts/enemies/launch/void_arena_runtime.gd"),
	"forge_colossus": preload("res://scripts/enemies/launch/forge_arena_runtime.gd"),
	"forest_heart": preload("res://scripts/enemies/launch/forest_auxiliary_runtime.gd"),
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	for id: String in RUNTIMES:
		var parser := Definition.new()
		suite.assert_true(parser.configure(Content.boss(id)).ok, "cache fixture resolves authentic " + id)
		var definition := parser.runtime_projection()
		var identity := Actions.identity()
		identity.seed = 42
		var runtime: RefCounted = RUNTIMES[id].new()
		suite.assert_true(runtime.configure(definition, identity).ok, "auxiliary accepts authored configuration")
		var initial: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.can_restore_snapshot(initial), "authentic initial snapshot is restorable")
		var entries: Variant = runtime.get("_validation_cache")
		suite.assert_true(entries is Array and not entries.is_empty() and entries.size() <= 4, "accepted auxiliary snapshots use a bounded positive cache")
		suite.assert_true(runtime.has_method("_can_restore_snapshot_uncached"), "cold validator remains callable as the independent miss authority")
		if not entries is Array or not runtime.has_method("_can_restore_snapshot_uncached"):
			continue
		for entry: Dictionary in entries:
			suite.assert_true(entry.context is PackedByteArray and entry.snapshot is PackedByteArray and entry.accepted_boundary is bool, "cache retains exact detached typed bytes and boundary mode")
		for _repeat: int in range(6):
			suite.assert_true(runtime.can_restore_snapshot(initial), "repeated exact initial state remains valid")
		for kind: String in ["schema_float", "frame_float", "frame_fraction", "terminal_number", "foreign_identity", "foreign_digest", "extra_field", "derived_hp", "event_float"]:
			var changed := initial.duplicate(true)
			match kind:
				"schema_float": changed.schema_version = float(changed.schema_version)
				"frame_float": changed.runtime_frame = float(changed.runtime_frame)
				"frame_fraction": changed.runtime_frame = 0.5
				"terminal_number": changed.terminal = 0
				"foreign_identity": changed.identity.hostile_source_id = "foreign-owner"
				"foreign_digest": changed.definition_digest = "foreign-definition"
				"extra_field": changed.extra = true
				"derived_hp": changed[_constructs(id)][0].current_hp -= 1.0
				"event_float": changed.events = [{"kind": "terminal", "frame": 0.0}]
			_check_verdict(suite, runtime, changed, false, kind)
			suite.assert_equal(runtime.snapshot(), initial, "validation preserves live domain state")
		var mutated := initial.duplicate(true)
		mutated[_constructs(id)][0].current_hp = -10.0
		suite.assert_true(runtime.can_restore_snapshot(initial) and not runtime.can_restore_snapshot(mutated), "caller mutation cannot poison an accepted snapshot")
		suite.assert_true(_stage(runtime, id, identity), "real auxiliary event can be staged for next frame")
		var staged: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.can_restore_snapshot(staged), "general restore accepts authentic next-frame event")
		suite.assert_true(not runtime.can_restore_snapshot(staged, true), "general positive entry cannot bypass committed boundary")
		var typed_event := staged.duplicate(true)
		var event_frame := "frame" if id == "forest_heart" else "runtime_frame"
		typed_event.events[0][event_frame] = float(typed_event.events[0][event_frame])
		_check_verdict(suite, runtime, typed_event, false, "integral float event authority")
		typed_event.events[0][event_frame] = 1.5
		_check_verdict(suite, runtime, typed_event, false, "fractional event authority")
		suite.assert_true(runtime.advance_frame(1) and runtime.can_restore_snapshot(runtime.snapshot(), true), "committed next frame accepts the same authentic receipt")
		var committed: Dictionary = runtime.snapshot()
		for frame: int in range(2, 10):
			suite.assert_true(runtime.advance_frame(frame), "domain advances accepted frames")
			_check_verdict(suite, runtime, runtime.snapshot(), true, "successive accepted frame")
			suite.assert_true(runtime.get("_validation_cache").size() <= 4, "many unique accepted snapshots retain four-entry maximum")
		suite.assert_true(runtime.restore_snapshot(committed) and runtime.snapshot() == committed, "evicted historical state validates and restores exactly")
		runtime.retire()
		_check_verdict(suite, runtime, runtime.snapshot(), true, "terminal state")
		suite.assert_true(runtime.restore_snapshot(initial) and runtime.snapshot() == initial, "terminal state does not invalidate historical accepted snapshot")
		var moved := {"x": 16.0, "y": -12.0}
		suite.assert_true(runtime.bind_origin(moved), "empty accepted origin can be rebound")
		suite.assert_true(not runtime.can_restore_snapshot(initial), "warm entry cannot cross changed arena origin")
		suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "new origin validates independently")
		var alternate := identity.duplicate(true)
		alternate.hostile_source_id = "other-owner"
		suite.assert_true(runtime.configure(definition, alternate).ok and not runtime.can_restore_snapshot(initial), "cache cannot cross reconfigured owner")
		var before_failed_config: Dictionary = runtime.snapshot()
		suite.assert_true(not runtime.configure({}, identity).ok, "invalid configuration is refused")
		_check_verdict(suite, runtime, before_failed_config, false, "failed configuration preserves cold admission policy")
		var threads: Array[Thread] = []
		for worker: int in range(3):
			var thread := Thread.new()
			threads.append(thread)
			var local_identity := identity.duplicate(true)
			local_identity.hostile_source_id = "reader-%d" % worker
			suite.assert_equal(thread.start(func() -> bool:
				var local: RefCounted = RUNTIMES[id].new()
				if not local.configure(definition, local_identity).ok:
					return false
				var accepted: Dictionary = local.snapshot()
				for _step: int in range(10):
					if not local.can_restore_snapshot(accepted):
						return false
					var forged := accepted.duplicate(true)
					forged[_constructs(id)][0].current_hp = -1.0
					if local.can_restore_snapshot(forged):
						return false
				return true), OK, "parallel cloned validator starts")
		for thread: Thread in threads:
			suite.assert_true(thread.wait_to_finish(), "concurrent clones preserve exact positive and forged verdicts")
		suite.assert_true(runtime.get("_validation_cache").size() <= 4, "concurrent cache stays bounded")
	suite.finish(get_tree())


func _check_verdict(suite: RefCounted, runtime: RefCounted, candidate: Dictionary, boundary: bool, label: String) -> void:
	var before_size: int = runtime.get("_validation_cache").size()
	var cold: bool = runtime.call("_can_restore_snapshot_uncached", candidate, boundary)
	suite.assert_equal(runtime.can_restore_snapshot(candidate, boundary), cold, "warm verdict equals cold authority for " + label)
	if not cold:
		suite.assert_equal(runtime.get("_validation_cache").size(), before_size, "negative verdict never occupies positive cache")


func _constructs(id: String) -> String:
	return {"void_throne": "pillars", "forge_colossus": "covers", "forest_heart": "sacs"}[id]


func _stage(runtime: RefCounted, id: String, identity: Dictionary) -> bool:
	if id == "void_throne":
		return runtime.accept_phase(2, 1).ok
	if id == "forge_colossus":
		return runtime.accept_damage_fact({"fact_id": "staged-anvil", "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "construct_id": "forge_anvil:0", "runtime_frame": 1, "amount": 30.0}).ok
	return runtime.consume_flower("forest_healing_flower:0", "player:1", 1, 13.0).ok
