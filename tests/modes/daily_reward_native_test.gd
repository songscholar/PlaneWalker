extends "res://tests/integration/combat/daily_boss_native_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var fixture := _daily_fixture("native-rewards")
	var flow := _daily_flow(fixture)
	_suite.assert_true(flow.has_method("purchase_reward"), "daily exchanges own an atomic native reward command")
	if not flow.has_method("purchase_reward"):
		await _daily_dispose(flow)
		_suite.finish(get_tree())
		return
	_suite.assert_true(flow.start().ok, "reward admission constructs actual native daily Boss")
	var player: Node2D = flow.current_player()
	player.set_physics_process(false)
	var before: Dictionary = flow.snapshot()
	player.authoritative_frame_committed.emit(999999)
	_suite.assert_equal(flow.snapshot(), before, "invented frame notice cannot advance native daily clock")
	player.health.damaged.emit(1.0, player.health.current_hp - 1.0)
	_suite.assert_equal(flow.snapshot().active.damage_events, 0, "invented damage signal without physical HP loss refuses")
	player.health.lose_health(10)
	player.health.heal(10)
	_suite.assert_equal(flow.snapshot().active.damage_events, 1, "actual damage remains recorded after full healing")
	player.advance_action_frame({})
	flow.set_fault_injector(func(at: StringName): return at == &"before_primary_promote")
	flow.current_boss().health.lose_health(100000, player)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.has_pending_save() and flow.snapshot().reward_state.tokens == 0, "failed terminal promotion does not expose speculative rewards")
	flow.set_fault_injector(Callable())
	_suite.assert_true(flow.retry_save().ok and flow.snapshot().reward_state.tokens == 1 and flow.snapshot().reward_state.gold == 50 and flow.snapshot().reward_state.perfect_day == -1, "authentic retry commits one token and gold without false flawless title")
	await _daily_dispose(flow)
	flow = _daily_flow(fixture)
	for offset: int in range(4):
		_clock += 86400
		_suite.assert_true(flow.start().ok, "next day admits native reward proof")
		flow.current_player().set_physics_process(false)
		flow.current_player().advance_action_frame({})
		flow.current_boss().health.lose_health(100000, flow.current_player())
		await get_tree().process_frame
		await get_tree().process_frame
	_suite.assert_equal(flow.snapshot().reward_state.tokens, 5, "five native dates earn exactly five durable tokens")
	await _daily_dispose(flow)
	var coordinator := preload("res://scripts/modes/daily_boss_coordinator.gd").new()
	add_child(coordinator)
	_suite.assert_true(coordinator.configure(_registry, fixture.service, fixture.root.path_join("daily"), func(): return _clock).ok and coordinator.open().ok, "earned wallet opens actual production challenge controller")
	flow = coordinator.runtime()
	await get_tree().process_frame
	var exchange := _reward_action(coordinator.panel(), "exchange:daily_weapon_skin")
	_suite.assert_true(exchange != null and not exchange.disabled and exchange.has_focus(), "actual five-token controller exchange is available and focused")
	var stale := _daily_flow(fixture)
	flow.set_fault_injector(func(at: StringName): return at == &"before_primary_promote")
	exchange.pressed.emit()
	_suite.assert_true(flow.has_pending_save() and not flow.snapshot().reward_state.owned_ids.has("daily_weapon_skin"), "failed controller exchange keeps money and ownership unpublished")
	flow.set_fault_injector(Callable())
	_reward_action(coordinator.panel(), "retry").pressed.emit()
	_suite.assert_true(not flow.has_pending_save() and flow.snapshot().reward_state.tokens == 0, "controller exchange retry commits exact five-token price once")
	_suite.assert_true(_reward_action(coordinator.panel(), "exchange:daily_weapon_skin").disabled, "owned exchange remains present and disabled")
	var refused: Dictionary = stale.purchase_reward("daily_weapon_skin")
	_suite.assert_true(not refused.ok and refused.code == &"DAILY_STALE_PRIMARY", "stale reward writer cannot repeat another exchange")
	_suite.assert_true(stale.reload_saved_session().ok and stale.snapshot().reward_state.owned_ids == ["daily_weapon_skin"], "cold physical aggregate retains purchased ownership")
	_suite.assert_true(not stale.purchase_reward("daily_weapon_skin").ok, "owned cosmetic cannot spend a second time")
	coordinator.queue_free()
	await get_tree().process_frame
	await _daily_dispose(stale)
	_suite.finish(get_tree())


func _reward_action(panel: Control, id: String) -> Button:
	for button: Node in panel.find_children("*", "Button", true, false):
		if button.get_meta("action_id", "") == id:
			return button as Button
	return null
