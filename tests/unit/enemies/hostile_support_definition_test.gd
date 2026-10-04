extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for category: String in ["elite_affix", "summon"]:
		var implementation := load("res://scripts/enemies/launch/" + category + "_definition.gd")
		suite.assert_true(implementation != null, "P15 " + category + " definition exists")
		if implementation == null:
			continue
		var rows := Fixtures.read_catalog("elite_affixes.json" if category == "elite_affix" else "summons.json")
		suite.assert_equal(rows.size(), 10 if category == "elite_affix" else 9, "exact support catalog count")
		for row: Dictionary in rows:
			var parser: RefCounted = implementation.new()
			suite.assert_true(parser.configure(row).ok, "real support definition parses: " + row.id)
			for field: String in row:
				var bad := row.duplicate(true)
				bad.erase(field)
				_reject(parser, bad, "support required field: " + row.id + "." + field)
			var bad := row.duplicate(true)
			bad.runtime_script = "res://untrusted.gd"
			_reject(parser, bad, "support script rejects")
			bad = row.duplicate(true)
			bad.compatibility.actor_kinds.append("boss")
			_reject(parser, bad, "support actor kind closed")
			if category == "elite_affix":
				bad = row.duplicate(true)
				bad.parameters.unknown = true
				_reject(parser, bad, "affix parameters closed")
				bad = row.duplicate(true)
				bad.excluded_affix_ids = []
				_reject(parser, bad, "symmetric affix exclusions required")
			else:
				bad = row.duplicate(true)
				bad.capabilities.append("summon")
				_reject(parser, bad, "summon recursion rejects")
				bad = row.duplicate(true)
				bad.reward_eligible = true
				_reject(parser, bad, "summon rewards reject")
				bad = row.duplicate(true)
				bad.spawn_warning_frames = 29
				_reject(parser, bad, "summon spawn warning floor")
				bad = row.duplicate(true)
				bad.max_hp = true
				_reject(parser, bad, "Boolean support HP rejects")
				bad = row.duplicate(true)
				bad.attack.kind = "arbitrary_script"
				_reject(parser, bad, "support attack kind rejects")
	suite.finish(get_tree())


func _reject(parser: RefCounted, bad: Dictionary, label: String) -> void:
	suite.assert_true(not parser.configure(bad).ok, label)
	suite.assert_equal(parser.snapshot(), {}, "failed support configure clears state: " + label)
