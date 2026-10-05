extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
var suite: RefCounted


class CountingAuxiliary extends "res://scripts/enemies/launch/void_auxiliary_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class ColdQueries extends RefCounted:
	var authority: RefCounted
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return authority.snapshot()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var parser := Definition.new()
	suite.assert_true(parser.configure(Content.boss("void_throne")).ok, "exposure observations consume the authored Void Boss")
	var definition := parser.runtime_projection()
	var identity := {"run_id": "run-void-exposure", "hostile_source_id": "void-exposure-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	var runtime := Boss.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "exposure query fixture configures full real Boss")
	var auxiliary := CountingAuxiliary.new()
	suite.assert_true(auxiliary.configure(definition, identity).ok and auxiliary.restore_snapshot(runtime.snapshot().void_auxiliary), "counted real auxiliary retains full Boss authority")
	runtime.set("_void_auxiliary", auxiliary)
	_assert_queries(runtime, auxiliary, "initial")
	suite.assert_true(auxiliary.has_method("native_exposure_through_frame"), "native exposure cutoff belongs to current auxiliary authority")
	if not auxiliary.has_method("native_exposure_through_frame"):
		suite.finish(get_tree())
		return
	var empty := CountingAuxiliary.new()
	suite.assert_equal(empty.call("native_exposure_through_frame"), -1, "unconfigured exposure query retains absent-cutoff sentinel")
	var initial := runtime.snapshot()
	var hp_after := float(definition.max_hp) * float(definition.phases[1].hp_threshold)
	suite.assert_true(runtime.accept_damage_fact({"fact_id": "exposure-phase", "runtime_frame": 0, "target_source_id": identity.hostile_source_id, "amount": float(definition.max_hp) - hp_after, "hp_after": hp_after}).ok, "real damage admits authored tentacle phase")
	_assert_queries(runtime, auxiliary, "phase transition")
	for frame: int in range(1, 61):
		suite.assert_true(runtime.advance_frame(frame, _context(frame), false).ok, "full actual Boss clock advances phase cue")
	_assert_queries(runtime, auxiliary, "phase-two idle")
	suite.assert_true(runtime.request_action("voidking_tentacle_lash", _context(60)).ok, "actual tentacle generation begins full warning")
	_assert_queries(runtime, auxiliary, "tentacle warning")
	var action := {}
	for row: Dictionary in definition.actions:
		if row.id == "voidking_tentacle_lash":
			action = row
	var activation := 60 + int(action.warning_frames)
	for frame: int in range(61, activation + 1):
		suite.assert_true(runtime.advance_frame(frame, _context(frame), false).ok, "real tentacle respects its complete authored warning")
	var active := runtime.snapshot()
	suite.assert_true(active.void_auxiliary.exposure_through_frame == activation + 29 and runtime.is_exposed(), "real tentacle creates exactly thirty accepted exposure frames")
	_assert_queries(runtime, auxiliary, "tentacle active")
	for frame: int in range(activation + 1, activation + 30):
		suite.assert_true(runtime.advance_frame(frame, _context(frame), false).ok, "real tentacle exposure advances to its inclusive cutoff")
	suite.assert_true(runtime.is_exposed(), "exact auxiliary exposure cutoff remains included")
	_assert_queries(runtime, auxiliary, "inclusive cutoff")
	suite.assert_true(runtime.advance_frame(activation + 30, _context(activation + 30), false).ok and not runtime.is_exposed(), "first frame beyond auxiliary cutoff expires exposure")
	_assert_queries(runtime, auxiliary, "expired cutoff")
	suite.assert_true(runtime.cancel(&"exposure_observation").ok, "real terminal Boss retires finite auxiliary work")
	_assert_queries(runtime, auxiliary, "terminal")
	suite.assert_true(runtime.restore_snapshot(active), "complete active tentacle history remains restorable")
	_assert_queries(runtime, auxiliary, "active historical rollback")
	suite.assert_true(runtime.restore_snapshot(initial), "complete initial Boss state remains restorable")
	_assert_queries(runtime, auxiliary, "initial historical rollback")
	var saved: Dictionary = auxiliary.snapshot()
	auxiliary.get("_state").exposure_through_frame = 77
	suite.assert_equal(auxiliary.call("native_exposure_through_frame"), 77, "cutoff query immediately reads actual live authority")
	_assert_queries(runtime, auxiliary, "direct live cutoff change")
	auxiliary.get("_state").terminal = true
	_assert_queries(runtime, auxiliary, "auxiliary terminal does not add a new Boss cutoff rule")
	suite.assert_true(auxiliary.restore_snapshot(saved), "current scalar observations preserve complete historical validation")
	var cold := ColdQueries.new()
	cold.authority = auxiliary
	runtime.set("_void_auxiliary", cold)
	suite.assert_equal(runtime.is_exposed(), _legacy_exposed(runtime, initial), "query-less exposure retains original complete algorithm")
	suite.assert_equal(cold.full_snapshot_calls, 1, "query-less exposure captures once")
	suite.assert_equal(runtime.call("_character_tail_must_wait"), _legacy_tail(runtime, initial), "query-less Character tail retains original algorithm")
	suite.assert_equal(cold.full_snapshot_calls, 2, "query-less Character tail captures once")
	runtime.set("_void_auxiliary", auxiliary)
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(initial), "all observations and fallbacks preserve complete accepted state")
	suite.finish(get_tree())


func _assert_queries(runtime: RefCounted, auxiliary: RefCounted, label: String) -> void:
	var full: Dictionary = runtime.snapshot()
	var before := var_to_bytes(full)
	var expected_exposed := _legacy_exposed(runtime, full)
	var expected_tail := _legacy_tail(runtime, full)
	auxiliary.full_snapshot_calls = 0
	for _repeat: int in range(16):
		suite.assert_equal(runtime.is_exposed(), expected_exposed, "exposure boolean preserves original full-history algorithm: " + label)
		suite.assert_equal(runtime.call("_character_tail_must_wait"), expected_tail, "Character tail preserves original full-history algorithm: " + label)
	suite.assert_equal(auxiliary.full_snapshot_calls, 0, "thirty-two exposure observations avoid complete auxiliary histories: " + label)
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "exposure observations preserve every typed domain byte: " + label)


func _legacy_exposed(runtime: RefCounted, full: Dictionary) -> bool:
	return not full.is_empty() and not full.terminal and (int(full.runtime_frame) <= int(full.mechanism_state.exposure_through_frame) or runtime.get("_conversion").is_character_exposed() or runtime.get("_void_arena").is_exposed() or int(full.runtime_frame) <= int(full.void_auxiliary.exposure_through_frame))


func _legacy_tail(runtime: RefCounted, full: Dictionary) -> bool:
	return not full.is_empty() and (full.action.phase == "RECOVERY" or int(full.runtime_frame) <= int(full.mechanism_state.exposure_through_frame) or runtime.get("_void_arena").is_exposed() or int(full.runtime_frame) <= int(full.void_auxiliary.exposure_through_frame))


func _context(frame: int) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 380.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
