extends Node

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const RunRuntimeHostScript := preload("res://scripts/application/run_runtime_host.gd")
const RoomSceneHostScript := preload("res://scripts/dungeon/room_scene_host.gd")
const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)

const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


class RouteLifecycleRecorder:
	extends RefCounted

	var publication_order: Array[String] = []
	var run_started_events: Array[Dictionary] = []
	var route_events: Array[Dictionary] = []
	var room_started_events: Array[Dictionary] = []
	var room_cleared_events: Array[Dictionary] = []
	var floor_started_events: Array[Dictionary] = []
	var floor_completed_events: Array[Dictionary] = []
	var event_opened_events: Array[Dictionary] = []

	func record_run_started(run_id: String, snapshot: Dictionary) -> void:
		run_started_events.append({"run_id": run_id, "snapshot": snapshot.duplicate(true)})

	func record_route_selected(
		run_id: String,
		floor_id: StringName,
		edge_id: StringName,
		node_id: StringName,
		revision: int
	) -> void:
		publication_order.append("route_selected")
		route_events.append({
			"run_id": run_id,
			"floor_id": str(floor_id),
			"edge_id": str(edge_id),
			"node_id": str(node_id),
			"revision": revision,
		})

	func record_room_started(run_id: String, room_id: StringName, revision: int) -> void:
		publication_order.append("room_started")
		room_started_events.append({
			"run_id": run_id,
			"room_id": str(room_id),
			"revision": revision,
		})

	func record_event_opened(
		run_id: String,
		event_id: StringName,
		node_key: String,
		revision: int
	) -> void:
		publication_order.append("event_opened")
		event_opened_events.append({
			"run_id": run_id,
			"event_id": str(event_id),
			"node_key": node_key,
			"revision": revision,
		})

	func record_room_cleared(run_id: String, room_id: StringName, revision: int) -> void:
		room_cleared_events.append({
			"run_id": run_id,
			"room_id": str(room_id),
			"revision": revision,
		})

	func record_floor_started(
		run_id: String, floor_id: StringName, floor_index: int, revision: int
	) -> void:
		floor_started_events.append({
			"run_id": run_id,
			"floor_id": str(floor_id),
			"floor_index": floor_index,
			"revision": revision,
		})

	func record_floor_completed(
		run_id: String, floor_id: StringName, floor_index: int, revision: int
	) -> void:
		floor_completed_events.append({
			"run_id": run_id,
			"floor_id": str(floor_id),
			"floor_index": floor_index,
			"revision": revision,
		})


class AtomicRouteSceneAdapter:
	extends RefCounted

	var active_snapshot: Dictionary = {"content_id": "entry", "instance_generation": 1}
	var prior_snapshot: Dictionary = {}
	var prepared_ticket: Dictionary = {}
	var fail_prepare: bool = false
	var fail_commit: bool = false
	var fail_confirm: bool = false

	func prepare_route_transition(target: Dictionary, _context: Dictionary) -> Dictionary:
		if fail_prepare or not prepared_ticket.is_empty():
			return {"ok": false, "code": &"PREPARE_FAILED"}
		prior_snapshot = active_snapshot.duplicate(true)
		prepared_ticket = {
			"ticket_id": 1,
			"target_content_id": str(target.get("template_id", "")),
		}
		return {"ok": true, "ticket": prepared_ticket.duplicate(true)}

	func commit_route_transition(ticket: Dictionary, target: Dictionary, _context: Dictionary) -> Dictionary:
		if fail_commit or ticket != prepared_ticket:
			return {"ok": false, "code": &"COMMIT_FAILED"}
		active_snapshot = {
			"content_id": str(target.get("template_id", "")),
			"instance_generation": int(prior_snapshot.get("instance_generation", 0)) + 1,
		}
		return {"ok": true}

	func confirm_route_transition(ticket: Dictionary, _context: Dictionary) -> Dictionary:
		if fail_confirm or ticket != prepared_ticket:
			return {"ok": false, "code": &"CONFIRM_FAILED"}
		prepared_ticket.clear()
		prior_snapshot.clear()
		return {"ok": true}

	func rollback_route_transition(ticket: Dictionary, _context: Dictionary) -> Dictionary:
		if ticket != prepared_ticket:
			return {"ok": false, "code": &"ROLLBACK_FAILED"}
		active_snapshot = prior_snapshot.duplicate(true)
		prepared_ticket.clear()
		prior_snapshot.clear()
		return {"ok": true}


class TransactionalRoomRuntime:
	extends Node

	signal room_started(room_id: StringName, revision: int)
	signal room_cleared(room_id: StringName, revision: int)
	signal terminal_committed(context: Dictionary, revision: int)
	signal runtime_failed(context: Dictionary)

	var facade: RefCounted
	var fail_entry: bool = false

	func begin_current_room() -> Variant:
		var paused: Variant = facade.call("pause_run")
		if paused == null or not bool(paused.get("ok")):
			return paused
		room_started.emit(&"transactional_room", int(paused.new_revision))
		if fail_entry:
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE",
				int(paused.new_revision),
				{"operation": "begin_current_room"}
			)
		return facade.call("resume_run")



class RouteEntryRunner:
	extends Node

	signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
	signal spawn_requested(spawn_definition: Dictionary)
	signal encounter_completed(encounter_id: StringName)
	signal encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary)

	var active: bool = false

	func start_encounter(_definition: Dictionary, _run_seed: int, _room_number: int) -> void:
		active = true

	func is_active() -> bool:
		return active

	func cancel() -> void:
		active = false

	func snapshot() -> Dictionary:
		return {"active": active}

	func register_spawned(_entity: Node, _definition: Dictionary = {}) -> bool:
		return active

	func reject_spawn(_definition: Dictionary, _reason: StringName) -> bool:
		return active


class RouteEntryRoomController:
	extends Node

	var runner := RouteEntryRunner.new()

	func _init() -> void:
		add_child(runner)

	func encounter_runner() -> Node:
		return runner

	func configure_authored_runtime(_runtime: Node, _catalog: RefCounted) -> bool:
		return true


class MerchantRuntimePlayer:
	extends RefCounted

	var state := {
		"generation": 1,
		"health": {"current_hp": 40.0, "max_hp": 100.0},
		"operations": [],
	}
	var publication_active := false

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if value.is_empty() or not value.get("health") is Dictionary:
			return false
		state = value.duplicate(true)
		return true

	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		(state["operations"] as Array).append(operation.duplicate(true))
		return {"ok": true, "code": &"OK"}

	func reward_effect_begin_publication() -> bool:
		if publication_active:
			return false
		publication_active = true
		return true

	func reward_effect_publication_can_commit() -> bool:
		return publication_active

	func reward_effect_commit_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		return true

	func reward_effect_rollback_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		return true


class RecordingFloorRuleEffectAuthority:
	extends RefCounted

	var batches: Array[Array] = []

	func commit_floor_rule_effects(facts: Array) -> bool:
		batches.append(facts.duplicate(true))
		return true


class RejectingFloorRuleEffectAuthority:
	extends RefCounted

	var calls: int = 0

	func commit_floor_rule_effects(_facts: Array) -> bool:
		calls += 1
		return false


class FloorRuleFrameController:
	extends Node

	var runtime_frame: int = 45

	func character_boss_exposure_runtime_frame() -> int:
		return runtime_frame


class FloorRuleRuntimeFailureRecorder:
	extends RefCounted

	var events: Array[Dictionary] = []

	func record_run_ended(run_id: String, result: Dictionary, revision: int) -> void:
		events.append({
			"run_id": run_id,
			"result": result.duplicate(true),
			"revision": revision,
		})

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var floors: Array = _load_json_array(FLOOR_PATH)
	var templates: Array = _load_json_array(TEMPLATE_PATH)
	if floors.size() != 5 or templates.size() != 30:
		suite.assert_true(false, "five-floor lifecycle fixtures are complete")
		suite.finish(get_tree())
		return
	_test_five_floor_progression(suite, floors, templates)
	_test_first_boss_is_not_victory(suite, floors[0], templates)
	_test_event_bus_floor_signal_contract(suite)
	_test_runtime_host_launch_start_failure_is_atomic(suite)
	_test_runtime_host_route_transaction_and_publication(suite)
	_test_runtime_host_room_entry_failure_is_atomic_and_recoverable(suite)
	_test_runtime_host_route_returns_final_room_entry_revision(suite)
	_test_runtime_host_real_room_entry_rejection_restores_terminal_fields(suite)
	_test_runtime_host_real_room_entry_rollback_is_atomic(suite, "event")
	_test_runtime_host_real_room_entry_rollback_is_atomic(suite, "shop")
	_test_facade_finalized_route_compensation_and_confirmation(suite)
	_test_floor_rule_state_runtime_round_trip(suite)
	_test_launch_restore_rebuilds_active_floor_rule_runtime(suite)
	_test_floor_rule_advance_failure_is_terminal_once(suite)
	suite.finish(get_tree())


func _test_five_floor_progression(suite, floors: Array, templates: Array) -> void:
	var orchestrator = _started_launch("run-five-floor-lifecycle")
	for floor_index: int in range(floors.size()):
		var floor: Dictionary = floors[floor_index]
		var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
			20261001, floor, templates
		)
		suite.assert_true(bool(generated.get("ok", false)), "floor %d generates" % (floor_index + 1))
		if not bool(generated.get("ok", false)):
			return
		var started = orchestrator.start_floor(
			generated["plan"], floor, templates, orchestrator.revision()
		)
		suite.assert_true(started.ok, "floor %d starts" % (floor_index + 1))
		if not started.ok:
			return
		while str(orchestrator.snapshot()["floor_plan"]["current_node_id"]) != "boss":
			if not _advance_one_node(suite, orchestrator, "floor %d" % (floor_index + 1)):
				return
		var boss_id := str(orchestrator.snapshot()["floor_plan"]["current_node_id"])
		var entered = orchestrator.enter_floor_node(boss_id, orchestrator.revision())
		suite.assert_true(entered.ok, "floor %d Boss enters" % (floor_index + 1))
		suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.BOSS_ACTIVE, "floor %d owns Boss phase" % (floor_index + 1))
		var cleared = orchestrator.complete_floor_node(boss_id, orchestrator.revision())
		suite.assert_true(cleared.ok, "floor %d Boss clears" % (floor_index + 1))
		var completed = orchestrator.complete_floor(
			{"result": "victory", "floor_id": str(floor["id"])},
			orchestrator.revision()
		)
		suite.assert_true(completed.ok, "floor %d completion commits" % (floor_index + 1))
		var snapshot: Dictionary = orchestrator.snapshot()
		suite.assert_equal(
			(snapshot["completed_floor_ids"] as Array).size(),
			floor_index + 1,
			"floor completion appends one history entry"
		)
		if floor_index < 4:
			suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.RUN_PREPARING, "non-final Boss returns to floor preparation")
			suite.assert_true(not orchestrator.is_terminal(), "non-final Boss is not Victory")
		else:
			suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.VICTORY, "fifth Boss enters Victory")
			suite.assert_true(orchestrator.is_terminal(), "fifth Boss is terminal")
			suite.assert_equal(snapshot["result"].get("result"), "victory", "final victory context is retained")


func _test_first_boss_is_not_victory(suite, floor: Dictionary, templates: Array) -> void:
	var orchestrator = _started_launch("run-first-boss-convenience")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "Boss convenience fixture generates")
		return
	orchestrator.start_floor(generated["plan"], floor, templates, orchestrator.revision())
	while str(orchestrator.snapshot()["floor_plan"]["current_node_id"]) != "boss":
		if not _advance_one_node(suite, orchestrator, "Boss convenience"):
			return
	var boss_id := str(orchestrator.snapshot()["floor_plan"]["current_node_id"])
	orchestrator.enter_floor_node(boss_id, orchestrator.revision())
	var defeated = orchestrator.boss_defeated({"result": "victory"})
	suite.assert_true(defeated.ok, "Launch Boss convenience command commits")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.RUN_PREPARING, "first Boss convenience command is not Victory")
	suite.assert_equal(orchestrator.snapshot()["completed_floor_ids"], [str(floor["id"])], "Boss convenience completes exactly one floor")


func _test_event_bus_floor_signal_contract(suite) -> void:
	var signatures: Dictionary = {}
	for signal_definition: Dictionary in EventBus.get_signal_list():
		signatures[str(signal_definition.get("name", ""))] = signal_definition.get("args", [])
	for signal_name: String in ["route_selected", "floor_started", "floor_completed"]:
		suite.assert_true(signatures.has(signal_name), "EventBus declares typed %s" % signal_name)
		if signatures.has(signal_name):
			suite.assert_true((signatures[signal_name] as Array).size() >= 3, "%s carries run identity, payload, and revision" % signal_name)


func _test_runtime_host_route_transaction_and_publication(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "Launch runtime facade boots")
	if not booted.ok:
		return
	var run_id := "run-launch-route-runtime"
	var started = facade.start_run(_launch_config(), run_id)
	suite.assert_true(started.ok, "Launch runtime facade starts from canonical registry definitions")
	if not started.ok:
		return

	var host := RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_active_run_id", run_id)
	host.set("_published_run_id", run_id)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)

	var choices: Array[Dictionary] = host.call("route_choices")
	suite.assert_true(not choices.is_empty(), "Launch floor entry exposes a route choice")
	if choices.is_empty():
		_disconnect_route_recorder(recorder)
		host.free()
		return
	var first_edge_id := StringName(str(choices[0].get("edge_id", "")))
	var before_failure: Dictionary = facade.snapshot()
	suite.assert_true(
		host.call("configure_route_scene_adapter", func(_target: Dictionary, _context: Dictionary): return false),
		"Host accepts a rejecting route scene adapter"
	)
	var failed = host.call("select_route", first_edge_id)
	suite.assert_true(not failed.ok, "scene adapter rejection fails the route transition")
	suite.assert_equal(str(failed.code), "COMMIT_FAILED", "scene adapter rejection returns the stable failure code")
	suite.assert_equal(facade.snapshot(), before_failure, "scene adapter rejection restores the exact authoritative snapshot")
	suite.assert_equal(recorder.route_events.size(), 0, "rejected scene transition publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "rejected scene transition publishes no room-start fact")
	suite.assert_equal(recorder.room_cleared_events.size(), 0, "rejected scene transition publishes no room-clear fact")
	suite.assert_equal(recorder.floor_completed_events.size(), 0, "rejected scene transition publishes no floor-complete fact")
	var before_finalize_failure: Dictionary = facade.snapshot()
	var revision_changing_adapter := func(_target: Dictionary, _context: Dictionary): return facade.pause_run().ok
	suite.assert_true(
		host.call("configure_route_scene_adapter", revision_changing_adapter),
		"Host accepts a revision-changing route scene adapter"
	)
	var finalize_failed = host.call("select_route", first_edge_id)
	suite.assert_true(not finalize_failed.ok, "stale route finalization fails closed")
	suite.assert_equal(str(finalize_failed.code), "STALE_REVISION", "stale route finalization preserves its diagnostic")
	suite.assert_equal(facade.snapshot(), before_finalize_failure, "stale route finalization restores the exact authoritative snapshot")
	suite.assert_equal(recorder.route_events.size(), 0, "stale route finalization publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "stale route finalization publishes no room-start fact")

	var atomic_adapter := AtomicRouteSceneAdapter.new()
	atomic_adapter.fail_confirm = true
	suite.assert_true(
		host.call("configure_route_scene_adapter", atomic_adapter),
		"Host accepts a two-phase route scene adapter"
	)
	var before_confirm_failure: Dictionary = facade.snapshot()
	var scene_before_confirm_failure: Dictionary = atomic_adapter.active_snapshot.duplicate(true)
	var confirm_failed = host.call("select_route", first_edge_id)
	suite.assert_true(not confirm_failed.ok, "scene confirmation failure compensates the route")
	suite.assert_equal(facade.snapshot(), before_confirm_failure, "confirmation failure restores exact RunState")
	suite.assert_equal(atomic_adapter.active_snapshot, scene_before_confirm_failure, "confirmation failure restores the prior active scene")
	suite.assert_equal(recorder.route_events.size(), 0, "confirmation failure publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "confirmation failure publishes no room-start fact")

	var room_scene_host := RoomSceneHostScript.new()
	add_child(room_scene_host)
	suite.assert_true(
		host.call("configure_route_scene_adapter", room_scene_host),
		"Host accepts the real two-phase RoomSceneHost"
	)
	var before_missing_effect_authority: Dictionary = facade.snapshot()
	var missing_effect_authority = host.call("select_route", first_edge_id)
	suite.assert_true(
		not missing_effect_authority.ok,
		"real room transition fails before prepare without floor-rule effect authority"
	)
	suite.assert_equal(
		str(missing_effect_authority.code),
		"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
		"missing floor-rule effect authority reports a stable configuration failure"
	)
	suite.assert_equal(
		facade.snapshot(),
		before_missing_effect_authority,
		"missing floor-rule effect authority preserves the exact RunState"
	)
	suite.assert_equal(
		room_scene_host.call("active_snapshot").get("instance_id"),
		0,
		"missing floor-rule effect authority does not prepare or activate a room scene"
	)
	suite.assert_true(
		host.call("configure_floor_rule_effect_authority", RecordingFloorRuleEffectAuthority.new()),
		"Host accepts the floor-rule effect authority"
	)
	host.call("_publish_floor_started_once", facade.snapshot())
	host.call("_publish_floor_started_once", facade.snapshot())
	suite.assert_equal(recorder.floor_started_events.size(), 1, "floor start publishes exactly once")

	while (facade.snapshot().get("completed_floor_ids", []) as Array).is_empty():
		choices = host.call("route_choices")
		suite.assert_true(not choices.is_empty(), "active Launch node exposes the next route choice")
		if choices.is_empty():
			break
		var edge_id := StringName(str(choices[0].get("edge_id", "")))
		var route_count_before := recorder.route_events.size()
		var room_start_count_before := recorder.room_started_events.size()
		var selected = host.call("select_route", edge_id)
		suite.assert_true(selected.ok, "successful route transition commits")
		if not selected.ok:
			break
		suite.assert_true(
			not (facade.snapshot().get("floor_rule_state", {}) as Dictionary).is_empty(),
			"real room transition commits its floor-rule snapshot before publication"
		)
		suite.assert_equal(recorder.route_events.size(), route_count_before + 1, "route selection publishes one route fact")
		suite.assert_equal(recorder.room_started_events.size(), room_start_count_before + 1, "route selection publishes one room-start fact")
		var room: Dictionary = facade.current_room_definition()
		var completed = facade.complete_current_room()
		suite.assert_true(completed.ok, "selected Launch room completes through the facade")
		if not completed.ok:
			break
		host.call(
			"_on_room_cleared",
			StringName(str(room.get("node_id", ""))),
			int(completed.new_revision)
		)

	var final_snapshot: Dictionary = facade.snapshot()
	suite.assert_equal((final_snapshot.get("completed_floor_ids", []) as Array).size(), 1, "first Launch floor completes once")
	suite.assert_equal(
		final_snapshot.get("run_economy", {}).get("settled_floor_indices"),
		[0],
		"first Boss completion settles floor-one economy exactly once"
	)
	var economy_ledger: Array = final_snapshot.get("run_economy", {}).get("ledger", [])
	suite.assert_equal(economy_ledger.size(), 1, "floor settlement appends one economy fact")
	if economy_ledger.size() == 1:
		suite.assert_equal(
			economy_ledger[0],
			{
				"transaction_id": "tx_floor_1_settlement",
				"operation": "gold_decay",
				"amount": 0,
				"revision": 1,
			},
			"under-cap floor settlement records the canonical zero-decay fact"
		)
	suite.assert_equal(recorder.route_events.size(), recorder.room_started_events.size(), "every committed route publishes one room start")
	suite.assert_equal(recorder.route_events.size(), recorder.room_cleared_events.size(), "every entered room publishes one room clear")
	suite.assert_equal(recorder.floor_completed_events.size(), 1, "floor completion publishes exactly once")
	host.call("_publish_floor_completed_if_new", final_snapshot, int(final_snapshot.get("revision", 0)))
	suite.assert_equal(recorder.floor_completed_events.size(), 1, "duplicate floor-completion publication is suppressed")

	_disconnect_route_recorder(recorder)
	room_scene_host.reset()
	room_scene_host.free()
	host.free()


func _test_facade_finalized_route_compensation_and_confirmation(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "route compensation facade boots")
	suite.assert_true(facade.start_run(_launch_config(), "run-route-compensation").ok, "route compensation run starts")
	var before: Dictionary = facade.snapshot()
	var choice := (facade.route_choices() as Array)[0] as Dictionary
	var begun = facade.begin_route_transition(StringName(str(choice["edge_id"])), int(before["revision"]))
	suite.assert_true(begun.ok, "compensation route begins")
	var transition_id := str(begun.context.get("transition_id", ""))
	var finalized = facade.finalize_route_transition(transition_id, int(begun.new_revision))
	suite.assert_true(finalized.ok, "compensation route finalizes without discarding its before snapshot")
	var rolled_back = facade.rollback_route_transition(transition_id, int(finalized.new_revision))
	suite.assert_true(rolled_back.ok, "finalized route remains compensatable before confirmation")
	suite.assert_equal(facade.snapshot(), before, "finalized compensation restores byte-identical RunState")

	choice = (facade.route_choices() as Array)[0] as Dictionary
	begun = facade.begin_route_transition(StringName(str(choice["edge_id"])), int(facade.snapshot()["revision"]))
	transition_id = str(begun.context.get("transition_id", ""))
	finalized = facade.finalize_route_transition(transition_id, int(begun.new_revision))
	var confirmed = facade.confirm_route_transition(transition_id, int(finalized.new_revision))
	suite.assert_true(confirmed.ok, "confirmed route releases its compensation snapshot")
	var late_rollback = facade.rollback_route_transition(transition_id, int(confirmed.new_revision))
	suite.assert_true(not late_rollback.ok, "confirmed route cannot be rolled back")


func _test_runtime_host_room_entry_failure_is_atomic_and_recoverable(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "room-entry transaction facade boots")
	suite.assert_true(
		facade.start_run(_launch_config(), "run-route-room-entry-transaction").ok,
		"room-entry transaction run starts"
	)
	var host := RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_active_run_id", "run-route-room-entry-transaction")
	host.set("_published_run_id", "run-route-room-entry-transaction")
	var controller := RouteEntryRoomController.new()
	host.add_child(controller)
	host.set("_room_controller", controller)
	var runtime := TransactionalRoomRuntime.new()
	runtime.facade = facade
	host.add_child(runtime)
	host.set("_room_runtime", runtime)
	host.call("_connect_room_runtime")
	var scene_adapter := AtomicRouteSceneAdapter.new()
	suite.assert_true(
		host.call("configure_route_scene_adapter", scene_adapter),
		"room-entry transaction configures its scene adapter"
	)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)

	var choices: Array[Dictionary] = host.call("route_choices")
	suite.assert_true(not choices.is_empty(), "room-entry transaction exposes a route")
	if choices.is_empty():
		_disconnect_route_recorder(recorder)
		host.free()
		return
	var edge_id := StringName(str(choices[0].get("edge_id", "")))
	var before: Dictionary = facade.snapshot()
	runtime.fail_entry = true
	var failed: Variant = host.call("select_route", edge_id)
	suite.assert_true(not bool(failed.get("ok")), "room-entry rejection fails the route command")
	suite.assert_equal(
		str(failed.get("code")),
		"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
		"room-entry rejection returns the stable host failure code"
	)
	suite.assert_equal(
		facade.snapshot(),
		before,
		"room-entry rejection restores the exact pre-route authoritative snapshot"
	)
	suite.assert_equal(recorder.route_events.size(), 0, "room-entry rejection publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "room-entry rejection publishes no room fact")
	suite.assert_true(
		host.get("_room_runtime") != runtime,
		"room-entry rejection replaces the failed runtime with a clean production runtime"
	)

	host.call("_dispose_room_runtime")
	var retry_runtime := TransactionalRoomRuntime.new()
	retry_runtime.facade = facade
	host.add_child(retry_runtime)
	host.set("_room_runtime", retry_runtime)
	host.call("_connect_room_runtime")
	var selected: Variant = host.call("select_route", edge_id)
	suite.assert_true(bool(selected.get("ok")), "compensated room-entry route can retry immediately")
	suite.assert_equal(recorder.route_events.size(), 1, "successful retry publishes one route fact")
	suite.assert_equal(recorder.room_started_events.size(), 1, "successful retry publishes one room fact")
	suite.assert_equal(
		recorder.publication_order,
		["route_selected", "room_started"],
		"successful route publication remains ordered before room-start publication"
	)

	_disconnect_route_recorder(recorder)
	host.free()


func _test_runtime_host_route_returns_final_room_entry_revision(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "final route revision facade boots")
	suite.assert_true(
		facade.start_run(_launch_config(), "run-route-final-entry-revision").ok,
		"final route revision run starts"
	)
	var host := RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_active_run_id", "run-route-final-entry-revision")
	host.set("_published_run_id", "run-route-final-entry-revision")
	var runtime := TransactionalRoomRuntime.new()
	runtime.facade = facade
	host.add_child(runtime)
	host.set("_room_runtime", runtime)
	host.call("_connect_room_runtime")
	suite.assert_true(
		host.call("configure_route_scene_adapter", AtomicRouteSceneAdapter.new()),
		"final route revision configures its scene adapter"
	)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)
	var before: Dictionary = facade.snapshot()
	var choices: Array[Dictionary] = host.call("route_choices")
	suite.assert_true(not choices.is_empty(), "final route revision exposes a route")
	if choices.is_empty():
		_disconnect_route_recorder(recorder)
		host.free()
		return
	var selected: Variant = host.call(
		"select_route", StringName(str(choices[0].get("edge_id", "")))
	)
	suite.assert_true(bool(selected.get("ok")), "revision-advancing room entry commits")
	var final_snapshot: Dictionary = facade.snapshot()
	suite.assert_equal(
		int(selected.get("new_revision")),
		int(final_snapshot.get("revision", -1)),
		"successful route returns the final post-entry authoritative revision"
	)
	suite.assert_true(
		int(selected.get("new_revision")) > int(before.get("revision", -1)) + 2,
		"returned revision includes the room runtime's pause/resume mutations"
	)
	suite.assert_equal(
		recorder.publication_order,
		["route_selected", "room_started"],
		"route fact remains ordered before buffered room-start publication"
	)
	_disconnect_route_recorder(recorder)
	host.free()


func _test_runtime_host_real_room_entry_rejection_restores_terminal_fields(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "real entry rejection Facade boots")
	var run_id := "run-real-shop-entry-rejection"
	var started = facade.start_run(_launch_config(), run_id)
	suite.assert_true(started.ok, "real entry rejection run starts")
	if not started.ok:
		return
	var target_node_id := _first_reachable_node_type(
		facade.snapshot().get("floor_plan", {}) as Dictionary,
		"shop"
	)
	var path := _edge_path_to_node(
		facade.snapshot().get("floor_plan", {}) as Dictionary,
		target_node_id
	)
	suite.assert_true(
		not target_node_id.is_empty() and not path.is_empty(),
		"real entry rejection fixture has a reachable shop"
	)
	if target_node_id.is_empty() or path.is_empty():
		return
	for index: int in range(path.size() - 1):
		var begun = facade.begin_route_transition(
			StringName(path[index]), int(facade.snapshot().get("revision", -1))
		)
		if not begun.ok:
			suite.assert_true(false, "real entry rejection begins predecessor route")
			return
		var transition_id := str(begun.context.get("transition_id", ""))
		var finalized = facade.finalize_route_transition(
			transition_id, int(begun.new_revision)
		)
		if not finalized.ok:
			suite.assert_true(false, "real entry rejection enters predecessor")
			return
		var confirmed = facade.confirm_route_transition(
			transition_id, int(finalized.new_revision)
		)
		if not confirmed.ok:
			suite.assert_true(false, "real entry rejection confirms predecessor")
			return
		var completed = facade.complete_current_room()
		if not completed.ok:
			suite.assert_true(false, "real entry rejection clears predecessor")
			return

	var controller := RouteEntryRoomController.new()
	add_child(controller)
	var host := RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_active_run_id", run_id)
	host.set("_published_run_id", run_id)
	host.set("_room_controller", controller)
	var runtime: Variant = facade.create_room_runtime(controller.runner)
	suite.assert_true(runtime is Node, "real entry rejection creates RoomRuntime")
	if not runtime is Node:
		host.free()
		controller.free()
		return
	(runtime as Node).name = "RoomRuntime"
	host.add_child(runtime as Node)
	host.set("_room_runtime", runtime)
	host.call("_connect_room_runtime")
	host.call(
		"configure_floor_rule_effect_authority",
		RecordingFloorRuleEffectAuthority.new()
	)
	host.call("configure_route_scene_adapter", AtomicRouteSceneAdapter.new())
	var before := facade.snapshot().duplicate(true)
	var failed = host.select_route(StringName(path[-1]))
	suite.assert_true(not failed.ok, "missing merchant authority rejects real room entry")
	suite.assert_equal(
		str(failed.code),
		"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
		"real room entry rejection returns the stable configuration code"
	)
	suite.assert_equal(
		facade.snapshot(),
		before,
		"real room entry rejection restores every authoritative field"
	)
	suite.assert_true(
		(facade.snapshot().get("result", {}) as Dictionary).is_empty(),
		"real room entry rejection leaves no terminal result"
	)

	var merchant_player := MerchantRuntimePlayer.new()
	var merchant_reward_runtime = PlayerRewardEffectRuntimeScript.new()
	suite.assert_true(
		facade.configure_merchant_effect_authority(
			merchant_reward_runtime, merchant_player
		),
		"real entry rejection retry configures merchant authority"
	)
	var retried = host.select_route(StringName(path[-1]))
	suite.assert_true(retried.ok, "real room entry retries after complete rollback")
	host.free()
	controller.free()


func _test_runtime_host_real_room_entry_rollback_is_atomic(
	suite,
	room_type: String
) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "%s rollback Facade boots" % room_type)
	var merchant_player: MerchantRuntimePlayer = null
	var merchant_reward_runtime: RefCounted = null
	if room_type == "shop":
		merchant_player = MerchantRuntimePlayer.new()
		merchant_reward_runtime = PlayerRewardEffectRuntimeScript.new()
		suite.assert_true(
			facade.configure_merchant_effect_authority(
				merchant_reward_runtime, merchant_player
			),
			"shop rollback configures merchant effect authority"
		)
	var run_id := "run-real-%s-route-rollback" % room_type
	var started = facade.start_run(_launch_config(), run_id)
	suite.assert_true(started.ok, "%s rollback run starts" % room_type)
	if not started.ok:
		return
	var target_node_id := _first_reachable_node_type(
		facade.snapshot().get("floor_plan", {}) as Dictionary,
		room_type
	)
	var path := _edge_path_to_node(
		facade.snapshot().get("floor_plan", {}) as Dictionary,
		target_node_id
	)
	suite.assert_true(
		not target_node_id.is_empty() and not path.is_empty(),
		"%s rollback fixture has a reachable target" % room_type
	)
	if target_node_id.is_empty() or path.is_empty():
		return
	for index: int in range(path.size() - 1):
		var begun = facade.begin_route_transition(
			StringName(path[index]), int(facade.snapshot().get("revision", -1))
		)
		if not begun.ok:
			suite.assert_true(false, "%s rollback fixture begins predecessor route" % room_type)
			return
		var transition_id := str(begun.context.get("transition_id", ""))
		var finalized = facade.finalize_route_transition(
			transition_id, int(begun.new_revision)
		)
		if not finalized.ok:
			suite.assert_true(false, "%s rollback fixture enters predecessor" % room_type)
			return
		var confirmed = facade.confirm_route_transition(
			transition_id, int(finalized.new_revision)
		)
		if not confirmed.ok:
			suite.assert_true(false, "%s rollback fixture confirms predecessor" % room_type)
			return
		var completed = facade.complete_current_room()
		if not completed.ok:
			suite.assert_true(false, "%s rollback fixture clears predecessor" % room_type)
			return

	var controller := RouteEntryRoomController.new()
	add_child(controller)
	var host := RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_active_run_id", run_id)
	host.set("_published_run_id", run_id)
	host.set("_room_controller", controller)
	var runtime: Variant = facade.create_room_runtime(controller.runner)
	suite.assert_true(runtime is Node, "%s rollback creates a real RoomRuntime" % room_type)
	if not runtime is Node:
		host.free()
		controller.free()
		return
	(runtime as Node).name = "RoomRuntime"
	host.add_child(runtime as Node)
	host.set("_room_runtime", runtime)
	host.call("_connect_room_runtime")
	host.call(
		"configure_floor_rule_effect_authority",
		RecordingFloorRuleEffectAuthority.new()
	)
	var adapter := AtomicRouteSceneAdapter.new()
	adapter.fail_confirm = true
	host.call("configure_route_scene_adapter", adapter)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)
	var before := facade.snapshot().duplicate(true)
	var event_runtime_before := (
		before.get("dungeon_event_runtime", {}) as Dictionary
	).duplicate(true)
	var merchant_before := (
		before.get("merchant_state", {}) as Dictionary
	).duplicate(true)

	var failed = host.select_route(StringName(path[-1]))
	suite.assert_true(not failed.ok, "%s scene confirm failure is surfaced" % room_type)
	suite.assert_equal(
		str(failed.code),
		"COMMIT_FAILED",
		"%s failure keeps the stable code" % room_type
	)
	suite.assert_equal(
		facade.snapshot(), before,
		"%s failure restores authoritative RunState" % room_type
	)
	suite.assert_equal(
		(facade.get("_event_runtime") as RefCounted).call("snapshot"),
		event_runtime_before,
		"%s failure restores the live event runtime" % room_type
	)
	suite.assert_equal(
		(facade.get("_merchant_run_state") as RefCounted).call("snapshot"),
		merchant_before,
		"%s failure restores the live merchant state" % room_type
	)
	suite.assert_true(
		(facade.get("_merchant_sessions") as Dictionary).is_empty(),
		"%s failure removes tentative merchant sessions" % room_type
	)
	suite.assert_equal(
		recorder.route_events.size(), 0,
		"%s failure publishes no route fact" % room_type
	)
	suite.assert_equal(
		recorder.room_started_events.size(), 0,
		"%s failure publishes no room fact" % room_type
	)
	suite.assert_equal(
		recorder.event_opened_events.size(), 0,
		"%s failure publishes no event fact" % room_type
	)

	adapter.fail_confirm = false
	var retried = host.select_route(StringName(path[-1]))
	suite.assert_true(retried.ok, "%s route retries after complete rollback" % room_type)
	if retried.ok:
		suite.assert_equal(
			recorder.route_events.size(), 1,
			"%s retry publishes one route fact" % room_type
		)
		suite.assert_equal(
			recorder.room_started_events.size(), 1,
			"%s retry publishes one room fact" % room_type
		)
		if room_type == "event":
			suite.assert_equal(
				recorder.event_opened_events.size(), 1,
				"event retry publishes one opened fact"
			)
			suite.assert_equal(
				recorder.publication_order,
				["route_selected", "event_opened", "room_started"],
				"event facts publish after route confirmation and before room started"
			)
			suite.assert_equal(
				(facade.get("_event_runtime") as RefCounted).call("snapshot"),
				facade.snapshot().get("dungeon_event_runtime", {}),
				"event retry keeps live and authoritative runtime identical"
			)
		else:
			suite.assert_true(
				not (facade.get("_merchant_sessions") as Dictionary).is_empty(),
				"shop retry creates one authoritative merchant session"
			)
			suite.assert_equal(
				(facade.get("_merchant_run_state") as RefCounted).call("snapshot"),
				facade.snapshot().get("merchant_state", {}),
				"shop retry keeps live and authoritative merchant state identical"
			)
	_disconnect_route_recorder(recorder)
	host.free()
	controller.free()


func _test_floor_rule_state_runtime_round_trip(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "floor-rule facade boots")
	suite.assert_true(facade.start_run(_launch_config(), "run-floor-rule-state").ok, "floor-rule run starts")
	var choice := (facade.route_choices() as Array)[0] as Dictionary
	var begun = facade.begin_route_transition(StringName(str(choice["edge_id"])), int(facade.snapshot()["revision"]))
	var transition_id := str(begun.context.get("transition_id", ""))
	var finalized = facade.finalize_route_transition(transition_id, int(begun.new_revision))
	suite.assert_true(finalized.ok, "floor-rule room enters")
	var authority := RecordingFloorRuleEffectAuthority.new()
	var configured = facade.configure_floor_rule(
		&"rule_crumbling_ground",
		_floor_rule_configuration(str(choice["node_id"])),
		authority,
		int(finalized.new_revision)
	)
	suite.assert_true(configured.ok, "current floor rule configures through facade authority")
	var initial_rule: Dictionary = facade.snapshot().get("floor_rule_state", {}).duplicate(true)
	suite.assert_true(not initial_rule.is_empty(), "configured floor rule is stored in RunState")
	var cached_command_revision := int(configured.new_revision)
	var advanced = facade.advance_floor_rule_frame(0, {}, int(configured.new_revision))
	suite.assert_true(advanced.ok, "floor-rule frame advances through facade")
	suite.assert_equal(
		advanced.new_revision,
		cached_command_revision,
		"floor-rule frame observation does not consume the command revision"
	)
	var frame_zero: Dictionary = facade.snapshot().get("floor_rule_state", {}).duplicate(true)
	suite.assert_equal(frame_zero.get("runtime_frame"), 0, "RunState records the monotonic runtime frame")
	var still_confirmable = facade.can_confirm_route_transition(
		transition_id,
		cached_command_revision
	)
	suite.assert_true(
		still_confirmable.ok,
		"cached route command revision survives floor-rule frame observations"
	)
	var stale = facade.advance_floor_rule_frame(0, {}, int(advanced.new_revision))
	suite.assert_true(not stale.ok, "duplicate floor-rule frame fails closed")
	suite.assert_equal(facade.snapshot().get("floor_rule_state"), frame_zero, "rejected frame preserves exact floor-rule state")
	var restored = facade.restore_floor_rule_snapshot(initial_rule, authority, int(advanced.new_revision))
	suite.assert_true(restored.ok, "canonical floor-rule snapshot restores through facade")
	suite.assert_equal(facade.snapshot().get("floor_rule_state"), initial_rule, "floor-rule Save/Replay restore is byte-identical")
	var confirmed = facade.confirm_route_transition(transition_id, int(restored.new_revision))
	suite.assert_true(confirmed.ok, "route can confirm after floor-rule state joins the transaction")
	var completed = facade.complete_current_room()
	suite.assert_true(completed.ok, "floor-rule room completes")
	var next_choice := (facade.route_choices() as Array)[0] as Dictionary
	var next_begun = facade.begin_route_transition(StringName(str(next_choice["edge_id"])), int(completed.new_revision))
	suite.assert_true(next_begun.ok, "next route begins")
	suite.assert_equal(facade.snapshot().get("floor_rule_state"), {}, "room transition clears the prior floor-rule state")
	var next_rollback = facade.rollback_route_transition(str(next_begun.context.get("transition_id", "")), int(next_begun.new_revision))
	suite.assert_true(next_rollback.ok, "next route rollback succeeds")
	suite.assert_equal(facade.snapshot().get("floor_rule_state"), initial_rule, "route rollback restores the prior floor-rule snapshot")


func _test_launch_restore_rebuilds_active_floor_rule_runtime(suite) -> void:
	var source = RunRuntimeFacadeScript.new()
	suite.assert_true(source.boot().ok, "floor-rule restore source boots")
	suite.assert_true(
		source.start_run(_launch_config(), "run-floor-rule-launch-restore").ok,
		"floor-rule restore source run starts"
	)
	var choice: Dictionary = {}
	for value: Variant in source.route_choices():
		if value is Dictionary and str((value as Dictionary).get("room_type", "")) != "shop":
			choice = (value as Dictionary).duplicate(true)
			break
	suite.assert_true(not choice.is_empty(), "floor-rule restore fixture finds a non-shop room")
	if choice.is_empty():
		return
	var begun = source.begin_route_transition(
		StringName(str(choice["edge_id"])), int(source.snapshot()["revision"])
	)
	var transition_id := str(begun.context.get("transition_id", ""))
	var finalized = source.finalize_route_transition(transition_id, int(begun.new_revision))
	suite.assert_true(finalized.ok, "floor-rule restore source enters its room")
	var source_authority := RecordingFloorRuleEffectAuthority.new()
	var configured = source.configure_floor_rule(
		&"rule_crumbling_ground",
		_floor_rule_configuration(str(choice["node_id"])),
		source_authority,
		int(finalized.new_revision)
	)
	suite.assert_true(configured.ok, "floor-rule restore source configures its rule")
	var advanced = source.advance_floor_rule_frame(0, {}, int(configured.new_revision))
	suite.assert_true(advanced.ok, "floor-rule restore source advances before save")
	var saved: Dictionary = source.snapshot().duplicate(true)

	var restored = RunRuntimeFacadeScript.new()
	suite.assert_true(restored.boot().ok, "floor-rule restore target boots")
	var restored_authority := RecordingFloorRuleEffectAuthority.new()
	var result = restored.restore_launch_run(saved, restored_authority)
	suite.assert_true(result.ok, "Launch restore accepts an active floor-rule snapshot")
	if not result.ok:
		return
	suite.assert_equal(restored.snapshot(), saved, "Launch restore keeps the complete RunState byte-identical")
	var next_frame = restored.advance_floor_rule_frame(1, {}, int(result.new_revision))
	suite.assert_true(next_frame.ok, "restored floor-rule runtime continues from the saved frame")
	suite.assert_equal(
		(restored.snapshot().get("floor_rule_state", {}) as Dictionary).get("runtime_frame"),
		1,
		"restored floor-rule runtime owns the next monotonic frame"
	)


func _test_floor_rule_advance_failure_is_terminal_once(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "floor-rule failure facade boots")
	var run_id := "run-floor-rule-runtime-failure"
	suite.assert_true(facade.start_run(_launch_config(), run_id).ok, "floor-rule failure run starts")
	var choice := (facade.route_choices() as Array)[0] as Dictionary
	var begun = facade.begin_route_transition(
		StringName(str(choice["edge_id"])),
		int(facade.snapshot()["revision"])
	)
	var transition_id := str(begun.context.get("transition_id", ""))
	var finalized = facade.finalize_route_transition(transition_id, int(begun.new_revision))
	var authority := RejectingFloorRuleEffectAuthority.new()
	var configured = facade.configure_floor_rule(
		&"rule_crumbling_ground",
		_floor_rule_configuration(str(choice["node_id"])),
		authority,
		int(finalized.new_revision)
	)
	suite.assert_true(configured.ok, "rejecting floor-rule authority configures before the active frame")
	var confirmed = facade.confirm_route_transition(transition_id, int(configured.new_revision))
	suite.assert_true(confirmed.ok, "floor-rule failure route confirms")

	var host := RunRuntimeHostScript.new()
	var frame_controller := FloorRuleFrameController.new()
	add_child(frame_controller)
	add_child(host)
	host.set("_facade", facade)
	host.set("_room_controller", frame_controller)
	host.set("_active_run_id", run_id)
	host.set("_published_run_id", run_id)
	host.set("_floor_rule_frame_origin", 0)
	var recorder := FloorRuleRuntimeFailureRecorder.new()
	EventBus.run_ended.connect(recorder.record_run_ended)

	host.call("_advance_floor_rule_from_host")
	var terminal_state: Dictionary = facade.snapshot()
	suite.assert_equal(authority.calls, 1, "first active frame reaches the rejecting authority once")
	suite.assert_equal(
		int(terminal_state.get("phase", -1)),
		RunPhaseScript.Value.DEFEAT,
		"floor-rule rejection enters the terminal runtime-error phase"
	)
	suite.assert_equal(
		str((terminal_state.get("result", {}) as Dictionary).get("result", "")),
		"runtime_error",
		"floor-rule rejection records runtime_error as the authoritative result"
	)
	suite.assert_equal(recorder.events.size(), 1, "floor-rule rejection publishes one run-ended fact")
	if not recorder.events.is_empty():
		suite.assert_equal(
			str((recorder.events[0]["result"] as Dictionary).get("reason", "")),
			"floor_rule_frame_advance",
			"published runtime error identifies floor-rule frame advancement"
		)

	frame_controller.runtime_frame = 46
	host.call("_advance_floor_rule_from_host")
	suite.assert_equal(authority.calls, 1, "terminal host does not retry the rejected floor-rule frame")
	suite.assert_equal(recorder.events.size(), 1, "terminal host never republishes the runtime error")

	if EventBus.run_ended.is_connected(recorder.record_run_ended):
		EventBus.run_ended.disconnect(recorder.record_run_ended)
	host.free()
	frame_controller.free()


func _test_runtime_host_launch_start_failure_is_atomic(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "atomic Launch start fixture boots")
	if not booted.ok:
		return
	var registry: RefCounted = facade.content_registry()
	var definitions: Dictionary = (registry.get("_definitions") as Dictionary).duplicate(true)
	definitions.erase("floor_throne_of_void")
	registry.set("_definitions", definitions)
	var before: Dictionary = facade.snapshot()

	var host := RunRuntimeHostScript.new()
	add_child(host)
	var dummy_controller := Node.new()
	var dummy_player := Node.new()
	host.add_child(dummy_controller)
	host.add_child(dummy_player)
	host.set("_active", true)
	host.set("_room_controller", dummy_controller)
	host.set("_player", dummy_player)
	host.set("_facade", facade)
	var recorder := RouteLifecycleRecorder.new()
	_connect_route_recorder(recorder)
	var failed = host.call("start_run", _launch_config())
	suite.assert_true(not failed.ok, "incomplete Launch content rejects run start")
	suite.assert_equal(facade.snapshot(), before, "rejected Launch start preserves the exact Hub snapshot")
	suite.assert_equal(recorder.run_started_events.size(), 0, "rejected Launch start publishes no run fact")
	suite.assert_equal(recorder.floor_started_events.size(), 0, "rejected Launch start publishes no floor fact")
	suite.assert_equal(recorder.route_events.size(), 0, "rejected Launch start publishes no route fact")
	suite.assert_equal(recorder.room_started_events.size(), 0, "rejected Launch start publishes no room fact")

	_disconnect_route_recorder(recorder)
	host.free()


func _advance_one_node(suite, orchestrator, label: String) -> bool:
	var plan: Dictionary = orchestrator.snapshot()["floor_plan"]
	var edge := _first_outgoing_edge(plan)
	if edge.is_empty():
		suite.assert_true(false, "%s current node exposes an outgoing edge" % label)
		return false
	var begun = orchestrator.begin_route_transition(
		StringName(str(edge["id"])), orchestrator.revision()
	)
	if not begun.ok:
		suite.assert_true(false, "%s route begin succeeds" % label)
		return false
	var finalized = orchestrator.finalize_route_transition(
		str(begun.context.get("transition_id", "")), orchestrator.revision()
	)
	if not finalized.ok:
		suite.assert_true(false, "%s route finalize succeeds" % label)
		return false
	var node_id := str(orchestrator.snapshot()["floor_plan"]["current_node_id"])
	if node_id == "boss":
		return true
	var entered = orchestrator.enter_floor_node(node_id, orchestrator.revision())
	if not entered.ok:
		suite.assert_true(false, "%s node enters" % label)
		return false
	var completed = orchestrator.complete_floor_node(node_id, orchestrator.revision())
	if not completed.ok:
		suite.assert_true(false, "%s node completes" % label)
		return false
	return true


func _started_launch(run_id: String):
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_launch_config(), run_id)
	return orchestrator


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}


func _connect_route_recorder(recorder: RouteLifecycleRecorder) -> void:
	EventBus.run_started.connect(recorder.record_run_started)
	EventBus.route_selected.connect(recorder.record_route_selected)
	EventBus.room_started.connect(recorder.record_room_started)
	EventBus.room_cleared.connect(recorder.record_room_cleared)
	EventBus.floor_started.connect(recorder.record_floor_started)
	EventBus.floor_completed.connect(recorder.record_floor_completed)
	EventBus.event_opened.connect(recorder.record_event_opened)


func _disconnect_route_recorder(recorder: RouteLifecycleRecorder) -> void:
	if EventBus.run_started.is_connected(recorder.record_run_started):
		EventBus.run_started.disconnect(recorder.record_run_started)
	if EventBus.route_selected.is_connected(recorder.record_route_selected):
		EventBus.route_selected.disconnect(recorder.record_route_selected)
	if EventBus.room_started.is_connected(recorder.record_room_started):
		EventBus.room_started.disconnect(recorder.record_room_started)
	if EventBus.room_cleared.is_connected(recorder.record_room_cleared):
		EventBus.room_cleared.disconnect(recorder.record_room_cleared)
	if EventBus.floor_started.is_connected(recorder.record_floor_started):
		EventBus.floor_started.disconnect(recorder.record_floor_started)
	if EventBus.floor_completed.is_connected(recorder.record_floor_completed):
		EventBus.floor_completed.disconnect(recorder.record_floor_completed)
	if EventBus.event_opened.is_connected(recorder.record_event_opened):
		EventBus.event_opened.disconnect(recorder.record_event_opened)


func _first_outgoing_edge(plan: Dictionary) -> Dictionary:
	var source_id := str(plan.get("current_node_id", ""))
	for edge_value: Variant in plan.get("edges", []):
		var edge: Dictionary = edge_value
		if str(edge.get("source_node_id", "")) == source_id and not bool(edge.get("locked", false)):
			return edge.duplicate(true)
	return {}


func _first_reachable_node_type(plan: Dictionary, room_type: String) -> String:
	var queue: Array[String] = [str(plan.get("entry_node_id", "entry"))]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		for node_value: Variant in plan.get("nodes", []):
			if (
				node_value is Dictionary
				and str((node_value as Dictionary).get("id", "")) == node_id
				and str((node_value as Dictionary).get("room_type", "")) == room_type
			):
				return node_id
		for edge_value: Variant in plan.get("edges", []):
			if (
				edge_value is Dictionary
				and str((edge_value as Dictionary).get("source_node_id", "")) == node_id
				and not bool((edge_value as Dictionary).get("locked", false))
			):
				queue.append(str((edge_value as Dictionary).get("destination_node_id", "")))
	return ""


func _edge_path_to_node(plan: Dictionary, target_node_id: String) -> Array[String]:
	var entry_id := str(plan.get("entry_node_id", "entry"))
	var queue: Array[String] = [entry_id]
	var prior: Dictionary = {entry_id: {}}
	while not queue.is_empty():
		var source_id: String = queue.pop_front()
		if source_id == target_node_id:
			break
		for edge_value: Variant in plan.get("edges", []):
			if not edge_value is Dictionary:
				continue
			var edge := edge_value as Dictionary
			if (
				str(edge.get("source_node_id", "")) != source_id
				or bool(edge.get("locked", false))
			):
				continue
			var destination_id := str(edge.get("destination_node_id", ""))
			if prior.has(destination_id):
				continue
			prior[destination_id] = {
				"source": source_id,
				"edge_id": str(edge.get("id", "")),
			}
			queue.append(destination_id)
	if not prior.has(target_node_id):
		return []
	var reversed: Array[String] = []
	var cursor := target_node_id
	while cursor != entry_id:
		var step := prior[cursor] as Dictionary
		reversed.append(str(step.get("edge_id", "")))
		cursor = str(step.get("source", ""))
	reversed.reverse()
	return reversed


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _floor_rule_configuration(room_id: String) -> Dictionary:
	return {
		"room_id": room_id,
		"room_seed": 20261002,
		"zones": [
			{"id": "hazard_west", "bounds": {"x": 32.0, "y": 48.0, "width": 160.0, "height": 120.0}},
			{"id": "safe_core", "bounds": {"x": 224.0, "y": 96.0, "width": 192.0, "height": 168.0}},
		],
		"safe_zone_ids": ["safe_core"],
		"reduced_motion": false,
		"hit_flash_enabled": true,
	}
