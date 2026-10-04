extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Snapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Checkpoint := preload("res://scripts/save/native_run_checkpoint_authority.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Run := preload("res://scripts/application/run_state.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	_seed_base_profile(suite)
	var main := Main.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	suite.assert_true(main.has_method("content_manager") and main.has_method("submit_content_command") and main.has_method("open_content_management"), "actual Main exposes native content management")
	if not main.has_method("content_manager"):
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var manager: RefCounted = main.content_manager()
	suite.assert_true(manager != null, "Main configures the actual retained data-only manager")
	if manager == null:
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var base_profile: RefCounted = GameState.profile_runtime_service()
	suite.assert_true(base_profile.snapshot().active_launch_receipt.is_empty(), "management starts from an idle actual Profile")
	var base_bytes := FileAccess.get_file_as_string(_primary("base")) if FileAccess.file_exists(_primary("base")) else ""
	var source := _write_pack(suite)
	suite.assert_true(main.open_content_management().ok, "Hub opens its actual management panel")
	var panel: Control = main.get_node("ContentManagementLayer/ContentManagementPanel")
	suite.assert_true(panel.visible and panel.action_controls().size() >= 2, "native management renders real commands and focus")
	var installed: Dictionary = main.submit_content_command("install", {"path": source}, int(panel.view_state().revision))
	suite.assert_true(installed.ok and manager.discovery().installed.size() == 1, "actual Main installs validated package bytes")
	var epoch := int(panel.view_state().revision)
	suite.assert_true(not main.submit_content_command("set_enabled", {"ids": ["native_local"]}, epoch - 1).ok, "stale panel cannot activate a package")
	get_tree().current_scene = main
	var selection_before: Dictionary = manager.activation_context()
	manager.set_selection_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	var refused: Dictionary = main.submit_content_command("set_enabled", {"ids": ["native_local"]}, epoch)
	suite.assert_true(not refused.ok and panel.error_label.visible, "physical selection failure renders a native retry")
	suite.assert_equal(manager.activation_context(), selection_before, "failed native selection preserves the actual assembly")
	suite.assert_equal(get_tree().current_scene, main, "failed selection cannot reload the live Main")
	suite.assert_equal(FileAccess.get_file_as_string(_primary("base")), base_bytes, "failed local activation preserves valuable physical Base bytes")
	manager.set_selection_fault_injector(Callable())
	epoch = int(panel.view_state().revision)
	var enabled: Dictionary = main.submit_content_command("set_enabled", {"ids": ["native_local"]}, epoch)
	suite.assert_true(enabled.ok, "actual Main commits selection then reloads: " + str(enabled))
	for _index: int in range(6):
		await get_tree().process_frame
	main = get_tree().current_scene
	suite.assert_true(is_instance_valid(main) and main.scene_file_path == "res://scenes/main.tscn", "real scene reload reconstructs the production Main")
	if not is_instance_valid(main) or not main.has_method("content_manager"):
		get_tree().current_scene = self
		suite.finish(get_tree())
		return
	manager = main.content_manager()
	var activation: Dictionary = manager.activation_context()
	var domain := str(activation.save_domain)
	suite.assert_true(domain.begins_with("mod_") and not activation.verified_play_eligible, "native local gameplay uses isolated unranked domain")
	var host: Node = main.get_node("RunRuntimeHost")
	suite.assert_equal(Snapshot.snapshot(host.content_registry()), activation.content_snapshot, "real Host Registry consumes the exact selected installed bytes")
	suite.assert_true(not host.content_registry().get_content(&"native_local_item").is_empty(), "actual assembly exposes optional content")
	suite.assert_equal(GameState.active_profile_domain(), domain, "canonical Profile is bound to selected native domain")
	suite.assert_equal(FileAccess.get_file_as_string(_primary("base")) if FileAccess.file_exists(_primary("base")) else "", base_bytes, "enabling local content preserves physical Base bytes")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261011}
	var launched: bool = main._launch_run(config, false, true)
	suite.assert_true(launched, "actual local Profile starts a production run; profile error=" + str(main.get("_profile_error")) + "; launch=" + str(main.get("_last_launch_rejection")))
	if not launched:
		get_tree().current_scene = self
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_equal(host.runtime_snapshot().config.get("milestone"), "EXPANSION", "selected local content enters the actual Expansion reward path")
	suite.assert_true(FileAccess.file_exists(_primary(domain)), "native launch checkpoint persists in its actual isolated domain")
	var before: Dictionary = manager.activation_context()
	suite.assert_true(not manager.set_enabled([]).ok and not manager.uninstall("native_local").ok and not manager.install(source).ok, "real active native run locks every package mutation")
	suite.assert_equal(manager.activation_context(), before, "active run preserves selected assembly")
	host.set_process(false)
	main.get_node("CombatRoom01/Player").set_physics_process(false)
	suite.assert_true(main.checkpoint_current_run().ok, "isolated native checkpoint uses the selected actual catalog")
	var saved_run: Dictionary = host.runtime_snapshot()
	var saved_profile: Dictionary = GameState.profile_runtime_service().snapshot()
	var selected_catalog: RefCounted = host.native_checkpoint_participants().facade.active_meta_catalog()
	suite.assert_true(Envelope.validate_active_run_snapshot(saved_run, selected_catalog).ok, "selected native Run obeys the actual durable catalog contract")
	suite.assert_true(not Envelope.validate_active_run_snapshot(saved_run, Factory.load_base().context.catalog).ok, "Base catalog cannot authenticate a selected local Run")
	var clone := Run.new()
	clone.reset_domain(saved_run.config, saved_run.run_id)
	var floor: Dictionary = host.native_checkpoint_participants().facade.native_run_state().floor_transaction_snapshot()
	suite.assert_true(not clone.restore_launch_run_snapshot(saved_run, floor.floor_definition, floor.room_templates, Factory.load_base().context.catalog), "cold local domain rejects the wrong explicit catalog")
	suite.assert_true(clone.restore_launch_run_snapshot(saved_run, floor.floor_definition, floor.room_templates, selected_catalog), "cold local domain accepts its exact selected catalog")
	suite.assert_true(not clone.restore_launch_run_snapshot(saved_run, floor.floor_definition, floor.room_templates, Factory.load_base().context.catalog) and clone.snapshot() == saved_run, "wrong restore preserves the already bound domain and content authority")
	suite.assert_true(clone.restore_launch_run_snapshot(saved_run, floor.floor_definition, floor.room_templates), "refused content authority cannot replace the retained per-Run catalog")
	suite.assert_equal(get_tree().reload_current_scene(), OK, "active local package survives a real cold Main restart")
	for _index: int in range(6):
		await get_tree().process_frame
	main = get_tree().current_scene
	manager = main.content_manager()
	suite.assert_equal(manager.activation_context(), before, "cold Main retains exact package selection and domain")
	suite.assert_true(not manager.set_enabled([]).ok, "cold active receipt keeps package mutation locked before resume")
	var resumed: bool = main._launch_run(config, false, true)
	suite.assert_true(resumed, "selected local native launch cold-restores: " + str(main.get("_last_launch_rejection")))
	if not resumed:
		get_tree().current_scene = self
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	host = main.get_node("RunRuntimeHost")
	suite.assert_true(Checkpoint.json_equal(host.runtime_snapshot(), saved_run), "selected catalog cold restore preserves the canonical Run")
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), saved_profile, "cold local resume cannot spend another launch or change Profile")
	var profile: RefCounted = GameState.profile_runtime_service()
	var room: Node = main.get_node("CombatRoom01")
	var routes: Array = host.route_choices()
	suite.assert_true(not routes.is_empty(), "actual local entrance offers an authored route")
	if not routes.is_empty():
		var selected = host.select_route(StringName(routes[0].edge_id), int(host.runtime_snapshot().revision))
		suite.assert_true(selected.ok, "local native route installs its actual room: " + str(selected.context))
		main.get_node("DungeonFlow").refresh(true)
	for _index: int in range(4):
		await get_tree().physics_frame
		await get_tree().process_frame
	suite.assert_true(host.runtime_snapshot().run_time_ms > 0, "local native gameplay advances authoritative time")
	room.get_node("Player").health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	var returned: bool = profile.snapshot().active_launch_receipt.is_empty() and main.return_to_hub()
	suite.assert_true(returned, "real terminal settles isolated Profile and returns to Hub: " + str(main.retry_terminal_settlement()))
	var opened: Dictionary = main.open_content_management()
	suite.assert_true(opened.ok, "settled native Hub can reopen management: " + str(opened))
	if not returned or not opened.ok:
		get_tree().current_scene = self
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	panel = main.get_node("ContentManagementLayer/ContentManagementPanel")
	var restored: Dictionary = main.submit_content_command("set_enabled", {"ids": []}, int(panel.view_state().revision))
	suite.assert_true(restored.ok, "native Hub returns to the retained Base selection")
	for _index: int in range(6):
		await get_tree().process_frame
	main = get_tree().current_scene
	suite.assert_equal(GameState.active_profile_domain(), "base", "actual scene reload returns canonical Base Profile")
	suite.assert_equal(FileAccess.get_file_as_string(_primary("base")) if FileAccess.file_exists(_primary("base")) else "", base_bytes, "local run and return preserve original Base bytes")
	suite.assert_equal(GameState.profile_runtime_service().snapshot().statistics.finished_runs, 2, "local settlement preserves existing Base statistics")
	suite.assert_equal(GameState.profile_runtime_service().snapshot().chronos_shards, 73, "local settlement preserves existing Base currency")
	suite.assert_true(FileAccess.file_exists(_primary(domain)), "disabling local content retains its isolated save")
	get_tree().current_scene = self
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _primary(domain: String) -> String:
	return GameState.save_path.get_base_dir().path_join("plane_walker/save/profiles/slot_1").path_join(domain).path_join("primary.json")


func _seed_base_profile(suite) -> void:
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "valued Base fixture validates its actual content")
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var profile := Profile.new()
	suite.assert_true(profile.configure(catalog), "valued Base fixture configures canonical Profile")
	var value: Dictionary = profile.snapshot()
	value.chronos_shards = 73
	value.statistics.finished_runs = 2
	value.statistics.deaths = 2
	var save := Save.new()
	suite.assert_true(save.configure(GameState.save_path.get_base_dir().path_join("plane_walker/save"), "0.4.0-dev", Snapshot.snapshot(registry)).ok, "valued Base uses production save service")
	suite.assert_true(save.enable_meta_profile(catalog).ok, "valued Base uses actual Meta catalog")
	suite.assert_true(save.save_profile("slot_1", "base", {"meta_profile_state": value, "chronos_shards": 73, "sentinel": {"preserved": ["original", 73]}}).ok, "valued Base physically persists before native activation")


func _write_pack(suite) -> String:
	var path := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("native-content-source")
	var entries := [{"id": "native_local_item", "category": "item", "availability": ["EXPANSION"], "name_key": "NATIVE_LOCAL_ITEM_NAME", "description_key": "NATIVE_LOCAL_ITEM_DESC", "tags": ["time"], "compatibility": {}, "effects": {"attack_multiplier": 1.05}, "kind": "weapon", "archetype": "freeze_burst", "role": "starter", "rarity": "common", "icon_id": "native_local"}]
	_write(path.path_join("content/items.json"), JSON.stringify(entries), suite)
	_write(path.path_join("localization/strings.csv"), "keys,en,zh_CN\nNATIVE_LOCAL_ITEM_NAME,Local prism,Local prism\nNATIVE_LOCAL_ITEM_DESC,Attack rises,Attack rises\n", suite)
	var descriptor := {"pack_id": "native_local", "pack_version": "1.0.0", "schema_version": 2, "game_version_range": ">=0.4.0 <1.0.0", "dependencies": [], "load_order": 100, "content_manifest": ["content/items.json"], "localization_sources": ["localization/strings.csv"], "asset_manifest": [], "integrity_hashes": {"content/items.json": FileAccess.get_sha256(path.path_join("content/items.json")), "localization/strings.csv": FileAccess.get_sha256(path.path_join("localization/strings.csv"))}, "entitlement_tag": ""}
	_write(path.path_join("pack.json"), JSON.stringify(descriptor), suite)
	return path


func _write(path: String, value: String, suite) -> void:
	suite.assert_equal(DirAccess.make_dir_recursive_absolute(path.get_base_dir()), OK, "native package source parent exists")
	var file := FileAccess.open(path, FileAccess.WRITE)
	suite.assert_true(file != null, "native package bytes open")
	if file != null:
		file.store_string(value)
		file.close()
