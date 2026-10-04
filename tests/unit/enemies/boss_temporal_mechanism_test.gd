extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var runtime := _runtime()
	suite.assert_true(runtime.has_method("accept_weakpoint_damage_fact"), "Time Sovereign history and rewind require an executable weakpoint cancellation authority")
	if runtime.has_method("accept_weakpoint_damage_fact"):
		_test_history_landing_and_healing()
		_test_weakpoint_cancellation()
	suite.finish(get_tree())


func _runtime() -> RefCounted:
	var parser := Boss.new()
	parser.configure(Content.boss("time_sovereign"))
	var runtime := Runtime.new()
	runtime.configure(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-temporal", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
	return runtime


func _observation(frame: int) -> Dictionary:
	var value := Actions.context(frame)
	value.source_position = {"x": 100.0 + frame % 60, "y": 100.0}
	return value


func _prepare_history(runtime: RefCounted) -> void:
	for frame: int in range(1, 211):
		suite.assert_true(runtime.advance_frame(frame, _observation(frame), false).ok, "accepted temporal history advances independently of action selection")
		if frame == 150:
			suite.assert_true(runtime.accept_damage_fact({"fact_id": "temporal-damage", "runtime_frame": frame, "target_source_id": "hostile-temporal", "amount": 1000.0, "hp_after": 1000.0}).ok, "historical HP records actual accepted damage")


func _test_history_landing_and_healing() -> void:
	var runtime := _runtime()
	_prepare_history(runtime)
	var started: Dictionary = runtime.request_action("traitor_self_rewind", _observation(210))
	suite.assert_true(started.ok and started.threat_facts.size() == 1, "self rewind visibly marks its frozen historical landing during the full warning")
	var committed: Dictionary = runtime.snapshot()
	suite.assert_equal(committed.mechanism_state.history.size(), 180, "Time Sovereign retains exactly bounded accepted-frame history")
	suite.assert_equal(committed.mechanism_state.rewind.heal_amount, 150.0, "rewind freezes the authored per-cast heal cap")
	suite.assert_equal(committed.mechanism_state.rewind.landing, {"x": 131.0, "y": 100.0}, "rewind landing belongs to retained accepted history")
	for frame: int in range(211, 280):
		var batch: Dictionary = runtime.advance_frame(frame, _observation(frame), false)
		suite.assert_true(batch.ok and batch.mechanism_requests.is_empty(), "self rewind cannot heal before its complete seventy-frame warning")
	var checkpoint: Dictionary = runtime.snapshot()
	var at_active := _observation(280)
	suite.assert_equal(runtime.motion_for_frame(280, at_active).displacement, {"x": -9.0, "y": 0.0}, "native preflight targets the frozen historical landing")
	var batch: Dictionary = runtime.advance_frame(280, at_active, false)
	suite.assert_true(batch.ok and batch.mechanism_requests.size() == 1 and batch.mechanism_requests[0].kind == "boss_self_rewind", "accepted self rewind emits one transactional native healing request")
	suite.assert_equal(batch.mechanism_requests[0].amount, 150.0, "native healing request preserves the frozen cap")
	suite.assert_equal(runtime.snapshot().mechanism_state.rewind_healing_spent, 150.0, "accepted rewind consumes its bounded encounter budget")
	suite.assert_true(runtime.restore_snapshot(checkpoint), "rejected rewind restores history and unspent healing budget")
	suite.assert_equal(runtime.advance_frame(280, at_active, false), batch, "same accepted rewind frame retries deterministically")
	suite.assert_true(runtime.accept_health_fact({"fact_id": "temporal-heal", "runtime_frame": 280, "target_source_id": "hostile-temporal", "amount": 150.0, "hp_after": 1150.0}).ok, "actual native heal settles the independent domain HP")
	suite.assert_equal(runtime.snapshot().mechanism_state.phase_index, 1, "rewind preserves accepted phase, cooldown and hit claims")
	suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "healed temporal history and consumed cast form a closed checkpoint")
	var forged: Dictionary = runtime.snapshot()
	forged.mechanism_state.history[0].runtime_frame -= 1
	suite.assert_true(not runtime.restore_snapshot(forged), "history cannot contain skipped or fabricated accepted clocks")
	forged = runtime.snapshot()
	forged.mechanism_state.rewind_healing_spent = 301.0
	suite.assert_true(not runtime.restore_snapshot(forged), "replay cannot exceed authored encounter healing cap")


func _test_weakpoint_cancellation() -> void:
	var runtime := _runtime()
	_prepare_history(runtime)
	runtime.request_action("traitor_self_rewind", _observation(210))
	var first := {"fact_id": "watch-hit-one", "runtime_frame": 210, "attack_generation": 7, "amount": 40.0}
	suite.assert_true(runtime.accept_weakpoint_damage_fact(first).ok, "actual watch hit contributes to the committed rewind threshold")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.accept_weakpoint_damage_fact(first).ok and runtime.snapshot() == before, "duplicate weakpoint hit cannot contribute twice")
	var cancelled: Dictionary = runtime.accept_weakpoint_damage_fact({"fact_id": "watch-hit-two", "runtime_frame": 210, "attack_generation": 7, "amount": 40.0})
	suite.assert_true(cancelled.ok and cancelled.cancelled and cancelled.retired_generations == [7], "eighty distinct watch damage cancels and retires the entire rewind warning")
	for frame: int in range(211, 265):
		var batch: Dictionary = runtime.advance_frame(frame, _observation(frame), false)
		suite.assert_true(batch.ok and batch.mechanism_requests.is_empty() and batch.threat_facts.is_empty(), "cancelled rewind grants fifty-five nonattacking punishment frames without healing")
	suite.assert_equal(runtime.snapshot().mechanism_state.rewind_healing_spent, 0.0, "cancelled rewind spends no healing budget")
	suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "cancelled history retains claimed weakpoint identities")
