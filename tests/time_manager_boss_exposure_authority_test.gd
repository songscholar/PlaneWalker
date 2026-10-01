extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_unique_live_boss_authority_ignores_dead_bosses()
	await _test_multiple_live_bosses_require_exact_stable_identity()
	_suite.finish(get_tree())


func _test_unique_live_boss_authority_ignores_dead_bosses() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	add_child(player)
	await get_tree().process_frame
	var time_manager: Node = player.get_node("TimeManager")
	var dead_boss: Node = await _spawn_boss(&"hostile:dead-boss", &"spawn-dead")
	var live_boss: Node = await _spawn_boss(&"hostile:live-boss", &"spawn-live")
	dead_boss.get_node("HealthComponent").current_hp = 0.0
	dead_boss.get_node("HealthComponent").dead = true
	live_boss.apply_time_stop_source(&"live-window", 0.5)

	_suite.assert_equal(
		time_manager.active_boss_exposure_identity(),
		live_boss.character_boss_exposure_identity(),
		"dead Boss cannot block the unique active Boss authority"
	)
	_suite.assert_true(
		time_manager.extend_boss_exposure_frames(81, 30),
		"unique live Boss receives the exposure extension without instance-id ordering"
	)
	_suite.assert_equal(live_boss.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 81, "unique authority extends the live Boss")
	_suite.assert_equal(dead_boss.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 0, "dead Boss ledger remains untouched")
	await _cleanup_nodes([dead_boss, live_boss, player])


func _test_multiple_live_bosses_require_exact_stable_identity() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	add_child(player)
	await get_tree().process_frame
	var time_manager: Node = player.get_node("TimeManager")
	var first: Node = await _spawn_boss(&"hostile:first-live", &"spawn-first")
	var second: Node = await _spawn_boss(&"hostile:second-live", &"spawn-second")
	first.apply_time_stop_source(&"first-window", 0.5)
	second.apply_time_stop_source(&"second-window", 0.5)

	_suite.assert_equal(time_manager.active_boss_exposure_identity(), {}, "multiple live Bosses expose no ambiguous implicit authority")
	_suite.assert_true(
		not time_manager.extend_boss_exposure_frames(91, 30),
		"ambiguous multi-Boss encounter fails closed instead of choosing by instance id"
	)
	var second_identity: Dictionary = second.character_boss_exposure_identity()
	_suite.assert_true(
		time_manager.extend_boss_exposure_frames(91, 30, second_identity),
		"stable run/room/encounter/spawn/hostile identity selects the exact live Boss"
	)
	_suite.assert_equal(first.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 0, "identity-routed request cannot mutate the other live Boss")
	_suite.assert_equal(second.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 91, "identity-routed request mutates only its exact Boss")
	var foreign_identity := second_identity.duplicate(true)
	foreign_identity["room_id"] = "foreign-room"
	_suite.assert_true(
		not time_manager.extend_boss_exposure_frames(92, 30, foreign_identity),
		"foreign room identity cannot route a Boss exposure request"
	)
	_suite.assert_equal(second.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 91, "foreign request rejection is atomic")
	await _cleanup_nodes([first, second, player])


func _spawn_boss(source_id: StringName, spawn_id: StringName) -> Node:
	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	_suite.assert_true(boss.configure_hostile_identity(source_id, 1), "Boss authority fixture configures stable hostile identity")
	boss.set_meta("run_id", &"run-boss-authority")
	boss.set_meta("room_id", &"room-boss-authority")
	boss.set_meta("encounter_id", &"encounter-boss-authority")
	boss.set_meta("encounter_spawn_id", spawn_id)
	boss.set_meta("encounter_enemy_id", &"chrono_warden")
	add_child(boss)
	boss.set_physics_process(false)
	await get_tree().process_frame
	return boss


func _cleanup_nodes(nodes: Array) -> void:
	for node_value: Variant in nodes:
		if node_value is Node and is_instance_valid(node_value as Node):
			(node_value as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
