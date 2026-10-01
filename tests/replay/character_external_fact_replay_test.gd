extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const M1_SCHEMA_VERSION := 2
const LAUNCH_SCHEMA_VERSION := 5

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
	_suite.assert_true(
		not report.call("has_blocking_errors"),
		"Character external-fact Replay loads the Base Pack"
	)
	if not report.call("has_blocking_errors"):
		await _test_gameplay_rewind_preserves_committed_world_payloads()
		await _test_replay_checkpoint_reconstructs_recorded_world_descriptors()
		await _test_reset_and_loadout_replacement_invalidate_world_generations()
		await _test_forged_cross_domain_roots_reject_atomically()
		await _test_launch_and_m1_replay_identities_are_strictly_isolated()
	_suite.finish(get_tree())


func _test_gameplay_rewind_preserves_committed_world_payloads() -> void:
	var player := await _spawn_launch_player(&"primordial_knight", 7101)
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	_configure_free_rift_and_rewind(manager)

	recorder.call("clear_snapshots")
	player.global_position = Vector2(24.0, 32.0)
	recorder.call("_record_snapshot")
	player.global_position = Vector2(240.0, 160.0)

	_suite.assert_true(
		manager.call("try_time_rift", Vector2(96.0, 64.0)),
		"Gameplay Rewind fixture commits the payload that must survive"
	)
	var first_descriptor := _last_world_descriptor(authority)
	var first_payload_id := StringName(str(first_descriptor.get("payload_id", "")))
	var first_node: Node = authority.call("payload_node", first_payload_id)
	_suite.assert_true(
		first_node != null,
		"Gameplay Rewind fixture exposes the committed payload Node"
	)

	_suite.assert_true(
		manager.call("try_time_rift", Vector2(192.0, 64.0)),
		"Gameplay Rewind fixture commits a payload that will be consumed"
	)
	var consumed_descriptor := _last_world_descriptor(authority)
	var consumed_payload_id := StringName(str(consumed_descriptor.get("payload_id", "")))
	_suite.assert_true(
		bool((authority.call(
			"retire_payload",
			consumed_payload_id,
			StringName(str(consumed_descriptor.get("run_id", ""))),
			int(consumed_descriptor.get("owner_character_generation", 0)),
			&"character_external_fact_consumed"
		) as Dictionary).get("ok", false)),
		"Gameplay Rewind fixture consumes the second payload before rewind"
	)
	_suite.assert_true(
		not authority.call("contains", consumed_payload_id),
		"Consumed payload is absent before Gameplay Rewind"
	)
	var world_before: Dictionary = authority.call("replay_snapshot")

	_suite.assert_true(
		manager.call("try_rewind", recorder),
		"Gameplay Rewind commits through the production transaction"
	)
	_suite.assert_equal(
		authority.call("replay_snapshot"),
		world_before,
		"Gameplay Rewind preserves the exact committed descriptor set"
	)
	_suite.assert_true(
		authority.call("payload_node", first_payload_id) == first_node,
		"Gameplay Rewind preserves the exact committed payload Node"
	)
	_suite.assert_true(
		not authority.call("contains", consumed_payload_id),
		"Gameplay Rewind does not recreate a previously consumed payload"
	)
	await _free_player(player)


func _test_replay_checkpoint_reconstructs_recorded_world_descriptors() -> void:
	var player := await _spawn_launch_player(&"primordial_knight", 7102)
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	_configure_free_rift_and_rewind(manager)

	_suite.assert_true(
		manager.call("try_time_rift", Vector2(112.0, 80.0)),
		"Replay reconstruction fixture commits its recorded payload"
	)
	var checkpoint: Dictionary = player.call("full_player_replay_snapshot")
	var recorded_world := (
		checkpoint.get("world_payload_state", {}) as Dictionary
	).duplicate(true)
	var recorded_descriptor := _last_world_descriptor(authority)
	var recorded_payload_id := StringName(str(recorded_descriptor.get("payload_id", "")))
	var recorded_node: Node = authority.call("payload_node", recorded_payload_id)

	_suite.assert_true(
		bool((authority.call(
			"retire_payload",
			recorded_payload_id,
			StringName(str(recorded_descriptor.get("run_id", ""))),
			int(recorded_descriptor.get("owner_character_generation", 0)),
			&"checkpoint_generation_consumed"
		) as Dictionary).get("ok", false)),
		"Replay reconstruction fixture deletes the recorded payload generation"
	)
	_suite.assert_true(
		manager.call("try_time_rift", Vector2(256.0, 80.0)),
		"Replay reconstruction fixture diverges with a later payload generation"
	)
	var divergent_descriptor := _last_world_descriptor(authority)
	var divergent_payload_id := StringName(str(divergent_descriptor.get("payload_id", "")))
	_suite.assert_true(
		divergent_payload_id != recorded_payload_id,
		"Replay reconstruction fixture owns a distinct divergent payload identity"
	)

	_suite.assert_true(
		player.call("restore_full_player_replay_snapshot", checkpoint),
		"Full Player Replay checkpoint restores after the recorded payload was deleted"
	)
	_suite.assert_equal(
		authority.call("replay_snapshot"),
		recorded_world,
		"Replay checkpoint reconstructs the exact recorded descriptor root"
	)
	var reconstructed_node: Node = authority.call("payload_node", recorded_payload_id)
	_suite.assert_true(
		reconstructed_node != null and reconstructed_node != recorded_node,
		"Replay checkpoint reconstructs a fresh Node for the recorded stable payload"
	)
	_suite.assert_true(
		not authority.call("contains", divergent_payload_id),
		"Replay checkpoint deletes payloads created after the checkpoint"
	)
	await _free_player(player)


func _test_reset_and_loadout_replacement_invalidate_world_generations() -> void:
	var player := await _spawn_launch_player(&"primordial_knight", 7103)
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	_configure_free_rift_and_rewind(manager)

	_suite.assert_true(
		manager.call("try_time_rift", Vector2(80.0, 80.0)),
		"Runtime reset invalidation fixture commits a payload"
	)
	var reset_descriptor := _last_world_descriptor(authority)
	var reset_run := StringName(str(reset_descriptor.get("run_id", "")))
	var reset_generation := int(reset_descriptor.get("owner_character_generation", 0))
	var reset_payload_id := StringName(str(reset_descriptor.get("payload_id", "")))
	_suite.assert_true(
		player.call("reset_runtime_state"),
		"Runtime reset invalidates the outgoing world generation"
	)
	_assert_stale_world_generation(
		authority,
		reset_descriptor,
		reset_run,
		reset_generation,
		reset_payload_id,
		"runtime reset"
	)

	_configure_free_rift_and_rewind(manager)
	_suite.assert_true(
		manager.call("try_time_rift", Vector2(160.0, 80.0)),
		"Loadout replacement invalidation fixture commits a payload"
	)
	var loadout_descriptor := _last_world_descriptor(authority)
	var loadout_run := StringName(str(loadout_descriptor.get("run_id", "")))
	var loadout_generation := int(loadout_descriptor.get("owner_character_generation", 0))
	var loadout_payload_id := StringName(str(loadout_descriptor.get("payload_id", "")))
	_suite.assert_true(
		player.call("configure_loadout", _launch_config(&"time_guardian", 7104)),
		"Loadout replacement installs a different certified character"
	)
	_assert_stale_world_generation(
		authority,
		loadout_descriptor,
		loadout_run,
		loadout_generation,
		loadout_payload_id,
		"loadout replacement"
	)
	await _free_player(player)


func _test_forged_cross_domain_roots_reject_atomically() -> void:
	var player := await _spawn_launch_player(&"void_walker", 7105)
	var health: Node = player.get_node("HealthComponent")
	var loss: RefCounted = health.call(
		"lose_health_irreversible",
		7.0,
		&"void_devour",
		41,
		9
	)
	_suite.assert_true(
		loss != null,
		"Forgery fixture records one irreversible HP external fact"
	)
	var before: Dictionary = player.call("full_player_replay_snapshot")
	_suite.assert_true(not before.is_empty(), "Forgery fixture captures a complete snapshot")

	var forged_ledger := before.duplicate(true)
	var forged_ledger_state := forged_ledger["health_state"] as Dictionary
	var forged_ledger_root := forged_ledger_state["ledger"] as Dictionary
	forged_ledger_root["irreversible_hp_loss_total"] = (
		float(forged_ledger_root["irreversible_hp_loss_total"]) + 1.0
	)
	_assert_restore_rejected_atomically(
		player,
		forged_ledger,
		before,
		"forged irreversible HP ledger"
	)

	var forged_token := before.duplicate(true)
	var token_ledger := ((forged_token["health_state"] as Dictionary)["ledger"] as Dictionary)
	var token_claims := token_ledger["claims"] as Dictionary
	var token_claim_key: Variant = token_claims.keys()[0]
	(token_claims[token_claim_key] as Dictionary)["source_token"] = 42
	_assert_restore_rejected_atomically(
		player,
		forged_token,
		before,
		"forged irreversible claim token"
	)

	var forged_generation := before.duplicate(true)
	var generation_ledger := (
		(forged_generation["health_state"] as Dictionary)["ledger"] as Dictionary
	)
	var generation_claims := generation_ledger["claims"] as Dictionary
	var generation_claim_key: Variant = generation_claims.keys()[0]
	(generation_claims[generation_claim_key] as Dictionary)["source_generation"] = 10
	_assert_restore_rejected_atomically(
		player,
		forged_generation,
		before,
		"forged irreversible claim generation"
	)

	var forged_frame := before.duplicate(true)
	forged_frame["frame"] = int(forged_frame["frame"]) + 1
	_assert_restore_rejected_atomically(
		player,
		forged_frame,
		before,
		"forged cross-domain frame"
	)

	var forged_run := before.duplicate(true)
	(forged_run["identity"] as Dictionary)["run_id"] = "foreign-run"
	_assert_restore_rejected_atomically(
		player,
		forged_run,
		before,
		"forged Replay run identity"
	)
	await _free_player(player)


func _test_launch_and_m1_replay_identities_are_strictly_isolated() -> void:
	var m1_player := await _spawn_m1_player()
	var launch_player := await _spawn_launch_player(&"wanderer", 7106)
	var m1_replay := _record_single_checkpoint_replay(m1_player, 7106)
	var launch_replay := _record_single_checkpoint_replay(launch_player, 7107)

	_assert_replay_schema(m1_replay, M1_SCHEMA_VERSION, "certified Wanderer M1")
	_assert_replay_schema(launch_replay, LAUNCH_SCHEMA_VERSION, "Wanderer Launch")
	_suite.assert_true(
		str((m1_replay.get("identity", {}) as Dictionary).get("character_profile_id", ""))
		!= str((launch_replay.get("identity", {}) as Dictionary).get("character_profile_id", "")),
		"M1 and Launch use distinct certified character profile identities"
	)

	var launch_on_m1: Dictionary = ReplayPlayerScript.new().call(
		"load_full_player_replay",
		launch_replay,
		m1_player.call("full_player_replay_identity")
	)
	_suite.assert_equal(
		launch_on_m1.get("code"),
		&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH",
		"Launch schema 5 Replay cannot load into the M1 schema 2 identity"
	)
	var m1_on_launch: Dictionary = ReplayPlayerScript.new().call(
		"load_full_player_replay",
		m1_replay,
		launch_player.call("full_player_replay_identity")
	)
	_suite.assert_equal(
		m1_on_launch.get("code"),
		&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH",
		"M1 schema 2 Replay cannot load into the Launch schema 5 identity"
	)

	var m1_before: Dictionary = m1_player.call("full_player_replay_snapshot")
	var launch_snapshot := (
		((launch_replay.get("frames", []) as Array)[0] as Dictionary).get("snapshot", {})
		as Dictionary
	)
	_suite.assert_true(
		not m1_player.call("restore_full_player_replay_snapshot", launch_snapshot),
		"Direct checkpoint restore also rejects Launch-to-M1 profile drift"
	)
	_suite.assert_equal(
		m1_player.call("full_player_replay_snapshot"),
		m1_before,
		"Cross-schema direct checkpoint rejection is atomic"
	)
	await _free_player(launch_player)
	await _free_player(m1_player)


func _assert_stale_world_generation(
	authority: Node,
	descriptor: Dictionary,
	run_id: StringName,
	generation: int,
	payload_id: StringName,
	label: String
) -> void:
	_suite.assert_true(
		authority.call("generation_is_invalidated", run_id, generation),
		"%s installs a permanent outgoing-generation tombstone" % label
	)
	_suite.assert_true(
		not authority.call("contains", payload_id),
		"%s removes outgoing-generation payloads" % label
	)
	var stale_commit := authority.call("commit_payload", descriptor) as Dictionary
	_suite.assert_equal(
		stale_commit.get("code"),
		&"INVALIDATED_GENERATION",
		"%s rejects a late commit from the stale generation" % label
	)
	var stale_callback := authority.call(
		"retire_payload",
		payload_id,
		run_id,
		generation,
		&"late_character_callback"
	) as Dictionary
	_suite.assert_equal(
		stale_callback.get("code"),
		&"STALE_CALLBACK",
		"%s rejects a late callback from the stale generation" % label
	)


func _assert_restore_rejected_atomically(
	player: Node,
	forged: Dictionary,
	before: Dictionary,
	label: String
) -> void:
	_suite.assert_true(
		not player.call("restore_full_player_replay_snapshot", forged),
		"%s is rejected" % label
	)
	_suite.assert_equal(
		player.call("full_player_replay_snapshot"),
		before,
		"%s rejection leaves every participant unchanged" % label
	)


func _assert_replay_schema(replay: Dictionary, expected: int, label: String) -> void:
	_suite.assert_equal(
		int(replay.get("schema_version", 0)),
		expected,
		"%s Replay root uses schema %d" % [label, expected]
	)
	var frames := replay.get("frames", []) as Array
	_suite.assert_equal(frames.size(), 1, "%s Replay owns one checkpoint" % label)
	if frames.size() != 1:
		return
	var frame := frames[0] as Dictionary
	_suite.assert_equal(
		int(frame.get("schema_version", 0)),
		expected,
		"%s Replay frame uses schema %d" % [label, expected]
	)
	_suite.assert_equal(
		int((frame.get("snapshot", {}) as Dictionary).get("schema_version", 0)),
		expected,
		"%s Replay snapshot uses schema %d" % [label, expected]
	)


func _record_single_checkpoint_replay(player: Node, seed_value: int) -> Dictionary:
	var recorder = ReplayRecorderScript.new()
	var identity: Dictionary = player.call("full_player_replay_identity")
	var snapshot: Dictionary = player.call("full_player_replay_snapshot")
	_suite.assert_true(
		bool(recorder.call("start_full_player_recording", identity, seed_value).get("ok", false)),
		"Single-checkpoint Replay recording starts"
	)
	_suite.assert_true(
		bool(recorder.call(
			"record_full_player_frame",
			snapshot,
			_frame_intents(int(snapshot.get("frame", 0))),
			[]
		).get("ok", false)),
		"Single-checkpoint Replay records"
	)
	var finished := recorder.call("finish_full_player_recording") as Dictionary
	_suite.assert_true(
		bool(finished.get("ok", false)),
		"Single-checkpoint Replay finishes"
	)
	return (finished.get("replay", {}) as Dictionary).duplicate(true)


func _last_world_descriptor(authority: Node) -> Dictionary:
	var snapshot := authority.call("replay_snapshot") as Dictionary
	var descriptors := snapshot.get("descriptors", []) as Array
	if descriptors.is_empty():
		return {}
	return (descriptors[-1] as Dictionary).duplicate(true)


func _configure_free_rift_and_rewind(manager: Node) -> void:
	manager.set("time_rift_cost", 0.0)
	manager.set("time_rift_cooldown", 0.0)
	manager.set("rewind_cost", 0.0)
	manager.set("rewind_cooldown", 0.0)
	manager.set("rewind_self_damage", 0.0)
	manager.set("rewind_heal", 0.0)


func _spawn_launch_player(character_id: StringName, seed_value: int) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(
		player.call("configure_loadout", _launch_config(character_id, seed_value)),
		"%s external-fact Replay fixture configures" % str(character_id)
	)
	return player


func _spawn_m1_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_equal(
		str((player.call("full_player_replay_identity") as Dictionary).get(
			"character_profile_id",
			""
		)),
		"wanderer_m1_v1",
		"Default Player fixture retains the certified Wanderer M1 profile"
	)
	return player


func _launch_config(character_id: StringName, seed_value: int) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": str(character_id),
		"character_profile": _registry.call(
			"resolve_character_runtime_profile",
			character_id,
			&"LAUNCH"
		),
		"character_talents": [],
		"weapon_id": "sword",
		"weapon_profile": _registry.call(
			"resolve_weapon_runtime_profile",
			&"sword",
			&"LAUNCH"
		),
		"enabled_time_skills": [&"rift", &"rewind"],
		"difficulty": "normal",
		"seed": seed_value,
	}


func _frame_intents(frame: int) -> Dictionary:
	return {
		"dash": [],
		"time": [],
		"weapon": [],
		"character": [],
		"movement": Vector2.ZERO,
		"aim": Vector2.RIGHT,
		"meta": {
			"source": "character_external_fact_replay_test",
			"target_frame": frame,
			"frame": frame,
		},
	}


func _free_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var health: Node = player.get_node_or_null("HealthComponent")
	if (
		health != null
		and not (health.get("_active_invulnerability_tokens") as Dictionary).is_empty()
	):
		await get_tree().create_timer(0.55).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
