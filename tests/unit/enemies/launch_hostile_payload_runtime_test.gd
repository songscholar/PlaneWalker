extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const BOUNDS := {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var path := "res://scripts/enemies/launch/launch_hostile_payload_runtime.gd"
	var implementation: Script = load(path) if FileAccess.file_exists(path) else null
	suite.assert_true(implementation != null, "hostile projectile and acid-pool lifecycles require a fixed-frame domain")
	if implementation != null:
		_test_projectile_and_controls(implementation)
		_test_impact_and_death_zones(implementation)
		_test_capacity_and_restore(implementation)
		_test_adversarial_contracts(implementation)
		_test_authored_boss_ranges_and_piercing(implementation)
	suite.finish(get_tree())


func _hit(source: String = "hostile-moth-one") -> Dictionary:
	var parser := Enemy.new()
	parser.configure(Content.enemy("corrosive_moth"))
	var projection := parser.runtime_projection()
	var coordinator := Coordinator.new()
	coordinator.configure({"id": projection.id, "actor_kind": projection.actor_kind, "actions": projection.actions}, {"run_id": "run-p15", "hostile_source_id": source, "next_generation_floor": 7, "runtime_frame": 0})
	coordinator.request_action("corrosive_moth.corrosive_spit", Actions.context())
	var result: Dictionary
	for frame: int in range(1, 31):
		result = coordinator.advance_frame(frame, Actions.context(frame))
	suite.assert_equal(result.hit_facts[0].geometry[0].length, 240.0, "moving projectile has its complete finite swept envelope fixed at warning commitment")
	return result.hit_facts[0]


func _mechanisms() -> Dictionary:
	return Content.enemy("corrosive_moth").mechanisms.duplicate(true)


func _boss_hit(boss_id: String, action_id: String, index: int = 0) -> Dictionary:
	var parser := Boss.new()
	parser.configure(Content.boss(boss_id))
	var projection := parser.runtime_projection()
	var coordinator := Coordinator.new()
	coordinator.configure({"id": projection.id, "actor_kind": projection.actor_kind, "actions": projection.actions}, {"run_id": "run-p15", "hostile_source_id": "hostile-boss-range", "next_generation_floor": 7, "runtime_frame": 0})
	coordinator.request_action(action_id, Actions.context())
	for frame: int in range(1, 601):
		var result := coordinator.advance_frame(frame, Actions.context(frame))
		if not result.hit_facts.is_empty():
			return result.hit_facts[index]
	return {}


func _test_authored_boss_ranges_and_piercing(implementation: Script) -> void:
	for row: Array in [["forge_colossus", "forge_lava_toss", 192.0], ["void_throne", "voidking_shard_projection", 256.0]]:
		var hit := _boss_hit(row[0], row[1])
		var runtime: RefCounted = implementation.new()
		runtime.configure("run-p15", hit.runtime_frame)
		var reserved: Dictionary = runtime.reserve_projectile(hit, BOUNDS, {})
		suite.assert_true(reserved.ok, "native payload preserves authored %s finite range" % row[1])
		if reserved.ok:
			suite.assert_equal(runtime.snapshot().projectiles[0].definition.range_px, row[2], "payload range equals the sealed authored warning envelope")
			suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "authored Boss projectile round-trips its exact trajectory")
	var hit := _boss_hit("forge_colossus", "forge_sword_wave")
	var runtime: RefCounted = implementation.new()
	runtime.configure("run-p15", hit.runtime_frame)
	var reserved: Dictionary = runtime.reserve_projectile(hit, BOUNDS, {})
	suite.assert_true(reserved.ok, "authored sword wave reserves one bounded penetration")
	if not reserved.ok:
		return
	var frame := int(hit.runtime_frame) + 1
	var first := {reserved.id: {"kind": "target", "target_id": "first", "position": {"x": 101.0, "y": 100.0}}}
	var first_result: Dictionary = runtime.advance_frame(frame, _observations(first, {"first": {"x": 101.0, "y": 100.0}}))
	suite.assert_true(first_result.ok and first_result.damage_requests.size() == 1, "piercing projectile damages its first sealed body exactly once")
	suite.assert_equal(runtime.snapshot().projectiles.size(), 1, "one-pierce wave remains live after the first body")
	var checkpoint: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.can_restore_snapshot(checkpoint), "pierced target claims are strict deterministic state")
	var duplicate := {reserved.id: {"kind": "target", "target_id": "first", "position": {"x": 103.0, "y": 100.0}}}
	suite.assert_true(not runtime.advance_frame(frame + 1, _observations(duplicate, {"first": {"x": 103.0, "y": 100.0}})).ok, "native observation cannot damage the same pierced target again")
	suite.assert_equal(runtime.snapshot(), checkpoint, "rejected repeat contact consumes no age, travel or pierce budget")
	var second := {reserved.id: {"kind": "target", "target_id": "second", "position": {"x": 103.0, "y": 100.0}}}
	var second_result: Dictionary = runtime.advance_frame(frame + 1, _observations(second, {"second": {"x": 103.0, "y": 100.0}}))
	suite.assert_true(second_result.ok and second_result.damage_requests.size() == 1, "one-pierce wave settles its second distinct body")
	suite.assert_true(runtime.snapshot().projectiles.is_empty(), "finite pierce budget retires after two target contacts")
	var forged := checkpoint.duplicate(true)
	forged.projectiles[0].hit_targets.append("second")
	suite.assert_true(not runtime.restore_snapshot(forged), "live projectile cannot restore already-exhausted pierce budget")


func _observations(contacts: Dictionary = {}, targets: Dictionary = {}) -> Dictionary:
	var descriptors: Dictionary = {}
	for id: String in targets:
		descriptors[id] = {"position": targets[id].duplicate(), "collision_radius_px": 0.0}
	return {"projectile_contacts": contacts, "targets": descriptors}


func _test_projectile_and_controls(implementation: Script) -> void:
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure("run-p15", 30), "payload clock binds a real accepted action frame")
	var reserved: Dictionary = runtime.reserve_projectile(_hit(), BOUNDS, _mechanisms())
	suite.assert_true(reserved.ok, "actual Moth scheduled hit reserves an authored projectile")
	if not reserved.ok:
		return
	var initial: Dictionary = runtime.snapshot()
	var id: String = reserved.id
	var motion: Dictionary = runtime.motion_for_frame(31)
	suite.assert_equal(motion[id].displacement, {"x": 3.2, "y": 0.0}, "authored 192px/sec projectile advances at sixty fixed frames")
	suite.assert_equal(runtime.snapshot(), initial, "motion preflight is read-only")
	suite.assert_true(runtime.add_control_source(id, "stop-projectile", "stop", 2, 1.0), "real payload owns a bounded Stop source")
	for frame: int in range(31, 33):
		suite.assert_equal(runtime.motion_for_frame(frame)[id].displacement, {"x": 0.0, "y": 0.0}, "Stop postpones projectile motion")
		suite.assert_true(runtime.advance_frame(frame, _observations()).ok, "Stop sources expire on sequential unscaled frames")
	suite.assert_true(runtime.add_control_source(id, "rift-projectile", "rift", 4, 0.5), "Rift installs a positive payload slow")
	suite.assert_equal(runtime.motion_for_frame(33)[id].displacement, {"x": 1.6, "y": 0.0}, "Rift changes travel while preserving frozen aim")
	runtime.advance_frame(33, _observations())
	var checkpoint: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.can_restore_snapshot(checkpoint), "live projectile and time sources form a strict checkpoint")
	var malformed := checkpoint.duplicate(true)
	malformed.projectiles[0].position.x += 16.0
	suite.assert_true(not runtime.can_restore_snapshot(malformed), "projectile checkpoint cannot leave its frozen swept trajectory")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.advance_frame(35, _observations()).ok, "payload clocks refuse skipped frames")
	suite.assert_equal(runtime.snapshot(), before, "bad frame cannot consume travel or controls")
	for frame: int in range(34, 115):
		runtime.advance_frame(frame, _observations())
	suite.assert_true(runtime.snapshot().projectiles.is_empty(), "projectile expires at its finite 240px range")
	suite.assert_true(runtime.snapshot().zones.is_empty(), "harmless range expiry does not invent an impact pool")


func _test_impact_and_death_zones(implementation: Script) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure("run-p15", 30)
	var reserved: Dictionary = runtime.reserve_projectile(_hit(), BOUNDS, _mechanisms())
	if not reserved.ok:
		return
	var impact := {reserved.id: {"kind": "target", "target_id": "player", "position": {"x": 101.6, "y": 100.0}}}
	var result: Dictionary = runtime.advance_frame(31, _observations(impact, {"player": {"x": 101.6, "y": 100.0}}))
	suite.assert_true(result.ok and result.damage_requests.size() == 1, "sealed native contact produces one projectile damage request")
	suite.assert_equal(result.damage_requests[0].damage, 8.0, "projectile preserves actual authored damage")
	suite.assert_true(runtime.snapshot().projectiles.is_empty() and runtime.snapshot().zones.size() == 1, "impact consumes the projectile and reserves its bounded acid pool")
	var ticks: Array = []
	for frame: int in range(32, 152):
		result = runtime.advance_frame(frame, _observations({}, {"player": {"x": 101.6, "y": 100.0}}))
		for request: Dictionary in result.damage_requests:
			ticks.append([frame, request.damage])
	suite.assert_equal(ticks, [[91, 3.0], [151, 3.0]], "acid pool ticks every sixty frames and expires after two finite ticks")
	suite.assert_true(runtime.snapshot().zones.is_empty(), "acid pool releases pending work at lifetime end")
	var death: RefCounted = implementation.new()
	death.configure("run-p15", 30)
	var request := {"kind": "death_pool", "run_id": "run-p15", "hostile_source_id": "hostile-moth-death", "runtime_frame": 30, "attack_generation": 8, "position": {"x": 100.0, "y": 100.0}, "bounds": BOUNDS.duplicate(), "parameters": {"warning_frames": 30, "radius": 16.0, "damage": 5.0}}
	suite.assert_true(death.reserve_death_pool(request).ok, "final native death reserves an independently owned warning pool")
	for frame: int in range(31, 60):
		suite.assert_true(death.advance_frame(frame, _observations({}, {"player": {"x": 100.0, "y": 100.0}})).damage_requests.is_empty(), "death pool deals zero damage before its full thirty-frame warning")
	result = death.advance_frame(60, _observations({}, {"player": {"x": 100.0, "y": 100.0}}))
	suite.assert_equal(result.damage_requests[0].damage, 5.0, "death pool settles exactly one warned authored pulse")
	suite.assert_true(death.snapshot().zones.is_empty(), "warned death pulse retires without persistent damage")


func _test_capacity_and_restore(implementation: Script) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure("run-p15", 30)
	for index: int in range(33):
		var reserved: Dictionary = runtime.reserve_projectile(_hit("hostile-moth-%d" % index), BOUNDS, _mechanisms())
		suite.assert_true(reserved.ok, "full room projectile budget delays a valid reservation instead of blocking the accepted frame")
	var snapshot: Dictionary = runtime.snapshot()
	suite.assert_equal(snapshot.projectiles.filter(func(row: Dictionary): return row.phase == "ACTIVE").size(), 32, "room has at most thirty-two active projectile bodies")
	suite.assert_equal(snapshot.projectiles.filter(func(row: Dictionary): return row.phase == "PENDING").size(), 1, "excess projectile keeps one deterministic pending reservation")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.reserve_projectile(_hit("hostile-moth-0"), BOUNDS, _mechanisms()).ok, "duplicate projectile generation/hit reservation rejects")
	suite.assert_equal(runtime.snapshot(), before, "duplicate reservation cannot spend an extra room budget")
	for frame: int in range(31, 106):
		suite.assert_true(runtime.advance_frame(frame, _observations()).ok, "full-budget room continues advancing existing payloads")
	suite.assert_equal(runtime.snapshot().projectiles.size(), 1, "range expiry releases capacity to the pending projectile")
	suite.assert_equal(runtime.snapshot().projectiles[0].phase, "ACTIVE", "pending reservation starts after capacity becomes available")
	suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "budget/pending/clock state round-trips without fabricated work")


func _test_adversarial_contracts(implementation: Script) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure("run-p15", 30)
	var hit := _hit()
	var reserved: Dictionary = runtime.reserve_projectile(hit, BOUNDS, _mechanisms())
	if not reserved.ok:
		return
	var before: Dictionary = runtime.snapshot()
	hit.damage += 1.0
	suite.assert_true(not runtime.reserve_projectile(hit, BOUNDS, _mechanisms()).ok, "one generation cannot reserve a second body by changing damage")
	suite.assert_equal(runtime.snapshot(), before, "changed duplicate lineage preserves the room budget")
	var wrong_contact := {reserved.id: {"kind": "world", "target_id": "", "position": {"x": 112.0, "y": 100.0}}}
	suite.assert_true(not runtime.advance_frame(31, _observations(wrong_contact)).ok, "native observation cannot jump ahead of the swept frame")
	suite.assert_equal(runtime.snapshot(), before, "invalid contact leaves motion and lifetime unchanged")
	var far_contact := {reserved.id: {"kind": "target", "target_id": "player", "position": {"x": 101.6, "y": 100.0}}}
	suite.assert_true(not runtime.advance_frame(31, _observations(far_contact, {"player": {"x": 500.0, "y": 100.0}})).ok, "a known target away from the native collision cannot receive projectile damage")
	suite.assert_equal(runtime.snapshot(), before, "distant forged target preserves payload clock")
	runtime.restore_snapshot(before)
	var foreign_hit := _hit("hostile-foreign-lineage")
	foreign_hit.geometry[0].attack_generation += 1
	suite.assert_true(not runtime.reserve_projectile(foreign_hit, BOUNDS, _mechanisms()).ok, "projectile envelope cannot substitute a foreign action generation")
	for mutation: String in ["missing_definition", "foreign_control", "extra_record", "over_age"]:
		var invalid := before.duplicate(true)
		match mutation:
			"missing_definition": invalid.projectiles[0].definition.erase("direction")
			"foreign_control": invalid.projectiles[0].control.identity.run_id = "another-run"
			"extra_record": invalid.projectiles[0].unowned = true
			"over_age": invalid.projectiles[0].age = 1
		suite.assert_true(not runtime.restore_snapshot(invalid), "strict payload snapshot rejects %s" % mutation)
		suite.assert_equal(runtime.snapshot(), before, "malformed payload restore has no effect")
