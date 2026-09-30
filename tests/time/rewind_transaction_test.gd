extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")

var _suite
var _started_count: int = 0
var _ended_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.time_skill_started.connect(_on_time_skill_started)
	EventBus.time_skill_ended.connect(_on_time_skill_ended)

	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame

	var health: Node = player.get_node("HealthComponent")
	var time_manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	_suite.assert_true(player.configure_run(&"rewind-transaction-run"), "rewind fixture installs one authoritative run")
	_suite.assert_equal(str(recorder.current_run_id()), "rewind-transaction-run", "player injects the same run identity into Rewind")

	player.global_position = Vector2(48.0, 72.0)
	player.velocity = Vector2(12.0, -4.0)
	player._last_move_direction = Vector2.UP
	health.current_hp = 80.0
	time_manager.energy = 15.0
	recorder._record_snapshot()
	player.global_position = Vector2(56.0, 80.0)
	recorder._record_snapshot()
	var oldest_snapshot: Dictionary = recorder.peek_oldest_snapshot()

	_suite.assert_true(recorder.has_snapshot(), "rewind recorder captures a snapshot")
	_suite.assert_true(not oldest_snapshot.has("energy"), "rewind snapshot excludes energy")
	_suite.assert_true(not oldest_snapshot.has("cooldowns"), "rewind snapshot excludes cooldowns")
	_suite.assert_equal(str(oldest_snapshot.get("run_id", "")), "rewind-transaction-run", "rewind snapshot carries authoritative run identity")
	_suite.assert_close(
		float(oldest_snapshot.get("irreversible_hp_loss_total", -1.0)),
		0.0,
		"rewind snapshot carries the irreversible loss total"
	)
	_suite.assert_equal(
		int(oldest_snapshot.get("irreversible_hp_loss_revision", -1)),
		0,
		"rewind snapshot carries the irreversible loss revision"
	)

	player.global_position = Vector2(260.0, 180.0)
	player.velocity = Vector2.ZERO
	player._last_move_direction = Vector2.RIGHT
	health.current_hp = 25.0
	time_manager.energy = 90.0
	time_manager.rewind_cost = 45.0
	time_manager.rewind_self_damage = 18.0
	time_manager.rewind_heal = 28.0

	var did_rewind: bool = time_manager.try_rewind(recorder)
	_suite.assert_true(did_rewind, "valid rewind succeeds")
	_suite.assert_equal(player.global_position, Vector2(48.0, 72.0), "rewind restores player position")
	_suite.assert_equal(player.velocity, Vector2(12.0, -4.0), "rewind restores player velocity")
	_suite.assert_equal(player._last_move_direction, Vector2.UP, "rewind restores player facing")
	_suite.assert_close(health.current_hp, 90.0, "rewind settles hp restore, self-damage, then build healing")
	_suite.assert_close(time_manager.energy, 45.0, "rewind pays cost from current energy without restoring snapshot energy")
	_suite.assert_close(time_manager.get_cooldown(&"time_rewind"), time_manager.rewind_cooldown, "successful rewind starts cooldown once")
	_suite.assert_equal(_started_count, 1, "successful rewind emits one start event")
	_suite.assert_equal(_ended_count, 1, "successful rewind emits one end event")
	_suite.assert_true(not recorder.has_snapshot(), "successful rewind discards the invalidated timeline")
	_suite.assert_equal(
		health.hp_loss_state(),
		{"irreversible_hp_loss_total": 18.0, "revision": 1},
		"successful legacy rewind cannot refund its irreversible self-cost"
	)

	var energy_before_empty: float = time_manager.energy
	var cooldown_before_empty: float = time_manager.get_cooldown(&"time_rewind")
	var empty_result: bool = time_manager.try_rewind(recorder)
	_suite.assert_true(not empty_result, "empty rewind fails")
	_suite.assert_close(time_manager.energy, energy_before_empty, "empty rewind does not spend energy")
	_suite.assert_close(time_manager.get_cooldown(&"time_rewind"), cooldown_before_empty, "empty rewind does not change cooldown")
	_suite.assert_equal(_started_count, 1, "empty rewind emits no start event")
	_suite.assert_equal(_ended_count, 1, "empty rewind emits no end event")

	recorder._record_snapshot()
	_suite.assert_true(recorder.has_snapshot(), "recorder can capture after rewind")
	var post_rewind_snapshot: Dictionary = recorder.peek_oldest_snapshot()
	_suite.assert_close(
		float(post_rewind_snapshot.get("irreversible_hp_loss_total", -1.0)),
		18.0,
		"post-rewind snapshots carry the live irreversible loss total"
	)
	_suite.assert_equal(
		int(post_rewind_snapshot.get("irreversible_hp_loss_revision", -1)),
		1,
		"post-rewind snapshots carry the live irreversible loss revision"
	)
	recorder.clear_snapshots()
	_suite.assert_true(not recorder.has_snapshot(), "clear snapshots removes recorded history")

	recorder._record_snapshot()
	recorder._snapshots.front().erase("hp")
	var invalid_snapshot_count: int = recorder._snapshots.size()
	var energy_before_invalid: float = time_manager.energy
	var cooldown_before_invalid: float = time_manager.get_cooldown(&"time_rewind")
	var hp_loss_before_invalid: Dictionary = health.hp_loss_state()
	var invalid_result: bool = time_manager.try_rewind(recorder)
	_suite.assert_true(not invalid_result, "invalid snapshot fails without committing")
	_suite.assert_equal(recorder._snapshots.size(), invalid_snapshot_count, "failed rewind retains snapshot history")
	_suite.assert_close(time_manager.energy, energy_before_invalid, "failed rewind keeps energy")
	_suite.assert_close(time_manager.get_cooldown(&"time_rewind"), cooldown_before_invalid, "failed rewind keeps cooldown")
	_suite.assert_equal(health.hp_loss_state(), hp_loss_before_invalid, "failed rewind cannot mutate irreversible loss state")
	recorder.clear_snapshots()

	EventBus.time_skill_started.disconnect(_on_time_skill_started)
	EventBus.time_skill_ended.disconnect(_on_time_skill_ended)
	await get_tree().create_timer(0.65).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.finish(get_tree())


func _on_time_skill_started(skill_id: StringName, _context: Dictionary) -> void:
	if skill_id == &"time_rewind":
		_started_count += 1


func _on_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
	if skill_id == &"time_rewind":
		_ended_count += 1
