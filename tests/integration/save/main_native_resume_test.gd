extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
var _fault := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	suite.assert_true(main.has_method("checkpoint_current_run"), "Main provides durable native checkpoint commands")
	if not main.has_method("checkpoint_current_run"):
		await _dispose(main)
		suite.finish(get_tree())
		return
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	suite.assert_true(main._launch_run(config, false, true), "actual Main prepares one launch")
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	_freeze(main)
	var service: RefCounted = GameState.profile_runtime_service()
	suite.assert_true(service.authenticated_native_checkpoint(int(service.snapshot().revision)).ok, "Main automatically retains the launch entrance")
	suite.assert_equal(player.global_position, Vector2(320, 180), "initial floor gateway uses the native canvas before a room is selected")
	player.global_position = Vector2(173, 229)
	var payload_before: Dictionary = service.payload()
	service.get("_save").set_fault_injector(_inject_fault)
	_fault = true
	suite.assert_true(not main.checkpoint_current_run().ok, "physical checkpoint failure is actionable and retains the prior durable checkpoint")
	suite.assert_equal(service.payload(), payload_before, "failed native checkpoint does not replace the physical Profile projection")
	_fault = false
	service.get("_save").set_fault_injector(Callable())
	suite.assert_true(main.checkpoint_current_run().ok, "retry persists the actual full native Player")
	var frame: int = int(player.priority_arbitration_snapshot().frame) + 1
	suite.assert_true(player.advance_action_frame({"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.ZERO, "aim": Vector2.RIGHT, "meta": {"source": "main_native_resume_test", "target_frame": frame, "frame": frame}}), "actual successful Player frame produces an authenticated tutorial observation")
	var observed: Dictionary = main.get_node("TutorialFlow").process_pending_observations()
	suite.assert_true(observed.ok and observed.context.get("consumed", false), "actual tutorial writes its durable observation")
	suite.assert_true(service.authenticated_native_checkpoint(int(service.snapshot().revision)).ok, "tutorial persistence preserves a complete atomic native checkpoint before another Main frame")
	var replay_before: Dictionary = player.full_player_replay_snapshot()
	var run_before: Dictionary = host.runtime_snapshot()
	var profile_before: Dictionary = service.snapshot()
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	_freeze(main)
	service = GameState.profile_runtime_service()
	var hub: Node = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.is_hub_visible(), "cold Main opens Hub with a resumable same launch")
	suite.assert_true(hub.open_function("gateway").ok, "actual gateway presents the saved run")
	var resume: Button = _action(hub, "resume")
	var launch: Button = _action(hub, "launch")
	suite.assert_true(resume != null and not resume.disabled, "actual gateway exposes an authenticated resume button")
	suite.assert_true(launch != null and launch.disabled, "active receipt cannot mint another launch")
	await _capture("resume-gateway")
	if resume != null and not resume.disabled:
		var retired_callback: Callable = resume.pressed.get_connections()[0].callable
		resume.pressed.emit()
		retired_callback.call()
		_freeze(main)
		host = main.get_node("RunRuntimeHost")
		player = main.get_node("CombatRoom01/Player")
		suite.assert_true(not hub.is_hub_visible() and main.get_node("CombatRoom01").visible, "native resume returns to the saved room")
		var replay_after: Dictionary = player.full_player_replay_snapshot()
		suite.assert_true(replay_after == replay_before, "presentation and binding preserve saved Player identity, position and clocks: " + str(_differences(replay_after, replay_before, "player")))
		suite.assert_true(_json_equal(host.runtime_snapshot(), run_before), "native resume restores the same canonical run")
		suite.assert_equal(service.snapshot().launch_sequence, profile_before.launch_sequence, "repeated retired control cannot spend another launch")
		suite.assert_equal(service.snapshot().statistics, profile_before.statistics, "resumption never publishes a terminal settlement")
		suite.assert_equal(service.snapshot(), profile_before, "Hub resumption does not revise the physical Profile")
		await _capture("restored-gateway")
	await _dispose(main)
	suite.finish(get_tree())


func _freeze(main: Node) -> void:
	main.get_node("RunRuntimeHost").set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _action(hub: Node, id: String) -> Button:
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))


func _differences(left: Variant, right: Variant, path: String) -> Array:
	var result: Array = []
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key):
				result.append(path + "." + str(key) + ": missing")
			else:
				result.append_array(_differences(left[key], right[key], path + "." + str(key)))
	elif left != right:
		result.append(path + ": " + str(left) + " != " + str(right))
	return result


func _inject_fault(stage: StringName) -> bool:
	return _fault and stage == &"before_primary_promote"


func _capture(name: String) -> void:
	var directory := OS.get_environment("PLANEWALKER_RESUME_CAPTURE_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))
