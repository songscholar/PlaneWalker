extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Checkpoint := preload("res://scripts/save/native_run_checkpoint_authority.gd")
const Phase := preload("res://scripts/application/run_phase.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	for case_name: String in ["entrance", "reward", "defeat", "payload", "drift"]:
		await _exercise(suite, case_name)
	suite.finish(get_tree())


func _exercise(suite: RefCounted, case_name: String) -> void:
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	suite.assert_true(host.has_method("checkpoint_profile_run"), "native Host exposes an authenticated full checkpoint entry point")
	suite.assert_true(host.has_method("restore_profile_checkpoint"), "native Host cold-restores a physical Profile without preparing another launch")
	if not host.has_method("checkpoint_profile_run") or not host.has_method("restore_profile_checkpoint"):
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		return
	host.set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var catalog: RefCounted = Factory.load_base().context.catalog
	var save := Save.new()
	var service := Service.new()
	suite.assert_true(save.configure(Paths.resolve_default("user://p16q-checkpoint", "p16q-checkpoint"), "0.4.0-dev", Content.snapshot(host.content_registry())).ok, "checkpoint test uses actual Base content and physical SaveService")
	var slot := "checkpoint_" + case_name
	suite.assert_true(service.configure(catalog, save, slot, "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "physical checkpoint Profile configures")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "time_guardian", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	if case_name == "payload":
		config.enabled_time_skills = ["rewind", "rift"]
	suite.assert_true(host.start_profile_run(config, service, int(service.snapshot().revision)).ok, "actual production Host prepares one authenticated launch")
	if case_name in ["reward", "defeat"]:
		var routes: Array = host.route_choices()
		var edge := ""
		for route: Dictionary in routes:
			if route.get("room_type") in ["combat", "elite", "boss"]:
				edge = str(route.edge_id)
				break
		suite.assert_true(not edge.is_empty() and host.select_route(StringName(edge), int(host.runtime_snapshot().revision)).ok, "native scene route enters a combat encounter")
		var unsafe_before: Dictionary = service.payload()
		var refused = host.checkpoint_profile_run(int(service.snapshot().revision))
		suite.assert_true(not refused.ok and refused.code == &"CHECKPOINT_UNSAFE" and service.payload() == unsafe_before, "unsupported live encounter checkpoint preserves physical Profile")
		var room: Node = host.native_checkpoint_participants().runtime
		if case_name == "reward":
			suite.assert_true(room.complete_current_room().ok and int(host.runtime_snapshot().phase) == Phase.Value.SELECTION_ACTIVE, "real room completion retains a native pending reward")
		else:
			suite.assert_true(room.report_player_died("checkpoint_fixture").ok and int(host.runtime_snapshot().phase) == Phase.Value.DEFEAT, "native room runtime produces terminal defeat")
	player.position = Vector2(153, 123)
	if case_name == "payload":
		suite.assert_true(player.time_manager.try_time_rift(Vector2(280, 160)), "physical checkpoint includes a real native persistent rift")
	var captured := Checkpoint.capture(host)
	if captured.ok:
		var unsafe := _unsafe_json_paths(captured.context.checkpoint, "checkpoint")
		suite.assert_true(unsafe.is_empty(), "checkpoint extension contains only JSON values: " + str(unsafe))
		var tampered: Dictionary = captured.context.checkpoint.duplicate(true)
		tampered.digest = "invalid"
		suite.assert_true(not Checkpoint.validate(tampered, captured.context.run, captured.context.reward).ok, "changed checkpoint digest fails before native reconstruction")
		if not tampered.scene_binding.is_empty():
			tampered.scene_binding.binding.room_seed += 1
			tampered.erase("digest")
			tampered["digest"] = Checkpoint.canonical(tampered).sha256_text()
			suite.assert_true(not Checkpoint.validate(tampered, captured.context.run, captured.context.reward).ok, "re-signed scene seed cannot bypass canonical Run binding")
	if case_name == "reward":
		var fault_before: Dictionary = service.payload()
		save.set_fault_injector(func(point: StringName) -> bool: return point == &"before_primary_promote")
		var fault = host.checkpoint_profile_run(int(service.snapshot().revision))
		suite.assert_true(not fault.ok and service.payload() == fault_before, "failed physical checkpoint preserves Profile before promotion")
		save.set_fault_injector(Callable())
	var retained = host.checkpoint_profile_run(int(service.snapshot().revision))
	suite.assert_true(retained.ok, "safe native entrance persists full Replay and room participants: " + str(retained.code) + " " + str(retained.context))
	if not retained.ok:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		return
	var run_before: Dictionary = host.runtime_snapshot()
	var replay_before: Dictionary = player.full_player_replay_snapshot()
	var payload_id := ""
	var payload_instance_before := 0
	if case_name == "payload":
		payload_id = str(replay_before.world_payload_state.descriptors[0].payload_id)
		payload_instance_before = player.world_payload_authority.payload_node(StringName(payload_id)).get_instance_id()
	var profile_before: Dictionary = service.snapshot()
	var host_id := host.get_instance_id()
	var player_id := player.get_instance_id()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	host = main.get_node("RunRuntimeHost")
	player = main.get_node("CombatRoom01/Player")
	host.set_process(false)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var reopened := Service.new()
	suite.assert_true(reopened.configure(catalog, save, slot, "base").ok, "a new Profile service reopens the promoted physical primary")
	if case_name == "entrance":
		var original_payload: Dictionary = reopened.payload()
		var changed_payload: Dictionary = original_payload.duplicate(true)
		changed_payload["checkpoint_probe"] = true
		suite.assert_true(save.save_profile(slot, "base", changed_payload).ok, "fixture writes a distinct physical primary")
		var untouched: Dictionary = player.full_player_replay_snapshot()
		var stale = host.restore_profile_checkpoint(reopened, int(reopened.snapshot().revision))
		suite.assert_true(not stale.ok and stale.code == &"STALE_DURABLE_PROFILE" and player.full_player_replay_snapshot() == untouched, "stale in-memory Profile cannot reconstruct over a different physical primary")
		changed_payload = original_payload.duplicate(true)
		changed_payload.native_run_checkpoint.digest = "invalid"
		suite.assert_true(save.save_profile(slot, "base", changed_payload).ok, "fixture writes a physical checkpoint with invalid inner authentication")
		var invalid_profile := Service.new()
		suite.assert_true(invalid_profile.configure(catalog, save, slot, "base").ok, "malformed inner checkpoint does not damage valid Profile")
		var rejected = host.restore_profile_checkpoint(invalid_profile, int(invalid_profile.snapshot().revision))
		suite.assert_true(not rejected.ok and rejected.code == &"NATIVE_CHECKPOINT_INVALID" and player.full_player_replay_snapshot() == untouched, "physical checkpoint tampering is refused before native mutation")
		suite.assert_true(save.save_profile(slot, "base", original_payload).ok, "valid physical preimage is recoverable")
	if case_name == "reward":
		var scene_host: Node = host.native_checkpoint_participants().scene_host
		var native_before: Dictionary = player.full_player_replay_snapshot()
		var world_before: Node = player.world_payload_authority
		var scene_before: Dictionary = scene_host.active_snapshot()
		scene_host.configure_activation_adapter(func(room: Node, preparing: bool) -> Dictionary: return room.prepare_activation() if preparing else {"ok": false, "code": &"ROOM_SCENE_ACTIVATION_FAILED"})
		var failed = host.restore_profile_checkpoint(reopened, int(reopened.snapshot().revision))
		suite.assert_true(not failed.ok and failed.code != &"INTEGRITY_FAILURE", "scene activation rejection compensates checkpoint restore: " + str(failed.context))
		suite.assert_true(player.full_player_replay_snapshot() == native_before and player.world_payload_authority == world_before, "failed cold restore preserves exact native Player and World preimages: " + str(_changed_paths(native_before, player.full_player_replay_snapshot())))
		suite.assert_equal(scene_host.active_snapshot(), scene_before, "failed cold restore preserves scene identity and generation")
		suite.assert_equal(reopened.snapshot(), profile_before, "failed cold restore cannot revise durable Profile")
		scene_host.clear_test_adapters()
	if case_name == "drift":
		host.profile_run_restored.connect(func(_id: String, _state: Dictionary) -> void: player.position += Vector2.ONE)
	var restored = host.restore_profile_checkpoint(reopened, int(reopened.snapshot().revision))
	if case_name == "drift":
		suite.assert_true(not restored.ok and restored.code == &"NATIVE_PUBLICATION_PENDING", "native presentation callback drift cannot report a clean restoration")
		suite.assert_true(player.process_mode == Node.PROCESS_MODE_DISABLED and host.native_checkpoint_participants().controller.process_mode == Node.PROCESS_MODE_DISABLED, "callback drift freezes both native combat participants")
		suite.assert_equal(reopened.snapshot(), profile_before, "callback drift preserves authenticated durable checkpoint")
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		return
	suite.assert_true(restored.ok, "new native Host cold-restores the same launch: " + str(restored.context))
	suite.assert_true(host.get_instance_id() != host_id and player.get_instance_id() != player_id, "restoration rebuilds actual native participants after scene destruction")
	suite.assert_true(_json_equal(host.runtime_snapshot(), run_before), "cold restore preserves canonical Run, floor entrances and frozen projection")
	suite.assert_true(player.full_player_replay_snapshot() == replay_before, "cold restore preserves full native Player Replay including Vector2")
	suite.assert_equal(reopened.snapshot(), profile_before, "restore cannot mint a launch, revise the Profile or settle twice")
	if restored.ok and case_name == "payload":
		var world: Node = player.world_payload_authority
		var rebuilt: Node = world.payload_node(StringName(payload_id))
		suite.assert_true(rebuilt != null and rebuilt.get_instance_id() != payload_instance_before, "persistent World rebuilds the actual rift native node")
		var remaining := int(world.payload_descriptor(StringName(payload_id)).remaining_frames)
		var frame := int(world.replay_snapshot().last_runtime_frame)
		for offset: int in remaining:
			suite.assert_true(world.advance_frame(frame + offset + 1).ok, "cold-restored World continues deterministic payload clock")
		suite.assert_true(world.payload_descriptor(StringName(payload_id)).is_empty() and world.payload_node(StringName(payload_id)) == null, "cold-restored rift expires through the native World lifecycle")
	if restored.ok and case_name == "reward":
		var offer: Dictionary = host.runtime_snapshot().open_offer
		suite.assert_true(not offer.is_empty() and Checkpoint.json_equal(offer, run_before.open_offer), "cold restore keeps exact pending reward identity and options")
		host.call("_on_option_chosen", str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
		var consumed: Dictionary = host.runtime_snapshot()
		suite.assert_true(consumed.open_offer.is_empty(), "restored pending reward consumes through native Host once")
		host.call("_on_option_chosen", str(offer.offer_id), str(offer.options[0].option_id), int(offer.get("revision", run_before.revision)))
		suite.assert_true(host.runtime_snapshot() == consumed, "repeated restored reward cannot grant a duplicate effect")
		suite.assert_true(not host.route_choices().is_empty(), "restored reward continues the canonical floor route")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))


func _unsafe_json_paths(value: Variant, path: String) -> Array[String]:
	var result: Array[String] = []
	if value is Dictionary:
		for key: Variant in value:
			if typeof(key) != TYPE_STRING:
				result.append(path + ".key:" + type_string(typeof(key)))
			result.append_array(_unsafe_json_paths(value[key], path + "." + str(key)))
	elif value is Array:
		for index: int in value.size():
			result.append_array(_unsafe_json_paths(value[index], path + "[%d]" % index))
	elif typeof(value) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		result.append(path + ":" + type_string(typeof(value)))
	return result


func _changed_paths(left: Dictionary, right: Dictionary, path: String = "") -> Array[String]:
	var result: Array[String] = []
	for key: Variant in left:
		if left[key] is Dictionary and right.get(key) is Dictionary:
			result.append_array(_changed_paths(left[key], right[key], path + "." + str(key)))
		elif left[key] != right.get(key):
			result.append(path + "." + str(key))
	return result
