extends "res://tests/integration/save/boss_rush_checkpoint_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	for guard: bool in [false, true]:
		var fixture := _fixture("guardian-hit-%s" % str(guard))
		var flow := _flow(fixture)
		var request := REQUEST.duplicate(true)
		request.character_id = "time_guardian"
		_suite.assert_true(flow.start(request).ok, "actual Guardian enters native Boss Rush")
		var player: Node2D = flow.current_player()
		var boss: Node2D = flow.current_boss()
		player.set_physics_process(false)
		player.global_position = boss.global_position + Vector2(40, 0)
		await get_tree().physics_frame
		var guard_frame := -1
		var resolved := false
		for frame: int in range(1, 300):
			var intents := {"aim": player.global_position.direction_to(boss.global_position)}
			var action: Dictionary = boss.launch_runtime_snapshot().runtime.action
			if guard and guard_frame < 0 and action.phase == "WARNING":
				for definition: Dictionary in boss.get("_launch_definition").actions:
					if definition.id == action.action_id and frame - int(action.commit_frame) >= int(definition.warning_frames) - 3:
						guard_frame = frame
						intents.character = [{"id": &"character_skill", "edge": &"pressed", "held_frames": 0, "mode": &"hold"}]
			elif guard_frame >= 0:
				intents.character = [{"id": &"character_skill", "edge": &"held", "held_frames": frame - guard_frame, "mode": &"hold"}]
			_suite.assert_true(player.advance_action_frame(intents), "actual Guardian and Boss commit authoritative hostile frame")
			if not flow.get("_effects").snapshot().claims.is_empty():
				resolved = true
				break
		_suite.assert_true(resolved, "real native Boss geometry resolves one actual Guardian hit")
		if guard:
			_suite.assert_equal(player.health.current_hp, player.health.max_hp, "timed perfect guard prevents actual native Boss damage")
			_suite.assert_true(player.character_runtime.presentation_snapshot().resource_value > 0, "native guard earns authoritative Ward from accepted hostile identity")
		else:
			_suite.assert_true(player.health.current_hp < player.health.max_hp, "unguarded native Boss damage passes Guardian identity validation")
		_suite.assert_true(flow.save_and_return().ok, "native Guardian combat saves attempted frames")
		await _dispose(flow)
	_suite.finish(get_tree())
