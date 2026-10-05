extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const REQUEST := {"character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "seed": 20261005, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var path := "res://scripts/modes/native_endless_flow.gd"
	suite.assert_true(ResourceLoader.exists(path), "Endless must execute actual native five-floor dungeon flow")
	if not ResourceLoader.exists(path):
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := Paths.resolve_default("user://p21d-native", "p21d-native")
	var storage := Save.new()
	storage.configure(root.path_join("profiles"), "test-p21d", Content.snapshot(registry))
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var service := Service.new()
	service.configure(catalog, storage, "endless_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	var before := service.snapshot()
	var script: Script = load(path)
	var flow: Node2D = script.new()
	add_child(flow)
	var configured: Dictionary = flow.configure(registry, service, root.path_join("modes"))
	suite.assert_true(configured.ok, "native Endless binds separate physical Profile " + str(configured))
	if not configured.ok:
		flow.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var launched: Dictionary = flow.start(REQUEST)
	suite.assert_true(launched.ok, "native Endless saves launch and initial five-floor state " + str(launched))
	if launched.ok:
		var host: Node = flow.runtime_host()
		var player: Node = flow.current_player()
		host.set_process(false)
		flow.set_process(false)
		flow.dungeon_flow().set_process(false)
		player.set_physics_process(false)
		var selected := false
		for route: Dictionary in host.route_choices():
			if route.room_type in ["combat", "elite"]:
				selected = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok
				break
		suite.assert_true(selected, "Endless enters actual production native combat route")
		host.set_dungeon_selection_safety(false)
		var runner: Node = host.native_checkpoint_participants().controller.encounter_runner()
		for _frame: int in range(100):
			if runner.alive_count() > 0:
				break
			suite.assert_true(player.advance_action_frame(), "native Endless accepted frame")
			await get_tree().physics_frame
		suite.assert_true(runner.alive_count() > 0 and not runner.native_launch_snapshot().is_empty(), "Endless spawns authored native hostiles")
		var native: Dictionary = runner.native_launch_snapshot()
		var driver: Node = runner.get_node("NativeLaunchEncounterDriver")
		var bridge: RefCounted = driver.get("_bridge")
		var ticket: Dictionary = bridge.begin_frame(int(player.priority_arbitration_snapshot().frame) + 1)
		suite.assert_true(not ticket.is_empty() and bridge.rollback_frame(ticket), "native Endless transaction can refuse before publication")
		suite.assert_equal(runner.native_launch_snapshot(), native, "Endless native aggregate remains unchanged on refusal")
		var saved: Dictionary = flow.save_and_return()
		suite.assert_true(saved.ok, "Endless retains actual live combat cold checkpoint " + str(saved))
		await get_tree().process_frame
		await get_tree().process_frame
		flow.queue_free()
		await get_tree().process_frame
		flow = script.new()
		add_child(flow)
		suite.assert_true(flow.configure(registry, service, root.path_join("modes")).ok, "fresh Endless reloads actual private physical state")
		var continued: Dictionary = flow.continue_session()
		suite.assert_true(continued.ok, "fresh Endless reconstructs actual hostile combat " + str(continued))
		if continued.ok:
			suite.assert_true(flow.snapshot().continued and flow.runtime_host().runtime_snapshot().floor_plan.floor_id == "floor_ruins_of_remnant", "native resumed floor and continued category retained")
		suite.assert_equal(service.snapshot(), before, "Endless never awards or changes the source Profile")
	flow.close()
	flow.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
