extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")


func _ready() -> void:
	var suite := Suite.new()
	var definition := {"id": "ruin_king", "actor_kind": "boss", "actions": Content.boss("ruin_king").actions}
	var identity := Fixtures.identity()
	var runtime := Action.new()
	var first: Dictionary = runtime.configure(definition, identity)
	suite.assert_true(first.ok, "cache fixture starts from fully accepted actual Boss actions")
	var source: Script = load("res://scripts/enemies/launch/hostile_action_coordinator.gd")
	var entries: Variant = source.get("_configuration_cache")
	suite.assert_true(entries is Array and entries.size() > 0 and entries.size() <= 4, "successful action parsing requires a bounded positive configuration cache")
	if not entries is Array:
		suite.finish(get_tree())
		return
	for entry: Dictionary in entries:
		suite.assert_true(entry.get("source") is PackedByteArray and entry.get("state") is PackedByteArray, "configuration cache stores detached full typed bytes")
	var original: Dictionary = runtime.snapshot()
	var original_actions: Dictionary = runtime.get("_actions").duplicate(true)
	var original_definition: Dictionary = runtime.get("_definition").duplicate(true)
	for _repeat: int in range(8):
		suite.assert_equal(runtime.configure(definition, identity), first, "exact configuration hit preserves complete returned result")
		var returned: Dictionary = runtime.configure(definition, identity)
		returned.snapshot.cooldowns["forged"] = 999
		suite.assert_equal(runtime.snapshot(), original, "returned mutable state cannot poison current or cached configuration")
	runtime.get("_actions")[definition.actions[0].id].warning_frames = -1
	runtime.get("_definition").actions[0].parameters["forged"] = true
	suite.assert_equal(runtime.configure(definition, identity), first, "instance definition mutation cannot poison accepted configuration bytes")
	suite.assert_equal(runtime.get("_actions"), original_actions, "every cache hit restores independent normalized actions")
	suite.assert_equal(runtime.get("_definition"), original_definition, "every cache hit restores the authentic digest source")
	for variation: String in ["float_warning", "fractional_warning", "bool_warning", "foreign_action", "extra_field", "float_identity", "fractional_identity", "bool_identity", "foreign_kind", "missing_actions"]:
		var changed := definition.duplicate(true)
		var changed_identity := identity.duplicate(true)
		match variation:
			"float_warning": changed.actions[0].warning_frames = float(changed.actions[0].warning_frames)
			"fractional_warning": changed.actions[0].warning_frames += 0.25
			"bool_warning": changed.actions[0].warning_frames = true
			"foreign_action": changed.actions[0].id = "foreign.action"
			"extra_field": changed.unexpected = true
			"float_identity": changed_identity.runtime_frame = float(changed_identity.runtime_frame)
			"fractional_identity": changed_identity.runtime_frame += 0.25
			"bool_identity": changed_identity.runtime_frame = false
			"foreign_kind": changed.actor_kind = "unknown"
			"missing_actions": changed.erase("actions")
		var cold := Action.new()
		var cold_result: Dictionary = cold.call("_configure_uncached", changed, changed_identity)
		var cache_size: int = source.get("_configuration_cache").size()
		var warm_result: Dictionary = runtime.configure(changed, changed_identity)
		suite.assert_equal(warm_result, cold_result, "warm cache preserves complete cold parser verdict for " + variation)
		if variation in ["float_warning", "float_identity"]:
			suite.assert_true(warm_result.ok, "integral JSON numbers retain established acceptance for " + variation)
			suite.assert_equal(runtime.snapshot(), cold.snapshot(), "accepted typed variant retains exact cold normalized state for " + variation)
		else:
			suite.assert_true(not warm_result.ok and runtime.snapshot().is_empty(), "failed varied source clears previous configuration for " + variation)
			suite.assert_equal(source.get("_configuration_cache").size(), cache_size, "refused source never populates configuration cache for " + variation)
		suite.assert_equal(runtime.configure(definition, identity), first, "accepted source restores exact configuration after refusal")
	var alternate := identity.duplicate(true)
	alternate.hostile_source_id = "hostile:cache-other"
	alternate.runtime_frame = 7
	alternate.next_generation_floor = 11
	var second := Action.new()
	suite.assert_true(second.configure(definition, alternate).ok, "different initial identity receives independent full configuration")
	suite.assert_equal(second.snapshot().identity, alternate, "cache key retains complete initial identity")
	suite.assert_true(not second.can_restore_snapshot(original), "cached configuration never admits another owner's snapshot")
	var changed := definition.duplicate(true)
	changed.actions[0].warning_frames += 1
	var cold := Action.new()
	suite.assert_equal(runtime.configure(changed, identity), cold.call("_configure_uncached", changed, identity), "valid changed source is revalidated and independently normalized")
	changed.actions[0].warning_frames += 1
	suite.assert_equal(runtime.configure(definition, identity), first, "caller mutation never changes retained typed bytes")
	suite.assert_true(runtime.request_action(definition.actions[0].id, Fixtures.context(0)).ok, "configuration hit still drives actual authored warning")
	var active: Dictionary = runtime.snapshot()
	var clone := Action.new()
	suite.assert_true(clone.configure(definition, identity).ok and clone.restore_snapshot(active), "cached initial definition preserves active action cold restore")
	var forged := active.duplicate(true)
	forged.geometry_generations[0] = float(forged.geometry_generations[0])
	suite.assert_true(not clone.restore_snapshot(forged) and clone.snapshot() == active, "warm definition never bypasses typed active snapshot validation")
	for index: int in range(9):
		var distinct := identity.duplicate(true)
		distinct.hostile_source_id = "hostile:cache-%d" % index
		suite.assert_true(Action.new().configure(definition, distinct).ok, "eviction fixture accepts independent owner")
		suite.assert_true(source.get("_configuration_cache").size() <= 4, "full configuration cache capacity stays at four")
	var threads: Array[Thread] = []
	for _worker: int in range(5):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _step: int in range(20):
				var worker := Action.new()
				if worker.configure(definition, identity) != first:
					return false
				var invalid := definition.duplicate(true)
				invalid.actions[0].warning_frames = true
				if worker.configure(invalid, identity).ok or not worker.snapshot().is_empty():
					return false
			return true), OK, "concurrent configuration worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent cache preserves authentic and refused source results")
	suite.assert_true(source.get("_configuration_cache").size() <= 4, "concurrent configuration cache remains bounded")
	suite.finish(get_tree())
