extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var projection_path := "res://scripts/enemies/launch/launch_summon_projection.gd"
	var runtime_path := "res://scripts/enemies/launch/launch_summon_runtime.gd"
	suite.assert_true(ResourceLoader.exists(projection_path) and ResourceLoader.exists(runtime_path), "all nine support definitions require executable nonrecursive summon runtime")
	if ResourceLoader.exists(projection_path) and ResourceLoader.exists(runtime_path):
		var projection: Script = load(projection_path)
		var runtime_script: Script = load(runtime_path)
		for summon: Dictionary in Content.read_catalog("summons.json"):
			var parent := _parent("shattered_sentinel" if summon.id == "elite_mirror" else str(summon.parent_definition_id))
			var result: Dictionary = projection.create(summon, parent)
			suite.assert_true(result.ok, "authored summon projects executable " + str(summon.id))
			if not result.ok:
				continue
			var definition: Dictionary = result.definition
			suite.assert_true(definition.actor_kind == "summon" and definition.actions.size() == 1 and definition.actions[0].handler_id in ["melee", "charge", "projectile_volley"], "support has exactly one bounded damaging action without recursive capabilities")
			var runtime: RefCounted = runtime_script.new()
			var identity := {"run_id": "run-summons", "hostile_source_id": "summon-test-" + str(summon.id), "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}
			suite.assert_true(runtime.configure(definition, identity).ok, "native child accepts authored " + str(summon.id))
			var action: Dictionary = definition.actions[0]
			suite.assert_true(runtime.request_action(str(action.id), _context(0)).ok, "child starts actual full-warning attack")
			for frame: int in range(1, int(action.warning_frames)):
				var tick: Dictionary = runtime.advance_frame(frame, _context(frame), false)
				suite.assert_true(tick.ok and tick.hit_facts.is_empty(), "summon preserves complete damaging warning")
			var before: Dictionary = runtime.snapshot()
			var hit: Dictionary = runtime.advance_frame(int(action.warning_frames), _context(int(action.warning_frames)), false)
			suite.assert_true(hit.ok and not hit.hit_facts.is_empty(), "child warning produces actual authored damage fact")
			suite.assert_true(runtime.restore_snapshot(before), "summon attack can compensate original warning state")
			suite.assert_equal(runtime.advance_frame(int(action.warning_frames), _context(int(action.warning_frames)), false), hit, "child retry preserves exact damage generation")
			var cold: Dictionary = runtime.snapshot()
			var twin: RefCounted = runtime_script.new()
			twin.configure(definition, identity)
			suite.assert_true(twin.restore_snapshot(cold), "fresh summon retains exact action and control clocks")
			var forged := cold.duplicate(true)
			forged.mechanism_state.hp_after = definition.max_hp + 1.0
			suite.assert_true(not twin.can_restore_snapshot(forged), "child rejects invented health")
			var forbidden := definition.duplicate(true)
			forbidden.actions[0].handler_id = "summon"
			suite.assert_true(not runtime_script.new().configure(forbidden, identity).ok, "child refuses recursive summon capability")
	suite.finish(get_tree())


func _parent(id: String) -> Dictionary:
	var boss: Dictionary = Content.boss(id)
	var parser: RefCounted = Boss.new() if not boss.is_empty() else Enemy.new()
	parser.configure(boss if not boss.is_empty() else Content.enemy(id))
	return parser.runtime_projection()


func _context(frame: int) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 120.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
