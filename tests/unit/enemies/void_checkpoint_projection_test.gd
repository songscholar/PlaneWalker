extends "res://tests/unit/enemies/void_auxiliary_runtime_test.gd"

const Runtime := preload("res://scripts/enemies/launch/void_auxiliary_runtime.gd")


class CustomRuntime extends "res://scripts/enemies/launch/void_auxiliary_runtime.gd":
	func extension_marker() -> bool:
		return true


func _ready() -> void:
	suite = Suite.new()
	var parser := Definition.new()
	suite.assert_true(parser.configure(Content.boss("void_throne")).ok, "frozen history uses actual authored Void definition")
	definition = parser.runtime_projection()
	var live := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	suite.assert_true(live.reserve_cast(_cast("voidking_scepter_strike", 7, 0)).ok and live.accept_damage_receipt(_damage(7, 0, "frozen-burn")).ok, "actual cast and Health receipt establish burn history")
	suite.assert_true(live.reserve_cast(_cast("voidking_void_bolt", 8, 0)).ok and live.accept_damage_receipt(_damage(8, 0, "frozen-slow")).ok, "actual projectile receipt establishes exclusive slow expiry")
	var validator := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	var value: Dictionary = live.snapshot()
	suite.assert_true(validator.can_restore_snapshot(value, true), "production validator authenticates complete initial event history")
	var checkpoint: Dictionary = validator.get("_event_replay_checkpoint")
	var first: Dictionary = validator.call("_event_checkpoint_replay", checkpoint.context, checkpoint.events, 0)
	var second: Dictionary = validator.call("_event_checkpoint_replay", checkpoint.context, checkpoint.events, 0)
	suite.assert_true(not first.is_empty() and not second.is_empty(), "two actual warm checkpoint queries retain complete authenticated values")
	if not first.is_empty() and not second.is_empty():
		suite.assert_true(is_same(first.events, second.events), "warm production queries share event history instead of decoding it twice")
		suite.assert_true(first.events.is_read_only() and first.events[0].is_read_only() and first.events[0].geometry.is_read_only() and first.events[0].geometry[0].is_read_only(), "every shared event container is immutable")
		suite.assert_true(first.casts.is_read_only() and first.casts[0].is_read_only() and first.burns.is_read_only(), "all shared derived history containers are immutable")
		first.runtime_frame = 181
		Runtime._refresh(first)
		suite.assert_true(first.burns.is_empty() and first.statuses.is_empty() and second.runtime_frame == 0 and second.burns.size() == 1 and second.statuses.size() == 1, "mutable frame and expiry projection cannot change another historical query")
		suite.assert_equal(var_to_bytes(second), var_to_bytes(value), "warm retained history preserves every original typed field")
		var restored := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
		suite.assert_true(restored.restore_snapshot(second), "public restoration still owns a complete private domain state")
		var public_value: Dictionary = restored.snapshot()
		suite.assert_true(not public_value.events.is_read_only() and not public_value.events[0].is_read_only(), "public snapshots retain detached mutable event containers")
		public_value.events[0].geometry[0].radius += 1.0
		suite.assert_equal(var_to_bytes(restored.snapshot()), var_to_bytes(second), "public nested edits cannot reach restored or retained historical state")
		suite.assert_true(restored.advance_frame(1) and restored.reserve_cast(_cast("voidking_scepter_strike", 9, 1)).ok, "restored live domain can advance and append independently from frozen historical state")
	value.events[0].frame = 0.0
	suite.assert_true(not validator.can_restore_snapshot(value, true), "shared immutable history refuses a numerically equal float event authority")
	suite.assert_equal(var_to_bytes(second), var_to_bytes(live.snapshot()), "caller event edits cannot mutate retained checkpoint history")
	var custom := CustomRuntime.new()
	suite.assert_true(custom.configure(definition, identity).ok, "custom runtime configures original authored authority")
	_clear_full_cache()
	suite.assert_true(custom.can_restore_snapshot(live.snapshot(), true), "custom runtime retains complete original event replay validation")
	var custom_checkpoint: Dictionary = custom.get("_event_replay_checkpoint")
	var custom_first: Dictionary = custom.call("_event_checkpoint_replay", custom_checkpoint.context, custom_checkpoint.events, 0)
	var custom_second: Dictionary = custom.call("_event_checkpoint_replay", custom_checkpoint.context, custom_checkpoint.events, 0)
	suite.assert_true(not custom_first.events.is_read_only() and not custom_first.events[0].is_read_only() and not is_same(custom_first.events, custom_second.events), "custom runtime keeps private mutable history per query")
	custom_first.events[0].geometry[0].radius += 1.0
	suite.assert_equal(var_to_bytes(custom_second), var_to_bytes(live.snapshot()), "custom history mutation cannot change another complete query")
	for frame: int in [1, 119, 120, 121, 179, 180, 181]:
		_clock(live, frame)
		var authentic: Dictionary = live.snapshot()
		_clear_full_cache()
		suite.assert_true(validator.can_restore_snapshot(authentic, true), "shared event history validates exact finite expiry at frame " + str(frame))
		var fresh := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
		_clear_full_cache()
		suite.assert_true(fresh.can_restore_snapshot(authentic, true), "fresh complete replay agrees with warm immutable history")
	var workers: Array[Thread] = []
	var terminal_value: Dictionary = live.snapshot()
	for _index: int in range(3):
		var worker := Thread.new()
		workers.append(worker)
		suite.assert_equal(worker.start(func() -> bool:
			var private_history: Dictionary = validator.call("_event_checkpoint_replay", checkpoint.context, checkpoint.events, 181)
			if private_history.is_empty() or private_history.events.is_read_only():
				return false
			for repeat: int in range(12):
				var later := terminal_value.duplicate(true)
				later.runtime_frame += repeat + 1
				var forged := later.duplicate(true)
				forged.exposure_through_frame += 1
				if not validator.can_restore_snapshot(later, true) or validator.can_restore_snapshot(forged, true):
					return false
			return true), OK, "concurrent production checkpoint projection worker starts")
	for worker: Thread in workers:
		suite.assert_true(worker.wait_to_finish(), "concurrent frame projections preserve authentic and forged verdicts")
	suite.assert_equal(var_to_bytes(live.snapshot()), var_to_bytes(terminal_value), "concurrent read-only history validation preserves live domain state")
	suite.finish(get_tree())


func _clear_full_cache() -> void:
	var source: Script = load("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	var cache: Array = source.get("_validation_cache")
	cache.clear()
