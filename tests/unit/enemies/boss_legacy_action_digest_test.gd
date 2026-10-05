extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var fresh_action_calls := 0

	func _make_action(phase_index: int, enraged: bool, room_half: bool = true, current_time_responses: bool = true) -> RefCounted:
		fresh_action_calls += 1
		return super._make_action(phase_index, enraged, room_half, current_time_responses)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		var parser := Definition.new()
		suite.assert_true(parser.configure(row).ok, "legacy digest fixture parses authored Boss " + row.id)
		var identity := Actions.identity()
		identity.seed = 42
		_test_boundaries(parser.runtime_projection(), identity)
		if row.id in ["void_throne", "time_sovereign"]:
			_test_boundaries(parser.runtime_projection(), identity, true)
	suite.finish(get_tree())


func _test_boundaries(definition: Dictionary, identity: Dictionary, historical: bool = false) -> void:
	var runtime := CountingBoss.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "legacy fixture configures full authentic mutable Boss")
	var action: Dictionary = definition.actions[0]
	suite.assert_true(runtime.request_action(str(action.id), Actions.context()).ok, "legacy fixture commits authentic authored action")
	if historical:
		var legacy: RefCounted
		if definition.id == "void_throne":
			legacy = runtime.call("_make_action", 0, false, false, true)
			runtime.set("_legacy_void_action", true)
		else:
			legacy = runtime.call("_make_action", 0, false, true, false)
			runtime.set("_legacy_time_action", true)
		suite.assert_true(legacy.request_action(str(action.id), Actions.context()).ok, "historical coordinator independently commits the same authored action")
		runtime.set("_action", legacy)
	var active_start := int(action.warning_frames)
	var recovery_start := active_start + int(action.active_frames)
	var ended := recovery_start + int(action.recovery_frames)
	var boundaries := [0, active_start - 1, active_start, recovery_start - 1, recovery_start, ended - 1, ended]
	for frame: int in range(ended + 1):
		if frame > 0:
			suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "legacy fixture advances actual sequential Boss clock")
		if frame not in boundaries:
			continue
		_test_restore(runtime, definition, identity, historical, frame)
	var saved := runtime.snapshot()
	var alternate := identity.duplicate(true)
	alternate.hostile_source_id = "other-legacy-digest-owner"
	suite.assert_true(runtime.configure(definition, alternate).ok and runtime.get("_action_validation_cache").is_empty(), "reconfiguration clears all private digest templates")
	suite.assert_true(not runtime.restore_snapshot(saved), "new configured owner cannot restore the previous owner")


func _test_restore(runtime: RefCounted, definition: Dictionary, identity: Dictionary, historical: bool, frame: int) -> void:
	var saved: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.call("_can_restore_snapshot_uncached", saved), "full authentic validation warms exact current and historical authority")
	var context: PackedByteArray = runtime.call("_snapshot_validation_context")
	var template: Dictionary = runtime.call("_action_validation_template", 0, false, true, true, context)
	var template_bytes := var_to_bytes(template)
	var is_historical: bool = saved.action.definition_digest != template.definition_digest
	suite.assert_equal(is_historical, historical and saved.action.phase != "IDLE", "historical fixture retains the old regime until authored action retirement")
	var previous: RefCounted = runtime.get("_action")
	runtime.fresh_action_calls = 0
	suite.assert_true(runtime.restore_snapshot(saved), "accepted complete Boss restoration retains every original check")
	var restored: RefCounted = runtime.get("_action")
	var expected_calls := 2 if is_historical else 1
	suite.assert_equal(runtime.fresh_action_calls, expected_calls, "warm restore constructs only independent mutable selection: " + definition.id + ":" + str(historical) + ":" + str(frame))
	suite.assert_true(not is_same(previous, restored), "actual restoration creates a different mutable Action")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(saved), "complete typed Boss and auxiliary snapshot remains exact")
	suite.assert_equal(runtime.get("_legacy_void_action"), is_historical and definition.id == "void_throne", "Void current-versus-historical classification is unchanged")
	suite.assert_equal(runtime.get("_legacy_time_action"), is_historical and definition.id == "time_sovereign", "Time current-versus-historical classification is unchanged")
	suite.assert_equal(var_to_bytes(template), template_bytes, "legacy classification never mutates retained immutable authority")
	var repeated: Dictionary = runtime.call("_action_validation_template", 0, false, true, true, context)
	suite.assert_true(is_same(template, repeated), "legacy classification preserves the bounded private template")
	runtime.fresh_action_calls = 0
	suite.assert_true(runtime.restore_snapshot(saved), "a second complete restoration remains accepted")
	suite.assert_equal(runtime.fresh_action_calls, expected_calls, "repeat restore retains only independent mutable selection: " + definition.id + ":" + str(historical) + ":" + str(frame))
	suite.assert_true(not is_same(restored, runtime.get("_action")), "separate restorations cannot share mutable Action state")
	_test_refusals(runtime, saved)
	var reference := Boss.new()
	suite.assert_true(reference.configure(definition, identity).ok and reference.restore_snapshot(saved), "independent reference restores the same complete accepted authority")
	suite.assert_equal(runtime.advance_frame(frame + 1, Actions.context(frame + 1), false), reference.advance_frame(frame + 1, Actions.context(frame + 1), false), "restored next hit, effect and auxiliary outputs remain exact")
	suite.assert_true(runtime.restore_snapshot(saved), "fixture resumes authentic boundary after exact next-frame comparison")


func _test_refusals(runtime: RefCounted, saved: Dictionary) -> void:
	for field: String in ["schema_version", "definition_digest", "identity", "action_phase_index"]:
		var forged := saved.duplicate(true)
		match field:
			"schema_version": forged.action.schema_version = 1.0
			"definition_digest": forged.action.definition_digest = "foreign-digest"
			"identity": forged.action.identity.hostile_source_id = "foreign-owner"
			"action_phase_index": forged.mechanism_state.action_phase_index = 0.25
		var before := var_to_bytes(runtime.snapshot())
		suite.assert_true(not runtime.restore_snapshot(forged), "warm restoration refuses typed or foreign authority: " + field)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "refused restoration leaves complete typed gameplay state unchanged")
