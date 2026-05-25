extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const COMBAT_ROOM_SCENE := preload("res://scenes/rooms/combat_room_01.tscn")
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
	await _run_room_progression_check()
	await get_tree().process_frame
	get_tree().quit(1 if _failed else 0)


func _run_room_progression_check() -> void:
	GameState.start_run({"seed": 456})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	_assert_true(GameState.current_room == 1, "first combat room starts at one")

	for expected_room: int in range(2, 6):
		room._clear_room()
		room.get_node("RewardSelection")._select_reward(0)
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_true(GameState.current_room == expected_room, "reward advances to room %d" % expected_room)

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
