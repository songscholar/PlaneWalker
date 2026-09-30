extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


class ReplayStopProbe extends Node:
	var observed_player: Node = null
	var apply_calls: int = 0
	var clear_calls: int = 0
	var observed_snapshots: Array[Dictionary] = []


	func _ready() -> void:
		add_to_group("time_stoppable")


	func apply_time_stop_source(_source_id: StringName, _duration: float) -> void:
		apply_calls += 1
		_capture_observed_snapshot()


	func clear_time_stop_source(_source_id: StringName) -> void:
		clear_calls += 1
		_capture_observed_snapshot()


	func _capture_observed_snapshot() -> void:
		if (
			observed_player != null
			and is_instance_valid(observed_player)
			and observed_player.has_method("weapon_replay_snapshot")
		):
			observed_snapshots.append(observed_player.weapon_replay_snapshot())


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var profile := _load_profile(suite, "gun_launch_v1")
	if not profile.is_empty():
		await _test_restore_observers_see_only_complete_snapshots(suite, profile)
		await _test_failed_gameplay_rewind_is_observably_atomic(suite, profile)
		await _test_successful_gameplay_rewind_marks_replay_boundary(suite, profile)
	suite.finish(get_tree())


func _test_restore_observers_see_only_complete_snapshots(suite, profile: Dictionary) -> void:
	var source := await _spawn_player(suite, profile, "ObservableAtomicitySource")
	var target := await _spawn_player(suite, profile, "ObservableAtomicityTarget")
	if source == null or target == null:
		await _free_player(source)
		await _free_player(target)
		return

	_set_time_energy(source, 37.0)
	suite.assert_true(await _drive_to_active(source), "observable-atomicity source reaches Gun ACTIVE")
	var source_time_state: Dictionary = source.time_manager.weapon_replay_snapshot()
	source_time_state["stop_active"] = true
	source_time_state["stop_source_sequence"] = 1
	source_time_state["stop_source_id"] = "observable:stop:1"
	source_time_state["stop_remaining"] = 2.5
	suite.assert_true(
		source.time_manager.restore_weapon_replay_snapshot(source_time_state),
		"observable-atomicity source installs an authoritative active Stop"
	)
	var desired: Dictionary = source.weapon_replay_snapshot()
	var source_events: Array[Dictionary] = source.weapon_replay_events()
	var desired_prefix_count := int(desired.get("event_prefix_count", -1))
	var desired_prefix: Array = source_events.slice(0, desired_prefix_count)
	var before: Dictionary = target.weapon_replay_snapshot()
	suite.assert_true(not desired.is_empty(), "observable-atomicity source exposes a replay snapshot")
	suite.assert_true(desired != before, "observable-atomicity fixture has distinct before and after states")
	suite.assert_true(desired_prefix_count > 0, "observable-atomicity fixture uses a non-empty verified event prefix")
	suite.assert_equal(
		desired_prefix.size(),
		desired_prefix_count,
		"observable-atomicity fixture installs the exact checkpoint prefix count"
	)
	var stop_probe := ReplayStopProbe.new()
	stop_probe.observed_player = target
	add_child(stop_probe)
	await get_tree().process_frame

	var observed_snapshots: Array[Dictionary] = []
	target.time_manager.energy_changed.connect(func(_current: float, _maximum: float) -> void:
		observed_snapshots.append(target.weapon_replay_snapshot())
	)
	suite.assert_true(
		target.restore_weapon_replay_snapshot_with_event_prefix(desired, desired_prefix),
		"Player restores the complete authoritative snapshot"
	)
	suite.assert_equal(target.weapon_replay_snapshot(), desired, "Player reaches the exact requested snapshot")
	suite.assert_equal(observed_snapshots.size(), 1, "successful restore publishes one consolidated energy signal")
	for observed: Dictionary in observed_snapshots:
		suite.assert_true(
			observed == before or observed == desired,
			"energy observers see only the complete before or complete after Player snapshot"
		)
		suite.assert_equal(observed, desired, "successful restore publishes only after all Player authority is installed")
	suite.assert_equal(stop_probe.apply_calls, 1, "successful restore applies the final Stop source once")
	suite.assert_equal(stop_probe.clear_calls, 0, "successful restore clears no absent previous Stop source")
	suite.assert_equal(
		stop_probe.observed_snapshots,
		[desired],
		"Stop observers see the complete after Player snapshot"
	)
	suite.assert_equal(
		target.weapon_replay_events().size(),
		desired_prefix_count,
		"successful restore installs the exact verified event prefix"
	)
	suite.assert_true(
		ReplayRecorderScript.event_prefix_matches(
			target.weapon_replay_snapshot(),
			target.weapon_replay_events()
		),
		"successful restore preserves the verified event-prefix root"
	)

	var inactive := desired.duplicate(true)
	var inactive_time := inactive["time_manager_state"] as Dictionary
	inactive_time["stop_active"] = false
	inactive_time["stop_source_id"] = ""
	inactive_time["stop_remaining"] = 0.0
	inactive_time["stop_extension_frames"] = 0
	inactive_time["stop_extension_tokens"] = {}
	stop_probe.apply_calls = 0
	stop_probe.clear_calls = 0
	stop_probe.observed_snapshots.clear()
	var energy_observation_count_before_clear := observed_snapshots.size()
	suite.assert_true(
		target.restore_weapon_replay_snapshot(inactive),
		"Player atomically restores active Stop to inactive"
	)
	suite.assert_equal(stop_probe.apply_calls, 0, "inactive restore applies no replacement Stop source")
	suite.assert_equal(stop_probe.clear_calls, 1, "inactive restore clears the previous Stop source once")
	suite.assert_equal(
		stop_probe.observed_snapshots,
		[inactive],
		"Stop-clear observers see the complete inactive Player snapshot"
	)
	suite.assert_equal(
		observed_snapshots.size(),
		energy_observation_count_before_clear,
		"Stop-only restore emits no unrelated Energy signal"
	)

	stop_probe.queue_free()
	await get_tree().process_frame
	await _free_player(source)
	await _free_player(target)


func _test_failed_gameplay_rewind_is_observably_atomic(suite, profile: Dictionary) -> void:
	var player := await _spawn_player(suite, profile, "GameplayRewindAtomicity")
	if player == null:
		return
	suite.assert_true(
		player.configure_run(&"gameplay-rewind-observable-run"),
		"observable Gameplay Rewind fixture installs one run identity"
	)
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	player.global_position = Vector2(16.0, 28.0)
	player.velocity = Vector2(2.0, -1.0)
	health.current_hp = 92.0
	recorder.clear_snapshots()
	recorder._record_snapshot()

	player.global_position = Vector2(224.0, 156.0)
	player.velocity = Vector2(-5.0, 3.0)
	health.current_hp = 61.0
	_set_time_energy(player, 78.0)
	suite.assert_true(await _drive_to_active(player), "observable Gameplay Rewind fixture reaches Gun ACTIVE")
	var before_player: Dictionary = player.weapon_replay_snapshot()
	var before_history := _snapshot_rewind_history(recorder)
	var before_position: Vector2 = player.global_position
	var before_velocity: Vector2 = player.velocity
	var before_hp: float = health.current_hp
	var before_ledger: Dictionary = health.irreversible_ledger_snapshot()
	var before_cooldowns: Dictionary = manager._cooldowns.duplicate(true)
	suite.assert_true(manager.can_rewind(recorder), "observable Gameplay Rewind fixture is resource-eligible")
	var preflight_ticket: Dictionary = recorder.prepare_rewind_transaction()
	suite.assert_true(not preflight_ticket.is_empty(), "observable Gameplay Rewind fixture prepares a real ticket")
	if not preflight_ticket.is_empty():
		var preflight_rollback: Dictionary = recorder.rollback_rewind_transaction(preflight_ticket)
		suite.assert_true(
			bool(preflight_rollback.get("ok", false)),
			"observable Gameplay Rewind preflight ticket releases without mutation"
		)
	var energy_observations: Array[Dictionary] = []
	var cooldown_observations: Array[Dictionary] = []
	manager.energy_changed.connect(func(current: float, maximum: float) -> void:
		energy_observations.append({"current": current, "maximum": maximum})
	)
	manager.cooldown_changed.connect(func(skill_id: StringName, remaining: float) -> void:
		cooldown_observations.append({"skill_id": skill_id, "remaining": remaining})
	)

	suite.assert_true(
		recorder.has_method("set_restore_fault_for_test"),
		"observable Gameplay Rewind exposes deterministic restore fault injection"
	)
	if recorder.has_method("set_restore_fault_for_test"):
		recorder.call("set_restore_fault_for_test", &"after_time_install")
		suite.assert_true(
			not manager.try_rewind(recorder),
			"faulted Gameplay Rewind rejects the partially installed transaction"
		)
		suite.assert_equal(
			player.weapon_replay_snapshot(),
			before_player,
			"failed Gameplay Rewind restores the exact observable Player snapshot"
		)
		suite.assert_equal(
			_snapshot_rewind_history(recorder),
			before_history,
			"failed Gameplay Rewind restores the exact snapshot history"
		)
		suite.assert_equal(player.global_position, before_position, "failed Gameplay Rewind restores position")
		suite.assert_equal(player.velocity, before_velocity, "failed Gameplay Rewind restores velocity")
		suite.assert_close(health.current_hp, before_hp, "failed Gameplay Rewind restores hp")
		suite.assert_equal(
			health.irreversible_ledger_snapshot(),
			before_ledger,
			"failed Gameplay Rewind restores the exact irreversible ledger"
		)
		suite.assert_equal(manager._cooldowns, before_cooldowns, "failed Gameplay Rewind restores cooldowns")
		suite.assert_true(
			energy_observations.is_empty(),
			"failed Gameplay Rewind publishes no transient or rollback energy observation"
		)
		suite.assert_true(
			cooldown_observations.is_empty(),
			"failed Gameplay Rewind publishes no transient or rollback cooldown observation"
		)

	await _free_player(player)


func _test_successful_gameplay_rewind_marks_replay_boundary(suite, profile: Dictionary) -> void:
	var player := await _spawn_player(suite, profile, "GameplayRewindReplayBoundary")
	if player == null:
		return
	suite.assert_true(
		player.configure_run(&"gameplay-rewind-replay-boundary-run"),
		"successful Gameplay Rewind boundary fixture installs one run identity"
	)
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	player.global_position = Vector2(20.0, 36.0)
	recorder.clear_snapshots()
	recorder._record_snapshot()
	player.global_position = Vector2(220.0, 148.0)
	suite.assert_true(
		await _drive_to_active(player),
		"successful Gameplay Rewind boundary fixture commits one Gun payload"
	)
	var projectiles_before: Array[Node] = player.gun_weapon.call("owned_projectiles_for_test")
	suite.assert_equal(
		projectiles_before.size(),
		1,
		"successful Gameplay Rewind boundary fixture owns one committed projectile"
	)
	var committed_projectile: Node = (
		projectiles_before[0]
		if projectiles_before.size() == 1
		else null
	)
	manager.rewind_cost = 0.0
	manager.rewind_self_damage = 0.0
	manager.rewind_heal = 0.0
	suite.assert_true(
		manager.try_rewind(recorder),
		"successful Gameplay Rewind commits before Replay boundary invalidation"
	)
	var projectiles_after: Array[Node] = player.gun_weapon.call("owned_projectiles_for_test")
	suite.assert_equal(
		projectiles_after.size(),
		1,
		"successful Gameplay Rewind preserves the committed projectile"
	)
	if projectiles_after.size() == 1 and committed_projectile != null:
		suite.assert_true(
			projectiles_after[0] == committed_projectile,
			"successful Gameplay Rewind preserves projectile object identity"
		)
	var capture_status: Dictionary = player.weapon_replay_capture_status()
	suite.assert_true(
		not bool(capture_status.get("ok", true)),
		"successful Gameplay Rewind explicitly invalidates Replay capture"
	)
	suite.assert_equal(
		capture_status.get("code"),
		&"GAMEPLAY_REWIND_UNSUPPORTED",
		"successful Gameplay Rewind exposes the unsupported Replay boundary reason"
	)
	suite.assert_true(
		player.weapon_replay_snapshot().is_empty(),
		"unsupported Gameplay Rewind boundary exposes no recordable Replay checkpoint"
	)
	var replay_recorder = ReplayRecorderScript.new()
	var replay_profile: Dictionary = player.loadout_runtime.weapon_profile_snapshot()
	suite.assert_true(
		bool(replay_recorder.start_recording(replay_profile, 919191).get("ok", false)),
		"Replay recorder starts for explicit boundary rejection"
	)
	var record_result: Dictionary = replay_recorder.record_snapshot(
		player.weapon_replay_snapshot()
	)
	suite.assert_true(
		not bool(record_result.get("ok", true)),
		"Replay recorder explicitly rejects the unsupported post-Rewind checkpoint"
	)

	await _free_player(player)


func _set_time_energy(player: Node, current: float) -> void:
	var state: Dictionary = player.time_manager.resource_state(&"time_energy")
	state["current"] = current
	state["revision"] = int(state.get("revision", 0)) + 1
	player.time_manager.restore_resource_state(&"time_energy", state)


func _drive_to_active(player: Node) -> bool:
	player.advance_action_frame()
	if not player.try_action(&"weapon_primary"):
		return false
	if str(player.weapon_replay_snapshot().get("phase", "")) == "HOLD":
		for _frame: int in range(18):
			if str(player.weapon_replay_snapshot().get("phase", "")) != "HOLD":
				break
			player.advance_action_frame()
		if (
			str(player.weapon_replay_snapshot().get("phase", "")) == "HOLD"
			and not bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released"))
		):
			return false
	var guard := 512
	while str(player.weapon_replay_snapshot().get("phase", "")) != "ACTIVE" and guard > 0:
		player.advance_action_frame()
		guard -= 1
	return guard > 0


func _spawn_player(suite, profile: Dictionary, node_name: String) -> Node:
	var player := PlayerScene.instantiate()
	player.name = node_name
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured: bool = bool(player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "gun",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 919191,
		"weapon_profile": profile.duplicate(true),
	}))
	suite.assert_true(configured, "%s configures" % node_name)
	if not configured:
		await _free_player(player)
		return null
	return player


func _free_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.cancel_transient_actions()
	var health: Node = player.get_node("HealthComponent")
	if not (health.get("_active_invulnerability_tokens") as Dictionary).is_empty():
		await get_tree().create_timer(0.55).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _snapshot_rewind_history(recorder: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for snapshot: Dictionary in recorder._snapshots:
		result.append(snapshot.duplicate(true))
	return result


func _load_profile(suite, profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	suite.assert_true(parsed is Array, "weapon profile catalog parses for observable atomicity")
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	suite.assert_true(false, "%s exists for observable atomicity" % profile_id)
	return {}
