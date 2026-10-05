extends "res://tests/integration/save/boss_rush_checkpoint_test.gd"

const DailySource := "res://scripts/modes/native_daily_boss_flow.gd"
var _clock := 1791129600


func _run() -> void:
	_suite = Suite.new()
	if not ResourceLoader.exists(DailySource):
		_suite.assert_true(false, "daily starts an actual fixed-Build Boss and physically spends bounded attempts")
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var fixture := _daily_fixture("native")
	var flow := _daily_flow(fixture)
	var ordinary: Dictionary = fixture.service.snapshot()
	var preview: Dictionary = flow.preview()
	_suite.assert_equal(preview.remaining_attempts, 3, "new daily begins with exactly three durable attempts")
	_suite.assert_true(flow.start().ok, "daily admission saves before actual native construction")
	_suite.assert_equal(flow.preview().remaining_attempts, 2, "actual native admission spends one attempt")
	var player: Node2D = flow.current_player()
	var boss: Node2D = flow.current_boss()
	_suite.assert_true(player != null and boss != null, "daily exposes actual production Player and selected Boss")
	_suite.assert_equal(str(boss.hostile_source_id), "daily-" + str(flow.snapshot().active.run_id).sha256_text().substr(0, 40), "native daily Boss uses authenticated stable source identity")
	_suite.assert_true(player.reward_effect_snapshot() != flow.baseline_player_effects(), "three items blessing curse and rules change actual native effect state")
	_suite.assert_equal(flow.installed_build_receipts().size(), 5 + preview.definition.condition_ids.size(), "daily commits all five authored content effects and actual condition effects")
	boss.hostile_final_death.emit(boss.hostile_source_id, "invented")
	await get_tree().process_frame
	_suite.assert_true(not flow.snapshot().active.is_empty(), "forged daily completion notice cannot create a result")
	player.set_physics_process(false)
	player.global_position = boss.global_position + Vector2(42, 0)
	await get_tree().physics_frame
	_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}) and player.try_action(&"weapon_primary"), "actual fixed daily weapon begins an authoritative attack")
	for frame: int in range(150):
		if frame == 40:
			player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		_suite.assert_true(player.advance_action_frame({"aim": player.global_position.direction_to(boss.global_position)}), "actual fixed daily Build commits native Boss frames")
		await get_tree().physics_frame
	_suite.assert_true(boss.health.current_hp < boss.health.max_hp, "actual fixed daily weapon damages bound Boss through physical collision")
	boss.health.lose_health(100000, player)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.snapshot().active.is_empty() and flow.preview().best.status == "VICTORY", "real daily death receipt commits durable victory and best result")
	_suite.assert_equal(fixture.service.snapshot(), ordinary, "daily never settles ordinary Meta or ranking source state")
	await _daily_dispose(flow)
	flow = _daily_flow(fixture)
	_suite.assert_equal(flow.preview().remaining_attempts, 2, "fresh physical reload retains daily victory and spent attempt")
	_suite.assert_true(flow.start().ok, "second actual native daily attempt starts")
	await _frames(3)
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_equal(flow.preview().results[-1].status, "DEFEAT", "actual Player death records a daily defeat")
	_suite.assert_equal(flow.preview().best.status, "VICTORY", "defeat cannot replace the real daily victory")
	_suite.assert_true(flow.start().ok and flow.abandon().ok, "third admitted attempt may be explicitly abandoned")
	_suite.assert_equal(flow.preview().results.size(), 3, "three admissions yield exactly three terminal records")
	_suite.assert_true(not flow.start().ok and flow.preview().remaining_attempts == 0, "fourth daily admission is refused")
	await _daily_dispose(flow)
	flow = _daily_flow(fixture)
	_suite.assert_true(not flow.start().ok, "physical cold reload cannot reset the exhausted daily attempt limit")
	_clock += 86400
	_suite.assert_equal(flow.preview().remaining_attempts, 3, "next UTC+8 day receives exactly three new attempts")
	_suite.assert_true(flow.start().ok and flow.abandon().ok, "rollover executes an actual next-day challenge")
	_clock -= 86400
	_suite.assert_true(not flow.start().ok and flow.preview().reason == "DAILY_CLOCK_ROLLBACK", "clock rollback cannot restore old daily attempts")
	await _daily_dispose(flow)
	_suite.finish(get_tree())


func _daily_fixture(case_id: String, advanced: bool = true, domain: String = "base", victory: bool = true) -> Dictionary:
	var root := Paths.resolve_default("user://p21b-daily/" + case_id, "p21b-daily/" + case_id)
	var storage := Save.new()
	storage.configure(root.path_join("profiles"), "test-p21b", Content.snapshot(_registry))
	var catalog: RefCounted = Factory.from_registry(_registry).context.catalog
	var profile: Dictionary = Fixtures.profile(catalog)
	if not advanced:
		var fresh := preload("res://scripts/progression/meta_profile_state.gd").new()
		fresh.configure(catalog)
		profile = fresh.snapshot()
	if victory:
		profile.statistics.finished_runs = 1
		profile.statistics.victories = 1
		profile.completed_boss_ids = ["void_throne"]
	var service := Service.new()
	_suite.assert_true(service.configure(catalog, storage, "daily_owner", domain, {"meta_profile_state": profile}).ok, "real Profile daily fixture is valid")
	return {"root": root, "service": service, "storage": storage}


func _daily_flow(fixture: Dictionary) -> Node2D:
	var value: Node2D = load(DailySource).new()
	add_child(value)
	_suite.assert_true(value.configure(_registry, fixture.service, fixture.root.path_join("daily"), func(): return _clock).ok, "daily flow binds actual Profile content identity and independent storage")
	return value


func _daily_dispose(value: Node) -> void:
	value.close()
	value.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _seed_main_profile(case_id: String) -> void:
	var root := Paths.resolve_default("user://p21b-main/" + case_id, "p21b-main/" + case_id)
	GameState.save_path = root.path_join("persistent.json")
	GameState.set("_profile_runtime", null)
	var catalog: RefCounted = Factory.from_registry(_registry).context.catalog
	var profile: Dictionary = Fixtures.profile(catalog)
	profile.statistics.finished_runs = 1
	profile.statistics.victories = 1
	profile.completed_boss_ids = ["void_throne"]
	var storage := Save.new()
	_suite.assert_true(storage.configure(GameState.call("_save_service_root_path"), GameState.SAVE_GAME_VERSION, Content.snapshot(_registry)).ok and storage.enable_meta_profile(catalog).ok, "actual Main Profile storage uses production schema and content")
	_suite.assert_true(storage.save_profile(GameState.DEFAULT_PROFILE_ID, "base", {"meta_profile_state": profile}).ok, "actual Main test seeds a valid earned-victory Profile physically")
