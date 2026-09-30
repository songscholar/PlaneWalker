extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class RejectingCharacterRuntime:
	extends RefCounted

	var last_runtime_frame: int = -1
	var revision: int = 0
	var reject_next_frame: bool = false

	func advance_frame(context: Dictionary) -> Variant:
		last_runtime_frame = int(context.get("runtime_frame", -1))
		revision += 1
		if reject_next_frame:
			return {"malformed": true}
		return []

	func snapshot() -> Dictionary:
		return {
			"last_runtime_frame": last_runtime_frame,
			"revision": revision,
		}

	func can_restore_snapshot(value: Dictionary) -> bool:
		return (
			value.size() == 2
			and typeof(value.get("last_runtime_frame")) == TYPE_INT
			and int(value.get("last_runtime_frame", -2)) >= -1
			and typeof(value.get("revision")) == TYPE_INT
			and int(value.get("revision", -1)) >= 0
		)

	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		last_runtime_frame = int(value["last_runtime_frame"])
		revision = int(value["revision"])
		return snapshot() == value

	func reset_runtime_state(_reason: StringName) -> void:
		last_runtime_frame = -1
		revision += 1


class FrameOrderCharacterRuntime:
	extends RefCounted

	var time_manager: Node
	var last_runtime_frame: int = -1
	var revision: int = 0
	var observed_time_manager_frame: int = -1

	func advance_frame(context: Dictionary) -> Array[Dictionary]:
		observed_time_manager_frame = int(time_manager.replay_snapshot().get("runtime_frame", -1))
		last_runtime_frame = int(context.get("runtime_frame", -1))
		revision += 1
		return []

	func snapshot() -> Dictionary:
		return {
			"last_runtime_frame": last_runtime_frame,
			"revision": revision,
			"observed_time_manager_frame": observed_time_manager_frame,
		}

	func can_restore_snapshot(value: Dictionary) -> bool:
		return (
			value.size() == 3
			and typeof(value.get("last_runtime_frame")) == TYPE_INT
			and typeof(value.get("revision")) == TYPE_INT
			and typeof(value.get("observed_time_manager_frame")) == TYPE_INT
		)

	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		last_runtime_frame = int(value["last_runtime_frame"])
		revision = int(value["revision"])
		observed_time_manager_frame = int(value["observed_time_manager_frame"])
		return snapshot() == value

	func reset_runtime_state(_reason: StringName) -> void:
		last_runtime_frame = -1
		observed_time_manager_frame = -1
		revision += 1


class RewindOrderProbe:
	extends Node

	var world_payload_authority: Node
	var samples_per_second: float = 10.0
	var record_seconds: float = 5.0
	var _snapshots: Array[Dictionary] = []
	var _sample_timer: float = 0.0
	var _history_revision: int = 0
	var _next_sample_sequence: int = 1
	var _last_runtime_frame: int = 0
	var _active_transaction: Dictionary = {}
	var observed_world_frame: int = -2
	var reject_next_frame: bool = false
	var late_frame_hook: Callable = Callable()

	func advance_frame(runtime_frame: int) -> bool:
		observed_world_frame = int(
			world_payload_authority.replay_snapshot().get("last_runtime_frame", -2)
		)
		_last_runtime_frame = runtime_frame
		if late_frame_hook.is_valid():
			var hook := late_frame_hook
			late_frame_hook = Callable()
			hook.call()
		return not reject_next_frame

	func has_snapshot() -> bool:
		return not _snapshots.is_empty()


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_character_rejection_rolls_back_the_complete_frame()
	await _test_fixed_frame_participants_observe_authoritative_order()
	await _test_rewind_rejection_restores_active_world_payload_exactly()
	await _test_event_commit_preflight_is_observer_atomic()
	await _test_time_stop_health_publication_is_discarded_on_late_rejection()
	await _test_world_commit_failure_discards_finalized_publications()
	await _test_time_stop_health_publication_occurs_after_world_commit()
	await _test_nonempty_time_and_weapon_intents_match_live_and_replay()
	await _test_full_player_replay_restores_movement_aim_and_health()
	await _test_player_timers_advance_once_per_fixed_frame()
	await _test_nonzero_p11_checkpoint_reanchors_every_fixed_frame_clock()
	await _test_active_rift_marks_the_p11_capture_epoch_unsupported()
	await _test_death_invalidates_without_advancing_character_generation()
	await _test_run_replacement_preflights_before_generation_invalidation()
	await _test_reused_run_skips_every_tombstoned_generation()
	await _test_loadout_and_reset_reject_locked_world_without_partial_state()
	await _test_loadout_rewind_failure_restores_every_runtime_participant()
	_suite.finish(get_tree())


func _test_character_rejection_rolls_back_the_complete_frame() -> void:
	var player := await _spawn_player()
	var runtime := RejectingCharacterRuntime.new()
	_suite.assert_true(
		player.character_action_coordinator.configure(runtime),
		"rejecting character runtime configures"
	)
	runtime.reject_next_frame = true
	var before := _complete_frame_snapshot(player)
	_suite.assert_true(
		not bool(player.call("advance_action_frame", {"source": "character_rejection"})),
		"authoritative frame reports rejection"
	)
	_suite.assert_equal(
		_complete_frame_snapshot(player),
		before,
		"character rejection rolls Player, Time, Action, Character, Weapon, World, and Rewind clocks back exactly"
	)
	runtime.reject_next_frame = false
	_suite.assert_true(
		bool(player.call("advance_action_frame", {"source": "recovery"})),
		"the next valid frame still commits as frame one"
	)
	_assert_all_clocks(player, 1, "post-rejection recovery")
	await _free_player(player)


func _test_fixed_frame_participants_observe_authoritative_order() -> void:
	var player := await _spawn_player()
	var character_runtime := FrameOrderCharacterRuntime.new()
	character_runtime.time_manager = player.get_node("TimeManager")
	_suite.assert_true(
		player.character_action_coordinator.configure(character_runtime),
		"frame-order character probe configures"
	)
	var rewind_probe := RewindOrderProbe.new()
	rewind_probe.world_payload_authority = player.get_node("WorldPayloadAuthority")
	add_child(rewind_probe)
	player.rewind_recorder = rewind_probe

	_suite.assert_true(
		bool(player.call("advance_action_frame", {"source": "participant_order_probe"})),
		"participant-order probe frame commits"
	)
	_suite.assert_equal(
		character_runtime.observed_time_manager_frame,
		character_runtime.last_runtime_frame,
		"Character runtime observes TimeManager already advanced to its context frame"
	)
	_suite.assert_equal(
		rewind_probe.observed_world_frame,
		int(player.get_node("WorldPayloadAuthority").replay_snapshot().get("last_runtime_frame", -2)),
		"Rewind sampling observes WorldPayloadAuthority already advanced to the same frame"
	)
	rewind_probe.queue_free()
	await _free_player(player)


func _test_rewind_rejection_restores_active_world_payload_exactly() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
	}), "world rollback fixture configures Rift")
	var manager: Node = player.get_node("TimeManager")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	_suite.assert_true(manager.try_time_rift(Vector2(96.0, 64.0)), "world rollback fixture commits a Rift")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var descriptor_values := authority.replay_snapshot().get("descriptors", []) as Array
	_suite.assert_equal(descriptor_values.size(), 1, "fixture owns exactly one authoritative Rift")
	var payload_id := StringName(str((descriptor_values[0] as Dictionary).get("payload_id", "")))
	var payload_node: Node = authority.payload_node(payload_id)
	var authority_before: Dictionary = authority.replay_snapshot()
	var node_before: Dictionary = payload_node.call("world_payload_frame_snapshot")

	var rejecting_rewind := RewindOrderProbe.new()
	rejecting_rewind.world_payload_authority = authority
	rejecting_rewind.reject_next_frame = true
	add_child(rejecting_rewind)
	player.rewind_recorder = rejecting_rewind
	_suite.assert_true(
		not player.advance_action_frame({}),
		"downstream Rewind rejection aborts the entire authoritative frame"
	)
	_suite.assert_equal(
		authority.replay_snapshot(),
		authority_before,
		"World rollback restores descriptor, remaining frames, revision, and runtime frame"
	)
	_suite.assert_true(
		authority.payload_node(payload_id) == payload_node,
		"World rollback preserves the exact Rift Node identity"
	)
	_suite.assert_equal(
		payload_node.call("world_payload_frame_snapshot"),
		node_before,
		"World rollback restores the Rift frame snapshot exactly"
	)
	rejecting_rewind.queue_free()
	await _free_player(player)


func _test_event_commit_preflight_is_observer_atomic() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy = 50.0
	manager.energy_regen = 7.0
	var time_events: Array[Dictionary] = []
	var weapon_events: Array[Dictionary] = []
	var on_energy_changed := func(current: float, maximum: float) -> void:
		time_events.append({"current": current, "maximum": maximum})
	var on_weapon_event := func(event: Dictionary) -> void:
		weapon_events.append(event.duplicate(true))
	manager.energy_changed.connect(on_energy_changed)
	player.weapon_action_coordinator.weapon_runtime_event.connect(on_weapon_event)
	player.weapon_action_coordinator.set("_frame_event_commit_fault_for_test", true)
	var before: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(not before.is_empty(), "event-settlement fixture captures the complete Player state")
	_suite.assert_true(
		not bool(player.advance_action_frame({})),
		"weapon commit preflight fault rejects the authoritative frame"
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before,
		"commit preflight fault restores Player, Time, Action, Character, Weapon, World, Rewind, and Replay prefix exactly"
	)
	_suite.assert_equal(time_events, [], "failed settlement publishes no Time observer prefix")
	_suite.assert_equal(weapon_events, [], "failed settlement publishes no Weapon observer prefix")
	player.weapon_action_coordinator.set("_frame_event_commit_fault_for_test", false)
	manager.energy_changed.disconnect(on_energy_changed)
	player.weapon_action_coordinator.weapon_runtime_event.disconnect(on_weapon_event)
	await _free_player(player)


func _test_time_stop_health_publication_is_discarded_on_late_rejection() -> void:
	await _assert_rejected_time_stop_health_publication(false)
	await _assert_rejected_time_stop_health_publication(true)


func _assert_rejected_time_stop_health_publication(lethal: bool) -> void:
	var player := await _spawn_player()
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	manager.energy_regen = 0.0
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 0.0
	manager.time_stop_duration = 1.0
	manager.time_stop_self_damage = float(health.current_hp) if lethal else 25.0

	var probe := RewindOrderProbe.new()
	probe.world_payload_authority = authority
	probe.late_frame_hook = func() -> void:
		player.weapon_action_coordinator.set("_frame_event_commit_fault_for_test", true)
	add_child(probe)
	player.rewind_recorder = probe

	var publications: Array[Dictionary] = []
	var on_damaged := func(amount: float, current_hp: float) -> void:
		publications.append({
			"kind": &"damaged",
			"amount": amount,
			"current_hp": current_hp,
		})
	var on_died := func(killer: Variant) -> void:
		publications.append({
			"kind": &"died",
			"killer": killer,
		})
	health.damaged.connect(on_damaged)
	health.died.connect(on_died)

	var before: Dictionary = player.full_player_replay_snapshot()
	var health_before: Dictionary = health.runtime_state_snapshot()
	var player_state_before := before.get("player_state", {}) as Dictionary
	var cursor_before := int(player_state_before.get("next_time_action_token", -1))
	var self_damage_cursor_before := int(manager.get("_next_irreversible_self_damage_token"))
	_suite.assert_true(
		not player.advance_action_frame({
			"time_slot_1": {"edge": &"pressed"},
		}),
		"late settlement fault rejects Time Stop self-damage frame"
	)
	player.weapon_action_coordinator.set("_frame_event_commit_fault_for_test", false)

	_suite.assert_equal(publications, [], "rejected frame publishes no Health observer prefix")
	_suite.assert_equal(
		health.runtime_state_snapshot(),
		health_before,
		"rejected frame restores HP, dead state, and irreversible ledger"
	)
	var after: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_equal(
		int((after.get("player_state", {}) as Dictionary).get("next_time_action_token", -1)),
		cursor_before,
		"rejected frame restores the time-action cursor"
	)
	_suite.assert_equal(
		int(manager.get("_next_irreversible_self_damage_token")),
		self_damage_cursor_before,
		"rejected frame restores the irreversible self-damage cursor"
	)
	_suite.assert_equal(after, before, "rejected frame restores the complete Player snapshot exactly")

	if health.damaged.is_connected(on_damaged):
		health.damaged.disconnect(on_damaged)
	if health.died.is_connected(on_died):
		health.died.disconnect(on_died)
	probe.queue_free()
	await _free_player(player)


func _test_time_stop_health_publication_occurs_after_world_commit() -> void:
	await _assert_committed_time_stop_health_publication(false)
	await _assert_committed_time_stop_health_publication(true)


func _test_world_commit_failure_discards_finalized_publications() -> void:
	var player := await _spawn_player()
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	manager.energy_regen = 0.0
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 0.0
	manager.time_stop_duration = 1.0
	manager.time_stop_self_damage = 25.0

	var damaged_events: Array[Dictionary] = []
	var on_damaged := func(amount: float, current_hp: float) -> void:
		damaged_events.append({"amount": amount, "current_hp": current_hp})
	health.damaged.connect(on_damaged)
	var before: Dictionary = player.full_player_replay_snapshot()
	authority.set("_frame_transaction_commit_fault_for_test", true)
	_suite.assert_true(
		not player.advance_action_frame({
			"time_slot_1": {"edge": &"pressed"},
		}),
		"World commit fault rejects the finalized fixed-frame publications"
	)
	authority.set("_frame_transaction_commit_fault_for_test", false)
	_suite.assert_equal(damaged_events, [], "World commit failure publishes no Health prefix")
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before,
		"World commit failure restores the complete Player snapshot"
	)
	_suite.assert_true(
		(player.get("_active_time_frame_signal_ticket") as Dictionary).is_empty(),
		"World commit failure clears the finalized Time ticket"
	)
	_suite.assert_true(
		(player.get("_active_health_frame_signal_ticket") as Dictionary).is_empty(),
		"World commit failure clears the finalized Health ticket"
	)
	_suite.assert_true(
		(authority.get("_active_frame_transaction") as Dictionary).is_empty(),
		"World commit failure rolls back the World transaction"
	)
	_suite.assert_true(
		player.advance_action_frame({
			"time_slot_1": {"edge": &"pressed"},
		}),
		"the next valid Time Stop frame commits after World failure rollback"
	)
	_suite.assert_equal(damaged_events.size(), 1, "recovery frame publishes Health exactly once")

	if health.damaged.is_connected(on_damaged):
		health.damaged.disconnect(on_damaged)
	await _free_player(player)


func _assert_committed_time_stop_health_publication(lethal: bool) -> void:
	var player := await _spawn_player()
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	manager.energy_regen = 0.0
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 0.0
	manager.time_stop_duration = 1.0
	manager.time_stop_self_damage = float(health.current_hp) if lethal else 25.0

	var observations: Array[Dictionary] = []
	var record_observation := func(kind: StringName) -> void:
		var snapshot: Dictionary = player.full_player_replay_snapshot()
		observations.append({
			"kind": kind,
			"world_transaction_active": not (
				authority.get("_active_frame_transaction") as Dictionary
			).is_empty(),
			"player_world_ticket_active": not (
				player.get("_active_world_frame_ticket") as Dictionary
			).is_empty(),
			"world_frame": int(authority.replay_snapshot().get("last_runtime_frame", -1)),
			"time_action_cursor": int((
				snapshot.get("player_state", {}) as Dictionary
			).get("next_time_action_token", -1)),
		})
	var on_damaged := func(_amount: float, _current_hp: float) -> void:
		record_observation.call(&"damaged")
	var on_died := func(_killer: Variant) -> void:
		record_observation.call(&"died")
	health.damaged.connect(on_damaged)
	health.died.connect(on_died)

	_suite.assert_true(
		player.advance_action_frame({
			"time_slot_1": {"edge": &"pressed"},
		}),
		"Time Stop self-damage frame commits"
	)
	_suite.assert_equal(
		observations.size(),
		2 if lethal else 1,
		"successful Health settlement publishes exactly once per event"
	)
	_suite.assert_equal(observations[0].get("kind"), &"damaged", "damage publishes first")
	if lethal:
		_suite.assert_equal(observations[1].get("kind"), &"died", "terminal publication follows damage")
	for observation: Dictionary in observations:
		_suite.assert_true(
			not bool(observation.get("world_transaction_active", true)),
			"Health observer runs after World transaction commit"
		)
		_suite.assert_true(
			not bool(observation.get("player_world_ticket_active", true)),
			"Health observer runs after Player clears its World ticket"
		)
		_suite.assert_equal(observation.get("world_frame"), 1, "observer sees the committed World frame")
		_suite.assert_equal(observation.get("time_action_cursor"), 2, "observer sees the committed time-action cursor")

	if health.damaged.is_connected(on_damaged):
		health.damaged.disconnect(on_damaged)
	if health.died.is_connected(on_died):
		health.died.disconnect(on_died)
	await _free_player(player)


func _test_nonempty_time_and_weapon_intents_match_live_and_replay() -> void:
	var live_time := await _spawn_player()
	var replay_time := await _spawn_player()
	for player: Node in [live_time, replay_time]:
		var manager: Node = player.get_node("TimeManager")
		manager.time_stop_cost = 0.0
		manager.time_stop_cooldown = 0.0
	var time_intent := {"time_slot_1": {"edge": &"pressed"}}
	_suite.assert_true(live_time.advance_action_frame(time_intent), "live nonempty Time intent commits")
	_suite.assert_true(replay_time.advance_action_frame(time_intent), "Replay nonempty Time intent commits through the same pump")
	_suite.assert_equal(
		replay_time.get_node("TimeManager").replay_snapshot(),
		live_time.get_node("TimeManager").replay_snapshot(),
		"live and Replay Time intents reach the identical authoritative Time state"
	)
	_suite.assert_equal(
		replay_time.action_state.snapshot().get("current_state"),
		live_time.action_state.snapshot().get("current_state"),
		"live and Replay Time intents enter the same Player action state"
	)
	_suite.assert_true(
		bool((live_time.get_node("TimeManager").replay_snapshot() as Dictionary).get("stop_active", false)),
		"nonempty Time intent actually starts Stop"
	)
	await _free_player(live_time)
	await _free_player(replay_time)

	var live_weapon := await _spawn_player()
	var replay_weapon := await _spawn_player()
	var weapon_intent := {"weapon_primary": {"edge": &"pressed"}}
	_suite.assert_true(live_weapon.advance_action_frame(weapon_intent), "live nonempty Weapon intent commits")
	_suite.assert_true(replay_weapon.advance_action_frame(weapon_intent), "Replay nonempty Weapon intent commits through the same pump")
	_suite.assert_equal(
		replay_weapon.weapon_action_coordinator.snapshot(),
		live_weapon.weapon_action_coordinator.snapshot(),
		"live and Replay Weapon intents reach the identical authoritative Weapon state"
	)
	_suite.assert_equal(
		replay_weapon.get("_weapon_replay_events"),
		live_weapon.get("_weapon_replay_events"),
		"live and Replay Weapon intents record the identical event prefix"
	)
	_suite.assert_true(
		int(live_weapon.weapon_action_coordinator.snapshot().get("token", 0)) > 0,
		"nonempty Weapon intent actually commits an action"
	)
	await _free_player(live_weapon)
	await _free_player(replay_weapon)


func _test_full_player_replay_restores_movement_aim_and_health() -> void:
	var player := await _spawn_player()
	var health: Node = player.get_node("HealthComponent")
	var checkpoint: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(not checkpoint.is_empty(), "full Player checkpoint captures the initial frame")
	_suite.assert_true(
		player.advance_action_frame({
			"movement": Vector2.RIGHT,
			"aim": Vector2.UP,
		}),
		"movement and aim commit through the authoritative frame envelope"
	)
	_suite.assert_true(player.global_position.x > 0.0, "fixed-frame movement changes world position")
	_suite.assert_equal(
		(player.full_player_replay_snapshot().get("player_state", {}) as Dictionary).get(
			"weapon_aim_direction"
		),
		Vector2.UP,
		"resolved aim direction is part of the full Player snapshot"
	)
	var loss: RefCounted = health.call(
		"lose_health_irreversible",
		25.0,
		&"replay_fixture",
		901,
		1,
		player.current_run_id()
	)
	_suite.assert_true(loss != null and not bool(loss.call("is_prevented")), "fixture commits irreversible Health state")
	_suite.assert_true(
		player.restore_full_player_replay_snapshot(checkpoint),
		"full Player Replay restores an earlier movement, aim, and Health checkpoint"
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		checkpoint,
		"full Player Replay restores the complete checkpoint exactly"
	)
	await _free_player(player)


func _test_player_timers_advance_once_per_fixed_frame() -> void:
	var large_delta := await _spawn_player()
	var normal_delta := await _spawn_player()
	for player: Node in [large_delta, normal_delta]:
		player.set("_dash_cooldown_remaining_frames", 27)
		player.set("_knockback_velocity", Vector2(100.0, -25.0))
	large_delta.call("_physics_process", 10.0)
	normal_delta.call("_physics_process", 1.0 / 60.0)
	_suite.assert_equal(
		large_delta.get("_dash_cooldown_remaining_frames"),
		26,
		"a ten-second render delta consumes exactly one dash cooldown frame"
	)
	_suite.assert_equal(
		large_delta.get("_dash_cooldown_remaining_frames"),
		normal_delta.get("_dash_cooldown_remaining_frames"),
		"dash cooldown is independent from wall-clock delta"
	)
	_suite.assert_equal(
		large_delta.get("_knockback_velocity"),
		normal_delta.get("_knockback_velocity"),
		"knockback decay is independent from wall-clock delta"
	)
	await _free_player(large_delta)
	await _free_player(normal_delta)


func _test_nonzero_p11_checkpoint_reanchors_every_fixed_frame_clock() -> void:
	var player := await _spawn_player()
	for _frame: int in range(20):
		_suite.assert_true(bool(player.call("advance_action_frame", {})), "checkpoint fixture frame commits")
	var checkpoint: Dictionary = player.weapon_replay_snapshot()
	_suite.assert_equal(checkpoint.get("frame"), 20, "fixture captures a nonzero P11 checkpoint")
	player.reset_runtime_state()
	_suite.assert_true(
		player.restore_weapon_replay_snapshot(checkpoint),
		"nonzero P11 checkpoint restores on the compatible base runtime"
	)
	_assert_all_clocks(player, 20, "checkpoint restore")
	_suite.assert_true(bool(player.call("advance_action_frame", {"source": "replay", "target_frame": 21})), "replay frame after checkpoint commits")
	_assert_all_clocks(player, 21, "checkpoint continuation")
	await _free_player(player)


func _test_active_rift_marks_the_p11_capture_epoch_unsupported() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
	}), "active Rift replay fixture configures")
	var checkpoint: Dictionary = player.weapon_replay_snapshot()
	var manager: Node = player.get_node("TimeManager")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	_suite.assert_true(manager.try_time_rift(Vector2(128.0, 96.0)), "real Rift commits")
	_suite.assert_true(player.weapon_replay_snapshot().is_empty(), "active Rift makes the current P11 capture epoch unavailable")
	var capture_status: Dictionary = player.weapon_replay_capture_status()
	_suite.assert_equal(
		capture_status.get("code"),
		&"ACTIVE_RIFT_REPLAY_UNSUPPORTED",
		"active Rift uses the explicit sticky unsupported boundary"
	)
	_suite.assert_true(
		not player.restore_weapon_replay_snapshot(checkpoint),
		"P11 checkpoint restore refuses to discard an active authoritative world payload"
	)
	var restore_status: Dictionary = player.call("weapon_replay_restore_status")
	_suite.assert_equal(
		restore_status.get("code"),
		&"ACTIVE_WORLD_PAYLOAD_REPLAY_UNSUPPORTED",
		"active-world restore rejection is explicit"
	)
	player.reset_runtime_state()
	_suite.assert_true(bool(player.weapon_replay_capture_status().get("ok", false)), "full reset starts a clean P11 capture epoch")
	_suite.assert_true(not player.weapon_replay_snapshot().is_empty(), "clean epoch captures again after reset")
	await _free_player(player)


func _test_death_invalidates_without_advancing_character_generation() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
	}), "death invalidation fixture configures")
	var manager: Node = player.get_node("TimeManager")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	_suite.assert_true(manager.try_time_rift(Vector2(64.0, 64.0)), "death invalidation Rift commits")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var run_id: StringName = player.current_run_id()
	var generation: int = player.owner_character_generation()
	var payload_id := StringName("%s:%d:rift:1:1" % [run_id, generation])
	var descriptor: Dictionary = authority.payload_descriptor(payload_id)
	player.call("_on_died", null)
	_suite.assert_equal(
		player.owner_character_generation(),
		generation,
		"terminal invalidation does not impersonate a successful character activation"
	)
	var invalidations := (authority.replay_snapshot().get("invalidated_generations", []) as Array)
	var found_generation_tombstone := false
	for value: Variant in invalidations:
		if (
			value is Dictionary
			and StringName(str((value as Dictionary).get("run_id", ""))) == run_id
			and int((value as Dictionary).get("owner_character_generation", 0)) == generation
		):
			found_generation_tombstone = true
			break
	_suite.assert_true(
		found_generation_tombstone,
		"death installs a permanent tombstone for the outgoing generation"
	)
	var stale_commit: Dictionary = authority.commit_payload(descriptor)
	_suite.assert_equal(stale_commit.get("code"), &"INVALIDATED_GENERATION", "death generation cannot commit another payload")
	var stale_callback: Dictionary = authority.retire_payload(
		payload_id,
		run_id,
		generation,
		&"late_completion"
	)
	_suite.assert_equal(stale_callback.get("code"), &"STALE_CALLBACK", "death rejects late payload callbacks")
	await _free_player(player)


func _test_run_replacement_preflights_before_generation_invalidation() -> void:
	var player := await _spawn_player()
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var recorder: Node = player.get_node("RewindRecorder")
	var health: Node = player.get_node("HealthComponent")
	var run_before: StringName = player.current_run_id()
	var generation_before: int = player.owner_character_generation()
	var authority_before: Dictionary = authority.replay_snapshot()
	var ticket: Dictionary = authority.begin_transaction_restore(authority_before)
	_suite.assert_true(not ticket.is_empty(), "run replacement preflight fixture locks world mutation")
	_suite.assert_true(
		not player.configure_run(&"replacement-run"),
		"run replacement rejects before touching participants when generation invalidation is unavailable"
	)
	_suite.assert_equal(player.current_run_id(), run_before, "failed run replacement preserves Player run identity")
	_suite.assert_equal(player.owner_character_generation(), generation_before, "failed run replacement preserves generation")
	_suite.assert_equal(health.irreversible_run_id(), run_before, "failed run replacement preserves Health run identity")
	_suite.assert_equal(recorder.current_run_id(), run_before, "failed run replacement preserves Rewind run identity")
	_suite.assert_equal(authority.replay_snapshot(), authority_before, "failed run replacement preserves world tombstones and payloads")
	_suite.assert_true(authority.rollback_transaction_restore(ticket), "run replacement preflight fixture unlocks cleanly")
	await _free_player(player)


func _test_reused_run_skips_every_tombstoned_generation() -> void:
	var player := await _spawn_player()
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var original_run: StringName = player.current_run_id()
	var original_generation: int = player.owner_character_generation()
	_suite.assert_true(
		player.configure_run(&"generation-reuse-probe"),
		"fixture switches away from the original run"
	)
	_suite.assert_true(
		authority.generation_is_invalidated(original_run, original_generation),
		"switching away tombstones the outgoing original generation"
	)
	_suite.assert_true(player.configure_run(original_run), "fixture re-enters the original run")
	_suite.assert_equal(
		player.owner_character_generation(),
		original_generation + 1,
		"re-entering a run selects the first generation after every permanent tombstone"
	)
	_suite.assert_true(
		not authority.generation_is_invalidated(
			player.current_run_id(),
			player.owner_character_generation()
		),
		"the re-entered run never revives an invalidated generation"
	)
	await _free_player(player)


func _test_loadout_and_reset_reject_locked_world_without_partial_state() -> void:
	var player := await _spawn_player()
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var before: Dictionary = player.full_player_replay_snapshot()
	var authority_before: Dictionary = authority.replay_snapshot()
	var ticket: Dictionary = authority.begin_transaction_restore(authority_before)
	_suite.assert_true(not ticket.is_empty(), "loadout reset failure fixture locks World authority")
	_suite.assert_true(
		not player.configure_loadout({
			"weapon_id": "sword",
			"enabled_time_skills": ["stop", "rift"],
		}),
		"loadout configuration reports World reset preflight failure"
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before,
		"failed loadout configuration preserves the complete Player state"
	)
	_suite.assert_true(
		not bool(player.call("reset_runtime_state")),
		"direct runtime reset reports the same locked-World failure"
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		before,
		"failed direct runtime reset performs no partial Player mutation"
	)
	_suite.assert_true(authority.rollback_transaction_restore(ticket), "World authority unlocks cleanly")
	_suite.assert_true(
		bool(player.call("reset_runtime_state")),
		"runtime reset succeeds after the World authority is unlocked"
	)
	await _free_player(player)


func _test_loadout_rewind_failure_restores_every_runtime_participant() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rift"],
		"milestone": "NEXT",
	}), "late reset rollback fixture equips Bow and Rift")
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var recorder: Node = player.get_node("RewindRecorder")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	_suite.assert_true(manager.try_time_rift(Vector2(96.0, 64.0)), "late reset rollback fixture commits a Rift")
	recorder.call("_record_snapshot")
	player.set_physics_process(true)

	var loadout_before: Dictionary = player.loadout_runtime.snapshot()
	var character_before: Dictionary = player.character_action_coordinator.snapshot()
	var weapon_before: Dictionary = player.weapon_action_coordinator.snapshot()
	var time_before: Dictionary = manager.replay_snapshot()
	var world_before: Dictionary = authority.replay_snapshot()
	var rewind_before: Dictionary = (
		player.full_player_replay_snapshot().get("rewind_state", {}) as Dictionary
	).duplicate(true)
	var physics_before := player.is_physics_processing()
	recorder.set_restore_fault_for_test(&"reset_runtime_state")

	_suite.assert_true(
		not player.configure_loadout({
			"weapon_id": "sword",
			"enabled_time_skills": ["stop", "rewind"],
		}),
		"late Rewind reset rejection aborts loadout configuration"
	)
	_suite.assert_equal(player.loadout_runtime.snapshot(), loadout_before, "failed loadout restores old loadout")
	_suite.assert_equal(player.character_action_coordinator.snapshot(), character_before, "failed loadout restores Character runtime")
	_suite.assert_equal(player.weapon_action_coordinator.snapshot(), weapon_before, "failed loadout restores Weapon runtime")
	_suite.assert_equal(manager.replay_snapshot(), time_before, "failed loadout restores Time runtime")
	_suite.assert_equal(authority.replay_snapshot(), world_before, "failed loadout restores World runtime and generation")
	_suite.assert_equal(
		player.full_player_replay_snapshot().get("rewind_state", {}),
		rewind_before,
		"failed loadout restores Rewind runtime"
	)
	_suite.assert_equal(player.is_physics_processing(), physics_before, "failed loadout restores physics processing")
	await _free_player(player)


func _complete_frame_snapshot(player: Node) -> Dictionary:
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var recorder: Node = player.get_node("RewindRecorder")
	return {
		"player_runtime_frame": int(player.rewind_transaction_snapshot().get("runtime_frame", -1)),
		"time": manager.replay_snapshot(),
		"action": player.action_state.snapshot(),
		"character": player.character_action_coordinator.snapshot(),
		"weapon": player.weapon_action_coordinator.snapshot(),
		"world": authority.replay_snapshot(),
		"rewind_runtime_frame": int(recorder.get("_last_runtime_frame")),
	}


func _assert_all_clocks(player: Node, expected_frame: int, label: String) -> void:
	var snapshot := _complete_frame_snapshot(player)
	_suite.assert_equal(snapshot.get("player_runtime_frame"), expected_frame, "%s Player clock" % label)
	_suite.assert_equal(int((snapshot.get("time", {}) as Dictionary).get("runtime_frame", -1)), expected_frame, "%s Time clock" % label)
	_suite.assert_equal(int((snapshot.get("action", {}) as Dictionary).get("frame", -1)), expected_frame, "%s Action clock" % label)
	_suite.assert_equal(int((snapshot.get("character", {}) as Dictionary).get("last_runtime_frame", -1)), expected_frame, "%s Character clock" % label)
	_suite.assert_equal(int((snapshot.get("weapon", {}) as Dictionary).get("frame", -1)), expected_frame, "%s Weapon clock" % label)
	_suite.assert_equal(int((snapshot.get("world", {}) as Dictionary).get("last_runtime_frame", -1)), expected_frame, "%s World clock" % label)
	_suite.assert_equal(snapshot.get("rewind_runtime_frame"), expected_frame, "%s Rewind clock" % label)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	# Godot enables callbacks declared by a script when the node enters the tree,
	# so disable them after add_child() to keep this fixture manually clocked.
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	player.reset_runtime_state()
	return player


func _free_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
