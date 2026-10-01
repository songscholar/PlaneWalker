extends Node

const HostileTelegraphFactScript := preload("res://scripts/combat/hostile_telegraph_fact.gd")
const HostileThreatRegistryScript := preload("res://scripts/combat/hostile_threat_registry.gd")
const CombatTelegraphScript := preload("res://scripts/fx/combat_telegraph_2d.gd")
const RunRuntimeHostScript := preload("res://scripts/application/run_runtime_host.gd")
const RoomControllerScript := preload("res://scripts/dungeon/room_controller.gd")
const ChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const ShooterScene := preload("res://scenes/enemies/enemy_shooter.tscn")
const TankScene := preload("res://scenes/enemies/enemy_tank.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _runtime_frame_for_test: int = 100


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_fact_is_strict_and_deep_isolated()
	_test_circle_uses_unscaled_geometry_and_inclusive_frames()
	_test_duplicate_identity_rejects_until_retired()
	_test_line_cone_and_rift_geometry()
	_test_summon_slots_and_nearest_distance_are_stable()
	_test_accessibility_scale_changes_only_projection()
	_test_host_and_room_share_one_registry_authority()
	await _test_enemy_attack_commit_registers_and_cancel_retires()
	await _test_boss_fact_shapes_and_time_crack_retirement()
	_suite.finish(get_tree())


func _test_fact_is_strict_and_deep_isolated() -> void:
	var source := _circle_fact(&"tank-a", 9, Vector2.ZERO, 96.0, 100, 154)
	source["summon_slots"] = [Vector2(-64.0, 0.0), Vector2(64.0, 0.0)]
	var fact: Dictionary = HostileTelegraphFactScript.create(source)
	_suite.assert_true(not fact.is_empty(), "strict hostile telegraph fact accepts valid geometry")
	(source["summon_slots"] as Array)[0] = Vector2(999.0, 999.0)
	_suite.assert_equal(
		(fact["summon_slots"] as Array)[0],
		Vector2(-64.0, 0.0),
		"fact isolates authored summon slots"
	)
	var extra := source.duplicate(true)
	extra["unknown"] = true
	_suite.assert_equal(HostileTelegraphFactScript.create(extra), {}, "unknown fact fields fail closed")
	var invalid_range := source.duplicate(true)
	invalid_range["active_through_frame"] = 99
	_suite.assert_equal(HostileTelegraphFactScript.create(invalid_range), {}, "reversed active range fails closed")


func _test_circle_uses_unscaled_geometry_and_inclusive_frames() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var fact := _circle_fact(&"tank-a", 9, Vector2.ZERO, 96.0, 100, 154)
	_suite.assert_true(registry.call("register_fact", fact), "circle threat publishes")
	for frame: int in [100, 120, 154]:
		_suite.assert_true(
			registry.call("contains_point", Vector2(95.0, 0.0), frame),
			"circle contains point inside unscaled radius at frame %d" % frame
		)
		_suite.assert_true(
			not registry.call("contains_point", Vector2(97.0, 0.0), frame),
			"circle excludes point beyond unscaled radius at frame %d" % frame
		)
	_suite.assert_true(not registry.call("contains_point", Vector2.ZERO, 99), "frame before active range excludes")
	_suite.assert_true(not registry.call("contains_point", Vector2.ZERO, 155), "frame after active range excludes")


func _test_duplicate_identity_rejects_until_retired() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var fact := _circle_fact(&"warden-a", 4, Vector2.ZERO, 64.0, 20, 40)
	_suite.assert_true(registry.call("register_fact", fact), "first source/generation publishes")
	_suite.assert_true(not registry.call("register_fact", fact), "duplicate source/generation rejects")
	_suite.assert_true(registry.call("retire", &"warden-a", 4), "matching fact retires")
	_suite.assert_true(not registry.call("retire", &"warden-a", 4), "retiring missing fact rejects")
	_suite.assert_true(registry.call("register_fact", fact), "retired identity can be reconstructed")


func _test_line_cone_and_rift_geometry() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var line := _circle_fact(&"line-a", 1, Vector2.ZERO, 6.0, 1, 30)
	line["shape"] = "line"
	line["length"] = 80.0
	_suite.assert_true(registry.call("register_fact", line), "line threat publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(40.0, 5.0), 10), "line includes authored half-width")
	_suite.assert_true(not registry.call("contains_point", Vector2(40.0, 7.0), 10), "line excludes outside authored half-width")

	var cone := _circle_fact(&"cone-a", 1, Vector2(100.0, 0.0), 30.0, 1, 30)
	cone["shape"] = "cone"
	cone["length"] = 90.0
	_suite.assert_true(registry.call("register_fact", cone), "cone threat publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(160.0, 10.0), 10), "cone includes point inside widening boundary")
	_suite.assert_true(not registry.call("contains_point", Vector2(160.0, 25.0), 10), "cone excludes point outside widening boundary")

	var rift := _circle_fact(&"rift-a", 3, Vector2(-100.0, 0.0), 24.0, 5, 50)
	rift["shape"] = "rift"
	rift["target_point"] = Vector2(-40.0, 0.0)
	rift["length"] = 60.0
	_suite.assert_true(registry.call("register_fact", rift), "authorized Rift geometry publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(-70.0, 20.0), 20), "Rift corridor uses unscaled width")
	_suite.assert_true(not registry.call("contains_point", Vector2(-70.0, 25.0), 20), "Rift corridor excludes outside width")


func _test_summon_slots_and_nearest_distance_are_stable() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var fact := _circle_fact(&"summon-a", 2, Vector2.ZERO, 12.0, 1, 60)
	fact["shape"] = "summon_slots"
	fact["summon_slots"] = [Vector2(-64.0, 0.0), Vector2(64.0, 0.0)]
	_suite.assert_true(registry.call("register_fact", fact), "summon-slot threat publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(60.0, 0.0), 20), "summon slot contains nearby point")
	_suite.assert_true(not registry.call("contains_point", Vector2.ZERO, 20), "summon slots do not inflate toward origin")
	_suite.assert_close(
		float(registry.call("nearest_threat_distance", Vector2.ZERO, 20)),
		52.0,
		"nearest distance measures unscaled boundary"
	)
	var snapshot: Dictionary = registry.call("fact_snapshot", &"summon-a", 2)
	(snapshot["summon_slots"] as Array)[0] = Vector2.ZERO
	_suite.assert_equal(
		(registry.call("fact_snapshot", &"summon-a", 2) as Dictionary)["summon_slots"][0],
		Vector2(-64.0, 0.0),
		"registry snapshot cannot mutate authoritative geometry"
	)


func _test_accessibility_scale_changes_only_projection() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var fact := _circle_fact(&"tank-visual", 12, Vector2.ZERO, 96.0, 100, 154)
	_suite.assert_true(registry.call("register_fact", fact), "visual-scale fixture publishes")
	var telegraph: Node2D = CombatTelegraphScript.new()
	_suite.assert_true(telegraph.call("project_fact", fact), "presentation projects immutable threat fact")
	for scale: float in [1.0, 1.25, 1.5]:
		telegraph.call("set_accessibility_visual_scale", scale)
		var snapshot: Dictionary = telegraph.call("get_snapshot")
		_suite.assert_close(
			float(snapshot.get("visual_radius", 0.0)),
			96.0 * scale,
			"presentation radius follows accessibility scale %.2f" % scale
		)
		_suite.assert_true(
			registry.call("contains_point", Vector2(95.0, 0.0), 120),
			"gameplay threat remains inside at visual scale %.2f" % scale
		)
		_suite.assert_true(
			not registry.call("contains_point", Vector2(97.0, 0.0), 120),
			"gameplay threat remains outside at visual scale %.2f" % scale
		)
	telegraph.free()


func _test_host_and_room_share_one_registry_authority() -> void:
	var host: Node = RunRuntimeHostScript.new()
	_suite.assert_true(
		host.has_method("hostile_threat_registry"),
		"RunRuntimeHost exposes its run-scoped hostile threat authority"
	)
	if not host.has_method("hostile_threat_registry"):
		host.free()
		return
	var registry_value: Variant = host.call("hostile_threat_registry")
	_suite.assert_true(registry_value is RefCounted, "RunRuntimeHost owns one registry instance")
	if not registry_value is RefCounted:
		host.free()
		return

	var controller: Node = RoomControllerScript.new()
	_suite.assert_true(
		controller.has_method("configure_hostile_threat_authority"),
		"RoomController accepts the host-owned threat authority"
	)
	if controller.has_method("configure_hostile_threat_authority"):
		_suite.assert_true(
			controller.call(
				"configure_hostile_threat_authority",
				RunRuntimeHostScript.hostile_identity_scope(&"run-threat-owner"),
				registry_value
			),
			"RoomController accepts one complete hostile authority configuration"
		)
		_suite.assert_true(
			controller.call("hostile_threat_registry") == registry_value,
			"RoomController injects the exact host-owned registry instead of copying it"
		)
		var teardown_fact := _circle_fact(&"room-teardown-source", 1, Vector2.ZERO, 24.0, 1, 10)
		_suite.assert_true(registry_value.call("register_fact", teardown_fact), "room teardown fixture registers")
		controller.call("retire_hostile_threats")
		_suite.assert_equal(
			(registry_value.call("snapshot") as Array).size(),
			0,
			"RoomController teardown clears every room-owned threat"
		)
	controller.free()
	host.free()


func _test_enemy_attack_commit_registers_and_cancel_retires() -> void:
	var target := Node2D.new()
	target.name = "ThreatTarget"
	add_child(target)
	target.global_position = Vector2(24.0, 0.0)

	var cases: Array[Dictionary] = [
		{"scene": ChaserScene, "source": &"threat-chaser", "shape": "cone", "distance": 24.0},
		{"scene": ShooterScene, "source": &"threat-shooter", "shape": "line", "distance": 220.0},
	]
	for case_value: Dictionary in cases:
		var registry: RefCounted = HostileThreatRegistryScript.new()
		var enemy: Node2D = (case_value["scene"] as PackedScene).instantiate()
		enemy.call("configure_hostile_identity", case_value["source"], 1)
		_suite.assert_true(
			enemy.has_method("configure_hostile_threat_authority"),
			"%s accepts the room threat authority" % str(case_value["shape"])
		)
		if not enemy.has_method("configure_hostile_threat_authority"):
			enemy.free()
			continue
		_suite.assert_true(
			enemy.call(
				"configure_hostile_threat_authority",
				registry,
				Callable(self, "_runtime_frame_for_threat_test")
			),
			"%s installs its threat authority before ready" % str(case_value["shape"])
		)
		add_child(enemy)
		enemy.set_physics_process(false)
		enemy.target = target
		target.global_position = Vector2(float(case_value["distance"]), 0.0)
		enemy.call("_physics_process", 0.01)
		var facts: Array = registry.call("snapshot")
		_suite.assert_equal(facts.size(), 1, "%s attack commit registers exactly one fact" % str(case_value["shape"]))
		if facts.size() == 1:
			var fact := facts[0] as Dictionary
			_suite.assert_equal(fact.get("shape"), case_value["shape"], "%s keeps authored risk geometry" % str(case_value["shape"]))
			_suite.assert_equal(fact.get("active_from_frame"), _runtime_frame_for_test, "%s uses the authoritative runtime frame" % str(case_value["shape"]))
		if str(case_value["shape"]) == "cone":
			enemy.call("_tick_attack_phase", float(enemy.get("attack_windup")) + 0.01)
			enemy.call("_tick_attack_phase", float(enemy.get("attack_recovery")) + 0.01)
			_suite.assert_equal((registry.call("snapshot") as Array).size(), 0, "completed cone attack retires its committed fact")
			enemy.set("_attack_cooldown_remaining", 0.0)
			enemy.call("_physics_process", 0.01)
			_suite.assert_equal((registry.call("snapshot") as Array).size(), 1, "next cone attack registers a fresh generation")
			enemy.call("retire_hostile_identity", &"death")
			_suite.assert_equal((registry.call("snapshot") as Array).size(), 0, "death retires every fact owned by the hostile source")
		else:
			enemy.call("cancel_active_attack")
			_suite.assert_equal((registry.call("snapshot") as Array).size(), 0, "%s cancellation retires the committed fact" % str(case_value["shape"]))
		enemy.queue_free()
		await get_tree().process_frame

	var tank_registry: RefCounted = HostileThreatRegistryScript.new()
	var tank: Node2D = TankScene.instantiate()
	tank.call("configure_hostile_identity", &"threat-tank", 1)
	if tank.has_method("configure_hostile_threat_authority"):
		tank.call("configure_hostile_threat_authority", tank_registry, Callable(self, "_runtime_frame_for_threat_test"))
	add_child(tank)
	tank.set_physics_process(false)
	tank.target = target
	target.global_position = tank.global_position + Vector2(20.0, 0.0)
	tank.call("apply_elite_modifier")
	_suite.assert_true(tank.call("force_overload_pulse_for_test"), "Tank commits its elite pulse")
	var tank_facts: Array = tank_registry.call("snapshot")
	_suite.assert_equal(tank_facts.size(), 1, "Tank pulse registers one circle fact")
	if tank_facts.size() == 1:
		_suite.assert_equal((tank_facts[0] as Dictionary).get("shape"), "circle", "Tank pulse owns circle risk geometry")
		var visual: Dictionary = tank.call("get_elite_action_snapshot_for_test").get("telegraph", {})
		_suite.assert_equal(visual.get("attack_generation"), (tank_facts[0] as Dictionary).get("attack_generation"), "Tank presentation projects the registered fact identity")
	tank.call("cancel_active_attack")
	_suite.assert_equal((tank_registry.call("snapshot") as Array).size(), 0, "Tank cancellation retires its circle fact")
	tank.queue_free()
	target.queue_free()
	await get_tree().process_frame


func _test_boss_fact_shapes_and_time_crack_retirement() -> void:
	var expected_shapes := {
		"MELEE": "cone",
		"SLAM": "circle",
		"AIMED": "line",
		"SUMMON": "summon_slots",
	}
	for action_name: String in expected_shapes:
		var subject: Dictionary = await _spawn_boss_subject(action_name)
		var boss: Node = subject["boss"]
		var registry: RefCounted = subject["registry"]
		_suite.assert_true(boss.call("force_action_for_test", action_name), "%s commits for threat coverage" % action_name)
		var facts: Array = registry.call("snapshot")
		_suite.assert_equal(facts.size(), 1, "%s registers one immutable threat fact" % action_name)
		if facts.size() == 1:
			_suite.assert_equal((facts[0] as Dictionary).get("shape"), expected_shapes[action_name], "%s registers its authored shape" % action_name)
			var telegraph: Dictionary = boss.call("get_active_telegraph_snapshot_for_test")
			_suite.assert_equal(telegraph.get("attack_generation"), (facts[0] as Dictionary).get("attack_generation"), "%s presentation projects the domain fact" % action_name)
		boss.call("cancel_active_attack")
		_suite.assert_equal((registry.call("snapshot") as Array).size(), 0, "%s cancellation retires its fact" % action_name)
		await _cleanup_boss_subject(subject)

	var crack_subject: Dictionary = await _spawn_boss_subject("TIME_CRACK")
	var crack_boss: Node = crack_subject["boss"]
	var crack_registry: RefCounted = crack_subject["registry"]
	_suite.assert_true(crack_boss.call("force_action_for_test", "TIME_CRACK"), "Time Crack action commits")
	var committed: Dictionary = crack_boss.call("get_committed_action_snapshot_for_test")
	var before_spawn: Dictionary = crack_registry.call(
		"fact_snapshot",
		committed.get("hostile_source_id", &""),
		int(committed.get("attack_generation", 0))
	)
	_suite.assert_equal(before_spawn.get("shape"), "target_circle", "Warden publishes the committed Time Crack target")
	var definition: Dictionary = crack_boss.call("get_action_definitions_for_test").get("TIME_CRACK", {})
	crack_boss.call("advance_action_for_test", float(definition.get("windup", 0.0)) + 0.001)
	var cracks := get_tree().get_nodes_in_group("boss_hazards")
	_suite.assert_true(not cracks.is_empty(), "Time Crack runtime materializes after the committed windup")
	if not cracks.is_empty():
		var crack: Node = cracks.back()
		var during_arm: Dictionary = crack_registry.call(
			"fact_snapshot",
			committed.get("hostile_source_id", &""),
			int(committed.get("attack_generation", 0))
		)
		_suite.assert_equal(during_arm.get("shape"), "target_circle", "Time Crack owns the same unscaled target geometry while arming")
		crack.call("_explode")
		_suite.assert_equal((crack_registry.call("snapshot") as Array).size(), 0, "Time Crack completion retires its fact")
		await get_tree().create_timer(0.20).timeout
	await _cleanup_boss_subject(crack_subject)


func _spawn_boss_subject(action_name: String) -> Dictionary:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var target := Node2D.new()
	target.name = "BossThreatTarget%s" % action_name
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	target.add_child(health)
	add_child(target)
	target.global_position = Vector2(30.0, 0.0)
	var boss: Node2D = BossScene.instantiate()
	boss.call("configure_hostile_identity", StringName("threat-boss-%s" % action_name.to_lower()), 1)
	if boss.has_method("configure_hostile_threat_authority"):
		boss.call("configure_hostile_threat_authority", registry, Callable(self, "_runtime_frame_for_threat_test"))
	add_child(boss)
	boss.set_physics_process(false)
	boss.target = target
	return {"boss": boss, "target": target, "registry": registry}


func _cleanup_boss_subject(subject: Dictionary) -> void:
	(subject["boss"] as Node).queue_free()
	(subject["target"] as Node).queue_free()
	await get_tree().process_frame


func _runtime_frame_for_threat_test() -> int:
	return _runtime_frame_for_test


func _circle_fact(
	source_id: StringName,
	generation: int,
	origin: Vector2,
	radius: float,
	from_frame: int,
	through_frame: int
) -> Dictionary:
	return {
		"hostile_source_id": source_id,
		"attack_generation": generation,
		"shape": "circle",
		"origin": origin,
		"aim_direction": Vector2.RIGHT,
		"target_point": origin,
		"summon_slots": [],
		"radius": radius,
		"length": 0.0,
		"active_from_frame": from_frame,
		"active_through_frame": through_frame,
	}
