extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const TankScene := preload("res://scenes/enemies/enemy_tank.tscn")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")

const REQUIRED_TANK_METHODS: Array[StringName] = [
	&"force_overload_pulse_for_test",
	&"set_overload_cooldown_for_test",
	&"advance_action_for_test",
	&"get_elite_action_snapshot_for_test",
]

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	if not await _assert_contract_available():
		_suite.finish(get_tree())
		return
	await _assert_normal_tank_never_triggers_overload()
	await _assert_elite_triggers_when_cooldown_expires()
	await _assert_deterministic_cooldown_sequence()
	await _assert_overload_telegraphs_and_resolves_once()
	await _assert_primary_attack_and_overload_share_one_clock()
	await _assert_time_stop_freezes_the_current_phase()
	await _assert_death_and_room_exit_clear_the_action()
	_suite.finish(get_tree())


func _assert_contract_available() -> bool:
	var subject: Dictionary = await _spawn_subject(false)
	var tank: Node = subject["tank"]
	var available := true
	for method_name: StringName in REQUIRED_TANK_METHODS:
		var has_method_contract := tank.has_method(method_name)
		_suite.assert_true(has_method_contract, "elite tank exposes %s" % method_name)
		available = available and has_method_contract
	await _cleanup_subject(subject)
	return available


func _assert_normal_tank_never_triggers_overload() -> void:
	var subject: Dictionary = await _spawn_subject(false)
	var tank: Node = subject["tank"]
	tank.set_overload_cooldown_for_test(0.0)
	tank._attack_cooldown_remaining = 99.0
	tank._physics_process(8.0)
	var snapshot: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_equal(snapshot["action"], "NONE", "ordinary tank never enters the elite active action")
	_suite.assert_equal(snapshot["resolution_count"], 0, "ordinary tank resolves no overload pulse")
	_suite.assert_true(not bool(snapshot["telegraph"].get("visible", true)), "ordinary tank shows no overload telegraph")
	await _cleanup_subject(subject)


func _assert_elite_triggers_when_cooldown_expires() -> void:
	var subject: Dictionary = await _spawn_subject(true)
	var tank: Node = subject["tank"]
	tank.set_overload_cooldown_for_test(0.1)
	tank._attack_cooldown_remaining = 99.0
	tank._physics_process(0.11)
	var snapshot: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_equal(snapshot["action"], "OVERLOAD_PULSE", "elite tank automatically commits overload when its cooldown expires")
	_suite.assert_equal(snapshot["phase"], "WINDUP", "automatic overload starts its telegraphed windup")
	await _cleanup_subject(subject)


func _assert_deterministic_cooldown_sequence() -> void:
	var subject: Dictionary = await _spawn_subject(true)
	var tank: Node = subject["tank"]
	var initial: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_close(float(initial["cooldown_remaining"]), 5.0, "first overload cooldown is deterministic")

	tank.set_overload_cooldown_for_test(0.0)
	_suite.assert_true(tank.force_overload_pulse_for_test(), "first overload can be forced when ready")
	tank.advance_action_for_test(0.91)
	var second: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_close(float(second["cooldown_remaining"]), 6.0, "second overload cooldown advances deterministically")
	tank.advance_action_for_test(2.0)

	tank.set_overload_cooldown_for_test(0.0)
	_suite.assert_true(tank.force_overload_pulse_for_test(), "second overload can be forced after recovery")
	tank.advance_action_for_test(0.91)
	var third: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_close(float(third["cooldown_remaining"]), 7.0, "third overload cooldown advances deterministically")
	await _cleanup_subject(subject)


func _assert_overload_telegraphs_and_resolves_once() -> void:
	var subject: Dictionary = await _spawn_subject(true)
	var tank: Node = subject["tank"]
	var health: Node = subject["health"]
	var damage_events := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: damage_events[0] += 1)
	var starting_hp: float = health.current_hp

	tank.set_overload_cooldown_for_test(0.0)
	_suite.assert_true(tank.force_overload_pulse_for_test(), "elite tank starts overload pulse")
	var windup: Dictionary = tank.get_elite_action_snapshot_for_test()
	var telegraph: Dictionary = windup["telegraph"]
	_suite.assert_equal(windup["action"], "OVERLOAD_PULSE", "overload owns the active action slot")
	_suite.assert_equal(windup["phase"], "WINDUP", "overload begins in windup")
	_suite.assert_equal(telegraph.get("action_id", ""), "OVERLOAD_PULSE", "overload telegraph has a stable action ID")
	_suite.assert_equal(telegraph.get("shape", ""), "circle", "overload uses a circular telegraph")
	_suite.assert_true(bool(telegraph.get("visible", false)), "overload telegraph is visible during windup")
	_suite.assert_close(float(telegraph.get("remaining", 0.0)), 0.9, "overload telegraph uses a 0.9 second windup")
	_suite.assert_close(health.current_hp, starting_hp, "overload windup deals no immediate damage")

	tank.advance_action_for_test(0.89)
	_suite.assert_close(health.current_hp, starting_hp, "overload deals no damage before the windup boundary")
	tank.advance_action_for_test(0.02)
	var recovery: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_equal(damage_events[0], 1, "overload resolves exactly one range damage event")
	_suite.assert_true(health.current_hp < starting_hp, "overload damages a target inside its radius")
	_suite.assert_equal(recovery["phase"], "RECOVERY", "overload enters recovery after resolving")
	_suite.assert_close(float(recovery["phase_remaining"]), 0.65, "overload has a committed recovery window")
	_suite.assert_equal(recovery["resolution_count"], 1, "overload records one resolution")
	_suite.assert_true(not bool(recovery["telegraph"].get("visible", true)), "overload clears its telegraph before recovery")
	tank.advance_action_for_test(0.2)
	_suite.assert_equal(damage_events[0], 1, "overload recovery cannot deal duplicate damage")
	await _cleanup_subject(subject)


func _assert_primary_attack_and_overload_share_one_clock() -> void:
	var pulse_subject: Dictionary = await _spawn_subject(true)
	var pulse_tank: Node = pulse_subject["tank"]
	pulse_tank.set_overload_cooldown_for_test(0.0)
	_suite.assert_true(pulse_tank.force_overload_pulse_for_test(), "overload enters the shared clock")
	_suite.assert_true(not pulse_tank._try_begin_primary_attack(), "melee cannot replace an active overload")
	_suite.assert_equal(pulse_tank.get_elite_action_snapshot_for_test()["action"], "OVERLOAD_PULSE", "blocked melee preserves overload")
	await _cleanup_subject(pulse_subject)

	var melee_subject: Dictionary = await _spawn_subject(true)
	var melee_tank: Node = melee_subject["tank"]
	melee_tank._attack_cooldown_remaining = 0.0
	_suite.assert_true(melee_tank._try_begin_primary_attack(), "melee enters the shared clock")
	melee_tank.set_overload_cooldown_for_test(0.0)
	_suite.assert_true(not melee_tank.force_overload_pulse_for_test(), "overload cannot replace an active melee")
	_suite.assert_equal(melee_tank.get_elite_action_snapshot_for_test()["action"], "MELEE", "blocked overload preserves melee")
	await _cleanup_subject(melee_subject)


func _assert_time_stop_freezes_the_current_phase() -> void:
	var subject: Dictionary = await _spawn_subject(true)
	var tank: Node = subject["tank"]
	tank.set_overload_cooldown_for_test(0.0)
	tank.force_overload_pulse_for_test()
	tank.advance_action_for_test(0.25)
	var before: Dictionary = tank.get_elite_action_snapshot_for_test()

	tank.apply_time_stop(1.0)
	tank._physics_process(0.45)
	var frozen: Dictionary = tank.get_elite_action_snapshot_for_test()
	_suite.assert_equal(frozen["phase"], "WINDUP", "time stop preserves the current overload phase")
	_suite.assert_close(float(frozen["phase_remaining"]), float(before["phase_remaining"]), "time stop freezes overload phase time")
	_suite.assert_close(float(frozen["telegraph"].get("remaining", 0.0)), float(before["telegraph"].get("remaining", 0.0)), "time stop freezes telegraph time")
	_suite.assert_equal(frozen["resolution_count"], 0, "time stop resolves no overload damage")
	await get_tree().create_timer(0.55).timeout
	await _cleanup_subject(subject)


func _assert_death_and_room_exit_clear_the_action() -> void:
	var death_subject: Dictionary = await _spawn_subject(true)
	var death_tank: Node = death_subject["tank"]
	death_tank.set_overload_cooldown_for_test(0.0)
	death_tank.force_overload_pulse_for_test()
	death_tank.health.lose_health(death_tank.health.current_hp, death_tank)
	var dead: Dictionary = death_tank.get_elite_action_snapshot_for_test()
	_suite.assert_equal(dead["action"], "NONE", "death cancels the elite active action")
	_suite.assert_equal(dead["phase"], "READY", "death clears the shared action phase")
	_suite.assert_true(not bool(dead["telegraph"].get("visible", true)), "death clears the overload telegraph")
	await get_tree().create_timer(0.25).timeout
	await _cleanup_subject(death_subject)

	var exit_subject: Dictionary = await _spawn_subject(true)
	var exit_tank: Node = exit_subject["tank"]
	exit_tank.set_overload_cooldown_for_test(0.0)
	exit_tank.force_overload_pulse_for_test()
	remove_child(exit_tank)
	var exited: Dictionary = exit_tank.get_elite_action_snapshot_for_test()
	_suite.assert_equal(exited["action"], "NONE", "room exit cancels the elite active action")
	_suite.assert_true(not bool(exited["telegraph"].get("visible", true)), "room exit clears the overload telegraph")
	exit_tank.free()
	var player: Node = exit_subject["player"]
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame


func _spawn_subject(make_elite: bool) -> Dictionary:
	var player := Node2D.new()
	player.name = "PlayerTarget"
	player.add_to_group("player")
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 500.0
	player.add_child(health)
	add_child(player)
	player.global_position = Vector2(48.0, 0.0)

	var tank := TankScene.instantiate()
	add_child(tank)
	tank.set_physics_process(false)
	tank.global_position = Vector2.ZERO
	tank.target = player
	if make_elite:
		tank.apply_elite_modifier()
	await get_tree().process_frame
	return {
		"player": player,
		"tank": tank,
		"health": health,
	}


func _cleanup_subject(subject: Dictionary) -> void:
	var tank: Variant = subject.get("tank")
	var player: Variant = subject.get("player")
	if is_instance_valid(tank):
		tank.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
