extends "res://tests/integration/combat/authored_challenge_native_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	await _checkpoint_faults()
	await _cold_practice()
	await _competing_writers(false)
	await _competing_writers(true)
	await _retained_history()
	await _construction_retry()
	_suite.finish(get_tree())


func _checkpoint_faults() -> void:
	for point: StringName in [&"before_primary_promote", &"after_primary_promote"]:
		var fixture := _daily_fixture("authored-fault-" + str(point))
		var flow := _authored_flow(fixture)
		var reentrant: Dictionary = {}
		flow.set_fault_injector(func(at: StringName):
			if at == point:
				reentrant.merge(flow.start("bow_precision"), true)
				return true
			return false)
		var started: Dictionary = flow.start("sword_timer")
		_suite.assert_true(not reentrant.ok, "physical authored write refuses reentrant admission")
		if point == &"before_primary_promote":
			_suite.assert_true(not started.ok and flow.has_pending_save() and not flow.is_active() and flow.snapshot().sequence == 0, "failed admission neither publishes sequence nor constructs arena")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok and flow.is_active() and flow.snapshot().sequence == 1, "retry admits exactly one actual native trial")
		else:
			_suite.assert_true(started.ok and flow.is_active() and not flow.has_pending_save(), "post-promotion ambiguity accepts only equal physical primary")
		flow.set_fault_injector(func(at: StringName): return at == point)
		await _kill_boss(flow)
		if point == &"before_primary_promote":
			_suite.assert_true(flow.has_pending_save() and flow.snapshot().active.stages.is_empty() and not flow.next_stage().ok, "failed Boss clear freezes actual dead Boss without publishing receipt")
			var frozen: Dictionary = flow.snapshot()
			await _frames(3)
			_suite.assert_equal(flow.snapshot(), frozen, "pending native save advances no authored timer")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok and flow.snapshot().active.status == "STAGE_CLEAR", "saved actual Boss clear retries without repeating combat")
		else:
			_suite.assert_true(flow.snapshot().active.status == "STAGE_CLEAR" and not flow.has_pending_save(), "promoted authentic Boss clear persists despite after-promotion fault")
		flow.set_fault_injector(Callable())
		_suite.assert_true(flow.save_and_return().ok, "completed Boss boundary may physically save and return")
		await _dispose(flow)


func _cold_practice() -> void:
	var fixture := _daily_fixture("authored-practice")
	var flow := _authored_flow(fixture)
	_suite.assert_true(flow.start("sword_timer").ok, "fresh authored run starts before cold boundary")
	await _kill_boss(flow)
	_suite.assert_true(flow.next_stage().ok, "actual second native Boss starts")
	await _frames(5)
	flow.set_paused(true)
	var paused: Dictionary = flow.snapshot()
	await _frames(5)
	_suite.assert_equal(flow.snapshot(), paused, "controller-style native pause freezes all accepted mode frames")
	_suite.assert_true(flow.save_and_return().ok, "explicit return saves accepted frames and practice classification")
	var saved: Dictionary = flow.snapshot()
	await _dispose(flow)
	flow = _authored_flow(fixture)
	_suite.assert_equal(flow.snapshot(), saved, "physical reload normalizes and retains exact authored stage/metrics")
	_suite.assert_true(flow.continue_session().ok and flow.snapshot().active.continued, "cold native reconstruction remains classified as continued practice")
	_suite.assert_equal(flow.snapshot().active.stage_index, 1, "cold reconstruction preserves earned Boss stage")
	await _kill_boss(flow)
	_suite.assert_true(flow.next_stage().ok, "continued stage can advance actual third Boss")
	await _kill_boss(flow)
	_suite.assert_true(flow.preview().history.sword_timer[-1].continued and flow.preview().history.sword_timer[-1].status == "VICTORY", "continued objective victory is durable history")
	_suite.assert_true(not flow.preview().best.has("sword_timer"), "continued victory cannot grant a fresh best")
	_suite.assert_true(flow.start("bow_precision").ok, "uninterrupted second set starts")
	await _frames(3)
	await _dispose(flow)
	flow = _authored_flow(fixture)
	_suite.assert_true(flow.continue_session().ok and flow.snapshot().active.continued, "abrupt physical restart marks even unsaved active admission as practice")
	_suite.assert_true(flow.abandon().ok, "cold continued arena can explicitly abandon")
	await _dispose(flow)


func _competing_writers(identical: bool) -> void:
	var fixture := _daily_fixture("authored-race-" + str(identical))
	var losing := _authored_flow(fixture)
	var winner := _authored_flow(fixture)
	var competing: Dictionary = {}
	losing.set_fault_injector(func(at: StringName):
		if at == &"before_primary_promote":
			competing.merge(winner.start("sword_timer" if identical else "bow_precision"), true)
		return false)
	var result: Dictionary = losing.start("sword_timer")
	_suite.assert_true(competing.ok and not result.ok and result.code == &"AUTHORED_STALE_PRIMARY", "explicit lost CAS refuses equal/different authored candidates: " + str(identical))
	_suite.assert_true(not losing.is_active() and winner.is_active(), "losing writer cannot construct another native arena")
	losing.set_fault_injector(Callable())
	_suite.assert_true(not losing.retry_save().ok, "stale candidate cannot overwrite the physical winner")
	_suite.assert_true(losing.reload_saved_session().ok and losing.snapshot().active == winner.snapshot().active, "stale loser reloads actual physical identity")
	await _dispose(winner)
	_suite.assert_true(losing.continue_session().ok and losing.snapshot().active.continued, "reloaded physical winner may reconstruct only as continued practice")
	_suite.assert_true(losing.abandon().ok, "reloaded practice can settle one abandonment")
	await _dispose(losing)


func _retained_history() -> void:
	var fixture := _daily_fixture("authored-history")
	var flow := _authored_flow(fixture)
	_suite.assert_true(flow.start("sword_timer").ok, "history first fresh trial starts")
	for index: int in range(3):
		if index > 0:
			_suite.assert_true(flow.next_stage().ok, "history fixture advances authenticated stage")
		await _kill_boss(flow)
	var best: Dictionary = flow.preview().best.sword_timer
	for _attempt: int in range(12):
		_suite.assert_true(flow.start("sword_timer").ok and flow.abandon().ok, "authored attempts have no arbitrary daily cap")
	_suite.assert_equal(flow.preview().history.sword_timer.size(), 10, "physical authored history retains at most ten recent attempts per set")
	_suite.assert_equal(flow.preview().best.sword_timer, best, "native lifetime fresh best survives old victory history pruning")
	await _dispose(flow)
	flow = _authored_flow(fixture)
	_suite.assert_equal(flow.preview().best.sword_timer, best, "cold reload retains pruned lifetime best")
	_suite.assert_equal(flow.preview().history.sword_timer.size(), 10, "cold reload retains bounded authored history")
	await _dispose(flow)


func _construction_retry() -> void:
	var fixture := _daily_fixture("authored-native-fault")
	var flow := _authored_flow(fixture)
	var catalog: RefCounted = flow.get("_catalog")
	var rush: RefCounted = catalog.get("_rush")
	var stages: Array = rush.get("_stages")
	var before: Dictionary = stages[0].duplicate(true)
	stages[0].runtime_definition = {}
	var refused: Dictionary = flow.start("sword_timer")
	_suite.assert_true(not refused.ok and flow.snapshot().sequence == 1 and flow.preview().native_retry, "construction failure keeps physically admitted authored sequence")
	stages[0] = before
	_suite.assert_true(flow.retry_native().ok and flow.snapshot().sequence == 1 and not flow.snapshot().active.continued, "same-process construction retry creates actual arena without another admission or practice mark")
	_suite.assert_true(flow.abandon().ok, "construction recovery can settle admitted attempt")
	await _dispose(flow)
