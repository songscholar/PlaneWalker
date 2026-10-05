extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const CHILDREN := ["action", "control", "conversion", "arena_state", "forest_auxiliary", "void_arena_state", "void_auxiliary", "forge_arena_state", "time_response", "time_auxiliary"]
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var parent_copy_calls := 0

	func _copy_restored_parent_state(value: Dictionary) -> Dictionary:
		parent_copy_calls += 1
		var parent := value.duplicate()
		for field: String in ["action", "control", "conversion", "arena_state", "forest_auxiliary", "void_arena_state", "void_auxiliary", "forge_arena_state", "time_response", "time_auxiliary"]:
			parent.erase(field)
		return parent.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		var parser := Definition.new()
		suite.assert_true(parser.configure(row).ok, "parent fixture uses authored Boss " + row.id)
		var definition := parser.runtime_projection()
		var identity := Actions.identity()
		identity.seed = 42
		var source := Boss.new()
		suite.assert_true(source.configure(definition, identity).ok, "parent fixture binds real independent authority")
		_check_restore(source.snapshot(), definition, identity)
		var action: Dictionary = definition.actions[0]
		suite.assert_true(source.request_action(str(action.id), Actions.context()).ok, "parent fixture requests actual authored action")
		var recovery := int(action.warning_frames) + int(action.active_frames)
		var ended := recovery + int(action.recovery_frames)
		for frame: int in range(ended + 1):
			if frame > 0:
				suite.assert_true(source.advance_frame(frame, Actions.context(frame), false).ok, "parent fixture advances complete actual frame")
			if frame in [0, int(action.warning_frames), recovery, ended]:
				_check_restore(source.snapshot(), definition, identity)
		suite.assert_true(source.cancel(&"parent_restore_terminal").ok, "parent fixture reaches actual terminal authority")
		_check_restore(source.snapshot(), definition, identity)
	suite.finish(get_tree())


func _check_restore(saved: Dictionary, definition: Dictionary, identity: Dictionary) -> void:
	var runtime := CountingBoss.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "counted full Boss configures before restore")
	var reference := Boss.new()
	suite.assert_true(reference.configure(definition, identity).ok and reference.restore_snapshot(saved), "actual uninstrumented Boss restores the same complete historical boundary")
	var original := saved.duplicate(true)
	for field: String in CHILDREN:
		original.erase(field)
	suite.assert_equal(var_to_bytes(reference.get("_state")), var_to_bytes(original), "production parent copy retains original exact remaining bytes")
	suite.assert_equal(var_to_bytes(reference.snapshot()), var_to_bytes(saved), "production parent and child installation retain complete typed bytes")
	for _repeat: int in range(2):
		runtime.parent_copy_calls = 0
		suite.assert_true(runtime.restore_snapshot(saved), "complete accepted Boss restores through original validators")
		suite.assert_equal(runtime.parent_copy_calls, 1, "accepted parent restore avoids copying discarded child histories: " + definition.id)
		suite.assert_equal(var_to_bytes(runtime.get("_state")), var_to_bytes(original), "remaining parent preserves original exact fields, order and types")
		suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(saved), "independent children preserve complete restored typed bytes")
	var before := var_to_bytes(runtime.snapshot())
	for field: String in ["schema", "owner", "action", "child"]:
		var forged := saved.duplicate(true)
		match field:
			"schema": forged.schema_version = float(forged.schema_version)
			"owner": forged.identity.hostile_source_id = "foreign-parent-owner"
			"action": forged.action.next_generation_floor = float(forged.action.next_generation_floor)
			"child": forged.conversion.extra = true
		runtime.parent_copy_calls = 0
		suite.assert_true(not runtime.restore_snapshot(forged), "full accepted-boundary restore still rejects forged " + field)
		suite.assert_equal(runtime.parent_copy_calls, 0, "refused authority never reaches parent installation")
		suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "refused restore leaves complete state exact")
	var mutable := saved.duplicate(true)
	suite.assert_true(runtime.restore_snapshot(mutable), "detachment fixture restores authentic full input")
	suite.assert_true(reference.restore_snapshot(mutable), "production restoration retains caller isolation without counter override")
	mutable.identity.hostile_source_id = "caller"
	mutable.mechanism_state.health_claims.append("caller")
	mutable.action.cooldowns["caller"] = 999
	mutable.conversion.claims.append({"caller": true})
	for field: String in ["arena_state", "forest_auxiliary", "void_arena_state", "void_auxiliary", "forge_arena_state", "time_response", "time_auxiliary"]:
		if mutable.has(field):
			mutable[field].clear()
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "caller parent and every child remain independently detached after restore")
	suite.assert_equal(var_to_bytes(reference.snapshot()), before, "production parent and every child remain independently detached after restore")
	if not saved.terminal:
		var frame := int(saved.runtime_frame) + 1
		suite.assert_equal(runtime.advance_frame(frame, Actions.context(frame), false), reference.advance_frame(frame, Actions.context(frame), false), "detached parent preserves actual next-frame action and auxiliary outputs")
		suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(reference.snapshot()), "actual next complete state matches independent reference bytes")
