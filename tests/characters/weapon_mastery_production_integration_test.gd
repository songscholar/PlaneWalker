extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class MasteryRecorder extends RefCounted:
	var facts: Array[Dictionary] = []


	func record(
		weapon_id: StringName,
		mastery_family: StringName,
		mastery_id: StringName,
		action_id: StringName,
		token: int,
		generation: int,
		target_id: int,
		context: Dictionary
	) -> void:
		facts.append({
			"weapon_id": weapon_id,
			"mastery_family": mastery_family,
			"mastery_id": mastery_id,
			"action_id": action_id,
			"token": token,
			"generation": generation,
			"target_id": target_id,
			"context": context.duplicate(true),
		})


var _suite
var _registry: RefCounted
var _recorder := MasteryRecorder.new()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(not report.call("has_blocking_errors"), "mastery production fixture loads Base Pack")
	EventBus.weapon_mastery_confirmed.connect(_recorder.record)
	await _test_sword_counter_and_charged_semantics_are_family_exactly_once()
	await _test_bow_weakpoint_penetration_and_echo_rejection()
	await _test_gun_perfect_reload_commit_context_reaches_mastery()
	await _test_staff_combo_and_controlled_zone_semantics()
	await _test_gauntlets_counter_threshold_and_finisher_semantics()
	EventBus.weapon_mastery_confirmed.disconnect(_recorder.record)
	_suite.finish(get_tree())


func _test_sword_counter_and_charged_semantics_are_family_exactly_once() -> void:
	var player := await _spawn_player(&"sword")
	var target := _stable_target(101)
	add_child(target)
	_track(player, 11, &"counter", {})
	player.call("_confirm_weapon_hit_mastery", _damage(player, 11, ["weapon:sword"]), target, 12.0, 11, 1)
	_suite.assert_equal(_latest_id(), &"sword_counter_confirmed", "Sword Counter hit produces its mastery")
	var before := _recorder.facts.size()
	player.call("_confirm_weapon_hit_mastery", _damage(player, 11, ["weapon:sword"]), target, 12.0, 11, 1)
	_suite.assert_equal(_recorder.facts.size(), before, "Sword family claim is exactly once per action token")
	await _free_nodes(player, target)

	player = await _spawn_player(&"sword")
	target = _stable_target(102)
	add_child(target)
	_track(player, 12, &"charged_slash", {"held_frames": 30, "full_charge": true})
	player.call("_confirm_weapon_hit_mastery", _damage(player, 12, ["weapon:sword"]), target, 18.0, 12, 1)
	_suite.assert_equal(_latest_id(), &"sword_charged_commitment", "thirty-frame charged Sword hit produces commitment mastery")
	await _free_nodes(player, target)


func _test_bow_weakpoint_penetration_and_echo_rejection() -> void:
	var player := await _spawn_player(&"bow")
	var weakpoint := _stable_target(201)
	weakpoint.set_meta("weakpoint_active", true)
	add_child(weakpoint)
	_track(player, 21, &"precision_draw", {"full_charge": true, "held_frames": 48})
	player.call("_confirm_weapon_hit_mastery", _damage(player, 21, ["weapon:bow", "attack:full_charge"]), weakpoint, 20.0, 21, 1)
	_suite.assert_equal(_latest_id(), &"bow_full_charge_weakpoint", "full-charge weakpoint hit produces Bow mastery")
	await _free_nodes(player, weakpoint)

	player = await _spawn_player(&"bow")
	var first := _stable_target(202)
	var second := _stable_target(203)
	add_child(first)
	add_child(second)
	_track(player, 22, &"precision_draw", {"full_charge": true, "held_frames": 48})
	var before := _recorder.facts.size()
	player.call("_confirm_weapon_hit_mastery", _damage(player, 22, ["weapon:bow", "attack:full_charge"]), first, 10.0, 22, 1)
	_suite.assert_equal(_recorder.facts.size(), before, "first ordinary Bow target only arms penetration progress")
	player.call("_confirm_weapon_hit_mastery", _damage(player, 22, ["weapon:bow", "attack:full_charge"]), second, 10.0, 22, 1)
	_suite.assert_equal(_latest_id(), &"bow_full_charge_penetration", "second distinct stable target produces Bow penetration mastery")
	await _free_nodes(player, first, second)

	player = await _spawn_player(&"bow")
	var echo_target := _stable_target(204)
	echo_target.set_meta("weakpoint_active", true)
	add_child(echo_target)
	_track(player, 23, &"precision_draw", {"full_charge": true, "held_frames": 48})
	before = _recorder.facts.size()
	player.call("_confirm_weapon_hit_mastery", _damage(player, 23, ["weapon:bow", "non_recursive:echo"]), echo_target, 10.0, 23, 1)
	_suite.assert_equal(_recorder.facts.size(), before, "echo-tagged Bow hit cannot mint mastery")
	await _free_nodes(player, echo_target)


func _test_gun_perfect_reload_commit_context_reaches_mastery() -> void:
	var player := await _spawn_player(&"gun")
	_track(player, 31, &"reload", {})
	player.call(
		"_confirm_weapon_action_commit_mastery",
		&"gun",
		&"reload",
		31,
		{"perfect_reload": true, "reload_frame": 31},
		{}
	)
	_suite.assert_equal(_latest_id(), &"gun_perfect_reload", "perfect reload commit context produces Gun mastery")
	_suite.assert_equal((_recorder.facts.back() as Dictionary).context.reload_frame, 31, "Gun mastery preserves the authoritative reload frame")
	await _free_nodes(player)


func _test_staff_combo_and_controlled_zone_semantics() -> void:
	var player := await _spawn_player(&"staff")
	_track(player, 41, &"charged_element", {})
	player.call("_confirm_weapon_payload_mastery", &"staff", 41, 41, {
		"hit": true,
		"hit_confirmed": true,
		"target_id": 301,
		"outcome_id": "staff:combo",
		"combination": {"combo_id": "steam_burst"},
	})
	_suite.assert_equal(_latest_id(), &"staff_ordered_combination", "confirmed ordered Staff combination produces mastery")
	await _free_nodes(player)

	player = await _spawn_player(&"staff")
	_track(player, 42, &"planar_collapse", {})
	var before := _recorder.facts.size()
	for target_id: int in [302, 303, 304]:
		player.call("_confirm_weapon_payload_mastery", &"staff", 42, 42, {
			"hit": true,
			"hit_confirmed": true,
			"target_id": target_id,
			"outcome_id": "staff:zone:%d" % target_id,
		})
	_suite.assert_equal(_recorder.facts.size(), before + 1, "third distinct Plane Collapse target mints one mastery")
	_suite.assert_equal(_latest_id(), &"staff_controlled_zone", "Plane Collapse uses controlled-zone mastery identity")
	await _free_nodes(player)


func _test_gauntlets_counter_threshold_and_finisher_semantics() -> void:
	var player := await _spawn_player(&"gauntlets")
	_track(player, 51, &"dodge_counter", {})
	player.call("_confirm_weapon_payload_mastery", &"gauntlets", 51, 51, {
		"hit": true, "hit_confirmed": true, "target_id": 401, "outcome_id": "counter",
		"combo_gain": 5,
	})
	_suite.assert_equal(_latest_id(), &"gauntlets_dodge_counter", "Dodge Counter hit produces Gauntlets mastery")
	await _free_nodes(player)

	player = await _spawn_player(&"gauntlets")
	_track(player, 52, &"punch_5", {})
	player.call("_confirm_weapon_payload_mastery", &"gauntlets", 52, 52, {
		"hit": true, "hit_confirmed": true, "target_id": 402, "outcome_id": "punch-five",
		"combo_gain": 1,
	})
	_suite.assert_equal(_latest_id(), &"gauntlets_chain_finisher", "Punch five hit produces chain-finisher mastery")
	await _free_nodes(player)


func _track(player: Node, token: int, action_id: StringName, context: Dictionary) -> void:
	player.call("_track_weapon_action_token", token, action_id, 1, context, {
		"weapon_id": str(player.loadout_runtime.weapon_id()),
		"action_id": str(action_id),
	})


func _damage(player: Node, token: int, tags: Array[String]) -> RefCounted:
	return DamageInfoScript.from_plan({
		"run_id": player.current_run_id(),
		"target_id": &"pending_target",
		"hostile_source_id": StringName("player:test:%d" % token),
		"attack_generation": 1,
		"hit_index": 0,
		"action_token": token,
		"amount": 10.0,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": player,
		"attacker": player,
		"tags": tags,
		"source_generation": 1,
	})


func _stable_target(target_id: int) -> Node:
	var target := Node.new()
	target.set_meta("stable_target_id", target_id)
	return target


func _latest_id() -> StringName:
	return StringName(str((_recorder.facts.back() as Dictionary).get("mastery_id", ""))) if not _recorder.facts.is_empty() else &""


func _launch_config(weapon_id: StringName) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"character_profile": _registry.call("resolve_character_runtime_profile", &"wanderer", &"LAUNCH"),
		"character_talents": [],
		"weapon_id": str(weapon_id),
		"weapon_profile": _registry.call("resolve_weapon_runtime_profile", weapon_id, &"LAUNCH"),
		"enabled_time_skills": [&"stop", &"rewind"],
		"difficulty": "normal",
		"seed": 20261001,
	}


func _spawn_player(weapon_id: StringName) -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(player.reset_runtime_state(), "%s fixture resets" % weapon_id)
	_suite.assert_true(player.configure_loadout(_launch_config(weapon_id)), "%s Launch loadout configures" % weapon_id)
	EventBus.room_started.emit(str(player.current_run_id()), &"room-mastery", 1)
	_suite.assert_true(player.advance_action_frame({}), "%s character binding frame advances" % weapon_id)
	return player


func _free_nodes(player: Node, first: Node = null, second: Node = null) -> void:
	for node: Node in [first, second, player]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
