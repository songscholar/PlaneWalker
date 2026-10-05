extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class ColdQueries extends RefCounted:
	var runtime: RefCounted
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return runtime.snapshot()

	func _action_definition(id: String) -> Dictionary:
		return runtime.call("_action_definition", id)

	func is_exposed() -> bool:
		return runtime.is_exposed()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var probe := CountingBoss.new()
	if probe.has_method("native_ui_snapshot"):
		suite.assert_equal(probe.call("native_ui_snapshot"), {}, "unconfigured Boss retains empty UI authority")
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _check_boss(row)
	suite.finish(get_tree())


func _check_boss(row: Dictionary) -> void:
	var parser := Definition.new()
	suite.assert_true(parser.configure(row).ok, "UI observation uses authored Boss " + row.id)
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var actor := (load("res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % row.id) as PackedScene).instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actual Boss configures UI authority")
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime := CountingBoss.new()
	var origin: Vector2 = actor.call("_native_arena_origin")
	suite.assert_true(runtime.configure_arena_origin({"x": origin.x, "y": origin.y}, {"x": actor.global_position.x, "y": actor.global_position.y}) and runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "counted real Boss preserves full actual authority")
	actor.set("_launch_runtime", runtime)
	_assert_ui(actor, runtime, definition, "configured " + row.id)
	if not runtime.has_method("native_ui_snapshot"):
		actor.queue_free()
		await get_tree().process_frame
		return
	var query: Dictionary = runtime.call("native_ui_snapshot")
	var full: Dictionary = runtime.snapshot()
	var expected := {"runtime_frame": full.runtime_frame, "action": full.action, "mechanism_state": {"phase_index": full.mechanism_state.phase_index, "delay_remaining_frames": full.mechanism_state.delay_remaining_frames, "enraged": full.mechanism_state.enraged}}
	suite.assert_equal(var_to_bytes(query), var_to_bytes(expected), "native UI input preserves exact typed current fields")
	query.action.phase = "caller-mutated"
	query.action.resolved_hit_indices.append(999)
	query.action.cooldowns["caller-mutated"] = 999
	query.mechanism_state.phase_index = 999
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(full), "native UI action and mechanism descendants are detached")
	var action: Dictionary = definition.actions[1 if row.id == "forest_heart" else 0]
	var context := _context(actor, action, 0)
	suite.assert_true(runtime.request_action(str(action.id), context).ok, "real authored action begins UI warning")
	_assert_ui(actor, runtime, definition, "warning " + row.id)
	var duration: int = int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames)
	var exposure_seen := false
	for frame: int in range(1, duration + 2):
		suite.assert_true(runtime.advance_frame(frame, _context(actor, action, frame), false).ok, "real Boss clock advances authored UI state")
		if not exposure_seen and runtime.native_action_snapshot().phase == "RECOVERY":
			suite.assert_true(runtime.extend_character_boss_exposure(1, 18), "real recovery admits a Character exposure tail")
			exposure_seen = true
			_assert_ui(actor, runtime, definition, "pending exposure " + row.id)
		if frame in [int(action.warning_frames), int(action.warning_frames) + int(action.active_frames), duration + 1]:
			_assert_ui(actor, runtime, definition, "action frame %d %s" % [frame, row.id])
	suite.assert_true(exposure_seen and runtime.is_exposed(), "authentic recovery tail becomes live shared UI exposure")
	_assert_ui(actor, runtime, definition, "active exposure " + row.id)
	var phase_frame := duration + 2
	var hp_after := float(definition.max_hp) * float(definition.phases.back().hp_threshold)
	suite.assert_true(runtime.accept_damage_fact({"fact_id": "ui-phase", "runtime_frame": phase_frame, "target_source_id": identity.hostile_source_id, "amount": float(definition.max_hp) - hp_after, "hp_after": hp_after}).ok, "authentic body loss changes live phase authority")
	_assert_ui(actor, runtime, definition, "phase transition " + row.id)
	suite.assert_true(runtime.cancel(&"ui_observation").ok, "actual Boss retires its action")
	_assert_ui(actor, runtime, definition, "terminal " + row.id)
	suite.assert_true(runtime.restore_snapshot(initial), "full historical Boss snapshot remains restorable")
	_assert_ui(actor, runtime, definition, "historical rollback " + row.id)
	var cold := ColdQueries.new()
	cold.runtime = runtime
	actor.set("_launch_runtime", cold)
	var expected_ui := _legacy_ui(actor, runtime, definition)
	suite.assert_equal(var_to_bytes(actor.get_boss_ui_snapshot()), var_to_bytes(expected_ui), "query-less runtime retains exact original full UI algorithm")
	suite.assert_equal(cold.full_snapshot_calls, 1, "query-less UI takes one original complete Boss observation")
	actor.set("_launch_runtime", runtime)
	actor.queue_free()
	await get_tree().process_frame


func _assert_ui(actor: Node2D, runtime: RefCounted, definition: Dictionary, label: String) -> void:
	var before := var_to_bytes(runtime.snapshot())
	var expected := _legacy_ui(actor, runtime, definition)
	runtime.full_snapshot_calls = 0
	for _repeat: int in range(16):
		var actual: Dictionary = actor.get_boss_ui_snapshot()
		suite.assert_equal(var_to_bytes(actual), var_to_bytes(expected), "UI preserves every original field and type: " + label)
		actual.phase = "caller-mutated"
		actual.current_hp = -1.0
	suite.assert_equal(runtime.full_snapshot_calls, 0, "sixteen repeated actual UI observations avoid complete Boss histories: " + label)
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "UI observation and output mutation preserve complete gameplay state: " + label)


func _legacy_ui(actor: Node2D, runtime: RefCounted, definition: Dictionary) -> Dictionary:
	var state: Dictionary = runtime.snapshot()
	var action: Dictionary = runtime.call("_action_definition", str(state.action.action_id))
	var remaining := 0
	if not action.is_empty():
		var elapsed := int(state.runtime_frame) - int(state.action.commit_frame) - int(state.action.paused_frames)
		remaining = int(action.warning_frames) - elapsed if state.action.phase == "WARNING" else int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) - elapsed
		remaining = maxi(0, remaining) + int(state.mechanism_state.delay_remaining_frames)
	var label := "NONE" if action.is_empty() else str(action.handler_id).to_upper()
	var health := actor.get_node("HealthComponent")
	return {"action": label, "phase": "WINDUP" if state.action.phase == "WARNING" else str(state.action.phase), "remaining": float(remaining) / 60.0, "boss_phase": int(state.mechanism_state.phase_index) + 1, "exposed": runtime.is_exposed(), "name": tr("BOSS_%s_NAME" % str(definition.id).to_upper()), "phase_total": definition.phases.size(), "current_hp": float(health.current_hp), "maximum_hp": float(health.max_hp), "enraged": bool(state.mechanism_state.enraged)}


func _context(actor: Node2D, action: Dictionary, frame: int) -> Dictionary:
	var context := Actions.context(frame)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + maxf(float(action.distance_min_px), minf(40.0, float(action.distance_max_px))), "y": actor.global_position.y}
	return context
