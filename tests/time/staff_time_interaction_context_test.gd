extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_stop_generation_supports_real_staff_plans()
	await _test_accelerate_generation_supports_real_staff_plans()
	await _test_rift_generation_tracks_the_live_source()
	_suite.finish(get_tree())


func _test_stop_generation_supports_real_staff_plans() -> void:
	var player := await _spawn_staff(["stop", "rewind"])
	if player == null:
		return
	var manager: Node = player.get_node("TimeManager")
	var runtime: RefCounted = player.weapon_runtime
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 0.0
	manager.time_stop_duration = 0.05

	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player activates Stop")
	var active := _weapon_context(player)
	var first_generation := int(active.get("stop_generation", 0))
	_suite.assert_true(bool(active.get("stop_active", false)), "active Stop is exposed to Staff")
	_suite.assert_true(first_generation > 0, "active Stop exposes a positive source generation")

	var ordinary: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _submission_context(player))
	_suite.assert_true(bool(ordinary.get("ok", false)), "active Stop does not reject an unrelated Staff primary hold")
	var planned: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _submission_context(player))
	_suite.assert_true(bool(planned.get("ok", false)), "active Stop plans the corresponding Staff skill")
	var plan: Dictionary = planned.get("plan", {})
	var descriptor := _descriptor(plan, "staff_stop_field")
	_suite.assert_equal(int(descriptor.get("source_generation", 0)), first_generation, "Stop descriptor freezes the live generation")
	_suite.assert_true(bool(runtime.commit_action(plan, 8101).get("ok", false)), "active Stop Staff skill commits")
	runtime.cancel_action(8101, &"generation_test")

	manager.call("_tick_active_effects", 0.06)
	var expired := _weapon_context(player)
	_suite.assert_true(not bool(expired.get("stop_active", true)), "expired Stop is inactive")
	_suite.assert_equal(int(expired.get("stop_generation", -1)), 0, "expired Stop exposes no live generation")
	var expired_ordinary: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _submission_context(player))
	_suite.assert_true(bool(expired_ordinary.get("ok", false)), "expired Stop cannot poison an ordinary Staff intent")

	_advance_time_cast(player)
	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player reactivates Stop")
	var reactivated := _weapon_context(player)
	_suite.assert_true(int(reactivated.get("stop_generation", 0)) > first_generation, "reactivated Stop advances its generation monotonically")
	await _free_player(player)


func _test_accelerate_generation_supports_real_staff_plans() -> void:
	var player := await _spawn_staff(["accelerate", "rewind"])
	if player == null:
		return
	var manager: Node = player.get_node("TimeManager")
	var runtime: RefCounted = player.weapon_runtime
	manager.time_accelerate_cost = 0.0
	manager.time_accelerate_cooldown = 0.0
	manager.time_accelerate_duration = 0.05

	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player activates Accelerate")
	var active := _weapon_context(player)
	var first_generation := int(active.get("accelerate_generation", 0))
	_suite.assert_true(bool(active.get("accelerate_active", false)), "active Accelerate is exposed to Staff")
	_suite.assert_true(first_generation > 0, "active Accelerate exposes a positive source generation")

	var planned: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _submission_context(player))
	_suite.assert_true(bool(planned.get("ok", false)), "active Accelerate plans the corresponding Staff primary hold")
	var plan: Dictionary = planned.get("plan", {})
	var descriptor := _descriptor(plan, "staff_fast_charge")
	_suite.assert_equal(int(descriptor.get("source_generation", 0)), first_generation, "Accelerate descriptor freezes the live generation")
	_suite.assert_true(bool(runtime.commit_action(plan, 8201).get("ok", false)), "active Accelerate Staff hold commits")
	runtime.cancel_action(8201, &"generation_test")

	manager.call("_tick_active_effects", 0.06)
	var expired := _weapon_context(player)
	_suite.assert_true(not bool(expired.get("accelerate_active", true)), "expired Accelerate is inactive")
	_suite.assert_equal(int(expired.get("accelerate_generation", -1)), 0, "expired Accelerate exposes no live generation")
	var ordinary: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), _submission_context(player))
	_suite.assert_true(bool(ordinary.get("ok", false)), "expired Accelerate cannot poison an unrelated Staff utility intent")

	_advance_time_cast(player)
	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player reactivates Accelerate")
	var reactivated := _weapon_context(player)
	_suite.assert_true(int(reactivated.get("accelerate_generation", 0)) > first_generation, "reactivated Accelerate advances its generation monotonically")
	await _free_player(player)


func _test_rift_generation_tracks_the_live_source() -> void:
	var player := await _spawn_staff(["rift", "rewind"])
	if player == null:
		return
	var manager: Node = player.get_node("TimeManager")
	var runtime: RefCounted = player.weapon_runtime
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	manager.time_rift_duration = 30.0
	player.global_position = Vector2(64.0, 32.0)

	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player activates Rift")
	var first_context := _weapon_context(player)
	var first_generation := int(first_context.get("rift_generation", 0))
	_suite.assert_true(bool(first_context.get("rift_active", false)), "active Rift is exposed to Staff")
	_suite.assert_true(first_generation > 0, "active Rift exposes a positive source generation")
	var first_descriptors: Array = first_context.get("active_rifts", [])
	_suite.assert_equal(first_descriptors.size(), 1, "one live Rift exposes one spatial descriptor")
	if first_descriptors.size() == 1:
		var first_descriptor := first_descriptors[0] as Dictionary
		_suite.assert_equal(int(first_descriptor.get("generation", 0)), first_generation, "Rift descriptor identity matches rift_generation")
		_suite.assert_equal(first_descriptor.get("center"), Vector2(64.0, 32.0), "Rift descriptor exposes the committed world center")
		_suite.assert_close(float(first_descriptor.get("radius", 0.0)), manager.time_rift_radius, "Rift descriptor exposes the committed radius")
	var first_rift: Node = _active_rifts(manager)[0]

	var ordinary: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _submission_context(player))
	_suite.assert_true(bool(ordinary.get("ok", false)), "active Rift does not reject an unrelated Staff primary hold")
	_commit_confirmed_element(runtime, &"fire", 8301, _submission_context(player))
	_cycle_to_ice(runtime, 8302, _submission_context(player))
	var planned: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _submission_context(player))
	_suite.assert_true(bool(planned.get("ok", false)), "active Rift plans the corresponding Staff combination")
	var plan: Dictionary = planned.get("plan", {})
	var descriptor := _descriptor(plan, "staff_rift_combination")
	_suite.assert_equal(int(descriptor.get("source_generation", 0)), first_generation, "Rift descriptor freezes the live generation")
	_suite.assert_true(bool(runtime.commit_action(plan, 8303).get("ok", false)), "active Rift Staff combination commits")
	runtime.cancel_action(8303, &"generation_test")

	_advance_time_cast(player)
	player.global_position = Vector2(192.0, 96.0)
	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player creates an overlapping Rift")
	var second_context := _weapon_context(player)
	var second_generation := int(second_context.get("rift_generation", 0))
	_suite.assert_true(second_generation > first_generation, "newest live Rift advances the generation monotonically")
	var overlapping_descriptors: Array = second_context.get("active_rifts", [])
	_suite.assert_equal(overlapping_descriptors.size(), 2, "overlapping Rifts expose both spatial descriptors")
	if overlapping_descriptors.size() == 2:
		_suite.assert_equal(int((overlapping_descriptors[0] as Dictionary).get("generation", 0)), first_generation, "Rift descriptors sort by stable generation")
		_suite.assert_equal(int((overlapping_descriptors[1] as Dictionary).get("generation", 0)), second_generation, "newest Rift descriptor sorts last")
		_suite.assert_equal((overlapping_descriptors[1] as Dictionary).get("center"), Vector2(192.0, 96.0), "newest Rift descriptor preserves its own center")
	var rifts := _active_rifts(manager)
	var second_rift: Node = rifts[rifts.size() - 1]
	second_rift.call("cancel", false)
	var fallback := _weapon_context(player)
	_suite.assert_true(bool(fallback.get("rift_active", false)), "ending the newest Rift preserves an older live Rift")
	_suite.assert_equal(int(fallback.get("rift_generation", 0)), first_generation, "Rift context falls back to the generation of the remaining live source")
	var fallback_descriptors: Array = fallback.get("active_rifts", [])
	_suite.assert_equal(fallback_descriptors.size(), 1, "ending the newest Rift removes only its descriptor")
	if fallback_descriptors.size() == 1:
		_suite.assert_equal(int((fallback_descriptors[0] as Dictionary).get("generation", 0)), first_generation, "remaining descriptor keeps the older live generation")

	_advance_frames(player, 1801)
	var expired := _weapon_context(player)
	_suite.assert_true(not bool(expired.get("rift_active", true)), "ending every Rift clears the active context")
	_suite.assert_equal(int(expired.get("rift_generation", -1)), 0, "no live Rift exposes no source generation")
	_suite.assert_equal((expired.get("active_rifts", []) as Array).size(), 0, "expired Rift removes its spatial descriptor")
	var expired_ordinary: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), _submission_context(player))
	_suite.assert_true(bool(expired_ordinary.get("ok", false)), "expired Rift cannot poison an unrelated Staff intent")

	_advance_time_cast(player)
	_suite.assert_true(player.try_action(&"time_slot_1"), "real Player reactivates Rift after expiry")
	var reactivated := _weapon_context(player)
	_suite.assert_true(int(reactivated.get("rift_generation", 0)) > second_generation, "reactivated Rift advances beyond every prior activation")
	manager.reset_runtime_state()
	var reset_context := _weapon_context(player)
	_suite.assert_true(not bool(reset_context.get("rift_active", true)), "runtime reset clears the active Rift context")
	_suite.assert_equal(int(reset_context.get("rift_generation", -1)), 0, "runtime reset clears the live Rift generation")
	_suite.assert_equal((reset_context.get("active_rifts", []) as Array).size(), 0, "runtime reset clears every Rift descriptor")
	await _free_player(player)


func _commit_confirmed_element(runtime: RefCounted, element: StringName, token: int, context: Dictionary) -> void:
	var current := StringName(str(runtime.snapshot().get("current_element", "")))
	_suite.assert_equal(current, element, "Staff combo fixture starts on the expected element")
	var plan: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), context).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "Staff combo fixture commits its first element")
	_suite.assert_true(
		bool(runtime.payload_result(token, token, &"rift_generation_first", element, token, true, 0.0, true).get("ok", false)),
		"Staff combo fixture confirms its first element hit"
	)
	runtime.finish_action(token)


func _cycle_to_ice(runtime: RefCounted, token: int, context: Dictionary) -> void:
	var plan: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), context).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "Staff combo fixture cycles to Ice")
	runtime.finish_action(token)
	_suite.assert_equal(runtime.snapshot().get("current_element"), "ice", "Staff combo fixture selected Ice")


func _spawn_staff(time_abilities: Array) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured: bool = player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "staff",
		"enabled_time_skills": time_abilities.duplicate(true),
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("staff_launch_v1"),
	})
	_suite.assert_true(configured, "Staff time-context fixture configures")
	if not configured:
		player.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		return null
	_suite.assert_true(
		player.advance_action_frame(),
		"Staff time-context fixture binds the character runtime frame"
	)
	return player


func _profile_definition(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/content_packs/base/content/weapon_runtime_profiles.json")
	)
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == profile_id:
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _weapon_context(player: Node) -> Dictionary:
	return player.call("weapon_time_interaction_context")


func _submission_context(player: Node) -> Dictionary:
	return player.call("_weapon_submission_context")


func _active_rifts(manager: Node) -> Array:
	var value: Variant = manager.get("_active_rifts")
	return value as Array if value is Array else []


func _descriptor(plan: Dictionary, interaction_id: String) -> Dictionary:
	for value: Variant in plan.get("time_interactions", []):
		if value is Dictionary and str((value as Dictionary).get("interaction_id", "")) == interaction_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _press_intent(action_id: StringName) -> Dictionary:
	return {"id": action_id, "edge": &"pressed", "held_frames": 0}


func _release_intent(action_id: StringName, held_frames: int) -> Dictionary:
	return {"id": action_id, "edge": &"released", "held_frames": held_frames}


func _advance_time_cast(player: Node) -> void:
	for _frame: int in range(12):
		player.advance_action_frame()


func _advance_frames(player: Node, frame_count: int) -> void:
	for _frame: int in range(maxi(0, frame_count)):
		player.advance_action_frame()


func _free_player(player: Node) -> void:
	if is_instance_valid(player):
		player.cancel_transient_actions()
		player.cancel_active_time_effects(&"test_cleanup")
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
