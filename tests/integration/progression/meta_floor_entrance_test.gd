extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Facade := preload("res://scripts/application/run_runtime_facade.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const RewardRuntime := preload("res://scripts/items/player_reward_effect_runtime.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const PlayerScript := preload("res://scripts/player/player_controller.gd")


class EventRefreshFault extends Facade:
	var reject_refresh_once := false

	func _refresh_event_runtime_from_state() -> bool:
		if reject_refresh_once:
			reject_refresh_once = false
			return false
		return super._refresh_event_runtime_from_state()


class PlayerInstallFault extends PlayerScript:
	var reject_install_once := false

	func restore_reward_effect_snapshot(value: Dictionary, publish: bool = true, replay_context: Dictionary = {}) -> bool:
		if reject_install_once:
			reject_install_once = false
			return false
		return super.restore_reward_effect_snapshot(value, publish, replay_context)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var facade = Facade.new()
	suite.assert_true(facade.boot().ok, "entry fixture boots actual content")
	for api: String in ["start_meta_run", "apply_meta_floor_entrance"]:
		suite.assert_true(facade.has_method(api), "native Meta entry boundary exists: " + api)
	if not facade.has_method("start_meta_run") or not facade.has_method("apply_meta_floor_entrance"):
		suite.finish(get_tree())
		return
	var catalog: RefCounted = Factory.load_base().context.catalog
	var projection: Dictionary = MetaProjection.from_profile(Fixtures.profile(catalog), catalog).context.projection
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	var corrupt := projection.duplicate(true)
	corrupt.stat_bonuses.entrance_healing = 0.90
	corrupt.projection_digest = MetaProjection.digest(corrupt)
	var before: Dictionary = facade.snapshot()
	suite.assert_true(not facade.call("start_meta_run", config, "meta-entry", corrupt).ok, "contradictory rehashed policy cannot start a native run")
	suite.assert_equal(facade.snapshot(), before, "bad launch leaves canonical facade untouched")
	suite.assert_true(facade.call("start_meta_run", config, "meta-entry", projection).ok, "authenticated projection starts the production five-floor facade")
	suite.assert_equal(facade.snapshot().resources.meta_run_projection, projection, "RunState preserves the immutable launch policy")
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var loadout: Dictionary = facade.active_loadout()
	var native_config: Dictionary = facade.snapshot().config.duplicate(true)
	native_config.character_profile = loadout.character_profile
	native_config.weapon_profile = loadout.weapon_profile
	native_config.meta_run_projection = projection.duplicate(true)
	suite.assert_true(player.configure_run(&"meta-entry") and player.configure_loadout(native_config), "native Player shares the sealed launch identity and permanent policy")
	suite.assert_true(facade.configure_merchant_effect_authority(RewardRuntime.new(), player), "physical health and event participants bind")
	var physical: Dictionary = player.reward_effect_snapshot()
	physical.health.current_hp = physical.health.max_hp * 0.5
	suite.assert_true(player.restore_reward_effect_snapshot(physical), "entry fixture starts with actual missing HP")
	var entered: Dictionary = facade.call("apply_meta_floor_entrance", player)
	suite.assert_true(entered.ok, "first floor entry settles actual native health")
	var expected: float = physical.health.current_hp + physical.health.max_hp * 0.02
	suite.assert_close(player.health.current_hp, expected, "W-04 restores two percent of permanent max HP")
	suite.assert_close(facade.snapshot().resources.health.current, expected, "canonical event health matches the physical recovery")
	var once: Dictionary = facade.snapshot()
	var native: RefCounted = facade.native_run_state()
	var floor_context: Dictionary = native.floor_transaction_snapshot()
	var malformed := once.duplicate(true)
	malformed.build.unknown_policy = true
	malformed.stats.kills += 7
	malformed.run_time_ms += 1000
	suite.assert_true(not native.restore_launch_run_snapshot(malformed, floor_context.floor_definition, floor_context.room_templates), "native restore rejects unrecognized build fields")
	suite.assert_true(native.snapshot() == once, "a rejected native restore preserves every participant, clock, statistic, and receipt")
	suite.assert_true(facade.call("apply_meta_floor_entrance", player).ok, "duplicate notification is an idempotent success")
	suite.assert_equal(facade.snapshot(), once, "duplicate entry cannot mutate markers or revision")
	suite.assert_close(player.health.current_hp, expected, "duplicate entry cannot heal twice")
	var restored = Facade.new()
	suite.assert_true(restored.boot().ok, "fresh facade boots for native JSON continuation")
	suite.assert_true(restored.configure_merchant_effect_authority(RewardRuntime.new(), player), "fresh facade binds actual Player")
	var persisted = Envelope.validate_active_run_snapshot(JSON.parse_string(JSON.stringify(once)))
	suite.assert_true(persisted.ok, "SaveEnvelope authenticates canonical Meta resources after real JSON normalization: " + str(persisted.diagnostics))
	var json_state: Dictionary = persisted.payload if persisted.ok else {}
	var restored_result = restored.restore_launch_run(json_state)
	suite.assert_true(restored_result.ok, "native Meta state restores after physical JSON roundtrip: " + str(restored_result.context))
	if restored_result.ok:
		suite.assert_true(restored.call("apply_meta_floor_entrance", player).ok, "saved entry marker remains consumed")
		suite.assert_close(player.health.current_hp, expected, "reloading a floor cannot mint another recovery")
		var bad := once.duplicate(true)
		bad.resources.meta_floor_entrances = [2]
		var rejecting = Facade.new()
		suite.assert_true(rejecting.boot().ok, "corrupt restore target starts at native Hub phase")
		var current: Dictionary = rejecting.snapshot()
		suite.assert_true(not rejecting.restore_launch_run(bad).ok, "future or noncanonical entrance markers refuse")
		suite.assert_equal(rejecting.snapshot(), current, "corrupt marker restore is atomic")
		bad = once.duplicate(true)
		bad.resources.meta_run_projection.projection_digest = "0".repeat(64)
		suite.assert_true(not rejecting.restore_launch_run(bad).ok, "corrupt permanent projection refuses native restore")
		suite.assert_equal(rejecting.snapshot(), current, "corrupt policy restore preserves current run")
		bad = once.duplicate(true)
		bad.resources.health.current += 1.0
		suite.assert_true(not rejecting.restore_launch_run(bad).ok, "canonical health cannot contradict its actual event participant")
		suite.assert_equal(rejecting.snapshot(), current, "health drift restore preserves the native target")
	player.queue_free()
	facade = null
	restored = null
	await get_tree().process_frame
	await _test_failed_entry(suite, config, projection, false)
	await _test_failed_entry(suite, config, projection, true)
	suite.finish(get_tree())


func _test_failed_entry(suite, config: Dictionary, projection: Dictionary, event_failure: bool) -> void:
	var facade := EventRefreshFault.new()
	suite.assert_true(facade.boot().ok and facade.start_meta_run(config, "entry-compensation", projection).ok, "compensation uses the actual native Meta run")
	var player := PlayerScene.instantiate()
	player.set_script(PlayerInstallFault)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var loadout: Dictionary = facade.active_loadout()
	var native_config: Dictionary = facade.snapshot().config.duplicate(true)
	native_config.character_profile = loadout.character_profile
	native_config.weapon_profile = loadout.weapon_profile
	native_config.meta_run_projection = projection.duplicate(true)
	suite.assert_true(player.configure_run(&"entry-compensation") and player.configure_loadout(native_config), "compensation uses an actual Player with a one-shot failing participant")
	var physical: Dictionary = player.reward_effect_snapshot()
	physical.health.current_hp *= 0.5
	suite.assert_true(player.restore_reward_effect_snapshot(physical), "compensation fixture installs missing HP")
	suite.assert_true(facade.configure_merchant_effect_authority(RewardRuntime.new(), player), "compensation binds real health and event participants")
	var before: Dictionary = facade.snapshot()
	var notices: Array = []
	player.get_node("HealthComponent").healed.connect(func(amount: float, hp: float): notices.append([amount, hp]))
	if event_failure:
		facade.reject_refresh_once = true
	else:
		player.reject_install_once = true
	var failed: Dictionary = facade.apply_meta_floor_entrance(player)
	suite.assert_true(not failed.ok and failed.code == &"COMMIT_FAILED", "participant failure reports a compensated refusal")
	suite.assert_true(facade.snapshot() == before, "entry failure restores the whole native run and event state")
	suite.assert_equal(player.reward_effect_snapshot(), physical, "entry failure preserves physical Player participants")
	suite.assert_true(notices.is_empty(), "failed entry publishes no healing signal")
	suite.assert_true(facade.apply_meta_floor_entrance(player).ok, "the compensated floor entry can retry")
	suite.assert_equal(notices.size(), 1, "successful retry publishes one physical healing fact")
	player.queue_free()
	await get_tree().process_frame
