extends Node

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


class EchoHealth extends Node:
	var hits: Array[Dictionary] = []
	var alive: bool = true


	func take_damage(damage_info: RefCounted) -> float:
		if not alive:
			return 0.0
		hits.append({
			"amount": damage_info.amount,
			"damage_type": damage_info.damage_type,
			"tags": damage_info.tags.duplicate(),
		})
		return damage_info.amount


	func is_alive() -> bool:
		return alive


class EchoEnemy extends Node2D:
	var health: EchoHealth


	func _init() -> void:
		health = EchoHealth.new()
		health.name = "HealthComponent"
		add_child(health)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_transaction_is_deep_copied()
	await _test_build_effect_configuration()
	await _test_no_build_and_failed_transaction_create_no_echo()
	await _test_successful_commit_creates_one_timed_echo()
	await _test_path_blessing_hits_each_enemy_once()
	await _test_death_cancels_delayed_damage()
	await get_tree().create_timer(0.65).timeout
	await get_tree().process_frame
	_suite.finish(get_tree())


func _test_transaction_is_deep_copied() -> void:
	var player := await _spawn_player()
	var recorder: Node = player.get_node("RewindRecorder")
	player.global_position = Vector2(16.0, 20.0)
	recorder._record_snapshot()
	player.global_position = Vector2(48.0, 20.0)
	recorder._record_snapshot()
	player.global_position = Vector2(80.0, 20.0)

	var transaction: Dictionary = recorder.prepare_rewind_transaction()
	_suite.assert_equal(transaction["origin"], Vector2(80.0, 20.0), "transaction captures rewind origin")
	_suite.assert_equal(transaction["destination"], Vector2(16.0, 20.0), "transaction captures oldest destination")
	_suite.assert_equal(transaction["path_samples"], [Vector2(80.0, 20.0), Vector2(48.0, 20.0), Vector2(16.0, 20.0)], "transaction commits the reverse traversal path")

	recorder._snapshots[0]["position"] = Vector2(999.0, 999.0)
	recorder._snapshots[1]["position"] = Vector2(888.0, 888.0)
	_suite.assert_equal(transaction["target_snapshot"]["position"], Vector2(16.0, 20.0), "target snapshot is deeply copied")
	_suite.assert_equal(transaction["path_samples"], [Vector2(80.0, 20.0), Vector2(48.0, 20.0), Vector2(16.0, 20.0)], "path samples are deeply copied")
	await _free_player(player)


func _test_build_effect_configuration() -> void:
	var player := await _spawn_player()
	var time_manager: Node = player.get_node("TimeManager")
	ItemEffectScript.apply_to_player(player, {
		"rewind_echo_enabled": true,
		"rewind_path_hit_multiplier": 0.5,
	})
	_suite.assert_true(time_manager.rewind_echo_enabled, "item effect enables rewind echo")
	_suite.assert_close(time_manager.rewind_path_hit_multiplier, 0.5, "blessing effect configures one-shot path damage")
	await _free_player(player)


func _test_no_build_and_failed_transaction_create_no_echo() -> void:
	var no_build_player := await _spawn_player()
	var no_build_manager: Node = no_build_player.get_node("TimeManager")
	var no_build_recorder: Node = no_build_player.get_node("RewindRecorder")
	var no_build_runtime: Node = no_build_player.get_node("RewindEchoRuntime")
	no_build_runtime.set_process(false)
	_record_path(no_build_player, no_build_recorder)
	_suite.assert_true(no_build_manager.try_rewind(no_build_recorder), "normal rewind still succeeds without echo build")
	_suite.assert_equal(no_build_runtime.get_echo_start_count(), 0, "normal rewind creates no damaging afterimage")
	_suite.assert_true(not no_build_runtime.is_echo_active(), "no-build rewind leaves runtime inactive")
	await _free_player(no_build_player)

	var failed_player := await _spawn_player()
	var failed_manager: Node = failed_player.get_node("TimeManager")
	var failed_recorder: Node = failed_player.get_node("RewindRecorder")
	var failed_runtime: Node = failed_player.get_node("RewindEchoRuntime")
	failed_runtime.set_process(false)
	failed_manager.rewind_echo_enabled = true
	var empty_energy_before: float = failed_manager.energy
	_suite.assert_true(not failed_manager.try_rewind(failed_recorder), "empty rewind transaction fails")
	_suite.assert_equal(failed_runtime.get_echo_start_count(), 0, "empty rewind emits no echo commit")
	_suite.assert_close(failed_manager.energy, empty_energy_before, "empty rewind does not spend energy")
	_record_path(failed_player, failed_recorder)
	failed_recorder._snapshots.front().erase("hp")
	var energy_before: float = failed_manager.energy
	var cooldown_before: float = failed_manager.get_cooldown(&"time_rewind")
	_suite.assert_true(not failed_manager.try_rewind(failed_recorder), "invalid rewind transaction fails")
	_suite.assert_equal(failed_runtime.get_echo_start_count(), 0, "failed rewind emits no echo commit")
	_suite.assert_true(not failed_runtime.is_echo_active(), "failed rewind leaves no delayed runtime")
	_suite.assert_close(failed_manager.energy, energy_before, "failed rewind keeps energy")
	_suite.assert_close(failed_manager.get_cooldown(&"time_rewind"), cooldown_before, "failed rewind keeps cooldown")
	await _free_player(failed_player)


func _test_successful_commit_creates_one_timed_echo() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	var runtime: Node = player.get_node("RewindEchoRuntime")
	runtime.set_process(false)
	manager.rewind_echo_enabled = true
	player.stats.attack = 40.0
	player._apply_stats_to_components(false)

	var enemy := _spawn_enemy(Vector2(48.0, 20.0))
	var far_enemy := _spawn_enemy(Vector2(48.0, 180.0))
	_record_path(player, recorder)
	var committed_transactions: Array[Dictionary] = []
	manager.rewind_committed.connect(func(transaction: Dictionary) -> void:
		committed_transactions.append(transaction.duplicate(true))
	)
	_suite.assert_true(manager.try_rewind(recorder), "echo build commits a valid rewind")
	_suite.assert_equal(committed_transactions.size(), 1, "successful rewind emits one typed commit")
	_suite.assert_equal(runtime.get_echo_start_count(), 1, "one successful commit creates one echo")
	_suite.assert_true(runtime.is_echo_active(), "echo is active after committed rewind")
	_suite.assert_equal(runtime.get_committed_path(), [Vector2(80.0, 20.0), Vector2(48.0, 20.0), Vector2(16.0, 20.0)], "runtime owns the committed path")

	committed_transactions[0]["path_samples"][0] = Vector2(999.0, 999.0)
	_suite.assert_equal(runtime.get_committed_path()[0], Vector2(80.0, 20.0), "runtime isolates its path from signal listeners")
	runtime.advance(0.49)
	_suite.assert_equal(enemy.health.hits.size(), 0, "echo does not pulse before 0.5 seconds")
	runtime.advance(0.01)
	_suite.assert_equal(enemy.health.hits.size(), 1, "echo pulses once at 0.5 seconds")
	_suite.assert_close(enemy.health.hits[0]["amount"], 10.0, "echo pulse deals ATK times 0.25")
	_suite.assert_equal(enemy.health.hits[0]["damage_type"], DamageInfoScript.DamageType.TIME, "echo pulse deals time damage")
	_suite.assert_true(enemy.health.hits[0]["tags"].has("time:rewind_echo_pulse"), "pulse damage carries the rewind echo tag")
	_suite.assert_equal(far_enemy.health.hits.size(), 0, "echo does not damage enemies outside the path radius")
	runtime.advance(0.5)
	_suite.assert_equal(enemy.health.hits.size(), 2, "the next pulse can hit the enemy once again")
	runtime.advance(1.0)
	_suite.assert_equal(enemy.health.hits.size(), 4, "two-second echo resolves exactly four pulses")
	_suite.assert_true(not runtime.is_echo_active(), "echo cleans itself after two seconds")
	_suite.assert_equal(runtime.get_proxy_point_count(), 0, "cleanup removes the path proxy")
	await _free_enemy(enemy)
	await _free_enemy(far_enemy)
	await _free_player(player)


func _test_path_blessing_hits_each_enemy_once() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	var runtime: Node = player.get_node("RewindEchoRuntime")
	runtime.set_process(false)
	manager.rewind_echo_enabled = true
	manager.rewind_path_hit_multiplier = 0.5
	player.stats.attack = 30.0
	player._apply_stats_to_components(false)

	var enemy := _spawn_enemy(Vector2(48.0, 20.0))
	_record_path(player, recorder)
	_suite.assert_true(manager.try_rewind(recorder), "blessed rewind commits")
	runtime.advance(0.1)
	runtime.advance(0.1)
	_suite.assert_equal(_count_tagged_hits(enemy.health.hits, "time:rewind_path_hit"), 1, "path blessing hits an enemy only once per rewind")
	var path_hit: Dictionary = _find_tagged_hit(enemy.health.hits, "time:rewind_path_hit")
	_suite.assert_close(float(path_hit.get("amount", 0.0)), 15.0, "path blessing deals ATK times 0.50")
	runtime.advance(1.8)
	_suite.assert_equal(_count_tagged_hits(enemy.health.hits, "time:rewind_path_hit"), 1, "pulse processing cannot duplicate blessing damage")
	await _free_enemy(enemy)
	await _free_player(player)


func _test_death_cancels_delayed_damage() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	var runtime: Node = player.get_node("RewindEchoRuntime")
	var health: Node = player.get_node("HealthComponent")
	runtime.set_process(false)
	manager.rewind_echo_enabled = true
	var enemy := _spawn_enemy(Vector2(48.0, 20.0))
	_record_path(player, recorder)
	_suite.assert_true(manager.try_rewind(recorder), "rewind starts an echo before owner death")
	health.lose_health(health.current_hp, &"test:death")
	_suite.assert_true(not runtime.is_echo_active(), "owner death cancels active echo immediately")
	runtime.advance(2.0)
	_suite.assert_equal(enemy.health.hits.size(), 0, "cancelled echo creates no delayed damage")
	await _free_enemy(enemy)
	await _free_player(player)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	return player


func _record_path(player: Node2D, recorder: Node) -> void:
	recorder.clear_snapshots()
	player.global_position = Vector2(16.0, 20.0)
	recorder._record_snapshot()
	player.global_position = Vector2(48.0, 20.0)
	recorder._record_snapshot()
	player.global_position = Vector2(80.0, 20.0)


func _spawn_enemy(enemy_position: Vector2) -> EchoEnemy:
	var enemy := EchoEnemy.new()
	enemy.add_to_group("enemies")
	enemy.global_position = enemy_position
	add_child(enemy)
	return enemy


func _free_player(player: Node) -> void:
	if is_instance_valid(player):
		var health := player.get_node_or_null("HealthComponent")
		if health != null and bool(health.get("invulnerable")):
			await get_tree().create_timer(0.55).timeout
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _free_enemy(enemy: Node) -> void:
	if is_instance_valid(enemy):
		enemy.queue_free()
	await get_tree().process_frame


func _count_tagged_hits(hits: Array[Dictionary], tag: String) -> int:
	var count := 0
	for hit: Dictionary in hits:
		if hit["tags"].has(tag):
			count += 1
	return count


func _find_tagged_hit(hits: Array[Dictionary], tag: String) -> Dictionary:
	for hit: Dictionary in hits:
		if hit["tags"].has(tag):
			return hit
	return {}
