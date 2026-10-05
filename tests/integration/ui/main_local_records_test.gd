extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Records := preload("res://scripts/community/local_run_records.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var records: RefCounted = main.get("_local_records")
	suite.assert_true(records != null, "actual Main installs optional physical local record provider")
	if records == null:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var host: Node = main.get_node("RunRuntimeHost")
	var service: RefCounted = GameState.profile_runtime_service()
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	suite.assert_true(main._launch_run(config, false, true), "native entry launches an actual durable run")
	EventBus.run_ended.emit("forged-record", {"result": "victory"}, 99)
	suite.assert_true(records.snapshot().entries.is_empty(), "fabricated terminal notices cannot publish local records")
	var routes: Array = host.route_choices()
	if not routes.is_empty():
		suite.assert_true(host.select_route(StringName(routes[0].edge_id), int(host.runtime_snapshot().revision)).ok, "native route starts playable time")
		main.get_node("DungeonFlow").refresh(true)
	for _frame: int in range(4):
		await get_tree().physics_frame
	suite.assert_true(host.runtime_snapshot().run_time_ms > 0, "native elapsed time is observed by canonical Run")
	host.set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	records.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	player.health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(service.snapshot().statistics.finished_runs, 1, "actual death settles physical Profile despite optional record fault")
	suite.assert_true(records.snapshot().entries.is_empty(), "failed optional record promotion retains empty memory")
	suite.assert_true(main.return_to_hub(), "optional storage failure preserves actual Hub return")
	suite.assert_true(main._launch_run(config, false, true), "record storage fault cannot block the next successful native launch")
	suite.assert_equal(service.snapshot().launch_sequence, 2, "second actual launch consumes its own durable identity")
	suite.assert_equal(service.payload().local_records_outbox.sources.size(), 1, "new native launch retains the previous authenticated failed record")
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	service = GameState.profile_runtime_service()
	records = main.get("_local_records")
	suite.assert_true(records != null and records.snapshot().entries.size() == 1, "fresh Main reads physical outbox and recovers old record during the second active Run")
	suite.assert_true(service.snapshot().active_launch_receipt.sequence == 2 and service.payload().local_records_outbox.sources.is_empty(), "record acknowledgement preserves second launch and retires only consumed outbox")
	var hub: Node = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("mirror").ok, "real Hub mirror opens")
	var refresh := _action(hub, "provider_refresh:leaderboard")
	suite.assert_true(refresh != null, "native mirror includes actual local-record refresh control")
	if refresh != null:
		var retired: Callable = refresh.pressed.get_connections()[0].callable
		refresh.pressed.emit()
		retired.call()
		await get_tree().process_frame
	suite.assert_equal(records.snapshot().entries.size(), 1, "real refresh retries failed authentic record exactly once")
	var state: Dictionary = hub.view_state()
	var displayed := false
	for row: Dictionary in state.providers:
		if row.id == "leaderboard": displayed = row.available and row.entries.size() == 1
	suite.assert_true(displayed, "native Hub view state exposes real ranked local record")
	var labels: Array[Node] = hub.panel_view().find_children("*", "Label", true, false)
	var label_present := false
	for label: Label in labels:
		label_present = label_present or label.text.contains(tr("CHARACTER_WANDERER_NAME")) and label.text.contains(tr("WEAPON_SWORD_NAME"))
	suite.assert_true(label_present, "actual record name and score render in native mirror")
	refresh = _action(hub, "provider_refresh:leaderboard")
	refresh.grab_focus()
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), refresh, "refresh control belongs to actual controller scope")
	suite.assert_true(not refresh.focus_next.is_empty() and not refresh.focus_previous.is_empty(), "refresh participates in linked focus chain")
	var before: Dictionary = records.snapshot()
	suite.assert_true(main._sync_local_records().code == &"NO_SETTLED_RUN" and records.snapshot() == before, "refresh during the next Run cannot duplicate the recovered local record")
	await _dispose(main)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	records = main.get("_local_records")
	suite.assert_true(records != null and records.snapshot() == before, "fresh actual Main startup authenticates and reloads local record")
	for locale: String in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		hub = main.get_node("HubFlowCoordinator")
		suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("mirror").ok, "localized mirror opens")
		_action(hub, "provider_refresh:leaderboard").pressed.emit()
		suite.assert_true(_action(hub, "provider_refresh:leaderboard").text != "UI_COMMUNITY_REFRESH", "native refresh label is translated")
		hub.close_panel()
	await _dispose(main)
	suite.finish(get_tree())


func _action(hub: Node, id: String) -> Button:
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
