extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const ProjectileScene := preload("res://scenes/enemies/enemy_projectile.tscn")
const BossTimeCrackScript := preload("res://scripts/enemies/boss_time_crack.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _assert_elite_resistance()
	await _assert_overlapping_enemy_stops()
	await _assert_overlapping_projectile_stops()
	await _assert_overlapping_crack_stops()
	_suite.finish(get_tree())


func _assert_elite_resistance() -> void:
	var normal := ChaserScene.instantiate()
	var elite := ChaserScene.instantiate()
	add_child(normal)
	add_child(elite)
	await get_tree().process_frame
	normal.set_physics_process(false)
	elite.set_physics_process(false)
	elite.apply_elite_modifier()

	normal.apply_time_stop(0.24)
	elite.apply_time_stop(0.24)
	_suite.assert_true(normal.is_time_stopped(), "normal enemy stops immediately")
	_suite.assert_true(elite.is_time_stopped(), "elite enemy stops immediately")
	await get_tree().create_timer(0.16).timeout
	_suite.assert_true(normal.is_time_stopped(), "normal enemy keeps the full stop duration")
	_suite.assert_true(not elite.is_time_stopped(), "elite enemy recovers at the 0.5 duration multiplier")
	await get_tree().create_timer(0.12).timeout
	_suite.assert_true(not normal.is_time_stopped(), "normal enemy eventually recovers")

	normal.queue_free()
	elite.queue_free()
	await get_tree().process_frame


func _assert_overlapping_enemy_stops() -> void:
	var enemy := ChaserScene.instantiate()
	add_child(enemy)
	await get_tree().process_frame
	enemy.set_physics_process(false)
	enemy.apply_time_stop(0.12)
	await get_tree().create_timer(0.04).timeout
	enemy.apply_time_stop(0.30)
	await get_tree().create_timer(0.12).timeout
	_suite.assert_true(enemy.is_time_stopped(), "earlier enemy token cannot release a later stop")
	await get_tree().create_timer(0.22).timeout
	_suite.assert_true(not enemy.is_time_stopped(), "enemy releases after the final stop token expires")
	enemy.queue_free()
	await get_tree().process_frame


func _assert_overlapping_projectile_stops() -> void:
	var projectile := ProjectileScene.instantiate()
	add_child(projectile)
	await get_tree().process_frame
	projectile.apply_time_stop(0.12)
	await get_tree().create_timer(0.04).timeout
	projectile.apply_time_stop(0.30)
	await get_tree().create_timer(0.12).timeout
	_suite.assert_true(projectile.is_time_stopped(), "earlier projectile token cannot release a later stop")
	await get_tree().create_timer(0.22).timeout
	_suite.assert_true(not projectile.is_time_stopped(), "projectile releases after the final stop token expires")
	projectile.queue_free()
	await get_tree().process_frame


func _assert_overlapping_crack_stops() -> void:
	var crack := BossTimeCrackScript.new()
	crack.arm_delay = 1.0
	add_child(crack)
	await get_tree().process_frame
	crack.apply_time_stop(0.12)
	await get_tree().create_timer(0.04).timeout
	crack.apply_time_stop(0.30)
	await get_tree().create_timer(0.12).timeout
	_suite.assert_true(crack.is_time_stopped(), "earlier crack token cannot release a later stop")
	_suite.assert_true(not crack.has_exploded(), "stopped crack does not explode")
	await get_tree().create_timer(0.22).timeout
	_suite.assert_true(not crack.is_time_stopped(), "crack releases after the final stop token expires")
	crack.queue_free()
	await get_tree().process_frame
