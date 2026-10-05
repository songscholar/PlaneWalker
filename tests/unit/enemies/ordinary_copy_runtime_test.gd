extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Affix := preload("res://scripts/enemies/launch/launch_elite_affix_projection.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var projection_path := "res://scripts/enemies/launch/launch_ordinary_copy_projection.gd"
	var runtime_path := "res://scripts/enemies/launch/launch_ordinary_copy_runtime.gd"
	suite.assert_true(ResourceLoader.exists(projection_path) and ResourceLoader.exists(runtime_path), "Splitting requires canonical ordinary-copy projection and runtime")
	if ResourceLoader.exists(projection_path) and ResourceLoader.exists(runtime_path):
		var projection: Script = load(projection_path)
		var runtime_script: Script = load(runtime_path)
		for enemy: Dictionary in Content.read_catalog("enemies.json"):
			var configuration := _configuration(str(enemy.id))
			var result: Dictionary = projection.create(str(enemy.id), configuration)
			if Rules.CHILD_OWNER_IDS.has(enemy.id):
				suite.assert_true(not result.ok, "copies refuse species with own split, echo, summon, portal or revival: " + str(enemy.id))
				continue
			suite.assert_true(result.ok, "every legal Splitting parent projects: " + str(enemy.id))
			if not result.ok:
				continue
			var parser := Enemy.new()
			parser.configure(enemy)
			var ordinary: Dictionary = parser.runtime_projection()
			var definition: Dictionary = result.definition
			suite.assert_close(definition.max_hp, ordinary.max_hp * 0.33, "copy uses33% ordinary authored HP")
			suite.assert_equal(definition.actions, ordinary.actions, "copy preserves exact ordinary damage and warning actions")
			suite.assert_equal(definition.mechanisms, ordinary.mechanisms, "copy preserves exact ordinary mechanisms")
			suite.assert_true(definition.actor_kind == "summon" and not definition.has("affix_signature"), "copy stays unrewarded child without inherited elite affixes")
			var identity := {"run_id": "run-copies", "hostile_source_id": "copy-" + str(enemy.id), "next_generation_floor": 1, "runtime_frame": 0, "seed": 43}
			var runtime: RefCounted = runtime_script.new()
			suite.assert_true(runtime.configure(definition, identity).ok, "ordinary-copy runtime accepts sealed canonical wrapper")
			var context := _context(0)
			var action: Dictionary = definition.actions[0]
			suite.assert_true(runtime.request_action(action.id, context).ok, "copy selects actual ordinary species action")
			for frame: int in range(1, int(action.warning_frames)):
				var tick: Dictionary = runtime.advance_frame(frame, _context(frame), false)
				suite.assert_true(tick.ok and tick.hit_facts.is_empty(), "copy retains full ordinary damaging warning")
			var before: Dictionary = runtime.snapshot()
			var hit: Dictionary = runtime.advance_frame(int(action.warning_frames), _context(int(action.warning_frames)), false)
			suite.assert_true(hit.ok, "copy accepts native active action frame")
			suite.assert_true(runtime.restore_snapshot(before), "ordinary species state compensates warning frame")
			suite.assert_equal(runtime.advance_frame(int(action.warning_frames), _context(int(action.warning_frames)), false), hit, "copy compensated retry keeps exact action facts")
			var cold: Dictionary = runtime.snapshot()
			var twin: RefCounted = runtime_script.new()
			twin.configure(definition, identity)
			suite.assert_true(twin.restore_snapshot(cold), "copy cold continuation retains ordinary species and child identity")
			var next_frame: int = int(cold.runtime_frame) + 1
			suite.assert_equal(twin.motion_for_frame(next_frame, _context(next_frame)), runtime.motion_for_frame(next_frame, _context(next_frame)), "ordinary copy cold motion is deterministic for every legal species")
			suite.assert_true(runtime.add_control_source("copy-control", "stop", 3, 1.0) and twin.add_control_source("copy-control", "stop", 3, 1.0), "ordinary copies accept normal native controls")
			suite.assert_equal(twin.advance_frame(next_frame, _context(next_frame)), runtime.advance_frame(next_frame, _context(next_frame)), "ordinary copies retain identical controlled native action facts after cold recovery")
			suite.assert_true(runtime.accept_damage_fact({"fact_id": "copy-unit-health", "runtime_frame": next_frame, "target_source_id": identity.hostile_source_id, "amount": 1.0, "hp_after": float(definition.max_hp) - 1.0}).ok, "ordinary copy accepts real bounded body health fact")
			suite.assert_true(runtime.prepare_lethal_transition().final_death, "legal ordinary copies cannot revive or become recursive principals")
			for field: String in ["max_hp", "defense", "move_speed", "collision_radius_px"]:
				var forged := definition.duplicate(true)
				forged[field] += 1.0
				suite.assert_true(not runtime_script.new().configure(forged, identity).ok, "copy rejects altered " + field)
			for field: String in ["actions", "mechanisms", "copy_contract"]:
				var forged := definition.duplicate(true)
				if field == "actions":
					forged.actions[0].weight += 1
				else:
					forged[field]["invented"] = true
				suite.assert_true(not runtime_script.new().configure(forged, identity).ok, "copy rejects mutated " + field)
			var other := definition.duplicate(true)
			other["invented"] = true
			suite.assert_true(not runtime_script.new().configure(other, identity).ok, "copy rejects additional wrapper fields")
			var substituted := cold.duplicate(true)
			substituted.definition_digest = JSON.stringify(ordinary, "", true, true).sha256_text()
			suite.assert_true(not twin.can_restore_snapshot(substituted), "ordinary digest cannot substitute the full origin-bound copy digest")
		var valid := _configuration("shattered_sentinel")
		for field: String in ["native_revision", "floor_index", "pending_ids", "ids"]:
			var forged := valid.duplicate(true)
			match field:
				"native_revision": forged[field] = 9
				"floor_index": forged[field] = 1
				"pending_ids": forged[field] = ["splitting"]
				"ids": forged[field] = ["nullified", "splitting"]
			suite.assert_true(not projection.create("shattered_sentinel", forged).ok, "copy rejects wrong origin " + field)
		suite.assert_true(not projection.create("invented_parent", valid).ok, "copy rejects nonauthored parent")
	suite.finish(get_tree())


func _configuration(id: String) -> Dictionary:
	if Rules.CHILD_OWNER_IDS.has(id):
		return {"ids": ["splitting"], "floor_index": 5, "pending_ids": [], "damage_taken_multiplier": 1.0, "knockback_resistance": 0.0, "native_revision": 10}
	var projection := Affix.new()
	projection.configure([Content.affix("splitting")], 5, 10)
	var parser := Enemy.new()
	parser.configure(Content.enemy(id))
	projection.project(parser.runtime_projection("elite"))
	return projection.snapshot()


func _context(frame: int) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 120.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
