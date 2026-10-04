extends "res://tests/integration/save/narrative_profile_service_test.gd"

const MainScene := preload("res://scenes/main.tscn")
const Contract := preload("res://scripts/ui/contracts/narrative_view_state.gd")
var _main: Node
var _flow: Node
var _host: Node
var _room_host: Node
var _runtime_parent: Node2D
var _ending_signals: Array = []
var _credit_signals: Array = []
var _retire_on_promote := false


func _run() -> void:
	suite = Suite.new()
	var path := "res://scripts/narrative/narrative_flow_coordinator.gd"
	suite.assert_true(ResourceLoader.exists(path), "native narrative coordinator must connect actual issued heart contact, ending and credits")
	if not ResourceLoader.exists(path):
		suite.finish(get_tree())
		return
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_host = _main.get_node("RunRuntimeHost")
	_room_host = _main.get_node("LaunchRoomSceneHost")
	_player = _main.get_node("CombatRoom01/Player")
	_service = GameState.profile_runtime_service()
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 73}
	suite.assert_true(_main._launch_run(config, false, true), "actual Main issues a durable Launch receipt")
	_run_state = _host.native_run_state()
	_host.set_process(false)
	_player.set_physics_process(false)
	_main.get_node("CombatRoom01").process_mode = Node.PROCESS_MODE_DISABLED
	var tutorial: Node = _main.get_node_or_null("TutorialFlow")
	if tutorial != null:
		tutorial.set_process(false)
	var production_flow: Node = _main.get_node_or_null("NarrativeFlow")
	if production_flow != null:
		production_flow.set_physics_process(false)
		production_flow.retire_active_run()
	_runtime_parent = Node2D.new()
	_main.add_child(_runtime_parent)
	_flow = load(path).new()
	_main.add_child(_flow)
	_flow.set_physics_process(false)
	var configured: Dictionary = _flow.configure(_host.content_registry(), _service, _host, _room_host, _player, _runtime_parent)
	suite.assert_true(configured.ok, "narrative flow uses actual Main, Host, Registry, Player and RoomSceneHost")
	if not configured.ok:
		await _finish()
		return
	suite.assert_true(_flow.bind_active_run().ok, "actual native Run has one service-issued narrative binding")
	_flow.ending_selected.connect(func(id: String, receipt: Dictionary): _ending_signals.append([id, receipt]))
	_flow.credits_completed.connect(func(id: String, receipt: Dictionary): _credit_signals.append([id, receipt]))
	_service.get("_save").set_fault_injector(_flow_fault)
	var before: Dictionary = _service.snapshot()
	suite.assert_true(_flow.open_dialogue("phia").ok, "native Hub dialogue projects authored replies")
	var panel: Control = _flow.panel()
	var state: Dictionary = panel.view_state()
	suite.assert_true(Contract.validate(state).ok, "strict native dialogue view validates")
	var leaked := state.duplicate(true)
	leaked.profile = before
	suite.assert_true(not Contract.validate(leaked).ok, "presentation rejects injected complete Profile")
	var reply := _action("dialogue:phia_intro:phia_intro_remember")
	suite.assert_true(reply != null, "actual authored intro reply is keyboard/controller focusable")
	var old_callback: Callable = reply.pressed.get_connections()[0].callable
	_fault = &"before_primary_promote"
	reply.pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "failed physical dialogue cannot publish affinity")
	suite.assert_true(not _action("dialogue:phia_intro:phia_intro_remember").disabled, "failed native reply remains retryable")
	_fault = &""
	reply.pressed.emit()
	suite.assert_true(_service.snapshot().narrative_state.consumed_sources.has("dialogue:phia_intro"), "native reply persists its one authored source")
	before = _service.snapshot()
	old_callback.call()
	suite.assert_equal(_service.snapshot(), before, "retired native dialogue callback cannot write twice")
	await _capture("dialogue-saved")
	_flow.close()
	suite.assert_true(_flow.open_dialogue("odysseus").ok, "second NPC opens from current Profile")
	var stale_revision: int = panel.view_state().revision
	suite.assert_true(_service.execute_narrative({"command_id": "external-elara-intro", "kind": "narrative_dialogue", "npc_id": "elara", "node_id": "elara_intro", "choice_id": "elara_intro_remember"}, stale_revision).ok, "independent real Profile command advances the open panel revision")
	before = _service.snapshot()
	_action("dialogue:odysseus_intro:odysseus_intro_remember").pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "old NPC controls refuse stale Profile revision")
	suite.assert_equal(panel.view_state().revision, before.revision, "stale refusal refreshes authoritative native controls")
	_action("dialogue:odysseus_intro:odysseus_intro_remember").pressed.emit()
	suite.assert_true(_service.snapshot().narrative_state.consumed_sources.has("dialogue:odysseus_intro"), "refreshed NPC controls remain usable after stale refusal")
	_flow.close()
	suite.assert_true(not _flow.terminal_victory().ok, "active nonterminal Run cannot install final heart or choose ending")
	var templates := _content("room_templates.json")
	var floors := _content("floors.json")
	var launch: Dictionary = _service.snapshot().active_launch_receipt
	# The existing authenticated deterministic fixture traverses real generated nodes and boss receipts.
	_run_state.floor_rule_state = {}
	for index: int in range(5):
		if index > 0:
			_enter_floor(floors[index], templates)
		_complete_floor(launch)
		_run_state.phase = Phase.Value.RUN_PREPARING if index < 4 else Phase.Value.VICTORY
		_install_actual_room(templates)
		if index == 0:
			suite.assert_true(_flow.refresh_occurrences().ok, "cleared actual room installs floor-authored physical markers")
			var records: Array = _flow.get("_occurrences")
			suite.assert_true(not records.is_empty(), "actual cleared room exposes authored collect/choice occurrences")
			if not records.is_empty():
				var token: Area2D = records[0].token.get_ref()
				_player.global_position = token.global_position + Vector2(-100, 0)
				await get_tree().physics_frame
				before = _service.snapshot()
				suite.assert_true(not _flow.process_pending_contact().context.get("consumed", false), "distance without real overlap cannot mint a source")
				suite.assert_equal(_service.snapshot(), before, "no-contact native frame leaves physical Profile unchanged")
				_player.global_position = token.global_position
				await get_tree().physics_frame
				await get_tree().physics_frame
				_fault = &"before_primary_promote"
				suite.assert_true(not _flow.process_pending_contact().ok, "physical source save refusal is surfaced")
				suite.assert_equal(_service.snapshot(), before, "failed contact does not grant authored content")
				_fault = &""
				suite.assert_true(_flow.process_pending_contact().ok and _service.snapshot().revision == before.revision + 1, "real contact retries once through production Profile service")
				suite.assert_equal(panel.view_state().mode, "story", "saved physical collection opens authored story only after persistence")
				var story: Dictionary = panel.view_state()
				suite.assert_true(_service.execute_narrative({"command_id": "normal-story-concurrent-sibyl", "kind": "narrative_dialogue", "npc_id": "sibyl", "node_id": "sibyl_intro", "choice_id": "sibyl_intro_remember"}, story.revision).ok, "real independent Profile command advances an open source story")
				before = _service.snapshot()
				_action("continue").pressed.emit()
				suite.assert_equal(_service.snapshot(), before, "ordinary stale story continuation cannot write")
				suite.assert_true(panel.view_state().revision == before.revision and panel.view_state().subject_id == story.subject_id and panel.view_state().text_key == story.text_key and panel.view_state().close_available, "ordinary stale story reprojects saved content at the authoritative revision")
				_flow.close()
				_flow.refresh_occurrences()
				var pending_records: Array = _flow.get("_occurrences")
				if not pending_records.is_empty():
					await get_tree().physics_frame
					await get_tree().physics_frame
					var original_reward: Dictionary = _player.reward_effect_snapshot()
					before = _service.snapshot()
					_drift_on_promote = true
					var pending: Dictionary = _flow.process_pending_contact()
					_drift_on_promote = false
					suite.assert_equal(pending.code, &"NATIVE_PUBLICATION_PENDING", "physical collection detects native callback drift")
					suite.assert_true(_service.snapshot().revision == before.revision + 1 and not panel.visible, "saved drifted collection publishes no unverified native story")
					suite.assert_true(not _flow.bind_active_run().ok, "rebind cannot discard an unrecovered physical checkpoint")
					var recovered: Dictionary = _flow.recover_active_run()
					suite.assert_true(recovered.ok, "actual saved native participants recover through coordinator: " + str(recovered))
					suite.assert_equal(_player.reward_effect_snapshot(), original_reward, "native recovery restores exact saved reward and health state")
				_flow._retire_occurrences()
				suite.assert_true(_flow._install("choice", "choice_nemesis_1", _flow._definition("choice_nemesis_1")).ok, "authored Nemesis choice installs at the same validated actual room anchor")
				await get_tree().physics_frame
				await get_tree().physics_frame
				var choice_contact: Dictionary = _flow.process_pending_contact()
				suite.assert_true(choice_contact.ok and panel.view_state().mode == "choice", "real native contact opens authored Nemesis choices: " + str(choice_contact))
				if _action("choice:spare") == null:
					await _finish()
					return
				before = _service.snapshot()
				_fault = &"before_primary_promote"
				_action("choice:spare").pressed.emit()
				suite.assert_equal(_service.snapshot(), before, "failed native choice publishes no affinity or faction change")
				_fault = &""
				_action("choice:spare").pressed.emit()
				suite.assert_true(_service.snapshot().narrative_state.nemesis_choices == ["spare"], "saved native choice records one authenticated encounter")
				_flow.close()
	_run_state.phase = Phase.Value.VICTORY
	_run_state.result = {"result": "victory"}
	_run_state.run_time_ms = 1000
	suite.assert_true(_flow.terminal_victory().ok, "canonical native five-floor victory installs final heart contact")
	suite.assert_true(not panel.visible and _ending_signals.is_empty(), "final fragment is neither automatically granted nor implicitly chosen")
	var heart: Area2D = _flow.get("_occurrences")[0].token.get_ref()
	await _capture("actual-heart-marker")
	_player.global_position = heart.global_position + Vector2(-100, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var position_before: Vector2 = _player.global_position
	var native_before: Dictionary = _player.full_player_replay_snapshot()
	var run_before: Dictionary = _run_state.snapshot()
	var reward_before: Dictionary = _player.reward_effect_snapshot()
	Input.action_press("move_right")
	for index: int in range(8):
		_flow._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	var native_after: Dictionary = _player.full_player_replay_snapshot()
	suite.assert_true(_player.global_position.x > position_before.x, "terminal traversal moves the actual CharacterBody through native collision")
	native_before.player_state.erase("position")
	native_after.player_state.erase("position")
	suite.assert_equal(native_after, native_before, "terminal movement advances no action, time, weapon, replay or health participant")
	suite.assert_equal(_run_state.snapshot(), run_before, "terminal traversal advances no domain gameplay frame")
	suite.assert_equal(_player.reward_effect_snapshot(), reward_before, "terminal traversal changes no reward participant")
	get_tree().paused = true
	position_before = _player.global_position
	Input.action_press("move_right")
	_flow._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	suite.assert_equal(_player.global_position, position_before, "external pause blocks terminal traversal")
	get_tree().paused = false
	_player.global_position = heart.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _flow.process_pending_contact().ok, "final native fragment physical save can refuse")
	suite.assert_equal(_service.snapshot(), before, "failed final fragment cannot unblock ending selection")
	_fault = &""
	suite.assert_true(_flow.process_pending_contact().ok, "actual final Area2D overlap persists the fifth heart")
	suite.assert_true(_service.snapshot().narrative_state.heart_fragments.has("floor_throne_of_void"), "durable fifth fragment uses authored floor identity")
	suite.assert_true(not panel.view_state().close_available and not panel.back_button.visible, "terminal saved fragment offers Continue without a Back escape")
	panel._request_close()
	suite.assert_true(panel.visible and panel.view_state().mode == "story", "terminal story Back/cancel cannot discard the explicit ending path")
	await _capture("terminal-story")
	var terminal_story: Dictionary = panel.view_state()
	suite.assert_true(_service.execute_narrative({"command_id": "terminal-story-concurrent-vera", "kind": "narrative_dialogue", "npc_id": "vera", "node_id": "vera_intro", "choice_id": "vera_intro_remember"}, terminal_story.revision).ok, "actual Profile can advance while the terminal story is open")
	before = _service.snapshot()
	_action("continue").pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "stale terminal story continuation cannot write")
	suite.assert_true(panel.visible and panel.view_state().revision == before.revision and not panel.view_state().close_available and not panel.back_button.visible, "terminal stale story retains protected Continue at the authoritative revision")
	_action("continue").pressed.emit()
	suite.assert_equal(panel.view_state().mode, "ending", "saved fifth heart exposes explicit ending choices")
	suite.assert_true(_action("ending:shattered_freedom") != null, "canonical fallback ending is selectable")
	await _capture("ending-choices")
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	_action("ending:shattered_freedom").pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "failed ending save preserves terminal choice")
	suite.assert_true(_ending_signals.is_empty(), "failed ending cannot signal settlement or credits")
	_fault = &""
	_retire_on_promote = true
	_action("ending:shattered_freedom").pressed.emit()
	_retire_on_promote = false
	suite.assert_true(_ending_signals.is_empty(), "detached save callback cannot emit completion from a retired native binding")
	suite.assert_true(_flow.bind_active_run().ok and _flow.terminal_victory().ok, "new actual binding recovers already saved ending handoff without a second choice")
	suite.assert_equal(_ending_signals.size(), 1, "saved ending emits exactly one native handoff")
	_flow.terminal_victory()
	suite.assert_equal(_ending_signals.size(), 1, "repeated terminal presentation cannot duplicate its saved handoff")
	suite.assert_true(not _flow.show_selected_credits("shattered_freedom").ok, "credits cannot begin before durable settlement")
	var receipts: Array = []
	for event: Dictionary in _run_state.events:
		if event.get("type") == Settlement.SOURCE_TYPE:
			receipts.append(event.receipt)
	suite.assert_true(_service.settle_terminal(_run_state.snapshot(), receipts, _service.snapshot().revision).ok, "actual terminal settles after saved narrative choice")
	suite.assert_true(_flow.show_selected_credits("shattered_freedom").ok, "separately saved credits begin only after settlement")
	await _capture("credits-pending")
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	_action("credits:shattered_freedom").pressed.emit()
	suite.assert_equal(_service.snapshot(), before, "failed credits save cannot report Hub completion")
	suite.assert_true(_credit_signals.is_empty(), "credits persistence failure emits no completion")
	_fault = &""
	_flow.close()
	suite.assert_true(_flow.resume_selected_credits().context.resumed, "settled physical Profile resumes unfinished selected credits")
	_action("credits:shattered_freedom").pressed.emit()
	suite.assert_equal(_credit_signals.size(), 1, "durable credits emit exactly one completion handoff")
	suite.assert_true(_service.snapshot().narrative_state.credits_completed.has("shattered_freedom"), "credits completion is a separate durable fact")
	suite.assert_true(not _flow.resume_selected_credits().context.resumed, "completed credits do not reopen after restart")
	await _finish()


func _install_actual_room(templates: Array) -> void:
	var node: Dictionary = _run_state.current_floor_node()
	for template: Dictionary in templates:
		if template.id != node.template_id:
			continue
		var preview: Node = load(template.scene_path).instantiate()
		var presentation: Dictionary = preview.FLOOR_PRESENTATION[_run_state.floor_plan.floor_id]
		preview.free()
		suite.assert_true(_room_host.transition_to(node, template, {"floor_id": _run_state.floor_plan.floor_id, "palette_id": presentation.palette_id, "environment_rule_id": presentation.environment_rule_id, "room_seed": 73}).ok, "narrative occurrence is installed by actual RoomSceneHost transition")


func _action(id: String) -> Button:
	for control: Control in _flow.panel().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _flow_fault(point: StringName) -> bool:
	if point == &"before_primary_promote" and _retire_on_promote:
		_flow.retire_active_run()
	return _inject_fault(point)


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/visual-evidence/p16o-native-narrative")
	get_viewport().get_texture().get_image().save_png("res://build/visual-evidence/p16o-native-narrative/%s.png" % name)
	var panel: Control = _flow.panel()
	if panel.visible:
		var locale := TranslationServer.get_locale()
		var state: Dictionary = panel.view_state()
		TranslationServer.set_locale("en")
		panel.close_panel()
		panel.render(state)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/visual-evidence/p16o-native-narrative/%s-en.png" % name)
		TranslationServer.set_locale(locale)
		panel.close_panel()
		panel.render(state)


func _finish() -> void:
	Input.action_release("move_right")
	get_tree().paused = false
	if _service != null:
		_service.get("_save").set_fault_injector(Callable())
	if is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_flow = null
	_run_state = null
	_player = null
	_service = null
	suite.finish(get_tree())
