extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ProjectileScene := preload("res://scenes/enemies/enemy_projectile.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var player := PlayerScene.instantiate()
	var projectile := ProjectileScene.instantiate()
	projectile.lifetime = 1.0
	_suite.assert_true(
		projectile.configure_attack_identity(&"projectile-test-run", &"shooter-test", 7, 2, null),
		"projectile fixture installs an authoritative launch identity"
	)
	add_child(player)
	add_child(projectile)
	await get_tree().process_frame

	var health: Node = player.get_node("HealthComponent")
	var hurtbox: Area2D = player.get_node("Hurtbox")
	var damage_events := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: damage_events[0] += 1)
	var starting_hp: float = health.current_hp

	projectile._on_area_entered(hurtbox)
	projectile._on_body_entered(player)

	var identity: Dictionary = projectile.attack_identity_snapshot()
	_suite.assert_equal(identity.get("hostile_source_id"), &"shooter-test", "projectile damage keeps the shooter source")
	_suite.assert_equal(identity.get("attack_generation"), 7, "projectile damage keeps the launch generation")
	_suite.assert_equal(identity.get("hit_index"), 2, "projectile damage keeps the authored pellet index")
	_suite.assert_close(health.current_hp, starting_hp - projectile.damage, "one projectile contact applies damage once")
	_suite.assert_equal(damage_events[0], 1, "one projectile contact emits one damage event")
	_suite.assert_true(projectile._resolved, "projectile resolves atomically before deferred deletion")

	player.queue_free()
	await get_tree().create_timer(0.06).timeout

	var frozen_projectile := ProjectileScene.instantiate()
	frozen_projectile.lifetime = 0.05
	frozen_projectile.set_physics_process(false)
	add_child(frozen_projectile)
	frozen_projectile.apply_time_stop_source(&"test", 1.0)
	frozen_projectile._physics_process(0.07)
	_suite.assert_true(
		is_instance_valid(frozen_projectile)
		and not frozen_projectile.is_queued_for_deletion()
		and frozen_projectile.is_time_stopped(),
		"time stop pauses projectile lifetime"
	)
	_suite.assert_close(
		float(frozen_projectile.get("_age")),
		0.0,
		"time-stopped projectile age does not advance"
	)
	frozen_projectile.clear_time_stop_source(&"test")
	frozen_projectile._physics_process(0.06)
	_suite.assert_true(
		frozen_projectile.is_queued_for_deletion(),
		"projectile lifetime resumes after time stop"
	)
	_suite.finish(get_tree())
