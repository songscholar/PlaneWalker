extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunRuntimeFacadeScript := preload(
	"res://scripts/application/run_runtime_facade.gd"
)
const RunRuntimeHostScript := preload(
	"res://scripts/application/run_runtime_host.gd"
)

const SEED := 20261002
const FORBIDDEN_FACT_FIELDS: Array[String] = [
	"roll", "roll_value", "consequences", "continuation_id", "token", "ticket",
]


class FactRecorder:
	extends RefCounted

	var facts: Array[Dictionary] = []

	func opened(
		run_id: String,
		event_id: StringName,
		node_key: String,
		revision: int
	) -> void:
		facts.append({
			"kind": "event_opened",
			"run_id": run_id,
			"event_id": str(event_id),
			"node_key": node_key,
			"revision": revision,
		})

	func committed(
		run_id: String,
		event_id: StringName,
		node_key: String,
		phase: StringName,
		pending_kind: StringName,
		result_key: StringName,
		revision: int
	) -> void:
		facts.append({
			"kind": "event_committed",
			"run_id": run_id,
			"event_id": str(event_id),
			"node_key": node_key,
			"phase": str(phase),
			"pending_kind": str(pending_kind),
			"result_key": str(result_key),
			"revision": revision,
		})

	func reward_completed(
		run_id: String,
		event_id: StringName,
		node_key: String,
		result_key: StringName,
		revision: int
	) -> void:
		facts.append({
			"kind": "event_reward_completed",
			"run_id": run_id,
			"event_id": str(event_id),
			"node_key": node_key,
			"result_key": str(result_key),
			"revision": revision,
		})

	func encounter_completed(
		run_id: String,
		event_id: StringName,
		node_key: String,
		result_key: StringName,
		success: bool,
		revision: int
	) -> void:
		facts.append({
			"kind": "event_encounter_completed",
			"run_id": run_id,
			"event_id": str(event_id),
			"node_key": node_key,
			"result_key": str(result_key),
			"success": success,
			"revision": revision,
		})

	func dismissed(
		run_id: String,
		event_id: StringName,
		node_key: String,
		result_key: StringName,
		revision: int
	) -> void:
		facts.append({
			"kind": "event_dismissed",
			"run_id": run_id,
			"event_id": str(event_id),
			"node_key": node_key,
			"result_key": str(result_key),
			"revision": revision,
		})


class AckFailingFacade:
	extends RunRuntimeFacadeScript

	var fail_event_fact_ack_count := 0

	func fail_next_event_fact_ack() -> void:
		fail_event_fact_ack_count = 1

	func _commit_event_runtime_state(
		command: Dictionary, expected_revision: int
	) -> Dictionary:
		if (
			fail_event_fact_ack_count > 0
			and str(command.get("operation", "")) == "ack_event_fact"
		):
			fail_event_fact_ack_count -= 1
			return {
				"ok": false,
				"code": &"INTEGRITY_FAILURE",
				"new_revision": expected_revision,
				"context": {"stage": "injected_event_fact_ack"},
			}
		return super._commit_event_runtime_state(command, expected_revision)


class DriverFixture:
	extends Node
	var profile_resolver: Callable

	func configure_profile_launch_resolver(value: Callable) -> void:
		profile_resolver = value


class RunnerFixture:
	extends Node
	var native_binding: Dictionary = {}
	var _native_launch_driver := DriverFixture.new()

	func _init() -> void:
		add_child(_native_launch_driver)

	signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
	signal spawn_requested(spawn_definition: Dictionary)
	signal encounter_completed(encounter_id: StringName)
	signal encounter_failed(
		encounter_id: StringName, reason: StringName, context: Dictionary
	)

	func configure_native_launch(controller: Node, facade: RefCounted, player: Node, scene_resolver: Callable) -> bool:
		native_binding = {"controller": controller, "facade": facade, "player": player, "scene_resolver": scene_resolver}
		return controller != null and facade != null and player != null and scene_resolver.is_valid()

	func start_encounter(_definition: Dictionary, _seed: int, _room: int) -> void:
		pass

	func cancel() -> void:
		pass

	func is_active() -> bool:
		return false

	func snapshot() -> Dictionary:
		return {}


class ControllerFixture:
	extends Node

	var runner := RunnerFixture.new()
	var configured_runtime: Node

	func _init() -> void:
		add_child(runner)

	func encounter_runner() -> Node:
		return runner

	func configure_authored_runtime(runtime: Node, _catalog: RefCounted) -> bool:
		configured_runtime = runtime
		return true

	func configure_hostile_threat_authority(
		_scope: Dictionary, _authority: RefCounted
	) -> bool:
		return true


class PlayerFixture:
	extends Node

	var run_id: StringName = &""

	func configure_run(value: StringName) -> bool:
		run_id = value
		return true

	func configure_loadout(_config: Dictionary) -> bool:
		return true

	func reward_effect_snapshot() -> Dictionary:
		return {"configured": true, "health": {"current_hp": 100.0, "max_hp": 100.0}}

	func restore_reward_effect_snapshot(_value: Dictionary) -> bool:
		return true

	func reward_effect_apply_operation(_operation: Dictionary) -> bool:
		return true

	func reward_effect_begin_publication() -> bool:
		return true

	func reward_effect_publication_can_commit() -> bool:
		return true

	func reward_effect_commit_publication() -> bool:
		return true

	func reward_effect_rollback_publication() -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_real_facade_event_flow_and_restore(suite)
	_test_event_fact_ack_retry_is_idempotent(suite)
	_test_launch_host_creates_connected_room_runtime(suite)
	suite.finish(get_tree())


func _test_real_facade_event_flow_and_restore(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "event Facade boots the real Base Pack")
	if not booted.ok:
		return
	var started = facade.start_run(_launch_config(SEED), "event-facade-flow")
	suite.assert_true(started.ok, "event Facade starts a generated Launch floor")
	if not started.ok:
		return
	var start_snapshot: Dictionary = facade.snapshot()
	suite.assert_true(
		start_snapshot.get("dungeon_event_runtime", {}) is Dictionary
		and not (start_snapshot.get("dungeon_event_runtime", {}) as Dictionary).is_empty(),
		"Launch startup stores the complete event runtime in RunState"
	)
	var initial_plan := (start_snapshot.get("floor_plan", {}) as Dictionary).duplicate(true)
	var initial_digest := str(initial_plan.get("generation_digest", ""))
	var event_node_id := _first_reachable_event_node(initial_plan)
	suite.assert_true(not event_node_id.is_empty(), "generated FloorPlan has a reachable event node")
	if event_node_id.is_empty():
		return
	var primary_event_id := str(_node(initial_plan, event_node_id).get("event_id", ""))
	var recorder := FactRecorder.new()
	var connected := _connect_event_facts(recorder)
	suite.assert_true(connected, "EventBus declares committed event fact signals")
	if not connected:
		return
	var reached := _drive_to_node(facade, event_node_id)
	suite.assert_true(reached, "route finalization reaches the event room")
	if not reached:
		_disconnect_event_facts(recorder)
		return
	var opened = facade.call("open_current_event", {})
	suite.assert_true(opened.ok, "event room opens through the production Facade")
	if not opened.ok:
		_disconnect_event_facts(recorder)
		return
	var view: Dictionary = facade.call("event_view_state")
	suite.assert_true(not view.is_empty(), "opened event exposes a UI-safe view")
	suite.assert_equal(str(view.get("phase", "")), "open", "event begins in open phase")
	var selected_event_id := str(view.get("event_id", ""))
	suite.assert_true(not selected_event_id.is_empty(), "selector freezes a concrete event")
	var room: Dictionary = facade.current_room_definition()
	suite.assert_equal(
		str(room.get("event_id", "")), selected_event_id,
		"runtime room definition overlays the selected event"
	)
	var opened_snapshot: Dictionary = facade.snapshot()
	var opened_plan := opened_snapshot.get("floor_plan", {}) as Dictionary
	suite.assert_equal(
		str(_node(opened_plan, event_node_id).get("event_id", "")),
		primary_event_id,
		"selected overlay does not rewrite the generated primary candidate"
	)
	suite.assert_equal(
		str(opened_plan.get("generation_digest", "")), initial_digest,
		"selected overlay preserves the FloorPlan generation digest"
	)

	var restored = RunRuntimeFacadeScript.new()
	var restore_booted = restored.boot()
	suite.assert_true(restore_booted.ok, "restore Facade boots")
	var restored_result = restored.restore_launch_run(opened_snapshot)
	suite.assert_true(restored_result.ok, "restore rebuilds the event runtime")
	if restored_result.ok:
		suite.assert_equal(restored.call("event_view_state"), view, "restore preserves the exact event view")
		suite.assert_equal(
			str(restored.current_room_definition().get("event_id", "")),
			selected_event_id,
			"restore rebuilds the selected-event Director overlay"
		)
		suite.assert_equal(
			str((restored.snapshot().get("floor_plan", {}) as Dictionary).get("generation_digest", "")),
			initial_digest,
			"restore leaves the generated FloorPlan digest unchanged"
		)

	var option_id := _first_eligible_option(view)
	suite.assert_true(not option_id.is_empty(), "opened event has an eligible authored option")
	if not option_id.is_empty():
		var chosen = facade.call(
			"choose_current_event_option", StringName(option_id), int(view.get("revision", -1))
		)
		suite.assert_true(chosen.ok, "Facade commits an authored event option")
		if chosen.ok:
			var chosen_view := chosen.context.get("view_state", {}) as Dictionary
			var continuation := chosen.context.get("continuation", {}) as Dictionary
			match str(chosen_view.get("phase", "")):
				"pending_reward":
					var reward_result = facade.call(
						"complete_current_event_reward",
						str(continuation.get("continuation_id", "")),
						{"accepted": true},
						int(chosen_view.get("revision", -1))
					)
					suite.assert_true(reward_result.ok, "Facade completes an authenticated reward continuation")
					chosen_view = reward_result.context.get("view_state", {}) as Dictionary
				"pending_encounter":
					var encounter_result = facade.call(
						"complete_current_event_encounter",
						str(continuation.get("continuation_id", "")),
						true,
						{"encounter_id": str(continuation.get("encounter_id", ""))},
						int(chosen_view.get("revision", -1))
					)
					suite.assert_true(encounter_result.ok, "Facade completes an authenticated encounter continuation")
					chosen_view = encounter_result.context.get("view_state", {}) as Dictionary
			if str(chosen_view.get("phase", "")) == "resolved":
				var dismissed = facade.call(
					"dismiss_current_event", int(chosen_view.get("revision", -1))
				)
				suite.assert_true(dismissed.ok, "Facade dismisses the committed event result")
				if dismissed.ok:
					suite.assert_equal(
						str((dismissed.context.get("view_state", {}) as Dictionary).get("phase", "")),
						"dismissed",
						"dismissal reaches the event terminal phase"
					)

	suite.assert_true(not recorder.facts.is_empty(), "committed event operations publish safe facts")
	for fact: Dictionary in recorder.facts:
		for forbidden: String in FORBIDDEN_FACT_FIELDS:
			suite.assert_true(not fact.has(forbidden), "EventBus fact omits %s" % forbidden)
	_disconnect_event_facts(recorder)


func _test_event_fact_ack_retry_is_idempotent(suite) -> void:
	var facade := AckFailingFacade.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "ack retry Facade boots the real Base Pack")
	if not booted.ok:
		return
	var started = facade.start_run(_launch_config(SEED + 2), "event-fact-ack-retry")
	suite.assert_true(started.ok, "ack retry Facade starts a generated Launch floor")
	if not started.ok:
		return
	var event_node_id := _first_reachable_event_node(
		facade.snapshot().get("floor_plan", {}) as Dictionary
	)
	suite.assert_true(not event_node_id.is_empty(), "ack retry floor has a reachable event node")
	if event_node_id.is_empty() or not _drive_to_node(facade, event_node_id):
		suite.assert_true(false, "ack retry fixture reaches the event room")
		return
	var recorder := FactRecorder.new()
	if not _connect_event_facts(recorder):
		suite.assert_true(false, "ack retry fixture connects EventBus facts")
		return

	facade.fail_next_event_fact_ack()
	var failed = facade.call("open_current_event", {})
	suite.assert_true(not failed.ok, "injected fact ack failure is surfaced")
	suite.assert_equal(
		failed.code,
		&"INTEGRITY_FAILURE",
		"ack failure preserves the state-sink error code"
	)
	suite.assert_equal(
		recorder.facts.size(),
		1,
		"event fact reaches EventBus before durable ack fails"
	)
	suite.assert_equal(
		(facade.snapshot().get("dungeon_event_runtime", {}) as Dictionary)
			.get("pending_facts", [])
			.size(),
		1,
		"failed ack keeps the event fact in the durable outbox"
	)

	var retried = facade.call("open_current_event", {})
	suite.assert_true(retried.ok, "event open retries and acknowledges the pending fact")
	suite.assert_equal(
		recorder.facts.size(),
		1,
		"retrying the same fact ID does not emit a duplicate EventBus fact"
	)
	suite.assert_equal(
		(facade.snapshot().get("dungeon_event_runtime", {}) as Dictionary)
			.get("pending_facts", [])
			.size(),
		0,
		"successful retry drains the durable outbox"
	)
	_disconnect_event_facts(recorder)


func _test_launch_host_creates_connected_room_runtime(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	if not booted.ok:
		suite.assert_true(false, "Host fixture Facade boots")
		return
	var controller := ControllerFixture.new()
	var player := PlayerFixture.new()
	controller.add_child(player)
	player.name = "Player"
	var host = RunRuntimeHostScript.new()
	host.set("_active", true)
	host.set("_facade", facade)
	host.set("_room_controller", controller)
	host.set("_player", player)
	var started = host.start_run(_launch_config(SEED + 1))
	suite.assert_true(started.ok, "Launch Host starts through the real Base Pack Facade: " + str(started.code) + " " + str(started.context))
	if started.ok:
		suite.assert_true(controller.runner._native_launch_driver.profile_resolver.is_valid(), "Host binds the profile receipt resolver to its native driver")
		suite.assert_true(
			controller.runner.native_binding.get("controller") == controller
			and controller.runner.native_binding.get("player") == player
			and controller.runner.native_binding.get("facade") == facade,
			"Launch Host configures its same native encounter participants"
		)
		var runtime_value: Variant = host.get("_room_runtime")
		suite.assert_true(runtime_value is Node, "Launch Host creates and owns a RoomRuntime")
		suite.assert_equal(
			controller.configured_runtime,
			runtime_value,
			"Launch Host connects the same RoomRuntime to the room controller"
		)
	host.free()
	controller.free()


func _drive_to_node(facade: RefCounted, target_node_id: String) -> bool:
	var path := _edge_path(facade.snapshot().get("floor_plan", {}) as Dictionary, target_node_id)
	if path.is_empty():
		return false
	for edge_id: String in path:
		var begun = facade.call("begin_route_transition", StringName(edge_id), int(facade.snapshot().get("revision", -1)))
		if begun == null or not begun.ok:
			return false
		var transition_id := str(begun.context.get("transition_id", ""))
		var finalized = facade.call("finalize_route_transition", transition_id, int(begun.new_revision))
		if finalized == null or not finalized.ok:
			return false
		var confirmed = facade.call("confirm_route_transition", transition_id, int(finalized.new_revision))
		if confirmed == null or not confirmed.ok:
			return false
		var room := facade.call("current_room_definition") as Dictionary
		if str(room.get("node_id", "")) != target_node_id:
			var completed = facade.call("complete_current_room")
			if completed == null or not completed.ok:
				return false
	return str((facade.call("current_room_definition") as Dictionary).get("node_id", "")) == target_node_id


func _first_reachable_event_node(plan: Dictionary) -> String:
	var queue: Array[String] = [str(plan.get("entry_node_id", "entry"))]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		var node := _node(plan, node_id)
		if str(node.get("room_type", "")) == "event":
			return node_id
		for edge_value: Variant in plan.get("edges", []):
			if not edge_value is Dictionary:
				continue
			var edge := edge_value as Dictionary
			if str(edge.get("source_node_id", "")) == node_id and not bool(edge.get("locked", false)):
				queue.append(str(edge.get("destination_node_id", "")))
	return ""


func _edge_path(plan: Dictionary, target_node_id: String) -> Array[String]:
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
			if str(edge.get("source_node_id", "")) != source_id or bool(edge.get("locked", false)):
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


func _node(plan: Dictionary, node_id: String) -> Dictionary:
	for value: Variant in plan.get("nodes", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == node_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _first_eligible_option(view: Dictionary) -> String:
	for value: Variant in view.get("options", []):
		if value is Dictionary and bool((value as Dictionary).get("eligible", false)):
			return str((value as Dictionary).get("id", ""))
	return ""


func _connect_event_facts(recorder: FactRecorder) -> bool:
	var connections := {
		"event_opened": recorder.opened,
		"event_committed": recorder.committed,
		"event_reward_completed": recorder.reward_completed,
		"event_encounter_completed": recorder.encounter_completed,
		"event_dismissed": recorder.dismissed,
	}
	for signal_name: String in connections:
		if not EventBus.has_signal(signal_name):
			return false
		EventBus.connect(signal_name, connections[signal_name] as Callable)
	return true


func _disconnect_event_facts(recorder: FactRecorder) -> void:
	var connections := {
		"event_opened": recorder.opened,
		"event_committed": recorder.committed,
		"event_reward_completed": recorder.reward_completed,
		"event_encounter_completed": recorder.encounter_completed,
		"event_dismissed": recorder.dismissed,
	}
	for signal_name: String in connections:
		var callable := connections[signal_name] as Callable
		if EventBus.has_signal(signal_name) and EventBus.is_connected(signal_name, callable):
			EventBus.disconnect(signal_name, callable)


func _launch_config(seed: int) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": seed,
	}
