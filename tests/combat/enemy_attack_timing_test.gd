extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const ChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const ShooterScene := preload("res://scenes/enemies/enemy_shooter.tscn")
const TankScene := preload("res://scenes/enemies/enemy_tank.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var player := _create_player_target()
	await get_tree().process_frame

	await _assert_chaser_timing(player)
	await _assert_shooter_timing(player)
	_assert_declared_timings()

	player.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())


func _assert_chaser_timing(player: Node2D) -> void:
	var chaser := ChaserScene.instantiate()
	chaser.configure_hostile_identity(&"timing-chaser", 1)
	chaser.global_position = Vector2.ZERO
	player.global_position = Vector2(20.0, 0.0)
	var phases: Array[int] = []
	chaser.attack_phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	add_child(chaser)
	chaser.set_physics_process(false)

	var health: Node = player.get_node("HealthComponent")
	var starting_hp: float = health.current_hp
	var damage_events := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: damage_events[0] += 1)

	chaser._physics_process(0.01)
	_suite.assert_equal(chaser.attack_phase(), EnemyBaseScript.AttackPhase.WINDUP, "chaser begins a visible windup")
	_suite.assert_close(health.current_hp, starting_hp, "chaser windup deals zero immediate damage")

	chaser._physics_process(0.28)
	_suite.assert_close(health.current_hp, starting_hp, "chaser deals zero damage before windup ends")
	chaser._physics_process(0.03)
	_suite.assert_close(health.current_hp, starting_hp - chaser.attack, "chaser resolves once when windup ends")
	_suite.assert_equal(damage_events[0], 1, "chaser windup boundary emits one damage event")
	_suite.assert_equal(chaser.attack_phase(), EnemyBaseScript.AttackPhase.RECOVERY, "chaser enters recovery after resolving")

	var recovery_position: Vector2 = chaser.global_position
	player.global_position = Vector2(500.0, 0.0)
	chaser._physics_process(0.20)
	_suite.assert_true(chaser.is_attack_locked(), "chaser remains attack-locked during recovery")
	_suite.assert_equal(chaser.global_position, recovery_position, "chaser cannot move during recovery")
	chaser._physics_process(0.11)
	_suite.assert_equal(chaser.attack_phase(), EnemyBaseScript.AttackPhase.READY, "chaser returns to ready after recovery")
	_suite.assert_equal(phases, [
		EnemyBaseScript.AttackPhase.WINDUP,
		EnemyBaseScript.AttackPhase.RECOVERY,
		EnemyBaseScript.AttackPhase.READY,
	], "chaser emits one ordered phase sequence")

	chaser.queue_free()
	await get_tree().process_frame


func _assert_shooter_timing(player: Node2D) -> void:
	var shooter := ShooterScene.instantiate()
	shooter.configure_hostile_identity(&"timing-shooter", 1)
	shooter.global_position = Vector2.ZERO
	player.global_position = Vector2(220.0, 0.0)
	add_child(shooter)
	shooter.set_physics_process(false)

	var projectiles_before := get_tree().get_nodes_in_group("time_stoppable").filter(
		func(node: Node) -> bool: return node is Area2D and node.get_script() == preload("res://scripts/enemies/enemy_projectile.gd")
	).size()
	shooter._physics_process(0.01)
	_suite.assert_equal(shooter.attack_phase(), EnemyBaseScript.AttackPhase.WINDUP, "shooter begins a visible windup")
	shooter._physics_process(0.58)
	_suite.assert_equal(_projectile_count(), projectiles_before, "shooter spawns no projectile before windup ends")
	shooter._physics_process(0.03)
	_suite.assert_equal(_projectile_count(), projectiles_before + 1, "shooter spawns one projectile at the windup boundary")
	_suite.assert_equal(shooter.attack_phase(), EnemyBaseScript.AttackPhase.RECOVERY, "shooter enters recovery after firing")

	for projectile: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if projectile is Area2D and projectile.get_script() == preload("res://scripts/enemies/enemy_projectile.gd"):
			projectile.queue_free()
	shooter.queue_free()
	await get_tree().process_frame


func _assert_declared_timings() -> void:
	var chaser := ChaserScene.instantiate()
	var shooter := ShooterScene.instantiate()
	var tank := TankScene.instantiate()
	_suite.assert_close(chaser.attack_windup, 0.30, "chaser uses the planned windup")
	_suite.assert_close(chaser.attack_recovery, 0.30, "chaser uses the planned recovery")
	_suite.assert_close(shooter.attack_windup, 0.60, "shooter uses the planned windup")
	_suite.assert_close(shooter.attack_recovery, 0.45, "shooter uses the planned recovery")
	_suite.assert_close(tank.attack_windup, 0.75, "tank uses the planned windup")
	_suite.assert_close(tank.attack_recovery, 0.80, "tank uses the planned recovery")
	chaser.free()
	shooter.free()
	tank.free()


func _create_player_target() -> Node2D:
	var player := Node2D.new()
	player.name = "PlayerTarget"
	player.add_to_group("player")
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 500.0
	player.add_child(health)
	add_child(player)
	return player


func _projectile_count() -> int:
	return get_tree().get_nodes_in_group("time_stoppable").filter(
		func(node: Node) -> bool: return node is Area2D and node.get_script() == preload("res://scripts/enemies/enemy_projectile.gd")
	).size()
