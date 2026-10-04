extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Catalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	var launched: bool = main._launch_run(config, false, true)
	suite.assert_true(launched, "production Main launches actual accepted Launch content: %s" % str(main.get("_profile_error")))
	var host: Node = main.get_node("RunRuntimeHost")
	var controller: Node = main.get_node("CombatRoom01")
	var player: Node = controller.get_node("Player")
	host.set_process(false)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
	main.get_node("DungeonFlow").set_process(false)
	var facade: RefCounted = host.native_checkpoint_participants().facade
	var catalog_probe := Catalog.new()
	var catalog_report: Dictionary = catalog_probe.configure(facade.content_registry())
	suite.assert_true(catalog_report.ok, "activated native catalog is executable: %s" % str(catalog_report))
	suite.assert_true(facade.encounter_catalog() is Catalog, "production Launch resolves its complete authored encounter catalog")
	var runner: Node = controller.encounter_runner()
	suite.assert_true(runner.has_method("native_launch_snapshot"), "production EncounterRunner exposes its native deterministic frame aggregate")
	if not facade.encounter_catalog() is Catalog or not runner.has_method("native_launch_snapshot"):
		await _dispose(main)
		suite.finish(get_tree())
		return
	var spawn_reentry: Array[bool] = []
	var spawn_observer := func(actor: Node, _context: Dictionary):
		if is_instance_valid(actor) and controller.is_ancestor_of(actor):
			player.authoritative_frame_committed.emit(int(player.priority_arbitration_snapshot().frame))
			spawn_reentry.append(player.advance_action_frame())
	EventBus.enemy_spawned.connect(spawn_observer)
	var selected := false
	for route: Dictionary in host.route_choices():
		if route.room_type in ["combat", "elite"]:
			selected = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok
			break
	suite.assert_true(selected, "actual Host routing enters a native Launch combat room")
	if not selected:
		await _dispose(main)
		suite.finish(get_tree())
		return
	host.set_dungeon_selection_safety(false)
	var initial: Dictionary = runner.native_launch_snapshot()
	suite.assert_true(not initial.is_empty() and initial.encounter.identity.runtime_frame == player.priority_arbitration_snapshot().frame, "room and Player start on the same accepted frame")
	var resolved: Dictionary = facade.current_encounter_definition()
	var room: Dictionary = facade.current_room_definition()
	var expected: Dictionary = facade.encounter_catalog().resolve_for_node(str(room.encounter_id), int(host.runtime_snapshot().run_seed), str(room.node_id), str(room.type), str(room.template.id))
	suite.assert_true(resolved == expected and resolved == initial.definition and resolved.floor_id == host.runtime_snapshot().floor_plan.floor_id, "native recipe binds the actual floor, node and compatible room template")
	var accepted := true
	for _step: int in range(100):
		if not player.advance_action_frame():
			accepted = false
			break
		await get_tree().physics_frame
		if runner.alive_count() > 0:
			break
	suite.assert_true(accepted and runner.alive_count() > 0, "actual committed Player frames publish and acknowledge authored native spawns")
	var state: Dictionary = runner.native_launch_snapshot()
	suite.assert_true(state.encounter.pending_spawns.is_empty() and state.encounter.last_runtime_frame == player.priority_arbitration_snapshot().frame, "post-publication spawn registration retains the exact accepted encounter clock")
	var sources: Dictionary = {}
	for actor: Node in controller.get_node("Enemies").get_children():
		suite.assert_true(actor.has_method("configure_launch_definition") and actor.has_method("configure_launch_room_motion"), "production actors use actual Launch hostile and physical room contracts")
		if not actor.has_method("launch_runtime_snapshot"):
			continue
		var actor_state: Dictionary = actor.launch_runtime_snapshot()
		var source_id: String = str(actor.get("hostile_source_id"))
		sources[source_id] = true
		suite.assert_true(state.encounter.roster.has(source_id) and actor_state.runtime.runtime_frame == state.encounter.last_runtime_frame and actor_state.runtime.identity.run_id == host.runtime_snapshot().run_id, "native roster, actor and Player share authenticated source identity and clock")
		suite.assert_true(not actor.launch_room_motion_snapshot().is_empty(), "real authored anchors bind actor movement to the native room geometry")
	suite.assert_equal(sources.size(), runner.alive_count(), "every living production hostile has exactly one native roster entry")
	suite.assert_true(not spawn_reentry.is_empty() and not spawn_reentry.has(true), "native spawn publication refuses Player frame callback reentry")
	var encounter_before: Dictionary = state.encounter
	await get_tree().create_timer(0.1).timeout
	suite.assert_equal(runner.native_launch_snapshot().encounter, encounter_before, "paused Player frames cannot advance native waves through a wall-clock timer")
	var native_before: Dictionary = runner.native_launch_snapshot()
	var player_before: Dictionary = player.full_player_replay_snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(), "late production World rejection refuses the complete native encounter frame")
	suite.assert_equal(runner.native_launch_snapshot(), native_before, "late rejection compensates every production actor, effect and encounter participant")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "late rejection preserves complete native Player state")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "production native participants retry the same accepted frame")
	var before_forged: Dictionary = runner.native_launch_snapshot().encounter
	for actor: Node in controller.get_node("Enemies").get_children():
		actor.get_node("HealthComponent").died.emit(null)
		var source_id: StringName = actor.get("hostile_source_id")
		var receipt := "hostile_defeat:%s" % (str(player.current_run_id()) + "|" + str(source_id)).sha256_text().substr(0, 40)
		actor.hostile_final_death.emit(source_id, receipt)
	suite.assert_equal(runner.native_launch_snapshot().encounter, before_forged, "forged legacy Health death signals cannot remove actual native roster rows")
	var room_runtime: Node = host.native_checkpoint_participants().runtime
	var clears: Array[String] = []
	room_runtime.room_cleared.connect(func(room_id: StringName, _revision: int): clears.append(str(room_id)))
	var wave_count: int = resolved.waves.size()
	var waves: Dictionary = {}
	for _step: int in range(1000):
		if not runner.is_active():
			break
		waves[runner.current_wave_index()] = true
		for actor: Node in controller.get_node("Enemies").get_children():
			if not actor.is_queued_for_deletion():
				actor.get_node("HealthComponent").lose_health(1000.0, null)
		if not player.advance_action_frame():
			accepted = false
			break
		await get_tree().physics_frame
	suite.assert_true(accepted and not runner.is_active() and clears.size() == 1, "actual native death receipts retire every authored wave and publish one room clear: %s" % str(runner.snapshot()))
	suite.assert_true(waves.size() >= wave_count, "production room executes all authored native waves")
	var rewards_before: Dictionary = host.runtime_snapshot()
	suite.assert_true(player.advance_action_frame(), "Player can advance after the actual native room completion")
	suite.assert_equal(clears.size(), 1, "post-completion frame cannot publish duplicate room rewards")
	suite.assert_equal(host.runtime_snapshot(), rewards_before, "post-completion frame preserves the canonical pending reward")
	EventBus.enemy_spawned.disconnect(spawn_observer)
	var driver: Node = runner.get_node("NativeLaunchEncounterDriver")
	var callback_starts: Array[bool] = []
	var cancelled_warnings: Array[Dictionary] = []
	var warning_observer := func(spawn: Dictionary, _duration: float): cancelled_warnings.append(spawn)
	runner.spawn_warning_requested.connect(warning_observer)
	runner.wave_started.connect(func(_index: int, _id: StringName):
		callback_starts.append(driver.start(resolved, int(host.runtime_snapshot().run_seed), 1))
		player.authoritative_frame_committed.emit(int(player.priority_arbitration_snapshot().frame))
		callback_starts.append(player.advance_action_frame())
		runner.cancel()
	, CONNECT_ONE_SHOT)
	runner.start_encounter(resolved, int(host.runtime_snapshot().run_seed), int(room.room_number))
	suite.assert_true(player.advance_action_frame(), "actual native warning frame accepts deferred callback cancellation")
	suite.assert_equal(callback_starts, [false, false], "native wave callbacks cannot replace the aggregate or reenter an accepted Player frame")
	suite.assert_true(runner.native_launch_snapshot().is_empty() and cancelled_warnings.is_empty(), "deferred native cancellation stops same-frame warnings and destroys its aggregate")
	suite.assert_true(player.advance_action_frame(), "native cancellation releases the Player frame owner at the accepted boundary")
	runner.spawn_warning_requested.disconnect(warning_observer)
	await _dispose(main)
	suite.finish(get_tree())


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
