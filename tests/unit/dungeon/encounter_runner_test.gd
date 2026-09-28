extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EncounterRunnerScript := preload("res://scripts/dungeon/encounter_runner.gd")

var _runner: Node
var _enemies_root: Node2D
var _spawned: Array[Node] = []
var _wave_ids: Array[String] = []
var _completion_count: int = 0


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

	_runner.start_encounter(_two_wave_encounter(), 20260928, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_wave_ids, ["wave_01"], "runner starts only the first wave")
	suite.assert_equal(_spawned.size(), 2, "runner requests every first-wave spawn")
	suite.assert_equal(_runner.alive_count(), 2, "runner exclusively counts first-wave actors")

	EventBus.entity_died.emit(_spawned[0], null)
	suite.assert_equal(_runner.alive_count(), 1, "one defeat decrements alive count once")
	EventBus.entity_died.emit(_spawned[0], null)
	suite.assert_equal(_runner.alive_count(), 1, "duplicate death cannot decrement twice")
	EventBus.entity_died.emit(_spawned[1], null)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(_wave_ids, ["wave_01", "wave_02"], "next wave waits for zero alive actors")
	suite.assert_equal(_runner.alive_count(), 1, "second wave owns its alive count")

	var summon := Node2D.new()
	summon.add_to_group("enemies")
	_enemies_root.add_child(summon)
	EventBus.enemy_spawned.emit(summon)
	suite.assert_equal(_runner.alive_count(), 2, "runner counts an in-room summon")
	EventBus.entity_died.emit(_spawned[2], null)
	suite.assert_equal(_runner.alive_count(), 1, "encounter remains active while summon lives")
	EventBus.entity_died.emit(summon, null)
	await get_tree().process_frame
	suite.assert_equal(_runner.alive_count(), 0, "all actors are cleared")
	suite.assert_equal(_completion_count, 1, "encounter completes exactly once")
	EventBus.entity_died.emit(summon, null)
	suite.assert_equal(_completion_count, 1, "late duplicate death cannot complete twice")

	_runner.start_encounter(_two_wave_encounter(), 20260928, 2)
	await get_tree().process_frame
	_runner.cancel()
	var count_after_cancel := _completion_count
	for actor: Node in _spawned:
		EventBus.entity_died.emit(actor, null)
	await get_tree().process_frame
	suite.assert_equal(_completion_count, count_after_cancel, "cancelled encounter ignores delayed deaths")

	_runner.queue_free()
	_enemies_root.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _on_spawn_requested(spawn_definition: Dictionary) -> void:
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
