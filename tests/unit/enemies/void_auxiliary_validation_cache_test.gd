extends "res://tests/unit/enemies/void_auxiliary_runtime_test.gd"

const Runtime := preload("res://scripts/enemies/launch/void_auxiliary_runtime.gd")


func _ready() -> void:
	suite = Suite.new()
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	definition = parser.runtime_projection()
	var runtime := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	suite.assert_true(runtime.reserve_cast(_cast("voidking_void_bolt", 7, 0)).ok and runtime.accept_damage_receipt(_damage(7, 0, "cache-health")).ok, "cache fixture retains authenticated cast and actual Health receipt")
	var original: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.can_restore_snapshot(original), "first exact value passes full event replay")
	var cache: Variant = _cache_entries()
	suite.assert_true(cache is Array and cache.size() > 0 and cache.size() <= 4, "successful replay retains a bounded positive validation cache")
	if not cache is Array:
		suite.finish(get_tree())
		return
	for row: Variant in cache:
		suite.assert_true(row is Dictionary and row.get("context") is PackedByteArray and row.get("snapshot") is PackedByteArray and typeof(row.get("accepted_boundary")) == TYPE_BOOL, "cache preserves full typed bytes without external mutable snapshot references")
	for _repeat: int in range(8):
		suite.assert_true(runtime.can_restore_snapshot(original), "exact positive cache remains restorable")
	for kind: String in ["schema_float", "event_float", "event_bool", "derived_bool", "terminal_bool", "event_deleted", "event_modified", "cast_removed", "status_forged", "identity", "initial_origin"]:
		var forged := original.duplicate(true)
		match kind:
			"schema_float": forged.schema_version = 1.0
			"event_float": forged.events[0].frame = 0.0
			"event_bool": forged.events[0].generation = true
			"derived_bool": forged.casts[0].retired = 0
			"terminal_bool": forged.terminal = 0
			"event_deleted": forged.events.remove_at(1)
			"event_modified": forged.events[1].actual_loss = 0.0
			"cast_removed": forged.casts.clear()
			"status_forged": forged.statuses[0].through_frame += 1
			"identity": forged.identity.hostile_source_id = "different-owner"
			"initial_origin": forged.arena_origin.x = 1.0
		suite.assert_true(not runtime.can_restore_snapshot(forged) and runtime.snapshot() == original, "warm cache rejects forged " + kind + " without mutation")
	suite.assert_true(runtime.can_restore_snapshot(original), "external snapshot mutation cannot corrupt frozen successful cache")
	var numeric := original.duplicate(true)
	numeric.casts[0].generation = 7.0
	suite.assert_true(runtime.can_restore_snapshot(numeric), "compatible derived integer representation retains original JSON equality behavior")
	var near_numeric := original.duplicate(true)
	near_numeric.casts[0].damage_multiplier = 1.000000000000001
	suite.assert_true(runtime.can_restore_snapshot(near_numeric), "existing JSON precision fallback remains compatible")
	var staged := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	suite.assert_true(staged.reserve_cast(_cast("voidking_tentacle_lash", 7, 1)).ok and staged.can_restore_snapshot(staged.snapshot()) and not staged.can_restore_snapshot(staged.snapshot(), true), "warm next-frame cache cannot bypass strict accepted boundary")
	suite.assert_true(staged.advance_frame(1) and staged.can_restore_snapshot(staged.snapshot(), true), "accepted boundary gets independently validated after actual commit")
	var shifted := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	suite.assert_true(shifted.bind_origin({"x": 16.0, "y": 0.0}) and not shifted.can_restore_snapshot(original), "cache isolates exact configured initial arena origin")
	var alternate_initial := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	var changed_initial: Dictionary = alternate_initial.get("_initial")
	changed_initial.exposure_through_frame -= 1
	suite.assert_true(not alternate_initial.can_restore_snapshot(original), "cache isolates full initial replay state beyond public header fields")
	var changed_definition := definition.duplicate(true)
	changed_definition.defense += 1.0
	var source := Runtime.new()
	suite.assert_true(source.configure(changed_definition, identity).ok and not source.can_restore_snapshot(original), "cache isolates authored source digest")
	changed_definition.defense += 1.0
	suite.assert_true(source.can_restore_snapshot(source.snapshot()), "caller source mutation cannot alter configured or cached state")
	for _frame: int in range(1, 9):
		suite.assert_true(runtime.advance_frame(_frame) and runtime.can_restore_snapshot(runtime.snapshot()), "new exact frame receives its own validated cache entry")
	suite.assert_true(_cache_entries().size() <= 4, "cache never grows beyond four complete snapshots")
	var retained: Dictionary = runtime.snapshot()
	var threads: Array[Thread] = []
	for _worker: int in range(5):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _step: int in range(40):
				if not runtime.can_restore_snapshot(retained, true):
					return false
				var forged := retained.duplicate(true)
				forged.statuses[0].multiplier = 0.4
				if runtime.can_restore_snapshot(forged, true):
					return false
			return true), OK, "parallel cache validation worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent native cache calls retain true and forged verdicts")
	suite.assert_true(_cache_entries().size() <= 4 and runtime.snapshot() == retained, "thread-safe cache recording stays bounded and leaves domain state exact")
	suite.finish(get_tree())


func _cache_entries() -> Variant:
	var source: Script = load("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	return source.get("_validation_cache")
