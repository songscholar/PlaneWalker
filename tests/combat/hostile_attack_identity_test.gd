extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const EnemyChaserScript := preload("res://scripts/enemies/enemy_chaser.gd")
const EnemyShooterScript := preload("res://scripts/enemies/enemy_shooter.gd")
const EnemyProjectileScript := preload("res://scripts/enemies/enemy_projectile.gd")
const EnemyTankScript := preload("res://scripts/enemies/enemy_tank.gd")
const ChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const BossTimeCrackScript := preload("res://scripts/enemies/boss_time_crack.gd")
const BossChronoWardenScript := preload("res://scripts/enemies/boss_chrono_warden.gd")
const RoomControllerScript := preload("res://scripts/dungeon/room_controller.gd")
const RunRuntimeHostScript := preload("res://scripts/application/run_runtime_host.gd")

var _suite


class FakeRoomRuntime:
	extends Node

	func snapshot() -> Dictionary:
		return {
			"room_id": "floor1_room2",
			"run_seed": 4242,
		}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_base_and_chaser_generations_are_monotonic()
	_test_shooter_burst_shares_generation_and_authors_hit_indexes()
	_test_projectile_freezes_launch_identity_across_collisions()
	_test_tank_pulse_and_time_crack_tick_share_one_generation()
	_test_warden_outputs_share_committed_action_identity()
	_test_reset_death_room_transition_and_replay_boundaries()
	_test_runtime_room_source_is_deterministic_and_instance_free()
	_test_room_controller_injects_identity_before_ready()
	await _test_burn_tick_uses_status_identity_without_consuming_attack_generation()
	_suite.finish(get_tree())


func _test_base_and_chaser_generations_are_monotonic() -> void:
	for enemy_script: Script in [EnemyBaseScript, EnemyChaserScript]:
		var enemy: Node = enemy_script.new()
		_suite.assert_true(
			enemy.call("configure_hostile_identity", &"run7:room2:spawn4", 1),
			"enemy accepts an authoritative hostile source"
		)
		var first: Dictionary = enemy.call("begin_attack_for_test")
		var second: Dictionary = enemy.call("begin_attack_for_test")
		_suite.assert_equal(first.get("hostile_source_id"), &"run7:room2:spawn4", "attack keeps the configured source")
		_suite.assert_equal(first.get("attack_generation"), 1, "first committed attack uses generation one")
		_suite.assert_equal(second.get("attack_generation"), 2, "next committed attack increments once")
		_suite.assert_true(
			not str(first.get("hostile_source_id", "")).contains(str(enemy.get_instance_id())),
			"hostile source never contains runtime instance identity"
		)
		enemy.free()


func _test_shooter_burst_shares_generation_and_authors_hit_indexes() -> void:
	var shooter: Node = EnemyShooterScript.new()
	shooter.call("configure_hostile_identity", &"run7:room2:spawn4", 1)
	var first_burst: Array = shooter.call("projectile_identities_for_test", 3)
	_suite.assert_equal(first_burst.size(), 3, "shooter authors every requested pellet")
	for index: int in range(first_burst.size()):
		var identity: Dictionary = first_burst[index]
		_suite.assert_equal(identity.get("hostile_source_id"), &"run7:room2:spawn4", "pellet shares shooter source")
		_suite.assert_equal(identity.get("attack_generation"), 1, "pellet shares one burst generation")
		_suite.assert_equal(identity.get("hit_index"), index, "pellet has its authored burst index")
	var second_burst: Array = shooter.call("projectile_identities_for_test", 2)
	_suite.assert_equal(second_burst[0].get("attack_generation"), 2, "next burst advances exactly one generation")
	_suite.assert_equal(second_burst[1].get("attack_generation"), 2, "second burst pellets remain grouped")
	shooter.free()


func _test_projectile_freezes_launch_identity_across_collisions() -> void:
	var projectile: Node = EnemyProjectileScript.new()
	_suite.assert_true(
		projectile.call("configure_attack_identity", &"run7", &"shooter-a", 8, 2, null),
		"projectile accepts one complete launch identity"
	)
	var first: Dictionary = projectile.call("attack_identity_snapshot")
	var repeated: Dictionary = projectile.call("attack_identity_snapshot")
	_suite.assert_equal(first, repeated, "repeated collision reads cannot mutate projectile identity")
	_suite.assert_equal(first.get("attack_generation"), 8, "projectile freezes launch generation")
	_suite.assert_equal(first.get("hit_index"), 2, "projectile freezes authored pellet index")
	_suite.assert_true(
		not projectile.call("configure_attack_identity", &"run7", &"shooter-a", 9, 0, null),
		"armed launch identity cannot be overwritten"
	)
	projectile.free()


func _test_tank_pulse_and_time_crack_tick_share_one_generation() -> void:
	var tank: Node = EnemyTankScript.new()
	tank.call("configure_hostile_identity", &"tank-a", 4)
	var pulse: Array = tank.call("pulse_identities_for_test", 3)
	_assert_grouped_identities(pulse, &"tank-a", 4, "Tank pulse")
	var next_pulse: Array = tank.call("pulse_identities_for_test", 1)
	_suite.assert_equal(next_pulse[0].get("attack_generation"), 5, "next Tank pulse advances generation")
	tank.free()

	var crack: Node = BossTimeCrackScript.new()
	_suite.assert_true(
		crack.call("configure_attack_identity", &"run7", &"warden-a", 11, null),
		"Time Crack accepts its committed Warden identity"
	)
	var tick: Array = crack.call("tick_identities_for_test", 3)
	_assert_grouped_identities(tick, &"warden-a", 11, "Time Crack tick")
	crack.free()


func _test_warden_outputs_share_committed_action_identity() -> void:
	var boss: Node = BossChronoWardenScript.new()
	boss.call("configure_hostile_identity", &"warden-a", 20)
	var radial: Array = boss.call("action_identities_for_test", "RADIAL", 4)
	_assert_grouped_identities(radial, &"warden-a", 20, "Warden radial burst")
	var summon: Array = boss.call("action_identities_for_test", "SUMMON", 2)
	_assert_grouped_identities(summon, &"warden-a", 21, "Warden summon slots")
	var crack: Array = boss.call("action_identities_for_test", "TIME_CRACK", 1)
	_assert_grouped_identities(crack, &"warden-a", 22, "Warden Time Crack")
	var melee: Array = boss.call("action_identities_for_test", "MELEE", 1)
	_assert_grouped_identities(melee, &"warden-a", 23, "Warden melee")
	boss.free()


func _test_reset_death_room_transition_and_replay_boundaries() -> void:
	var enemy: Node = EnemyBaseScript.new()
	enemy.call("configure_hostile_identity", &"run7:room2:spawn4", 1)
	enemy.call("begin_attack_for_test")
	enemy.call("begin_attack_for_test")
	var replay_snapshot: Dictionary = enemy.call("hostile_identity_snapshot")
	_suite.assert_equal(replay_snapshot.get("next_generation_floor"), 3, "snapshot records the next replay-safe floor")

	_suite.assert_true(
		enemy.call("configure_hostile_identity", &"run7:room2:spawn4", 1),
		"same-source reset is accepted"
	)
	var after_reset: Dictionary = enemy.call("begin_attack_for_test")
	_suite.assert_equal(after_reset.get("attack_generation"), 3, "same-source reset cannot regress generation")

	_suite.assert_true(
		enemy.call("configure_hostile_identity", &"run7:room3:spawn4", 1),
		"room transition installs a new deterministic source"
	)
	var transitioned: Dictionary = enemy.call("begin_attack_for_test")
	_suite.assert_equal(transitioned.get("attack_generation"), 1, "new room source starts at its authored floor")
	_suite.assert_equal(transitioned.get("hostile_source_id"), &"run7:room3:spawn4", "room transition retires the prior source")

	enemy.call("retire_hostile_identity", &"death")
	_suite.assert_true((enemy.call("begin_attack_for_test") as Dictionary).is_empty(), "death retires attack allocation")
	enemy.free()

	var reconstructed: Node = EnemyBaseScript.new()
	_suite.assert_true(
		reconstructed.call("restore_hostile_identity_snapshot", replay_snapshot),
		"Replay reconstruction accepts an authoritative identity snapshot"
	)
	var replayed: Dictionary = reconstructed.call("begin_attack_for_test")
	_suite.assert_equal(replayed.get("hostile_source_id"), &"run7:room2:spawn4", "Replay restores source identity")
	_suite.assert_equal(replayed.get("attack_generation"), 3, "Replay resumes at the snapshotted generation floor")
	reconstructed.free()


func _test_runtime_room_source_is_deterministic_and_instance_free() -> void:
	var scope: Dictionary = RunRuntimeHostScript.hostile_identity_scope(&"run-4242-1")
	var first := RoomControllerScript.hostile_source_id_for_spawn(
		scope,
		&"floor1_room2",
		&"encounter_alpha",
		{"id": "spawn_04", "spawn_slot_id": "slot_east"},
		0
	)
	var repeated := RoomControllerScript.hostile_source_id_for_spawn(
		scope,
		&"floor1_room2",
		&"encounter_alpha",
		{"id": "spawn_04", "spawn_slot_id": "slot_east"},
		0
	)
	var next_ordinal := RoomControllerScript.hostile_source_id_for_spawn(
		scope,
		&"floor1_room2",
		&"encounter_alpha",
		{"id": "spawn_04", "spawn_slot_id": "slot_east"},
		1
	)
	_suite.assert_equal(first, repeated, "runtime source derivation is deterministic")
	_suite.assert_true(first != &"", "runtime source derivation produces a non-empty ID")
	_suite.assert_true(str(first).length() <= 64, "runtime source fits DamageInfo identity bounds")
	_suite.assert_true(first != next_ordinal, "spawn ordinal participates in source identity")
	_suite.assert_true(not str(first).contains(str(get_instance_id())), "runtime source excludes node instance identity")
	var first_chaser: Node = EnemyChaserScript.new()
	var second_chaser: Node = EnemyChaserScript.new()
	first_chaser.call("configure_hostile_identity", first, 1)
	second_chaser.call("configure_hostile_identity", next_ordinal, 1)
	var first_attack: Dictionary = first_chaser.call("begin_attack_for_test")
	var second_attack: Dictionary = second_chaser.call("begin_attack_for_test")
	_suite.assert_true(
		first_attack.get("hostile_source_id") != second_attack.get("hostile_source_id"),
		"two same-type enemies receive distinct deterministic sources"
	)
	_suite.assert_equal(first_attack.get("attack_generation"), 1, "first same-type enemy owns its generation stream")
	_suite.assert_equal(second_attack.get("attack_generation"), 1, "second same-type enemy owns an independent generation stream")
	first_chaser.free()
	second_chaser.free()


func _test_room_controller_injects_identity_before_ready() -> void:
	var controller: Node = RoomControllerScript.new()
	var runtime := FakeRoomRuntime.new()
	controller.set("_room_runtime", runtime)
	controller.set("_hostile_identity_scope", RunRuntimeHostScript.hostile_identity_scope(&"run-4242-1"))
	controller.set("_current_room_definition", {"encounter_id": "encounter_alpha"})
	var first: Node = EnemyChaserScript.new()
	var second: Node = EnemyChaserScript.new()
	_suite.assert_true(
		controller.call("_configure_spawned_hostile_identity", first, {"id": "chaser", "spawn_slot_id": "slot_a"}),
		"RoomController configures first enemy before ready"
	)
	_suite.assert_true(
		controller.call("_configure_spawned_hostile_identity", second, {"id": "chaser", "spawn_slot_id": "slot_a"}),
		"RoomController configures repeated enemy before ready"
	)
	var first_identity: Dictionary = first.call("hostile_identity_snapshot")
	var second_identity: Dictionary = second.call("hostile_identity_snapshot")
	_suite.assert_true(first_identity.get("hostile_source_id") != second_identity.get("hostile_source_id"), "RoomController allocates distinct same-type spawn ordinals")
	_suite.assert_equal(str(first.get_meta("run_id", "")), "run-4242-1", "RoomController installs run identity before ready")
	_suite.assert_equal(str(second.get_meta("run_id", "")), "run-4242-1", "repeated spawn receives the same authoritative run scope")
	first.free()
	second.free()
	runtime.free()
	controller.free()


func _test_burn_tick_uses_status_identity_without_consuming_attack_generation() -> void:
	var enemy: Node = ChaserScene.instantiate()
	_suite.assert_true(
		enemy.call("configure_hostile_identity", &"burn-target-hostile", 7),
		"burn allocator fixture starts at the authored hostile generation floor"
	)
	add_child(enemy)
	enemy.set_physics_process(false)
	var observed: Array[RefCounted] = []
	var callback := func(damage_info: RefCounted, target: Node, _amount: float) -> void:
		if target == enemy:
			observed.append(damage_info)
	EventBus.damage_applied.connect(callback)
	_suite.assert_true(
		enemy.call(
			"apply_elemental_status",
			&"burn",
			&"staff-status-source",
			3,
			1,
			2.0,
			1
		),
		"burn fixture accepts an explicit status source identity"
	)
	enemy.call("_tick_elemental_status_runtime")
	if EventBus.damage_applied.is_connected(callback):
		EventBus.damage_applied.disconnect(callback)
	_suite.assert_equal(observed.size(), 1, "burn emits one authored status tick")
	if observed.size() == 1:
		var info := observed[0]
		_suite.assert_true(
			str(info.hostile_source_id).begins_with("status:"),
			"burn damage uses a status-source namespace instead of the target hostile source"
		)
		_suite.assert_true(info.hostile_source_id != &"burn-target-hostile", "burn identity cannot impersonate the target attack allocator")
		_suite.assert_equal(int(info.source_generation), 3, "burn preserves its authored status generation")
	var first_attack: Dictionary = enemy.call("begin_attack_for_test")
	_suite.assert_equal(first_attack.get("attack_generation"), 7, "burn tick does not consume hostile attack generation seven")
	await get_tree().create_timer(0.10).timeout
	enemy.queue_free()
	await get_tree().process_frame


func _assert_grouped_identities(
	identities: Array,
	expected_source: StringName,
	expected_generation: int,
	label: String
) -> void:
	_suite.assert_true(not identities.is_empty(), "%s authors at least one hit" % label)
	for index: int in range(identities.size()):
		var identity: Dictionary = identities[index]
		_suite.assert_equal(identity.get("hostile_source_id"), expected_source, "%s shares hostile source" % label)
		_suite.assert_equal(identity.get("attack_generation"), expected_generation, "%s shares attack generation" % label)
		_suite.assert_equal(identity.get("hit_index"), index, "%s authors deterministic hit index" % label)
