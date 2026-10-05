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
const Rules := preload("res://scripts/community/local_run_record_rules.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := Paths.resolve_default("user://p25-rush-carried", "p25-rush-carried")
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var save := Save.new()
	save.configure(root.path_join("profiles"), "0.4.0-dev", Content.snapshot(registry))
	var service := Service.new()
	var initial: Dictionary = Fixtures.profile(catalog)
	service.configure(catalog, save, "carried_owner", "base", {"meta_profile_state": initial})
	var flow: Node2D = Flow.new()
	add_child(flow)
	if not flow.has_method("choose_reward"):
		suite.assert_true(false, "continuous Boss Rush exposes real reward choices")
		flow.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_true(flow.configure(registry, service, root.path_join("locked"), true).ok, "carried flow configures")
	var request := {"character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "seed": 674, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}
	suite.assert_true(not flow.start(request).ok, "first normal victory is required")
	flow.queue_free()
	await get_tree().process_frame
	initial.statistics.finished_runs = 1
	initial.statistics.victories = 1
	service.configure(catalog, save, "carried_owner", "base", {"meta_profile_state": initial})
	var before := service.snapshot()
	flow = Flow.new()
	add_child(flow)
	suite.assert_true(flow.configure(registry, service, root.path_join("modes"), true).ok and flow.start(request).ok, "unlocked carried flow starts native arena")
	if flow.current_player() == null:
		flow.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_true(flow.current_player().health.max_hp == 100.0 and flow.snapshot().carried.gold == 100, "initial carried baseline is HP100 and gold100")
	suite.assert_true(flow.current_boss().health.max_hp == 960.0, "native first Boss gets HP1.2")
	var observation_before: Dictionary = flow.snapshot()
	flow.current_player().authoritative_frame_committed.emit(999999)
	flow.current_player().health.damaged.emit(10.0, 90.0)
	suite.assert_equal(flow.snapshot(), observation_before, "forged frame and HP notifications cannot advance carried challenge facts")
	for index: int in range(5):
		var player: Node = flow.current_player()
		var boss: Node = flow.current_boss()
		for _frame: int in range(3):
			await get_tree().physics_frame
		if not is_instance_valid(player) or not is_instance_valid(boss):
			suite.assert_true(false, "native carried stage remains valid at index %d: %s" % [index, str(flow.snapshot())])
			break
		if index == 0:
			player.health.lose_health(60, boss)
		boss.health.lose_health(100000, player)
		await get_tree().process_frame
		await get_tree().process_frame
		suite.assert_equal(flow.snapshot().completed_stages.size(), index + 1, "real native Boss terminal enters continuous aggregate")
		if index < 4:
			suite.assert_true(flow.snapshot().carried.choices.size() == 3 and not flow.next_stage().ok, "choice is required before next native Boss: " + str(flow.snapshot().status) + " " + str(flow.snapshot().carried.choices) + " pending=" + str(flow.has_pending_save()))
			var hp := float(flow.snapshot().carried.portable.health.current_hp)
			if index == 0:
				suite.assert_true(is_equal_approx(hp, 70.0), "30 percent native victory heal retains HP loss")
				var chosen: Dictionary = flow.choose_reward(0)
				suite.assert_true(chosen.ok and flow.current_player().health.current_hp <= 100.0 and flow.snapshot().carried.blessing_ids.size() == 1, "blessing and HP persist into next actual Player: " + str(chosen))
			elif index == 1:
				suite.assert_true(flow.choose_reward(1).ok and flow.snapshot().carried.item_ids.size() == 1, "rare/legendary item applies to carried native Player")
			else:
				suite.assert_true(flow.choose_reward(2).ok and flow.current_player().health.current_hp == flow.current_player().health.max_hp, "restore choice fills native HP and time")
		if not suite.failures.is_empty():
			flow.queue_free()
			await get_tree().process_frame
			suite.finish(get_tree())
			return
	suite.assert_true(flow.snapshot().status == "VICTORY" and flow.snapshot().carried.history.size() == 1 and flow.snapshot().carried.reward_ids.has("walker_proof") and not flow.snapshot().carried.reward_ids.has("void_walker"), "victory history and first-clear rewards derive from native terminal and damage")
	suite.assert_equal(service.snapshot(), before, "continuous challenge never creates ordinary run settlement")
	var settled: Dictionary = flow.snapshot()
	flow.queue_free()
	await get_tree().process_frame
	flow = Flow.new()
	add_child(flow)
	suite.assert_true(flow.configure(registry, service, root.path_join("modes"), true).ok and flow.snapshot().carried.history.size() == 1, "physical cold restart retains history and reward ownership")
	suite.assert_true(flow.start(request).ok, "a new continuous session retains reward history")
	var player: Node = flow.current_player()
	player.health.lose_health(20, flow.current_boss())
	suite.assert_true(flow.save_and_return().ok, "active carried HP is saved before returning")
	flow.queue_free()
	await get_tree().process_frame
	flow = Flow.new()
	add_child(flow)
	suite.assert_true(flow.configure(registry, service, root.path_join("modes"), true).ok and flow.continue_session().ok and is_equal_approx(flow.current_player().health.current_hp, 80.0), "cold active continuation restores HP instead of refreshing it")
	suite.assert_true(flow.snapshot().continued and Rules.same(flow.snapshot().carried.history, settled.carried.history), "continued status retains exact prior history")
	flow.current_player().health.lose_health(10, flow.current_boss())
	flow.set_fault_injector(func(at: StringName): return at == &"before_primary_promote")
	var failed: Dictionary = flow.save_and_return()
	suite.assert_true(not failed.ok and flow.has_pending_save() and flow.is_active(), "carried HP save failure freezes and keeps retry candidate")
	flow.set_fault_injector(Callable())
	suite.assert_true(flow.retry_save().ok and not flow.is_active(), "carried save retry promotes once then returns")
	flow.queue_free()
	await get_tree().process_frame
	flow = Flow.new()
	add_child(flow)
	suite.assert_true(flow.configure(registry, service, root.path_join("modes"), true).ok and flow.continue_session().ok and flow.current_player().health.current_hp == 70.0, "cold carried retry retains actual damaged HP")
	var stale: Node2D = Flow.new()
	add_child(stale)
	suite.assert_true(stale.configure(registry, service, root.path_join("modes"), true).ok, "stale carried writer observes current physical session")
	flow.current_player().health.lose_health(10, flow.current_boss())
	flow.set_fault_injector(func(at: StringName): return at == &"after_primary_promote")
	suite.assert_true(flow.save_and_return().ok and not flow.has_pending_save(), "carried exact promoted primary reconciles reported save failure")
	var conflicted: Dictionary = stale.continue_session()
	suite.assert_true(not conflicted.ok and conflicted.code == &"CHALLENGE_STALE_PRIMARY", "stale carried writer cannot replace promoted HP")
	suite.assert_true(stale.reload_saved_session().ok and stale.snapshot().carried.portable.health.current_hp == 60.0, "stale carried recovery reloads winning HP")
	stale.queue_free()
	flow.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
