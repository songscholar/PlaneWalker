extends "res://tests/integration/combat/void_arena_native_test.gd"

const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Auxiliary := preload("res://scripts/enemies/launch/void_auxiliary_runtime.gd")


func _run() -> void:
	suite = Suite.new()
	var available := Runtime.new().has_method("native_void_burn_damage_requests_for_snapshot")
	var child_available := Auxiliary.new().has_method("burn_damage_requests_for_snapshot")
	suite.assert_true(available, "Void candidate burn query validates full Boss state without restoring an arena preview")
	suite.assert_true(child_available, "Void auxiliary supports validated detached historical burn requests")
	await _native_candidate()
	if available and child_available:
		_check_domain()
	suite.finish(get_tree())


func _check_domain() -> void:
	var parser := Definition.new()
	suite.assert_true(parser.configure(Content.boss("void_throne")).ok, "burn query uses real authored Void content")
	var definition := parser.runtime_projection()
	var identity := {"run_id": "burn-query-run", "hostile_source_id": "burn-query-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	var runtime := Runtime.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "burn query binds complete Boss authority")
	var saved: Array[Dictionary] = [runtime.snapshot()]
	var context := {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 350.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
	suite.assert_true(runtime.request_action("voidking_scepter_strike", context).ok, "real Scepter reserves authored generation")
	saved.append(runtime.snapshot())
	for frame: int in range(1, 210):
		context.runtime_frame = frame
		suite.assert_true(runtime.advance_frame(frame, context, false).ok, "actual burn-history clock advances contiguously")
		if frame == 28:
			suite.assert_true(runtime.accept_void_damage_receipt({"fact_id": "burn-query-damage", "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "attack_generation": 7, "hit_index": 0, "target_id": "player", "runtime_frame": frame, "actual_loss": 1.0}).ok, "accepted real Scepter loss installs finite source-owned burn")
		if frame in [28, 29, 58, 88, 118, 148, 178, 208, 209]:
			saved.append(runtime.snapshot())
	suite.assert_true(runtime.cancel(&"burn_query_terminal").ok, "actual terminal authority retires finite requests")
	saved.append(runtime.snapshot())
	var before := var_to_bytes(runtime.snapshot())
	var ticks := 0
	for value: Dictionary in saved:
		var expected := Runtime.new()
		suite.assert_true(expected.configure(definition, identity).ok and expected.restore_snapshot(value), "original separate Boss restores complete historical candidate")
		var frame := int(value.runtime_frame)
		var original: Array[Dictionary] = expected.void_burn_damage_requests(frame)
		ticks += original.size()
		var input := var_to_bytes(value)
		for _repeat: int in range(8):
			var result: Dictionary = runtime.call("native_void_burn_damage_requests_for_snapshot", value, frame)
			suite.assert_true(result.ok and var_to_bytes(result.requests) == var_to_bytes(original), "historical request retains every original typed field and tick boundary")
			if not result.requests.is_empty():
				result.requests[0].target_id = "caller"
				result.requests[0].damage = 999.0
			suite.assert_equal(var_to_bytes(value), input, "returned burn request cannot mutate supplied history")
			suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "validated query never installs historical state into live Boss")
		var mistimed: Dictionary = runtime.call("native_void_burn_damage_requests_for_snapshot", value, frame + 1)
		suite.assert_true(mistimed.ok and mistimed.requests.is_empty(), "a mismatched request frame preserves original empty result")
	suite.assert_equal(ticks, 6, "six actual authored burn ticks remain visible before exclusive expiry")
	var tick: Dictionary = saved[4]
	for field: String in ["schema", "identity", "definition", "derived", "history", "other_authority"]:
		var forged := tick.duplicate(true)
		match field:
			"schema": forged.schema_version = float(forged.schema_version)
			"identity": forged.identity.hostile_source_id = "foreign"
			"definition": forged.definition_digest = "foreign"
			"derived": forged.void_auxiliary.burns[0].through_frame += 1
			"history": forged.void_auxiliary.events[0].frame = -1
			"other_authority": forged.void_arena_state.extra = true
		var original := Runtime.new()
		suite.assert_true(original.configure(definition, identity).ok, "refusal reference binds original authority")
		suite.assert_true(not original.restore_snapshot(forged), "original restore rejects forged " + field)
		var result: Dictionary = runtime.call("native_void_burn_damage_requests_for_snapshot", forged, int(tick.runtime_frame))
		suite.assert_true(not result.ok, "full Boss query retains original refusal for " + field)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "query refusal preserves live typed state")
	var child: RefCounted = runtime.get("_void_auxiliary")
	var child_before := var_to_bytes(child.snapshot())
	var child_tick: Dictionary = tick.void_auxiliary
	var result: Dictionary = child.call("burn_damage_requests_for_snapshot", child_tick, int(tick.runtime_frame))
	suite.assert_true(result.ok and result.requests.size() == 1, "configured child query reads valid old tick without installation")
	var forged_child := child_tick.duplicate(true)
	forged_child.burns[0].through_frame += 1
	suite.assert_true(not child.call("burn_damage_requests_for_snapshot", forged_child, int(tick.runtime_frame)).ok, "standalone child query retains complete derived-history validation")
	suite.assert_equal(var_to_bytes(child.snapshot()), child_before, "standalone child preserves terminal live authority")
	suite.assert_true(not Runtime.new().call("native_void_burn_damage_requests_for_snapshot", tick, int(tick.runtime_frame)).ok, "unconfigured authority cannot authorize a historical burn")
	for row: Dictionary in Content.read_catalog("bosses.json"):
		if row.id == "void_throne":
			continue
		var other_parser := Definition.new()
		var other := Runtime.new()
		suite.assert_true(other_parser.configure(row).ok and other.configure(other_parser.runtime_projection(), identity).ok, "non-Void refusal binds real Boss")
		suite.assert_true(not other.call("native_void_burn_damage_requests_for_snapshot", other.snapshot(), 0).ok, "non-Void authority cannot authorize a Void query")


func _native_candidate() -> void:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	actor.global_position = Vector2(320, 180)
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var observations := {"runtime_frame": 1, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 350.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
	var result: Dictionary = actor.prepare_launch_frame(1, observations)
	suite.assert_true(result.ok, "actual native Void candidate retains complete preparation")
	if result.ok:
		var slots: Dictionary = actor.get("_frame_preview_slots")
		suite.assert_true(slots.has(&"body") and not slots.has(&"arena"), "read-only Void candidate owns its body preview without an unnecessary restored arena")
		var fallback_ticket: Dictionary = result.ticket.duplicate(true)
		var current: RefCounted = actor.get("_launch_runtime")
		actor.set("_launch_runtime", RefCounted.new())
		var fallback: Dictionary = actor.call("_prepare_native_void_frame", fallback_ticket, observations)
		actor.set("_launch_runtime", current)
		suite.assert_true(fallback.get("ok", false), "query-less fallback accepts the actual prepared native ticket")
		suite.assert_equal(var_to_bytes(fallback_ticket), var_to_bytes(result.ticket), "query-less fallback retains complete original typed ticket and batch")
		suite.assert_true((actor.get("_frame_preview_slots") as Dictionary).has(&"arena"), "query-less fallback still restores an independently owned arena preview")
		suite.assert_true(actor.rollback_launch_frame(result.ticket), "native prepared ticket retains full rollback")
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "read-only native candidate and rollback preserve complete live actor bytes")
	actor.queue_free()
	room.queue_free()
	await get_tree().process_frame
