extends "res://tests/integration/combat/void_auxiliary_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	var context := _open_case(false, Vector2(318.44921875, 144.0))
	context.actor.global_position = Vector2(278.1015625, 144.0)
	_request(context, "voidking_void_step")
	var frozen: Dictionary = context.actor.launch_runtime_snapshot().runtime.action.committed_geometry[0].origin
	_frames(context, 29)
	context.actor.set("_knockback_velocity", Vector2(-0.01, 0.0))
	var before: Dictionary = context.actor.launch_transaction_snapshot()
	var registry_before: Array = context.registry.snapshot()
	var ticket: Dictionary = context.bridge.begin_frame(30)
	var prepared: bool = context.bridge.prepare_frame(ticket)
	suite.assert_true(prepared, "remaining weapon recoil cannot offset frozen native Void Step relocation")
	if prepared:
		var state: Dictionary = context.actor.native_void_auxiliary_snapshot()
		suite.assert_true(state.landings.size() == 1 and state.landings[0].landed and state.landings[0].position == frozen, "actual native Step lands at the exact accepted frozen position")
		suite.assert_equal(context.actor.global_position, Vector2(float(frozen.x), float(frozen.y)), "actual native body matches the strict landing receipt")
		suite.assert_true(context.bridge.rollback_frame(ticket), "late native refusal compensates exact Step relocation and followup")
		suite.assert_equal(context.actor.launch_transaction_snapshot(), before, "Step refusal restores position, recoil, action and receipts")
		suite.assert_equal(context.registry.snapshot(), registry_before, "Step refusal restores original frozen warning")
		_frames(context, 30)
		suite.assert_equal(context.actor.native_void_auxiliary_snapshot().landings.size(), 1, "same Step retry owns one landing receipt")
		suite.assert_true(context.actor.launch_runtime_snapshot().runtime.action.action_id in ["voidking_scepter_strike", "voidking_void_bolt"], "accepted Step retains its independently warned authored followup")
	else:
		context.bridge.rollback_frame(ticket)
	await _close_case(context)
	suite.finish(get_tree())
