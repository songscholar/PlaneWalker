extends Node

const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const EnemyProjectileScript := preload("res://scripts/enemies/enemy_projectile.gd")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const EnemyChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const EnemyProjectileScene := preload("res://scenes/enemies/enemy_projectile.tscn")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeRiftScene := preload("res://scenes/time/time_rift.tscn")

const ABILITY_IDS := ["stop", "rewind", "rift", "accelerate"]
const LOADOUTS := [
	["stop", "rewind"],
	["stop", "rift"],
	["stop", "accelerate"],
	["rewind", "rift"],
	["rewind", "accelerate"],
	["rift", "accelerate"],
]

class RewindRecorderStub:
	extends Node

	func has_snapshot() -> bool:
		return true

	func prepare_rewind_transaction() -> Dictionary:
		return {"target_snapshot": {"position": Vector2.ZERO}}

	func restore_player_state(_snapshot: Dictionary) -> bool:
		return true

	func consume_oldest_snapshot() -> Dictionary:
		return {"position": Vector2.ZERO}

	func clear_snapshots() -> void:
		pass


class ReplayStopTarget extends Node:
	var apply_calls: int = 0
	var clear_calls: int = 0
	var sources: Dictionary = {}

	func _ready() -> void:
		add_to_group("time_stoppable")

	func apply_time_stop_source(source_id: StringName, _duration: float) -> void:
		apply_calls += 1
		sources[source_id] = true

	func clear_time_stop_source(source_id: StringName) -> void:
		clear_calls += 1
		sources.erase(source_id)

	func is_time_stopped() -> bool:
		return not sources.is_empty()

var _suite
var _time_started: Dictionary = {}
var _time_ended: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.time_skill_started.connect(_on_time_skill_started)
	EventBus.time_skill_ended.connect(_on_time_skill_ended)
	await _test_time_manager_generic_contract()
	await _test_time_self_damage_uses_unique_claims_and_survives_same_run_reset()
	await _test_active_stop_and_accelerate_reject_reapply()
	await _test_cancel_clears_real_time_stop_targets()
	await _test_replay_restore_reconciles_real_time_stop_targets()
	await _test_pause_freezes_real_time_stop_targets()
	await _test_manager_stop_honors_real_elite_resistance()
	await _test_six_unordered_pairs_gate_all_actions()
	await _test_rejections_are_atomic()
	await _test_time_cast_buffer_uses_single_action_clock()
	await _test_accelerate_cancel_ignores_stale_expiry()
	await _test_pause_freezes_active_duration()
	await _test_disabled_player_freezes_inherited_time_clock()
	await _test_death_cancels_every_active_time_effect_once()
	await _test_legacy_acceleration_automatically_expires()
	await _test_rift_source_recomputation()
	await _test_boss_rift_exposure_tracks_each_source()
	await _test_projectile_rift_changes_actual_movement()
	await _test_rift_area_tracks_enemy_projectiles()
	get_tree().paused = false
	EventBus.time_skill_started.disconnect(_on_time_skill_started)
	EventBus.time_skill_ended.disconnect(_on_time_skill_ended)
	_suite.finish(get_tree())


func _test_time_manager_generic_contract() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	_suite.assert_equal(_method_argument_count(manager, &"can_use"), 2, "time manager exposes can_use(skill_id, context)")
	_suite.assert_equal(_method_argument_count(manager, &"try_use"), 2, "time manager exposes try_use(skill_id, context)")
	_suite.assert_equal(_method_argument_count(manager, &"cancel_all_time_effects"), 1, "time manager exposes cancel_all_time_effects(reason)")
	await _free_player(player)


func _test_time_self_damage_uses_unique_claims_and_survives_same_run_reset() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_run(&"time-self-damage-run"), "self-damage fixture installs one authoritative run")
	var manager: Node = player.get_node("TimeManager")
	var health: Node = player.get_node("HealthComponent")
	health.current_hp = health.max_hp

	_suite.assert_true(
		bool(manager.call("_take_self_damage", 4.0, &"curse:time_stop")),
		"first Stop self-damage compatibility claim commits"
	)
	_suite.assert_true(
		bool(manager.call("_take_self_damage", 4.0, &"curse:time_stop")),
		"second Stop self-damage compatibility claim commits"
	)
	_suite.assert_equal(
		health.hp_loss_state(),
		{"irreversible_hp_loss_total": 8.0, "revision": 2},
		"repeated Stop self-damage uses a unique compatibility claim each time"
	)
	_suite.assert_close(health.current_hp, health.max_hp - 8.0, "two Stop costs each remove HP once")

	player.reset_runtime_state()
	_suite.assert_equal(
		health.hp_loss_state(),
		{"irreversible_hp_loss_total": 8.0, "revision": 2},
		"same-run runtime reset cannot refund irreversible self-damage"
	)
	_suite.assert_true(
		bool(manager.call("_take_self_damage", 4.0, &"curse:time_stop")),
		"same-run reset preserves a fresh Stop compatibility identity"
	)
	_suite.assert_true(
		bool(manager.call("_take_self_damage", 5.0, &"curse:rewind")),
		"Rewind self-damage compatibility claim commits"
	)
	_suite.assert_equal(
		health.hp_loss_state(),
		{"irreversible_hp_loss_total": 17.0, "revision": 4},
		"same-run reset preserves the token floor and Rewind receives its own unique claim"
	)
	_suite.assert_close(
		health.current_hp,
		health.max_hp - 9.0,
		"post-reset Stop and Rewind costs both apply without duplicate-claim rejection"
	)
	_suite.assert_equal(str(player.current_run_id()), "time-self-damage-run", "same-run reset preserves the authoritative run id")
	await _free_player(player)


func _test_active_stop_and_accelerate_reject_reapply() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_stop_duration = 0.20
	manager.time_stop_cooldown = 0.02
	var stop_starts_before := _start_count(&"time_stop")
	var stop_ends_before := _end_count(&"time_stop")
	_suite.assert_true(manager.try_use(&"time_stop", {}), "long Stop commits once")
	manager.call("_process", 0.03)
	var stop_energy_before_retry: float = manager.energy
	_suite.assert_true(not manager.can_use(&"time_stop", {}), "active Stop remains unavailable after its shorter cooldown ends")
	_suite.assert_true(not manager.try_use(&"time_stop", {}), "active Stop rejects reapplication")
	_suite.assert_close(manager.energy, stop_energy_before_retry, "rejected active Stop spends no additional energy")
	_suite.assert_equal(_start_count(&"time_stop"), stop_starts_before + 1, "active Stop publishes only one start")
	manager.cancel_all_time_effects(&"active_reapply_test")
	_suite.assert_equal(_end_count(&"time_stop"), stop_ends_before + 1, "the single active Stop publishes one end")

	player.reset_runtime_state()
	manager.energy_regen = 0.0
	manager.time_accelerate_duration = 0.20
	manager.time_accelerate_cooldown = 0.02
	var accelerate_starts_before := _start_count(&"time_accelerate")
	var accelerate_ends_before := _end_count(&"time_accelerate")
	_suite.assert_true(manager.try_use(&"time_accelerate", {}), "long Accelerate commits once")
	manager.call("_process", 0.03)
	var accelerate_energy_before_retry: float = manager.energy
	_suite.assert_true(not manager.can_use(&"time_accelerate", {}), "active Accelerate remains unavailable after its shorter cooldown ends")
	_suite.assert_true(not manager.try_use(&"time_accelerate", {}), "active Accelerate rejects reapplication")
	_suite.assert_close(manager.energy, accelerate_energy_before_retry, "rejected active Accelerate spends no additional energy")
	_suite.assert_equal(_start_count(&"time_accelerate"), accelerate_starts_before + 1, "active Accelerate publishes only one start")
	manager.cancel_all_time_effects(&"active_reapply_test")
	_suite.assert_equal(_end_count(&"time_accelerate"), accelerate_ends_before + 1, "the single active Accelerate publishes one end")
	await _free_player(player)


func _test_cancel_clears_real_time_stop_targets() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.time_stop_duration = 0.40
	var enemy := EnemyChaserScene.instantiate()
	var projectile := EnemyProjectileScene.instantiate()
	add_child(enemy)
	add_child(projectile)
	enemy.set_physics_process(false)
	projectile.set_physics_process(false)
	await get_tree().process_frame

	_suite.assert_true(manager.try_time_stop(), "real-target Stop commits")
	_suite.assert_true(enemy.is_time_stopped(), "real enemy receives Stop")
	_suite.assert_true(projectile.is_time_stopped(), "real projectile receives Stop")
	manager.cancel_all_time_effects(&"explicit_cancel")
	_suite.assert_true(not enemy.is_time_stopped(), "cancel_all immediately releases the real enemy")
	_suite.assert_true(not projectile.is_time_stopped(), "cancel_all immediately releases the real projectile")

	# Existing asynchronous target timers must settle even while this test is red.
	await get_tree().create_timer(0.45).timeout
	enemy.queue_free()
	projectile.queue_free()
	await get_tree().process_frame
	await _free_player(player)


func _test_replay_restore_reconciles_real_time_stop_targets() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	var enemy := EnemyChaserScene.instantiate()
	var projectile := EnemyProjectileScene.instantiate()
	var probe := ReplayStopTarget.new()
	add_child(enemy)
	add_child(projectile)
	add_child(probe)
	enemy.set_physics_process(false)
	projectile.set_physics_process(false)
	await get_tree().process_frame

	var inactive_snapshot: Dictionary = manager.weapon_replay_snapshot()
	var impossible_rewind_generation := inactive_snapshot.duplicate(true)
	impossible_rewind_generation["rewind_window_remaining"] = 1.0
	impossible_rewind_generation["rewind_window_generation"] = 0
	_suite.assert_true(
		not manager.restore_weapon_replay_snapshot(impossible_rewind_generation),
		"active Rewind replay window requires a positive generation"
	)
	var impossible_rewind_claim := inactive_snapshot.duplicate(true)
	impossible_rewind_claim["rewind_window_remaining"] = 1.0
	impossible_rewind_claim["rewind_window_generation"] = 7
	impossible_rewind_claim["rewind_window_claimed"] = true
	_suite.assert_true(
		not manager.restore_weapon_replay_snapshot(impossible_rewind_claim),
		"active Rewind replay window cannot already be claimed"
	)
	var valid_claimed_rewind := inactive_snapshot.duplicate(true)
	valid_claimed_rewind["rewind_window_generation"] = 7
	valid_claimed_rewind["rewind_window_claimed"] = true
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(valid_claimed_rewind),
		"closed Rewind replay window preserves its positive claimed generation"
	)
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(inactive_snapshot),
		"Rewind replay fixture restores its initial cleared state"
	)
	var active_snapshot := inactive_snapshot.duplicate(true)
	active_snapshot["stop_active"] = true
	active_snapshot["stop_source_sequence"] = 41
	active_snapshot["stop_source_id"] = "replay_stop:41"
	active_snapshot["stop_remaining"] = 0.40
	var zero_remaining := active_snapshot.duplicate(true)
	zero_remaining["stop_remaining"] = 0.0
	_suite.assert_true(
		not manager.restore_weapon_replay_snapshot(zero_remaining),
		"active Stop replay snapshot with zero remaining duration fails closed"
	)
	_suite.assert_true(not probe.is_time_stopped(), "rejected zero-duration Stop changes no real target")
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(active_snapshot),
		"replay restore accepts an authoritative active Stop snapshot"
	)
	_suite.assert_true(enemy.is_time_stopped(), "active Stop replay restore stops the real enemy")
	_suite.assert_true(projectile.is_time_stopped(), "active Stop replay restore stops the real projectile")
	_suite.assert_equal(probe.apply_calls, 1, "active Stop replay restore applies its source once")
	_suite.assert_equal(probe.clear_calls, 0, "initial active Stop replay restore clears no source")
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(active_snapshot),
		"repeated active Stop replay restore is accepted idempotently"
	)
	_suite.assert_equal(probe.apply_calls, 1, "repeated active Stop restore does not reapply its source")
	_suite.assert_equal(probe.clear_calls, 0, "repeated active Stop restore does not clear its source")

	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(inactive_snapshot),
		"replay restore accepts the authoritative inactive Stop snapshot"
	)
	_suite.assert_true(not enemy.is_time_stopped(), "inactive Stop replay restore releases the real enemy")
	_suite.assert_true(not projectile.is_time_stopped(), "inactive Stop replay restore releases the real projectile")
	_suite.assert_equal(probe.clear_calls, 1, "inactive Stop replay restore clears the active source once")

	# Restored target timers must settle before fixture teardown.
	await get_tree().create_timer(0.45).timeout
	enemy.queue_free()
	projectile.queue_free()
	probe.queue_free()
	await get_tree().process_frame
	await _free_player(player)


func _test_pause_freezes_real_time_stop_targets() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.time_stop_duration = 0.12
	var enemy := EnemyChaserScene.instantiate()
	var projectile := EnemyProjectileScene.instantiate()
	add_child(enemy)
	add_child(projectile)
	enemy.set_physics_process(false)
	projectile.set_physics_process(false)
	await get_tree().process_frame

	_suite.assert_true(manager.try_time_stop(), "paused real-target Stop commits")
	var remaining_before: float = float(manager.get("_time_stop_remaining"))
	get_tree().paused = true
	await get_tree().create_timer(0.18, true).timeout
	_suite.assert_close(float(manager.get("_time_stop_remaining")), remaining_before, "pause freezes the authoritative Stop duration", 0.01)
	_suite.assert_true(enemy.is_time_stopped(), "pause preserves the real enemy Stop state")
	_suite.assert_true(projectile.is_time_stopped(), "pause preserves the real projectile Stop state")
	get_tree().paused = false
	manager.cancel_all_time_effects(&"pause_cleanup")
	await get_tree().create_timer(0.15).timeout
	enemy.queue_free()
	projectile.queue_free()
	await get_tree().process_frame
	await _free_player(player)


func _test_manager_stop_honors_real_elite_resistance() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.time_stop_duration = 0.20
	var normal_enemy := EnemyChaserScene.instantiate()
	var elite_enemy := EnemyChaserScene.instantiate()
	add_child(normal_enemy)
	add_child(elite_enemy)
	normal_enemy.set_physics_process(false)
	elite_enemy.set_physics_process(false)
	await get_tree().process_frame
	elite_enemy.apply_elite_modifier()
	elite_enemy.elite_time_stop_multiplier = 0.5
	var starts_before := _start_count(&"time_stop")
	var ends_before := _end_count(&"time_stop")

	_suite.assert_true(manager.try_time_stop(), "manager commits Stop against real normal and elite targets")
	_suite.assert_true(normal_enemy.is_time_stopped(), "normal target receives manager Stop")
	_suite.assert_true(elite_enemy.is_time_stopped(), "elite target receives manager Stop")
	_suite.assert_equal(_start_count(&"time_stop"), starts_before + 1, "manager Stop publishes one start")
	await get_tree().create_timer(0.13).timeout
	_suite.assert_true(not elite_enemy.is_time_stopped(), "elite target recovers after its resisted half duration")
	_suite.assert_true(normal_enemy.is_time_stopped(), "normal target remains stopped after elite recovery")
	_suite.assert_true(bool(manager.get("_time_stop_active")), "manager remains active for the full Stop duration")
	_suite.assert_equal(_end_count(&"time_stop"), ends_before, "elite recovery does not end the manager effect early")

	await get_tree().create_timer(0.13).timeout
	_suite.assert_true(not normal_enemy.is_time_stopped(), "normal target recovers at the full duration")
	_suite.assert_true(not elite_enemy.is_time_stopped(), "elite target remains recovered at final cleanup")
	_suite.assert_true(not bool(manager.get("_time_stop_active")), "manager ends after the full Stop duration")
	_suite.assert_equal(_end_count(&"time_stop"), ends_before + 1, "manager Stop publishes exactly one final end")
	normal_enemy.queue_free()
	elite_enemy.queue_free()
	await get_tree().process_frame
	await _free_player(player)


func _test_six_unordered_pairs_gate_all_actions() -> void:
	for pair: Array in LOADOUTS:
		var player := await _spawn_player()
		var config := _config(pair)
		_suite.assert_true(player.configure_loadout(config), "%s configures" % str(pair))
		for ability_id: String in ABILITY_IDS:
			_suite.assert_true(player.configure_loadout(config), "%s resets before %s" % [str(pair), ability_id])
			var manager: Node = player.get_node("TimeManager")
			manager.energy_regen = 0.0
			manager.time_stop_duration = 0.02
			manager.time_rift_duration = 0.02
			manager.time_accelerate_duration = 0.02
			if ability_id == "rewind":
				_prepare_rewind(player)

			var action_id := StringName("time_%s" % ability_id)
			var energy_before: float = manager.energy
			var cooldown_before: float = manager.get_cooldown(action_id)
			var facts_before := _fact_total()
			var rifts_before := get_tree().get_nodes_in_group("time_rifts").size()
			var accelerated_before: bool = player.is_time_accelerated()
			var committed: bool = player.try_action(action_id)
			var expected: bool = pair.has(ability_id)

			_suite.assert_equal(committed, expected, "%s follows equipped pair %s" % [ability_id, str(pair)])
			if expected:
				_suite.assert_equal(_start_count(action_id), _start_count_before(facts_before, action_id) + 1, "%s publishes one start on commit" % ability_id)
			else:
				_suite.assert_close(manager.energy, energy_before, "unequipped %s preserves energy" % ability_id)
				_suite.assert_close(manager.get_cooldown(action_id), cooldown_before, "unequipped %s preserves cooldown" % ability_id)
				_suite.assert_equal(_fact_total(), facts_before, "unequipped %s publishes no facts" % ability_id)
				_suite.assert_equal(get_tree().get_nodes_in_group("time_rifts").size(), rifts_before, "unequipped %s spawns no Rift" % ability_id)
				_suite.assert_equal(player.is_time_accelerated(), accelerated_before, "unequipped %s changes no acceleration" % ability_id)
				_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "unequipped %s preserves the action clock" % ability_id)

			player.reset_runtime_state()
			await get_tree().process_frame
		await _free_player(player)


func _test_rejections_are_atomic() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_config(["rift", "accelerate"])), "candidate rejection fixture configures")
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0

	manager.energy = manager.time_rift_cost - 1.0
	var facts_before := _fact_total()
	var energy_before: float = manager.energy
	_suite.assert_true(not player.try_action(&"time_rift"), "insufficient energy rejects equipped Rift")
	_suite.assert_close(manager.energy, energy_before, "energy rejection spends nothing")
	_suite.assert_close(manager.get_cooldown(&"time_rift"), 0.0, "energy rejection starts no Rift cooldown")
	_suite.assert_equal(_fact_total(), facts_before, "energy rejection publishes no fact")
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "energy rejection spawns no Rift")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "energy rejection preserves free action state")

	player.reset_runtime_state()
	manager.energy_regen = 0.0
	manager.set("_cooldowns", {
		&"time_stop": 0.0,
		&"time_rewind": 0.0,
		&"time_rift": 0.0,
		&"time_accelerate": 2.0,
	})
	facts_before = _fact_total()
	energy_before = manager.energy
	_suite.assert_true(not player.try_action(&"time_accelerate"), "cooldown rejects equipped Accelerate")
	_suite.assert_close(manager.energy, energy_before, "cooldown rejection spends nothing")
	_suite.assert_close(manager.get_cooldown(&"time_accelerate"), 2.0, "cooldown rejection preserves its timer")
	_suite.assert_equal(_fact_total(), facts_before, "cooldown rejection publishes no fact")
	_suite.assert_true(not player.is_time_accelerated(), "cooldown rejection applies no acceleration")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "cooldown rejection preserves free action state")

	player.reset_runtime_state()
	manager.energy_regen = 0.0
	var health: Node = player.get_node("HealthComponent")
	health.lose_health(health.current_hp, &"time_loadout_test")
	facts_before = _fact_total()
	energy_before = manager.energy
	_suite.assert_true(not player.try_action(&"time_rift"), "death rejects equipped Rift")
	_suite.assert_true(not player.try_action(&"time_accelerate"), "death rejects equipped Accelerate")
	_suite.assert_close(manager.energy, energy_before, "death rejection spends nothing")
	_suite.assert_equal(_fact_total(), facts_before, "death rejection publishes no time facts")
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "death rejection spawns no Rift")
	_suite.assert_true(not player.is_time_accelerated(), "death rejection applies no acceleration")
	await _free_player(player)


func _test_time_cast_buffer_uses_single_action_clock() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_config(["stop", "rift"])), "buffer fixture equips Rift")
	var sword: Node = player.get_node("SwordWeapon")
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_rift_duration = 0.05
	var definition: Dictionary = sword.attack_definition(false)

	_suite.assert_true(player.try_action(&"attack"), "buffer fixture begins Sword attack")
	_advance(player, int(definition["windup_frames"]))
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_ACTIVE, "attack reaches active before Rift input")
	var energy_before: float = manager.energy
	var starts_before := _start_count(&"time_rift")
	var rifts_before := get_tree().get_nodes_in_group("time_rifts").size()
	_suite.assert_true(player.try_action(&"time_rift"), "equipped Rift buffers during attack active")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_ACTIVE, "buffered Rift does not skip the active phase")
	_suite.assert_true(player.action_state.has_buffered_input(&"time_cast"), "single action owner retains the time-cast buffer")
	_suite.assert_close(manager.energy, energy_before, "buffered Rift spends nothing before commit")
	_suite.assert_equal(_start_count(&"time_rift"), starts_before, "buffered Rift publishes nothing before commit")
	_suite.assert_equal(get_tree().get_nodes_in_group("time_rifts").size(), rifts_before, "buffered Rift spawns nothing before commit")

	_advance(player, int(definition["active_frames"]))
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_RECOVERY, "attack reaches recovery before Rift")
	_advance(player, int(definition["recovery_cancel_frame"]) - 1)
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_RECOVERY, "Rift waits for the recovery cancel window")
	_suite.assert_close(manager.energy, energy_before, "waiting Rift still spends nothing")
	player.advance_action_frame()
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.TIME_CAST, "Rift owns the action clock when cancel opens")
	_suite.assert_true(manager.energy < energy_before, "committed buffered Rift spends energy")
	_suite.assert_equal(_start_count(&"time_rift"), starts_before + 1, "committed buffered Rift publishes once")
	_suite.assert_equal(get_tree().get_nodes_in_group("time_rifts").size(), rifts_before + 1, "committed buffered Rift spawns once")
	await _free_player(player)


func _test_accelerate_cancel_ignores_stale_expiry() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_config(["stop", "accelerate"])), "Accelerate lifecycle fixture configures")
	var manager: Node = player.get_node("TimeManager")
	_suite.assert_true(manager.has_method("cancel_all_time_effects"), "time manager exposes explicit time-effect cancellation")
	if not manager.has_method("cancel_all_time_effects"):
		await _free_player(player)
		return

	manager.energy_regen = 0.0
	manager.time_accelerate_duration = 0.04
	var starts_before := _start_count(&"time_accelerate")
	var ends_before := _end_count(&"time_accelerate")
	_suite.assert_true(player.try_action(&"time_accelerate"), "first Accelerate commits")
	_suite.assert_true(player.is_time_accelerated(), "first Accelerate applies its effect")
	var old_token: int = int(manager.get("_time_accelerate_token"))
	manager.call("cancel_all_time_effects", &"test_cancel")
	_suite.assert_true(not player.is_time_accelerated(), "explicit cancellation clears first Accelerate")
	player.cancel_transient_actions()
	manager.energy = manager.max_energy
	manager.set("_cooldowns", {
		&"time_stop": 0.0,
		&"time_rewind": 0.0,
		&"time_rift": 0.0,
		&"time_accelerate": 0.0,
	})
	manager.time_accelerate_duration = 0.20
	_suite.assert_true(player.try_action(&"time_accelerate"), "second Accelerate commits after cancellation")
	_suite.assert_true(player.is_time_accelerated(), "second Accelerate applies its effect")
	var new_token: int = int(manager.get("_time_accelerate_token"))
	_suite.assert_true(new_token != old_token, "replacement Accelerate receives a new token")
	var remaining_before_stale_end: float = float(manager.get("_time_accelerate_remaining"))
	var ends_before_stale_end := _end_count(&"time_accelerate")
	_suite.assert_true(not bool(manager.call("_end_time_accelerate", old_token, true)), "stale manager token cannot end the replacement effect")
	_suite.assert_true(not bool(player.call("clear_time_acceleration", old_token)), "stale player token cannot clear the replacement effect")
	_suite.assert_true(player.is_time_accelerated(), "replacement Accelerate survives stale token callbacks")
	_suite.assert_close(float(manager.get("_time_accelerate_remaining")), remaining_before_stale_end, "stale token leaves the authoritative remaining duration unchanged")
	_suite.assert_equal(_end_count(&"time_accelerate"), ends_before_stale_end, "stale token publishes no duplicate end")
	await get_tree().create_timer(0.07).timeout
	_suite.assert_true(player.is_time_accelerated(), "stale first expiry cannot clear the later Accelerate")
	_suite.assert_equal(_start_count(&"time_accelerate"), starts_before + 2, "two Accelerate commits publish two starts")
	_suite.assert_equal(_end_count(&"time_accelerate"), ends_before + 1, "stale expiry publishes no duplicate end")
	manager.call("cancel_all_time_effects", &"test_cleanup")
	_suite.assert_true(not player.is_time_accelerated(), "second cancellation clears Accelerate")
	_suite.assert_equal(_end_count(&"time_accelerate"), ends_before + 2, "each committed Accelerate ends exactly once")
	await _free_player(player)


func _test_pause_freezes_active_duration() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_config(["rewind", "accelerate"])), "pause fixture equips Accelerate")
	var manager: Node = player.get_node("TimeManager")
	manager.time_accelerate_duration = 0.08
	_suite.assert_true(player.try_action(&"time_accelerate"), "pause fixture commits Accelerate")
	var manager_remaining_before: float = float(manager.get("_time_accelerate_remaining"))
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	_suite.assert_true(player.is_time_accelerated(), "pause preserves active acceleration")
	_suite.assert_close(float(manager.get("_time_accelerate_remaining")), manager_remaining_before, "pause does not advance manager effect duration", 0.01)
	get_tree().paused = false
	await get_tree().create_timer(0.12).timeout
	_suite.assert_true(not player.is_time_accelerated(), "effect expires after gameplay resumes")
	await _free_player(player)


func _test_disabled_player_freezes_inherited_time_clock() -> void:
	get_tree().paused = false
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_config(["stop", "accelerate"])), "selection freeze fixture equips Accelerate")
	var manager: Node = player.get_node("TimeManager")
	_suite.assert_equal(player.process_mode, Node.PROCESS_MODE_PAUSABLE, "Player scene defaults to pausable processing")
	_suite.assert_equal(manager.process_mode, Node.PROCESS_MODE_INHERIT, "TimeManager inherits the Player process mode")
	manager.time_accelerate_duration = 0.08
	_suite.assert_true(player.try_action(&"time_accelerate"), "selection freeze fixture commits Accelerate")
	var remaining_before: float = float(manager.get("_time_accelerate_remaining"))

	player.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.12, true).timeout
	_suite.assert_close(float(manager.get("_time_accelerate_remaining")), remaining_before, "disabled Player freezes the inherited time clock", 0.01)
	_suite.assert_true(player.is_time_accelerated(), "disabled Player preserves the active effect during selection")

	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().create_timer(0.12).timeout
	_suite.assert_true(not player.is_time_accelerated(), "restoring Player processing lets the effect finish")
	await _free_player(player)


func _test_death_cancels_every_active_time_effect_once() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_stop_duration = 10.0
	manager.time_rift_duration = 10.0
	manager.time_accelerate_duration = 10.0
	var starts_before := _fact_total()
	var stop_ends_before := _end_count(&"time_stop")
	var rift_ends_before := _end_count(&"time_rift")
	var accelerate_ends_before := _end_count(&"time_accelerate")

	_suite.assert_true(manager.try_time_stop(), "death fixture starts Stop")
	_suite.assert_true(manager.try_time_rift(player.global_position), "death fixture starts Rift")
	_suite.assert_true(manager.try_time_accelerate(), "death fixture starts Accelerate")
	_suite.assert_equal(_start_count(&"time_stop"), _start_count_before(starts_before, &"time_stop") + 1, "death fixture records one Stop start")
	_suite.assert_equal(_start_count(&"time_rift"), _start_count_before(starts_before, &"time_rift") + 1, "death fixture records one Rift start")
	_suite.assert_equal(_start_count(&"time_accelerate"), _start_count_before(starts_before, &"time_accelerate") + 1, "death fixture records one Accelerate start")
	_suite.assert_true(player.is_time_accelerated(), "death fixture has active acceleration")
	_suite.assert_true(not get_tree().get_nodes_in_group("time_rifts").is_empty(), "death fixture has an active Rift")
	_suite.assert_true(bool(manager.get("_time_stop_active")), "death fixture has active Stop")

	var health: Node = player.get_node("HealthComponent")
	health.lose_health(health.current_hp, &"time_effect_death_test")
	await get_tree().process_frame
	_suite.assert_true(not bool(manager.get("_time_stop_active")), "death cancels active Stop")
	_suite.assert_true(not player.is_time_accelerated(), "death cancels active Accelerate")
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "death cancels every active Rift")
	_suite.assert_equal(_end_count(&"time_stop"), stop_ends_before + 1, "death publishes one Stop end")
	_suite.assert_equal(_end_count(&"time_rift"), rift_ends_before + 1, "death publishes one Rift end")
	_suite.assert_equal(_end_count(&"time_accelerate"), accelerate_ends_before + 1, "death publishes one Accelerate end")
	manager.cancel_all_time_effects(&"death_test_cleanup")
	_suite.assert_equal(_end_count(&"time_stop"), stop_ends_before + 1, "post-death cleanup cannot duplicate Stop end")
	_suite.assert_equal(_end_count(&"time_rift"), rift_ends_before + 1, "post-death cleanup cannot duplicate Rift end")
	_suite.assert_equal(_end_count(&"time_accelerate"), accelerate_ends_before + 1, "post-death cleanup cannot duplicate Accelerate end")
	await _free_player(player)


func _test_legacy_acceleration_automatically_expires() -> void:
	var player := await _spawn_player()
	player.set_physics_process(true)
	player.apply_time_acceleration(1.5, 0.05)
	_suite.assert_true(player.is_time_accelerated(), "legacy acceleration entry applies immediately")
	await get_tree().create_timer(0.09).timeout
	_suite.assert_true(not player.is_time_accelerated(), "legacy acceleration entry expires without TimeManager ownership")
	player.set_physics_process(false)
	await _free_player(player)


func _test_rift_source_recomputation() -> void:
	var enemy := EnemyBaseScript.new()
	_assert_rift_source_runtime(enemy, "enemy")
	enemy.free()

	var projectile := EnemyProjectileScript.new()
	_assert_rift_source_runtime(projectile, "projectile")
	projectile.free()
	await get_tree().process_frame


func _test_boss_rift_exposure_tracks_each_source() -> void:
	var boss := BossScene.instantiate()
	add_child(boss)
	boss.set_physics_process(false)
	await get_tree().process_frame
	var health: Node = boss.get_node("HealthComponent")
	var base_defense: float = health.defense
	_suite.assert_true(not bool((boss.get_boss_ui_snapshot() as Dictionary).get("exposed", true)), "Boss starts without Rift exposure")

	boss.apply_time_rift(&"rift_alpha", 0.60)
	_suite.assert_true(bool((boss.get_boss_ui_snapshot() as Dictionary).get("exposed", false)), "first Rift source exposes the Boss")
	_suite.assert_true(health.defense < base_defense, "Rift exposure applies the Boss defense penalty")
	boss.apply_time_rift(&"rift_beta", 0.35)
	_suite.assert_true(bool((boss.get_boss_ui_snapshot() as Dictionary).get("exposed", false)), "second Rift source keeps the Boss exposed")

	boss.clear_time_rift(&"rift_beta")
	_suite.assert_true(bool((boss.get_boss_ui_snapshot() as Dictionary).get("exposed", false)), "clearing one Rift source preserves exposure from the other")
	_suite.assert_true(health.defense < base_defense, "partial Rift cleanup preserves the defense penalty")
	boss.clear_time_rift(&"rift_alpha")
	_suite.assert_true(not bool((boss.get_boss_ui_snapshot() as Dictionary).get("exposed", true)), "clearing the final Rift source removes exposure")
	_suite.assert_close(health.defense, base_defense, "final Rift cleanup restores Boss defense")
	boss.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_projectile_rift_changes_actual_movement() -> void:
	var projectile := EnemyProjectileScene.instantiate()
	add_child(projectile)
	projectile.set_physics_process(false)
	await get_tree().process_frame
	projectile.speed = 200.0
	projectile.arm_time = 0.0
	projectile.lifetime = 10.0
	projectile.direction = Vector2.RIGHT

	projectile.global_position = Vector2.ZERO
	projectile.call("_physics_process", 0.5)
	_suite.assert_close(projectile.global_position.x, 100.0, "projectile moves at base speed without Rift")

	projectile.global_position = Vector2.ZERO
	projectile.apply_time_rift(&"rift_slow", 0.40)
	projectile.call("_physics_process", 0.5)
	_suite.assert_close(projectile.global_position.x, 40.0, "projectile movement uses the active Rift multiplier")

	projectile.global_position = Vector2.ZERO
	projectile.clear_time_rift(&"rift_slow")
	projectile.call("_physics_process", 0.5)
	_suite.assert_close(projectile.global_position.x, 100.0, "projectile movement restores base speed after Rift clears")
	projectile.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_rift_source_runtime(entity: Node, label: String) -> void:
	var apply_args := _method_argument_count(entity, &"apply_time_rift")
	var clear_args := _method_argument_count(entity, &"clear_time_rift")
	_suite.assert_equal(apply_args, 2, "%s Rift apply accepts source ID plus multiplier" % label)
	_suite.assert_equal(clear_args, 1, "%s Rift clear removes one source ID" % label)
	if apply_args != 2 or clear_args != 1:
		return

	entity.call("apply_time_rift", &"rift_a", 0.60)
	entity.call("apply_time_rift", &"rift_b", 0.35)
	_suite.assert_close(float(entity.get("_rift_slow_multiplier")), 0.35, "%s uses the strongest overlapping slow" % label)
	entity.call("clear_time_rift", &"rift_b")
	_suite.assert_close(float(entity.get("_rift_slow_multiplier")), 0.60, "%s recomputes after stronger source exits" % label)
	entity.call("apply_time_rift", &"rift_a", 0.80)
	_suite.assert_close(float(entity.get("_rift_slow_multiplier")), 0.80, "%s replaces an existing source value" % label)
	entity.call("clear_time_rift", &"rift_a")
	_suite.assert_close(float(entity.get("_rift_slow_multiplier")), 1.0, "%s restores base speed after all sources exit" % label)


func _test_rift_area_tracks_enemy_projectiles() -> void:
	var rift := TimeRiftScene.instantiate()
	add_child(rift)
	await get_tree().process_frame
	_suite.assert_true(rift.has_method("_on_area_entered"), "Rift owns an area-enter endpoint for enemy projectiles")
	_suite.assert_true(rift.has_method("_on_area_exited"), "Rift owns an area-exit endpoint for enemy projectiles")
	if rift.has_method("_on_area_entered"):
		_suite.assert_true(rift.area_entered.is_connected(Callable(rift, "_on_area_entered")), "Rift connects projectile area entry")
	if rift.has_method("_on_area_exited"):
		_suite.assert_true(rift.area_exited.is_connected(Callable(rift, "_on_area_exited")), "Rift connects projectile area exit")
	rift.cancel(false)
	await get_tree().process_frame


func _config(ability_ids: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ability_ids.duplicate(true),
		"difficulty": "normal",
		"seed": 20260929,
	}


func _prepare_rewind(player: Node) -> void:
	# This suite verifies loadout dispatch, not rewind restoration. A minimal
	# recorder avoids the real rewind's 0.5 s invulnerability timer leaking from
	# an intentionally failing scene test.
	var recorder := RewindRecorderStub.new()
	player.add_child(recorder)
	player.rewind_recorder = recorder


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	return player


func _free_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	player.reset_runtime_state()
	await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _advance(player: Node, frames: int) -> void:
	for _frame: int in range(maxi(0, frames)):
		player.advance_action_frame()


func _method_argument_count(target: Object, method_name: StringName) -> int:
	for method: Dictionary in target.get_method_list():
		if StringName(method.get("name", "")) == method_name:
			return (method.get("args", []) as Array).size()
	return -1


func _fact_total() -> Dictionary:
	return {
		"started": _time_started.duplicate(true),
		"ended": _time_ended.duplicate(true),
	}


func _start_count_before(snapshot: Dictionary, skill_id: StringName) -> int:
	return int((snapshot.get("started", {}) as Dictionary).get(skill_id, 0))


func _start_count(skill_id: StringName) -> int:
	return int(_time_started.get(skill_id, 0))


func _end_count(skill_id: StringName) -> int:
	return int(_time_ended.get(skill_id, 0))


func _on_time_skill_started(skill_id: StringName, _context: Dictionary) -> void:
	_time_started[skill_id] = _start_count(skill_id) + 1


func _on_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
	_time_ended[skill_id] = _end_count(skill_id) + 1
