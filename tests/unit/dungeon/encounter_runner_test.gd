extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EncounterRunnerScript := preload("res://scripts/dungeon/encounter_runner.gd")

var _runner: Node
var _enemies_root: Node2D
var _spawned: Array[Node] = []
var _wave_ids: Array[String] = []
var _completion_count: int = 0
var _spawn_mode: StringName = &"register"
var _rejected_spawns: Array[Dictionary] = []
var _failures: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_runner = EncounterRunnerScript.new()
	add_child(_runner)
	_enemies_root = Node2D.new()
	add_child(_enemies_root)
	_runner.configure(_enemies_root)
	_runner.spawn_requested.connect(_on_spawn_requested)
	_runner.wave_started.connect(_on_wave_started)
	_runner.encounter_completed.connect(_on_encounter_completed)
	_runner.spawn_rejected.connect(_on_spawn_rejected)
	_runner.encounter_failed.connect(_on_encounter_failed)

	_runner.start_encounter(_two_wave_encounter(), 20260928, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_wave_ids, ["wave_01"], "runner starts only the first wave")
	suite.assert_equal(_spawned.size(), 2, "runner requests every first-wave spawn")
	suite.assert_equal(_runner.alive_count(), 2, "runner exclusively counts first-wave actors")

	_runner.notify_entity_defeated(_spawned[0])
	suite.assert_equal(_runner.alive_count(), 1, "one defeat decrements alive count once")
	_runner.notify_entity_defeated(_spawned[0])
	suite.assert_equal(_runner.alive_count(), 1, "duplicate death cannot decrement twice")
	_runner.notify_entity_defeated(_spawned[1])
	var late_summon := Node2D.new()
	late_summon.add_to_group("enemies")
	_enemies_root.add_child(late_summon)
	_runner.register_spawned(late_summon, {"id": "late-summon"})
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_wave_ids, ["wave_01"], "late summon cancels the deferred wave advance")
	suite.assert_equal(_runner.current_wave_index(), 0, "late summon keeps the runner on the completed wave")
	_runner.notify_entity_defeated(late_summon)
	late_summon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_wave_ids, ["wave_01", "wave_02"], "next wave waits for zero alive actors")
	suite.assert_equal(_runner.alive_count(), 1, "second wave owns its alive count")

	var summon := Node2D.new()
	summon.add_to_group("enemies")
	_enemies_root.add_child(summon)
	_runner.register_spawned(summon, {"id": "summon"})
	suite.assert_equal(_runner.alive_count(), 2, "runner counts an in-room summon")
	_runner.notify_entity_defeated(_spawned[2])
	suite.assert_equal(_runner.alive_count(), 1, "encounter remains active while summon lives")
	_runner.notify_entity_defeated(summon)
	await get_tree().process_frame
	suite.assert_equal(_runner.alive_count(), 0, "all actors are cleared")
	suite.assert_equal(_completion_count, 1, "encounter completes exactly once")
	_runner.notify_entity_defeated(summon)
	suite.assert_equal(_completion_count, 1, "late duplicate death cannot complete twice")

	_runner.start_encounter(_two_wave_encounter(), 20260928, 2)
	await get_tree().process_frame
	_runner.cancel()
	var count_after_cancel := _completion_count
	for actor: Node in _spawned:
		_runner.notify_entity_defeated(actor)
	await get_tree().process_frame
	suite.assert_equal(_completion_count, count_after_cancel, "cancelled encounter ignores delayed deaths")

	_spawn_mode = &"reject"
	_runner.start_encounter(_two_wave_encounter(), 20260928, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_rejected_spawns.size(), 1, "spawn rejection is observable")
	suite.assert_equal(_failures.size(), 1, "spawn rejection fails the encounter exactly once")
	suite.assert_true(not _runner.is_active(), "rejected spawn terminates the encounter")
	suite.assert_equal(_runner.snapshot()["pending_spawn_count"], 0, "rejected spawn clears pending work")

	_spawn_mode = &"ignore"
	_runner.start_encounter(_two_wave_encounter(), 20260928, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_rejected_spawns.size(), 2, "unacknowledged spawn is rejected by the runner")
	suite.assert_equal(_failures.size(), 2, "unacknowledged spawn cannot leave an active encounter")
	suite.assert_equal(_runner.snapshot()["pending_spawn_count"], 0, "unacknowledged spawn cannot remain pending")

	_spawn_mode = &"register"
	_runner.start_encounter({}, 20260928, 2)
	suite.assert_equal(_failures.size(), 3, "empty encounter fails explicitly")
	suite.assert_true(not _runner.is_active(), "empty encounter never becomes active")
	suite.assert_equal(_runner.snapshot()["pending_spawn_count"], 0, "empty encounter leaves no pending work")

	_runner.queue_free()
	_enemies_root.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _on_spawn_requested(spawn_definition: Dictionary) -> void:
	if _spawn_mode == &"reject":
		_runner.reject_spawn(spawn_definition, &"TEST_REJECTION")
		return
	if _spawn_mode == &"ignore":
		return
	var actor := Node2D.new()
	actor.add_to_group("enemies")
	actor.set_meta("spawn_id", spawn_definition.get("id", ""))
	_enemies_root.add_child(actor)
	_spawned.append(actor)
	_runner.register_spawned(actor, spawn_definition)


func _on_wave_started(_wave_index: int, wave_id: StringName) -> void:
	_wave_ids.append(str(wave_id))


func _on_encounter_completed(_encounter_id: StringName) -> void:
	_completion_count += 1


func _on_spawn_rejected(spawn_definition: Dictionary, reason: StringName) -> void:
	_rejected_spawns.append({
		"spawn": spawn_definition.duplicate(true),
		"reason": reason,
	})


func _on_encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary) -> void:
	_failures.append({
		"encounter_id": encounter_id,
		"reason": reason,
		"context": context.duplicate(true),
	})


func _two_wave_encounter() -> Dictionary:
	return {
		"id": "runner_test",
		"waves": [
			{
				"id": "wave_01",
				"delay_seconds": 0.0,
				"telegraph_seconds": 0.0,
				"spawns": [
					{"id": "spawn_01", "enemy_id": "chaser", "spawn_slot_id": "slot_a", "mechanism_ids": []},
					{"id": "spawn_02", "enemy_id": "shooter", "spawn_slot_id": "slot_b", "mechanism_ids": []},
				],
			},
			{
				"id": "wave_02",
				"delay_seconds": 0.0,
				"telegraph_seconds": 0.0,
				"spawns": [
					{"id": "spawn_03", "enemy_id": "tank", "spawn_slot_id": "slot_c", "mechanism_ids": []},
				],
			},
		],
	}
