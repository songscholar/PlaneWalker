extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Binding := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Scope := preload("res://scripts/player/player_scene_scope.gd")
const Stream := preload("res://scripts/replay/run_replay_stream_store.gd")
const Library := preload("res://scripts/replay/run_replay_library.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var source := await Fixture.spawn(self, registry, suite, "whole-run-rewind", 789, true)
	var observations: Array[Dictionary] = []
	var commits: Array[StringName] = []
	var observe := func(ability: StringName, _token: int, _generation: int, _frame: int, _run_id: StringName, _context: Dictionary): commits.append(ability)
	Scope.event_bus(source).time_skill_committed.connect(observe)
	for frame: int in range(66):
		var intents := {"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.RIGHT, "aim": Vector2.RIGHT, "meta": {}}
		if frame == 64:
			intents.time.append({"id": "time_slot_2", "edge": "pressed", "mode": "press", "held_frames": 0})
		if frame > 0:
			suite.assert_true(source.advance_action_frame(intents), "native source accepts the whole-run Rewind frame")
		if frame == 65:
			source.health.lose_health(100000)
		observations.append({"sequence": frame, "kind": "frame", "player": source.full_player_replay_snapshot(), "run": {"run_id": "whole-run-rewind", "run_seed": 789}, "native": {}, "room": {}, "scene": {}})
	Scope.event_bus(source).time_skill_committed.disconnect(observe)
	suite.assert_equal(commits, [&"rewind"], "the native TimeManager commits exactly one Rewind")
	suite.assert_true(observations[65].player.player_state.position.x < observations[63].player.player_state.position.x, "native Rewind restores sampled position")
	suite.assert_true(observations[65].player.health_state.dead, "native Health publishes a terminal lifecycle event after Rewind")
	suite.assert_true(observations[65].player.world_payload_state.invalidated_generations != observations[63].player.world_payload_state.invalidated_generations, "the accepted lifecycle event crosses the payload invalidation boundary")
	var storage := Stream.new()
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("whole_run_history")
	suite.assert_true(storage.configure(root, "0.4.0-dev", Binding.snapshot(registry), "slot_1", "base").ok, "whole-run history uses physical streamed storage")
	var begun := storage.begin(source.full_player_replay_identity(), 789)
	suite.assert_true(begun.ok and storage.append(begun.context.id, observations).ok and storage.finish(begun.context.id, "INTERRUPTED").ok, "actual Rewind observations persist as authenticated stream bytes")
	var library := Library.new()
	add_child(library)
	suite.assert_true(library.configure(storage, registry).ok and library.select(begun.context.id).ok, "whole-run viewer owns its private Player")
	for index: int in [65, 0, 64, 63, 65]:
		var sought: Dictionary = library.seek(index)
		suite.assert_true(sought.ok, "whole-run seek crosses native Rewind and lifecycle history in both directions: %d" % index)
		if sought.ok:
			suite.assert_true(library.current_player().full_player_replay_snapshot() == observations[index].player, "whole-run history seek restores exact accepted Player state")
	var before: Dictionary = library.current_player().full_player_replay_snapshot()
	var selection: Dictionary = library.snapshot()
	var world: SubViewport = library.current_world()
	var isolated: World2D = world.world_2d
	world.world_2d = get_viewport().world_2d
	suite.assert_true(not library.seek(0).ok, "shared live physics rejects whole-run historical seek")
	suite.assert_true(library.current_player().full_player_replay_snapshot() == before, "shared-world refusal preserves Player state")
	suite.assert_equal(library.snapshot(), selection, "shared-world refusal preserves selection")
	world.world_2d = isolated
	library.current_player().process_mode = Node.PROCESS_MODE_INHERIT
	suite.assert_true(not library.seek(0).ok, "enabled whole-run Player rejects invalidation history rollback")
	suite.assert_true(library.current_player().full_player_replay_snapshot() == before, "enabled-Player refusal preserves Player state")
	library.current_player().process_mode = Node.PROCESS_MODE_DISABLED
	suite.assert_true(library.seek(0).ok, "restored isolation admits whole-run historical seek again")
	library.queue_free()
	source.get_parent().queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
