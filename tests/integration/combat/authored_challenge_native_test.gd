extends "res://tests/integration/combat/daily_boss_native_test.gd"

const AuthoredSource := "res://scripts/modes/native_authored_challenge_flow.gd"


func _run() -> void:
	_suite = Suite.new()
	if not ResourceLoader.exists(AuthoredSource):
		_suite.assert_true(false, "authored trials must admit actual fixed Builds and three authenticated native Boss stages")
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var fixture := _daily_fixture("authored-native")
	var flow := _authored_flow(fixture)
	var ordinary: Dictionary = fixture.service.snapshot()
	var started: Dictionary = flow.start("sword_timer")
	_suite.assert_true(started.ok, "actual authored admission persists before playable native construction: " + str(started))
	if not started.ok:
		await _dispose(flow)
		_suite.finish(get_tree())
		return
	var player: Node = flow.current_player()
	var boss: Node = flow.current_boss()
	_suite.assert_equal(flow.installed_build_receipts().size(), 5, "authored trial commits all fixed items blessing and curse effects")
	_suite.assert_equal(flow.baseline_player_effects().health.max_hp, 100.0, "authored Wanderer starts from standardized 100 HP")
	_suite.assert_equal(str(boss.launch_runtime_snapshot().runtime.identity.run_id), flow.snapshot().active.run_id + "-stage-1", "actual Boss has authored stable stage identity")
	boss.hostile_final_death.emit(boss.hostile_source_id, "invented")
	await get_tree().process_frame
	_suite.assert_true(flow.snapshot().active.stages.is_empty(), "invented Boss notice cannot complete an authored stage")
	player.set_physics_process(false)
	player.global_position = boss.global_position + Vector2(42, 0)
	await get_tree().physics_frame
	_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}) and player.try_action(&"weapon_primary"), "fixed authored weapon uses real authoritative Player actions")
	for frame: int in range(150):
		if frame == 40:
			player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		_suite.assert_true(player.advance_action_frame({"aim": player.global_position.direction_to(boss.global_position)}), "authored arena commits actual Player and hostile frame")
		await get_tree().physics_frame
	_suite.assert_true(boss.health.current_hp < boss.health.max_hp, "actual authored sword damages native Boss through physics: " + str({"boss_hp": boss.health.current_hp, "boss_max": boss.health.max_hp, "player": player.global_position, "boss": boss.global_position, "weapon": player.weapon_action_coordinator.snapshot()}))
	var measured: Dictionary = flow.snapshot()
	var accepted_frame: int = int(player.priority_arbitration_snapshot().frame)
	player.authoritative_frame_committed.emit(accepted_frame)
	player.authoritative_frame_committed.emit(accepted_frame + 1)
	_suite.assert_equal(flow.snapshot(), measured, "duplicate or fabricated frame notices cannot increase authored objective time")
	player.health.damaged.emit(1.0, player.health.current_hp)
	_suite.assert_equal(flow.snapshot().active.damage_events, 0, "forged Health notice without actual loss cannot change objective metrics")
	player.health.healed.emit(0.0, player.health.current_hp + 100.0)
	player.health.damaged.emit(1.0, player.health.current_hp)
	_suite.assert_equal(flow.snapshot().active.damage_events, 0, "forged healing notice cannot manufacture a later authored damage event")
	boss.health.lose_health(100000, player)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_equal(flow.snapshot().active.status, "STAGE_CLEAR", "actual first native Boss terminal persists one stage receipt")
	for _stage: int in range(2):
		_suite.assert_true(flow.next_stage().ok, "saved native stage clear opens the next authored arena")
		await _kill_boss(flow)
	_suite.assert_true(flow.snapshot().active.is_empty() and flow.preview().history.sword_timer[-1].status == "VICTORY", "all three authenticated Bosses and objective produce one durable authored victory")
	_suite.assert_equal(fixture.service.snapshot(), ordinary, "authored victory never settles ordinary Profile or local ranking state")
	await _dispose(flow)
	flow = _authored_flow(fixture)
	_suite.assert_equal(flow.preview().best.sword_timer.status, "VICTORY", "physical fresh reload retains native fresh best")
	_suite.assert_true(flow.start("gauntlets_flawless").ok, "actual no-hit authored trial starts")
	await _frames(3)
	flow.current_player().health.lose_health(1)
	await _kill_boss(flow)
	_suite.assert_true(flow.snapshot().active.is_empty() and flow.preview().history.gauntlets_flawless[-1].status == "OBJECTIVE_FAILED", "authentic Boss death with real Player damage is objective failure rather than victory")
	_suite.assert_true(not flow.preview().best.has("gauntlets_flawless"), "failed no-hit objective grants no fresh best")
	_suite.assert_true(flow.start("bow_precision").ok, "another authored trial remains playable after objective failure")
	await _frames(3)
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_equal(flow.preview().history.bow_precision[-1].status, "DEFEAT", "actual Player terminal death records a distinct authored defeat")
	await _dispose(flow)
	_suite.finish(get_tree())


func _authored_flow(fixture: Dictionary) -> Node2D:
	var flow: Node2D = load(AuthoredSource).new()
	add_child(flow)
	var configured: Dictionary = flow.configure(_registry, fixture.service, fixture.root.path_join("authored"))
	_suite.assert_true(configured.ok, "authored flow uses actual content snapshot and separate physical save: " + str(configured))
	return flow
