extends "res://tests/integration/save/natural_elite_encounter_checkpoint_test.gd"

const SpeciesRoute := preload("res://tests/support/native_species_route_finder.gd")
var _phase_suite: RefCounted


func _run() -> void:
	var suite := Suite.new()
	_phase_suite = suite
	var target := SpeciesRoute.find_species("phase_ranger", 3)
	suite.assert_true(not target.is_empty(), "deterministic FloorGenerator supplies authored Ranger route")
	if target.is_empty():
		suite.finish(get_tree())
		return
	var f := await _new_profile(suite, target.seed, "phase_shift")
	if not await _route_to_recipe(suite, f.host, 3, target.node_id):
		suite.assert_true(false, "actual Profile Host reaches natural Ranger route")
		await _dispose(f.main)
		suite.finish(get_tree())
		return
	f.host.set_dungeon_selection_safety(false)
	f.player.health.acquire_invulnerability_source(&"phase-native-save")
	var driver: Node = f.runner.get_node("NativeLaunchEncounterDriver")
	var owner: Node2D
	for _frame: int in range(600):
		for actor: Node2D in driver.get("_actors").values():
			if actor.get("_launch_definition").id == "phase_ranger":
				owner = actor
		if is_instance_valid(owner) and owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.phase == "DEPARTURE":
			break
		suite.assert_true(f.player.advance_action_frame(), "production Ranger route accepts actual shared native frame")
		await get_tree().physics_frame
	suite.assert_true(is_instance_valid(owner) and owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.phase == "DEPARTURE", "production Driver freezes Ranger's marked landing after its real cooldown")
	if not is_instance_valid(owner) or owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.phase != "DEPARTURE":
		await _dispose(f.main)
		suite.finish(get_tree())
		return
	var source := str(owner.hostile_source_id)
	var warning: Dictionary = owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.duplicate(true)
	f = await _physical_roundtrip(suite, f, "phase-marked-warning")
	if f.is_empty():
		suite.finish(get_tree())
		return
	driver = f.runner.get_node("NativeLaunchEncounterDriver")
	owner = driver.get("_actors").get(source)
	var restored_warning: Dictionary = owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift
	suite.assert_true(is_instance_valid(owner) and restored_warning.reservations == warning.reservations and restored_warning.remaining_frames == warning.remaining_frames - 1 and owner.get_node("PhaseArrival").visible, "fresh Main reconstructs exact sealed landing and matches uninterrupted next warning frame")
	warning = restored_warning.duplicate(true)
	for _frame: int in range(int(warning.remaining_frames)):
		suite.assert_true(f.player.advance_action_frame(), "restored Ranger completes exact remaining marked warning")
		await get_tree().physics_frame
	var landed: Dictionary = owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift
	suite.assert_true(landed.phase == "ARRIVAL" and landed.remaining_frames == 30 and landed.reservations[0].outcome == "LANDED", "physical restored Ranger relocates at the authored full-warning boundary")
	var direction := Vector2.RIGHT
	var bounds: Dictionary = owner.launch_room_motion_snapshot().bounds
	if owner.global_position.x - 42.0 < float(bounds.x) + 10.0:
		direction = Vector2.LEFT
	f.player.global_position = owner.global_position - direction * 42.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp_before: float = owner.health.current_hp
	suite.assert_true(f.player.advance_action_frame({"aim": direction}) and f.player.try_action(&"weapon_primary") and f.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "ordinary Sword input attacks physical Ranger during arrival recovery")
	for _frame: int in range(20):
		suite.assert_true(f.player.advance_action_frame({"aim": direction}), "restored arrival accepts actual Sword producer collision frame")
		await get_tree().physics_frame
	f.player.cancel_transient_actions()
	suite.assert_true(owner.health.current_hp < hp_before and not owner.health.dead, "Ranger remains physically vulnerable to normal Sword during recovery")
	for _frame: int in range(31):
		suite.assert_true(f.player.advance_action_frame(), "native restored Ranger accumulates genuine Rewind history")
	var receipt_before: Dictionary = owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.reservations[0].duplicate(true)
	var receipts: Array = []
	f.player.time_manager.native_ability_committed.connect(func(receipt: Dictionary): receipts.append(receipt.duplicate(true)))
	var energy_before: float = f.player.time_manager.energy
	suite.assert_true(f.player.advance_action_frame({"time_slot_2": {"edge": &"pressed"}}), "ordinary paid Rewind input accepts after restored Ranger arrival")
	suite.assert_true(receipts.size() == 1 and receipts[0].ability_id == "rewind" and f.player.time_manager.energy < energy_before, "real Rewind publishes one native receipt with spent energy")
	suite.assert_equal(owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.reservations[0], receipt_before, "gameplay Rewind cannot erase accepted native Ranger landing history")
	f.player.cancel_transient_actions()
	var historical: Dictionary = driver.cold_snapshot()
	historical.actors[source].actor.runtime.schema_version = 1
	historical.actors[source].actor.runtime.mechanism_state.erase("phase_shift")
	suite.assert_true(driver.discard_cold_restore() and driver.restore_cold_snapshot(historical), "production Driver reconstructs exact historical schema-one Ranger alongside native aggregate state")
	owner = driver.get("_actors").get(source)
	if is_instance_valid(owner):
		suite.assert_true(driver.matches_cold_snapshot(historical) and not owner.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.enabled and not owner.get_node("PhaseArrival").visible, "aggregate historical normalization retains exact prior continuation without a new shift")
		suite.assert_true(f.player.advance_action_frame(), "historical reconstructed native aggregate accepts ordinary next Player frame")
	await _dispose(f.main)
	suite.finish(get_tree())


func _dispose(main: Node) -> void:
	var playback_refs: Array[WeakRef] = []
	var director: Node = main.get_node_or_null("MusicDirector")
	if director != null:
		for deck: Node in director.get_children():
			if deck is AudioStreamPlayer and deck.has_stream_playback():
				playback_refs.append(weakref(deck.get_stream_playback()))
	await super._dispose(main)
	# Stopped WAV playback retires on AudioServer's independent mix thread.
	for _step: int in range(20):
		if playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null):
			break
		await get_tree().create_timer(0.01).timeout
	_phase_suite.assert_true(playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "physical Main teardown releases actual music playback before process exit")
