extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Binding := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Library := preload("res://scripts/replay/player_replay_library.gd")
const Scope := preload("res://scripts/player/player_scene_scope.gd")
const HostileBridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var source := await Fixture.spawn(self, registry, suite, "history-recording", 789, true)
	var recorder := Recorder.new()
	suite.assert_true(recorder.start_full_player_recording(source.full_player_replay_identity(), 789).ok, "history recording starts from actual launch Player")
	var facts: Array[Dictionary] = []
	var committed_facts: Array[Dictionary] = []
	var observer := func(ability: StringName, token: int, generation: int, frame: int, run_id: StringName, context: Dictionary): facts.append({"ability_id": ability, "token": token, "generation": generation, "frame": frame, "run_id": run_id, "context": context.duplicate(true)})
	var bus := Scope.event_bus(source)
	bus.time_skill_committed.connect(observer)
	for frame: int in range(66):
		var intents := {"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.RIGHT, "aim": Vector2.RIGHT, "meta": {}}
		if frame == 64:
			intents.time.append({"id": "time_slot_2", "edge": "pressed", "mode": "press", "held_frames": 0})
		if frame > 0:
			suite.assert_true(source.advance_action_frame(intents), "actual Player history frame advances")
		suite.assert_true(recorder.record_full_player_frame(source.full_player_replay_snapshot(), intents, facts).ok, "actual rewind boundary records")
		committed_facts.append_array(facts.duplicate(true))
		facts.clear()
	bus.time_skill_committed.disconnect(observer)
	var finished: Dictionary = recorder.finish_full_player_recording()
	suite.assert_true(finished.ok, "actual history recording seals")
	if not finished.ok:
		source.get_parent().queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var replay: Dictionary = finished.replay
	suite.assert_true(committed_facts.size() == 1 and str(committed_facts[0].ability_id) == "rewind", "actual Rewind commits once through native TimeManager")
	suite.assert_true(replay.frames[65].snapshot.player_state.position.x < replay.frames[63].snapshot.player_state.position.x, "actual Rewind restores sampled native position")
	suite.assert_equal(replay.frames[65].snapshot.weapon_state.generation, replay.frames[63].snapshot.weapon_state.generation + 1, "actual Rewind invalidates pending native weapon generation")
	suite.assert_true(source.time_manager.world_payload_authority == source.world_payload_authority, "actual Rewind uses native World authority")
	var library := Library.new()
	add_child(library)
	suite.assert_true(library.configure(OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("history_library"), "0.4.0-dev", Binding.snapshot(registry), "slot_1", "base").ok, "history library configures")
	var stored := library.store(replay)
	suite.assert_true(stored.ok, "actual history replay validates and archives")
	if stored.ok:
		suite.assert_true(library.select(stored.context.id).ok, "history viewer admits native Player")
		for index: int in [65, 0, 64, 63, 65]:
			var sought: Dictionary = library.seek(index)
			suite.assert_true(sought.ok, "seek crosses committed history in both directions: %d %s" % [index, str(sought)])
			if sought.ok:
				suite.assert_true(library.current_player().full_player_replay_snapshot() == replay.frames[index].snapshot, "cross-history seek restores exact native snapshot")
		var target := library.current_player()
		_test_replay_health_pair(suite, target, replay.frames[0].snapshot, replay.frames[65].snapshot)
		var before: Dictionary = target.full_player_replay_snapshot()
		target.process_mode = Node.PROCESS_MODE_INHERIT
		suite.assert_true(not library.seek(0).ok, "enabled target cannot seek historical snapshots")
		suite.assert_true(target.full_player_replay_snapshot() == before, "refused enabled seek preserves state")
		target.process_mode = Node.PROCESS_MODE_DISABLED
	library.queue_free()
	source.get_parent().queue_free()
	await get_tree().process_frame
	await _test_payload_history_admission(suite, registry)
	suite.finish(get_tree())


func _test_payload_history_admission(suite: RefCounted, registry: RefCounted) -> void:
	var player := await Fixture.spawn(self, registry, suite, "viewer-history", 987, true)
	var authority: Node = player.world_payload_authority
	var before: Dictionary = authority.replay_snapshot()
	suite.assert_true(authority.invalidate_generation(player.current_run_id(), 700, &"history_fixture").ok, "native authority records real lifecycle invalidation")
	var after: Dictionary = authority.replay_snapshot()
	suite.assert_true(before.invalidated_generations != after.invalidated_generations, "native invalidation changes the closed history")
	suite.assert_true(authority.can_restore_replay_snapshot(before), "admitted disabled viewer preflights older history")
	suite.assert_true(authority.restore_replay_snapshot(before) and authority.replay_snapshot() == before, "admitted viewer direct restore installs exact older history")
	suite.assert_true(authority.restore_replay_snapshot(after) and authority.replay_snapshot() == after, "admitted viewer direct restore moves history forward")
	var ticket: Dictionary = authority.begin_transaction_restore(before)
	suite.assert_true(not ticket.is_empty() and authority.replay_snapshot() == before, "admitted viewer transactional restore stages older history")
	if not ticket.is_empty():
		suite.assert_true(authority.rollback_transaction_restore(ticket) and authority.replay_snapshot() == after, "viewer history rollback restores exact prior state")
	ticket = authority.begin_transaction_restore(before)
	suite.assert_true(not ticket.is_empty() and authority.commit_transaction_restore(ticket), "viewer history transaction commits exact older state")
	suite.assert_true(authority.restore_replay_snapshot(after), "viewer history resets before refusal matrix")
	player.process_mode = Node.PROCESS_MODE_INHERIT
	_assert_history_refused(suite, authority, before, "enabled Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(true)
	_assert_history_refused(suite, authority, before, "physics-enabled Player")
	player.set_physics_process(false)
	player.set("_hostile_frame_participant", HostileBridge.new())
	_assert_history_refused(suite, authority, before, "Player with hostile participant")
	player.set("_hostile_frame_participant", null)
	var world: SubViewport = player.get_parent()
	var isolated_world := world.world_2d
	world.world_2d = get_viewport().world_2d
	_assert_history_refused(suite, authority, before, "shared production physics world")
	world.world_2d = isolated_world
	suite.assert_true(authority.can_restore_replay_snapshot(before), "restoring every admission condition enables historical seek")
	var live := await Fixture.spawn(self, registry, suite, "live-history", 987)
	var live_authority: Node = live.world_payload_authority
	var live_before: Dictionary = live_authority.replay_snapshot()
	suite.assert_true(live_authority.invalidate_generation(live.current_run_id(), 700, &"history_fixture").ok, "production authority commits same real history boundary")
	_assert_history_refused(suite, live_authority, live_before, "production Player")
	live.reparent(world)
	suite.assert_true(not world.owns_player(live), "reparented global Player is not admitted by ReplayWorld")
	_assert_history_refused(suite, live_authority, live_before, "reparented unadmitted Player")
	world.queue_free()
	await get_tree().process_frame


func _assert_history_refused(suite: RefCounted, authority: Node, historical: Dictionary, label: String) -> void:
	var before: Dictionary = authority.replay_snapshot()
	suite.assert_true(not authority.can_restore_replay_snapshot(historical), label + " refuses history preflight")
	suite.assert_true(not authority.restore_replay_snapshot(historical), label + " refuses direct history restore")
	suite.assert_true(authority.begin_transaction_restore(historical).is_empty(), label + " refuses transactional history restore")
	suite.assert_equal(authority.replay_snapshot(), before, label + " refusal preserves exact authority state")


func _test_replay_health_pair(suite: RefCounted, player: Node, early: Dictionary, protected: Dictionary) -> void:
	var health: Node = player.health
	var state_before: Dictionary = health.runtime_state_snapshot()
	var reward_before: Dictionary = health.reward_effect_snapshot()
	var invulnerability_before: Dictionary = health.invulnerability_replay_snapshot()
	var target_health: Dictionary = protected.reward_effect_state.health
	var target_invulnerability: Dictionary = protected.player_state.invulnerability_state
	suite.assert_true(not target_invulnerability.non_reward_tokens.is_empty(), "real Rewind creates native non-reward protection")
	suite.assert_true(not health.can_restore_reward_effect_snapshot(early.reward_effect_state.health), "ordinary reward restore preserves current Rewind protection tokens")
	suite.assert_true(health.can_restore_full_replay_reward_snapshot(early.reward_effect_state.health, early.player_state.invulnerability_state), "full replay preflights consistent historical Health pair")
	var mismatched := target_health.duplicate(true)
	mismatched.invulnerability_token += 1
	suite.assert_true(not health.can_restore_full_replay_reward_snapshot(mismatched, target_invulnerability), "paired replay rejects differing token ceilings")
	suite.assert_true(not health.restore_full_replay_reward_snapshot(mismatched, target_invulnerability), "mismatched pair restore refuses before mutation")
	var overlap := target_health.duplicate(true)
	var token: int = target_invulnerability.non_reward_tokens[0]
	overlap.reward_invulnerability_tokens = [token]
	overlap.reward_invulnerability_remaining = {str(token): 3}
	overlap.invulnerable = true
	suite.assert_true(not health.can_restore_full_replay_reward_snapshot(overlap, target_invulnerability), "paired replay rejects reward and non-reward token overlap")
	suite.assert_true(not health.restore_full_replay_reward_snapshot(overlap, target_invulnerability), "overlapping pair restore refuses before mutation")
	suite.assert_equal(health.runtime_state_snapshot(), state_before, "invalid pairs preserve actual Health ledger and HP")
	suite.assert_equal(health.reward_effect_snapshot(), reward_before, "invalid pairs preserve reward-owned protection")
	suite.assert_equal(health.invulnerability_replay_snapshot(), invulnerability_before, "invalid pairs preserve non-reward protection frames")
	var reward_only_invulnerability := target_invulnerability.duplicate(true)
	reward_only_invulnerability.non_reward_tokens = []
	reward_only_invulnerability.non_reward_remaining_frames = {}
	suite.assert_true(health.restore_full_replay_reward_snapshot(overlap, reward_only_invulnerability), "consistent reward-owned protection installs")
	suite.assert_true(player.restore_full_player_replay_snapshot(protected), "full replay may change the same token from reward-owned to Rewind-owned protection")
	suite.assert_equal(player.full_player_replay_snapshot(), protected, "cross-owner protection seek restores exact full Player state")
