extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
var suite: RefCounted


class CountedRuin extends "res://scripts/enemies/launch/boss_arena_runtime.gd":
	var boundaries: Array[bool] = []
	func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
		boundaries.append(accepted_boundary)
		return super.can_restore_snapshot(value, accepted_boundary)


class CountedForest extends "res://scripts/enemies/launch/forest_arena_runtime.gd":
	var boundaries: Array[bool] = []
	func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
		boundaries.append(accepted_boundary)
		return super.can_restore_snapshot(value, accepted_boundary)


class CountedFlowers extends "res://scripts/enemies/launch/forest_auxiliary_runtime.gd":
	var boundaries: Array[bool] = []
	func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
		boundaries.append(accepted_boundary)
		return super.can_restore_snapshot(value, accepted_boundary)


class CountedVoid extends "res://scripts/enemies/launch/void_arena_runtime.gd":
	var boundaries: Array[bool] = []
	func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
		boundaries.append(accepted_boundary)
		return super.can_restore_snapshot(value, accepted_boundary)


class CountedVoidAuxiliary extends "res://scripts/enemies/launch/void_auxiliary_runtime.gd":
	var boundaries: Array[bool] = []
	func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
		boundaries.append(accepted_boundary)
		return super.can_restore_snapshot(value, accepted_boundary)


class CountedForge extends "res://scripts/enemies/launch/forge_arena_runtime.gd":
	var boundaries: Array[bool] = []
	func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
		boundaries.append(accepted_boundary)
		return super.can_restore_snapshot(value, accepted_boundary)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		var parser := Definition.new()
		suite.assert_true(parser.configure(row).ok, "single-pass fixture uses authored Boss " + row.id)
		var identity := Actions.identity()
		identity.seed = 42
		var runtime := Boss.new()
		suite.assert_true(runtime.configure(parser.runtime_projection(), identity).ok, "actual Boss configures full authority")
		var saved := runtime.snapshot()
		var children := _install_counted_children(runtime, identity)
		runtime.call("_clear_snapshot_validation_cache")
		_reset_counts(children)
		suite.assert_true(runtime.can_restore_native_snapshot(saved), "cold complete native boundary remains restorable")
		_assert_counts(children, [true], "cold native validates each child once with the accepted-frame constraint: " + row.id)
		_reset_counts(children)
		for _repeat: int in range(8):
			suite.assert_true(runtime.can_restore_native_snapshot(saved), "repeated exact complete native boundary remains restorable")
		_assert_counts(children, [], "warm native verdict avoids repeating complete child validations: " + row.id)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(saved), "read-only native validation preserves every typed gameplay field")
		runtime.call("_clear_snapshot_validation_cache")
		_reset_counts(children)
		suite.assert_true(runtime.can_restore_snapshot(saved), "general restore still performs its complete independent validation")
		_assert_counts(children, [false], "general restore retains staged-event policy")
		_reset_counts(children)
		suite.assert_true(runtime.can_restore_native_snapshot(saved), "a general positive verdict cannot certify a native boundary")
		_assert_counts(children, [true], "general warm cache cannot omit native child authority")
		_test_forgery_and_isolation(runtime, saved)
		_test_history(runtime)
		_test_concurrency(runtime)
		if row.id == "forest_heart":
			_test_staged_flower(runtime, children)
	suite.finish(get_tree())


func _install_counted_children(runtime: RefCounted, identity: Dictionary) -> Array[RefCounted]:
	var replacements: Dictionary = {}
	match str(runtime.get("_definition").id):
		"ruin_king": replacements = {"_arena": CountedRuin.new()}
		"forest_heart": replacements = {"_arena": CountedForest.new(), "_forest_auxiliary": CountedFlowers.new()}
		"void_throne": replacements = {"_void_arena": CountedVoid.new(), "_void_auxiliary": CountedVoidAuxiliary.new()}
		"forge_colossus": replacements = {"_forge_arena": CountedForge.new()}
	var children: Array[RefCounted] = []
	for field: String in replacements:
		var original: RefCounted = runtime.get(field)
		var child: RefCounted = replacements[field]
		suite.assert_true(child.configure(runtime.get("_definition"), identity).ok, "counted child calls the actual production configuration")
		if child.has_method("bind_origin"):
			suite.assert_true(child.bind_origin(runtime.get("_arena_origin")), "counted child binds the actual arena origin")
		suite.assert_true(child.restore_snapshot(original.snapshot()), "counted child retains actual typed initial authority")
		runtime.set(field, child)
		children.append(child)
	return children


func _reset_counts(children: Array[RefCounted]) -> void:
	for child: RefCounted in children:
		child.get("boundaries").clear()


func _assert_counts(children: Array[RefCounted], expected: Array, message: String) -> void:
	for child: RefCounted in children:
		suite.assert_equal(child.get("boundaries"), expected, message)


func _test_forgery_and_isolation(runtime: RefCounted, saved: Dictionary) -> void:
	var before := var_to_bytes(runtime.snapshot())
	for field: String in ["schema", "frame", "owner", "action", "conversion"]:
		var forged := saved.duplicate(true)
		match field:
			"schema": forged.schema_version = float(forged.schema_version)
			"frame": forged.runtime_frame = float(forged.runtime_frame) + 0.5
			"owner": forged.identity.hostile_source_id = "foreign-native-owner"
			"action": forged.action.next_generation_floor = float(forged.action.next_generation_floor)
			"conversion": forged.conversion.extra = true
		suite.assert_true(not runtime.can_restore_native_snapshot(forged), "native cache preserves full typed refusal for " + field)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "refused native validation cannot mutate domain state")
	var mutable := saved.duplicate(true)
	suite.assert_true(runtime.can_restore_native_snapshot(mutable), "native cache accepts an independently detached caller snapshot")
	mutable.mechanism_state.health_claims.append("caller")
	mutable.action.cooldowns["caller"] = 999
	suite.assert_true(runtime.can_restore_native_snapshot(saved), "caller mutations cannot poison an exact retained native verdict")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "public snapshot and native cache remain detached")
	if runtime.get("_definition").id != "time_sovereign":
		var origin: Dictionary = runtime.get("_arena_origin")
		origin.x += 1.0
		suite.assert_equal(runtime.can_restore_native_snapshot(saved), _original_native_verdict(runtime, saved), "live arena context cannot reuse a prior native cache verdict")
		origin.x -= 1.0


func _original_native_verdict(runtime: RefCounted, value: Dictionary) -> bool:
	if not runtime.call("_can_restore_snapshot_uncached", value):
		return false
	for pair: Array in [["_arena", "arena_state"], ["_forest_auxiliary", "forest_auxiliary"], ["_void_arena", "void_arena_state"], ["_void_auxiliary", "void_auxiliary"], ["_forge_arena", "forge_arena_state"]]:
		var child: RefCounted = runtime.get(pair[0])
		if child != null and not child.can_restore_snapshot(value[pair[1]], true):
			return false
	return true


func _test_history(runtime: RefCounted) -> void:
	var saved: Dictionary = runtime.snapshot()
	for offset: int in range(1, 7):
		var frame := int(saved.runtime_frame) + offset
		suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "native fixture advances real sequential Boss frames")
		var value: Dictionary = runtime.snapshot()
		suite.assert_equal(runtime.can_restore_native_snapshot(value), _original_native_verdict(runtime, value), "single native pass agrees with original two-pass complete authority")
		suite.assert_true(runtime.can_restore_snapshot(value), "native and general cached modes preserve historical restoration")
		suite.assert_true(runtime.get("_snapshot_validation_cache").size() <= 4, "mixed boundary modes retain bounded exact snapshot storage")
	suite.assert_true(runtime.restore_snapshot(saved), "historical native boundary still restores through full production installation")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(saved), "historical restore preserves every typed child state")


func _test_concurrency(runtime: RefCounted) -> void:
	var saved: Dictionary = runtime.snapshot()
	var production := Boss.new()
	suite.assert_true(production.configure(runtime.get("_definition"), saved.identity).ok and production.restore_snapshot(saved), "concurrent fixture uses original uninstrumented production authority")
	suite.assert_true(production.can_restore_native_snapshot(saved) and production.can_restore_snapshot(saved), "concurrency fixture warms both authentic boundary modes")
	var threads: Array[Thread] = []
	for _worker: int in range(3):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _repeat: int in range(10):
				if not production.can_restore_native_snapshot(saved) or not production.can_restore_snapshot(saved):
					return false
				var forged: Dictionary = saved.duplicate(true)
				forged.terminal = 0
				if production.can_restore_native_snapshot(forged):
					return false
			return true), OK, "concurrent mixed native/general validation worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent exact caches preserve full authentic and forged verdicts")
	suite.assert_equal(var_to_bytes(production.snapshot()), var_to_bytes(saved), "concurrent read-only validation cannot mutate any authority")


func _test_staged_flower(runtime: RefCounted, children: Array[RefCounted]) -> void:
	var auxiliary: RefCounted = runtime.get("_forest_auxiliary")
	suite.assert_true(auxiliary.consume_flower("forest_healing_flower:0", "player:1", 1, 10.0).get("ok", false), "fixture stages a genuine next-frame flower event")
	var staged: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.can_restore_snapshot(staged), "general restore still admits the authored next-frame event")
	_reset_counts(children)
	suite.assert_true(not runtime.can_restore_native_snapshot(staged), "general warm cache cannot admit a staged next-frame native event")
	for child: RefCounted in children:
		var boundaries: Array = child.get("boundaries")
		suite.assert_true(boundaries.size() <= 1 and not boundaries.has(false), "native refusal cannot repeat a weaker general child pass")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(staged), "native refusal preserves the staged event exactly for ordinary rollback")
