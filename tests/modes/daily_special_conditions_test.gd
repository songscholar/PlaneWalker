extends "res://tests/integration/combat/daily_boss_native_test.gd"

const PlayerRulePath := "res://scripts/modes/daily_player_controller.gd"


func _run() -> void:
	_suite = Suite.new()
	_suite.assert_true(ResourceLoader.exists(PlayerRulePath), "all authored Daily conditions have executable native Player behavior")
	if not ResourceLoader.exists(PlayerRulePath):
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := preload("res://scripts/modes/daily_boss_catalog.gd").new()
	_suite.assert_true(catalog.configure(_registry), "expanded native daily catalog configures")
	var found: Dictionary = {}
	var origin := _clock
	for offset: int in range(500):
		var definition: Dictionary = catalog.projection(origin + offset * 86400)
		for id: String in definition.condition_ids:
			if not found.has(id):
				found[id] = offset
	_suite.assert_equal(found.size(), 8, "actual calendar reaches all eight authored native conditions")
	for id: String in ["swift_finish", "dodge_master", "final_strike", "temporal_disorder", "bullet_hell"]:
		if not found.has(id):
			continue
		_clock = origin + int(found[id]) * 86400
		var flow := _daily_flow(_daily_fixture("native-special-" + id))
		_suite.assert_true(flow.start().ok, "actual native special condition starts " + id)
		if not flow.is_active():
			await _daily_dispose(flow)
			continue
		var player: Node2D = flow.current_player()
		player.set_physics_process(false)
		var definition: Dictionary = flow.current_boss().get("_launch_definition")
		match id:
			"swift_finish":
				_suite.assert_equal(definition.enrage.threshold_frames, 3600, "actual bound Boss has sixty-second enrage")
			"dodge_master":
				var native: Dictionary = player.call("daily_rule_snapshot")
				_suite.assert_equal(native.extra_dash_remaining, 1, "daily native Player owns exactly one additional dash")
				_suite.assert_equal(player.mobility_snapshot().dash_invulnerable_frames, native.base_mobility.dash_invulnerable_frames - 3, "native dash loses exactly three invulnerability frames")
				player.health.invulnerable = true
				_suite.assert_true(player.try_action(&"dash"), "first actual dash commits")
				for frame: int in range(int(player.mobility_snapshot().dash_duration_frames)):
					_suite.assert_true(player.advance_action_frame({}), "native first dash frame commits")
				var dash_before: Dictionary = player.call("_fixed_frame_transaction_snapshot")
				_suite.assert_true(player.try_action(&"dash") and player.call("daily_rule_snapshot").extra_dash_remaining == 0, "actual extra dash spends its owned charge during cooldown")
				_suite.assert_true(player.call("_restore_fixed_frame_transaction", dash_before), "refused native extra dash restores entire Player frame transaction")
				_suite.assert_equal(player.call("daily_rule_snapshot").extra_dash_remaining, 1, "dash rollback restores the owned extra charge")
				_suite.assert_true(player.try_action(&"dash"), "same actual extra dash retries after rollback")
				for frame: int in range(int(player.mobility_snapshot().dash_duration_frames)):
					player.advance_action_frame({})
				_suite.assert_true(not player.try_action(&"dash"), "third actual dash refuses during recharge")
				for frame: int in range(int(player.mobility_snapshot().dash_cooldown_frames)):
					player.advance_action_frame({})
				_suite.assert_true(player.call("daily_rule_snapshot").extra_dash_remaining == 1 and player.try_action(&"dash"), "actual cooldown restores both normal dash and one extra charge")
			"temporal_disorder":
				var native: Dictionary = player.call("daily_rule_snapshot")
				_suite.assert_equal(player.time_manager.time_stop_cooldown, native.base_time.stop_cooldown * 2.0, "native time cooldown doubles")
				_suite.assert_equal(player.time_manager.time_stop_duration + player.time_manager.time_stop_duration_bonus, native.base_time.stop_duration * 1.5, "actual stop effect duration scales after Build installation")
				_suite.assert_equal(player.rewind_recorder.record_seconds, native.base_time.rewind_history * 1.5, "actual rewind history capacity scales")
				_verify_time_settlements(player, native.base_time)
			"final_strike":
				_suite.assert_true(definition.daily_conditions.ids.has("final_strike"), "native Boss projection retains validated low-HP rule")
			"bullet_hell":
				for action: Dictionary in definition.actions:
					if action.handler_id == "projectile_volley":
						var original := _original_action(definition.daily_conditions.base.actions, action.id)
						_suite.assert_equal(action.geometry.size(), ceili(original.geometry.size() * 1.5), "actual Boss volley expands native projectile lanes")
		_suite.assert_true(flow.abandon().ok, "actual daily special arena retires once")
		await _daily_dispose(flow)
	_clock = origin
	_suite.finish(get_tree())


func _original_action(actions: Array, id: String) -> Dictionary:
	for action: Dictionary in actions:
		if action.id == id:
			return action
	return {}


func _verify_time_settlements(player: Node2D, base: Dictionary) -> void:
	var manager: Node = player.time_manager
	manager.energy = manager.max_energy
	_suite.assert_true(manager.try_time_stop(), "native Daily Stop settles actual effect")
	_suite.assert_close(manager.replay_snapshot().stop_remaining, ceili(float(base.stop_duration) * 1.5 * 60.0) / 60.0, "actual committed Daily Stop retains150percent duration")
	_suite.assert_close(manager.get_cooldown(&"time_stop"), ceili(float(base.stop_cooldown) * 2.0 * 60.0) / 60.0, "actual committed Daily Stop retains doubled cooldown")
	manager.cancel_all_time_effects(&"daily_rule_test")
	manager.energy = manager.max_energy
	_suite.assert_true(manager.try_time_rift(player.global_position), "native Daily Rift settles actual world payload")
	var rifts: Array = manager.replay_snapshot().active_rifts
	_suite.assert_equal(rifts.size(), 1, "actual Daily Rift owns one native world payload")
	if not rifts.is_empty():
		_suite.assert_equal(rifts[0].remaining_frames, maxi(1, roundi(float(base.rift_duration) * 1.5 * 60.0)), "actual committed Daily Rift retains150percent duration")
	_suite.assert_close(manager.get_cooldown(&"time_rift"), ceili(float(base.rift_cooldown) * 2.0 * 60.0) / 60.0, "actual committed Daily Rift retains doubled cooldown")
	manager.cancel_all_time_effects(&"daily_rule_test")
	manager.energy = manager.max_energy
	_suite.assert_true(manager.try_time_accelerate(), "native Daily acceleration settles actual Player effect")
	_suite.assert_true(player.is_time_accelerated(), "actual Daily acceleration reaches native Player")
	_suite.assert_close(manager.replay_snapshot().accelerate_remaining, ceili(float(base.accelerate_duration) * 1.5 * 60.0) / 60.0, "actual committed Daily acceleration retains150percent duration")
	_suite.assert_close(manager.get_cooldown(&"time_accelerate"), ceili(float(base.accelerate_cooldown) * 2.0 * 60.0) / 60.0, "actual committed Daily acceleration retains doubled cooldown")
	manager.cancel_all_time_effects(&"daily_rule_test")
