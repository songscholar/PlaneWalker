extends "res://tests/integration/save/native_combat_checkpoint_test.gd"


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var controller: Node = main.get_node("CombatRoom01")
	controller.visible = true
	controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	var save := Save.new()
	var catalog: RefCounted = Factory.load_base().context.catalog
	var service := Service.new()
	save.configure(Paths.resolve_default("user://native-boss-sources", "native-boss-sources"), "0.4.0-dev", Content.snapshot(host.content_registry()))
	service.configure(catalog, save, "boss_source_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(host.start_profile_run(config, service, int(service.snapshot().revision)).ok, "ordinary production Host starts an authenticated Profile run")
	# Prerequisite combat clears are fixtures; the Boss stays fully native.
	suite.assert_true(await _route_to_native_target(suite, host, true), "ordinary production route reaches the real first Boss")
	host.set_dungeon_selection_safety(false)
	var runner: Node = controller.encounter_runner()
	for _frame: int in range(120):
		if runner.alive_count() > 0:
			break
		suite.assert_true(player.advance_action_frame(), "ordinary Boss warning advances accepted native frame")
		await get_tree().physics_frame
	var bosses: Array[Node] = controller.get_node("Enemies").get_children()
	suite.assert_true(bosses.size() == 1, "ordinary Boss route binds exactly one production principal")
	if not bosses.is_empty():
		var boss: Node = bosses[0]
		var source := str(boss.hostile_source_id)
		var run := str(player.current_run_id())
		var receipt := "hostile_defeat:" + (run + "|" + source).sha256_text().substr(0, 40)
		var before: Dictionary = host.runtime_snapshot()
		boss.hostile_final_death.emit(StringName(source), receipt)
		suite.assert_equal(host.runtime_snapshot(), before, "matching text notice from live Boss cannot forge a settlement source")
		boss.health.lose_health(1000000.0, player)
		suite.assert_true(player.advance_action_frame(), "actual lethal native Boss receipt commits")
		await get_tree().physics_frame
		await get_tree().process_frame
		var completed: Dictionary = host.runtime_snapshot()
		var sources: Array = []
		for event: Dictionary in completed.events:
			if event.get("type") == Settlement.SOURCE_TYPE and event.receipt.kind == "boss":
				sources.append(event.receipt)
		suite.assert_true(completed.completed_floor_ids.size() == 1 and sources.size() == 1, "real ordinary Boss death retains exactly one authenticated completion source")
		if sources.size() == 1:
			suite.assert_equal(sources[0].payload.boss_id, "ruin_king", "retained source identifies the bound production Boss")
			suite.assert_equal(sources[0].launch_sequence, service.snapshot().active_launch_receipt.sequence, "retained source binds actual Profile launch sequence")
			var authority := Settlement.new()
			var boss_by_floor := {}
			for index: int in range(Settlement.BOSS_ORDER.size()):
				boss_by_floor[preload("res://scripts/save/save_envelope.gd").FLOOR_IDS[index]] = Settlement.BOSS_ORDER[index]
			authority.configure(catalog, boss_by_floor)
			suite.assert_true(authority.verified_run_sources(service.snapshot().active_launch_receipt, completed).ok, "ordinary checkpoint source verifier accepts actual native Boss")
		var retained: Variant = host.checkpoint_profile_run(int(service.snapshot().revision))
		suite.assert_true(retained.ok, "ordinary actual Boss completion checkpoint saves: " + str(retained))
	await _dispose(main)
	suite.finish(get_tree())
