extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const COMBAT_ROOM_SCENE := preload("res://scenes/rooms/combat_room_01.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame

	var health: Node = player.get_node("HealthComponent")
	var time_manager: Node = player.get_node("TimeManager")
	var sword: Node = player.get_node("SwordWeapon")

	_assert_close(player.stats.attack, 30.0, "base attack")
	_assert_close(sword.base_attack, 30.0, "base sword attack")

	player.apply_reward({
		"id": "test_power",
		"effects": {
			"attack_multiplier": 1.5,
			"attack_speed_multiplier": 1.2,
			"max_hp_bonus": 20.0,
			"defense_bonus": 2.0,
			"time_energy_max_bonus": 25.0,
			"time_energy_regen_bonus": 1.25,
			"time_energy_restore": 10.0,
			"heal": 5.0,
		},
	})

	_assert_close(player.stats.attack, 45.0, "reward attack")
	_assert_close(sword.base_attack, 45.0, "reward sword attack")
	_assert_close(sword.attack_speed, 1.2, "reward sword speed")
	_assert_close(health.max_hp, 220.0, "reward max hp")
	_assert_close(health.defense, 2.0, "reward defense")
	_assert_close(time_manager.max_energy, 125.0, "reward max time energy")
	_assert_close(time_manager.energy_regen, 3.25, "reward time regen")

	GameState.start_run({"seed": 123})
	GameState.add_run_reward({"id": "test_power", "effects": {}})
	_assert_true(GameState.current_run.get("inventory", []).has("test_power"), "run inventory records reward")
	_assert_true(GameState.current_room == 0, "run starts before first room")

	var first_roll := RewardPoolScript.roll_options(3, 123, 1, [])
	var second_roll := RewardPoolScript.roll_options(3, 123, 1, [])
	_assert_true(_reward_ids(first_roll) == _reward_ids(second_roll), "reward roll is deterministic")

	player.queue_free()
	await _run_death_check()
	await _run_room_progression_check()
	await _run_death_overlay_check()
	await get_tree().process_frame
	get_tree().quit(1 if _failed else 0)


func _run_death_check() -> void:
	var deaths_before := GameState.death_count
	GameState.start_run({"seed": 321})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame

	var room_player: Node = room.get_node("Player")
	var fatal_damage := DamageInfoScript.new(9999.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	room_player.get_node("HealthComponent").take_damage(fatal_damage)
	await get_tree().process_frame

	_assert_true(GameState.phase == GameState.GamePhase.DEATH, "player death enters death phase")
	_assert_true(GameState.last_run_result.get("result", "") == "death", "death records run result")
	_assert_true(GameState.last_run_result.get("rooms_cleared", -1) == 0, "death records cleared rooms")
	_assert_true(GameState.last_run_result.get("current_room", -1) == 1, "death records current room")
	_assert_true(GameState.death_count == deaths_before + 1, "death count increments")
	_assert_true(room.get_node("RewardMarker").visible == false, "death hides reward marker")

	room.queue_free()
	await get_tree().process_frame


func _run_death_overlay_check() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var room_player: Node = main.get_node("CombatRoom01/Player")
	var fatal_damage := DamageInfoScript.new(9999.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	room_player.get_node("HealthComponent").take_damage(fatal_damage)
	await get_tree().process_frame

	var overlay: CanvasLayer = main.get_node("RunEndOverlay")
	var label: Label = main.get_node("RunEndOverlay/Panel/Margin/VBox/ResultLabel")
	_assert_true(overlay.visible, "death shows run end overlay")
	_assert_true(label.text.contains("Run Failed"), "death overlay shows failed result")

	main.queue_free()
	await get_tree().process_frame


func _run_room_progression_check() -> void:
	GameState.start_run({"seed": 456})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(GameState.current_room == 1, "first combat room starts at one")

	for expected_room: int in range(2, 6):
		room._clear_room()
		var reward_title: Label = room.get_node("RewardSelection/Panel/Margin/VBox/Title")
		_assert_true(reward_title.text.contains("Room %d" % GameState.current_room), "reward title includes cleared room")
		room.get_node("RewardSelection")._select_reward(0)
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_true(GameState.current_room == expected_room, "reward advances to room %d" % expected_room)

	var enemies := _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")
	var boss_panel: PanelContainer = room.get_node("CombatHUD/BossPanel")
	var boss_hp_bar: ProgressBar = room.get_node("CombatHUD/BossPanel/VBox/BossHPBar")
	_assert_true(GameState.phase == GameState.GamePhase.BOSS_FIGHT, "fifth room enters boss phase")
	_assert_true(enemies.size() == 1, "boss room spawns one enemy")
	_assert_true(enemies[0].is_in_group("bosses"), "fifth room enemy is boss")
	await get_tree().process_frame
	_assert_true(boss_panel.visible, "boss room shows boss panel")
	_assert_close(boss_hp_bar.max_value, enemies[0].health.max_hp, "boss hp max binds to health")
	enemies[0].apply_time_stop(0.1)
	await get_tree().process_frame
	_assert_close(enemies[0].health.defense, 0.0, "time stop exposes boss")

	room._clear_room()
	room.get_node("RewardSelection")._select_reward(0)
	await get_tree().process_frame
	_assert_true(GameState.phase == GameState.GamePhase.RUN_END, "final room ends run")
	room.queue_free()
	await get_tree().process_frame


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("Smoke test failed: %s" % label)


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) <= 0.001:
		return
	_failed = true
	push_error("Smoke test failed: %s expected %.3f got %.3f" % [label, expected, actual])


func _reward_ids(rewards: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for reward: Dictionary in rewards:
		ids.append(str(reward.get("id", "")))
	return ids


func _nodes_in_group(nodes: Array, group_name: StringName) -> Array:
	var matches: Array = []
	for node: Node in nodes:
		if node.is_in_group(group_name):
			matches.append(node)
	return matches
