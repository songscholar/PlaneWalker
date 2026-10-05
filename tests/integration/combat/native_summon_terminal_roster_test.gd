extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	var f := await _fixture("forest_caller")
	var action := Content.action("forest_caller.void_call")
	suite.assert_true(_start(f, action.id), "actual Caller starts the authored two-child warning")
	for _frame: int in range(int(action.warning_frames)):
		suite.assert_true(_step(f), "terminal roster fixture accepts the full native warning")
	suite.assert_true(_step(f), "both actual summons join the next shared frame")
	var children: Dictionary = f.effects.native_summon_actors()
	suite.assert_equal(children.size(), 2, "terminal roster fixture owns two actual authored children")
	if children.size() != 2:
		await _dispose(f)
		suite.finish(get_tree())
		return
	var child: Node2D = children.values()[0]
	var source := str(child.hostile_source_id)
	var deaths: Array = []
	child.hostile_final_death.connect(func(id: StringName, receipt: String): deaths.append({"id": str(id), "receipt": receipt}))
	suite.assert_true(_hit(child, f.player, 100000.0, 901) > 0.0 and child.health.dead and child.launch_runtime_snapshot().runtime.terminal, "explicit authenticated lethal fixture finalizes one actual native child")
	suite.assert_true(f.bridge.retire_actor(source), "accepted final death retires the child from the native frame roster")
	suite.assert_true(f.effects.native_summon_actors().has(source), "actual summon owner retains the terminal projection until its next cleanup frame")
	var before: Dictionary = f.effects.snapshot()
	var threats_before: Array = f.registry.snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(int(f.frame) + 1)
	suite.assert_true(not ticket.is_empty(), "terminal child cannot refuse the next accepted native cleanup frame")
	if not ticket.is_empty():
		suite.assert_true(f.bridge.prepare_frame(ticket), "accepted native frame prepares terminal child cleanup")
		suite.assert_true(not f.effects.native_summon_actors().has(source), "prepared native cleanup releases only the dead child projection")
		suite.assert_true(f.bridge.rollback_frame(ticket), "late native refusal compensates dead-child cleanup")
		suite.assert_equal(f.effects.snapshot(), before, "terminal child rollback restores the exact summon lease and native state")
		suite.assert_equal(f.registry.snapshot(), threats_before, "terminal child rollback restores the exact prior warning ledger")
		suite.assert_true(f.effects.native_summon_actors().has(source) and not f.bridge.get("_actors").has(source), "compensation restores the terminal projection without reactivating its roster")
		suite.assert_true(_step(f), "terminal native child cleanup retries the original accepted frame")
		suite.assert_equal(deaths.size(), 1, "terminal cleanup cannot republish the authenticated native death")
		suite.assert_equal(f.effects.native_summon_actors().size(), 1, "surviving actual sibling remains in the native roster")
		suite.assert_true(_step(f), "surviving actual summon accepts the following shared frame")
	await _dispose(f)
	suite.finish(get_tree())
