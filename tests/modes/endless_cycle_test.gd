extends "res://tests/modes/endless_checkpoint_test.gd"

const Phase := preload("res://scripts/application/run_phase.gd")
const Endless := preload("res://scripts/modes/endless_session.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var fixture := _fixture("cycle")
	var source_before: Dictionary = fixture.service.snapshot()
	var flow := _flow(fixture)
	_suite.assert_true(flow.start(REQUEST).ok, "actual Endless cycle starts")
	var native_completed := await _complete_cycle(flow)
	_suite.assert_true(native_completed, "actual Health deaths and production routes clear all five Endless floors")
	flow._process(0.0)
	var state: Dictionary = flow.snapshot()
	_suite.assert_equal(state.status, "CYCLE_CLEAR", "actual final Boss produces durable cycle summary")
	_suite.assert_true(not flow.has_pending_save() and state.completed_cycles.size() == 1 and Endless.valid(state, "endless_owner"), "native five-floor cycle summary validates: " + str(flow.save_error()))
	if state.status == "CYCLE_CLEAR":
		var build: Dictionary = flow.runtime_host().native_run_state().reward_replay_build_snapshot()
		var player: Dictionary = flow.current_player().reward_effect_snapshot()
		_suite.assert_true(not build.reward_history.is_empty(), "real cycle acquires production reward Build")
		var next: Dictionary = flow.next_cycle()
		_suite.assert_true(next.ok, "next native cycle preserves real Build with a durable checkpoint: " + str(next))
		if next.ok:
			_suite.assert_equal(flow.snapshot().cycle_index, 1, "five-floor victory advances exactly one cycle")
			_suite.assert_equal(flow.runtime_host().native_run_state().reward_replay_build_snapshot(), build, "new native dungeon carries exact typed Build")
			_suite.assert_equal(flow.current_player().reward_effect_snapshot(), player, "new native dungeon carries physical HP time and weapon state")
			_suite.assert_equal(flow.runtime_host().runtime_snapshot().run_seed, Endless.cycle_seed(int(REQUEST.seed), 1), "next cycle uses its declared deterministic seed")
			await _check_native_scaling(flow)
			var saved: Dictionary = flow.save_and_return()
			_suite.assert_true(saved.ok, "carried-build native combat saves physically: " + str(saved))
			await _dispose(flow)
			flow = _flow(fixture)
			var continued: Dictionary = flow.continue_session()
			_suite.assert_true(continued.ok, "fresh second cycle rebuilds native scaled combat: " + str(continued))
			if continued.ok:
				_suite.assert_true(Rules.same(flow.runtime_host().native_run_state().reward_replay_build_snapshot(), build), "second cycle physical JSON restore retains canonical inherited Build")
				_suite.assert_equal(flow.snapshot().cycle_index, 1, "cold restore retains absolute cycle identity")
		_suite.assert_equal(fixture.service.snapshot(), source_before, "complete Endless cycle never settles source Profile")
		_check_long_history(state)
	await _dispose(flow)
	_suite.finish(get_tree())


func _complete_cycle(flow: Node) -> bool:
	var host: Node = flow.runtime_host()
	var dungeon: Node = flow.dungeon_flow()
	var player: Node = flow.current_player()
	var controller: Node = host.native_checkpoint_participants().controller
	for _step: int in range(6000):
		_freeze(flow)
		dungeon.refresh(true)
		var state: Dictionary = host.runtime_snapshot()
		if int(state.phase) == Phase.Value.VICTORY:
			return state.completed_floor_ids.size() == 5
		if Phase.is_terminal(int(state.phase)):
			return false
		var choice: Control = host.choice_panel()
		var panel: Control = dungeon.active_panel()
		if choice.visible:
			var buttons: Array = choice._option_buttons()
			if buttons.is_empty():
				return false
			buttons[0].pressed.emit()
			if choice.replacement_panel.visible:
				choice._on_replacement_confirmed()
		elif panel != null:
			var actions: Array = panel.action_controls()
			var selected: Button = null
			for action: Button in actions:
				if not action.disabled and (selected == null or str(action.get_meta("action_id", "")) in ["decline", "leave"]):
					selected = action
			if selected == null:
				return false
			selected.pressed.emit()
			if int(host.runtime_snapshot().revision) <= int(state.revision):
				return false
		else:
			for actor: Node in controller.get_node("Enemies").get_children():
				var health := actor.get_node_or_null("HealthComponent")
				if health != null and not health.dead:
					health.lose_health(1000000.0, player)
			if int(host.runtime_snapshot().phase) in [Phase.Value.COMBAT_ACTIVE, Phase.Value.BOSS_ACTIVE]:
				if not player.advance_action_frame():
					return false
		_freeze(flow)
		await get_tree().physics_frame
	print("Endless cycle stalled: ", host.runtime_snapshot(), " native: ", controller.encounter_runner().snapshot())
	return false


func _freeze(flow: Node) -> void:
	flow.set_process(false)
	flow.runtime_host().set_process(false)
	flow.dungeon_flow().set_process(false)
	var player: Node = flow.current_player()
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)


func _check_native_scaling(flow: Node) -> void:
	_freeze(flow)
	var host: Node = flow.runtime_host()
	for route: Dictionary in host.route_choices():
		if route.room_type in ["combat", "elite"]:
			_suite.assert_true(host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok, "second cycle enters real combat")
			break
	_freeze(flow)
	host.set_dungeon_selection_safety(false)
	var player: Node = flow.current_player()
	var runner: Node = host.native_checkpoint_participants().controller.encounter_runner()
	for _frame: int in range(120):
		if runner.alive_count() > 0:
			break
		_suite.assert_true(player.advance_action_frame(), "scaled native encounter accepts frame")
		await get_tree().physics_frame
	var enemies: Array[Node] = host.native_checkpoint_participants().controller.get_node("Enemies").get_children()
	_suite.assert_true(not enemies.is_empty(), "second cycle binds actual scaled native Actor")
	if not enemies.is_empty():
		var actor := enemies[0]
		var definition: Dictionary = host.native_checkpoint_participants().facade.encounter_catalog().enemy_definition(str(actor.get_meta("encounter_enemy_id")))
		_suite.assert_true(is_equal_approx(float(actor.health.max_hp), float(definition.max_hp) * 1.15), "cycle scaling applies before native physical Actor binding")


func _check_long_history(first: Dictionary) -> void:
	var candidate := first.duplicate(true)
	candidate.cycle_index = 40
	candidate.elapsed_frames = 410
	candidate.cycle_frames = 10
	candidate.completed_cycles.clear()
	for cycle: int in range(9, 41):
		candidate.completed_cycles.append({"cycle_index": cycle, "seed": Endless.cycle_seed(int(candidate.request.seed), cycle), "frames": 10, "final_floor_rooms": 5, "native_digest": "f".repeat(64)})
	_suite.assert_true(Endless.valid(candidate, "endless_owner"), "post-160-floor history rolls with absolute cycle indices")
	candidate.completed_cycles[0].cycle_index = 8
	_suite.assert_true(not Endless.valid(candidate, "endless_owner"), "rolling cycle history refuses reordered absolute identity")
