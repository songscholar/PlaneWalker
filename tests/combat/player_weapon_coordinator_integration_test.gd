extends Node

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const LIGHT_1_WINDUP_FRAMES := 6
const LIGHT_1_ACTIVE_FRAMES := 5
const LIGHT_1_RECOVERY_CANCEL_FRAME := 6

var _suite


class EventRecorder extends RefCounted:
	var commits: Array[Dictionary] = []
	var cues: Array[Dictionary] = []


	func on_weapon_action_committed(
		weapon_id: StringName,
		action_id: StringName,
		token: int,
		context: Dictionary
	) -> void:
		commits.append({
			"weapon_id": weapon_id,
			"action_id": action_id,
			"token": token,
			"context": context.duplicate(true),
		})


	func on_weapon_cue_requested(
		weapon_id: StringName,
		action_id: StringName,
		token: int,
		cue: Dictionary
	) -> void:
		cues.append({
			"weapon_id": weapon_id,
			"action_id": action_id,
			"token": token,
			"cue": cue.duplicate(true),
		})


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_default_sword_exposes_immutable_weapon_snapshot()
	await _test_coordinator_owns_phases_and_event_timing()
	await _test_same_frame_edges_follow_dash_time_weapon_priority()
	await _test_dash_and_time_buffers_preempt_weapon_combo()
	await _test_cancel_and_reset_invalidate_active_hitbox()
	await _test_mismatched_profile_reconfigure_is_atomic()
	await _test_non_m1_direct_loadout_exposes_compatibility_fallback()
	await _test_explicit_profile_milestone_mismatch_is_atomic()
	await _test_bow_candidate_uses_shared_hold_transaction()
	await _test_bow_undercharge_and_time_cancel_are_atomic()
	_suite.finish(get_tree())


func _test_default_sword_exposes_immutable_weapon_snapshot() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.has_method("weapon_presentation_snapshot"),
		"default Sword player exposes the coordinator-backed weapon presentation snapshot"
	)
	if not player.has_method("weapon_presentation_snapshot"):
		await _free_player(player)
		return

	var presentation: Dictionary = _weapon_presentation(player)
	var identity := _profile_identity(player, presentation)
	_suite.assert_equal(presentation.get("weapon_id"), "sword", "default weapon presentation identifies Sword")
	_suite.assert_equal(presentation.get("phase"), "READY", "default weapon presentation begins ready")
	_suite.assert_equal(identity.get("profile_id"), "sword_m1_v1", "presentation or UI publishes the accepted profile id")
	_suite.assert_equal(identity.get("profile_version"), 1, "presentation or UI publishes the accepted profile version")
	_suite.assert_true(int(presentation.get("generation", 0)) > 0, "presentation publishes a valid coordinator generation")
	_suite.assert_equal(int(presentation.get("token", -1)), 0, "ready presentation has no active action token")

	_corrupt_snapshot(presentation)
	var ui_snapshot: Dictionary = _player_ui_snapshot(player)
	_corrupt_snapshot(ui_snapshot)
	var fresh_presentation := _weapon_presentation(player)
	var fresh_identity := _profile_identity(player, fresh_presentation)
	_suite.assert_equal(fresh_presentation.get("weapon_id"), "sword", "caller mutation cannot replace presentation weapon identity")
	_suite.assert_equal(fresh_presentation.get("phase"), "READY", "caller mutation cannot replace the coordinator phase")
	_suite.assert_equal(fresh_identity.get("profile_id"), "sword_m1_v1", "profile id snapshot is immutable to callers")
	_suite.assert_equal(fresh_identity.get("profile_version"), 1, "profile version snapshot is immutable to callers")
	await _free_player(player)


func _test_coordinator_owns_phases_and_event_timing() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.has_method("weapon_presentation_snapshot"),
		"phase integration exposes the coordinator-backed presentation snapshot"
	)
	if not player.has_method("weapon_presentation_snapshot"):
		await _free_player(player)
		return

	var recorder := EventRecorder.new()
	EventBus.weapon_action_committed.connect(recorder.on_weapon_action_committed)
	EventBus.weapon_cue_requested.connect(recorder.on_weapon_cue_requested)

	_suite.assert_true(player.try_action(&"attack"), "default Sword primary commits through the coordinator")
	_suite.assert_equal(recorder.commits.size(), 1, "EventBus publishes exactly one typed weapon commit at transaction commit")
	_suite.assert_equal(recorder.cues.size(), 0, "typed release cue is silent during windup")
	if recorder.commits.size() == 1:
		var committed: Dictionary = recorder.commits[0]
		_suite.assert_equal(committed.get("weapon_id"), &"sword", "typed commit identifies Sword")
		_suite.assert_equal(committed.get("action_id"), &"light_1", "typed commit identifies the first combo action")
		_suite.assert_true(int(committed.get("token", 0)) > 0, "typed commit publishes the coordinator token")

	var windup := _weapon_presentation(player)
	_suite.assert_equal(windup.get("phase"), "WINDUP", "coordinator begins the action in windup")
	_suite.assert_equal(windup.get("action_id"), "light_1", "presentation projects the committed action")
	_suite.assert_equal(
		player.action_state.current_state,
		PlayerActionStateScript.State.ATTACK_WINDUP,
		"legacy action_state is a compatible windup projection"
	)

	_advance(player, LIGHT_1_WINDUP_FRAMES - 1)
	_suite.assert_equal(_weapon_presentation(player).get("phase"), "WINDUP", "coordinator retains windup before its final frame")
	_suite.assert_equal(recorder.cues.size(), 0, "pre-active frame publishes no release cue")
	_suite.assert_equal(recorder.commits.size(), 1, "phase advancement never duplicates the typed commit")

	player.advance_action_frame()
	var active := _weapon_presentation(player)
	_suite.assert_equal(active.get("phase"), "ACTIVE", "coordinator enters active on the exact M1 frame")
	_suite.assert_equal(
		player.action_state.current_state,
		PlayerActionStateScript.State.ATTACK_ACTIVE,
		"legacy action_state projects the coordinator active phase"
	)
	_suite.assert_equal(recorder.cues.size(), 1, "typed weapon cue publishes exactly once on ACTIVE")
	_suite.assert_equal(recorder.commits.size(), 1, "ACTIVE entry does not republish the typed commit")

	_advance(player, LIGHT_1_ACTIVE_FRAMES)
	_suite.assert_equal(_weapon_presentation(player).get("phase"), "RECOVERY", "coordinator advances active into recovery")
	_suite.assert_equal(
		player.action_state.current_state,
		PlayerActionStateScript.State.ATTACK_RECOVERY,
		"legacy action_state projects the coordinator recovery phase"
	)
	_suite.assert_equal(recorder.cues.size(), 1, "recovery never duplicates the typed release cue")
	_suite.assert_equal(recorder.commits.size(), 1, "recovery never duplicates the typed commit fact")

	_disconnect_recorder(recorder)
	await _free_player(player)


func _test_same_frame_edges_follow_dash_time_weapon_priority() -> void:
	var time_and_attack: Array[StringName] = [&"time_stop"]
	var attack: Array[StringName] = [&"attack"]
	var no_time_actions: Array[StringName] = []

	var dash_player := await _spawn_player()
	var dash_energy_before: float = dash_player.get_node("TimeManager").energy
	_suite.assert_true(
		bool(dash_player.call("_submit_priority_action_edges", true, time_and_attack, attack)),
		"same-frame Dash, Time, and Attack produce one accepted action"
	)
	_suite.assert_equal(
		dash_player.action_state.current_state,
		PlayerActionStateScript.State.DASH,
		"Dash wins over Time and Attack from READY"
	)
	_suite.assert_close(
		dash_player.get_node("TimeManager").energy,
		dash_energy_before,
		"Dash priority prevents the lower-priority Time action from spending energy"
	)
	_suite.assert_equal(_weapon_presentation(dash_player).get("phase"), "READY", "Dash priority commits no weapon action")
	await get_tree().create_timer(0.25).timeout
	await _free_player(dash_player)

	var time_player := await _spawn_player()
	var time_manager: Node = time_player.get_node("TimeManager")
	var time_energy_before: float = time_manager.energy
	_suite.assert_true(
		bool(time_player.call("_submit_priority_action_edges", false, time_and_attack, attack)),
		"same-frame Time and Attack produce one accepted action"
	)
	_suite.assert_equal(
		time_player.action_state.current_state,
		PlayerActionStateScript.State.TIME_CAST,
		"Time wins over Attack from READY"
	)
	_suite.assert_true(time_manager.energy < time_energy_before, "the winning Time action spends energy exactly once")
	_suite.assert_equal(_weapon_presentation(time_player).get("phase"), "READY", "Time priority commits no weapon action")
	await _free_player(time_player)

	var cancel_player := await _spawn_player()
	_suite.assert_true(cancel_player.try_action(&"attack"), "same-frame cancel fixture commits light one")
	_advance(
		cancel_player,
		LIGHT_1_WINDUP_FRAMES + LIGHT_1_ACTIVE_FRAMES + LIGHT_1_RECOVERY_CANCEL_FRAME
	)
	_suite.assert_true(
		bool(cancel_player.call("_submit_priority_action_edges", true, no_time_actions, attack)),
		"same-frame Dash and Attack produce one accepted recovery cancel"
	)
	_suite.assert_equal(
		cancel_player.action_state.current_state,
		PlayerActionStateScript.State.DASH,
		"Dash wins over Attack on the open recovery cancel frame"
	)
	_suite.assert_equal(_weapon_presentation(cancel_player).get("phase"), "READY", "Dash cancels instead of replacing the weapon action")
	await get_tree().create_timer(0.25).timeout
	await _free_player(cancel_player)


func _test_dash_and_time_buffers_preempt_weapon_combo() -> void:
	var dash_player := await _spawn_player()
	_suite.assert_true(dash_player.try_action(&"attack"), "dash priority fixture commits light one")
	_advance(dash_player, LIGHT_1_WINDUP_FRAMES + LIGHT_1_ACTIVE_FRAMES)
	_suite.assert_equal(
		_weapon_presentation(dash_player).get("phase"),
		"RECOVERY",
		"dash priority fixture reaches recovery"
	)
	_suite.assert_true(dash_player.try_action(&"attack"), "dash priority fixture buffers the combo")
	_suite.assert_true(dash_player.try_action(&"dash"), "dash priority fixture buffers Dash")
	_advance(dash_player, LIGHT_1_RECOVERY_CANCEL_FRAME)
	_suite.assert_equal(
		dash_player.action_state.current_state,
		PlayerActionStateScript.State.DASH,
		"Dash preempts the buffered combo on the shared cancel frame"
	)
	var dash_weapon := _weapon_presentation(dash_player)
	_suite.assert_equal(dash_weapon.get("phase"), "READY", "Dash cancellation leaves no replacement weapon phase")
	_suite.assert_equal(int(dash_weapon.get("token", -1)), 0, "Dash invalidates the abandoned weapon token")
	await get_tree().create_timer(0.25).timeout
	await _free_player(dash_player)

	var time_player := await _spawn_player()
	var time_manager: Node = time_player.get_node("TimeManager")
	time_manager.time_stop_duration = 0.01
	_suite.assert_true(time_player.try_action(&"attack"), "time priority fixture commits light one")
	_advance(time_player, LIGHT_1_WINDUP_FRAMES + LIGHT_1_ACTIVE_FRAMES)
	_suite.assert_true(time_player.try_action(&"attack"), "time priority fixture buffers the combo")
	_suite.assert_true(time_player.try_action(&"time_stop"), "time priority fixture buffers Time Stop")
	_advance(time_player, LIGHT_1_RECOVERY_CANCEL_FRAME)
	_suite.assert_equal(
		time_player.action_state.current_state,
		PlayerActionStateScript.State.TIME_CAST,
		"Time Cast preempts the buffered combo when no Dash is pending"
	)
	var time_weapon := _weapon_presentation(time_player)
	_suite.assert_equal(time_weapon.get("phase"), "READY", "Time Cast cancellation leaves no replacement weapon phase")
	_suite.assert_equal(int(time_weapon.get("token", -1)), 0, "Time Cast invalidates the abandoned weapon token")
	await _free_player(time_player)


func _test_cancel_and_reset_invalidate_active_hitbox() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.has_method("weapon_presentation_snapshot"),
		"cancellation integration exposes the coordinator-backed presentation snapshot"
	)
	if not player.has_method("weapon_presentation_snapshot"):
		await _free_player(player)
		return

	var hitbox: Node = player.get_node("SwordWeapon/Hitbox")
	_suite.assert_true(player.try_action(&"attack"), "cancellation fixture commits an attack")
	_advance(player, LIGHT_1_WINDUP_FRAMES)
	_suite.assert_true(bool(hitbox.call("is_active")), "Sword hitbox is active before cancellation")
	var active := _weapon_presentation(player)
	var cancelled_token := int(active.get("token", 0))
	var cancelled_generation := int(active.get("generation", 0))
	_suite.assert_true(cancelled_token > 0, "active cancellation fixture owns a token")

	player.cancel_transient_actions()
	var cancelled := _weapon_presentation(player)
	_suite.assert_equal(cancelled.get("phase"), "READY", "cancellation returns coordinator authority to ready")
	_suite.assert_equal(int(cancelled.get("token", -1)), 0, "cancellation invalidates the active action token")
	_suite.assert_true(
		int(cancelled.get("generation", 0)) > cancelled_generation,
		"cancellation advances the generation against stale callbacks"
	)
	_suite.assert_true(not bool(hitbox.call("is_active")), "cancellation deactivates the active Sword hitbox")
	_suite.assert_equal(
		player.action_state.current_state,
		PlayerActionStateScript.State.FREE,
		"cancellation clears the compatibility action projection"
	)
	_advance(player, LIGHT_1_ACTIVE_FRAMES + 2)
	_suite.assert_true(not bool(hitbox.call("is_active")), "stale action frames cannot reactivate a cancelled hitbox")

	_suite.assert_true(player.try_action(&"attack"), "a fresh attack can commit after cancellation")
	var restarted := _weapon_presentation(player)
	_suite.assert_true(int(restarted.get("token", 0)) > cancelled_token, "new action token remains monotonic after cancellation")
	player.reset_runtime_state()
	var reset := _weapon_presentation(player)
	_suite.assert_equal(reset.get("phase"), "READY", "runtime reset leaves coordinator ready")
	_suite.assert_equal(int(reset.get("token", -1)), 0, "runtime reset invalidates the replacement token")
	_suite.assert_true(not bool(hitbox.call("is_active")), "runtime reset leaves the Sword hitbox inactive")
	await _free_player(player)


func _test_mismatched_profile_reconfigure_is_atomic() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.has_method("weapon_presentation_snapshot"),
		"profile integration exposes the coordinator-backed presentation snapshot"
	)
	if not player.has_method("weapon_presentation_snapshot"):
		await _free_player(player)
		return

	_suite.assert_true(player.try_action(&"attack"), "atomic reconfigure fixture starts the accepted Sword runtime")
	var before := _weapon_presentation(player)
	var before_identity := _profile_identity(player, before)
	var mismatched := _loadout_config("sword")
	mismatched["weapon_profile"] = _profile_definition("bow_candidate_v1")
	_suite.assert_true(
		not player.configure_loadout(mismatched),
		"Sword loadout rejects a Bow weapon profile before runtime replacement"
	)

	var after := _weapon_presentation(player)
	var after_identity := _profile_identity(player, after)
	_suite.assert_equal(after_identity, before_identity, "failed reconfigure preserves accepted profile identity and version")
	_suite.assert_equal(after.get("phase"), before.get("phase"), "failed reconfigure preserves the current coordinator phase")
	_suite.assert_equal(after.get("token"), before.get("token"), "failed reconfigure preserves the active runtime token")
	_suite.assert_equal(after.get("generation"), before.get("generation"), "failed reconfigure does not replace the runtime generation")
	_suite.assert_equal(
		player.action_state.current_state,
		PlayerActionStateScript.State.ATTACK_WINDUP,
		"failed reconfigure preserves the compatibility action projection"
	)

	_advance(player, LIGHT_1_WINDUP_FRAMES)
	_suite.assert_equal(_weapon_presentation(player).get("phase"), "ACTIVE", "prior Sword runtime continues after rejected reconfigure")
	_suite.assert_true(
		bool(player.get_node("SwordWeapon/Hitbox").call("is_active")),
		"prior Sword payload still activates after rejected reconfigure"
	)
	player.cancel_transient_actions()
	await _free_player(player)


func _test_non_m1_direct_loadout_exposes_compatibility_fallback() -> void:
	var player := await _spawn_player()
	var next_without_profile := _loadout_config("sword")
	next_without_profile["milestone"] = "NEXT"
	_suite.assert_true(
		player.configure_loadout(next_without_profile),
		"direct NEXT time-loadout fixtures retain the temporary M1 compatibility path"
	)
	var presentation := _weapon_presentation(player)
	_suite.assert_equal(
		_profile_identity(player, presentation).get("profile_id"),
		"sword_m1_v1",
		"the compatibility path identifies the exact fallback profile"
	)
	_suite.assert_true(
		bool(presentation.get("compatibility_profile_fallback", false)),
		"the direct-loadout compatibility path is observable instead of silent"
	)
	await _free_player(player)


func _test_explicit_profile_milestone_mismatch_is_atomic() -> void:
	var player := await _spawn_player()
	var before := _weapon_presentation(player)
	var mismatched := _loadout_config("sword")
	mismatched["milestone"] = "NEXT"
	mismatched["weapon_profile"] = _profile_definition("sword_m1_v1")
	_suite.assert_true(
		not player.configure_loadout(mismatched),
		"an explicit NEXT plus M1 Profile mismatch is rejected"
	)
	var after := _weapon_presentation(player)
	_suite.assert_equal(
		_profile_identity(player, after),
		_profile_identity(player, before),
		"milestone mismatch rejection preserves the accepted Profile"
	)
	_suite.assert_equal(
		after.get("generation"),
		before.get("generation"),
		"milestone mismatch rejection does not replace the coordinator"
	)
	await _free_player(player)


func _test_bow_candidate_uses_shared_hold_transaction() -> void:
	var player := await _spawn_player()
	var bow_config := _loadout_config("bow")
	bow_config["milestone"] = "NEXT"
	bow_config["weapon_profile"] = _profile_definition("bow_candidate_v1")
	_suite.assert_true(
		player.configure_loadout(bow_config),
		"NEXT Bow candidate configures a profile-backed runtime and coordinator"
	)
	_suite.assert_true(player.weapon_runtime != null, "Bow candidate owns a real weapon runtime")
	_suite.assert_true(
		player.weapon_action_coordinator != null,
		"Bow candidate owns the shared weapon action coordinator"
	)
	if player.weapon_action_coordinator == null:
		await _free_player(player)
		return

	var recorder := EventRecorder.new()
	EventBus.weapon_action_committed.connect(recorder.on_weapon_action_committed)
	EventBus.weapon_cue_requested.connect(recorder.on_weapon_cue_requested)

	_suite.assert_true(player.try_action(&"ranged_attack"), "Bow press reserves the charge transaction")
	var hold := _weapon_presentation(player)
	var hold_token := int(hold.get("token", 0))
	var hold_generation := int(hold.get("generation", 0))
	_suite.assert_equal(hold.get("phase"), "HOLD", "Bow press enters coordinator-owned HOLD")
	_suite.assert_true(hold_token > 0, "Bow HOLD owns a coordinator action token")
	_suite.assert_equal(recorder.commits.size(), 0, "Bow press publishes no typed commit before release")
	_suite.assert_equal(recorder.cues.size(), 0, "Bow HOLD publishes no release cue")

	_advance(player, 9)
	_suite.assert_true(player.try_action(&"ranged_release"), "threshold release resolves the active HOLD")
	var released := _weapon_presentation(player)
	_suite.assert_equal(released.get("phase"), "WINDUP", "threshold release advances the same transaction to WINDUP")
	_suite.assert_equal(int(released.get("token", 0)), hold_token, "release preserves the original action token")
	_suite.assert_equal(int(released.get("generation", 0)), hold_generation, "release does not create a replacement generation")
	_suite.assert_equal(recorder.commits.size(), 1, "release publishes exactly one typed commit")
	_suite.assert_equal(recorder.cues.size(), 0, "Bow release waits for ACTIVE before its release cue")

	player.cancel_transient_actions()
	var cues_before_cancelled_hold := recorder.cues.size()
	_suite.assert_true(
		not player.try_action(&"ranged_attack"),
		"cancelling recovery cannot bypass the committed Bow cooldown"
	)
	_advance(player, 21)
	_suite.assert_true(player.try_action(&"ranged_attack"), "Bow can begin a fresh HOLD after cancellation")
	var cancelled_hold := _weapon_presentation(player)
	var cancelled_token := int(cancelled_hold.get("token", 0))
	var cancelled_generation := int(cancelled_hold.get("generation", 0))
	_suite.assert_true(player.try_action(&"dash"), "Dash cancels Bow HOLD immediately")
	var cancelled := _weapon_presentation(player)
	_suite.assert_equal(cancelled.get("phase"), "READY", "Dash cancellation clears Bow HOLD")
	_suite.assert_true(
		int(cancelled.get("generation", 0)) > cancelled_generation,
		"Dash cancellation invalidates the Bow HOLD generation"
	)
	_suite.assert_true(
		not player.try_action(&"ranged_release"),
		"stale release cannot resolve the cancelled Bow token"
	)
	_suite.assert_equal(
		recorder.cues.size(),
		cues_before_cancelled_hold,
		"cancelled Bow HOLD publishes no additional release cue"
	)
	_suite.assert_true(cancelled_token > hold_token, "fresh Bow HOLD uses a monotonic token")

	_disconnect_recorder(recorder)
	await get_tree().create_timer(0.25).timeout
	await _free_player(player)


func _test_bow_undercharge_and_time_cancel_are_atomic() -> void:
	var player := await _spawn_player()
	var bow_config := _loadout_config("bow")
	bow_config["milestone"] = "NEXT"
	bow_config["weapon_profile"] = _profile_definition("bow_candidate_v1")
	_suite.assert_true(player.configure_loadout(bow_config), "Bow atomic-cancel fixture configures")
	var recorder := EventRecorder.new()
	EventBus.weapon_action_committed.connect(recorder.on_weapon_action_committed)
	EventBus.weapon_cue_requested.connect(recorder.on_weapon_cue_requested)

	_suite.assert_true(player.try_action(&"ranged_attack"), "undercharge fixture begins HOLD")
	var undercharge_hold := _weapon_presentation(player)
	var undercharge_generation := int(undercharge_hold.get("generation", 0))
	_advance(player, 8)
	_suite.assert_true(
		not player.try_action(&"ranged_release"),
		"release below the nine-frame threshold is rejected"
	)
	var undercharged := _weapon_presentation(player)
	_suite.assert_equal(undercharged.get("phase"), "READY", "undercharge rejection cancels the transaction")
	_suite.assert_equal(int(undercharged.get("token", -1)), 0, "undercharge rejection clears the action token")
	_suite.assert_true(
		int(undercharged.get("generation", 0)) > undercharge_generation,
		"undercharge rejection invalidates the prior generation"
	)
	_suite.assert_equal(recorder.commits.size(), 0, "undercharge publishes no typed commit")
	_suite.assert_equal(recorder.cues.size(), 0, "undercharge publishes no release cue")

	_suite.assert_true(player.try_action(&"ranged_attack"), "time-cancel fixture begins a fresh HOLD")
	var time_hold := _weapon_presentation(player)
	var time_token := int(time_hold.get("token", 0))
	var time_manager: Node = player.get_node("TimeManager")
	var energy_before: float = time_manager.energy
	_suite.assert_true(player.try_action(&"time_stop"), "Time Cast cancels Bow HOLD at higher priority")
	var time_cancelled := _weapon_presentation(player)
	_suite.assert_equal(time_cancelled.get("phase"), "READY", "Time Cast clears Bow HOLD authority")
	_suite.assert_true(time_manager.energy < energy_before, "winning Time Cast spends energy exactly once")
	_suite.assert_true(not player.try_action(&"ranged_release"), "stale release cannot revive a Time-cancelled HOLD")
	_suite.assert_equal(recorder.cues.size(), 0, "Time-cancelled HOLD publishes no release cue")
	_suite.assert_true(time_token > int(undercharge_hold.get("token", 0)), "replacement HOLD uses a monotonic token")

	_disconnect_recorder(recorder)
	await _free_player(player)


func _weapon_presentation(player: Node) -> Dictionary:
	var value: Variant = player.call("weapon_presentation_snapshot")
	_suite.assert_true(value is Dictionary, "weapon presentation API returns a Dictionary")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _player_ui_snapshot(player: Node) -> Dictionary:
	if not player.has_method("get_player_ui_snapshot"):
		return {}
	var value: Variant = player.call("get_player_ui_snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _profile_identity(player: Node, presentation: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = [presentation]
	var runtime_value: Variant = presentation.get("runtime", {})
	if runtime_value is Dictionary:
		candidates.append(runtime_value as Dictionary)
	var ui_snapshot := _player_ui_snapshot(player)
	candidates.append(ui_snapshot)
	var ui_weapon_value: Variant = ui_snapshot.get("weapon", {})
	if ui_weapon_value is Dictionary:
		candidates.append(ui_weapon_value as Dictionary)
	for candidate: Dictionary in candidates:
		if candidate.has("profile_id") and candidate.has("profile_version"):
			return {
				"profile_id": str(candidate.get("profile_id", "")),
				"profile_version": int(candidate.get("profile_version", 0)),
			}
	return {}


func _corrupt_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	snapshot["weapon_id"] = "forged_weapon"
	snapshot["profile_id"] = "forged_profile"
	snapshot["profile_version"] = 999
	snapshot["phase"] = "FORGED"
	for key: String in ["runtime", "weapon"]:
		var nested_value: Variant = snapshot.get(key, {})
		if not nested_value is Dictionary:
			continue
		var nested := nested_value as Dictionary
		nested["weapon_id"] = "forged_weapon"
		nested["profile_id"] = "forged_profile"
		nested["profile_version"] = 999
		nested["phase"] = "FORGED"


func _loadout_config(weapon_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": weapon_id,
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}


func _profile_definition(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if (
			definition_value is Dictionary
			and str((definition_value as Dictionary).get("id", "")) == profile_id
		):
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _disconnect_recorder(recorder: EventRecorder) -> void:
	if EventBus.weapon_action_committed.is_connected(recorder.on_weapon_action_committed):
		EventBus.weapon_action_committed.disconnect(recorder.on_weapon_action_committed)
	if EventBus.weapon_cue_requested.is_connected(recorder.on_weapon_cue_requested):
		EventBus.weapon_cue_requested.disconnect(recorder.on_weapon_cue_requested)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	return player


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _advance(player: Node, frames: int) -> void:
	for _frame: int in range(frames):
		player.advance_action_frame()
