extends "res://tests/unit/enemies/void_auxiliary_runtime_test.gd"

const Runtime := preload("res://scripts/enemies/launch/void_auxiliary_runtime.gd")

class CountingRuntime extends "res://scripts/enemies/launch/void_auxiliary_runtime.gd":
	var replay_calls := 0

	func _apply(state: Dictionary, event: Dictionary) -> Dictionary:
		replay_calls += 1
		return super._apply(state, event)


func _ready() -> void:
	suite = Suite.new()
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	definition = parser.runtime_projection()
	var live := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	suite.assert_true(live.reserve_cast(_cast("voidking_scepter_strike", 7, 0)).ok and live.accept_damage_receipt(_damage(7, 0, "burn-health")).ok, "actual cast and damage establish finite burn history")
	suite.assert_true(live.reserve_cast(_cast("voidking_void_bolt", 8, 0)).ok and live.accept_damage_receipt(_damage(8, 0, "slow-health")).ok, "actual bolt receipt establishes exclusive slow expiry")
	var validator := CountingRuntime.new()
	suite.assert_true(validator.configure(definition, identity).ok, "counting validator configures canonical authority")
	var frames := [0, 1, 2, 119, 120, 121, 179, 180, 181]
	var retained: Array[Dictionary] = []
	for frame: int in frames:
		_clock(live, frame)
		var value: Dictionary = live.snapshot()
		retained.append(value)
		_clear_full_cache()
		suite.assert_true(validator.can_restore_snapshot(value, true), "complete derived value is authentic at frame " + str(frame))
		var fresh := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
		_clear_full_cache()
		suite.assert_true(fresh.can_restore_snapshot(value, true), "fresh replay and warm replay agree at frame " + str(frame))
		suite.assert_equal(var_to_bytes(live.snapshot()), var_to_bytes(value), "validation leaves actual domain bytes unchanged")
	suite.assert_equal(validator.replay_calls, retained[0].events.size(), "identical event history is replayed once across new accepted frames")
	for value: Dictionary in retained:
		_clear_full_cache()
		suite.assert_true(validator.can_restore_snapshot(value, true), "earlier accepted frame can be reconstructed without a later expiry state")
		var forged := value.duplicate(true)
		forged.exposure_through_frame += 1
		suite.assert_true(not validator.can_restore_snapshot(forged, true), "matching event history never certifies forged derived state")
	_history_changes(validator, retained[0])
	_staged_and_terminal(validator)
	_checkpoint_bound(validator)
	_reconfiguration(validator, retained[0])
	suite.finish(get_tree())


func _history_changes(validator: RefCounted, original: Dictionary) -> void:
	for kind: String in ["float_frame", "bool_generation", "deleted", "changed", "extra", "foreign"]:
		var forged := original.duplicate(true)
		match kind:
			"float_frame": forged.events[0].frame = 0.0
			"bool_generation": forged.events[0].generation = true
			"deleted": forged.events.pop_back()
			"changed": forged.events[1].actual_loss = 0.0
			"extra": forged.events[0].extra = null
			"foreign": forged.identity.run_id = "other-run"
		suite.assert_true(not validator.can_restore_snapshot(forged, true), "warm history checkpoint rejects " + kind)
	var before := var_to_bytes(original)
	var near_numeric := original.duplicate(true)
	near_numeric.casts[0].damage_multiplier = 1.000000000000001
	suite.assert_true(validator.can_restore_snapshot(near_numeric, true), "complete derived comparison retains existing JSON precision compatibility")
	suite.assert_equal(var_to_bytes(original), before, "checkpoint storage cannot mutate caller snapshots")
	var changed_initial: Dictionary = validator.get("_initial")
	changed_initial.exposure_through_frame -= 1
	_clear_full_cache()
	suite.assert_true(not validator.can_restore_snapshot(original, true), "exact initial-state context invalidates previously authenticated history")
	changed_initial.exposure_through_frame += 1
	_clear_full_cache()
	suite.assert_true(validator.can_restore_snapshot(original, true), "restored initial context can fully reconstruct original history")


func _staged_and_terminal(validator: RefCounted) -> void:
	var live := _runtime("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	suite.assert_true(live.reserve_cast(_cast("voidking_tentacle_lash", 7, 1)).ok, "real next-frame action creates staged history")
	var staged: Dictionary = live.snapshot()
	_clear_full_cache()
	suite.assert_true(validator.can_restore_snapshot(staged) and not validator.can_restore_snapshot(staged, true), "staged history never bypasses strict accepted-frame boundary")
	suite.assert_true(live.advance_frame(1) and validator.can_restore_snapshot(live.snapshot(), true), "actual commit admits staged history after its event frame")
	suite.assert_true(live.accept_phase(1, 2).ok and live.advance_frame(2) and validator.can_restore_snapshot(live.snapshot(), true), "phase retirement is authenticated through complete event replay")
	live.retire()
	var terminal: Dictionary = live.snapshot()
	suite.assert_true(validator.can_restore_snapshot(terminal, true), "terminal event remains reconstructable")
	var forged := terminal.duplicate(true)
	forged.terminal = false
	suite.assert_true(not validator.can_restore_snapshot(forged, true), "warm terminal history refuses forged live state")
	var workers: Array[Thread] = []
	for _index: int in range(3):
		var worker := Thread.new()
		workers.append(worker)
		suite.assert_equal(worker.start(func() -> bool:
			for repeat: int in range(8):
				var later := terminal.duplicate(true)
				later.runtime_frame += repeat + 1
				var later_forged := later.duplicate(true)
				later_forged.terminal = false
				if not validator.can_restore_snapshot(later, true) or validator.can_restore_snapshot(later_forged, true):
					return false
			return true), OK, "parallel history validator starts")
	for worker: Thread in workers:
		suite.assert_true(worker.wait_to_finish(), "concurrent checkpoint reuse preserves authentic and forged verdicts")


func _checkpoint_bound(validator: RefCounted) -> void:
	var checkpoint: Variant = validator.get("_event_replay_checkpoint")
	suite.assert_true(checkpoint is Dictionary and not checkpoint.is_empty(), "successful event replay retains one private checkpoint")
	if not checkpoint is Dictionary or checkpoint.is_empty():
		return
	suite.assert_true(checkpoint.context is PackedByteArray and checkpoint.events is PackedByteArray and checkpoint.replay is PackedByteArray, "retained checkpoint contains typed bytes rather than caller-owned mutable references")
	suite.assert_true(checkpoint.events.size() <= 524288 and checkpoint.replay.size() <= 1048576, "event and replay retention are explicitly bounded")


func _reconfiguration(validator: RefCounted, original: Dictionary) -> void:
	suite.assert_true(validator.configure(definition, identity).ok, "successful reconfiguration keeps canonical authority")
	suite.assert_equal(validator.get("_event_replay_checkpoint"), {}, "reconfiguration releases retained historical checkpoint")
	suite.assert_true(validator.bind_origin({"x": 16.0, "y": 0.0}), "new authority binds another initial origin")
	suite.assert_true(not validator.can_restore_snapshot(original, true), "changed origin cannot reuse original history certificate")
	suite.assert_true(validator.bind_origin({"x": 0.0, "y": 0.0}), "initial origin can be reversibly restored")
	_clear_full_cache()
	suite.assert_true(validator.can_restore_snapshot(original, true), "restored configured origin fully authenticates old history")
	var foreign_identity := identity.duplicate(true)
	foreign_identity.run_id = "other-run"
	suite.assert_true(validator.configure(definition, foreign_identity).ok, "authority can reconfigure to a distinct run")
	suite.assert_equal(validator.get("_event_replay_checkpoint"), {}, "distinct run configuration releases prior checkpoint")
	suite.assert_true(not validator.can_restore_snapshot(original, true), "new run identity rejects old authenticated history")


func _clear_full_cache() -> void:
	var source: Script = load("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
	var cache: Array = source.get("_validation_cache")
	cache.clear()
