extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	var identity := {"run_id": "run-void", "hostile_source_id": "void-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	var runtime := Runtime.new()
	runtime.configure(parser.runtime_projection(), identity)
	suite.assert_true(runtime.snapshot().has("void_auxiliary"), "Boss snapshots retain finite Void auxiliary authority")
	if runtime.snapshot().has("void_auxiliary"):
		var context := {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 380.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
		suite.assert_true(runtime.request_action("voidking_void_step", context).ok, "actual Step warns its oldtarget landing")
		for frame: int in range(1, 30):
			context.runtime_frame = frame
			var motion: Dictionary = runtime.motion_for_frame(frame, context)
			suite.assert_true(motion.displacement == {"x": 0.0, "y": 0.0}, "Step never relocates during warning")
			runtime.advance_frame(frame, context, false)
		context.runtime_frame = 30
		var motion: Dictionary = runtime.motion_for_frame(30, context)
		suite.assert_true(motion.relocation and motion.displacement == {"x": 20.0, "y": 0.0}, "Step relocates to40behind frozen oldtarget")
		context.source_position = {"x": 340.0, "y": 180.0}
		var result: Dictionary = runtime.advance_frame(30, context, false)
		suite.assert_true(result.ok and result.phase == "WARNING" and runtime.snapshot().action.action_id == "voidking_scepter_strike" and runtime.snapshot().action.commit_frame == 30, "accepted Step creates a real new28framewarning action")
		for frame: int in range(31, 58):
			context.runtime_frame = frame
			result = runtime.advance_frame(frame, context, false)
			suite.assert_true(result.ok and result.hit_facts.is_empty(), "Step follow-up never hits before its own28warning")
		context.runtime_frame = 58
		result = runtime.advance_frame(58, context, false)
		suite.assert_true(result.ok and result.hit_facts.size() == 1 and result.hit_facts[0].attack_generation == 8, "Step follow-up uses a new real generation after fullwarning")
		var snapshot: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.can_restore_native_snapshot(snapshot), "accepted Step and follow-up are a strict native cold boundary")
		var fresh := Runtime.new()
		fresh.configure(parser.runtime_projection(), identity)
		suite.assert_true(fresh.restore_snapshot(snapshot) and fresh.snapshot() == snapshot, "fresh Boss retains Step landing and follow-up receipts")
		var forged := snapshot.duplicate(true)
		forged.void_auxiliary.landings[0].followup_generation += 1
		suite.assert_true(not fresh.can_restore_snapshot(forged), "forged follow-up identity fails coldpreflight")
		var old := snapshot.duplicate(true)
		old.schema_version = 5
		old.erase("void_auxiliary")
		old.erase("void_half_index")
		var upgraded: Dictionary = fresh.normalize_native_snapshot(old)
		suite.assert_true(upgraded.get("schema_version") == 8 and upgraded.void_arena_state == old.void_arena_state, "exact schema5 migration preserves native pillars and cores")
	suite.finish(get_tree())
