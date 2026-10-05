extends "res://tests/integration/combat/daily_boss_native_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	await _daily_faults()
	await _daily_crash()
	await _daily_stale()
	await _daily_interleaved_identical()
	await _daily_midnight()
	await _daily_archive()
	await _daily_fractional_victory()
	_suite.finish(get_tree())


func _daily_faults() -> void:
	for point: StringName in [&"before_primary_promote", &"after_primary_promote"]:
		var fixture := _daily_fixture("fault-" + str(point))
		var flow := _daily_flow(fixture)
		flow.set_fault_injector(func(at: StringName): return at == point)
		var started: Dictionary = flow.start()
		if point == &"before_primary_promote":
			_suite.assert_true(not started.ok and flow.has_pending_save() and flow.snapshot().active.is_empty() and flow.preview().remaining_attempts == 3 and not flow.is_active(), "failed daily admission does not publish/spend an attempt or native arena")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok and flow.preview().remaining_attempts == 2 and flow.is_active(), "daily admission retry physically spends once before native play")
		else:
			_suite.assert_true(started.ok and flow.is_active() and flow.preview().remaining_attempts == 2, "daily post-promotion admission accepts only the actual physical candidate")
		flow.set_fault_injector(func(at: StringName): return at == point)
		await _frames(3)
		flow.current_boss().health.lose_health(100000, flow.current_player())
		await get_tree().process_frame
		await get_tree().process_frame
		if point == &"before_primary_promote":
			_suite.assert_true(flow.has_pending_save() and not flow.snapshot().active.is_empty() and flow.preview().results.is_empty(), "failed native daily terminal keeps one pending authentic result")
			var frozen: Dictionary = flow.snapshot()
			await _frames(3)
			_suite.assert_equal(flow.snapshot(), frozen, "failed daily terminal freezes native timing during retry")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok, "daily terminal retry persists actual native victory")
		_suite.assert_true(flow.snapshot().active.is_empty() and flow.preview().results.size() == 1 and flow.preview().remaining_attempts == 2 and not flow.retry_save().ok, "daily settlement physically retains one result and cannot duplicate attempts")
		await _daily_dispose(flow)
		flow = _daily_flow(fixture)
		_suite.assert_true(flow.preview().results.size() == 1 and flow.preview().best.status == "VICTORY", "actual physical daily reload retains fault-recovered native result")
		await _daily_dispose(flow)


func _daily_crash() -> void:
	var fixture := _daily_fixture("crash")
	var flow := _daily_flow(fixture)
	_suite.assert_true(flow.start().ok, "daily crash fixture admits one actual attempt")
	var admitted: Dictionary = flow.snapshot()
	await _frames(3)
	await _daily_dispose(flow)
	flow = _daily_flow(fixture)
	_suite.assert_equal(flow.snapshot(), admitted, "cold admitted daily state normalizes physical JSON numbers including the fixed Build")
	_suite.assert_true(not flow.preview().active.is_empty() and not flow.is_active() and not flow.start().ok and not flow.retry_native().ok, "crash reload retains spent attempt without unlimited entrance retries")
	_suite.assert_true(flow.abandon().ok and flow.preview().remaining_attempts == 2 and flow.preview().results[0].status == "ABANDON", "explicit cold abandonment resolves the admitted attempt once")
	_suite.assert_true(flow.start().ok and flow.abandon().ok, "resolved crash permits exactly the next daily attempt")
	await _daily_dispose(flow)


func _daily_fractional_victory() -> void:
	var fixture := _daily_fixture("fractional-victory")
	var flow := _daily_flow(fixture)
	_suite.assert_true(flow.start().ok, "fractional-health daily victory fixture admits one actual attempt")
	await _frames(3)
	var player: Node2D = flow.current_player()
	player.set_physics_process(false)
	player.health.lose_health(player.health.current_hp - 0.0001)
	_suite.assert_true(not player.health.dead and player.health.current_hp > 0, "actual positive fractional Player health remains alive")
	flow.current_boss().health.lose_health(100000, player)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.snapshot().active.is_empty() and flow.preview().best.get("status") == "VICTORY" and flow.preview().best.get("remaining_hp_milli") == 1, "actual low-health daily victory stores the minimum positive ranking unit")
	await _daily_dispose(flow)


func _daily_stale() -> void:
	var fixture := _daily_fixture("stale")
	var first := _daily_flow(fixture)
	var stale := _daily_flow(fixture)
	_suite.assert_true(first.start().ok, "first daily writer admits the actual attempt")
	var rejected: Dictionary = stale.start()
	_suite.assert_true(not rejected.ok and rejected.code == &"DAILY_STALE_PRIMARY" and not stale.is_active(), "separately loaded stale daily writer cannot replay the admission")
	_suite.assert_true(stale.reload_saved_session().ok and stale.preview().remaining_attempts == 2, "physical daily reload discards stale command and retains spent count")
	_suite.assert_true(stale.abandon().ok, "latest cold writer may explicitly abandon the actual admitted attempt")
	_suite.assert_true(not first.abandon().ok and first.has_pending_save(), "old native daily writer cannot overwrite the resolved physical attempt")
	_suite.assert_true(first.reload_saved_session().ok and first.preview().results.size() == 1, "old native writer recovers the actual physical terminal result")
	await _daily_dispose(first)
	await _daily_dispose(stale)


func _daily_interleaved_identical() -> void:
	var fixture := _daily_fixture("identical-interleaved")
	var first := _daily_flow(fixture)
	var winner := _daily_flow(fixture)
	var race := {"injected": false, "competing": {}}
	first.set_fault_injector(func(point: StringName):
		if point == &"before_primary_promote" and not race.injected:
			race.injected = true
			race.competing = winner.start()
		return false)
	var lost: Dictionary = first.start()
	_suite.assert_true(race.competing.get("ok", false) and winner.is_active(), "interleaved identical daily candidate has one physical admission winner")
	_suite.assert_true(not lost.ok and lost.code == &"DAILY_STALE_PRIMARY" and not first.is_active(), "lost CAS cannot create a second native arena even when candidate bytes are identical")
	first.set_fault_injector(Callable())
	_suite.assert_true(winner.abandon().ok and first.reload_saved_session().ok, "identical admission race recovers one actual consumed attempt")
	_suite.assert_equal(first.preview().results.size(), 1, "identical race retains exactly one terminal record")
	await _daily_dispose(first)
	await _daily_dispose(winner)


func _daily_midnight() -> void:
	var fixture := _daily_fixture("midnight")
	var flow := _daily_flow(fixture)
	_suite.assert_true(flow.start().ok, "daily midnight fixture admits original day")
	var original: Dictionary = flow.snapshot().active
	_clock += 86400
	_suite.assert_true(not flow.start().ok and flow.snapshot().active.definition == original.definition, "midnight cannot replace a currently admitted fixed Build")
	_suite.assert_true(flow.abandon().ok and flow.preview().remaining_attempts == 3, "old-day abandon consumes its original attempt and preserves all next-day attempts")
	_suite.assert_true(flow.start().ok and flow.abandon().ok, "next-day challenge follows the actual old-day terminal boundary")
	var saved: Dictionary = flow.snapshot()
	_suite.assert_true(saved.days.size() == 2 and saved.days[0].attempts == 1 and saved.days[1].attempts == 1, "physical daily aggregate separates UTC+8 days and their attempts")
	await _daily_dispose(flow)
	_clock -= 86400


func _daily_archive() -> void:
	var fixture := _daily_fixture("archive")
	var flow := _daily_flow(fixture)
	var origin := _clock
	for offset: int in range(35):
		_clock = origin + offset * 86400
		_suite.assert_true(flow.start().ok and flow.abandon().ok, "each archived daily admits and retires one real native attempt")
		await get_tree().process_frame
	var saved: Dictionary = flow.snapshot()
	_suite.assert_equal(saved.days.size(), 31, "daily physical archive retains its bounded last thirty-one days")
	_suite.assert_equal(saved.days[0].day_index, preload("res://scripts/modes/daily_boss_catalog.gd").day_index(origin) + 4, "daily overflow retires the oldest completed days only")
	await _daily_dispose(flow)
	flow = _daily_flow(fixture)
	_suite.assert_equal(flow.snapshot(), saved, "fresh physical daily reload preserves the full bounded archive")
	_clock = origin
	_suite.assert_true(not flow.start().ok, "archived older day cannot reopen extra attempts after local clock rollback")
	await _daily_dispose(flow)
