extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/boss_definition.gd")
	suite.assert_true(implementation != null, "P15 BossDefinition parser exists")
	if implementation != null:
		var rows := Fixtures.read_catalog("bosses.json")
		suite.assert_equal(rows.size(), 5, "five real authored Bosses exist")
		var total_actions := 0
		var total_responses := 0
		for row: Dictionary in rows:
			var parser: RefCounted = implementation.new()
			var parsed: Dictionary = parser.configure(row)
			suite.assert_true(parsed.ok, "real Boss parses: " + row.id + " " + str(parsed.get("context", {})))
			if not parsed.ok:
				continue
			total_actions += parser.snapshot().actions.size()
			total_responses += parser.snapshot().time_responses.size()
			var projection: Dictionary = parser.runtime_projection()
			suite.assert_equal(projection.keys().size(), 13, "Boss runtime projection has thirteen closed fields including physical collision")
			suite.assert_equal(projection.actor_kind, "boss", "Boss kind retained")
			projection.phases.clear()
			suite.assert_true(not parser.snapshot().phases.is_empty(), "projection isolates phase authority")
		suite.assert_equal(total_actions, 48, "all forty-eight primary moves parse")
		suite.assert_equal(total_responses, 4, "all four authentic ability responses parse")
		_test_rejection(implementation)
	suite.finish(get_tree())


func _test_rejection(implementation: Script) -> void:
	var row := Fixtures.boss()
	if row.is_empty():
		return
	var parser: RefCounted = implementation.new()
	for field: String in row:
		var bad := row.duplicate(true)
		bad.erase(field)
		_reject(parser, bad, "required Boss field: " + field)
	var bad := row.duplicate(true)
	bad.phases[1].hp_threshold = 1.0
	_reject(parser, bad, "phase thresholds strictly decrease")
	bad = row.duplicate(true)
	bad.phases[0].action_ids.append("guardian_enrage_collapse")
	_reject(parser, bad, "enrage cannot bypass its bounded clock")
	bad = row.duplicate(true)
	bad.phases[0].action_ids.append("unknown_move")
	_reject(parser, bad, "unresolved phase action rejects")
	bad = row.duplicate(true)
	bad.actions[0].warning_frames = 39
	_reject(parser, bad, "first Boss forty-frame warning floor")
	bad = row.duplicate(true)
	bad.enrage.threshold_frames = true
	_reject(parser, bad, "Boolean enrage frame rejects")
	bad = row.duplicate(true)
	bad.arena.safe_corridor_width_px = 47
	_reject(parser, bad, "last safe corridor cannot shrink below forty-eight pixels")
	bad = row.duplicate(true)
	bad.arena.constructs[0].script = "res://untrusted.gd"
	_reject(parser, bad, "constructs never accept arbitrary scripts")
	bad = row.duplicate(true)
	bad.mechanisms.phase_damage_overrides.p2.unknown_move = 22
	_reject(parser, bad, "phase damage only targets authored action IDs")
	bad = row.duplicate(true)
	bad.time_responses = [row.actions[0].duplicate(true)]
	_reject(parser, bad, "responses only belong to the declared time Boss")
	bad = Fixtures.boss("time_sovereign")
	bad.time_responses[0].warning_frames = 44
	_reject(parser, bad, "every time-response warning reaches forty-five frames")


func _reject(parser: RefCounted, bad: Dictionary, label: String) -> void:
	suite.assert_true(parser.configure(Fixtures.boss()).ok, "seed Boss parser before invalid configure")
	suite.assert_true(not parser.configure(bad).ok, label)
	suite.assert_equal(parser.snapshot(), {}, "failed Boss configure clears state: " + label)
