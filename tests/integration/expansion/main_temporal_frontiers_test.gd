extends "res://tests/integration/save/natural_elite_encounter_checkpoint_test.gd"

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const ExpansionEnemy := preload("res://scripts/enemies/expansion/expansion_enemy_definition.gd")


func _run() -> void:
	var suite := Suite.new()
	var base_catalog: RefCounted = Factory.load_base().context.catalog
	var base_save := Save.new()
	var base_registry := ContentRegistryScript.new()
	base_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(base_save.configure(GameState.save_path.get_base_dir().path_join("plane_walker/save"), "0.4.0-dev", Content.snapshot(base_registry)).ok and base_save.enable_meta_profile(base_catalog).ok, "valuable Base fixture binds actual content")
	var base_profile: Dictionary = Fixtures.profile(base_catalog)
	base_profile.chronos_shards = 73
	suite.assert_true(base_save.save_profile("slot_1", "base", {"meta_profile_state": base_profile, "chronos_shards": 73, "sentinel": {"preserved": ["original", 73]}}).ok, "valuable Base persists before optional Expansion install")
	var base_path := GameState.save_path.get_base_dir().path_join("plane_walker/save/profiles/slot_1/base/primary.json")
	var base_bytes := FileAccess.get_file_as_string(base_path)
	var main := Main.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	suite.assert_true(main.open_content_management().ok, "actual Hub opens builtin Expansion installation")
	var panel: Control = main.get_node("ContentManagementLayer/ContentManagementPanel")
	var install: Button
	for control: Button in panel.action_controls():
		if control.get_meta("action_id") == "install:temporal_frontiers":
			install = control
	suite.assert_true(install != null and not install.disabled and not install.text.begins_with("UI_"), "builtin Expansion is localized and discoverable without filesystem selection")
	if install == null:
		await _end(suite, main)
		return
	install.pressed.emit()
	var manager: RefCounted = main.content_manager()
	suite.assert_true(manager.discovery().installed.size() == 1 and manager.discovery().installed[0].pack_id == "temporal_frontiers", "actual native builtin command installs authenticated data-only bytes")
	var enabled: Dictionary = main.submit_content_command("set_enabled", {"ids": ["temporal_frontiers"]}, int(panel.view_state().revision))
	suite.assert_true(enabled.ok, "actual Main activates complete optional Expansion assembly: " + str(enabled))
	for _frame: int in range(6):
		await get_tree().process_frame
	main = get_tree().current_scene
	var activation: Dictionary = main.content_manager().activation_context()
	suite.assert_true(activation.save_domain.begins_with("mod_") and not activation.verified_play_eligible, "actual Expansion saves use isolated local assembly domain")
	suite.assert_equal(FileAccess.get_file_as_string(base_path), base_bytes, "native Expansion activation preserves valuable Base bytes")
	for floor_index: int in range(5):
		var host: Node = main.get_node("RunRuntimeHost")
		var target := _expansion_route(host.content_registry(), floor_index)
		suite.assert_true(not target.is_empty(), "actual seeded FloorGenerator exposes Expansion species on floor %d" % (floor_index + 1))
		if target.is_empty():
			await _end(suite, main)
			return
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": target.seed}
		var launched: bool = main._launch_run(config, false, true)
		suite.assert_true(launched, "canonical selected Profile creates native Expansion Run: " + str(main.get("_last_launch_rejection")))
		if not launched:
			await _end(suite, main)
			return
		Route.freeze(main)
		main.get_node("DungeonFlow").set_process(false)
		suite.assert_equal(host.runtime_snapshot().config.get("launch_encounter_revision"), 3, "new selected Expansion Profile freezes revision3 in durable Run")
		if not await _route_to_recipe(suite, host, floor_index, target.node_id):
			suite.assert_true(false, "native Expansion route reaches authored selected recipe")
			await _end(suite, main)
			return
		var room: Node = main.get_node("CombatRoom01")
		var player: Node2D = room.get_node("Player")
		var runner: Node = room.encounter_runner()
		host.set_dungeon_selection_safety(false)
		player.health.acquire_invulnerability_source(&"expansion_checkpoint_fixture")
		for _frame: int in range(60):
			if not runner.native_launch_snapshot().actors.is_empty():
				break
			suite.assert_true(player.advance_action_frame(), "production Expansion spawn retains complete warning")
			await get_tree().physics_frame
		var driver: Node = runner.get_node("NativeLaunchEncounterDriver")
		var actors: Dictionary = driver.get("_actors")
		suite.assert_true(actors.size() == 1 and actors.values()[0].get("_launch_definition").id == ExpansionEnemy.IDS[floor_index], "production Driver constructs genuine authored Expansion Actor for each floor")
		if actors.size() != 1:
			await _end(suite, main)
			return
		var actor: Node2D = actors.values()[0]
		player.global_position = actor.global_position + Vector2(48, 0)
		var action: Dictionary = actor.get("_launch_definition").actions[0]
		var committed: Dictionary = actor.get("_launch_runtime").request_action(action.id, {"runtime_frame": int(player.priority_arbitration_snapshot().frame), "source_position": _point(actor.global_position), "target_position": _point(player.global_position), "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
		suite.assert_true(committed.ok, "production Expansion checkpoint captures genuine committed action")
		for fact: Dictionary in committed.get("threat_facts", []):
			room.hostile_threat_registry().register_fact(Actions.native_threat_fact(fact))
		actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
		var checkpointed: Dictionary = main.checkpoint_current_run()
		suite.assert_true(checkpointed.ok, "selected Expansion physically saves native body and warning: " + str(checkpointed))
		if not checkpointed.ok:
			await _end(suite, main)
			return
		var native_before: Dictionary = runner.native_launch_snapshot()
		var run_before: Dictionary = host.runtime_snapshot()
		var profile_before: Dictionary = GameState.profile_runtime_service().snapshot()
		suite.assert_true(player.advance_action_frame(), "live Expansion checkpoint accepts next native frame")
		var next_native: Dictionary = runner.native_launch_snapshot()
		var next_player: Dictionary = player.full_player_replay_snapshot()
		suite.assert_equal(get_tree().reload_current_scene(), OK, "selected Expansion reconstructs fresh physical Main")
		for _frame: int in range(6):
			await get_tree().process_frame
		main = get_tree().current_scene
		launched = main._launch_run(config, false, true)
		suite.assert_true(launched, "fresh selected Main cold-restores revision3 Expansion checkpoint: " + str(main.get("_last_launch_rejection")))
		if not launched:
			await _end(suite, main)
			return
		Route.freeze(main)
		main.get_node("DungeonFlow").set_process(false)
		host = main.get_node("RunRuntimeHost")
		room = main.get_node("CombatRoom01")
		player = room.get_node("Player")
		runner = room.encounter_runner()
		suite.assert_equal(runner.native_launch_snapshot(), native_before, "cold Expansion preserves exact warning, actor, generation and effects")
		suite.assert_true(_equal_json(host.runtime_snapshot(), run_before) and GameState.profile_runtime_service().snapshot() == profile_before, "cold selected Expansion preserves durable Run and Profile")
		suite.assert_true(player.advance_action_frame(), "cold Expansion accepts same next native frame")
		suite.assert_equal(runner.native_launch_snapshot(), next_native, "cold selected Expansion native continuation matches uninterrupted branch")
		suite.assert_equal(player.full_player_replay_snapshot(), next_player, "cold selected Expansion full Player continuation matches uninterrupted branch")
		host.set_dungeon_selection_safety(false)
		host._process(1.0 / 60.0)
		player.health.lose_health(100000)
		await get_tree().process_frame
		await get_tree().process_frame
		var returned: bool = GameState.profile_runtime_service().snapshot().active_launch_receipt.is_empty() and main.return_to_hub()
		suite.assert_true(returned, "actual selected Expansion terminal settles isolated domain and returns Hub: " + str(main.retry_terminal_settlement()))
		if not returned:
			await _end(suite, main)
			return
	suite.assert_true(main.open_content_management().ok, "settled native Expansion Hub permits disabling package")
	panel = main.get_node("ContentManagementLayer/ContentManagementPanel")
	suite.assert_true(main.submit_content_command("set_enabled", {"ids": []}, int(panel.view_state().revision)).ok, "native player disables optional Expansion assembly")
	for _frame: int in range(6):
		await get_tree().process_frame
	main = get_tree().current_scene
	suite.assert_equal(GameState.active_profile_domain(), "base", "native pack disable returns original Base Profile")
	suite.assert_equal(FileAccess.get_file_as_string(base_path), base_bytes, "five native Expansion runs and cold restores preserve original Base save bytes")
	suite.assert_true(FileAccess.file_exists(GameState.save_path.get_base_dir().path_join("plane_walker/save/profiles/slot_1").path_join(activation.save_domain).path_join("primary.json")), "disabled optional pack retains its recoverable isolated physical save")
	await _end(suite, main)


func _expansion_route(registry: RefCounted, floor_index: int) -> Dictionary:
	var catalog := EncounterCatalog.new()
	if not catalog.configure(registry).ok:
		return {}
	var floors: Array = registry.get_catalog_entries(&"floor_definition", &"EXPANSION")
	floors.sort_custom(func(left: Dictionary, right: Dictionary): return left.order < right.order)
	var templates: Array = registry.get_catalog_entries(&"room_template", &"EXPANSION")
	for seed: int in range(1, 64):
		var generated: Dictionary = FloorGenerator.new().generate(seed, floors[floor_index], templates)
		if not generated.ok:
			continue
		for node: Dictionary in generated.plan.nodes:
			if node.room_type != "combat":
				continue
			var encounter: Dictionary = catalog.resolve_for_revision(floors[floor_index].encounter_profile_id, seed, node.id, node.room_type, node.template_id, 3)
			if not encounter.is_empty() and encounter.waves[0].spawns[0].enemy_id == ExpansionEnemy.IDS[floor_index]:
				return {"seed": seed, "node_id": node.id}
	return {}


func _end(suite: RefCounted, main: Node) -> void:
	get_tree().current_scene = self
	var playback_refs: Array[WeakRef] = []
	var director: Node = main.get_node_or_null("MusicDirector")
	if director != null:
		for deck: Node in director.get_children():
			if deck is AudioStreamPlayer and deck.playing and deck.get_stream_playback() != null:
				playback_refs.append(weakref(deck.get_stream_playback()))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for _step: int in range(20):
		if playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null):
			break
		await get_tree().create_timer(0.01).timeout
	suite.assert_true(playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "fresh Expansion Main teardown releases actual independent audio playback")
	suite.finish(get_tree())


func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
