extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const State := preload("res://autoload/game_state.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Ledger := preload("res://scripts/save/actual_content_compatibility_ledger.gd")
const Checkpoint := preload("res://scripts/save/native_run_checkpoint_authority.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var native := await _fixture(suite, false)
	var gun := await _fixture(suite, false, "gun")
	var staff := await _fixture(suite, false, "staff")
	var terminal := await _fixture(suite, true)
	if native.is_empty() or gun.is_empty() or staff.is_empty() or terminal.is_empty():
		suite.finish(get_tree())
		return
	var catalog: RefCounted = Factory.load_base().context.catalog
	var sources := Ledger.trusted_sources(native.binding, catalog.fingerprint())
	suite.assert_true(not sources.is_empty(), "native migration uses authenticated historical descriptors")
	if sources.is_empty():
		suite.finish(get_tree())
		return
	for index: int in range(sources.size()):
		await _migrate(suite, native, sources[index], catalog, "native_%d" % index)
		await _migrate(suite, gun, sources[index], catalog, "gun_%d" % index)
		await _migrate(suite, staff, sources[index], catalog, "staff_%d" % index)
		await _migrate(suite, terminal, sources[index], catalog, "terminal_%d" % index)
	for kind: String in ["actor", "authored"]:
		var changed := native.duplicate(true)
		var aggregate: Dictionary = Replay.decode_replay_json(changed.payload.native_run_checkpoint.encounter_codec).replay
		if kind == "actor":
			aggregate.actors[aggregate.actors.keys()[0]].actor.weapon_claim_order = [-1]
		else:
			aggregate.definition.waves[0].spawns[0].spawn_offset.x += 1.0
			aggregate.encounter.encounter_digest = JSON.stringify(aggregate.definition).sha256_text()
		changed.payload.native_run_checkpoint.encounter_codec = Replay.encode_replay_json(aggregate).json
		changed.payload.native_run_checkpoint.erase("digest")
		changed.payload.native_run_checkpoint.digest = Checkpoint.canonical(changed.payload.native_run_checkpoint).sha256_text()
		suite.assert_true(Checkpoint.validate(changed.payload.native_run_checkpoint, changed.payload.active_run_state, changed.payload.reward_effect_state).ok, "re-signed " + kind + " fixture passes structural authentication and still requires actual reconstruction")
		await _migrate(suite, changed, sources[0], catalog, "refused_" + kind, true)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _fixture(suite: RefCounted, terminal: bool, weapon: String = "sword") -> Dictionary:
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	main.get_node("CombatRoom01").process_mode = Node.PROCESS_MODE_PAUSABLE
	var registry: RefCounted = host.content_registry()
	var binding := Content.snapshot(registry)
	var catalog: RefCounted = Factory.load_base().context.catalog
	var save := Save.new()
	var service := Service.new()
	var slot := "terminal_fixture" if terminal else "native_fixture_" + weapon
	suite.assert_true(save.configure(Paths.resolve_default("user://p16s-fixture", "p16s-fixture"), "0.4.0-dev", binding).ok and service.configure(catalog, save, slot, "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "migration fixture owns an actual physical Profile")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(host.start_profile_run(config, service, int(service.snapshot().revision)).ok, "migration fixture launches through actual Host")
	var selected := false
	for choice: Dictionary in host.route_choices():
		if choice.node_id == "layer_01_a":
			selected = host.select_route(StringName(choice.edge_id), int(host.runtime_snapshot().revision)).ok
			break
	suite.assert_true(selected, "migration fixture binds an actual authored room")
	var controller: Node = main.get_node("CombatRoom01")
	var player: Node = controller.get_node("Player")
	var runner: Node = controller.encounter_runner()
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"migration_fixture")
	var ready := false
	for _frame: int in range(80):
		if not player.advance_action_frame():
			break
		ready = runner.native_launch_snapshot().get("actors", {}).size() > 0
		if ready:
			break
		await get_tree().physics_frame
	suite.assert_true(ready, "migration fixture retains real native actors at an accepted frame")
	if terminal:
		host.native_checkpoint_participants().facade.advance_time(1.0)
		suite.assert_true(host.native_checkpoint_participants().runtime.report_player_died("migration_fixture").ok, "migration fixture uses actual terminal settlement")
	var retained: Variant = host.checkpoint_profile_run(int(service.snapshot().revision))
	suite.assert_true(retained.ok, "migration fixture captures actual native or settled checkpoint")
	if not retained.ok:
		await _dispose(main)
		return {}
	if terminal:
		var settled: Dictionary = service.settle_terminal(host.runtime_snapshot(), [], int(service.snapshot().revision))
		suite.assert_true(settled.ok, "physical fixture settles its authenticated terminal Run: " + str(settled))
	var payload := service.payload()
	payload.sentinel = {"nested": ["unchanged", 41]}
	var next_native: Dictionary = {}
	var next_player: Dictionary = {}
	if not terminal:
		suite.assert_true(player.advance_action_frame(), "uninterrupted migration fixture accepts next native frame")
		next_native = runner.native_launch_snapshot()
		next_player = player.full_player_replay_snapshot()
	else:
		suite.assert_true(service.snapshot().active_launch_receipt.is_empty() and not service.snapshot().last_settlement_receipt.is_empty(), "terminal migration starts from actual settled lineage")
	await _dispose(main)
	return {"payload": payload, "binding": binding, "registry": registry, "next_native": next_native, "next_player": next_player, "terminal": terminal}


func _migrate(suite: RefCounted, fixture: Dictionary, source: Dictionary, catalog: RefCounted, id: String, refuse: bool = false) -> void:
	var path := Paths.resolve_default("user://p16s-migration/" + id + "/legacy.json", "p16s-migration/" + id + "/legacy.json")
	var root := path.get_base_dir().path_join("plane_walker/save")
	var save := Save.new()
	var payload: Dictionary = JSON.parse_string(JSON.stringify(fixture.payload, "", true, true))
	suite.assert_true(save.configure(root, "0.4.0-dev", source).ok and save.enable_meta_profile(catalog).ok, "historical native fixture authenticates source content")
	var written: Variant = save.save_profile("slot_1", "base", payload)
	suite.assert_true(written.ok, "historical native primary promotes: " + id + " " + str(written.code))
	if not written.ok:
		return
	var primary := root.path_join("profiles/slot_1/base/primary.json")
	var before := FileAccess.get_file_as_string(primary)
	var original: Dictionary = save.inspect_profile("slot_1", "base").payload.payload
	var state := State.new()
	state.save_path = path
	add_child(state)
	var memory := state.persistent.duplicate(true)
	var children_before := state.get_child_count()
	var publications := {"spawns": 0, "launches": 0, "settlements": 0, "resources": 0}
	var on_spawn := func(_enemy: Node, _facts: Dictionary) -> void: publications.spawns += 1
	var on_launch := func(_run: String, _facts: Dictionary) -> void: publications.launches += 1
	var on_settlement := func(_run: String, _facts: Dictionary, _revision: int) -> void: publications.settlements += 1
	var on_resource := func(_weapon: StringName, _resource: StringName, _current: float, _maximum: float, _reason: StringName) -> void: publications.resources += 1
	EventBus.enemy_spawned.connect(on_spawn)
	EventBus.run_started.connect(on_launch)
	EventBus.run_ended.connect(on_settlement)
	EventBus.weapon_resource_changed.connect(on_resource)
	var result: Dictionary = state.activate_profile_content(fixture.registry)
	EventBus.enemy_spawned.disconnect(on_spawn)
	EventBus.run_started.disconnect(on_launch)
	EventBus.run_ended.disconnect(on_settlement)
	EventBus.weapon_resource_changed.disconnect(on_resource)
	suite.assert_true(state.get_child_count() == children_before and publications == {"spawns": 0, "launches": 0, "settlements": 0, "resources": 0}, "native compatibility probe retires synchronously without gameplay publication: " + id + " " + str(publications))
	if refuse:
		suite.assert_true(not result.ok and result.code == &"NATIVE_CONTENT_MIGRATION_REQUIRED", "actual reconstruction rejects re-signed incompatible " + id + ": " + str(result))
		suite.assert_true(FileAccess.get_file_as_string(primary) == before and state.persistent == memory and state.profile_runtime_service() == null, "refused native migration preserves primary bytes and authoritative memory")
	else:
		suite.assert_true(result.ok, "trusted native or settled content activates: " + id + " " + str(result))
		if not result.ok:
			state.queue_free()
			await get_tree().process_frame
			return
		var current := Save.new()
		current.configure(root, "0.4.0-dev", fixture.binding)
		current.enable_meta_profile(catalog)
		var inspected: Variant = current.inspect_profile("slot_1", "base")
		suite.assert_true(inspected.ok and inspected.payload.payload == original, "atomic native rebinding preserves the entire physical payload, currency, revision, launch and settlement")
		var promoted := FileAccess.get_file_as_string(primary)
		suite.assert_true(state.activate_profile_content(fixture.registry).ok and FileAccess.get_file_as_string(primary) == promoted, "repeated native activation cannot consume another save sequence")
		var main := Main.instantiate()
		add_child(main)
		await get_tree().process_frame
		Route.freeze(main)
		main.get_node("DungeonFlow").set_process(false)
		var restored: Variant = main.get_node("RunRuntimeHost").restore_profile_checkpoint(state.profile_runtime_service(), int(state.profile_runtime_service().snapshot().revision))
		suite.assert_true(restored.ok, "migrated physical checkpoint cold-restores through another actual Main: " + id + " " + str(restored.code))
		if restored.ok and not fixture.terminal:
			await get_tree().physics_frame
			var player: Node = main.get_node("CombatRoom01/Player")
			suite.assert_true(player.advance_action_frame(), "migrated active checkpoint accepts original next frame")
			suite.assert_true(main.get_node("CombatRoom01").encounter_runner().native_launch_snapshot() == fixture.next_native and player.full_player_replay_snapshot() == fixture.next_player, "migrated native continuation equals the uninterrupted physical branch")
		await _dispose(main)
	state.queue_free()
	await get_tree().process_frame


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
