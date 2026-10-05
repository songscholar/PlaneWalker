extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")
const Orchestrator := preload("res://scripts/application/run_orchestrator.gd")
const Lifetime := preload("res://scripts/events/event_modifier_lifetime.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Floors := preload("res://scripts/dungeon/floor_definition.gd")


class CountingOrchestrator:
	extends Orchestrator
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 6}
	var launched: bool = main._launch_run(config, false, true)
	suite.assert_true(launched, "observation queries bind a real Launch Main")
	if not launched:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("NativeRunReplayRecorder").set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	var facade: RefCounted = host.native_checkpoint_participants().facade
	var original: RefCounted = facade.get("_orchestrator")
	var counted := CountingOrchestrator.new()
	counted.set("_state", original.get("_state"))
	counted.set("_pending_route_transition", original.get("_pending_route_transition"))
	counted.set("_next_route_transition_id", original.get("_next_route_transition_id"))
	facade.set("_orchestrator", counted)
	var initial: Dictionary = host.runtime_snapshot()
	counted.full_snapshot_calls = 0
	for _read: int in range(12):
		suite.assert_equal(host.runtime_snapshot(), initial, "stable repeated observation preserves the complete native Run")
	suite.assert_equal(counted.full_snapshot_calls, 12, "each complete export materializes one Run snapshot; health and modifier queries stay narrow")
	var exported: Dictionary = host.runtime_snapshot()
	exported.floor_plan.nodes[0].id = "caller-mutation"
	exported.resources.health.current = -1.0
	exported.config.seed = -1
	suite.assert_equal(host.runtime_snapshot(), initial, "removing redundant copies preserves deep caller isolation")
	var supported := counted.has_method("event_health_snapshot") and counted.has_method("dungeon_event_snapshot") and counted.has_method("event_modifier_projection")
	suite.assert_true(supported, "orchestrator exposes detached event observations without exporting unrelated Run domains")
	if supported:
		var health: Dictionary = counted.call("event_health_snapshot")
		var event: Dictionary = counted.call("dungeon_event_snapshot")
		var projection: Dictionary = counted.call("event_modifier_projection")
		var parts: Dictionary = initial.dungeon_event_runtime.consequence_runtime.participant_snapshots
		suite.assert_equal(health, parts.health, "narrow health query retains the authoritative event participant")
		suite.assert_equal(event, initial.dungeon_event_runtime, "event-only export retains complete event restoration data")
		suite.assert_equal(projection, Lifetime.active_projection(initial.events, parts.event_state.selected_event_by_node, parts.modifier.temporary_modifiers), "narrow modifiers use the existing authenticated lifetime authority")
		health.current = -1.0
		event.consequence_runtime.participant_snapshots.health.current = -2.0
		suite.assert_equal(counted.call("event_health_snapshot"), parts.health, "narrow exports cannot mutate authoritative health")
		var player: Node = main.get_node("CombatRoom01/Player")
		var physical: Dictionary = player.reward_effect_snapshot()
		physical.health.current_hp -= 13.0
		suite.assert_true(player.restore_reward_effect_snapshot(physical, false), "fixture changes actual physical health through its restore boundary")
		var hurt: Dictionary = host.runtime_snapshot()
		suite.assert_close(hurt.resources.health.current, physical.health.current_hp, "complete export still synchronizes changed physical health")
		suite.assert_close(counted.call("event_health_snapshot").current, physical.health.current_hp, "health authority catches up to actual physical damage")
		counted.full_snapshot_calls = 0
		for _read: int in range(8):
			suite.assert_equal(host.runtime_snapshot(), hurt, "changed health remains stable on repeated observations")
		suite.assert_equal(counted.full_snapshot_calls, 8, "stable changed health requires no repeated event reconstruction")
		_test_modifier_observation(suite, counted)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	suite.finish(get_tree())


func _test_modifier_observation(suite: RefCounted, counted: RefCounted) -> void:
	var state: RefCounted = counted.native_run_state()
	var original: Dictionary = state.dungeon_event_runtime.duplicate(true)
	var events: Array = state.events.duplicate(true)
	var phase: int = state.phase
	# Synthetic accepted event participant isolates projection lifetime and ownership.
	state.events = []
	var parts: Dictionary = state.dungeon_event_runtime.consequence_runtime.participant_snapshots
	parts.event_state.selected_event_by_node = {Floors.FLOOR_IDS[0] + ":event_1": {"floor_id": Floors.FLOOR_IDS[0], "floor_index": 0, "node_id": "event_1", "transaction_id": "tx_query", "phase": "resolved"}}
	parts.modifier.temporary_modifiers = [{"modifier_id": "chronal_grace", "duration_rooms": 3, "magnitude": 1.15, "source_transaction_id": "tx_query"}]
	var expected := [{"modifier_id": "chronal_grace", "magnitude": 1.15, "source_transaction_id": "tx_query"}]
	var projection: Dictionary = counted.call("event_modifier_projection")
	suite.assert_true(projection.ok, "narrow observation authenticates an accepted temporary modifier source")
	if not projection.ok:
		state.phase = phase
		state.dungeon_event_runtime = original
		state.events = events
		return
	suite.assert_equal(projection.context.modifiers, expected, "active source reaches the detached projection")
	if not projection.context.modifiers.is_empty():
		projection.context.modifiers[0].magnitude = 9.0
	suite.assert_equal(counted.call("event_modifier_projection").context.modifiers, expected, "projection mutation cannot rewrite the authoritative grant")
	state.phase = Phase.Value.VICTORY
	suite.assert_equal(counted.call("event_modifier_projection").context.modifiers, [], "terminal state retires active temporary modifiers through the narrow authority")
	state.phase = phase
	state.dungeon_event_runtime = original
	state.events = events
