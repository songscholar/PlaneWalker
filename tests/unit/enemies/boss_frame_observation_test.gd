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
	var probe := Runtime.new()
	var available := probe.has_method("native_runtime_frame") and probe.has_method("native_is_terminal") and probe.has_method("native_action_snapshot")
	suite.assert_true(available, "Boss observation queries read owned current state without complete snapshot capture")
	if not available:
		suite.finish(get_tree())
		return
	for row: Dictionary in Content.read_catalog("bosses.json"):
		var parser := Definition.new()
		suite.assert_true(parser.configure(row).ok, "observation fixture uses authored Boss " + row.id)
		var definition := parser.runtime_projection()
		var identity := Actions.identity()
		identity.seed = 42
		var runtime := Runtime.new()
		suite.assert_true(runtime.configure(definition, identity).ok, "observation fixture configures complete authority")
		var initial := runtime.snapshot()
		_check_queries(suite, runtime, "configured " + row.id)
		for frame: int in range(1, 7):
			suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "unique accepted Boss frame advances")
			_check_queries(suite, runtime, "advanced " + row.id)
		var before := var_to_bytes(runtime.snapshot())
		suite.assert_true(not runtime.advance_frame(8, Actions.context(8), false).ok, "skipped native frame remains refused")
		_check_queries(suite, runtime, "refused " + row.id)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "refused observation never changes complete typed state")
		suite.assert_true(runtime.cancel(&"observation_test").ok, "actual terminal mutation commits")
		_check_queries(suite, runtime, "terminal " + row.id)
		suite.assert_true(runtime.native_is_terminal(), "terminal primitive observes actual domain mutation immediately")
		suite.assert_true(runtime.restore_snapshot(initial), "complete historical boundary restores after terminal mutation")
		_check_queries(suite, runtime, "rollback " + row.id)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(initial), "rollback retains exact original typed bytes")
		var changed_identity := identity.duplicate(true)
		changed_identity.hostile_source_id = "observation-other-owner"
		suite.assert_true(runtime.configure(definition, changed_identity).ok, "queries reflect a different configured owner")
		_check_queries(suite, runtime, "reconfigured " + row.id)
		await _check_previews(suite, row.id, definition, identity)
	suite.finish(get_tree())


func _check_queries(suite: RefCounted, runtime: RefCounted, label: String) -> void:
	var complete: Dictionary = runtime.snapshot()
	var before := var_to_bytes(complete)
	suite.assert_equal(var_to_bytes(runtime.native_runtime_frame()), var_to_bytes(complete.runtime_frame), "runtime-frame primitive retains exact type: " + label)
	suite.assert_equal(var_to_bytes(runtime.native_is_terminal()), var_to_bytes(complete.terminal), "terminal primitive retains exact type: " + label)
	var action: Dictionary = runtime.native_action_snapshot()
	suite.assert_equal(var_to_bytes(action), var_to_bytes(complete.action), "narrow action capture retains complete action typed bytes: " + label)
	action.cooldowns["caller-mutation"] = 123
	action.identity.hostile_source_id = "caller-owner"
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "narrow public action descendants stay detached: " + label)
	var foreign := complete.duplicate(true)
	foreign.runtime_frame = float(foreign.runtime_frame)
	suite.assert_equal(runtime.can_restore_snapshot(foreign), runtime.call("_can_restore_snapshot_uncached", foreign), "primitive queries never authorize a typed foreign restore: " + label)
	foreign.schema_version = float(foreign.schema_version)
	suite.assert_true(not runtime.can_restore_snapshot(foreign), "typed forged schema remains refused: " + label)


func _check_previews(suite: RefCounted, boss_id: String, definition: Dictionary, identity: Dictionary) -> void:
	var scene := load("res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % boss_id) as PackedScene
	var actor := scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actual Boss configures preview authority: " + boss_id)
	var available := actor.has_method("_native_frame_preview")
	suite.assert_true(available, "actual hostile owns separately configured frame-preview slots")
	if available:
		var initial: Dictionary = actor.launch_runtime_snapshot().runtime
		var complete := var_to_bytes(actor.launch_runtime_snapshot())
		var body: RefCounted = actor.call("_native_frame_preview", initial, &"body")
		var arena: RefCounted = actor.call("_native_frame_preview", initial, &"arena")
		suite.assert_true(body != null and arena != null and body != arena, "body and arena previews have separate mutation ownership")
		if body != null and arena != null:
			suite.assert_true(body.advance_frame(1, Actions.context(1), false).ok, "private preview may advance an independent actual Boss frame")
			suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), complete, "preview advance cannot mutate live actor")
			var restored: RefCounted = actor.call("_native_frame_preview", initial, &"body")
			suite.assert_true(restored == body, "same exact typed configuration reuses its private preview")
			suite.assert_equal(var_to_bytes(restored.snapshot()), var_to_bytes(initial), "every reused preview restores exact complete boundary")
			var forged := initial.duplicate(true)
			forged.schema_version = float(forged.schema_version)
			suite.assert_true(actor.call("_native_frame_preview", forged, &"body") == null, "reused preview keeps full foreign typed-snapshot validation")
			suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), complete, "foreign preview refusal leaves live actor unchanged")
			actor.global_position += Vector2.ONE
			var moved: RefCounted = actor.call("_native_frame_preview", initial, &"body")
			suite.assert_true(moved != null and moved != body, "changed actual origin context rebuilds preview authority")
			if moved != null:
				suite.assert_equal(var_to_bytes(moved.snapshot()), var_to_bytes(initial), "rebound preview preserves original cold restore bytes")
			var owned_identity: Dictionary = actor.get("_launch_identity")
			owned_identity.seed = float(owned_identity.seed)
			var retyped: RefCounted = actor.call("_native_frame_preview", initial, &"body")
			suite.assert_true(retyped == null or retyped != moved, "numerically equal configuration type change cannot reuse old authority")
			owned_identity.seed = "invalid-seed"
			suite.assert_true(actor.call("_native_frame_preview", initial, &"body") == null, "invalid configuration cannot reuse a previously accepted preview")
			owned_identity.seed = 42
			var retried: RefCounted = actor.call("_native_frame_preview", initial, &"body")
			suite.assert_true(retried != null, "restored authentic configuration retries safely")
	actor.queue_free()
	await get_tree().process_frame
