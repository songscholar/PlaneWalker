extends RefCounted

const PlayerScene := preload("res://scenes/player/player.tscn")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const ReplayWorld := preload("res://scripts/replay/player_replay_world.gd")
const SceneScope := preload("res://scripts/player/player_scene_scope.gd")


static func spawn(parent: Node, registry: RefCounted, suite: RefCounted, run_id: String, seed_value: int, viewing: bool = false, weapon_id: String = "sword") -> Node2D:
	var player: Node2D
	if viewing:
		var world := ReplayWorld.new()
		parent.add_child(world)
		player = world.create_player()
	else:
		player = PlayerScene.instantiate()
		player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		player.process_mode = Node.PROCESS_MODE_DISABLED
		parent.add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	await parent.get_tree().process_frame
	suite.assert_true(player.configure_run(StringName(run_id)), "isolated native Player gets recorded run identity")
	suite.assert_true(player.configure_loadout({"milestone": "LAUNCH", "seed": seed_value, "character_id": "wanderer", "weapon_id": weapon_id, "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon_id), &"LAUNCH")}), "actual launch replay fixture loadout")
	return player


static func record(parent: Node, registry: RefCounted, suite: RefCounted, run_id: String, seed_value: int, weapon_id: String = "sword", include_weapon: bool = false) -> Dictionary:
	var player := await spawn(parent, registry, suite, run_id, seed_value, true, weapon_id)
	var recorder := Recorder.new()
	suite.assert_true(recorder.start_full_player_recording(player.full_player_replay_identity(), seed_value).ok, "actual Player recorder starts")
	var facts: Array[Dictionary] = []
	var observer := func(ability_id: StringName, token: int, generation: int, frame: int, source_run_id: StringName, context: Dictionary):
		facts.append({"ability_id": ability_id, "token": token, "generation": generation, "frame": frame, "run_id": source_run_id, "context": context.duplicate(true)})
	var bus := SceneScope.event_bus(player)
	bus.time_skill_committed.connect(observer)
	for index: int in range(64 if include_weapon else 5):
		var intents := {"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.RIGHT, "aim": Vector2.RIGHT, "meta": {"frame": index}}
		if index == 1:
			intents.time.append({"id": "time_slot_1", "edge": "pressed", "mode": "press", "held_frames": 0})
		if include_weapon and index >= 20 and index <= 30:
			intents.weapon.append({"id": "weapon_primary", "edge": "pressed" if index == 20 else ("released" if index == 30 else "held"), "mode": str(player.call("_weapon_semantic_input_mode", &"weapon_primary")), "held_frames": index - 20})
		if index > 0:
			suite.assert_true(player.advance_action_frame(intents), "real movement/time/weapon frame advances: %s:%d" % [weapon_id, index])
		suite.assert_true(recorder.record_full_player_frame(player.full_player_replay_snapshot(), intents, facts).ok, "actual frame snapshot records")
		facts.clear()
	var finished: Dictionary = recorder.finish_full_player_recording()
	bus.time_skill_committed.disconnect(observer)
	suite.assert_true(finished.ok, "actual Player replay finishes")
	player.get_parent().queue_free()
	await parent.get_tree().process_frame
	return finished.get("replay", {})
