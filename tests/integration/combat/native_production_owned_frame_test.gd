extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")
const Token := preload("res://scripts/enemies/launch/native_hostile_frame_token.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var launched: bool = main._launch_run(config, false, true)
	suite.assert_true(launched, "fresh production Main accepts its actual Launch configuration")
	_freeze(main)
	if not launched or not await _admit_first_combat(main):
		await _dispose(main)
		suite.finish(get_tree())
		return
	_assert_owned_frame(main, "fresh")
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var driver := _driver(main)
	var native_before: Dictionary = driver.snapshot()
	var player_before: Dictionary = player.full_player_replay_snapshot()
	var run_before: Dictionary = host.runtime_snapshot()
	var actor_instances := {}
	for source: String in driver.get("_actors"):
		actor_instances[source] = driver.get("_actors")[source].get_instance_id()
	var checkpoint: Dictionary = main.checkpoint_current_run()
	suite.assert_true(checkpoint.ok, "fresh production combat persists through the physical Profile checkpoint: " + str(checkpoint.code))
	if not checkpoint.ok:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var service: RefCounted = GameState.profile_runtime_service()
	var payload_before: Dictionary = service.payload()
	var sequence_before: int = int(service.snapshot().launch_sequence)
	suite.assert_true(service.authenticated_native_checkpoint(int(service.snapshot().revision)).ok, "physical Profile retains an authenticated combat checkpoint")
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	_freeze(main)
	service = GameState.profile_runtime_service()
	suite.assert_true(_json(service.payload()) == _json(payload_before), "new Main reopens the exact promoted physical Profile payload")
	var restored: bool = main._launch_run(config, false, true)
	suite.assert_true(restored, "cold production Main reconstructs its saved native combat through the actual launch command")
	_freeze(main)
	if restored:
		host = main.get_node("RunRuntimeHost")
		player = main.get_node("CombatRoom01/Player")
		driver = _driver(main)
		suite.assert_equal(driver.snapshot(), native_before, "cold Main restores the complete original actors, effects and encounter clocks")
		suite.assert_equal(player.full_player_replay_snapshot(), player_before, "cold Main restores the exact original Player frame")
		suite.assert_equal(_json(host.runtime_snapshot()), _json(run_before), "cold Main restores the same route and run revision")
		suite.assert_equal(int(service.snapshot().launch_sequence), sequence_before, "cold Main cannot mint a second launch")
		for source: String in driver.get("_actors"):
			suite.assert_true(actor_instances.has(source) and driver.get("_actors")[source].get_instance_id() != actor_instances[source], "cold Main creates a new actual actor for its original source: " + source)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_assert_owned_frame(main, "cold")
	await _dispose(main)
	suite.finish(get_tree())


func _admit_first_combat(main: Node) -> bool:
	var host: Node = main.get_node("RunRuntimeHost")
	var selected := false
	for choice: Dictionary in host.route_choices():
		if choice.room_type == "combat":
			selected = host.select_route(StringName(choice.edge_id), int(host.runtime_snapshot().revision)).ok
			break
	suite.assert_true(selected, "actual production route selects its first authored combat room")
	if not selected:
		return false
	host.set_dungeon_selection_safety(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	var runner: Node = main.get_node("CombatRoom01").encounter_runner()
	var admitted := false
	for _step: int in range(120):
		if not player.advance_action_frame():
			break
		await get_tree().physics_frame
		if runner.alive_count() > 0:
			admitted = true
			break
	suite.assert_true(admitted, "actual accepted Player frames admit the production hostile roster")
	await get_tree().physics_frame
	await get_tree().physics_frame
	return admitted


func _assert_owned_frame(main: Node, label: String) -> void:
	var player: Node = main.get_node("CombatRoom01/Player")
	var driver := _driver(main)
	var bridge: RefCounted = driver.get("_bridge")
	var frame: int = int(player.priority_arbitration_snapshot().frame) + 1
	var before := var_to_bytes(driver.snapshot())
	var player_before := var_to_bytes(player.full_player_replay_snapshot())
	var threats_before := var_to_bytes(main.get_node("CombatRoom01").hostile_threat_registry().snapshot())
	var actor_checkpoints := {}
	for source: String in driver.get("_actors"):
		actor_checkpoints[source] = var_to_bytes(driver.get("_actors")[source].launch_transaction_snapshot())
	suite.assert_true(driver._boundary_ready() and bridge.is_ready_for_frame(frame), label + " production boundary is ready before transaction")
	driver.set("_flushing", true)
	suite.assert_true(not driver._boundary_ready() and not bridge.is_ready_for_frame(frame) and bridge.begin_frame(frame).is_empty() and not bridge.frame_transaction_is_active(), label + " genuine busy Driver boundary refuses both readiness and frame admission")
	driver.set("_flushing", false)
	suite.assert_equal(var_to_bytes(driver.snapshot()), before, label + " busy refusal preserves the complete production aggregate")
	var ticket: Dictionary = bridge.begin_frame(frame)
	suite.assert_true(not ticket.is_empty(), label + " production Bridge begins the exact next frame")
	if ticket.is_empty():
		return
	var prepared: bool = bridge.prepare_frame(ticket)
	suite.assert_true(prepared, label + " production Bridge prepares the complete original frame contract: " + str(bridge.frame_rejection_snapshot()))
	var records: Array = bridge.get("_active").get("records", [])
	suite.assert_equal(records.size(), actor_checkpoints.size(), label + " production transaction retains every living actual hostile")
	var native_count := 0
	var public_count := 0
	var native_only := not records.is_empty()
	var tokens: Array[RefCounted] = []
	for record: Dictionary in records:
		suite.assert_equal(var_to_bytes(record.checkpoint), actor_checkpoints.get(record.source_id), label + " original typed checkpoint precedes hostile preparation: " + str(record.source_id))
		var token: Variant = record.get("actor_token")
		var native: bool = record.get("native_actor_frame", false) and token is RefCounted and token.get_script() == Token and record.get("actor_ticket", {}).is_empty()
		native_only = native_only and native
		if native:
			native_count += 1
			tokens.append(token)
			suite.assert_true(record.actor.owns_native_launch_frame_token(token, bridge), label + " committed marker retains genuine production ownership")
			for property: Dictionary in token.get_property_list():
				suite.assert_true(property.type not in [TYPE_DICTIONARY, TYPE_ARRAY], label + " exact empty marker exposes no mutable frame payload")
		elif not record.get("actor_ticket", {}).is_empty():
			public_count += 1
	print("NATIVE_PRODUCTION_OWNED_FRAME_OBSERVATION ", JSON.stringify({"boundary": label, "records": records.size(), "native": native_count, "public": public_count}))
	suite.assert_true(native_only, label + " actual Main production Bridge retains only exact opaque native markers and no public full tickets")
	suite.assert_true(bridge.rollback_frame(ticket), label + " production compensation accepts its required pre-frame typed checkpoints")
	suite.assert_equal(var_to_bytes(driver.snapshot()), before, label + " complete production rollback is byte-exact")
	suite.assert_equal(var_to_bytes(player.full_player_replay_snapshot()), player_before, label + " manual hostile transaction preserves the actual Player boundary")
	suite.assert_equal(var_to_bytes(main.get_node("CombatRoom01").hostile_threat_registry().snapshot()), threats_before, label + " complete production rollback preserves the original threat prefix")
	for source: String in driver.get("_actors"):
		var actor: Node = driver.get("_actors")[source]
		suite.assert_equal(var_to_bytes(actor.launch_transaction_snapshot()), actor_checkpoints[source], label + " rollback restores every original typed actor checkpoint: " + source)
		suite.assert_true(actor.get("_native_launch_frame_token") == null, label + " compensation revokes every native actor marker")
	for token: RefCounted in tokens:
		for actor: Node in driver.get("_actors").values():
			suite.assert_true(not actor.owns_native_launch_frame_token(token, bridge), label + " revoked production marker cannot regain authority")
	suite.assert_true(not bridge.frame_transaction_is_active() and bridge.is_ready_for_frame(frame), label + " compensation releases the same production boundary for retry")


func _driver(main: Node) -> Node:
	return main.get_node("CombatRoom01").encounter_runner().get_node("NativeLaunchEncounterDriver")


func _freeze(main: Node) -> void:
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
