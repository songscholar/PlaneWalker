extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
var suite: RefCounted
var _main: Node
var _flow: Node
var _host: Node
var _player: Node
var _service: RefCounted
var _save: RefCounted
var _fault := false
var _drift_on_promote := false
var _before_promote: Dictionary = {}
var _training: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var path := "res://scripts/onboarding/tutorial_flow_coordinator.gd"
	suite.assert_true(ResourceLoader.exists(path), "native tutorial flow must connect actual Main participants")
	if not ResourceLoader.exists(path):
		suite.finish(get_tree())
		return
	_main = Main.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_host = _main.get_node("RunRuntimeHost")
	_player = _main.get_node("CombatRoom01/Player")
	_service = GameState.profile_runtime_service()
	_save = _service.get("_save")
	_flow = _main.get_node_or_null("TutorialFlow")
	if _flow == null:
		_flow = load(path).new()
		_main.add_child(_flow)
	_flow.set_process(false)
	var remap: RefCounted = _main.get_node("InputRemapLayer/InputRemapPanel").get("_service")
	var configured: Dictionary = _flow.configure(_host.content_registry(), _service, _host, _player, remap)
	suite.assert_true(configured.ok, "flow configures once from actual Registry and durable Profile")
	if not configured.ok:
		await _finish()
		return
	_flow.training_requested.connect(func(id: StringName, revision: int) -> void: _training.append([id, revision]))
	var before: Dictionary = _service.snapshot()
	suite.assert_true(_flow.open_review("controller").ok, "Hub opens controller-accessible review without launching a run")
	var panel: Control = _flow.review_panel()
	suite.assert_equal(_service.snapshot(), before, "review and recall cannot change physical Profile")
	suite.assert_true(panel.view_state().training_available and not panel.view_state().guided_available and not panel.view_state().mode_change_available, "Hub training remains distinct from unavailable frozen guided policy")
	suite.assert_true(_action(panel, "tutorial_mode") == null, "production review cannot offer an unfrozen guided selector")
	await _capture("hub-controller-review")
	var remapped := InputEventKey.new()
	remapped.physical_keycode = KEY_K
	suite.assert_true(remap.remap(&"dash", "keyboard_mouse", remapped).ok, "actual remap persists native dash binding")
	_flow.open_review("keyboard_mouse")
	suite.assert_equal(panel.view_state().lessons[0].actions[1].bindings[0].labels, ["K"], "open native review refreshes actual committed InputMap labels")
	suite.assert_true(remap.reset_action(&"dash").ok, "actual dash binding restores after remap verification")
	_action(panel, "training:T-01").pressed.emit()
	suite.assert_equal(_training, [[&"T-01", int(before.revision)]], "native training request forwards exact task and Profile revision")
	suite.assert_true(_main.get_node("TrainingFlow").is_training_active(), "tutorial request opens actual Main training flow")
	_main.get_node("TrainingFlow").close()
	suite.assert_true(_flow.open_review("keyboard_mouse").ok, "actual training return reopens current tutorial commands")
	panel.show_rejection("UI_TUTORIAL_RETRY")
	_save.set_fault_injector(_inject_fault)
	_fault = true
	_action(panel, "skip:movement_dodge").pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "failed physical skip keeps authoritative Profile unchanged")
	suite.assert_true(not _action(panel, "skip:movement_dodge").disabled, "failed skip remains retryable through actual panel")
	_fault = false
	_action(panel, "skip:movement_dodge").pressed.emit()
	suite.assert_true(_service.snapshot().tutorial_state.skipped_lessons.has("movement_dodge"), "retry persists actual tutorial skip")
	before = _service.snapshot()
	_fault = true
	var toggle: CheckBox = _action(panel, "tutorial_hints")
	toggle.button_pressed = false
	toggle.pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "failed hint preference cannot mutate Profile")
	suite.assert_true(toggle.button_pressed and not toggle.disabled, "failed suppression restores saved preference and retry control")
	_fault = false
	toggle.button_pressed = false
	toggle.pressed.emit()
	suite.assert_true(_service.snapshot().tutorial_state.suppressed, "retry persists actual hint suppression")
	toggle = _action(panel, "tutorial_hints")
	toggle.button_pressed = true
	toggle.pressed.emit()
	_flow.close()
	suite.assert_true(not get_tree().paused, "Hub review close does not acquire a gameplay pause")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261008}
	suite.assert_true(_main._launch_run(config, false, true), "actual Main starts durable native tutorial run")
	var routes: Array = _host.route_choices()
	if not routes.is_empty():
		suite.assert_true(_host.select_route(StringName(routes[0].edge_id), _host.runtime_snapshot().revision).ok, "actual tutorial enters a native room")
		_main.get_node("DungeonFlow").refresh(true)
	_host.set_process(false)
	_player.set_physics_process(false)
	_main.get_node("CombatRoom01").process_mode = Node.PROCESS_MODE_DISABLED
	suite.assert_true(_flow.bind_active_run().ok, "actual Host-owned Player binds service-issued adapter")
	var adapter: RefCounted = _flow.get("_adapter")
	_advance()
	suite.assert_equal(adapter.pending_observations().size(), 1, "authentic native entry queues exactly one teaching observation")
	before = _service.snapshot()
	_fault = true
	var refused: Dictionary = _flow.process_pending_observations()
	suite.assert_true(not refused.ok, "physical hint save failure is surfaced")
	suite.assert_equal(_service.snapshot(), before, "failed observation cannot advance Profile")
	suite.assert_true(not _flow.hint_presenter().visible and adapter.pending_observations().size() == 1, "failed save cannot display or consume queued hint")
	_fault = false
	get_tree().paused = true
	_flow.process_pending_observations()
	suite.assert_equal(adapter.pending_observations().size(), 1, "externally paused scene cannot drain native observations")
	suite.assert_true(_flow.open_review("controller").ok, "existing pause permits native controller review")
	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	cancel.pressed = true
	suite.assert_true(_flow.handle_input(cancel), "controller cancel closes current native review")
	suite.assert_true(get_tree().paused, "closing review preserves external pause ownership")
	get_tree().paused = false
	suite.assert_true(_flow.open_review().ok, "active gameplay can open review with an owned pause")
	suite.assert_true(get_tree().paused and _host.runtime_snapshot().suspended, "review pauses actual tree and domain together")
	_flow.process_pending_observations()
	suite.assert_equal(adapter.pending_observations().size(), 1, "review modal cannot drain native observations")
	_flow.close()
	suite.assert_true(not get_tree().paused and not _host.runtime_snapshot().suspended, "close resumes the same actual participants when review owns pause")
	var saved: Dictionary = _flow.process_pending_observations()
	suite.assert_true(saved.ok and saved.context.consumed, "native entry retry persists once before publication")
	suite.assert_true(_before_promote.get("hint_visible", true) == false and _before_promote.profile.revision == before.revision, "physical promotion begins before saved hint or Profile publication")
	suite.assert_true(_flow.hint_presenter().visible and adapter.pending_observations().is_empty(), "successful physical observation publishes actual authored hint")
	await _capture("actual-saved-entry-hint")
	var durable = _save.inspect_profile("slot_1", "base")
	suite.assert_equal(durable.payload.payload.meta_profile_state, JSON.parse_string(JSON.stringify(_service.snapshot())), "hint observes the already durable physical Profile")
	var after: Dictionary = _service.snapshot()
	_flow.process_pending_observations()
	suite.assert_equal(_service.snapshot(), after, "empty adapter cannot resend a saved hint")
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	suite.assert_true(_flow.handle_input(key) and panel.visible, "F1 opens actual native review")
	suite.assert_true(not panel.view_state().training_available, "active run prevents training transition")
	_flow.close()
	_flow.hint_presenter().clear_context()
	_player.health.current_hp = _player.health.max_hp * 0.4
	_advance()
	suite.assert_equal(adapter.pending_observations().size(), 1, "actual native low-health edge queues an authored hint")
	var saved_player: Dictionary = _player.reward_effect_snapshot()
	_drift_on_promote = true
	var drifted: Dictionary = _flow.process_pending_observations()
	_drift_on_promote = false
	suite.assert_equal(drifted.code, &"NATIVE_PUBLICATION_PENDING", "native callback drift surfaces physical publication recovery")
	suite.assert_true(not _flow.hint_presenter().visible, "publication recovery never exposes an uncertain saved hint")
	var recovery_revision: int = _service.snapshot().revision
	suite.assert_true(_flow.recover_active_run().ok, "coordinator restores actual saved participants through the physical service")
	suite.assert_equal(_player.reward_effect_snapshot(), saved_player, "recovery restores the complete saved native Player participant")
	suite.assert_true(_flow.get("_adapter") != adapter and adapter.pending_observations().is_empty(), "recovery replaces and retires old observer")
	adapter = _flow.get("_adapter")
	suite.assert_equal(_service.snapshot().revision, recovery_revision, "native recovery cannot award another tutorial revision")
	_player.health.current_hp = _player.health.max_hp
	_advance()
	_player.health.current_hp = _player.health.max_hp * 0.4
	_advance()
	adapter.observation_saved.connect(func(_receipt: Dictionary) -> void: adapter.detach(), CONNECT_ONE_SHOT)
	var detached: Dictionary = _flow.process_pending_observations()
	suite.assert_equal(detached.code, &"NATIVE_PUBLICATION_PENDING", "saved callback adapter detachment retains physical recovery")
	_flow.process_pending_observations()
	suite.assert_true(_flow.get("_run") == _host.native_run_state() and not _flow.hint_presenter().visible, "automatic drain retains current participants during publication recovery")
	suite.assert_equal(_flow.bind_active_run().code, &"NATIVE_PUBLICATION_PENDING", "rebind cannot erase the current physical recovery context")
	suite.assert_true(_flow.recover_active_run().ok, "coordinator can recover service-issued adapter detached during saved callback")
	adapter = _flow.get("_adapter")
	_player.health.current_hp = _player.health.max_hp
	_advance()
	_player.health.current_hp = _player.health.max_hp * 0.4
	_advance()
	adapter.observation_saved.connect(func(_receipt: Dictionary) -> void: _flow.retire_active_run(), CONNECT_ONE_SHOT)
	var stale: Dictionary = _flow.process_pending_observations()
	suite.assert_equal(stale.code, &"TUTORIAL_CONTEXT_CHANGED", "retirement during physical saved callback rejects late presentation")
	suite.assert_true(not _flow.hint_presenter().visible, "old saved callback cannot publish a hint after coordinator retirement")
	suite.assert_true(_flow.bind_active_run().ok, "native observer can rebind after settled callback retirement")
	adapter = _flow.get("_adapter")
	after = _service.snapshot()
	var generation: int = _player.owner_character_generation()
	_player.set("_owner_character_generation", generation + 1)
	_flow.process_pending_observations()
	suite.assert_true(not _flow.hint_presenter().visible and adapter.pending_observations().is_empty(), "replaced Player generation retires old hint and observer")
	suite.assert_equal(_service.snapshot(), after, "stale generation cannot change tutorial progress")
	_player.set("_owner_character_generation", generation)
	suite.assert_true(_flow.bind_active_run().ok, "actual participants can bind a fresh observer after generation test")
	adapter = _flow.get("_adapter")
	adapter.detach()
	_flow.process_pending_observations()
	suite.assert_true(_flow.get("_adapter") == null, "an externally retired service-issued adapter cannot remain presentation-active")
	await _finish()


func _inject_fault(point: StringName) -> bool:
	if point == &"before_primary_promote":
		_before_promote = {"profile": _service.snapshot(), "hint_visible": _flow.hint_presenter().visible}
		if _drift_on_promote:
			_player.health.current_hp -= 1.0
	return _fault and point == &"before_primary_promote"


func _advance() -> void:
	var frame: int = int(_player.priority_arbitration_snapshot().frame) + 1
	suite.assert_true(_player.advance_action_frame({"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.ZERO, "aim": Vector2.RIGHT, "meta": {"source": "tutorial_flow_test", "target_frame": frame, "frame": frame}}), "actual Player authoritative frame commits")


func _action(panel: Node, id: String) -> Button:
	for control: Control in panel.action_controls():
		if control.get_meta("action_id", "") == id:
			return control as Button
	return null


func _capture(name: String) -> void:
	var directory := OS.get_environment("PLANEWALKER_UI_VISUAL_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = get_viewport().get_texture().get_image()
	suite.assert_true(rendered != null and not rendered.is_empty(), "actual native tutorial flow renders pixels")
	if rendered == null or rendered.is_empty():
		return
	var colors: Dictionary = {}
	for y: int in range(0, rendered.get_height(), 8):
		for x: int in range(0, rendered.get_width(), 8):
			colors[rendered.get_pixel(x, y).to_rgba32()] = true
	suite.assert_true(colors.size() > 8, "actual native tutorial flow render is nonblank")
	suite.assert_equal(rendered.save_png(directory.path_join(name + ".png")), OK, "actual native flow screenshot saves")


func _finish() -> void:
	get_tree().paused = false
	if _save != null:
		_save.set_fault_injector(Callable())
	if _flow != null:
		_flow.retire_active_run()
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_flow = null
	_host = null
	_player = null
	_service = null
	_save = null
	suite.finish(get_tree())
