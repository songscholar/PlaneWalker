extends "res://tests/integration/save/natural_elite_encounter_checkpoint_test.gd"

const SpeciesRoute := preload("res://tests/support/native_species_route_finder.gd")

func _run() -> void:
	var suite := Suite.new()
	var target := SpeciesRoute.find_species("eternal_hound", 2)
	suite.assert_true(not target.is_empty(), "deterministic FloorGenerator supplies an authored Hound recipe")
	if target.is_empty():
		suite.finish(get_tree())
		return
	var f := await _new_profile(suite, target.seed, "hound_sigil")
	var selected := await _route_to_recipe(suite, f.host, 2, target.node_id)
	suite.assert_true(selected, "actual Host reaches an authored Hound route without encounter injection")
	if not selected:
		await _dispose(f.main)
		suite.finish(get_tree())
		return
	f.host.set_dungeon_selection_safety(false)
	f.player.health.acquire_invulnerability_source(&"hound-cold-isolation")
	var driver: Node = f.runner.get_node("NativeLaunchEncounterDriver")
	var owner: Node2D
	for _frame: int in range(100):
		for actor: Node2D in driver.get("_actors").values():
			if actor.get("_launch_definition").id == "eternal_hound":
				owner = actor
		if is_instance_valid(owner):
			break
		suite.assert_true(f.player.advance_action_frame(), "actual Hound route completes native spawn warning")
		await get_tree().physics_frame
	suite.assert_true(is_instance_valid(owner), "production Driver constructs actual Hound principal")
	if not is_instance_valid(owner):
		await _dispose(f.main)
		suite.finish(get_tree())
		return
	var source := str(owner.hostile_source_id)
	suite.assert_true(owner.get("_launch_runtime").add_control_source("hound-cold-stop", "stop", 1200, 1.0), "Hound action isolation is authoritative and cold-restorable")
	var hit := Damage.from_plan({"run_id": str(f.player.current_run_id()), "target_id": source, "hostile_source_id": "player:1", "attack_generation": 501, "action_token": 501, "source_generation": 501, "amount": 100000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": f.player, "attacker": f.player})
	suite.assert_true(owner.health.take_damage(hit) > 0.0 and owner.health.current_hp == 1.0 and driver.get("_actors").has(source), "natural dormant Hound keeps its original counted encounter token")
	var partial := hit.snapshot()
	partial.attack_generation = 502
	partial.action_token = 502
	partial.source_generation = 502
	partial.amount = 5.0
	suite.assert_close(owner.get_node("DormantSigil/Hurtbox").receive_hit(Damage.from_plan(partial)), 5.0, "production physical sigil retains partial accepted damage")
	f = await _physical_roundtrip(suite, f, "hound-partial-sigil")
	if f.is_empty():
		suite.finish(get_tree())
		return
	driver = f.runner.get_node("NativeLaunchEncounterDriver")
	owner = driver.get("_actors").get(source)
	suite.assert_true(is_instance_valid(owner) and owner.get_node_or_null("DormantSigil") != null and owner.launch_runtime_snapshot().runtime.mechanism_state.sigil_hp == 7.0, "fresh Main reconstructs authoritative partial sigil and physical weapon target")
	for _frame: int in range(31):
		suite.assert_true(f.player.advance_action_frame(), "restored Hound retains unscaled dormant counter during rewind history")
	var receipts: Array = []
	f.player.time_manager.native_ability_committed.connect(func(receipt: Dictionary): receipts.append(receipt.duplicate(true)))
	var energy_before: float = f.player.time_manager.energy
	suite.assert_true(f.player.advance_action_frame({"time_slot_2": {"edge": &"pressed"}}), "ordinary native Player Rewind input accepts during dormant Hound")
	suite.assert_true(receipts.size() == 1 and receipts[0].ability_id == "rewind" and f.player.time_manager.energy < energy_before, "real Rewind pays energy and publishes one genuine native receipt")
	suite.assert_true(owner.launch_runtime_snapshot().runtime.mechanism_state.dormancy_used and owner.launch_runtime_snapshot().runtime.mechanism_state.sigil_hp == 7.0, "gameplay Rewind cannot undo Hound once-only dormancy or accepted sigil damage")
	f.player.global_position = owner.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary") and f.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "ordinary Sword input targets physically restored Hound sigil")
	for _frame: int in range(100):
		if not driver.get("_actors").has(source):
			break
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "restored sigil accepts real Sword collision frame")
		await get_tree().physics_frame
	f.player.cancel_transient_actions()
	suite.assert_true(not driver.get("_actors").has(source) and driver.get("_encounter").snapshot().defeat_ledger.has(source), "normal Sword destroys restored sigil and settles one original Hound final death")
	await _dispose(f.main)
	suite.finish(get_tree())
