extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

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
		"Task 4 production fixture loads the authoritative Base Pack"
	)
	await _test_void_damage_corruption_time_and_snapshot_rollback()
	await _test_void_devour_commits_cost_and_replay_safe_world_payload()
	await _test_knight_realm_cleave_armor_and_replay_safe_world_payload()
	await _test_knight_time_action_snapshot_is_exactly_restorable()
	await _test_knight_weapon_commitment_reaches_character_runtime()
	_suite.finish(get_tree())


func _test_void_damage_corruption_time_and_snapshot_rollback() -> void:
	var player := await _spawn_player(&"void_walker")
	var health: Node = player.get_node("HealthComponent")
	EventBus.room_started.emit(str(player.current_run_id()), &"room-void", 1)
	_suite.assert_true(player.advance_action_frame({}), "Void binding frame advances")

	var damage: RefCounted = _enemy_damage(player, 60.0, &"void-enemy", 1)
	var resolution: RefCounted = health.resolve_and_apply_damage(damage)
	_suite.assert_true(
		resolution != null and not resolution.call("is_prevented"),
		"Void enemy damage resolves through HealthComponent"
	)
	_suite.assert_close(float(health.current_hp), 100.0, "Void enemy damage changes real HP")
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		60,
		"applied Health resolution grants exactly sixty Void Debt"
	)

	for _frame: int in range(60):
		_suite.assert_true(player.advance_action_frame({}), "Void corruption frame advances")
	_suite.assert_close(
		float(health.current_hp),
		98.0,
		"the frame-60 corruption request applies two irreversible HP through Player"
	)
	_suite.assert_close(
		float((health.call("hp_loss_state") as Dictionary).get("irreversible_hp_loss_total", 0.0)),
		2.0,
		"corruption production damage is recorded in the irreversible ledger"
	)

	var participant_before: Dictionary = player.character_time_action_participant_snapshot()
	var forged := participant_before.duplicate(true)
	var forged_health := forged.get("health", {}) as Dictionary
	forged_health["current_hp"] = float(forged_health.get("max_hp", 0.0)) + 1.0
	_suite.assert_true(
		not player.restore_character_time_action_participant_snapshot(forged),
		"invalid cross-participant restore is rejected"
	)
	_suite.assert_equal(
		player.character_time_action_participant_snapshot(),
		participant_before,
		"rejected cross-participant restore rolls Player, Health, and character state back exactly"
	)
	for _frame: int in range(11):
		_suite.assert_true(
			player.advance_action_frame({}),
			"Void corruption hitstun recovery frame advances"
		)

	var time_before: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(
		player.advance_action_frame(_time_press(&"time_stop")),
		"Void Time Stop commits through the authoritative fixed-frame transaction"
	)
	var time_committed: Dictionary = player.full_player_replay_snapshot()
	var committed_strategy := _strategy_snapshot(player)
	_suite.assert_equal(
		_accepted_action_id(player),
		&"time_stop",
		"Void Time Stop is the accepted semantic action"
	)
	_suite.assert_true(
		int(committed_strategy.get("corruption_pause_through_frame", -1))
		>= int(time_committed.get("frame", 0)),
		"committed Stop fact reaches Void corruption conversion"
	)
	_suite.assert_true(player.advance_action_frame({}), "post-Stop replay frame advances")
	_suite.assert_true(
		player.restore_full_player_replay_snapshot(time_committed),
		"Void full replay checkpoint restores after later fixed-frame mutation"
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		time_committed,
		"Void character, Health, Time, and World snapshots restore byte-equivalent values"
	)
	_suite.assert_true(
		time_before != time_committed,
		"committed TimeAction changes the authenticated replay state"
	)
	await _free_player(player)


func _test_void_devour_commits_cost_and_replay_safe_world_payload() -> void:
	var player := await _spawn_player(&"void_walker")
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var world: Node = player.get_node("WorldPayloadAuthority")
	EventBus.room_started.emit(str(player.current_run_id()), &"room-devour", 1)

	_suite.assert_true(player.advance_action_frame(_character_press()), "Devour input frame advances")
	var devour_accepted := _accepted_action_id(player) == &"character_skill"
	_suite.assert_true(
		devour_accepted,
		"Devour receives complete HP, attack, aim, and energy context from Player"
	)
	if not devour_accepted:
		await _free_player(player)
		return
	for _frame: int in range(23):
		_suite.assert_true(player.advance_action_frame({}), "Devour windup frame advances")
	var before_commit: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(
		player.advance_action_frame({}),
		"Devour active frame atomically commits HP, energy, character, and World state"
	)
	_suite.assert_close(float(health.current_hp), 128.0, "Devour pays exact 20 percent max-HP cost")
	_suite.assert_close(float(manager.energy), 65.0, "Devour spends exactly twenty-five Time Energy")
	_suite.assert_close(
		float((health.call("hp_loss_state") as Dictionary).get("irreversible_hp_loss_total", 0.0)),
		32.0,
		"Devour self-cost is irreversible and ledger-backed"
	)
	var committed_world: Dictionary = world.call("replay_snapshot")
	var descriptors := committed_world.get("descriptors", []) as Array
	_suite.assert_equal(descriptors.size(), 1, "Devour commits one WorldPayload descriptor")
	if descriptors.size() == 1:
		var descriptor := descriptors[0] as Dictionary
		_suite.assert_equal(
			str(descriptor.get("handler_id", "")),
			"void_devour_cone",
			"Devour WorldPayload keeps its production handler identity"
		)
		_suite.assert_equal(
			str(descriptor.get("payload_family", "")),
			"void_devour",
			"Devour WorldPayload keeps its replay family"
		)

	var committed: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(committed != before_commit, "Devour commit changes the full authenticated snapshot")
	_suite.assert_true(player.advance_action_frame({}), "Devour payload retirement frame advances")
	_suite.assert_true(
		player.restore_full_player_replay_snapshot(committed),
		"Devour Replay restore reconstructs the committed world-owned payload"
	)
	_suite.assert_equal(
		world.call("replay_snapshot"),
		committed_world,
		"Devour Replay restore reproduces the exact descriptor set"
	)
	await _free_player(player)


func _test_knight_realm_cleave_armor_and_replay_safe_world_payload() -> void:
	var player := await _spawn_player(&"primordial_knight")
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var world: Node = player.get_node("WorldPayloadAuthority")
	EventBus.room_started.emit(str(player.current_run_id()), &"room-cleave", 1)
	_suite.assert_true(player.advance_action_frame({}), "Knight binding frame advances")
	_grant_three_mastery(player)

	_suite.assert_true(player.advance_action_frame(_character_press()), "Realm Cleave input frame advances")
	var cleave_accepted := _accepted_action_id(player) == &"character_skill"
	_suite.assert_true(
		cleave_accepted,
		"Realm Cleave receives complete attack, position, alive, and energy context from Player"
	)
	if not cleave_accepted:
		await _free_player(player)
		return
	var energy_before_hit := float(manager.energy)
	var armor_hit: RefCounted = health.resolve_and_apply_damage(
		_enemy_damage(player, 20.0, &"knight-enemy", 1)
	)
	_suite.assert_close(
		float(armor_hit.call("finalized_damage")),
		4.0,
		"Realm Cleave windup armor resolves before Knight flat defense"
	)
	_suite.assert_close(float(health.current_hp), 226.0, "Knight Health owns the armored result")
	_suite.assert_true(
		(_strategy_snapshot(player).get("skill_action", {}) as Dictionary).is_empty(),
		"hitstun cancels the uncommitted Realm Cleave windup"
	)
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		3,
		"cancelled Realm Cleave does not consume reserved Resonance"
	)
	_suite.assert_close(
		float(manager.energy),
		energy_before_hit,
		"cancelled Realm Cleave does not spend Time Energy"
	)

	for _frame: int in range(11):
		_suite.assert_true(player.advance_action_frame({}), "Knight hitstun recovery frame advances")
	_suite.assert_true(
		player.advance_action_frame(_character_press()),
		"Realm Cleave can be started again after hitstun recovery"
	)
	_suite.assert_equal(
		_accepted_action_id(player),
		&"character_skill",
		"the restarted Realm Cleave owns the accepted action"
	)

	for _frame: int in range(35):
		_suite.assert_true(player.advance_action_frame({}), "Realm Cleave windup frame advances")
	var before_commit: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(
		player.advance_action_frame({}),
		"Realm Cleave active frame atomically commits resource, energy, and World state"
	)
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		0,
		"Realm Cleave consumes all three reserved Resonance stacks"
	)
	_suite.assert_close(float(manager.energy), 75.0, "Realm Cleave spends exactly thirty-five Time Energy")
	var committed_world: Dictionary = world.call("replay_snapshot")
	var descriptors := committed_world.get("descriptors", []) as Array
	_suite.assert_equal(descriptors.size(), 1, "Realm Cleave commits one WorldPayload descriptor")
	if descriptors.size() == 1:
		var descriptor := descriptors[0] as Dictionary
		_suite.assert_equal(
			str(descriptor.get("handler_id", "")),
			"realm_cleave_execution",
			"Realm Cleave WorldPayload keeps its production handler identity"
		)
		_suite.assert_equal(
			str(descriptor.get("payload_family", "")),
			"realm_cleave",
			"Realm Cleave WorldPayload keeps its replay family"
		)

	var committed: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(committed != before_commit, "Realm Cleave commit changes the full snapshot")
	_suite.assert_true(player.advance_action_frame({}), "Realm Cleave payload retirement frame advances")
	_suite.assert_true(
		player.restore_full_player_replay_snapshot(committed),
		"Realm Cleave Replay restore reconstructs the world-owned payload"
	)
	_suite.assert_equal(
		world.call("replay_snapshot"),
		committed_world,
		"Realm Cleave Replay restore reproduces the exact descriptor set"
	)
	await _free_player(player)


func _test_knight_time_action_snapshot_is_exactly_restorable() -> void:
	var player := await _spawn_player(&"primordial_knight")
	EventBus.room_started.emit(str(player.current_run_id()), &"room-knight-time", 1)
	_suite.assert_true(player.advance_action_frame({}), "Knight Time binding frame advances")
	var before_strategy := _strategy_snapshot(player)
	_suite.assert_true(
		player.advance_action_frame(_time_press(&"time_stop")),
		"Knight Time Stop commits through TimeActionTransaction"
	)
	var committed: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_true(
		int(_strategy_snapshot(player).get("revision", -1))
		> int(before_strategy.get("revision", -1)),
		"committed Stop fact reaches the Knight time-conversion hook"
	)
	_suite.assert_true(player.advance_action_frame({}), "Knight post-Time frame advances")
	_suite.assert_true(
		player.restore_full_player_replay_snapshot(committed),
		"Knight full replay checkpoint restores after TimeAction"
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		committed,
		"Knight Player, Health, Time, character, and World snapshots restore exactly"
	)
	await _free_player(player)


func _test_knight_weapon_commitment_reaches_character_runtime() -> void:
	var player := await _spawn_player(&"primordial_knight")
	EventBus.room_started.emit(str(player.current_run_id()), &"room-knight-weapon", 1)
	_suite.assert_true(player.advance_action_frame({}), "Knight weapon binding frame advances")
	_grant_three_mastery(player)

	_suite.assert_true(
		player.advance_action_frame(_weapon_intent(&"pressed", 0)),
		"Knight Sword primary hold starts through Player input"
	)
	for _frame: int in range(29):
		_suite.assert_true(player.advance_action_frame({}), "Knight charged commitment hold advances")
	_suite.assert_true(
		player.advance_action_frame(_weapon_intent(&"released", 30)),
		"Knight charged Sword release commits through WeaponActionCoordinator"
	)
	_suite.assert_equal(
		_accepted_action_id(player),
		&"weapon_primary",
		"the real charged release is the accepted frame action"
	)
	var strategy := _strategy_snapshot(player)
	_suite.assert_equal(
		int(strategy.get("resource_value", -1)),
		0,
		"the real weapon commit reserves all three Resonance stacks"
	)
	_suite.assert_equal(
		(strategy.get("pending_echoes", []) as Array).size(),
		1,
		"the real weapon commit schedules exactly one replay-safe planar echo"
	)
	await _free_player(player)


func _grant_three_mastery(player: Node) -> void:
	for token: int in [101, 102, 103]:
		var context: Dictionary = player.call(
			"_weapon_mastery_context",
			token,
			{"mastery_eligible": true}
		)
		var fact: Dictionary = player.weapon_runtime.call(
			"build_mastery_fact",
			&"sword_perfect_guard",
			&"weapon_secondary",
			int(player.character_action_coordinator.call("generation")),
			token,
			token,
			{"confirmed": true, "mastery_eligible": true},
			context
		)
		var accepted: bool = bool(player.call("_settle_weapon_mastery_fact", fact))
		_suite.assert_true(accepted, "Knight accepts canonical mastery fact %d" % token)
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		3,
		"Knight fixture owns three Resonance stacks"
	)


func _strategy_snapshot(player: Node) -> Dictionary:
	return (
		(player.character_runtime_snapshot().get("runtime", {}) as Dictionary)
		.get("strategy", {}) as Dictionary
	).duplicate(true)


func _accepted_action_id(player: Node) -> StringName:
	var accepted := player.priority_arbitration_snapshot().get("accepted", {}) as Dictionary
	return StringName(str(accepted.get("id", "")))


func _character_press() -> Dictionary:
	return {
		"character": [{
			"id": &"character_skill",
			"edge": &"pressed",
			"held_frames": 0,
			"mode": &"press",
		}],
	}


func _time_press(action_id: StringName) -> Dictionary:
	return {
		"time": [{
			"id": action_id,
			"edge": &"pressed",
			"held_frames": 0,
			"mode": &"press",
		}],
	}


func _weapon_intent(edge: StringName, held_frames: int) -> Dictionary:
	return {
		"weapon": [{
			"id": &"weapon_primary",
			"edge": edge,
			"held_frames": held_frames,
			"mode": &"hold",
		}],
	}


func _enemy_damage(
	player: Node,
	amount: float,
	hostile_source_id: StringName,
	attack_generation: int
) -> RefCounted:
	return DamageInfoScript.from_plan({
		"run_id": player.current_run_id(),
		"target_id": &"player",
		"hostile_source_id": hostile_source_id,
		"attack_generation": attack_generation,
		"hit_index": 0,
		"action_token": attack_generation,
		"amount": amount,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": null,
		"attacker": null,
		"can_crit": false,
		"knockback": Vector2.ZERO,
		"tags": ["enemy"],
		"source_generation": attack_generation,
	})


func _launch_config(character_id: StringName) -> Dictionary:
	return {
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
		"seed": 20261001,
	}


func _spawn_player(character_id: StringName) -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(player.reset_runtime_state(), "Player fixture resets")
	_suite.assert_true(
		player.configure_loadout(_launch_config(character_id)),
		"%s Launch character configures" % str(character_id)
	)
	return player


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
