extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const COMPONENTS := ["_action", "_control", "_conversion", "_arena", "_forest_auxiliary", "_void_arena", "_void_auxiliary", "_forge_arena", "_time_response", "_time_auxiliary"]
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class ObservationProbe extends RefCounted:
	var authority: RefCounted
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return authority.snapshot()

	func matches_snapshot(value: Dictionary) -> bool:
		return authority.call("matches_snapshot", value)


class SnapshotOnlyProbe extends RefCounted:
	var authority: RefCounted
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return authority.snapshot()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var empty := CountingBoss.new()
	suite.assert_true(empty.has_method("matches_snapshot"), "Boss complete equality observations need a runtime-owned no-copy predicate")
	if not empty.has_method("matches_snapshot"):
		suite.finish(get_tree())
		return
	suite.assert_true(empty.call("matches_snapshot", {}) and not empty.call("matches_snapshot", {"unexpected": true}), "unconfigured complete equality retains empty snapshot behavior")
	for row: Dictionary in Content.read_catalog("bosses.json"):
		_check_boss(row)
	suite.finish(get_tree())


func _check_boss(row: Dictionary) -> void:
	var parser := Definition.new()
	suite.assert_true(parser.configure(row).ok, "comparison consumes authored Boss " + row.id)
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var runtime := CountingBoss.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "comparison configures real complete Boss authority")
	var initial := runtime.snapshot()
	_assert_comparison(runtime, "configured " + row.id, true)
	var action: Dictionary = definition.actions[1 if row.id == "forest_heart" else 0]
	suite.assert_true(runtime.request_action(str(action.id), _context(0, action)).ok, "authored action enters comparison warning")
	_assert_comparison(runtime, "warning " + row.id, true)
	var duration: int = int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames)
	var exposure_seen := false
	for frame: int in range(1, duration + 2):
		suite.assert_true(runtime.advance_frame(frame, _context(frame, action), false).ok, "authentic frame advances complete comparison state")
		if not exposure_seen and runtime.native_action_snapshot().phase == "RECOVERY":
			suite.assert_true(runtime.extend_character_boss_exposure(1, 18), "actual recovery stages complete Character exposure")
			exposure_seen = true
			_assert_comparison(runtime, "pending exposure " + row.id, false)
		if frame in [int(action.warning_frames), int(action.warning_frames) + int(action.active_frames), duration + 1]:
			_assert_comparison(runtime, "action frame %d %s" % [frame, row.id], true)
	suite.assert_true(exposure_seen and runtime.is_exposed(), "real recovery tail exposes the complete domain state")
	suite.assert_true(runtime.add_control_source("comparison-rift", "rift", 30, 0.7), "real control state joins the complete comparison")
	_assert_comparison(runtime, "control and exposure " + row.id, true)
	var hp_after := float(definition.max_hp) * float(definition.phases.back().hp_threshold)
	suite.assert_true(runtime.accept_damage_fact({"fact_id": "comparison-phase", "runtime_frame": duration + 2, "target_source_id": identity.hostile_source_id, "amount": float(definition.max_hp) - hp_after, "hp_after": hp_after}).ok, "real body loss changes every related phase authority")
	_assert_comparison(runtime, "phase transition " + row.id, true)
	suite.assert_true(runtime.cancel(&"comparison").ok, "real Boss terminal state retires every related authority")
	_assert_comparison(runtime, "terminal " + row.id, true)
	suite.assert_true(runtime.restore_snapshot(initial), "comparison preserves complete historical restoration")
	_assert_comparison(runtime, "historical rollback " + row.id, true)
	_test_component_fallback(runtime, row.id)
	var checkpoint := runtime.snapshot()
	var threads: Array[Thread] = []
	for _worker: int in range(3):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _step: int in range(16):
				if not runtime.call("matches_snapshot", checkpoint):
					return false
				var forged := checkpoint.duplicate(true)
				forged.unexpected = true
				if runtime.call("matches_snapshot", forged):
					return false
			return true), OK, "parallel complete comparison worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "parallel comparisons preserve complete live verdicts")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(checkpoint), "parallel complete observations leave every typed gameplay field unchanged")


func _assert_comparison(runtime: RefCounted, label: String, exhaustive: bool) -> void:
	var complete: Dictionary = runtime.snapshot()
	var before := var_to_bytes(complete)
	var probes := {}
	for field: String in COMPONENTS:
		var authority: RefCounted = runtime.get(field)
		if authority == null:
			continue
		suite.assert_true(authority.has_method("matches_snapshot"), "every configured leaf owns its complete comparison: " + field)
		if not authority.has_method("matches_snapshot"):
			continue
		var probe := ObservationProbe.new()
		probe.authority = authority
		probes[field] = probe
		runtime.set(field, probe)
	runtime.full_snapshot_calls = 0
	for _repeat: int in range(16):
		suite.assert_true(runtime.call("matches_snapshot", complete), "complete no-copy observation matches original snapshot: " + label)
	if exhaustive:
		var paths: Array[Array] = []
		_collect_paths(complete, [], paths)
		for path: Array in paths:
			var changed := complete.duplicate(true)
			var original: Variant = _at(changed, path)
			_set_at(changed, path, _changed(original))
			suite.assert_equal(runtime.call("matches_snapshot", changed), complete == changed, "nested mutation preserves original complete equality: " + label + str(path))
			if typeof(original) in [TYPE_INT, TYPE_FLOAT]:
				_set_at(changed, path, float(original) if typeof(original) == TYPE_INT else int(original))
				suite.assert_equal(runtime.call("matches_snapshot", changed), complete == changed, "numeric types preserve original Godot equality: " + label + str(path))
		for field: Variant in complete:
			var missing := complete.duplicate(true)
			missing.erase(field)
			suite.assert_equal(runtime.call("matches_snapshot", missing), complete == missing, "missing complete field preserves equality: " + label + str(field))
			if complete[field] is Dictionary:
				var malformed := complete.duplicate(true)
				malformed[field] = "wrong-type"
				suite.assert_equal(runtime.call("matches_snapshot", malformed), complete == malformed, "wrong child type preserves equality: " + label + str(field))
				var extra := complete.duplicate(true)
				extra[field]["unexpected"] = true
				suite.assert_equal(runtime.call("matches_snapshot", extra), complete == extra, "extra child field preserves equality: " + label + str(field))
	var extra := complete.duplicate(true)
	extra.unexpected = true
	suite.assert_equal(runtime.call("matches_snapshot", extra), complete == extra, "unknown complete field preserves equality: " + label)
	suite.assert_equal(runtime.full_snapshot_calls, 0, "complete comparisons never capture another full Boss history: " + label)
	for field: String in probes:
		var probe: RefCounted = probes[field]
		suite.assert_equal(probe.full_snapshot_calls, 0, "complete leaf comparison never captures another history: " + label + field)
		runtime.set(field, probe.authority)
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "complete comparisons leave every typed gameplay field unchanged: " + label)
	complete.mechanism_state.damage_claims.append("caller-mutation")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "public full snapshots remain deeply detached: " + label)


func _collect_paths(value: Variant, path: Array, paths: Array[Array]) -> void:
	if value is Dictionary or value is Array:
		if not path.is_empty():
			paths.append(path)
		for key: Variant in value.keys() if value is Dictionary else range(value.size()):
			_collect_paths(value[key], path + [key], paths)
	else:
		paths.append(path)


func _test_component_fallback(runtime: RefCounted, boss_id: String) -> void:
	var complete: Dictionary = runtime.snapshot()
	var original: RefCounted = runtime.get("_control")
	var fallback := SnapshotOnlyProbe.new()
	fallback.authority = original
	runtime.set("_control", fallback)
	suite.assert_true(runtime.call("matches_snapshot", complete), "query-less component keeps original complete snapshot equality: " + boss_id)
	suite.assert_equal(fallback.full_snapshot_calls, 1, "query-less component takes exactly one original complete observation")
	var changed := complete.duplicate(true)
	changed.control.unexpected = true
	suite.assert_equal(runtime.call("matches_snapshot", changed), complete == changed, "query-less component preserves original unequal verdict")
	suite.assert_equal(fallback.full_snapshot_calls, 2, "unequal query-less comparison retains one original capture")
	runtime.set("_control", original)
	var state: Dictionary = runtime.get("_state")
	state["control"] = "overridden-by-composition"
	suite.assert_equal(runtime.call("matches_snapshot", complete), runtime.snapshot() == complete, "configured component overrides stale base field exactly like original snapshot")
	state.erase("control")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(complete), "fallback observation and composition parity preserve complete accepted state")


func _at(value: Dictionary, path: Array) -> Variant:
	var cursor: Variant = value
	for key: Variant in path:
		cursor = cursor[key]
	return cursor


func _set_at(value: Dictionary, path: Array, changed: Variant) -> void:
	var cursor: Variant = value
	for index: int in range(path.size() - 1):
		cursor = cursor[path[index]]
	cursor[path.back()] = changed


func _changed(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL: return not value
		TYPE_INT, TYPE_FLOAT: return value + 1
		TYPE_STRING, TYPE_STRING_NAME: return str(value) + "-changed"
		TYPE_DICTIONARY: return {"unexpected": true}
		TYPE_ARRAY: return [] if not value.is_empty() else [0]
	return null


func _context(frame: int, action: Dictionary) -> Dictionary:
	var context := Actions.context(frame)
	context.target_position = {"x": 100.0 + float(action.distance_min_px), "y": 100.0}
	return context
