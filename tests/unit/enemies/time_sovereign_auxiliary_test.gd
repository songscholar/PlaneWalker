extends Node

const Suite := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	var suite := Suite.new()
	var script: Script = load("res://scripts/enemies/launch/time_sovereign_auxiliary_runtime.gd")
	suite.assert_true(script != null, "regular Time auxiliary module exists")
	if script == null:
		suite.finish(get_tree())
		return
	var runtime: RefCounted = script.new()
	var identity := {"run_id": "run-time-aux", "hostile_source_id": "time-owner", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}
	suite.assert_true(runtime.configure(identity), "regular Time auxiliary authentic identity configures")
	suite.assert_true(runtime.advance_frame(1), "auxiliary accepts next fixed frame")
	var miss := _fact("miss", "traitor_temporal_slash", 1, 0.0)
	suite.assert_true(runtime.accept_damage_receipt(miss).ok, "prevented Slash retains authenticated receipt")
	suite.assert_true(runtime.snapshot().marks.is_empty(), "prevented Slash installs no mark")
	var slash := _fact("slash", "traitor_temporal_slash", 1, 24.0)
	suite.assert_true(runtime.accept_damage_receipt(slash).ok, "accepted Slash installs mark")
	suite.assert_equal(runtime.time_damage_multiplier("player"), 1.15, "Time damage consumes authored mark")
	suite.assert_equal(runtime.snapshot().marks.size(), 1, "single accepted Slash holds one mark")
	suite.assert_true(not runtime.accept_damage_receipt(slash).ok, "accepted damage receipt is once only")
	for frame: int in range(2, 20):
		runtime.advance_frame(frame)
	suite.assert_true(runtime.accept_damage_receipt(_fact("refresh", "traitor_temporal_slash", 19, 30.0)).ok, "new Slash refreshes existing mark")
	suite.assert_equal(runtime.snapshot().marks.size(), 1, "refresh never stacks a second mark")
	suite.assert_equal(runtime.snapshot().marks[0].through_frame, 259, "refresh grants exactly240future accepted frames")
	var saved: Dictionary = runtime.snapshot()
	var fresh: RefCounted = script.new()
	fresh.configure(identity)
	suite.assert_true(fresh.restore_snapshot(saved), "fresh auxiliary reconstructs exact mark and receipts")
	suite.assert_equal(fresh.snapshot(), saved, "fresh reconstruction preserves exact state")
	var malformed := saved.duplicate(true)
	malformed.marks[0].through_frame += 1
	suite.assert_true(not fresh.restore_snapshot(malformed), "forged mark duration is rejected")
	malformed = saved.duplicate(true)
	malformed["unknown"] = true
	suite.assert_true(not fresh.restore_snapshot(malformed), "unknown auxiliary field is rejected")
	for frame: int in range(20, 259):
		runtime.advance_frame(frame)
	suite.assert_equal(runtime.time_damage_multiplier("player"), 1.15, "mark survives through its last accepted frame")
	runtime.advance_frame(259)
	suite.assert_equal(runtime.time_damage_multiplier("player"), 1.0, "mark retires at exclusive boundary")
	suite.assert_equal(runtime.collapse_energy_allowance(100.0, 50.0), 10.0, "Collapse cap removes at most10energy")
	suite.assert_equal(runtime.collapse_energy_allowance(5.0, 50.0), 4.0, "Collapse leaves1energy when low")
	suite.assert_equal(runtime.collapse_energy_allowance(0.5, 50.0), 0.0, "Collapse preserves positive fractional energy")
	suite.assert_equal(runtime.collapse_energy_allowance(100.0, 0.0), 0.0, "prevented Collapse removes no energy")
	runtime.retire()
	suite.assert_true(runtime.snapshot().marks.is_empty(), "owner retirement clears owned marks")
	suite.finish(get_tree())


func _fact(id: String, action: String, frame: int, loss: float) -> Dictionary:
	return {"fact_id": id, "run_id": "run-time-aux", "owner_source_id": "time-owner", "action_id": action, "attack_generation": 3 if id == "miss" else 2 if id == "refresh" else 1, "hit_index": 0, "target_id": "player", "runtime_frame": frame, "actual_loss": loss}
