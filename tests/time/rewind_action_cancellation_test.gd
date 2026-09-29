extends Node

const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RewindRecorderScript := preload("res://scripts/time_system/rewind_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _player_attack_events: int = 0


class RewindTarget extends Node2D:
	var velocity: Vector2 = Vector2.ZERO
	var cancel_calls: int = 0
	var restore_calls: int = 0
	var cancel_happened_before_restore: bool = false
	var restored_facing: Vector2 = Vector2.ZERO
	var restored_action: Dictionary = {}


	func cancel_transient_actions() -> void:
		cancel_calls += 1


	func get_rewind_facing() -> Vector2:
		return Vector2.UP


	func restore_rewind_facing(facing: Vector2) -> void:
		restored_facing = facing


	func get_rewind_safe_action_state() -> Dictionary:
		return {"state": "FREE", "generation": 7}


	func restore_rewind_safe_action_state(state: Dictionary) -> void:
		restore_calls += 1
		cancel_happened_before_restore = cancel_calls > 0
		restored_action = state.duplicate(true)


class RewindHealth extends Node:
	var max_hp: float = 100.0
	var current_hp: float = 100.0
	var invulnerability_calls: int = 0


	func apply_invulnerability(_duration: float) -> void:
		invulnerability_calls += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	EventBus.player_attacked.connect(_on_player_attacked)
	await _test_bow_hold_cancellation(suite)
	await _test_rewind_cancels_before_restoring(suite)
	await _test_player_cancellation_is_idempotent(suite)
	await _test_rewind_cancels_each_transient_phase(suite)
	await _test_dead_player_rewind_is_rejected(suite)
	EventBus.player_attacked.disconnect(_on_player_attacked)
	suite.finish(get_tree())


func _test_bow_hold_cancellation(suite) -> void:
	var player := await _spawn_player()
	suite.assert_true(player.configure_loadout(_bow_loadout()), "cancellation fixture equips profile-backed Bow")
	var attacks_before := _player_attack_events
	suite.assert_true(player.try_action(&"ranged_attack"), "Bow begins a coordinator-owned HOLD")
	var hold: Dictionary = player.weapon_presentation_snapshot()
	var hold_token := int(hold.get("token", 0))
	var hold_generation := int(hold.get("generation", 0))
	suite.assert_equal(hold.get("phase"), "HOLD", "Bow cancellation setup reaches HOLD")
	_advance(player, 9)

	player.cancel_transient_actions()
	var cancelled: Dictionary = player.weapon_presentation_snapshot()
	suite.assert_equal(cancelled.get("phase"), "READY", "cancel closes Bow HOLD immediately")
	suite.assert_true(int(cancelled.get("generation", 0)) > hold_generation, "cancel invalidates the HOLD generation")
	suite.assert_true(not player.try_action(&"ranged_release"), "stale release cannot resolve a cancelled HOLD")
	suite.assert_equal(_player_attack_events, attacks_before, "cancelled HOLD publishes no projectile release")
	suite.assert_true(get_tree().get_nodes_in_group("player_arrows").is_empty(), "cancelled HOLD spawns no arrow")
	suite.assert_true(hold_token > 0, "cancelled HOLD owned a real action token")

	player.cancel_transient_actions()
	suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "READY", "Bow cancellation is idempotent")
	await _free_player(player)


func _test_rewind_cancels_before_restoring(suite) -> void:
	var harness := Node.new()
	harness.name = "Harness"
	add_child(harness)

	var target := RewindTarget.new()
	target.name = "Target"
	target.global_position = Vector2(48.0, 72.0)
	target.velocity = Vector2(12.0, -4.0)
	harness.add_child(target)

	var health := RewindHealth.new()
	health.name = "Health"
	health.current_hp = 80.0
	harness.add_child(health)

	var time_manager := Node.new()
	time_manager.name = "TimeManager"
	harness.add_child(time_manager)

	var recorder := RewindRecorderScript.new()
	recorder.name = "Recorder"
	recorder.target_path = NodePath("../Target")
	recorder.health_component_path = NodePath("../Health")
	recorder.time_manager_path = NodePath("../TimeManager")
	harness.add_child(recorder)
	await get_tree().process_frame

	recorder._record_snapshot()
	var snapshot: Dictionary = recorder.peek_oldest_snapshot()
	var invalid_snapshot := snapshot.duplicate(true)
	invalid_snapshot.erase("hp")
	suite.assert_true(not recorder.restore_player_state(invalid_snapshot), "invalid rewind snapshot is rejected")
	suite.assert_equal(target.cancel_calls, 0, "invalid rewind does not cancel the current timeline")

	target.global_position = Vector2(260.0, 180.0)
	target.velocity = Vector2.ZERO
	health.current_hp = 25.0
	suite.assert_true(recorder.restore_player_state(snapshot), "valid rewind snapshot restores successfully")
	suite.assert_equal(target.cancel_calls, 1, "valid rewind invokes cancellation exactly once")
	suite.assert_true(target.cancel_happened_before_restore, "rewind cancels abandoned actions before safe action restore")
	suite.assert_equal(target.restore_calls, 1, "rewind restores safe action state once")
	suite.assert_equal(target.restored_action, snapshot["safe_action"], "rewind passes a captured safe action copy")
	suite.assert_equal(target.global_position, Vector2(48.0, 72.0), "rewind still restores position")
	suite.assert_equal(target.velocity, Vector2(12.0, -4.0), "rewind still restores velocity")
	suite.assert_equal(target.restored_facing, Vector2.UP, "rewind still restores facing")
	suite.assert_close(health.current_hp, 80.0, "rewind still restores health")
	suite.assert_equal(health.invulnerability_calls, 1, "rewind still grants restore invulnerability")

	harness.queue_free()
	await get_tree().process_frame


func _test_player_cancellation_is_idempotent(suite) -> void:
	var player := await _spawn_player()
	var sword: Node = player.get_node("SwordWeapon")
	var hitbox: Node = sword.get_node("Hitbox")
	var definition: Dictionary = sword.attack_definition(false)
	var attacks_before: int = _player_attack_events

	suite.assert_true(player.try_action(&"attack"), "player commits a cancellable sword windup")
	suite.assert_true(player.try_action(&"dash"), "dash can buffer before cancellation")
	suite.assert_true(player.action_state.has_buffered_input(&"dash"), "setup contains a buffered dash")
	player.cancel_transient_actions()
	player.cancel_transient_actions()

	suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "repeated cancellation leaves player free")
	suite.assert_true(not player.action_state.has_buffered_input(&"dash"), "cancellation clears buffered inputs")
	suite.assert_true(not sword.is_attacking(), "cancellation closes pending sword windup")
	suite.assert_true(not hitbox.is_active(), "cancellation keeps hitbox closed")
	suite.assert_equal(player._dash_velocity, Vector2.ZERO, "cancellation clears dash velocity")

	_advance(player, int(definition["windup_frames"]) + int(definition["active_frames"]) + int(definition["recovery_frames"]) + 2)
	suite.assert_equal(_player_attack_events, attacks_before, "cancelled windup emits no delayed sword attack")
	suite.assert_true(not hitbox.is_active(), "cancelled windup cannot reopen the hitbox later")

	suite.assert_true(player.try_action(&"attack"), "player can start another attack after cancellation")
	var next_definition: Dictionary = sword.attack_definition(false)
	_advance(player, int(next_definition["windup_frames"]))
	suite.assert_true(hitbox.is_active(), "setup reaches active sword phase")
	var receiver := HitReceiver.new()
	receiver.name = "Receiver"
	add_child(receiver)
	var active_attack_count: int = _player_attack_events
	player.cancel_transient_actions()
	hitbox._on_area_entered(receiver)
	_advance(player, int(next_definition["active_frames"]) + int(next_definition["recovery_frames"]) + 2)
	suite.assert_equal(receiver.hit_count, 0, "cancelled active hitbox cannot deal a ghost hit")
	suite.assert_equal(_player_attack_events, active_attack_count, "cancelled active phase emits no later attack signal")
	suite.assert_true(not hitbox.is_active(), "cancelled active hitbox stays closed")
	receiver.queue_free()

	suite.assert_true(player.try_action(&"dash"), "player commits a cancellable dash")
	suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.DASH, "setup enters dash state")
	suite.assert_true(player._dash_velocity.length_squared() > 0.0, "setup creates dash velocity")
	player.cancel_transient_actions()
	player.cancel_transient_actions()
	suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "dash cancellation is idempotent")
	suite.assert_equal(player._dash_velocity, Vector2.ZERO, "dash cancellation removes residual movement")

	var health: Node = player.get_node("HealthComponent")
	health.lose_health(health.current_hp, &"test")
	player.cancel_transient_actions()
	player.cancel_transient_actions()
	suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.DEAD, "cancellation cannot revive terminal DEAD state")
	await get_tree().create_timer(0.25).timeout
	await _free_player(player)


func _test_rewind_cancels_each_transient_phase(suite) -> void:
	var players: Array[Node] = []

	var windup_player := await _spawn_player()
	players.append(windup_player)
	var windup_sword: Node = windup_player.get_node("SwordWeapon")
	var windup_definition: Dictionary = windup_sword.attack_definition(false)
	var windup_recorder: Node = windup_player.get_node("RewindRecorder")
	windup_recorder.clear_snapshots()
	windup_recorder._record_snapshot()
	var windup_attacks_before: int = _player_attack_events
	windup_player.try_action(&"attack")
	suite.assert_true(windup_player.get_node("TimeManager").try_rewind(windup_recorder), "rewind succeeds during sword windup")
	_advance(windup_player, int(windup_definition["windup_frames"]) + int(windup_definition["active_frames"]) + 2)
	suite.assert_equal(_player_attack_events, windup_attacks_before, "rewound windup emits no abandoned-timeline attack")
	suite.assert_equal(windup_player.action_state.current_state, PlayerActionStateScript.State.FREE, "rewind resets windup to safe free state")

	var active_player := await _spawn_player()
	players.append(active_player)
	var active_sword: Node = active_player.get_node("SwordWeapon")
	var active_hitbox: Node = active_sword.get_node("Hitbox")
	var active_definition: Dictionary = active_sword.attack_definition(false)
	var active_recorder: Node = active_player.get_node("RewindRecorder")
	active_recorder.clear_snapshots()
	active_recorder._record_snapshot()
	suite.assert_true(active_player.try_action(&"attack"), "active-phase rewind setup commits sword attack")
	_advance(active_player, int(active_definition["windup_frames"]))
	var active_attacks_before_rewind: int = _player_attack_events
	suite.assert_equal(active_player.action_state.current_state, PlayerActionStateScript.State.ATTACK_ACTIVE, "setup enters active action state before rewind")
	suite.assert_true(active_hitbox._active_damage_info != null, "setup reaches active damage phase before rewind")
	suite.assert_true(active_player.get_node("TimeManager").try_rewind(active_recorder), "rewind succeeds during active sword phase")
	var rewind_receiver := HitReceiver.new()
	rewind_receiver.name = "RewindReceiver"
	add_child(rewind_receiver)
	active_hitbox._on_area_entered(rewind_receiver)
	_advance(active_player, int(active_definition["active_frames"]) + int(active_definition["recovery_frames"]) + 2)
	suite.assert_equal(rewind_receiver.hit_count, 0, "rewound active phase cannot deal a ghost hit")
	suite.assert_equal(_player_attack_events, active_attacks_before_rewind, "rewound active phase emits no later attack signal")
	suite.assert_true(not active_hitbox.is_active(), "rewind closes the active hitbox immediately")
	rewind_receiver.queue_free()

	var dash_player := await _spawn_player()
	players.append(dash_player)
	var dash_recorder: Node = dash_player.get_node("RewindRecorder")
	dash_recorder.clear_snapshots()
	dash_recorder._record_snapshot()
	dash_player.try_action(&"dash")
	suite.assert_equal(dash_player.action_state.current_state, PlayerActionStateScript.State.DASH, "setup reaches dash before rewind")
	suite.assert_true(dash_player.get_node("TimeManager").try_rewind(dash_recorder), "rewind succeeds during dash")
	suite.assert_equal(dash_player.action_state.current_state, PlayerActionStateScript.State.FREE, "rewind cancels dash state")
	suite.assert_equal(dash_player._dash_velocity, Vector2.ZERO, "rewind cancels dash movement")

	var bow_player := await _spawn_player()
	players.append(bow_player)
	suite.assert_true(bow_player.configure_loadout(_bow_loadout()), "rewind fixture equips profile-backed Bow")
	var bow_recorder: Node = bow_player.get_node("RewindRecorder")
	bow_recorder.clear_snapshots()
	bow_recorder._record_snapshot()
	var bow_attacks_before := _player_attack_events
	suite.assert_true(bow_player.try_action(&"ranged_attack"), "rewind setup begins Bow HOLD")
	_advance(bow_player, 9)
	var bow_hold: Dictionary = bow_player.weapon_presentation_snapshot()
	var bow_generation := int(bow_hold.get("generation", 0))
	suite.assert_true(bow_player.get_node("TimeManager").try_rewind(bow_recorder), "rewind succeeds during Bow HOLD")
	var rewound_bow: Dictionary = bow_player.weapon_presentation_snapshot()
	suite.assert_equal(rewound_bow.get("phase"), "READY", "rewind cancels Bow HOLD")
	suite.assert_true(int(rewound_bow.get("generation", 0)) > bow_generation, "rewind invalidates the abandoned HOLD generation")
	suite.assert_true(not bow_player.try_action(&"ranged_release"), "rewound stale release cannot fire")
	suite.assert_equal(_player_attack_events, bow_attacks_before, "rewound HOLD publishes no attack fact")
	suite.assert_true(get_tree().get_nodes_in_group("player_arrows").is_empty(), "rewound HOLD spawns no arrow")

	await get_tree().create_timer(0.55).timeout
	for player: Node in players:
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_dead_player_rewind_is_rejected(suite) -> void:
	var player := await _spawn_player()
	var health: Node = player.get_node("HealthComponent")
	var recorder: Node = player.get_node("RewindRecorder")
	var time_manager: Node = player.get_node("TimeManager")
	player.global_position = Vector2(24.0, 48.0)
	recorder.clear_snapshots()
	recorder._record_snapshot()
	player.global_position = Vector2(240.0, 180.0)
	health.lose_health(health.current_hp, &"test")
	var energy_before: float = time_manager.energy
	var snapshot_count: int = recorder._snapshots.size()

	suite.assert_true(not time_manager.try_rewind(recorder), "dead player cannot commit a rewind")
	suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.DEAD, "rejected dead rewind preserves terminal action state")
	suite.assert_true(health.dead, "rejected dead rewind preserves dead health state")
	suite.assert_close(health.current_hp, 0.0, "rejected dead rewind cannot restore hp into a half-alive state")
	suite.assert_equal(player.global_position, Vector2(240.0, 180.0), "rejected dead rewind does not move the corpse")
	suite.assert_close(time_manager.energy, energy_before, "rejected dead rewind spends no energy")
	suite.assert_equal(recorder._snapshots.size(), snapshot_count, "rejected dead rewind retains snapshot history")

	await get_tree().create_timer(0.15).timeout
	await _free_player(player)


class HitReceiver extends Area2D:
	var hit_count: int = 0


	func receive_hit(_damage_info: RefCounted) -> void:
		hit_count += 1


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	return player


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _advance(player: Node, frames: int) -> void:
	for _frame: int in range(frames):
		player.advance_action_frame()


func _bow_loadout() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260930,
	}


func _on_player_attacked(_weapon_id: StringName, _context: Dictionary) -> void:
	_player_attack_events += 1
