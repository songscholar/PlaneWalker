extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Flow := preload("res://scripts/modes/native_boss_rush_flow.gd")
const Catalog := preload("res://scripts/progression/challenge_reward_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const DailyFlow := preload("res://scripts/modes/native_daily_boss_flow.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := Paths.resolve_default("user://p25-mode-rewards", "p25-mode-rewards")
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var save := Save.new()
	save.configure(root.path_join("profiles"), "0.4.0-dev", Content.snapshot(registry))
	var service: RefCounted = Service.new()
	var initial := Fixtures.profile(catalog)
	initial.statistics.finished_runs = 1
	initial.statistics.victories = 1
	initial.completed_boss_ids = ["void_throne"]
	service.configure(catalog, save, "reward_owner", "base", {"meta_profile_state": initial})
	if not service.has_method("configure_mode_rewards"):
		suite.assert_true(false, "Profile requires authenticated physical mode reward authority")
		suite.finish(get_tree())
		return
	var flow: Node2D = Flow.new()
	add_child(flow)
	suite.assert_true(flow.configure(registry, service, root.path_join("modes"), true).ok and service.configure_mode_rewards(registry, [flow]).ok, "actual Profile binds actual mode source")
	var claimed: Dictionary = service.claim_mode_rewards("boss_rush_carried", int(service.snapshot().revision))
	suite.assert_true(not claimed.ok, "absent promoted mode primary cannot grant rewards")
	var request := {"character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "seed": 851, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}
	suite.assert_true(flow.start(request).ok, "reward proof starts actual native challenge")
	for index: int in range(5):
		for _frame: int in range(3):
			await get_tree().physics_frame
		flow.current_boss().health.lose_health(100000, flow.current_player())
		await get_tree().process_frame
		await get_tree().process_frame
		if index < 4:
			suite.assert_true(flow.choose_reward(2).ok, "native interstage restore permits reward proof")
	var before: Dictionary = service.snapshot()
	suite.assert_true(not service.claim_mode_rewards("boss_rush_carried", int(before.revision) + 1).ok, "stale UI revision refuses mode claim")
	var result: Dictionary = service.claim_mode_rewards("boss_rush_carried", int(before.revision))
	suite.assert_true(result.ok, "native five-stage physical aggregate authorizes first clear and flawless rewards: " + str(result))
	var collection: Dictionary = service.challenge_reward_collection()
	suite.assert_true(collection.owned_ids.has("walker_proof") and collection.owned_ids.has("walker_entry") and collection.owned_ids.has("void_walker") and collection.owned_ids.has("speedwalker_boots"), "authenticated reward ownership enters separate durable collection")
	suite.assert_equal(service.snapshot().chronos_shards, before.chronos_shards, "mode entitlements do not silently alter ordinary currency")
	var revision: int = service.snapshot().revision
	suite.assert_true(service.claim_mode_rewards("boss_rush_carried", revision).ok and service.snapshot().revision == revision, "duplicate claim has no write or duplicated grant")
	suite.assert_true(not service.equip_challenge_reward("eternal_walker", true, revision).ok, "unowned equipment refuses")
	suite.assert_true(service.equip_challenge_reward("walker_proof", true, revision).ok, "owned proof is actually selectable equipment")
	suite.assert_true(service.equip_challenge_reward("speedwalker_boots", true, int(service.snapshot().revision)).ok and service.equip_challenge_reward("void_walker", true, int(service.snapshot().revision)).ok, "owned boots and skin equip through durable Profile route")
	var projected: Dictionary = service.challenge_reward_projection()
	var reward_catalog := Catalog.new()
	reward_catalog.configure()
	suite.assert_true(projected.ok and reward_catalog.valid_projection(projected.context.projection) and projected.context.projection.modifiers.boss_damage_multiplier == 1.15 and projected.context.projection.modifiers.dash_speed_multiplier == 1.2, "frozen equip projection has authored modifiers and content binding")
	var bad: Dictionary = projected.context.projection.duplicate(true)
	bad.modifiers.boss_damage_multiplier = 10.0
	suite.assert_true(not reward_catalog.valid_projection(bad), "caller-supplied modifier refuses")
	var cold: RefCounted = Service.new()
	suite.assert_true(cold.configure(catalog, save, "reward_owner", "base").ok and Rules.same(cold.challenge_reward_collection(), service.challenge_reward_collection()), "cold ordinary Profile reloads challenge collection")
	for point: StringName in Save.FAULT_POINTS:
		var fault_save := Save.new()
		fault_save.configure(root.path_join("faults").path_join(str(point)), "0.4.0-dev", Content.snapshot(registry))
		var fault_service: RefCounted = Service.new()
		fault_service.configure(catalog, fault_save, "reward_owner", "base", {"meta_profile_state": initial})
		fault_service.configure_mode_rewards(registry, [flow])
		fault_save.set_fault_injector(func(at: StringName): return at == point)
		var fault_result: Dictionary = fault_service.claim_mode_rewards("boss_rush_carried", int(fault_service.snapshot().revision))
		if point == &"after_primary_promote":
			suite.assert_true(fault_result.ok and fault_service.challenge_reward_collection().owned_ids.has("walker_proof"), "exact promoted reward claim reconciles " + str(point))
		else:
			suite.assert_true(not fault_result.ok and fault_service.challenge_reward_collection().owned_ids.is_empty(), "unpromoted mode reward claim publishes nothing " + str(point))
		fault_save.set_fault_injector(Callable())
		suite.assert_true(fault_service.claim_mode_rewards("boss_rush_carried", int(fault_service.snapshot().revision)).ok and fault_service.challenge_reward_collection().owned_ids.size() == 4, "mode claim fault retry preserves one grant " + str(point))
	var peer: RefCounted = Service.new()
	peer.configure(catalog, save, "reward_owner", "base")
	suite.assert_true(service.equip_challenge_reward("void_walker", false, int(service.snapshot().revision)).ok, "one Profile writer updates actual equipment")
	var stale_equip: Dictionary = peer.equip_challenge_reward("walker_entry", true, int(peer.snapshot().revision))
	suite.assert_true(not stale_equip.ok and stale_equip.code == &"STALE_DURABLE_PROFILE", "stale Profile cannot overwrite newer challenge equipment")
	var clock := {"now": 1600000000}
	var daily: Node2D = DailyFlow.new()
	add_child(daily)
	suite.assert_true(daily.configure(registry, service, root.path_join("daily"), func(): return clock.now).ok and service.configure_mode_rewards(registry, [flow, daily]).ok, "one Profile enrolls both real mode sources")
	for day: int in range(7):
		clock.now = 1600000000 + day * 86400
		var daily_start: Dictionary = daily.start()
		suite.assert_true(daily_start.ok, "actual daily source launches: " + str(daily_start))
		if daily.current_player() == null:
			daily.queue_free()
			flow.queue_free()
			await get_tree().process_frame
			suite.finish(get_tree())
			return
		daily.current_player().set_physics_process(false)
		daily.current_player().advance_action_frame({})
		daily.current_boss().health.lose_health(100000, daily.current_player())
		await get_tree().process_frame
		await get_tree().process_frame
	suite.assert_true(daily.purchase_reward("daily_weapon_skin").ok, "native daily earned tokens buy actual authored shop reward")
	suite.assert_true(service.claim_mode_rewards("daily_boss", int(service.snapshot().revision)).ok and service.challenge_reward_collection().owned_ids.has("daily_participation_frame") and service.challenge_reward_collection().owned_ids.has("daily_walker_frame") and service.challenge_reward_collection().owned_ids.has("daily_weapon_skin"), "physical seven-day native daily aggregate projects earned rewards")
	suite.assert_true(service.equip_challenge_reward("daily_weapon_skin", true, int(service.snapshot().revision)).ok and service.equip_challenge_reward("daily_walker_frame", true, int(service.snapshot().revision)).ok, "daily weapon skin and frame use same durable equip path")
	daily.queue_free()
	var migration_save := Save.new()
	migration_save.configure(root.path_join("migration"), "0.4.0-dev", Content.snapshot(registry))
	migration_save.enable_meta_profile(catalog)
	suite.assert_true(migration_save.save_profile("legacy", "base", {"meta_profile_state": initial}).ok, "pre-reward Profile persists without collection")
	var migrated: RefCounted = Service.new()
	suite.assert_true(migrated.configure(catalog, migration_save, "legacy", "base").ok and migrated.challenge_reward_collection() == reward_catalog.empty_collection(), "old physical Profile migrates to empty separate reward collection")
	var invalid_collection := reward_catalog.empty_collection()
	invalid_collection.owned_ids = ["walker_proof"]
	suite.assert_true(migration_save.save_profile("invalid", "base", {"meta_profile_state": initial, "challenge_reward_collection": invalid_collection}).ok, "corrupt collection fixture reaches physical Profile boundary")
	var invalid: RefCounted = Service.new()
	suite.assert_true(not invalid.configure(catalog, migration_save, "invalid", "base").ok, "physical ownership without source receipt fails closed")
	var forged := Node.new()
	add_child(forged)
	suite.assert_true(not cold.configure_mode_rewards(registry, [forged]).ok, "arbitrary node cannot become a trusted reward source")
	forged.queue_free()
	flow.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
