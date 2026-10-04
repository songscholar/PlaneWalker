extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const MainScene := preload("res://scenes/main.tscn")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const HostScript := preload("res://scripts/application/run_runtime_host.gd")


class EntranceFaultHost extends HostScript:
	var reject_entry_once := true

	func _settle_floor_entrance() -> bool:
		if reject_entry_once:
			reject_entry_once = false
			return false
		return super._settle_floor_entrance()

var _primary_writes := 0
var _fail_bootstrap_write := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	suite.assert_true(host.has_method("start_profile_run"), "production Host requires durable profile-to-native launch")
	if not host.has_method("start_profile_run"):
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	host.set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var catalog: RefCounted = Factory.load_base().context.catalog
	var save := Save.new()
	var service := Service.new()
	var content: Dictionary = ContentSnapshot.snapshot(host.get("_facade").content_registry())
	suite.assert_true(save.configure(Paths.resolve_default("user://p16-meta-host", "p16-meta-host"), "0.4.0-dev", content).ok, "Host integration uses actual Base fingerprint and isolated physical Save files")
	suite.assert_true(service.configure(catalog, save, "host_slot", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "Host integration starts from an explicit complete-progression fixture")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "time_guardian", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	var bad := config.duplicate(true)
	bad.milestone = "M1"
	var before: Dictionary = service.snapshot()
	var native_before: Dictionary = host.runtime_snapshot()
	for forged: Dictionary in [{"launch": true, "projection": false}, {"launch": {}, "projection": {}}, {"launch": {"run_id": "forged"}, "projection": {}}]:
		suite.assert_true(not host.start_run(config, forged).ok, "caller-built profile context is refused before native initialization")
		suite.assert_true(host.runtime_snapshot() == native_before, "malformed profile context cannot change the live native run")
	suite.assert_true(not host.call("start_profile_run", bad, service, int(before.revision)).ok, "durable Meta launch refuses a historical milestone before spending a launch sequence")
	suite.assert_equal(service.snapshot(), before, "invalid profile launch preserves the durable profile")
	var launched = host.call("start_profile_run", config, service, int(before.revision))
	suite.assert_true(launched.ok, "real Profile service launches the production Main Host: " + str(launched.context))
	if launched.ok:
		var state: Dictionary = host.call("runtime_snapshot")
		var profile: Dictionary = service.snapshot()
		suite.assert_equal(state.run_id, profile.active_launch_receipt.run_id, "Host and native Player use the durable monotonic launch identity")
		suite.assert_equal(str(player.current_run_id()), state.run_id, "native Player belongs to the persisted launch")
		suite.assert_equal(state.resources.meta_run_projection.projection_digest, profile.active_launch_receipt.projection_digest, "native RunState contains the exact frozen receipt projection")
		suite.assert_equal(player.meta_run_projection_snapshot(), state.resources.meta_run_projection, "production Host installs frozen progression before the Player reward baseline")
		suite.assert_true(float(player.stats.max_hp) > 160.0, "real permanent HP reaches the selected time guardian")
		suite.assert_equal(state.resources.meta_floor_entrances, [0], "production floor startup consumes its recovery once")
		suite.assert_equal(service.payload().active_run_state, state, "completed bootstrap retains the full canonical native run in the same Profile envelope")
		var durable = save.load_profile("host_slot", "base")
		suite.assert_true(durable.ok, "physical v4 launch envelope reloads")
		if durable.ok:
			suite.assert_true(_json_equal(durable.payload.active_run_state, state), "physical JSON preserves frozen launch and consumed entrance")
			suite.assert_true(_json_equal(durable.payload.reward_effect_state, player.reward_effect_snapshot()), "physical JSON preserves native permanent Health and reward participants")
			suite.assert_true(service.restore_active_run(host.native_run_state(), player).ok, "physical JSON can reinstall actual native Run and Player participants")
			var before_restore: Dictionary = host.runtime_snapshot()
			suite.assert_true(host.retry_floor_entrance().ok and host.runtime_snapshot() == before_restore, "physical restore cannot grant another entrance recovery")
		var repeated = host.call("start_profile_run", config, service, int(profile.revision))
		suite.assert_true(not repeated.ok, "a live durable receipt cannot silently launch another run")
		suite.assert_equal(service.snapshot(), profile, "rejected duplicate launch cannot mint a second sequence")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_failed_bootstrap(suite, catalog, config)
	await _test_cold_bootstrap(suite, catalog, config)
	await _test_publication_drift(suite, catalog, config)
	suite.finish(get_tree())


func _test_failed_bootstrap(suite, catalog: RefCounted, config: Dictionary) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	host.set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var save := Save.new()
	var service := Service.new()
	var content: Dictionary = ContentSnapshot.snapshot(host.get("_facade").content_registry())
	suite.assert_true(save.configure(Paths.resolve_default("user://p16-meta-host-retry", "p16-meta-host-retry"), "0.4.0-dev", content, Callable(), Callable(self, "_inject_bootstrap_fault")).ok, "retry uses actual atomic Save with a pre-promotion fault")
	suite.assert_true(service.configure(catalog, save, "host_retry", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "retry Profile fixture configures")
	var notices: Array = []
	var observer := func(run_id: String, state: Dictionary): notices.append([run_id, state])
	EventBus.run_started.connect(observer)
	_primary_writes = 0
	_fail_bootstrap_write = true
	var failed = host.start_profile_run(config, service, int(service.snapshot().revision))
	suite.assert_true(not failed.ok, "failed full bootstrap checkpoint is reported")
	suite.assert_true(notices.is_empty(), "run_started cannot publish before the full native checkpoint is durable")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "undurable bootstrap keeps the physical Player frozen")
	var pending: Dictionary = service.snapshot()
	suite.assert_true(not pending.active_launch_receipt.is_empty() and service.payload().active_run_state.is_empty(), "prepared durable launch survives a failed native checkpoint")
	suite.assert_true(host.has_method("retry_profile_startup"), "production Host exposes native checkpoint recovery")
	if host.has_method("retry_profile_startup"):
		var retry = host.retry_profile_startup(service, int(pending.revision))
		suite.assert_true(retry.ok, "same prepared launch can finish durable startup")
		suite.assert_equal(service.snapshot().launch_sequence, pending.launch_sequence, "startup retry cannot mint another launch identity")
		suite.assert_equal(notices.size(), 1, "successful durable retry publishes run_started exactly once")
		suite.assert_true(_json_equal(service.payload().active_run_state, host.runtime_snapshot()), "retry publishes the same canonical native state that was retained")
		suite.assert_equal(retry.new_revision, host.runtime_snapshot().revision, "startup result returns the final native revision")
	EventBus.run_started.disconnect(observer)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _inject_bootstrap_fault(point: StringName) -> bool:
	if point != &"before_primary_promote":
		return false
	_primary_writes += 1
	return _fail_bootstrap_write and _primary_writes == 2


func _test_cold_bootstrap(suite, catalog: RefCounted, config: Dictionary) -> void:
	var main := MainScene.instantiate()
	main.get_node("RunRuntimeHost").set_script(EntranceFaultHost)
	main.get_node("RunRuntimeHost").set("room_controller_path", NodePath("../CombatRoom01"))
	add_child(main)
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	host.set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var save := Save.new()
	var service := Service.new()
	var content: Dictionary = ContentSnapshot.snapshot(host.get("_facade").content_registry())
	suite.assert_true(save.configure(Paths.resolve_default("user://p16-meta-host-cold", "p16-meta-host-cold"), "0.4.0-dev", content).ok and service.configure(catalog, save, "host_cold", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "cold recovery uses physical Save and an actual production Host")
	var chosen := config.duplicate(true)
	chosen.accessibility_assists = {"damage_received_multiplier": 0.8, "enemy_telegraph_scale": 1.25}
	var notices: Array = []
	var observer := func(run_id: String, state: Dictionary): notices.append([run_id, state])
	EventBus.run_started.connect(observer)
	var failed = host.start_profile_run(chosen, service, int(service.snapshot().revision))
	suite.assert_true(not failed.ok and failed.context.get("startup_pending", false), "native setup refusal preserves a retryable durable receipt")
	suite.assert_true(notices.is_empty(), "failed native setup cannot publish a playable run")
	var identity := str(service.snapshot().active_launch_receipt.run_id)
	var restored := Service.new()
	suite.assert_true(restored.configure(catalog, save, "host_cold", "base").ok, "fresh Profile service reloads prepared bootstrap")
	var retry = host.retry_profile_startup(restored, int(restored.snapshot().revision))
	suite.assert_true(retry.ok, "fresh physical Profile finishes an interrupted native bootstrap: " + str(retry.context))
	if retry.ok:
		suite.assert_equal(host.runtime_snapshot().run_id, identity, "cold retry preserves the original durable run identity")
		suite.assert_equal(host.runtime_snapshot().config.accessibility_assists, chosen.accessibility_assists, "cold retry preserves explicitly chosen assistance rather than deriving new settings")
		suite.assert_equal(host.runtime_snapshot().resources.meta_floor_entrances, [0], "cold retry settles original floor recovery once")
		suite.assert_equal(notices.size(), 1, "cold retry publishes one playable run after durable native startup")
		suite.assert_equal(retry.new_revision, host.runtime_snapshot().revision, "cold retry returns the final installed revision")
		_test_next_floor_retry(suite, host, player)
	EventBus.run_started.disconnect(observer)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_next_floor_retry(suite, host: Node, player: Node) -> void:
	var facade: RefCounted = host.get("_facade")
	for step: int in range(16):
		var choices: Array = facade.route_choices()
		if choices.is_empty():
			suite.assert_true(false, "actual floor preparation exposes a route")
			return
		var begun = facade.begin_route_transition(StringName(choices[0].edge_id), int(facade.snapshot().revision))
		if not begun.ok:
			suite.assert_true(false, "actual floor preparation begins a canonical route")
			return
		var finalized = facade.finalize_route_transition(str(begun.context.transition_id), int(begun.new_revision))
		var confirmed = facade.confirm_route_transition(str(begun.context.transition_id), int(finalized.new_revision))
		suite.assert_true(finalized.ok and confirmed.ok, "floor retry fixture prepares native canonical room state")
		if not confirmed.ok:
			return
		var boss := str(facade.current_room_definition().room_type) == "boss"
		suite.assert_true(facade.complete_current_room().ok, "floor retry fixture completes actual room domains")
		if boss:
			break
	var physical: Dictionary = player.reward_effect_snapshot()
	physical.health.current_hp = physical.health.max_hp * 0.5
	suite.assert_true(player.restore_reward_effect_snapshot(physical), "next floor retry begins with actual missing HP")
	host.set("reject_entry_once", true)
	var floor_before: Dictionary = host.runtime_snapshot()
	var failed = host.start_next_floor(int(floor_before.revision))
	suite.assert_true(not failed.ok and failed.context.get("recovery") == "retry_floor_entrance", "post-transition entrance refusal exposes its dedicated recovery")
	suite.assert_equal(host.runtime_snapshot().current_floor_index, 1, "the canonical next floor remains prepared for entrance retry")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "entrance refusal freezes the Player while the prepared floor awaits recovery")
	var paused_before: Dictionary = host.runtime_snapshot()
	host.call("_process", 1.0)
	suite.assert_true(host.runtime_snapshot() == paused_before, "entrance recovery cannot advance gameplay time")
	var routes: Array = host.route_choices()
	if not routes.is_empty():
		suite.assert_true(not host.select_route(StringName(routes[0].edge_id), int(paused_before.revision)).ok, "route input cannot bypass pending entrance recovery")
	suite.assert_true(host.retry_floor_entrance().ok, "native next-floor recovery retries once")
	suite.assert_equal(host.runtime_snapshot().resources.meta_floor_entrances, [0, 1], "retry consumes only the prepared next entrance")
	suite.assert_close(player.health.current_hp, physical.health.current_hp + physical.health.max_hp * 0.02, "next-floor retry installs the authored recovery on actual health")
	suite.assert_true(player.process_mode != Node.PROCESS_MODE_DISABLED, "successful entrance retry restores gameplay processing")


func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(Envelope.canonical_json(left)) == JSON.parse_string(Envelope.canonical_json(right))


func _test_publication_drift(suite, catalog: RefCounted, config: Dictionary) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	host.set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var save := Save.new()
	var service := Service.new()
	var content: Dictionary = ContentSnapshot.snapshot(host.get("_facade").content_registry())
	suite.assert_true(save.configure(Paths.resolve_default("user://p16-meta-host-drift", "p16-meta-host-drift"), "0.4.0-dev", content).ok and service.configure(catalog, save, "host_drift", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "publication drift uses actual native Host and physical Profile")
	var run_notices: Array = []
	var floor_notices: Array = []
	var observer := func(run_id: String, _state: Dictionary):
		run_notices.append(run_id)
		player.configure_run(&"foreign-run-after-saved-publication")
	var floor_observer := func(_run_id: String, _floor_id: String, _floor_index: int, _revision: int): floor_notices.append(true)
	EventBus.run_started.connect(observer)
	EventBus.floor_started.connect(floor_observer)
	var drifted = host.start_profile_run(config, service, int(service.snapshot().revision))
	suite.assert_true(not drifted.ok and drifted.code == &"NATIVE_PUBLICATION_PENDING", "changed Player identity after saved publication is reported")
	suite.assert_equal(run_notices.size(), 1, "saved run publication is consumed once even when callback drifts identity")
	suite.assert_true(floor_notices.is_empty(), "drifted startup cannot publish a stale floor identity")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "post-publication identity drift freezes the actual Player")
	var again = host.retry_profile_startup(service, int(service.snapshot().revision))
	suite.assert_true(not again.ok and again.code == &"NATIVE_PUBLICATION_PENDING", "retry cannot duplicate an already consumed run publication")
	suite.assert_equal(run_notices.size(), 1, "pending publication retry never emits run_started twice")
	EventBus.run_started.disconnect(observer)
	EventBus.floor_started.disconnect(floor_observer)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
