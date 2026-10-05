extends "res://tests/integration/save/native_combat_checkpoint_test.gd"

const EncounterCatalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const FloorGenerator := preload("res://scripts/dungeon/floor_plan_generator.gd")
const Config := preload("res://scripts/application/run_config.gd")


func _run() -> void:
	var suite := Suite.new()
	for floor_index: int in range(2):
		var selected := OS.get_environment("PLANEWALKER_NATURAL_ELITE_CASE")
		if selected.is_empty() or selected == str(floor_index):
			await _terminal_encounter(suite, floor_index)
	if OS.get_environment("PLANEWALKER_NATURAL_ELITE_CASE") in ["", "historical"]:
		await _historical_encounter(suite)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _terminal_encounter(suite: RefCounted, floor_index: int) -> void:
	var target := _find_recipe(floor_index)
	suite.assert_true(not target.is_empty(), "actual seeded floor plan reaches additive terminal elite recipe")
	if target.is_empty():
		return
	var f := await _new_profile(suite, target.seed, "terminal_%d" % floor_index)
	suite.assert_true(f.host.runtime_snapshot().config.get("launch_encounter_revision") == 2 and f.service.pending_launch_config().get("launch_encounter_revision") == 2, "new native Profile freezes selection revision2 in Run and pending launch")
	if not await _route_to_recipe(suite, f.host, floor_index, str(target.node_id)):
		suite.assert_true(false, "actual Host reaches exact authored terminal elite route")
		await _dispose(f.main)
		return
	var expected: Dictionary = f.host.native_checkpoint_participants().facade.current_encounter_definition()
	suite.assert_equal(expected.id, target.recipe_id, "Host resolves concrete additive encounter authority without definition injection")
	f.host.set_dungeon_selection_safety(false)
	f.player.health.acquire_invulnerability_source(&"terminal_route_input_fixture")
	for _frame: int in range(80):
		if not f.runner.native_launch_snapshot().actors.is_empty():
			break
		suite.assert_true(f.player.advance_action_frame(), "actual terminal room completes full native spawn warning")
		await get_tree().physics_frame
	var driver: Node = f.runner.get_node("NativeLaunchEncounterDriver")
	var owner: Node2D
	for actor: Node2D in driver.get("_actors").values():
		if actor.get("_launch_definition").id == target.species and actor.get("_launch_definition").actor_kind == "elite":
			owner = actor
			break
	suite.assert_true(is_instance_valid(owner), "production Driver constructs the genuine authored elite terminal species")
	if not is_instance_valid(owner):
		await _dispose(f.main)
		return
	var source := str(owner.hostile_source_id)
	suite.assert_equal(owner.launch_affix_snapshot().ids, ["frenzy"], "natural elite retains its canonical Frenzy affix")
	# Isolate hostile steering while ordinary input and physical body damage remain real.
	suite.assert_true(owner.get("_launch_runtime").add_control_source("natural_terminal_input_fixture", "stop", 1200, 1.0), "terminal input fixture freezes principal steering with a restorable domain control")
	for _attack: int in range(12):
		if not driver.get("_actors").has(source):
			break
		f.player.global_position = owner.global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary") and f.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "ordinary native light Sword input attacks natural terminal principal")
		for _frame: int in range(120):
			suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "actual Sword collision advances shared native room frame")
			await get_tree().physics_frame
			if not driver.get("_actors").has(source):
				break
	f.player.cancel_transient_actions()
	suite.assert_true(f.player.advance_action_frame(), "next accepted native frame flushes physical death receipt before durable capture")
	await get_tree().physics_frame
	var pending: Dictionary = f.runner.native_launch_snapshot()
	var child_work := false
	if not pending.is_empty():
		child_work = pending.effects.summons.rows.size() == 2 and pending.effects.summons.rows.all(func(row: Dictionary): return pending.encounter.pending_work.has(row.id))
	suite.assert_true(not pending.is_empty() and not driver.get("_actors").has(source) and pending.encounter.defeat_ledger.has(source) and child_work, "actual native terminal death preserves two authenticated unrewarded children in production Encounter: " + _terminal_view(pending))
	if pending.is_empty() or not pending.encounter.defeat_ledger.has(source):
		await _dispose(f.main)
		return
	f.player.global_position = Vector2(500, 220)
	await get_tree().physics_frame
	await get_tree().physics_frame
	f = await _physical_roundtrip(suite, f, "pending")
	if f.is_empty():
		return
	var warning_frames := 0
	for row: Dictionary in f.runner.native_launch_snapshot().effects.summons.rows:
		warning_frames = maxi(warning_frames, int(row.spawn_warning_frames))
	for _warning: int in range(warning_frames + 1):
		suite.assert_true(f.player.advance_action_frame(), "restored terminal work completes full original child warning")
		await get_tree().physics_frame
	var active: Dictionary = f.runner.native_launch_snapshot()
	suite.assert_true(active.summon_actors.size() == 2 and active.effects.summons.rows.all(func(row: Dictionary): return active.encounter.pending_work.has(row.id)), "cold restored natural terminal work publishes two actual child bodies: " + _terminal_view(active))
	for row: Dictionary in active.effects.summons.rows:
		suite.assert_true(row.parent_source_id == source and row.spawn_mode == "DEATH" and row.phase == "ACTIVE" and not row.retire_on_owner_death and row.birth_frame >= row.warning_frame + row.spawn_warning_frames, "terminal children retain source, complete warning and orphan lifetime")
	f = await _physical_roundtrip(suite, f, "active")
	if not f.is_empty():
		await _dispose(f.main)


func _historical_encounter(suite: RefCounted) -> void:
	var f := await _new_profile(suite, 4, "historical", true)
	suite.assert_true(not f.host.runtime_snapshot().config.has("launch_encounter_revision") and not f.service.pending_launch_config().has("launch_encounter_revision"), "actual retry startup retains a historical frozen launch without current revision")
	suite.assert_true(await _route_to_elite(f.host), "historical native Run reaches a real authored elite")
	f.host.set_dungeon_selection_safety(false)
	f.player.health.acquire_invulnerability_source(&"historical_encounter_fixture")
	suite.assert_true(f.player.advance_action_frame(), "historical elite publishes a genuine accepted warning frame")
	f = await _physical_roundtrip(suite, f, "historical")
	if f.is_empty():
		return
	suite.assert_true(not f.host.runtime_snapshot().config.has("launch_encounter_revision") and not f.service.pending_launch_config().has("launch_encounter_revision"), "physical reconstruction cannot invent new encounter selection for a historical Run")
	_assert_historical_recipe(suite, f.host)
	suite.assert_true(f.host.native_checkpoint_participants().runtime.complete_current_room().ok, "explicit prerequisite receipt fixture releases historical elite continuation")
	for _choice: int in range(8):
		var state: Dictionary = f.host.runtime_snapshot()
		if state.open_offer.is_empty():
			break
		f.host._on_option_chosen(str(state.open_offer.offer_id), str(state.open_offer.options[0].option_id), int(state.open_offer.revision))
	for choice: Dictionary in f.host.route_choices():
		if choice.room_type in ["combat", "elite"]:
			suite.assert_true(f.host.select_route(StringName(choice.edge_id), int(f.host.runtime_snapshot().revision)).ok, "historical cold Run selects its next actual authored combat node")
			_assert_historical_recipe(suite, f.host)
			break
	await _dispose(f.main)


func _assert_historical_recipe(suite: RefCounted, host: Node) -> void:
	var facade: RefCounted = host.native_checkpoint_participants().facade
	var room: Dictionary = facade.current_room_definition()
	var expected: Dictionary = facade.encounter_catalog().resolve_for_node(str(room.encounter_id), int(host.runtime_snapshot().run_seed), str(room.node_id), str(room.type), str(room.template.id))
	suite.assert_equal(facade.current_encounter_definition(), expected, "historical future rooms retain original revision1 seeded resolver")


func _new_profile(suite: RefCounted, seed: int, suffix: String, historical: bool = false) -> Dictionary:
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	var controller: Node = main.get_node("CombatRoom01")
	controller.visible = true
	controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	var catalog: RefCounted = Factory.load_base().context.catalog
	var save := Save.new()
	var service := Service.new()
	var slot := "natural_elite_" + suffix
	suite.assert_true(save.configure(Paths.resolve_default("user://natural-elite-checkpoint", "natural-elite-checkpoint"), "0.4.0-dev", Content.snapshot(host.content_registry())).ok and service.configure(catalog, save, slot, "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "natural elite fixture configures actual content and physical Profile")
	var config := Config.normalized({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": seed})
	var started: Variant
	if historical:
		var prepared: Dictionary = service.prepare_launch({"seed": config.seed, "difficulty": config.difficulty, "character_id": config.character_id, "weapon_id": config.weapon_id, "time_abilities": config.enabled_time_skills}, int(service.snapshot().revision), config)
		suite.assert_true(prepared.ok, "historical pending launch physically freezes absent revision")
		started = host.retry_profile_startup(service, int(service.snapshot().revision))
	else:
		started = host.start_profile_run(config, service, int(service.snapshot().revision))
	suite.assert_true(started.ok, "actual Profile Host starts natural elite fixture: " + str(started.code) + " " + str(started.context))
	return {"main": main, "host": host, "controller": controller, "player": controller.get_node("Player"), "runner": controller.encounter_runner(), "service": service, "save": save, "catalog": catalog, "slot": slot}


func _physical_roundtrip(suite: RefCounted, f: Dictionary, label: String) -> Dictionary:
	var before: Dictionary = f.runner.native_launch_snapshot()
	var player_before: Dictionary = f.player.full_player_replay_snapshot()
	var run_before: Dictionary = f.host.runtime_snapshot()
	var retained: Variant = f.host.checkpoint_profile_run(int(f.service.snapshot().revision))
	suite.assert_true(retained.ok, "natural elite " + label + " persists through physical SaveService: " + str(retained.code) + " " + str(retained.context))
	if not retained.ok:
		await _dispose(f.main)
		return {}
	var profile_before: Dictionary = f.service.snapshot()
	suite.assert_true(f.player.advance_action_frame(), "uninterrupted natural elite accepts next shared frame")
	var next_native: Dictionary = f.runner.native_launch_snapshot()
	var next_player: Dictionary = f.player.full_player_replay_snapshot()
	await _dispose(f.main)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	f.main = main
	f.host = main.get_node("RunRuntimeHost")
	f.controller = main.get_node("CombatRoom01")
	f.player = f.controller.get_node("Player")
	f.runner = f.controller.encounter_runner()
	f.service = Service.new()
	suite.assert_true(f.service.configure(f.catalog, f.save, f.slot, "base").ok, "new Profile service reads natural elite physical primary")
	var restored: Variant = f.host.restore_profile_checkpoint(f.service, int(f.service.snapshot().revision))
	suite.assert_true(restored.ok, "fresh Main reconstructs natural elite " + label + ": " + str(restored.code) + " " + str(restored.context))
	if not restored.ok:
		await _dispose(main)
		return {}
	suite.assert_equal(f.runner.native_launch_snapshot(), before, "cold natural elite preserves exact definition, receipt ledger, terminal rows, bodies and clocks")
	suite.assert_equal(f.player.full_player_replay_snapshot(), player_before, "cold natural elite preserves full Player state")
	suite.assert_true(_equal_json(f.host.runtime_snapshot(), run_before) and f.service.snapshot() == profile_before, "cold natural elite preserves exact Run revision and durable Profile")
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.advance_action_frame(), "cold natural elite accepts same next shared frame")
	suite.assert_equal(f.runner.native_launch_snapshot(), next_native, "cold natural elite continuation matches uninterrupted next frame")
	suite.assert_equal(f.player.full_player_replay_snapshot(), next_player, "cold natural elite Player matches uninterrupted next frame")
	return f


func _terminal_view(native: Dictionary) -> String:
	if native.is_empty():
		return "empty"
	return str({"rows": native.effects.summons.rows.map(func(row: Dictionary): return {"id": row.id, "phase": row.phase, "warning_frame": row.warning_frame, "spawn_warning_frames": row.spawn_warning_frames}), "work": native.encounter.pending_work.keys(), "children": native.summon_actors.keys()})


func _find_recipe(floor_index: int) -> Dictionary:
	var catalog := EncounterCatalog.new()
	if not catalog.configure_authored().ok:
		return {}
	var floors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json"))
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	var species := "ruins_wraith" if floor_index == 0 else "void_spore"
	for seed: int in range(1, 64):
		var generated: Dictionary = FloorGenerator.new().generate(seed, floors[floor_index], templates)
		if not generated.ok:
			continue
		for node: Dictionary in generated.plan.nodes:
			if node.room_type != "elite":
				continue
			var recipe: Dictionary = catalog.resolve_for_revision(str(floors[floor_index].encounter_profile_id), seed, str(node.id), "elite", str(node.template_id), 2)
			for wave: Dictionary in recipe.get("waves", []):
				for spawn: Dictionary in wave.spawns:
					if spawn.elite and spawn.enemy_id == species:
						return {"seed": seed, "node_id": node.id, "species": species, "recipe_id": recipe.id}
	return {}


func _route_to_recipe(suite: RefCounted, host: Node, floor_index: int, target_node: String) -> bool:
	# Prerequisite room/Boss receipts are fixtures; the target route and Driver are real.
	for _step: int in range(140):
		var state: Dictionary = host.runtime_snapshot()
		var node: Dictionary = host.native_run_state().current_floor_node()
		if int(state.current_floor_index) == floor_index and node.id == target_node:
			return true
		var result: Variant
		if not state.open_offer.is_empty():
			host._on_option_chosen(str(state.open_offer.offer_id), str(state.open_offer.options[0].option_id), int(state.open_offer.revision))
			result = {"ok": int(host.runtime_snapshot().revision) > int(state.revision)}
		elif int(state.phase) == Phase.Value.RUN_PREPARING:
			result = host.start_next_floor(int(state.revision))
		elif node.id == state.floor_plan.entry_node_id or node.cleared:
			var choices: Array = host.route_choices()
			if choices.is_empty():
				return false
			var selected: Dictionary = choices[0]
			if int(state.current_floor_index) == floor_index:
				var ancestors: Array[String] = [target_node]
				for _layer: int in range(12):
					for edge: Dictionary in state.floor_plan.edges:
						if ancestors.has(str(edge.destination_node_id)) and not ancestors.has(str(edge.source_node_id)):
							ancestors.append(str(edge.source_node_id))
				for choice: Dictionary in choices:
					if ancestors.has(str(choice.node_id)):
						selected = choice
						break
			result = host.select_route(StringName(selected.edge_id), int(state.revision))
		else:
			match node.room_type:
				"shop": result = host.leave_merchant(int(state.revision))
				"event": result = host.choose_event_option(&"decline", int(state.revision)) if host.dungeon_ui_context().event.phase == "open" else host.dismiss_event(int(state.revision))
				"treasure", "rest": result = host.resolve_room_interaction(&"leave", int(state.revision))
				_:
					if node.room_type == "boss":
						var launch: Dictionary = host.native_checkpoint_participants().profile.snapshot().active_launch_receipt
						var receipt := {"schema_id": Settlement.SOURCE_TYPE, "run_id": launch.run_id, "launch_sequence": int(launch.sequence), "floor_id": state.floor_plan.floor_id, "node_id": node.id, "kind": "boss", "payload": {"actor_role": "principal", "boss_id": Settlement.BOSS_ORDER[int(state.current_floor_index)]}}
						receipt["source_id"] = Settlement.source_id(receipt, receipt.payload.boss_id)
						host.native_run_state().events.append({"type": Settlement.SOURCE_TYPE, "receipt": receipt})
					result = host.native_checkpoint_participants().runtime.complete_current_room()
		if not result.ok:
			suite.assert_true(false, "natural elite prerequisite route progresses: " + str(result))
			return false
		await get_tree().process_frame
	return false
