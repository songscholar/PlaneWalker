extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var activated: Dictionary = GameState.activate_profile_content(registry)
	suite.assert_true(activated.ok, "actual production Profile activates before Main launch: " + str(activated))
	var service: RefCounted = GameState.profile_runtime_service()
	if service == null:
		suite.finish(get_tree())
		return
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261006}
	suite.assert_true(main._launch_run(config, false, true), "Main's actual launch entry starts a real durable run")
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var profile: Dictionary = service.snapshot()
	suite.assert_equal(profile.launch_sequence, 1, "Main spends one durable monotonic launch identity")
	suite.assert_equal(profile.active_launch_receipt.get("run_id", ""), host.runtime_snapshot().run_id, "Main, canonical Run, and physical Profile share the same launch")
	if profile.active_launch_receipt.is_empty():
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var before: Dictionary = service.snapshot()
	EventBus.run_ended.emit("forged-summary", {"result": "victory", "rooms_cleared": 99}, 9999)
	suite.assert_equal(service.snapshot(), before, "a fabricated terminal notice cannot mint Profile currency or statistics")
	suite.assert_true(not main.get_node("RunEndOverlay").visible, "fabricated notices cannot take over actual terminal focus")
	var routes: Array = host.route_choices()
	suite.assert_true(not routes.is_empty(), "real Launch entry presents an authored route")
	if not routes.is_empty():
		var selected = host.select_route(StringName(routes[0].edge_id), int(host.runtime_snapshot().revision))
		suite.assert_true(selected.ok, "real route prepares and installs a native room: " + str(selected.context))
		main.get_node("DungeonFlow").refresh(true)
	for _frame: int in range(4):
		await get_tree().physics_frame
	suite.assert_true(host.runtime_snapshot().run_time_ms > 0, "actual gameplay advances outside the route selection")
	before = service.snapshot()
	host.set_process(false)
	player.set_physics_process(false)
	var save: RefCounted = GameState.get("_save_service")
	save.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	player.health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(host.runtime_snapshot().phase, Phase.Value.DEFEAT, "actual Player death reaches native terminal state")
	var contract = Envelope.validate_active_run_snapshot(host.runtime_snapshot())
	suite.assert_true(contract.ok, "actual terminal obeys the physical Save contract: " + str(contract.to_dictionary()))
	suite.assert_equal(service.snapshot(), before, "failed actual settlement promotion cannot mint currency or statistics")
	suite.assert_true(not main.return_to_hub(), "failed settlement keeps the actual terminal recoverable")
	save.set_fault_injector(Callable())
	var retry: Dictionary = main.retry_terminal_settlement()
	suite.assert_true(retry.ok, "native terminal settlement accepts the actual state: " + str(retry))
	profile = service.snapshot()
	suite.assert_equal(profile.statistics.finished_runs, 1, "Main settles one actual terminal run")
	suite.assert_equal(profile.statistics.deaths, 1, "native death persists canonical statistics")
	suite.assert_equal(profile.chronos_shards, 3, "entry death awards exactly the authored settlement amount")
	suite.assert_true(profile.active_launch_receipt.is_empty(), "successful settlement retires the active launch receipt")
	suite.assert_equal(GameState.persistent.meta_profile_state, profile, "compatibility mirror follows the durable settled Profile")
	var durable = save.inspect_profile("slot_1", "base")
	EventBus.run_ended.emit(str(host.runtime_snapshot().run_id), host.runtime_snapshot().result.duplicate(true), int(host.runtime_snapshot().revision))
	suite.assert_equal(service.snapshot(), profile, "repeated real terminal notices cannot award twice")
	suite.assert_equal(save.inspect_profile("slot_1", "base").payload, durable.payload, "repeated terminal cannot consume a physical save sequence")
	suite.assert_true(main.has_method("return_to_hub"), "Main needs a native terminal-to-Hub return without resetting the scene")
	if main.has_method("return_to_hub"):
		suite.assert_true(main.return_to_hub(), "actual terminal can return to the Hub entry")
		suite.assert_true(main._launch_run(config, false, true), "actual Hub can relaunch using the settled Profile")
		suite.assert_equal(service.snapshot().launch_sequence, 2, "relaunch creates the next durable identity")
		suite.assert_equal(service.snapshot().statistics.finished_runs, 1, "relaunch cannot repeat settlement statistics")
		suite.assert_equal(service.snapshot().chronos_shards, 3, "relaunch cannot mint a second terminal reward")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
