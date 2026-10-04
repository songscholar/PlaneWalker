extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/enemy_definition.gd")
	suite.assert_true(implementation != null, "P15 EnemyDefinition parser exists")
	if implementation != null:
		_test_real_catalog(implementation)
		_test_projection(implementation)
		_test_rejection(implementation)
	suite.finish(get_tree())


func _test_real_catalog(implementation: Script) -> void:
	var rows := Fixtures.read_catalog("enemies.json")
	suite.assert_equal(rows.size(), 22, "exact twenty-two authored ordinary species")
	for row: Dictionary in rows:
		var parser: RefCounted = implementation.new()
		var result: Dictionary = parser.configure(row)
		suite.assert_true(result.ok, "real species parses: " + row.id + " " + str(result.get("context", {})))
		if result.ok:
			suite.assert_equal(result.definition.id, row.id, "normalized species retains identity")
			for actor_kind: String in ["enemy", "elite"]:
				var projection: Dictionary = parser.runtime_projection(actor_kind)
				suite.assert_equal(projection.get("collision_radius_px"), row.collision_radius_px, "native %s retains authored body radius: %s" % [actor_kind, row.id])
			var snapshot: Dictionary = parser.snapshot()
			snapshot.mechanisms.clear()
			suite.assert_true(not parser.snapshot().mechanisms.is_empty(), "snapshot isolates authored mechanisms")
			result.definition.actions.clear()
			suite.assert_true(not parser.snapshot().actions.is_empty(), "configure output isolates state")


func _test_projection(implementation: Script) -> void:
	var parser: RefCounted = implementation.new()
	var row := Fixtures.enemy()
	var authored_radius: float = row.collision_radius_px
	suite.assert_true(parser.configure(row).ok, "Sentinel configures for native projection")
	var ordinary: Dictionary = parser.runtime_projection()
	var expected_fields: Array[String] = ["id", "actor_kind", "runtime_kind", "max_hp", "defense", "move_speed", "collision_radius_px", "actions", "mechanisms"]
	var actual_fields: Array = ordinary.keys()
	expected_fields.sort()
	actual_fields.sort()
	suite.assert_equal(actual_fields, expected_fields, "native enemy projection has exactly nine authenticated fields")
	suite.assert_equal(ordinary.get("collision_radius_px"), row.collision_radius_px, "ordinary projection retains authored radius")
	suite.assert_equal(ordinary.actor_kind, "enemy", "ordinary default kind")
	suite.assert_equal(ordinary.actions.size(), 1, "ordinary excludes elite action")
	suite.assert_equal(ordinary.mechanisms, parser.snapshot().mechanisms, "runtime retains one authoritative mechanism definition")
	var elite: Dictionary = parser.runtime_projection("elite")
	suite.assert_equal(elite.get("collision_radius_px"), row.collision_radius_px, "elite keeps authored radius while HP and damage scale")
	suite.assert_equal(elite.max_hp, 160.0, "elite body has twice base HP")
	suite.assert_equal(elite.actions.size(), 2, "elite retains base action and appends species move")
	suite.assert_equal(elite.actions[0].hit_schedule[0].damage, 15.0, "elite base damage multiplied exactly once")
	suite.assert_equal(elite.actions[1].hit_schedule[0].damage, 30.0, "elite species damage multiplied exactly once")
	elite.actions[0].parameters.knockback_px = 64
	elite.collision_radius_px = 32.0
	row.collision_radius_px = 1.0
	suite.assert_equal(parser.runtime_projection("elite").actions[0].parameters.knockback_px, 19.0, "projection deeply isolated")
	suite.assert_equal(parser.runtime_projection("elite").get("collision_radius_px"), authored_radius, "neither source nor returned projection can change configured radius")
	var alternate := Fixtures.enemy()
	alternate.collision_radius_px = 13.5
	suite.assert_true(parser.configure(alternate).ok, "alternate valid authored radius configures")
	suite.assert_equal(parser.runtime_projection().get("collision_radius_px"), 13.5, "radius projection derives from authored values rather than scene defaults")
	suite.assert_equal(parser.runtime_projection("boss"), {}, "unsupported native kind refuses")


func _test_rejection(implementation: Script) -> void:
	var parser: RefCounted = implementation.new()
	var row := Fixtures.enemy()
	for field: String in row:
		var bad := row.duplicate(true)
		bad.erase(field)
		_reject(parser, bad, "required enemy field: " + field)
	for field: String in ["max_hp", "defense", "move_speed", "threat_cost", "collision_radius_px"]:
		var bad := row.duplicate(true)
		bad[field] = true
		_reject(parser, bad, "Boolean-as-number rejects: " + field)
	for field: String in ["max_hp", "move_speed"]:
		var bad := row.duplicate(true)
		bad[field] = INF
		_reject(parser, bad, "nonfinite rejects: " + field)
	for key: String in ["_BAD", "1BAD", "A"]:
		var malformed := row.duplicate(true)
		malformed.name_key = key
		_reject(parser, malformed, "localization key matches shared schema: " + key)
	var bad := row.duplicate(true)
	bad.runtime_script = "res://untrusted.gd"
	_reject(parser, bad, "arbitrary script rejects")
	bad = row.duplicate(true)
	bad.compatibility.actor_kinds.append("boss")
	_reject(parser, bad, "enemy compatibility is closed")
	bad = row.duplicate(true)
	bad.mechanisms.untrusted = true
	_reject(parser, bad, "unknown species mechanism rejects")
	bad = row.duplicate(true)
	bad.mechanisms.retreat_frames = 1.5
	_reject(parser, bad, "fractional mechanism frame rejects")
	bad = row.duplicate(true)
	bad.floor_id = "floor_void_forest"
	_reject(parser, bad, "identity floor mismatch rejects")
	bad = row.duplicate(true)
	bad.references.append("unknown_summon")
	_reject(parser, bad, "unresolved reference rejects")
	bad = row.duplicate(true)
	bad.actions[0].warning_frames = 29
	_reject(parser, bad, "floor-one warning floor enforced")
	bad = row.duplicate(true)
	bad.elite_actions[0].id = bad.actions[0].id
	_reject(parser, bad, "ordinary and elite action IDs cannot collide")
	bad = row.duplicate(true)
	bad.actions[0].id = "void_hunter.shield_sweep"
	_reject(parser, bad, "foreign species action namespace rejects")
	bad = row.duplicate(true)
	bad.actions[0].id = "shattered_sentinel.unimplemented_attack"
	_reject(parser, bad, "unknown action in valid species namespace rejects")
	bad = Fixtures.enemy("ruins_wraith")
	bad.mechanisms.consume_after_active = 1
	_reject(parser, bad, "Boolean mechanism never coerces integers")


func _reject(parser: RefCounted, bad: Dictionary, label: String) -> void:
	suite.assert_true(parser.configure(Fixtures.enemy()).ok, "seed parser before invalid configure")
	suite.assert_true(not parser.configure(bad).ok, label)
	suite.assert_equal(parser.snapshot(), {}, "invalid configure clears previous state: " + label)
