extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const LIBRARY := "res://scripts/replay/run_replay_library.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(LIBRARY), "whole-run native replay viewing must exist")
	if not ResourceLoader.exists(LIBRARY):
		suite.finish(get_tree())
		return
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(main._launch_run(config, false, true), "actual launch starts automatic tape")
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var recorder: Node = main.get_node("NativeRunReplayRecorder")
	main.set_process(false)
	host.set_process(false)
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var chosen: Dictionary = host.route_choices()[0]
	for row: Dictionary in host.route_choices():
		if row.room_type == "combat":
			chosen = row
			break
	suite.assert_true(host.select_route(StringName(chosen.edge_id), int(host.runtime_snapshot().revision)).ok, "actual native room enters tape")
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"view_fixture")
	suite.assert_true(recorder.observe_transition().ok, "room transition records")
	for index: int in range(65):
		suite.assert_true(player.advance_action_frame({"movement": Vector2.ZERO, "aim": Vector2.RIGHT}), "native frame accepted")
		await get_tree().physics_frame
	var latest: Dictionary = recorder.latest_observation()
	suite.assert_true(not latest.native.get("actors", {}).is_empty(), "actual tape contains production hostiles")
	suite.assert_true(recorder.finish("INTERRUPTED").ok, "retained recording closes honestly")
	var library: Node = load(LIBRARY).new()
	add_child(library)
	suite.assert_true(library.configure(recorder.store(), host.content_registry()).ok, "viewer uses actual bounded stream store")
	var rows: Array = library.rows()
	suite.assert_true(rows.size() == 1 and rows[0].status == "INTERRUPTED", "whole-run row exposes incomplete status")
	var id: String = rows[0].id
	var profile_before: Dictionary = GameState.profile_runtime_service().snapshot()
	var live_before: Dictionary = player.full_player_replay_snapshot()
	var global_events: Array = []
	var observe := func(_ability: StringName, _token: int, _generation: int, _frame: int, _run: StringName, _context: Dictionary): global_events.append(true)
	EventBus.time_skill_committed.connect(observe)
	suite.assert_true(library.select(id).ok and library.seek(int(latest.sequence)).ok, "native whole world random seek succeeds")
	suite.assert_equal(library.current_player().full_player_replay_snapshot(), latest.player, "private Player restores exact accepted snapshot")
	suite.assert_equal(library.current_world().observation(), latest, "room, enemies, economy and accepted state are retained exactly")
	suite.assert_equal(library.current_world().hostile_count(), latest.native.actors.size(), "all actual native hostile raster projections are present")
	suite.assert_true(library.current_world().world_2d != player.get_viewport().world_2d, "viewing owns private World2D")
	var before: Dictionary = library.snapshot()
	suite.assert_true(not library.seek(-1).ok and library.snapshot() == before, "invalid seek preserves committed view")
	var malformed := latest.duplicate(true)
	malformed.player.identity.run_id = "forged"
	suite.assert_true(not library.current_world().present_observation(malformed, host.content_registry()).ok, "malformed identity refuses before visual publication")
	suite.assert_equal(library.current_world().observation(), latest, "failed world projection leaves prior observation intact")
	var atlas: Sprite2D = library.current_world().get("_atlas")
	var atlas_before: Dictionary = atlas.snapshot()
	malformed = latest.duplicate(true)
	malformed.cosmetic_id = "unavailable_cosmetic"
	suite.assert_true(not library.current_world().present_observation(malformed, host.content_registry()).ok, "invalid cosmetic refuses projection")
	suite.assert_equal(atlas.snapshot(), atlas_before, "failed cosmetic keeps committed avatar visible")
	var router: Node = main.get_node("ReplayLibrary")
	suite.assert_true(router.select("run:" + id).ok and router.seek(int(latest.sequence)).ok, "actual Main router views automatic whole-run tape")
	var other: Dictionary = recorder.store().begin(latest.player.identity, 5)
	suite.assert_true(other.ok and recorder.store().finish(other.context.id, "INTERRUPTED").ok, "second tape is retained")
	var routed_world: SubViewport = router.current_world()
	suite.assert_true(router.remove("run:" + str(other.context.id)).ok, "other tape removes through actual router")
	suite.assert_true(router.current_world() == routed_world and router.seek(0).ok, "deleting unselected tape preserves current playback")
	main.call("_on_run_replay_rejected", &"RUN_REPLAY_RECORDER_CAPACITY")
	var notice: Control = main.get_node_or_null("ReplayNoticeLayer/ReplayNotice")
	suite.assert_true(notice != null and notice.visible, "recorder failure is visible during ordinary native play")
	router.close_selection()
	suite.assert_equal(player.full_player_replay_snapshot(), live_before, "viewing does not mutate live Player")
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile_before, "viewing does not mutate progression")
	suite.assert_equal(global_events, [], "viewing emits no global gameplay facts")
	suite.assert_true(library.seek(0).ok and library.set_speed(2.0).ok and library.set_playing(true).ok and library.advance(1.0 / 60.0).ok, "native controls advance observations")
	suite.assert_equal(library.snapshot().cursor, 2, "double speed advances two committed observations")
	var exported: Dictionary = library.export_recording(id)
	suite.assert_true(exported.ok and FileAccess.file_exists(exported.context.path), "whole run exports authenticated physical package")
	suite.assert_true(library.import_file(exported.context.path).ok and library.rows().size() == 1, "import is validated and idempotent")
	suite.assert_true(not library.import_json("{}").ok, "malformed whole-run import refuses")
	suite.assert_true(library.remove(id).ok and library.rows().is_empty() and library.current_world() == null, "explicit deletion closes private world and commits archive")
	var storage: RefCounted = recorder.store()
	var chunks: Array = DirAccess.open(str(storage.storage_identity().chunk_directory)).get_files()
	suite.assert_true(not chunks.is_empty(), "recovery backups retain deleted tape chunks")
	for index: int in range(3):
		var begun: Dictionary = storage.begin(latest.player.identity, 4)
		suite.assert_true(begun.ok and storage.finish(begun.context.id, "INTERRUPTED").ok and storage.remove(begun.context.id).ok, "new archive transactions rotate recovery generations")
	suite.assert_true(storage.collect_garbage().ok, "managed reclamation authenticates all retained manifests")
	var remaining := DirAccess.open(str(storage.storage_identity().chunk_directory)).get_files()
	suite.assert_true(remaining.is_empty(), "unreferenced chunks reclaim physical capacity after backup rotation")
	var visual_dir := OS.get_environment("PLANEWALKER_RUN_REPLAY_VISUAL_OUTPUT")
	if not visual_dir.is_empty():
		# Reimport the actual tape for native framebuffer verification.
		suite.assert_true(library.import_file(exported.context.path).ok and library.select(id).ok and library.seek(int(latest.sequence)).ok, "native visual tape reconstructs from exported physical bytes")
		var panel := preload("res://scripts/replay/player_replay_library_panel.gd").new()
		var layer := CanvasLayer.new()
		layer.layer = 75
		add_child(layer)
		layer.add_child(panel)
		suite.assert_true(panel.configure(library).ok and panel.open().ok, "whole-run native panel opens")
		panel.set_process(false)
		DirAccess.make_dir_recursive_absolute(visual_dir)
		for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			DisplayServer.window_set_size(resolution)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			suite.assert_true(not image.is_empty() and image.save_png(visual_dir.path_join("run-replay-%dx%d.png" % [resolution.x, resolution.y])) == OK, "native panel framebuffer retains rendered assets")
			var world_image: Image = library.current_world().get_texture().get_image()
			var colors: Dictionary = {}
			for y: int in range(0, world_image.get_height(), 4):
				for x: int in range(0, world_image.get_width(), 4):
					colors[world_image.get_pixel(x, y).to_rgba32()] = true
			suite.assert_true(colors.size() >= 8, "private replay canvas contains actual nonblank raster/room colors")
		panel.close_panel()
		layer.queue_free()
	EventBus.time_skill_committed.disconnect(observe)
	library.queue_free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	suite.finish(get_tree())
