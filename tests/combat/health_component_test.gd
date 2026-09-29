extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var original_persistent := GameState.persistent.duplicate(true)
	var owner := Node2D.new()
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 100.0
	owner.add_child(health)
	add_child(owner)
	await get_tree().process_frame

	health.apply_invulnerability(0.12)
	await get_tree().create_timer(0.04).timeout
	health.apply_invulnerability(0.32)
	await get_tree().create_timer(0.12).timeout

	var damage_info := DamageInfoScript.new(10.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	var blocked_damage: float = health.take_damage(damage_info)
	_suite.assert_close(blocked_damage, 0.0, "earlier expiry cannot end overlapping invulnerability")
	_suite.assert_close(health.current_hp, 100.0, "health remains unchanged before latest expiry")

	await get_tree().create_timer(0.24).timeout
	var applied_damage: float = health.take_damage(damage_info)
	_suite.assert_close(applied_damage, 10.0, "damage applies after latest invulnerability expiry")
	_suite.assert_close(health.current_hp, 90.0, "health changes after latest expiry")

	health.apply_invulnerability(0.08)
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	_suite.assert_true(health.invulnerable, "paused gameplay preserves invulnerability duration")
	get_tree().paused = false
	await get_tree().create_timer(0.10).timeout
	_suite.assert_true(not health.invulnerable, "invulnerability expires after gameplay resumes")

	owner.add_to_group("player")
	var settings := GameState.normalized_settings()
	settings["damage_received_multiplier"] = 0.6
	GameState.persistent["settings"] = settings
	health.current_hp = 100.0
	var default_damage: float = health.take_damage(damage_info)
	_suite.assert_close(default_damage, 10.0, "player damage defaults to an unassisted run without a snapshot")
	_suite.assert_close(health.current_hp, 90.0, "persistent settings do not leak into an unconfigured run")

	health.configure_accessibility_assists({"damage_received_multiplier": 0.6})
	health.current_hp = 100.0
	var assisted_damage: float = health.take_damage(damage_info)
	_suite.assert_close(assisted_damage, 6.0, "run snapshot damage assist reduces incoming damage deterministically")
	_suite.assert_close(health.current_hp, 94.0, "damage assist changes only the applied player damage")

	settings["damage_received_multiplier"] = 0.8
	GameState.persistent["settings"] = settings
	health.current_hp = 100.0
	var stable_damage: float = health.take_damage(damage_info)
	_suite.assert_close(stable_damage, 6.0, "mid-run persistent setting changes cannot mutate the run snapshot")
	_suite.assert_close(health.current_hp, 94.0, "recorded and applied damage assist stay aligned for the run")

	GameState.persistent = original_persistent
	owner.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())
