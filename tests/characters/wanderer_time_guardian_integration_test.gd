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
	_suite.assert_true(not report.call("has_blocking_errors"), "integration fixture loads the base pack")
	await _test_wanderer_waypoint_commits_energy_damage_heal_and_teleport()
	await _test_guardian_character_defense_prevents_then_consumes_ward()
	await _test_committed_time_fact_consumes_wanderer_mark_and_reduces_cooldown()
	await _test_wanderer_forgiveness_reaches_and_is_consumed_by_real_weapon_runtime()
	_suite.finish(get_tree())


func _test_wanderer_waypoint_commits_energy_damage_heal_and_teleport() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_launch_config(&"wanderer")),
		"Launch Wanderer configures"
	)
	EventBus.room_started.emit(str(player.current_run_id()), &"room-1", 1)
	player.global_position = Vector2(32.0, 48.0)

	_suite.assert_true(
		player.advance_action_frame(_character_press()),
		"Waypoint placement press commits through semantic input"
	)
	for _frame: int in range(6):
		_suite.assert_true(player.advance_action_frame({}), "Waypoint windup frame advances")
	var manager: Node = player.get_node("TimeManager")
	var health: Node = player.get_node("HealthComponent")
	_suite.assert_close(float(manager.energy), 70.0, "Waypoint placement spends exactly 30 energy")
	_suite.assert_true(
		bool(player.character_presentation_snapshot().get("anchor_active", false)),
		"Waypoint placement creates the authoritative anchor"
	)

	var damage := _enemy_damage(player, 20.0, &"enemy-a", 1)
	var resolution: RefCounted = health.resolve_and_apply_damage(damage)
	_suite.assert_true(resolution != null and not resolution.call("is_prevented"), "enemy damage resolves")
	_suite.assert_close(float(health.current_hp), 180.0, "enemy damage applies before recall healing")

	for _frame: int in range(12):
		_suite.assert_true(player.advance_action_frame({}), "Waypoint recovery frame advances")
	player.global_position = Vector2(320.0, 480.0)
	_suite.assert_true(
		player.advance_action_frame(_character_press()),
		"Waypoint recall press commits after recovery"
	)
	for _frame: int in range(6):
		_suite.assert_true(player.advance_action_frame({}), "Waypoint recall windup frame advances")

	_suite.assert_equal(player.global_position, Vector2(32.0, 48.0), "Waypoint recall teleports to the anchor")
	_suite.assert_close(float(health.current_hp), 185.0, "Waypoint recall heals 25 percent of enemy damage")
	_suite.assert_close(float(manager.energy), 40.633333, "Waypoint costs remain exact alongside fixed-frame regeneration")
	_suite.assert_true(
		not bool(player.character_presentation_snapshot().get("anchor_active", true)),
		"Waypoint recall consumes the anchor"
	)
	await _free_player(player)


func _test_guardian_character_defense_prevents_then_consumes_ward() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_launch_config(&"time_guardian")),
		"Launch Time Guardian configures"
	)
	EventBus.room_started.emit(str(player.current_run_id()), &"room-1", 1)
	var health: Node = player.get_node("HealthComponent")

	_suite.assert_true(
		player.advance_action_frame(_character_press(&"hold")),
		"Guardian hold begins through semantic input"
	)
	for _frame: int in range(8):
		_suite.assert_true(player.advance_action_frame({}), "Guardian perfect window advances")
	var perfect: RefCounted = health.resolve_and_apply_damage(
		_enemy_damage(player, 20.0, &"enemy-perfect", 1)
	)
	_suite.assert_true(perfect != null and perfect.call("is_prevented"), "perfect Guard prevents true zero damage")
	_suite.assert_close(float(health.current_hp), 240.0, "perfect Guard preserves HP")
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		1,
		"perfect Guard grants exactly one Ward"
	)

	_suite.assert_true(
		player.advance_action_frame(_character_release(8)),
		"Guardian release closes the ordinary Guard"
	)
	var ward_hit: RefCounted = health.resolve_and_apply_damage(
		_enemy_damage(player, 20.0, &"enemy-ward", 2)
	)
	_suite.assert_true(ward_hit != null and not ward_hit.call("is_prevented"), "Ward hit remains applied damage")
	_suite.assert_close(float(ward_hit.call("finalized_damage")), 3.0, "Ward reduction precedes flat defense")
	_suite.assert_close(float(health.current_hp), 237.0, "Ward hit applies the canonical three damage")
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		0,
		"Ward is consumed exactly once"
	)
	await _free_player(player)


func _test_committed_time_fact_consumes_wanderer_mark_and_reduces_cooldown() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_launch_config(&"wanderer")),
		"Launch Wanderer configures for TimeAction integration"
	)
	EventBus.room_started.emit(str(player.current_run_id()), &"room-1", 1)
	_suite.assert_true(player.advance_action_frame({}), "Wanderer binding frame advances")
	var generation := int(player.character_action_coordinator.call("generation"))
	var mastery_result: Dictionary = player.character_action_coordinator.call(
		"on_weapon_mastery_confirmed",
		{
			"weapon_id": &"sword",
			"mastery_family": &"sword",
			"mastery_id": &"sword_perfect_guard",
			"action_id": &"weapon_primary",
			"generation": generation,
			"action_token": 77,
			"target_id": 1,
			"context": {
				"runtime_frame": 1,
				"run_id": player.current_run_id(),
				"run_revision": player.owner_character_generation(),
				"owner_character_generation": player.owner_character_generation(),
				"maximum_hp": 200.0,
			},
		}
	)
	_suite.assert_true(bool(mastery_result.get("ok", false)), "Wanderer mastery hook accepts a canonical fact")
	_suite.assert_true(
		player.apply_character_runtime_events(mastery_result.get("events", []) as Array),
		"Wanderer mastery events settle"
	)
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		1,
		"Wanderer owns one Path Mark before the TimeAction"
	)

	_suite.assert_true(
		player.advance_action_frame({
			"time": [{
				"id": &"time_stop",
				"edge": &"pressed",
				"held_frames": 0,
				"mode": &"press",
			}],
		}),
		"committed Time Stop advances through the frame transaction"
	)
	_suite.assert_equal(
		int(player.character_presentation_snapshot().get("resource_value", -1)),
		0,
		"committed TimeAction consumes exactly one Path Mark"
	)
	_suite.assert_true(
		bool(player.character_presentation_snapshot().get("wayfarer_active", false)),
		"committed TimeAction opens the Wayfarer window"
	)
	var manager: Node = player.get_node("TimeManager")
	var before_reduction := float(manager.get_cooldown(&"time_stop"))
	_suite.assert_true(before_reduction > 0.0, "Time Stop owns a committed cooldown")
	_suite.assert_true(
		manager.reduce_longer_equipped_cooldown_frames([&"stop", &"rewind"], 30),
		"fixed-frame cooldown reduction accepts equipped ability identities"
	)
	_suite.assert_close(
		float(manager.get_cooldown(&"time_stop")),
		before_reduction - 0.5,
		"fixed-frame reduction subtracts exactly 30 frames"
	)
	await _free_player(player)


func _test_wanderer_forgiveness_reaches_and_is_consumed_by_real_weapon_runtime() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.configure_loadout(_launch_config(&"wanderer")),
		"Launch Wanderer configures for forgiveness integration"
	)
	EventBus.room_started.emit(str(player.current_run_id()), &"room-forgiveness", 1)
	_suite.assert_true(player.advance_action_frame({}), "Wanderer forgiveness binding frame advances")
	_suite.assert_true(
		_confirm_wanderer_mastery(player, 201),
		"first real mastery conversion grants a Path Mark"
	)
	_suite.assert_true(
		player.advance_action_frame({
			"time": [{
				"id": &"time_stop",
				"edge": &"pressed",
				"held_frames": 0,
				"mode": &"press",
			}],
		}),
		"Wanderer Time Stop opens the Wayfarer conversion window"
	)
	for _frame: int in range(12):
		_suite.assert_true(player.advance_action_frame({}), "Wanderer Time Cast recovery advances")
	_suite.assert_true(
		_confirm_wanderer_mastery(player, 202),
		"mastery inside Wayfarer grants weapon forgiveness"
	)
	_suite.assert_true(
		not (_strategy_snapshot(player).get("forgiveness_descriptor", {}) as Dictionary).is_empty(),
		"Wanderer owns a frozen forgiveness descriptor before weapon planning"
	)

	_suite.assert_true(
		player.advance_action_frame(_weapon_intent(&"pressed", 0)),
		"real Sword hold freezes Wanderer forgiveness into the plan"
	)
	_suite.assert_true(
		not (_strategy_snapshot(player).get("forgiveness_descriptor", {}) as Dictionary).is_empty(),
		"starting a hold does not consume forgiveness"
	)
	for _frame: int in range(29):
		_suite.assert_true(player.advance_action_frame({}), "forgiven Sword hold advances")
	_suite.assert_true(
		player.advance_action_frame(_weapon_intent(&"released", 30)),
		"successful charged release commits the forgiven Sword action"
	)
	_suite.assert_true(
		(_strategy_snapshot(player).get("forgiveness_descriptor", {}) as Dictionary).is_empty(),
		"only the successful weapon commit consumes forgiveness"
	)
	var committed_plan := (
		player.weapon_action_coordinator.call("snapshot") as Dictionary
	).get("plan", {}) as Dictionary
	_suite.assert_equal(
		_phase_duration(committed_plan, &"RECOVERY"),
		18,
		"Wanderer forgiveness reduces charged Sword recovery from twenty-two to eighteen frames"
	)
	await _free_player(player)


func _confirm_wanderer_mastery(player: Node, token: int) -> bool:
	var result: Dictionary = player.character_action_coordinator.call(
		"on_weapon_mastery_confirmed",
		{
			"weapon_id": &"sword",
			"mastery_family": &"sword",
			"mastery_id": &"sword_perfect_guard",
			"action_id": &"weapon_primary",
			"generation": int(player.character_action_coordinator.call("generation")),
			"action_token": token,
			"target_id": token,
			"context": {
				"runtime_frame": int(_strategy_snapshot(player).get("last_runtime_frame", -1)),
				"run_id": player.current_run_id(),
				"run_revision": player.owner_character_generation(),
				"owner_character_generation": player.owner_character_generation(),
				"maximum_hp": 200.0,
			},
		}
	)
	return (
		bool(result.get("ok", false))
		and player.apply_character_runtime_events(result.get("events", []) as Array)
	)


func _strategy_snapshot(player: Node) -> Dictionary:
	return (
		(player.character_runtime_snapshot().get("runtime", {}) as Dictionary)
		.get("strategy", {}) as Dictionary
	).duplicate(true)


func _phase_duration(plan: Dictionary, phase_id: StringName) -> int:
	for phase_value: Variant in plan.get("phases", []) as Array:
		if phase_value is Dictionary and StringName(str(
			(phase_value as Dictionary).get("phase", "")
		)) == phase_id:
			return int((phase_value as Dictionary).get("duration_frames", -1))
	return -1


func _character_press(mode: StringName = &"press") -> Dictionary:
	return {
		"character": [{
			"id": &"character_skill",
			"edge": &"pressed",
			"held_frames": 0,
			"mode": mode,
		}],
	}


func _character_release(held_frames: int) -> Dictionary:
	return {
		"character": [{
			"id": &"character_skill",
			"edge": &"released",
			"held_frames": held_frames,
			"mode": &"hold",
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


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(player.reset_runtime_state(), "player fixture resets")
	return player


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
