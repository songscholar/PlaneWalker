extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const LAUNCH_SCHEMA_VERSION := 6
const CHARACTER_IDS: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]

var _suite
var _registry: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(not report.call("has_blocking_errors"), "Replay matrix loads the Base Pack")
	if not report.call("has_blocking_errors"):
		await _test_five_character_round_trips()
		await _test_passive_and_live_talent_round_trip_and_drift_rejection()
		await _test_active_item_round_trip_and_tamper_rejection()
		await _test_legacy_launch_v4_and_v5_migrate_after_authentication()
	_suite.finish(get_tree())


func _test_five_character_round_trips() -> void:
	for character_index: int in range(CHARACTER_IDS.size()):
		var character_id := CHARACTER_IDS[character_index]
		var source := await _spawn_launch_player(character_id, 4100 + character_index)
		var identity: Dictionary = source.full_player_replay_identity()
		var initial: Dictionary = source.full_player_replay_snapshot()
		var label := str(character_id)
		_suite.assert_equal(
			int(initial.get("schema_version", 0)),
			LAUNCH_SCHEMA_VERSION,
			"%s Launch snapshot uses Player Replay schema 6" % label
		)
		_suite.assert_true(
			initial.get("active_item_state") is Dictionary,
			"%s Launch snapshot includes authoritative active-item state" % label
		)
		_suite.assert_true(
			initial.get("reward_effect_state") is Dictionary,
			"%s Launch snapshot seals passive reward-effect state" % label
		)
		_suite.assert_true(
			initial.get("live_talent_state") is Dictionary,
			"%s Launch snapshot seals live talent definitions and modifiers" % label
		)

		var recorder = ReplayRecorderScript.new()
		_suite.assert_true(
			bool(recorder.start_full_player_recording(identity, 4100 + character_index).get("ok", false)),
			"%s Launch Replay recording starts" % label
		)
		_suite.assert_true(
			bool(recorder.record_full_player_frame(
				initial,
				_frame_intents(int(initial.get("frame", 0))),
				[]
			).get("ok", false)),
			"%s records the initial Launch checkpoint" % label
		)
		_suite.assert_true(source.advance_action_frame({}), "%s advances one fixed frame" % label)
		var terminal: Dictionary = source.full_player_replay_snapshot()
		_suite.assert_true(
			bool(recorder.record_full_player_frame(
				terminal,
				_frame_intents(int(terminal.get("frame", 0))),
				[]
			).get("ok", false)),
			"%s records the terminal Launch checkpoint" % label
		)
		var finished: Dictionary = recorder.finish_full_player_recording()
		_suite.assert_true(bool(finished.get("ok", false)), "%s Launch Replay finishes" % label)
		var replay := finished.get("replay", {}) as Dictionary
		_suite.assert_equal(
			int(replay.get("schema_version", 0)),
			LAUNCH_SCHEMA_VERSION,
			"%s Launch Replay root uses schema 6" % label
		)
		for frame_value: Variant in replay.get("frames", []) as Array:
			var frame := frame_value as Dictionary
			_suite.assert_equal(
				int(frame.get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s Launch Replay frame uses schema 6" % label
			)
			_suite.assert_equal(
				int((frame.get("snapshot", {}) as Dictionary).get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s embedded Launch snapshot uses schema 6" % label
			)

		var target := await _spawn_launch_player(character_id, 4100 + character_index)
		var replay_player = ReplayPlayerScript.new()
		_suite.assert_true(
			bool(replay_player.load_full_player_replay(
				replay,
				target.full_player_replay_identity()
			).get("ok", false)),
			"%s Launch Replay loads against the same character identity" % label
		)
		var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
		_suite.assert_true(
			bool(replayed.get("ok", false)),
			"%s Launch Replay reaches the terminal checkpoint" % label
		)
		_suite.assert_equal(
			target.full_player_replay_snapshot(),
			terminal,
			"%s Launch Replay restores the exact terminal state" % label
		)

		var mismatched_id := CHARACTER_IDS[(character_index + 1) % CHARACTER_IDS.size()]
		var mismatched := await _spawn_launch_player(mismatched_id, 4100 + character_index)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			replay,
			mismatched.full_player_replay_identity()
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH",
			"%s Replay rejects a different Launch character profile" % label
		)

		await _free_player(mismatched)
		await _free_player(target)
		await _free_player(source)


func _test_passive_and_live_talent_round_trip_and_drift_rejection() -> void:
	var source := await _spawn_launch_player(&"wanderer", 5151)
	var talent_definition: Dictionary = _registry.call("get_content", &"tal_eternity_reserve")
	var passive_definition := {
		"id": "replay_passive_fixture",
		"category": "item",
		"effects": {"max_hp_bonus": 12.0},
	}
	_suite.assert_true(
		source.install_character_talent(talent_definition),
		"Launch Replay fixture installs a live content-driven talent"
	)
	_suite.assert_true(
		bool(source.apply_reward(passive_definition).get("ok", false)),
		"Launch Replay fixture applies a passive reward effect"
	)
	var identity: Dictionary = source.full_player_replay_identity()
	var snapshot: Dictionary = source.full_player_replay_snapshot()
	var live_talent := snapshot.get("live_talent_state", {}) as Dictionary
	_suite.assert_equal(
		live_talent.get("selected_talent_ids"),
		["tal_eternity_reserve"],
		"Launch Replay seals the selected live talent IDs"
	)
	_suite.assert_equal(
		live_talent.get("definitions_digest"),
		ReplayRecorderScript.value_digest(live_talent.get("talent_definitions", [])),
		"Launch Replay seals the exact live talent definitions"
	)
	_suite.assert_equal(
		live_talent.get("modifier_digest"),
		ReplayRecorderScript.value_digest(live_talent.get("modifiers", {})),
		"Launch Replay seals the exact live talent modifiers"
	)
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5151).get("ok", false)),
		"sealed Launch Replay recording starts"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			snapshot,
			_frame_intents(int(snapshot.get("frame", 0))),
			[]
		).get("ok", false)),
		"sealed Launch Replay records passive and live-talent state"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "sealed Launch Replay finishes")
	var replay := (finished.get("replay", {}) as Dictionary).duplicate(true)
	await _free_player(source)

	var target := await _spawn_launch_player(&"wanderer", 5151)
	_suite.assert_true(target.install_character_talent(talent_definition), "target installs the same live talent")
	_suite.assert_true(
		bool(target.apply_reward(passive_definition).get("ok", false)),
		"target installs the same passive reward state"
	)
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(replay_player.load_full_player_replay(
			replay,
			target.full_player_replay_identity()
		).get("ok", false)),
		"sealed Launch Replay loads against matching content"
	)
	_suite.assert_true(
		bool(replay_player.restore_full_player_frame(target, 0).get("ok", false)),
		"sealed Launch Replay restores passive and live-talent state"
	)
	_suite.assert_equal(
		target.reward_effect_snapshot(),
		snapshot.get("reward_effect_state"),
		"passive reward-effect state round-trips exactly"
	)
	await _free_player(target)

	var unknown_reward := replay.duplicate(true)
	var unknown_reward_state := (
		((unknown_reward["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["reward_effect_state"] as Dictionary
	unknown_reward_state["unknown"] = true
	_rehash_full_player_replay(unknown_reward)
	var unknown_reward_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		unknown_reward,
		identity
	)
	_suite.assert_equal(
		unknown_reward_rejected.get("code"),
		&"FULL_PLAYER_REWARD_EFFECT_STATE_INVALID",
		"unknown passive-state fields fail closed after outer rehash"
	)

	var forged_modifier := replay.duplicate(true)
	var forged_live := (
		((forged_modifier["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["live_talent_state"] as Dictionary
	(forged_live["modifiers"] as Dictionary)["low_energy_threshold"] = 29
	forged_live["modifier_digest"] = ReplayRecorderScript.value_digest(forged_live["modifiers"])
	_rehash_full_player_replay(forged_modifier)
	var forged_modifier_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_modifier,
		identity
	)
	_suite.assert_equal(
		forged_modifier_rejected.get("code"),
		&"FULL_PLAYER_LIVE_TALENT_STATE_INVALID",
		"forged live modifier state fails closed after digest recomputation"
	)

	var changed_bounds := replay.duplicate(true)
	var changed_bounds_live := (
		((changed_bounds["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["live_talent_state"] as Dictionary
	var changed_definition := (changed_bounds_live["talent_definitions"] as Array)[0] as Dictionary
	(changed_definition["effects"] as Dictionary)["low_energy_regen_multiplier"] = -1.0
	changed_bounds_live["definitions_digest"] = ReplayRecorderScript.value_digest(
		changed_bounds_live["talent_definitions"]
	)
	_rehash_full_player_replay(changed_bounds)
	var changed_bounds_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		changed_bounds,
		identity
	)
	_suite.assert_equal(
		changed_bounds_rejected.get("code"),
		&"FULL_PLAYER_LIVE_TALENT_STATE_INVALID",
		"changed talent effect bounds fail closed after outer rehash"
	)

	var content_drift := replay.duplicate(true)
	var drift_live := (
		((content_drift["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["live_talent_state"] as Dictionary
	((drift_live["talent_definitions"] as Array)[0] as Dictionary)["name_key"] = "content.drift"
	drift_live["definitions_digest"] = ReplayRecorderScript.value_digest(
		drift_live["talent_definitions"]
	)
	_rehash_full_player_replay(content_drift)
	var drift_target := await _spawn_launch_player(&"wanderer", 5151)
	_suite.assert_true(drift_target.install_character_talent(talent_definition), "drift target installs authoritative talent content")
	_suite.assert_true(
		bool(drift_target.apply_reward(passive_definition).get("ok", false)),
		"drift target installs the matching passive state"
	)
	var drift_before: Dictionary = drift_target.full_player_replay_snapshot()
	var drift_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(drift_player.load_full_player_replay(
			content_drift,
			drift_target.full_player_replay_identity()
		).get("ok", false)),
		"semantically valid but drifted content reaches target validation"
	)
	_suite.assert_equal(
		drift_player.restore_full_player_frame(drift_target, 0).get("code"),
		&"FULL_PLAYER_REPLAY_RESTORE_REJECTED",
		"target authority rejects drifted live talent definitions"
	)
	_suite.assert_equal(
		drift_target.full_player_replay_snapshot(),
		drift_before,
		"content drift rejection leaves the target atomically unchanged"
	)
	await _free_player(drift_target)


func _test_active_item_round_trip_and_tamper_rejection() -> void:
	var source := await _spawn_launch_player(&"wanderer", 5201)
	var active_definition: Dictionary = _registry.call(
		"get_content",
		&"absolute_zero_device"
	)
	_suite.assert_true(
		bool(source.equip_active_item(active_definition).get("ok", false)),
		"Launch Replay fixture equips Absolute Zero Device"
	)
	var time_manager: Node = source.get_node("TimeManager")
	time_manager.set("energy", float(time_manager.get("max_energy")))
	var activated: Dictionary = source.activate_equipped_active_item({"is_boss_target": true})
	_suite.assert_true(bool(activated.get("ok", false)), "Launch Replay fixture activates its item")

	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5201).get("ok", false)),
		"active-item Launch Replay recording starts"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"active-item Launch Replay records the activated checkpoint"
	)
	_suite.assert_true(source.advance_action_frame({}), "active-item fixture advances one frame")
	var terminal: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			terminal,
			_frame_intents(int(terminal.get("frame", 0))),
			[]
		).get("ok", false)),
		"active-item Launch Replay records its terminal checkpoint"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "active-item Launch Replay finishes")
	var replay := (finished.get("replay", {}) as Dictionary).duplicate(true)
	var terminal_active := terminal.get("active_item_state", {}) as Dictionary
	_suite.assert_true(
		int(terminal_active.get("cooldown_end_frame", -1)) > int(terminal_active.get("current_frame", -1)),
		"recorded active item retains a non-zero cooldown"
	)
	_suite.assert_equal(terminal_active.get("next_token"), 2, "recorded active item retains token progress")
	_suite.assert_equal(terminal_active.get("generation"), 1, "recorded active item retains generation")
	_suite.assert_true(
		not (terminal_active.get("handler_state", {}) as Dictionary).is_empty(),
		"recorded active item retains handler state"
	)
	await _free_player(source)

	var target := await _spawn_launch_player(&"wanderer", 5201)
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(replay_player.load_full_player_replay(
			replay,
			target.full_player_replay_identity()
		).get("ok", false)),
		"active-item Launch Replay loads"
	)
	var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
	_suite.assert_true(
		bool(replayed.get("ok", false)),
		"active-item Launch Replay reaches terminal: %s" % str(replayed)
	)
	_suite.assert_equal(
		target.active_item_snapshot(),
		terminal_active,
		"active-item runtime restores cooldown, token, generation, handler, and receipts exactly"
	)
	await _free_player(target)

	for tamper: Dictionary in [
		{"field": "cooldown", "value": 1},
		{"field": "handler", "value": "forged_handler"},
		{"field": "token", "value": 1},
		{"field": "generation", "value": 99},
	]:
		var forged := replay.duplicate(true)
		var forged_active := (
			((forged["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
		)["active_item_state"] as Dictionary
		match str(tamper["field"]):
			"cooldown":
				forged_active["cooldown_end_frame"] = int(
					forged_active["cooldown_end_frame"]
				) + 1
			"handler":
				(forged_active["definition"] as Dictionary)["active_handler_id"] = tamper["value"]
			"token":
				forged_active["next_token"] = tamper["value"]
			"generation":
				forged_active["generation"] = tamper["value"]
		_rehash_full_player_replay(forged)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			forged,
			identity
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_ACTIVE_ITEM_STATE_INVALID",
			"forged active-item %s is rejected after authenticated Replay validation" % tamper["field"]
		)

	var atomic_target := await _spawn_launch_player(&"wanderer", 5201)
	var before: Dictionary = atomic_target.full_player_replay_snapshot()
	var forged_snapshot := initial.duplicate(true)
	var forged_snapshot_active := forged_snapshot["active_item_state"] as Dictionary
	(forged_snapshot_active["definition"] as Dictionary)["active_handler_id"] = "forged_handler"
	_suite.assert_true(
		not atomic_target.restore_full_player_replay_snapshot(forged_snapshot),
		"direct full-player restore rejects forged active-item state"
	)
	_suite.assert_equal(
		atomic_target.full_player_replay_snapshot(),
		before,
		"forged active-item restore leaves the target unchanged"
	)
	await _free_player(atomic_target)

	var rollback_replay := replay.duplicate(true)
	((rollback_replay["frames"] as Array)[1] as Dictionary)["snapshot"]["weapon_state"]["schema_version"] = 99
	_rehash_full_player_replay(rollback_replay)
	var rollback_target := await _spawn_launch_player(&"wanderer", 5201)
	_suite.assert_true(
		bool(rollback_target.equip_active_item(
			_registry.call("get_content", &"paradox_beacon")
		).get("ok", false)),
		"rollback fixture equips a distinct active item"
	)
	var rollback_before: Dictionary = rollback_target.full_player_replay_snapshot()
	var rollback_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(rollback_player.load_full_player_replay(
			rollback_replay,
			rollback_target.full_player_replay_identity()
		).get("ok", false)),
		"active-item rollback fixture loads before participant restore"
	)
	var failed_restore: Dictionary = rollback_player.restore_full_player_frame(rollback_target, 1)
	_suite.assert_equal(
		failed_restore.get("code"),
		&"FULL_PLAYER_REPLAY_RESTORE_REJECTED",
		"later participant rejection keeps the stable restore refusal code"
	)
	_suite.assert_equal(
		rollback_target.full_player_replay_snapshot(),
		rollback_before,
		"later participant rejection rolls active-item installation back atomically"
	)
	await _free_player(rollback_target)


func _test_legacy_launch_v4_and_v5_migrate_after_authentication() -> void:
	var source := await _spawn_launch_player(&"time_guardian", 5301)
	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5301).get("ok", false)),
		"legacy Launch fixture starts current recording"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"legacy Launch fixture records an empty active slot"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "legacy Launch fixture finishes")
	var current := (finished.get("replay", {}) as Dictionary).duplicate(true)
	var legacy_v4 := _legacy_launch_replay(current, 4)
	var legacy_v5 := _legacy_launch_replay(current, 5)
	var caller_copy_v4 := legacy_v4.duplicate(true)
	var caller_copy_v5 := legacy_v5.duplicate(true)
	var unauthenticated := legacy_v5.duplicate(true)
	var unauthenticated_player_state := (
		((unauthenticated["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["player_state"] as Dictionary
	unauthenticated_player_state["position"] = (
		unauthenticated_player_state.get("position", Vector2.ZERO) as Vector2
	) + Vector2.ONE
	var unauthenticated_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		unauthenticated,
		identity
	)
	_suite.assert_equal(
		unauthenticated_rejected.get("code"),
		&"FULL_PLAYER_FRAME_DIGEST_MISMATCH",
		"legacy Launch v5 content is authenticated before migration can refresh digests"
	)
	await _free_player(source)

	for legacy_case: Dictionary in [
		{"version": 4, "replay": legacy_v4, "copy": caller_copy_v4},
		{"version": 5, "replay": legacy_v5, "copy": caller_copy_v5},
	]:
		var target := await _spawn_launch_player(&"time_guardian", 5301)
		var replay_player = ReplayPlayerScript.new()
		var loaded: Dictionary = replay_player.load_full_player_replay(
			legacy_case["replay"],
			target.full_player_replay_identity()
		)
		_suite.assert_true(
			bool(loaded.get("ok", false)),
			"trusted legacy Launch v%d Replay migrates" % int(legacy_case["version"])
		)
		_suite.assert_equal(
			legacy_case["replay"],
			legacy_case["copy"],
			"legacy Launch v%d migration preserves caller-owned Replay" % int(legacy_case["version"])
		)
		var normalized := replay_player.full_player_replay_snapshot()
		_suite.assert_equal(normalized.get("schema_version"), 6, "legacy Launch root migrates to schema 6")
		var normalized_frame := (normalized.get("frames", []) as Array)[0] as Dictionary
		_suite.assert_equal(normalized_frame.get("schema_version"), 6, "legacy Launch frame migrates to schema 6")
		var normalized_snapshot := normalized_frame.get("snapshot", {}) as Dictionary
		_suite.assert_equal(normalized_snapshot.get("schema_version"), 6, "legacy Launch snapshot migrates to schema 6")
		_suite.assert_equal(
			normalized_snapshot.get("active_item_state"),
			_empty_active_item_state(),
			"legacy Launch snapshot receives the explicit empty active-item default"
		)
		_suite.assert_true(
			normalized_snapshot.get("reward_effect_state") is Dictionary
			and not (normalized_snapshot.get("reward_effect_state") as Dictionary).is_empty(),
			"legacy Launch snapshot receives a deterministic passive-state default"
		)
		_suite.assert_true(
			ReplayRecorderScript.validate_full_player_live_talent_state(
				normalized_snapshot.get("live_talent_state", {}),
				normalized_snapshot.get("identity", {})
			),
			"legacy Launch snapshot receives a verified live-talent seal"
		)
		_suite.assert_equal(
			normalized_frame.get("digest"),
			ReplayRecorderScript.full_player_frame_digest(normalized_frame),
			"legacy Launch migration refreshes the frame digest"
		)
		_suite.assert_equal(
			normalized.get("terminal_digest"),
			ReplayRecorderScript.full_player_terminal_digest(normalized),
			"legacy Launch migration refreshes the terminal digest"
		)
		await _free_player(target)


func _spawn_launch_player(character_id: StringName, seed_value: int) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(
		player.configure_loadout({
			"schema_version": 1,
			"milestone": "LAUNCH",
			"character_id": str(character_id),
			"character_profile": _registry.call(
				"resolve_character_runtime_profile", character_id, &"LAUNCH"
			),
			"character_talents": [],
			"weapon_id": "sword",
			"weapon_profile": _registry.call(
				"resolve_weapon_runtime_profile", &"sword", &"LAUNCH"
			),
			"enabled_time_skills": [&"stop", &"rewind"],
			"difficulty": "normal",
			"seed": seed_value,
		}),
		"%s Launch Replay fixture configures" % str(character_id)
	)
	return player


func _frame_intents(frame: int) -> Dictionary:
	return {
		"dash": [],
		"time": [],
		"weapon": [],
		"character": [],
		"movement": Vector2.ZERO,
		"aim": Vector2.RIGHT,
		"meta": {
			"source": "character_runtime_replay_test",
			"target_frame": frame,
			"frame": frame,
		},
	}


func _empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


func _legacy_launch_replay(current: Dictionary, version: int) -> Dictionary:
	var legacy := current.duplicate(true)
	legacy["schema_version"] = version
	for frame_value: Variant in legacy.get("frames", []) as Array:
		var frame := frame_value as Dictionary
		frame["schema_version"] = version
		var snapshot := frame.get("snapshot", {}) as Dictionary
		snapshot["schema_version"] = version
		snapshot.erase("reward_effect_state")
		snapshot.erase("live_talent_state")
		if version == 4:
			snapshot.erase("active_item_state")
	_rehash_full_player_replay(legacy)
	return legacy


func _rehash_full_player_replay(replay: Dictionary) -> void:
	for frame_value: Variant in replay.get("frames", []) as Array:
		var frame := frame_value as Dictionary
		frame["digest"] = ReplayRecorderScript.full_player_frame_digest(frame)
	var frames := replay.get("frames", []) as Array
	if not frames.is_empty():
		replay["terminal_snapshot_digest"] = ReplayRecorderScript.value_digest(
			(frames[-1] as Dictionary).get("snapshot", {})
		)
	replay["terminal_digest"] = ReplayRecorderScript.full_player_terminal_digest(replay)


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
