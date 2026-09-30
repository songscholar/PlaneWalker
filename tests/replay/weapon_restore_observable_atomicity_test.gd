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
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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
