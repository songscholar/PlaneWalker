extends "res://tests/integration/combat/void_auxiliary_lifecycle_test.gd"


func _boss(room: Node2D, _next_generation_floor: int = 1) -> Node2D:
	return super._boss(room, 1)


func _run() -> void:
	suite = Suite.new()
	var context := _open_case(false, Vector2(356.1328125, 144.0))
	context.actor.global_position = Vector2(316.1328125, 144.0)
	context.actor._refresh_native_arena()
	context.player.health.acquire_invulnerability_source(&"void-payload-identity")
	_request(context, "voidking_void_grasp")
	_frames(context, 102)
	_request(context, "voidking_plane_tear")
	var cast: Dictionary = context.actor.launch_runtime_snapshot().runtime.action
	suite.assert_true(cast.geometry_generations[0] > 1, "real prior Grasp owns generation1 before a later independently identified Tear")
	var active: int = context.frame + 47
	_frames(context, active)
	suite.assert_true(context.frame == active and context.effects.snapshot().semantics.zones.size() == 1, "later real Tear damage accepts inside its native zone without borrowing earlier Grasp identity")
	if context.frame == active:
		var receipts: Array = context.actor.native_void_auxiliary_snapshot().events.filter(func(row: Dictionary): return row.kind == "damage" and row.frame == active)
		suite.assert_true(receipts.is_empty(), "standalone Tear zone ticks never create a Grasp, Bolt, Devour or Scepter auxiliary receipt")
		await _cold_owner(context)
		_frames(context, active + 1)
	await _close_case(context)
	suite.finish(get_tree())
