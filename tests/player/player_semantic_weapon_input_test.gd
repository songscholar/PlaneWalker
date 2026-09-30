extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _commits: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.weapon_action_committed.connect(_on_weapon_action_committed)
	await _test_semantic_slots_reach_the_equipped_runtime()
	await _test_semantic_time_slots_follow_loadout_order()
	await _test_physical_legacy_and_semantic_aliases_deduplicate()
	await _test_bow_primary_aliases_release_only_on_the_last_edge()
	await _test_rejected_toggle_press_does_not_poison_the_next_attempt()
	await _test_weapon_aim_priority_and_fallback_match_submission_context()
	await _test_bow_candidate_respects_milestone_boundaries()
	await _test_candidate_bow_rejects_launch_only_slots_atomically()
	if EventBus.weapon_action_committed.is_connected(_on_weapon_action_committed):
		EventBus.weapon_action_committed.disconnect(_on_weapon_action_committed)
	_suite.finish(get_tree())


func _test_semantic_slots_reach_the_equipped_runtime() -> void:
	_commits.clear()
	var player := await _spawn_player()
	_suite.assert_true(player.try_action(&"weapon_primary"), "semantic primary reaches the equipped Sword runtime")
	_suite.assert_equal(_commits.size(), 1, "semantic primary publishes one commit")
	_suite.assert_equal(_commits[0].get("action_id"), "light_1", "semantic primary selects the first light action")
	_suite.assert_equal(
		int((_commits[0].get("context", {}) as Dictionary).get("run_seed", -1)),
		20260929,
		"committed action context carries the accepted run seed"
	)
	player.cancel_transient_actions()

	_suite.assert_true(player.try_action(&"weapon_secondary"), "semantic secondary reaches the equipped Sword runtime")
	_suite.assert_equal(_commits.size(), 2, "semantic secondary publishes one additional commit")
	_suite.assert_equal(_commits[1].get("action_id"), "heavy", "semantic secondary selects Sword heavy")
	player.cancel_transient_actions()

	for unsupported: StringName in [&"weapon_utility", &"weapon_skill", &"weapon_ultimate"]:
		var before: Dictionary = player.weapon_action_coordinator.snapshot()
		_suite.assert_true(not player.try_action(unsupported), "%s fails closed for M1 Sword" % unsupported)
		_suite.assert_equal(
			player.weapon_action_coordinator.snapshot(),
			before,
			"unsupported semantic slot is atomic: %s" % unsupported
		)
	await _free_player(player)


func _test_physical_legacy_and_semantic_aliases_deduplicate() -> void:
	_commits.clear()
	var player := await _spawn_player()
	Input.action_press("weapon_primary")
	Input.action_press("attack")
	player.call("_handle_priority_action_input")
	_suite.assert_equal(_commits.size(), 1, "overlapping semantic and legacy primary bindings commit once")
	_suite.assert_equal(_commits[0].get("action_id"), "light_1", "deduplicated physical edge keeps semantic identity")
	Input.action_release("weapon_primary")
	Input.action_release("attack")
	player.cancel_transient_actions()
	await _free_player(player)


func _test_semantic_time_slots_follow_loadout_order() -> void:
	var player := await _spawn_player()
	var time_manager: Node = player.get_node("TimeManager")
	time_manager.time_stop_duration = 0.01
	var energy_before: float = time_manager.energy
	Input.action_press("time_slot_1")
	Input.action_press("time_stop")
	player.call("_handle_priority_action_input")
	Input.action_release("time_slot_1")
	Input.action_release("time_stop")
	_suite.assert_close(
		energy_before - time_manager.energy,
		time_manager.time_stop_cost,
		"semantic slot and matching legacy alias resolve to one equipped Stop commit"
	)
	player.cancel_transient_actions()

	var recorder: Node = player.get_node("RewindRecorder")
	player.global_position = Vector2(32.0, 48.0)
	recorder.call("_record_snapshot")
	player.global_position = Vector2(240.0, 160.0)
	_suite.assert_true(player.try_action(&"time_slot_2"), "time slot two commits the second equipped ability")
	_suite.assert_equal(player.global_position, Vector2(32.0, 48.0), "time slot two resolves to equipped Rewind")
	await get_tree().create_timer(0.55).timeout
	await _free_player(player)


func _test_bow_primary_aliases_release_only_on_the_last_edge() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("bow_candidate_v1"),
	}), "multi-alias Bow fixture configures")
	Input.action_press("weapon_primary")
	Input.action_press("ranged_attack")
	player.call("_handle_priority_action_input")
	await get_tree().process_frame
	for _frame: int in range(9):
		player.advance_action_frame()
	Input.action_release("weapon_primary")
	player.call("_handle_priority_action_input")
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("phase"),
		"HOLD",
		"releasing one of two held aliases preserves Bow HOLD"
	)
	await get_tree().process_frame
	Input.action_release("ranged_attack")
	player.call("_handle_priority_action_input")
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("phase"),
		"WINDUP",
		"releasing the final held alias resolves Bow HOLD"
	)
	player.cancel_transient_actions()
	await _free_player(player)


func _test_rejected_toggle_press_does_not_poison_the_next_attempt() -> void:
	var previous_persistent: Dictionary = GameState.persistent.duplicate(true)
	var settings: Dictionary = GameState.normalized_settings()
	settings["ranged_charge_mode"] = "toggle"
	GameState.persistent["settings"] = settings
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("bow_candidate_v1"),
	}), "toggle rejection fixture configures Candidate Bow")
	_suite.assert_true(
		player.action_state.transition_to(PlayerActionStateScript.State.DASH, 2),
		"toggle rejection fixture enters Dash"
	)
	player.handle_ranged_input_for_test(true, false)
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("phase"),
		"READY",
		"toggle press is rejected while Dash owns the action state"
	)
	for _frame: int in range(2):
		player.advance_action_frame()
	player.handle_ranged_input_for_test(true, false)
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("phase"),
		"HOLD",
		"the first valid press after rejection starts HOLD directly"
	)
	player.cancel_transient_actions()
	GameState.persistent = previous_persistent.duplicate(true)
	await _free_player(player)


func _test_weapon_aim_priority_and_fallback_match_submission_context() -> void:
	var player := await _spawn_player()
	player.restore_rewind_facing(Vector2.LEFT)

	var right_stick: Vector2 = player.call(
		"_resolve_weapon_aim_direction",
		Vector2.UP,
		Vector2.RIGHT
	)
	_suite.assert_equal(right_stick, Vector2.UP, "right-stick aim has priority over mouse direction")
	player.call("_apply_weapon_aim_direction", right_stick)
	_assert_all_weapon_aims(player, Vector2.UP, "right-stick")
	_assert_vector_close(
		player.call("_weapon_submission_context").get("aim_direction"),
		Vector2.UP,
		"right-stick visual aim and committed context"
	)

	var mouse: Vector2 = player.call(
		"_resolve_weapon_aim_direction",
		Vector2(0.1, 0.0),
		Vector2.DOWN
	)
	_suite.assert_equal(mouse, Vector2.DOWN, "mouse aim remains compatible below the stick deadzone")
	player.call("_apply_weapon_aim_direction", mouse)
	_assert_all_weapon_aims(player, Vector2.DOWN, "mouse")
	_assert_vector_close(
		player.call("_weapon_submission_context").get("aim_direction"),
		Vector2.DOWN,
		"mouse visual aim and committed context"
	)

	var fallback: Vector2 = player.call(
		"_resolve_weapon_aim_direction",
		Vector2.ZERO,
		Vector2.ZERO
	)
	_suite.assert_equal(fallback, Vector2.LEFT, "missing stick and mouse input falls back to recent movement facing")
	player.call("_apply_weapon_aim_direction", fallback)
	_assert_all_weapon_aims(player, Vector2.LEFT, "movement fallback")
	_assert_vector_close(
		player.call("_weapon_submission_context").get("aim_direction"),
		Vector2.LEFT,
		"fallback visual aim and committed context"
	)
	await _free_player(player)


func _assert_all_weapon_aims(player: Node, expected: Vector2, label: String) -> void:
	for node_name: String in ["SwordWeapon", "BowWeapon", "GauntletsWeapon", "GunWeapon", "StaffWeapon"]:
		var weapon: Node2D = player.get_node(node_name)
		var actual := Vector2.RIGHT.rotated(weapon.rotation)
		_suite.assert_close(actual.x, expected.x, "%s %s aim x matches" % [label, node_name])
		_suite.assert_close(actual.y, expected.y, "%s %s aim y matches" % [label, node_name])


func _assert_vector_close(actual_value: Variant, expected: Vector2, label: String) -> void:
	var actual: Vector2 = actual_value as Vector2
	_suite.assert_close(actual.x, expected.x, "%s x agrees" % label)
	_suite.assert_close(actual.y, expected.y, "%s y agrees" % label)


func _test_bow_candidate_respects_milestone_boundaries() -> void:
	var player := await _spawn_player()
	var before: Dictionary = player.weapon_presentation_snapshot()
	var m1_bow := {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}
	_suite.assert_true(not player.configure_loadout(m1_bow), "M1 rejects implicit Candidate Bow profile selection")
	var explicit_m1_bow: Dictionary = m1_bow.duplicate(true)
	explicit_m1_bow["weapon_profile"] = _profile_definition("bow_candidate_v1")
	_suite.assert_true(not player.configure_loadout(explicit_m1_bow), "M1 rejects explicit Candidate Bow profile selection")
	var forged_m1_bow: Dictionary = m1_bow.duplicate(true)
	var forged_profile := _profile_definition("bow_candidate_v1")
	forged_profile["availability"] = ["M1"]
	forged_m1_bow["weapon_profile"] = forged_profile
	_suite.assert_true(
		not player.configure_loadout(forged_m1_bow),
		"M1 rejects a Candidate Bow profile with forged availability"
	)
	_suite.assert_equal(
		player.weapon_presentation_snapshot(),
		before,
		"rejected Candidate Bow configurations preserve the accepted M1 runtime atomically"
	)
	var next_bow: Dictionary = m1_bow.duplicate(true)
	next_bow["milestone"] = "NEXT"
	_suite.assert_true(player.configure_loadout(next_bow), "NEXT accepts the Candidate Bow compatibility profile")
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("profile_id"),
		"bow_candidate_v1",
		"NEXT implicit profile selection resolves to the certified Candidate"
	)
	await _free_player(player)


func _test_candidate_bow_rejects_launch_only_slots_atomically() -> void:
	_commits.clear()
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("bow_candidate_v1"),
	}), "candidate Bow semantic fixture configures")
	for unsupported: StringName in [
		&"weapon_secondary",
		&"weapon_utility",
		&"weapon_skill",
		&"weapon_ultimate",
	]:
		var before: Dictionary = player.weapon_action_coordinator.snapshot()
		_suite.assert_true(not player.try_action(unsupported), "%s remains Launch-only for Candidate Bow" % unsupported)
		_suite.assert_equal(
			player.weapon_action_coordinator.snapshot(),
			before,
			"Candidate Bow rejection is atomic: %s" % unsupported
		)
	_suite.assert_equal(_commits.size(), 0, "unsupported Candidate Bow slots publish no commits")
	await _free_player(player)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	_suite.assert_true(player.configure_loadout({
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}), "semantic input fixture configures M1 Sword")
	return player


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame


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


func _on_weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	_commits.append({
		"weapon_id": str(weapon_id),
		"action_id": str(action_id),
		"token": token,
		"context": context.duplicate(true),
	})
