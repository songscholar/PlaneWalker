extends "res://tests/integration/save/narrative_profile_service_test.gd"

const MainScene := preload("res://scenes/main.tscn")
const NativeRoute := preload("res://tests/support/native_launch_route_fixture.gd")
var _main: Node
var _flow: Node
var _host: Node
var _room_host: Node
var _settlement_fault := false


func _run() -> void:
	suite = Suite.new()
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_flow = _main.get_node_or_null("NarrativeFlow")
	suite.assert_true(_flow != null, "production Main owns the native final-fragment, ending and credits flow")
	if _flow == null:
		await _finish()
		return
	_service = GameState.profile_runtime_service()
	_host = _main.get_node("RunRuntimeHost")
	_room_host = _main.get_node("LaunchRoomSceneHost")
	_player = _main.get_node("CombatRoom01/Player")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 73}
	suite.assert_true(_main._launch_run(config, false, true), "Main starts one durable actual Launch")
	_run_state = _host.native_run_state()
	NativeRoute.freeze(_main)
	_run_state.run_time_ms = 1000
	var reached: bool = await NativeRoute.reach(_main, suite, true)
	suite.assert_true(reached, "terminal fixture uses canonical native room, reward and floor handoffs")
	if not reached:
		await _finish()
		return
	await get_tree().process_frame
	suite.assert_true(not _main.get_node("RunEndOverlay").visible, "victory preserves final room interaction instead of obscuring it with the summary overlay")
	suite.assert_true(not _main.return_to_hub(), "Main refuses Hub return before explicit saved ending and credits")
	suite.assert_equal(_service.snapshot().statistics.finished_runs, 0, "victory notification itself cannot settle the run")
	var occurrences: Array = _flow.get("_occurrences")
	suite.assert_true(occurrences.size() == 1, "Main's terminal handoff installs the issued physical final fragment")
	if occurrences.size() != 1:
		await _finish()
		return
	var heart: Area2D = occurrences[0].token.get_ref()
	suite.assert_true(not _main.get_node("CombatRoom01/Floor").visible, "native final room is not occluded by the legacy opaque floor")
	suite.assert_equal(_main.get_node("CombatRoom01/PixelCanvasCamera").zoom, Vector2.ONE, "native room uses its authored 640 by 360 canvas")
	suite.assert_true(not _host.get("_hud_layer").visible, "terminal fragment traversal exposes the room without combat HUD panels")
	await _capture("final-fragment")
	EventBus.run_ended.emit(str(_run_state.run_id), _run_state.result.duplicate(true), int(_run_state.revision))
	suite.assert_equal(_flow.get("_occurrences")[0].token.get_ref(), heart, "duplicate native victory preserves the live issued fragment")
	suite.assert_true(not _main.get_node("RunEndOverlay").visible, "duplicate native victory cannot obscure the final fragment")
	_player.global_position = heart.global_position + Vector2(-100, 0)
	await get_tree().physics_frame
	var native_before: Dictionary = _player.full_player_replay_snapshot()
	var domain_before: Dictionary = _run_state.snapshot()
	Input.action_press("move_right")
	for _frame: int in range(8):
		_flow._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	var native_after: Dictionary = _player.full_player_replay_snapshot()
	suite.assert_true(native_after.player_state.position != native_before.player_state.position, "terminal traversal moves the real Player")
	native_before.player_state.erase("position")
	native_after.player_state.erase("position")
	suite.assert_equal(native_after, native_before, "terminal traversal advances no gameplay participant")
	suite.assert_equal(_run_state.snapshot(), domain_before, "terminal traversal advances no Run clock")
	_player.global_position = heart.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(_flow.process_pending_contact().ok, "Main's final fragment requires actual Area2D contact")
	_action("continue").pressed.emit()
	suite.assert_equal(_flow.panel().view_state().mode, "ending", "saved final fragment presents authored ending selection")
	await _capture("ending-choice")
	_service.get("_save").set_fault_injector(_native_fault)
	_settlement_fault = true
	_action("ending:shattered_freedom").pressed.emit()
	suite.assert_true(_service.snapshot().narrative_state.endings.has("shattered_freedom"), "ending choice saves before Main attempts settlement")
	suite.assert_equal(_service.snapshot().statistics.finished_runs, 0, "failed physical settlement cannot publish statistics")
	suite.assert_true(not _service.snapshot().active_launch_receipt.is_empty(), "settlement failure retains the actual launch")
	suite.assert_true(not _main.return_to_hub(), "failed victory settlement remains recoverable")
	await _capture("settlement-retry")
	_settlement_fault = false
	_main.get_node("RunEndOverlay/Panel/Margin/VBox/RestartButton").pressed.emit()
	suite.assert_equal(_service.snapshot().statistics.finished_runs, 1, "native retry settles the saved victory exactly once")
	suite.assert_equal(_service.snapshot().statistics.victories, 1, "actual victory persists its statistics")
	suite.assert_true(_service.snapshot().active_launch_receipt.is_empty(), "successful victory settlement retires the launch")
	suite.assert_equal(_flow.panel().view_state().mode, "credits", "successful Main retry opens the selected authored credits")
	await _capture("selected-credits")
	suite.assert_true(not _main.return_to_hub(), "uncompleted credits remain a separate required durable step")
	var before: Dictionary = _service.snapshot()
	_fault = &"before_primary_promote"
	_action("credits:shattered_freedom").pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "failed credits promotion cannot return to Hub")
	suite.assert_true(not _main.get_node("HubFlowCoordinator").is_hub_visible(), "credits save failure keeps the native ending recoverable")
	_fault = &""
	_service.get("_save").set_fault_injector(Callable())
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.set("_profile_runtime", null)
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_service = GameState.profile_runtime_service()
	_flow = _main.get_node("NarrativeFlow")
	suite.assert_equal(_flow.panel().view_state().mode, "credits", "a fresh Main and physical Profile reload resume unfinished selected credits")
	suite.assert_true(not _main.get_node("HubFlowCoordinator").is_hub_visible(), "native restart keeps unfinished credits actionable")
	suite.assert_equal(_service.snapshot().launch_sequence, 1, "credits restart cannot prepare a second launch")
	suite.assert_equal(_service.snapshot().statistics.finished_runs, 1, "credits restart cannot settle again")
	await _capture("reloaded-credits")
	_action("credits:shattered_freedom").pressed.emit()
	suite.assert_true(_service.snapshot().narrative_state.credits_completed.has("shattered_freedom"), "native credits complete as a separately persisted fact")
	suite.assert_true(_main.get_node("HubFlowCoordinator").is_hub_visible(), "saved credits return to the native Hub")
	suite.assert_equal(GameState.persistent.meta_profile_state, _service.snapshot(), "credits refresh the production Profile mirror")
	suite.assert_equal(_service.snapshot().statistics.finished_runs, 1, "native handoffs cannot settle victory twice")
	await _capture("returned-hub")
	await _finish()


func _native_fault(point: StringName) -> bool:
	return point == &"before_primary_promote" and _settlement_fault and not _service.snapshot().narrative_state.endings.is_empty() or point == _fault


func _action(id: String) -> Button:
	for control: Control in _flow.panel().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _install_actual_room(templates: Array) -> void:
	var node: Dictionary = _run_state.current_floor_node()
	for template: Dictionary in templates:
		if template.id != node.template_id:
			continue
		var preview: Node = load(template.scene_path).instantiate()
		var presentation: Dictionary = preview.FLOOR_PRESENTATION[_run_state.floor_plan.floor_id]
		preview.free()
		suite.assert_true(_room_host.transition_to(node, template, {"floor_id": _run_state.floor_plan.floor_id, "palette_id": presentation.palette_id, "environment_rule_id": presentation.environment_rule_id, "room_seed": 73}).ok, "native final flow uses an actual generated room scene")
		var active: Node2D = _room_host.active_room()
		suite.assert_equal(_player.global_position, active.get_node("PlayerEntry").global_position, "production room entry uses the current authored Player anchor")
		suite.assert_equal(_main.get_node("CombatRoom01/PixelCanvasCamera").global_position, active.get_node("CameraBounds").global_position, "production camera frames the actual current room")
		suite.assert_equal(_main.get_node("CombatRoom01/ArenaBounds/LeftWall").collision_layer, 0, "legacy walls cannot obstruct native room coordinates")


func _finish() -> void:
	Input.action_release("move_right")
	get_tree().paused = false
	if _service != null:
		_service.get("_save").set_fault_injector(Callable())
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_flow = null
	_run_state = null
	_player = null
	_service = null
	suite.finish(get_tree())


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var root := "res://build/visual-evidence/p16-main-narrative"
	DirAccess.make_dir_recursive_absolute(root)
	get_viewport().get_texture().get_image().save_png(root.path_join(stage + ".png"))
