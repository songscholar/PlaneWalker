extends Node

const HostileTelegraphFactScript := preload("res://scripts/combat/hostile_telegraph_fact.gd")
const HostileThreatRegistryScript := preload("res://scripts/combat/hostile_threat_registry.gd")
const CombatTelegraphScript := preload("res://scripts/fx/combat_telegraph_2d.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


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
	_suite.assert_true(registry.call("publish", fact), "circle threat publishes")
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
	_suite.assert_true(registry.call("publish", fact), "first source/generation publishes")
	_suite.assert_true(not registry.call("publish", fact), "duplicate source/generation rejects")
	_suite.assert_true(registry.call("retire", &"warden-a", 4), "matching fact retires")
	_suite.assert_true(not registry.call("retire", &"warden-a", 4), "retiring missing fact rejects")
	_suite.assert_true(registry.call("publish", fact), "retired identity can be reconstructed")


func _test_line_cone_and_rift_geometry() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var line := _circle_fact(&"line-a", 1, Vector2.ZERO, 6.0, 1, 30)
	line["shape"] = "line"
	line["length"] = 80.0
	_suite.assert_true(registry.call("publish", line), "line threat publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(40.0, 5.0), 10), "line includes authored half-width")
	_suite.assert_true(not registry.call("contains_point", Vector2(40.0, 7.0), 10), "line excludes outside authored half-width")

	var cone := _circle_fact(&"cone-a", 1, Vector2(100.0, 0.0), 30.0, 1, 30)
	cone["shape"] = "cone"
	cone["length"] = 90.0
	_suite.assert_true(registry.call("publish", cone), "cone threat publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(160.0, 10.0), 10), "cone includes point inside widening boundary")
	_suite.assert_true(not registry.call("contains_point", Vector2(160.0, 25.0), 10), "cone excludes point outside widening boundary")

	var rift := _circle_fact(&"rift-a", 3, Vector2(-100.0, 0.0), 24.0, 5, 50)
	rift["shape"] = "rift"
	rift["target_point"] = Vector2(-40.0, 0.0)
	rift["length"] = 60.0
	_suite.assert_true(registry.call("publish", rift), "authorized Rift geometry publishes")
	_suite.assert_true(registry.call("contains_point", Vector2(-70.0, 20.0), 20), "Rift corridor uses unscaled width")
	_suite.assert_true(not registry.call("contains_point", Vector2(-70.0, 25.0), 20), "Rift corridor excludes outside width")


func _test_summon_slots_and_nearest_distance_are_stable() -> void:
	var registry: RefCounted = HostileThreatRegistryScript.new()
	var fact := _circle_fact(&"summon-a", 2, Vector2.ZERO, 12.0, 1, 60)
	fact["shape"] = "summon_slots"
	fact["summon_slots"] = [Vector2(-64.0, 0.0), Vector2(64.0, 0.0)]
	_suite.assert_true(registry.call("publish", fact), "summon-slot threat publishes")
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
	_suite.assert_true(registry.call("publish", fact), "visual-scale fixture publishes")
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
