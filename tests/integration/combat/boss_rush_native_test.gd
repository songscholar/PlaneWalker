extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists("res://scripts/modes/native_boss_rush_flow.gd"), "Boss Rush requires a real native stage flow")
	if not ResourceLoader.exists("res://scripts/modes/native_boss_rush_flow.gd"):
		suite.finish(get_tree())
		return
	var flow_script: Script = load("res://scripts/modes/native_boss_rush_flow.gd")
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := Paths.resolve_default("user://p21a-boss-rush", "p21a-boss-rush")
	var storage := Save.new()
	storage.configure(root.path_join("profiles"), "test-p21a", Content.snapshot(registry))
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var service := Service.new()
	service.configure(catalog, storage, "rush_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	var profile_before := service.snapshot()
	var flow: Node2D = flow_script.new()
	add_child(flow)
	var configured: Dictionary = flow.configure(registry, service, root.path_join("modes"))
	suite.assert_true(configured.ok, "Boss Rush binds actual content/Profile and independent physical save: " + str(configured))
	if not configured.ok:
		flow.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var request := {"character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "seed": 20261005, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}
	var launched: Dictionary = flow.start(request)
	suite.assert_true(launched.ok, "Boss Rush persists launch before real native play: " + str(launched))
	if not launched.ok:
		flow.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	for index: int in range(5):
		var boss: Node = flow.current_boss()
		var player: Node = flow.current_player()
		suite.assert_true(boss != null and player != null and boss.target == player and player.get("_hostile_frame_participant") != null, "each actual Boss shares the player's authoritative combat transaction")
		if boss == null or player == null:
			break
		var before: Dictionary = flow.snapshot()
		boss.hostile_final_death.emit(boss.hostile_source_id, "forged-notice")
		await get_tree().process_frame
		suite.assert_equal(flow.snapshot().completed_stages, before.completed_stages, "forged Boss death notification cannot advance a live native stage")
		for _frame: int in range(3):
			await get_tree().physics_frame
		boss.health.lose_health(100000, player)
		await get_tree().process_frame
		await get_tree().process_frame
		suite.assert_equal(flow.snapshot().completed_stages.size(), index + 1, "native Boss terminal receipt enters the durable aggregate exactly once")
		if index < 4:
			suite.assert_true(flow.next_stage().ok, "saved stage permits actual next authored Boss")
	suite.assert_true(flow.snapshot().status == "VICTORY" and flow.snapshot().elapsed_frames > 0, "all five actual Bosses produce a physical timed victory")
	suite.assert_equal(service.snapshot(), profile_before, "Boss Rush never creates ordinary currency/progression settlements")
	flow.close()
	flow.queue_free()
	await get_tree().process_frame
	flow = flow_script.new()
	add_child(flow)
	suite.assert_true(flow.configure(registry, service, root.path_join("modes")).ok and flow.snapshot().status == "VICTORY", "fresh native flow reloads physical challenge summary")
	flow.close()
	flow.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
