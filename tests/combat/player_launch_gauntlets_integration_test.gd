extends Node

const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _hit_facts: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.weapon_hit_confirmed.connect(_on_weapon_hit_confirmed)
	await _test_launch_and_expansion_assemble_authoritative_gauntlets()
	await _test_m1_and_next_reject_launch_gauntlets_atomically()
	await _test_late_assembly_failure_preserves_active_gauntlets()
	await _test_reconfigure_preserves_monotonic_action_tokens()
	await _test_no_coordinator_intermediate_loadout_preserves_monotonic_action_tokens()
	await _test_stale_payload_and_feedback_cannot_collide_after_runtime_rebuild()
	await _test_dash_completion_context_boundaries_and_reset()
	await _test_counter_ready_presentation_matches_the_real_submission_window()
	await _test_gauntlets_impact_fact_bridge()
	if EventBus.weapon_hit_confirmed.is_connected(_on_weapon_hit_confirmed):
		EventBus.weapon_hit_confirmed.disconnect(_on_weapon_hit_confirmed)
	_suite.finish(get_tree())


func _test_launch_and_expansion_assemble_authoritative_gauntlets() -> void:
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		var player := await _spawn_player()
		_suite.assert_true(
			player.configure_loadout(_gauntlets_config(milestone)),
			"%s accepts the authoritative Gauntlets profile" % milestone
		)
		_suite.assert_true(player.weapon_runtime != null, "%s assembles a Gauntlets runtime" % milestone)
		_suite.assert_true(player.weapon_action_coordinator != null, "%s assembles a Gauntlets coordinator" % milestone)
		_suite.assert_true(
			player.get_node_or_null("GauntletsWeapon") != null,
			"%s scene owns the Gauntlets adapter" % milestone
		)
		_suite.assert_equal(
			player.weapon_presentation_snapshot().get("weapon_id"),
			"gauntlets",
			"%s equips Gauntlets authority" % milestone
		)
		_suite.assert_equal(
			player.weapon_presentation_snapshot().get("profile_id"),
			"gauntlets_launch_v1",
			"%s preserves Gauntlets profile identity" % milestone
		)
		if player.weapon_runtime != null:
			var runtime_snapshot: Dictionary = player.weapon_runtime.snapshot()
			_suite.assert_equal(runtime_snapshot.get("chain_step"), 0, "%s starts at the first chain step" % milestone)
			_suite.assert_equal(runtime_snapshot.get("combo_count"), 0, "%s starts with no confirmed Combo" % milestone)
		await _free_player(player)

	var player := await _spawn_player()
	var implicit_profile := _gauntlets_config("LAUNCH")
	implicit_profile.erase("weapon_profile")
	_suite.assert_true(
		player.configure_loadout(implicit_profile),
		"Launch Gauntlets selects its authoritative profile when omitted"
	)
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("profile_id"),
		"gauntlets_launch_v1",
		"implicit Gauntlets selection resolves the Launch profile"
	)
	_suite.assert_true(
		bool(player.weapon_presentation_snapshot().get("compatibility_profile_fallback", false)),
		"implicit Gauntlets selection discloses the compatibility fallback"
	)
	await _free_player(player)


func _test_m1_and_next_reject_launch_gauntlets_atomically() -> void:
	var player := await _spawn_player()
	var accepted_before: Dictionary = player.weapon_presentation_snapshot()
	for milestone: String in ["M1", "NEXT"]:
		_suite.assert_true(
			not player.configure_loadout(_gauntlets_config(milestone)),
			"%s rejects the Launch-only Gauntlets profile" % milestone
		)
		_suite.assert_equal(
			player.weapon_presentation_snapshot(),
			accepted_before,
			"%s Gauntlets rejection preserves the accepted runtime atomically" % milestone
		)
	await _free_player(player)


func _test_late_assembly_failure_preserves_active_gauntlets() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_gauntlets_config("LAUNCH")), "late failure fixture equips Launch Gauntlets")
	var committed: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(committed.get("ok", false)), "late failure fixture stages an authoritative punch")
	var runtime_before: RefCounted = player.weapon_runtime
	var coordinator_before: RefCounted = player.weapon_action_coordinator
	var runtime_snapshot_before: Dictionary = runtime_before.snapshot()
	var presentation_before: Dictionary = player.weapon_presentation_snapshot()
	var weapon: Node = player.get_node("GauntletsWeapon")
	var prepared_before: Array[Dictionary] = weapon.prepared_payload_snapshots_for_test()
	_suite.assert_equal(prepared_before.size(), 1, "late failure fixture owns one staged payload")

	var real_time_manager: Node = player.time_manager
	var invalid_time_manager := Node.new()
	player.time_manager = invalid_time_manager
	_suite.assert_true(
		not player.configure_loadout(_gauntlets_config("LAUNCH")),
		"resource-provider failure rejects candidate assembly after Runtime validation"
	)
	player.time_manager = real_time_manager
	invalid_time_manager.free()
	_suite.assert_true(player.weapon_runtime == runtime_before, "late assembly rejection preserves the active Runtime identity")
	_suite.assert_true(player.weapon_action_coordinator == coordinator_before, "late assembly rejection preserves the active Coordinator identity")
	_suite.assert_equal(player.weapon_runtime.snapshot(), runtime_snapshot_before, "late assembly rejection preserves Runtime state")
	_suite.assert_equal(player.weapon_presentation_snapshot(), presentation_before, "late assembly rejection preserves presentation state")
	_suite.assert_equal(weapon.prepared_payload_snapshots_for_test(), prepared_before, "late assembly rejection preserves staged Adapter payloads")
	await _free_player(player)


func _test_reconfigure_preserves_monotonic_action_tokens() -> void:
	var player := await _spawn_player()
	var config := _gauntlets_config("LAUNCH")
	_suite.assert_true(player.configure_loadout(config), "token fixture equips Launch Gauntlets")
	var first: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(first.get("ok", false)), "token fixture commits the first punch")
	var first_token := int(first.get("token", 0))
	player.reset_runtime_state()
	_suite.assert_true(player.configure_loadout(config), "token fixture rebuilds the same Gauntlets loadout")
	var second: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(second.get("ok", false)), "token fixture commits the post-rebuild punch")
	_suite.assert_true(int(second.get("token", 0)) > first_token, "Coordinator rebuild preserves a monotonic action-token floor")
	await _free_player(player)


func _test_no_coordinator_intermediate_loadout_preserves_monotonic_action_tokens() -> void:
	var player := await _spawn_player()
	var config := _gauntlets_config("LAUNCH")
	_suite.assert_true(player.configure_loadout(config), "persistent token fixture equips Launch Gauntlets")
	var first: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(first.get("ok", false)), "persistent token fixture commits the first punch")
	var first_token := int(first.get("token", 0))

	_suite.assert_true(
		player.configure_loadout(_no_coordinator_weapon_config()),
		"an unknown future weapon can occupy the loadout without a Coordinator"
	)
	_suite.assert_true(player.weapon_action_coordinator == null, "the intermediate loadout owns no Coordinator")
	_suite.assert_true(player.configure_loadout(config), "persistent token fixture re-equips Launch Gauntlets")
	var second: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(second.get("ok", false)), "persistent token fixture commits after the Coordinator gap")
	_suite.assert_true(
		int(second.get("token", 0)) > first_token,
		"Player preserves the monotonic action-token floor across a loadout with no Coordinator"
	)
	await _free_player(player)


func _test_stale_payload_and_feedback_cannot_collide_after_runtime_rebuild() -> void:
	_hit_facts.clear()
	var player := await _spawn_player()
	var config := _gauntlets_config("LAUNCH")
	_suite.assert_true(player.configure_loadout(config), "stale callback fixture equips Launch Gauntlets")
	var old_commit: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(old_commit.get("ok", false)), "stale callback fixture commits the old action")
	var old_token := int(old_commit.get("token", 0))
	var weapon: Node = player.get_node("GauntletsWeapon")
	var old_payloads: Array[Dictionary] = weapon.prepared_payload_snapshots_for_test()
	_suite.assert_equal(old_payloads.size(), 1, "stale callback fixture captures one old payload")
	var old_payload: Dictionary = old_payloads[0].duplicate(true) if not old_payloads.is_empty() else {}
	var old_action_id := StringName(str(old_payload.get("source_action_id", "")))
	var stale_result := {
		"target_id": 9901,
		"outcome_id": str(old_payload.get("outcome_id", "stale:outcome")),
		"descriptor_id": str(old_payload.get("descriptor_id", "stale:descriptor")),
		"outcome_index": int(old_payload.get("outcome_index", 0)),
		"deterministic_seed": int(old_payload.get("deterministic_seed", 0)),
		"damage": 1.0,
		"hit": true,
		"hit_confirmed": true,
	}

	_suite.assert_true(
		player.configure_loadout(_no_coordinator_weapon_config()),
		"stale callback fixture crosses a loadout with no Coordinator"
	)
	_suite.assert_true(player.configure_loadout(config), "stale callback fixture binds a new Gauntlets Runtime sink")
	var new_commit: Dictionary = player.weapon_action_coordinator.submit_intent(
		{"id": "weapon_skill", "edge": "pressed"},
		player.call("_weapon_submission_context")
	)
	_suite.assert_true(bool(new_commit.get("ok", false)), "stale callback fixture commits the new action")
	var new_token := int(new_commit.get("token", 0))
	_suite.assert_true(new_token > old_token, "new Runtime action identity cannot collide with the old payload token")

	var runtime_before: Dictionary = player.weapon_runtime.snapshot()
	var energy_before := float(player.time_manager.energy)
	var payloads_before: Array[Dictionary] = weapon.prepared_payload_snapshots_for_test()
	var feedback_before: Array[Dictionary] = weapon.feedback_facts_for_test()
	var hit_facts_before := _hit_facts.size()
	var stale_response: Dictionary = player.weapon_runtime.handle_payload_result(
		old_token,
		old_token,
		stale_result.duplicate(true)
	)
	_suite.assert_true(not bool(stale_response.get("ok", false)), "the new Runtime sink explicitly rejects old payload identity")
	_suite.assert_true(
		StringName(str(stale_response.get("code", ""))) in [&"STALE_GENERATION", &"STALE_TOKEN"],
		"old payload rejection is classified as stale identity"
	)
	weapon.emit_signal(
		"impact_feedback_requested",
		old_token,
		old_token,
		{
			"weapon_id": "gauntlets",
			"action_id": str(old_action_id),
			"target_id": 9901,
			"damage": 1.0,
			"impact_tier": "heavy",
		}
	)
	_suite.assert_equal(player.weapon_runtime.snapshot(), runtime_before, "stale payload leaves the new Runtime and Combo unchanged")
	_suite.assert_equal(float(player.time_manager.energy), energy_before, "stale payload cannot change authoritative resources")
	_suite.assert_equal(weapon.prepared_payload_snapshots_for_test(), payloads_before, "stale callback leaves new staged payloads unchanged")
	_suite.assert_equal(weapon.feedback_facts_for_test(), feedback_before, "stale callback cannot append Adapter feedback")
	_suite.assert_equal(_hit_facts.size(), hit_facts_before, "stale callback cannot publish a Player hit fact")
	await _free_player(player)


func _test_dash_completion_context_boundaries_and_reset() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_gauntlets_config("LAUNCH")),
		"Dash context fixture equips Launch Gauntlets"
	)
	_suite.assert_true(
		player.action_state.transition_to(PlayerActionStateScript.State.DASH, 2),
		"fixture starts an isolated Dash"
	)
	player.advance_action_frame()
	player.advance_action_frame()
	var completed_context: Dictionary = player.call("_weapon_submission_context")
	_suite.assert_true(
		int(completed_context.get("dash_completion_token", 0)) > 0,
		"Dash completion publishes a positive token"
	)
	_suite.assert_equal(
		completed_context.get("frames_since_dash_completion"),
		0,
		"the completion frame opens Counter at age zero"
	)

	for _frame: int in range(8):
		player.advance_action_frame()
	_suite.assert_equal(
		player.call("_weapon_submission_context").get("frames_since_dash_completion"),
		8,
		"Counter remains eligible on frame eight"
	)
	player.advance_action_frame()
	_suite.assert_equal(
		player.call("_weapon_submission_context").get("frames_since_dash_completion"),
		9,
		"frame nine is observably outside the Counter boundary"
	)

	player.reset_runtime_state()
	var reset_context: Dictionary = player.call("_weapon_submission_context")
	_suite.assert_equal(reset_context.get("dash_completion_token"), 0, "reset invalidates the prior Dash token")
	_suite.assert_equal(reset_context.get("frames_since_dash_completion"), -1, "reset closes the prior Counter window")
	await _free_player(player)


func _test_counter_ready_presentation_matches_the_real_submission_window() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_gauntlets_config("LAUNCH")),
		"Counter presentation fixture equips Launch Gauntlets"
	)
	_suite.assert_true(
		player.action_state.transition_to(PlayerActionStateScript.State.DASH, 2),
		"Counter presentation fixture starts an isolated Dash"
	)
	player.advance_action_frame()
	player.advance_action_frame()
	_suite.assert_true(
		_counter_ready(player.weapon_presentation_snapshot()),
		"Dash completion frame zero exposes Counter Ready before submission"
	)
	for _frame: int in range(8):
		player.advance_action_frame()
	_suite.assert_true(
		_counter_ready(player.weapon_presentation_snapshot()),
		"Counter Ready remains visible on the last accepted frame eight"
	)
	player.advance_action_frame()
	_suite.assert_true(
		not _counter_ready(player.weapon_presentation_snapshot()),
		"Counter Ready closes on frame nine with the submission window"
	)

	player.reset_runtime_state()
	_suite.assert_true(
		player.action_state.transition_to(PlayerActionStateScript.State.DASH, 1),
		"Counter consumption fixture starts a second isolated Dash"
	)
	player.advance_action_frame()
	_suite.assert_true(_counter_ready(player.weapon_presentation_snapshot()), "second Dash opens Counter Ready")
	_suite.assert_true(player.try_action(&"weapon_primary"), "Counter input is accepted inside the real window")
	var consumed: Dictionary = player.weapon_presentation_snapshot()
	_suite.assert_equal(consumed.get("action_id"), "dodge_counter", "window submission resolves the Counter action")
	_suite.assert_true(
		not _counter_ready(consumed),
		"Counter Ready clears immediately when the submission consumes the window"
	)
	await _free_player(player)


func _test_gauntlets_impact_fact_bridge() -> void:
	_hit_facts.clear()
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_gauntlets_config("LAUNCH")),
		"impact bridge fixture equips Launch Gauntlets"
	)
	player.call("_track_weapon_action_token", 77, &"punch_1", 1)
	player.get_node("GauntletsWeapon").emit_signal(
		"impact_feedback_requested",
		77,
		77,
		{
			"weapon_id": "gauntlets",
			"action_id": "punch_1",
			"target_id": 7001,
			"damage": 4.8,
			"impact_tier": "light",
		}
	)
	_suite.assert_equal(_hit_facts.size(), 1, "one live Gauntlets impact publishes one typed hit fact")
	if _hit_facts.size() == 1:
		_suite.assert_equal(_hit_facts[0].get("weapon_id"), &"gauntlets", "impact fact identifies Gauntlets")
		_suite.assert_equal(_hit_facts[0].get("action_id"), &"punch_1", "impact fact preserves action identity")
		_suite.assert_equal(_hit_facts[0].get("target_id"), 7001, "impact fact preserves stable target identity")
		_suite.assert_equal(
			(_hit_facts[0].get("context", {}) as Dictionary).get("impact_tier"),
			"light",
			"impact fact carries deterministic feedback tier"
		)
	await _free_player(player)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	return player


func _free_player(player: Node) -> void:
	if is_instance_valid(player):
		player.cancel_transient_actions()
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _gauntlets_config(milestone: String) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"character_id": "wanderer",
		"weapon_id": "gauntlets",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("gauntlets_launch_v1"),
	}


func _no_coordinator_weapon_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "future_weapon_without_runtime",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}


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


func _counter_ready(presentation: Dictionary) -> bool:
	var runtime_value: Variant = presentation.get("runtime", {})
	return runtime_value is Dictionary and bool((runtime_value as Dictionary).get("counter_ready", false))


func _on_weapon_hit_confirmed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	target_id: int,
	context: Dictionary
) -> void:
	if weapon_id != &"gauntlets":
		return
	_hit_facts.append({
		"weapon_id": weapon_id,
		"action_id": action_id,
		"token": token,
		"target_id": target_id,
		"context": context.duplicate(true),
	})
