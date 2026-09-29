extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")
const CursePoolScript := preload("res://scripts/curses/curse_pool.gd")
const BlessingPoolScript := preload("res://scripts/rewards/blessing_pool.gd")
const TalentPoolScript := preload("res://scripts/rewards/talent_pool.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")


class RunResultSignalCounter:
	extends RefCounted

	var count: int = 0
	var payloads: Array[Dictionary] = []

	func record(_run_id: String, payload: Dictionary, _revision: int) -> void:
		count += 1
		payloads.append(payload.duplicate(true))


var _failed := false
var _original_save_path := ""
var _test_storage_root := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_save_path = GameState.save_path
	_test_storage_root = _isolated_storage_root("reward_system_smoke")
	GameState.save_path = _test_storage_root.path_join("legacy.json")
	GameState.reset_persistent_data(true)
	TranslationServer.set_locale("zh_CN")

	var player := PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame

	var health: Node = player.get_node("HealthComponent")
	var time_manager: Node = player.get_node("TimeManager")
	var sword: Node = player.get_node("SwordWeapon")
	var bow: Node = player.get_node("BowWeapon")

	_assert_close(player.stats.attack, 30.0, "base attack")
	_assert_close(sword.base_attack, 30.0, "base sword attack")
	_assert_close(bow.base_attack, 30.0, "base bow attack")

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
	_assert_close(bow.base_attack, 45.0, "reward bow attack")
	_assert_close(sword.attack_speed, 1.2, "reward sword speed")
	_assert_close(bow.attack_speed, 1.2, "reward bow speed")
	_assert_close(health.max_hp, 220.0, "reward max hp")
	_assert_close(health.defense, 2.0, "reward defense")
	_assert_close(time_manager.max_energy, 125.0, "reward max time energy")
	_assert_close(time_manager.energy_regen, 3.25, "reward time regen")

	player.apply_reward({
		"id": "test_build_starter",
		"effects": {
			"time_stop_duration_bonus": 0.75,
			"time_stop_cost_multiplier": 0.9,
			"time_stop_weakpoint_damage_bonus": 0.35,
			"time_stop_weakpoint_duration": 3.0,
			"rewind_heal": 28.0,
			"rewind_cost_multiplier": 0.9,
			"combo_finisher_multiplier_bonus": 0.35,
			"heavy_damage_multiplier_bonus": 0.4,
			"heavy_execute_multiplier_bonus": 0.5,
			"heavy_execute_threshold": 0.3,
			"low_hp_damage_multiplier_bonus": 0.45,
			"dash_invulnerable_bonus": 0.08,
			"time_rift_cost_multiplier": 0.85,
			"time_rift_duration_bonus": 1.0,
			"time_rift_radius_bonus": 22.0,
			"time_rift_slow_bonus": 0.12,
			"time_accelerate_cost_multiplier": 0.85,
			"time_accelerate_duration_bonus": 0.8,
			"time_accelerate_multiplier_bonus": 0.2,
			"low_energy_regen_multiplier": 2.0,
			"low_energy_threshold": 30.0,
			"bow_charge_rate_bonus": 0.25,
			"bow_full_charge_damage_multiplier_bonus": 0.35,
			"bow_pierce_bonus": 1,
		},
	})
	_assert_close(time_manager.time_stop_duration_bonus, 0.75, "time stop duration starter")
	_assert_close(time_manager.time_stop_cost_multiplier, 0.9, "time stop cost starter")
	_assert_close(time_manager.time_stop_weakpoint_damage_bonus, 0.35, "time stop weakpoint blessing")
	_assert_close(time_manager.time_stop_weakpoint_duration, 3.0, "time stop weakpoint duration")
	_assert_close(time_manager.rewind_heal, 28.0, "rewind heal starter")
	_assert_close(time_manager.rewind_cost_multiplier, 0.9, "rewind cost blessing")
	_assert_close(sword.combo_finisher_multiplier_bonus, 0.35, "combo finisher starter")
	_assert_close(sword.heavy_damage_multiplier_bonus, 0.4, "heavy damage starter")
	_assert_close(sword.heavy_execute_multiplier_bonus, 0.5, "heavy execute talent")
	_assert_close(sword.heavy_execute_threshold, 0.3, "heavy execute threshold")
	_assert_close(sword.low_hp_damage_multiplier_bonus, 0.45, "low hp damage starter")
	_assert_close(player._dash_invulnerable_bonus, 0.08, "dash invulnerability starter")
	_assert_close(time_manager.time_rift_cost_multiplier, 0.85, "rift cost payoff")
	_assert_close(time_manager.time_rift_duration_bonus, 1.0, "rift duration payoff")
	_assert_close(time_manager.time_rift_radius_bonus, 22.0, "rift radius payoff")
	_assert_close(time_manager.time_rift_slow_bonus, 0.12, "rift slow payoff")
	_assert_close(time_manager.time_accelerate_cost_multiplier, 0.85, "accelerate cost payoff")
	_assert_close(time_manager.time_accelerate_duration_bonus, 0.8, "accelerate duration payoff")
	_assert_close(time_manager.time_accelerate_multiplier_bonus, 0.2, "accelerate multiplier payoff")
	_assert_close(time_manager.low_energy_regen_multiplier, 2.0, "low energy regen talent")
	_assert_close(time_manager.low_energy_threshold, 30.0, "low energy threshold talent")
	_assert_close(bow.charge_rate_bonus, 0.25, "bow charge rate starter")
	_assert_close(bow.full_charge_damage_multiplier_bonus, 0.35, "bow full charge damage payoff")
	_assert_true(bow.pierce_bonus == 1, "bow pierce starter")

	var recorded_state := RunBuildStateScript.new()
	recorded_state.record_item({"id": "test_power", "effects": {}})
	recorded_state.record_item({
		"id": "test_archetype",
		"archetype": "accelerated_combo",
		"role": "starter",
		"effects": {},
	})
	var recorded_build: Dictionary = recorded_state.to_dictionary()
	_assert_true(recorded_build.get("items", []).has("test_power"), "build state records reward")
	_assert_true(recorded_build.get("archetypes", {}).get("accelerated_combo", 0) == 1, "build state records reward archetype")
	_assert_true(recorded_build.get("dominant_archetype", "") == "accelerated_combo", "build state tracks dominant archetype")

	var rebuilt_state := RunBuildStateScript.from_run({
		"rewards": recorded_build.get("reward_history", []),
		"blessings": [{"id": "test_blessing"}],
		"curses": [{"id": "test_curse"}],
		"talent_choices": [{"id": "test_talent"}],
	})
	_assert_true(rebuilt_state.items.has("test_power"), "build state can rebuild item ids")
	_assert_true(rebuilt_state.blessings.has("test_blessing"), "build state can rebuild blessing ids")
	_assert_true(rebuilt_state.curses.has("test_curse"), "build state can rebuild curse ids")
	_assert_true(rebuilt_state.talents.has("test_talent"), "build state can rebuild talent ids")

	var first_roll := RewardPoolScript.roll_options(3, 123, 1, [])
	var second_roll := RewardPoolScript.roll_options(3, 123, 1, [])
	_assert_true(_reward_ids(first_roll) == _reward_ids(second_roll), "reward roll is deterministic")
	var registered_rewards := RewardPoolScript.all_rewards()
	_assert_true(registered_rewards.size() >= 14, "base pack includes build starters")
	_assert_true(registered_rewards.all(func(entry): return entry.get("pack_id") == "base"), "item rewards originate from the base pack")
	_assert_true(_reward_ids(registered_rewards).has("frozen_burst"), "reward pool includes frozen burst starter")
	_assert_true(_reward_ids(registered_rewards).has("accelerated_combo"), "reward pool includes combo starter")
	_assert_true(_reward_ids(registered_rewards).has("tempo_barrage"), "reward pool includes barrage starter")
	_assert_true(_reward_ids(registered_rewards).has("piercing_draw"), "reward pool includes bow starter")
	_assert_true(_reward_ids(registered_rewards).has("focused_draw"), "reward pool includes bow payoff")
	_assert_true(_reward_ids(registered_rewards).has("rift_snare"), "reward pool includes rift payoff")
	_assert_true(RewardPoolScript.get_reward_route_label({
		"archetype": "rift_trap",
		"role": "payoff",
	}).contains("收益件 - 裂隙陷阱"), "reward route labels payoff")
	_assert_true(RewardPoolScript.get_reward_route_label({
		"archetype": "piercing_barrage",
		"role": "starter",
	}).contains("启动件 - 穿透弹幕"), "reward route labels bow starter")

	var first_curse_roll := CursePoolScript.roll_options(2, 123, 2, [])
	var second_curse_roll := CursePoolScript.roll_options(2, 123, 2, [])
	_assert_true(_reward_ids(first_curse_roll) == _reward_ids(second_curse_roll), "curse roll is deterministic")
	var registered_curses := CursePoolScript.all_curses()
	_assert_true(registered_curses.size() >= 6, "base pack includes the first curse set")
	_assert_true(registered_curses.all(func(entry): return entry.get("pack_id") == "base"), "curses originate from the base pack")

	var first_blessing_roll := BlessingPoolScript.roll_options(2, 123, 4, [])
	var second_blessing_roll := BlessingPoolScript.roll_options(2, 123, 4, [])
	_assert_true(_reward_ids(first_blessing_roll) == _reward_ids(second_blessing_roll), "blessing roll is deterministic")
	var registered_blessings := BlessingPoolScript.all_blessings()
	_assert_true(registered_blessings.size() >= 4, "base pack includes M1 blessings")
	_assert_true(registered_blessings.all(func(entry): return entry.get("pack_id") == "base"), "blessings originate from the base pack")
	_assert_true(_reward_ids(registered_blessings).has("bls_stop_weakpoint"), "blessing pool includes stop weakpoint")

	var first_talent_roll := TalentPoolScript.roll_options(3, 123, 3, [])
	var second_talent_roll := TalentPoolScript.roll_options(3, 123, 3, [])
	_assert_true(_reward_ids(first_talent_roll) == _reward_ids(second_talent_roll), "talent roll is deterministic")
	var registered_talents := TalentPoolScript.all_talents()
	_assert_true(registered_talents.size() >= 3, "base pack includes M1 talents")
	_assert_true(registered_talents.all(func(entry): return entry.get("pack_id") == "base"), "talents originate from the base pack")
	_assert_true(_reward_ids(registered_talents).has("tal_ruin_execute"), "talent pool includes ruin execute")

	player.apply_curse({
		"id": "test_curse",
		"effects": {
			"attack_multiplier": 1.25,
			"max_hp_multiplier": 0.8,
			"time_energy_regen_multiplier": 0.5,
			"time_stop_self_damage": 12.0,
			"rewind_self_damage": 18.0,
			"healing_multiplier": 0.5,
		},
	})
	recorded_state.record_curse({"id": "test_curse", "effects": {}})
	_assert_true(recorded_state.to_dictionary().get("curses", []).has("test_curse"), "build state records active curse")
	_assert_close(sword.base_attack, 56.25, "curse applies attack upside")
	_assert_close(health.max_hp, 176.0, "curse applies max hp risk")
	_assert_close(time_manager.energy_regen, 1.625, "curse applies time regen risk")
	_assert_close(time_manager.time_stop_self_damage, 12.0, "curse applies time stop hp cost")
	_assert_close(time_manager.rewind_self_damage, 18.0, "curse applies rewind hp cost")
	health.current_hp = 100.0
	health.heal(20.0)
	_assert_close(health.current_hp, 110.0, "curse modifies healing rules")
	health.invulnerable = true
	health.lose_health(10.0, self)
	health.invulnerable = false
	_assert_close(health.current_hp, 100.0, "curse hp costs bypass invulnerability")

	player.queue_free()
	await _run_hit_feedback_check()
	await _run_blessing_talent_damage_check()
	await _run_bow_weapon_check()
	await _run_time_rift_check()
	await _run_time_accelerate_check()
	await _run_death_check()
	await _run_curse_selection_check()
	await _run_event_selection_risk_check()
	await _run_room_progression_check()
	await _run_reward_ui_build_check()
	await _run_pause_menu_check()
	await _run_persistence_check()
	await _run_death_overlay_check()
	await get_tree().process_frame
	GameState.reset_persistent_data(true)
	GameState.save_path = _original_save_path
	GameState.load_persistent()
	_remove_tree(_test_storage_root)
	get_tree().quit(1 if _failed else 0)


func _run_hit_feedback_check() -> void:
	var fixture := await _create_host_fixture(654)
	var room: Node = fixture["room"]

	var enemy: Node = _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")[0]
	var floating_layer: CanvasLayer = room.get_node("FloatingTextLayer")
	var damage_info := DamageInfoScript.new(12.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	damage_info.tags = ["weapon:sword", "attack:heavy"]
	damage_info.knockback = Vector2.RIGHT * 80.0
	enemy.get_node("HealthComponent").take_damage(damage_info)
	await get_tree().process_frame

	_assert_true(floating_layer.get_child_count() > 0, "hit feedback spawns floating damage text")
	_assert_true(enemy._knockback_velocity.length() > 0.0, "hit feedback applies knockback")
	_assert_true(Engine.time_scale < 1.0, "weapon hit requests hit pause")
	var pause_snapshot: Dictionary = CombatFeedback.get_hit_pause_snapshot_for_test()
	var pause_duration := float(
		int(pause_snapshot.get("deadline_usec", 0)) - int(pause_snapshot.get("started_usec", 0))
	) / 1000000.0
	await get_tree().create_timer(pause_duration + 0.02, true, false, true).timeout
	await get_tree().process_frame
	_assert_close(Engine.time_scale, 1.0, "hit pause restores time scale")

	await _destroy_host_fixture(fixture)


func _run_blessing_talent_damage_check() -> void:
	var fixture := await _create_host_fixture(656)
	var room: Node = fixture["room"]

	var room_player: Node = room.get_node("Player")
	var sword: Node = room_player.get_node("SwordWeapon")
	var enemy: Node = _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")[0]
	var enemy_health: Node = enemy.get_node("HealthComponent")
	enemy_health.max_hp = 100.0
	enemy_health.current_hp = 100.0
	enemy_health.defense = 0.0

	enemy.apply_weakpoint(0.2, 0.35)
	var weakpoint_hit := DamageInfoScript.new(10.0, DamageInfoScript.DamageType.PHYSICAL, sword, room_player)
	weakpoint_hit.tags = ["weapon:sword", "attack:heavy"]
	var weakpoint_damage: float = enemy_health.take_damage(weakpoint_hit)
	_assert_close(weakpoint_damage, 13.5, "time stop weakpoint increases heavy damage")
	await get_tree().create_timer(0.22).timeout

	sword.heavy_execute_multiplier_bonus = 0.5
	sword.heavy_execute_threshold = 0.3
	enemy_health.current_hp = 20.0
	var execute_hit := DamageInfoScript.new(10.0, DamageInfoScript.DamageType.PHYSICAL, sword, room_player)
	execute_hit.tags = ["weapon:sword", "attack:heavy", "talent:ruin_execute"]
	var execute_damage: float = enemy_health.take_damage(execute_hit)
	_assert_close(execute_damage, 15.0, "ruin talent increases heavy damage against low hp enemies")

	await _destroy_host_fixture(fixture)


func _run_bow_weapon_check() -> void:
	var fixture := await _create_host_fixture(655)
	var room: Node = fixture["room"]

	var room_player: Node = room.get_node("Player")
	var bow: Node = room_player.get_node("BowWeapon")
	var time_manager: Node = room_player.get_node("TimeManager")
	var enemy: Node = _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")[0]
	var enemy_health: Node = enemy.get_node("HealthComponent")
	var floating_layer: CanvasLayer = room.get_node("FloatingTextLayer")

	var short_started: bool = bow.start_charge()
	bow._charge_time = bow.min_charge_time * 0.5
	await get_tree().process_frame
	var short_released: bool = bow.release_charge(Vector2.RIGHT)
	await get_tree().process_frame
	_assert_true(short_started, "bow starts charging")
	_assert_true(not short_released, "bow short charge does not fire")
	_assert_true(get_tree().get_nodes_in_group("player_arrows").is_empty(), "bow short charge spawns no arrow")

	bow._cooldown_remaining = 0.0
	bow.charge_rate_bonus = 0.25
	bow.full_charge_damage_multiplier_bonus = 0.35
	bow.pierce_bonus = 1
	time_manager.energy = 40.0
	var energy_before_arrow: float = time_manager.energy
	_assert_true(bow.start_charge(), "bow starts full charge")
	bow._charge_time = bow.full_charge_time
	var fired: bool = bow.release_charge(room_player.global_position.direction_to(enemy.global_position))
	await get_tree().process_frame
	var arrows := get_tree().get_nodes_in_group("player_arrows")
	_assert_true(fired, "bow full charge fires")
	_assert_true(not arrows.is_empty(), "bow full charge spawns arrow")
	if not arrows.is_empty():
		_assert_close(arrows[0].pierce, 2.0, "bow reward increases pierce")
		_assert_true(arrows[0].damage > bow.base_attack * 2.0, "bow reward increases full charge damage")
		_assert_true(arrows[0].full_charge, "bow full charge marks arrow")

	await _wait_for_health_below(enemy_health, enemy_health.max_hp)
	_assert_true(enemy_health.current_hp < enemy_health.max_hp, "bow arrow damages enemy")
	_assert_true(time_manager.energy > energy_before_arrow, "bow full charge hit restores time energy")
	_assert_true(floating_layer.get_child_count() > 0, "bow full charge spawns floating text")
	var floating_text: Label = floating_layer.get_child(0)
	_assert_true(floating_text.text.begins_with(">>"), "bow full charge uses special damage prefix")
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		arrow.queue_free()
	await get_tree().process_frame

	await _destroy_host_fixture(fixture)


func _run_time_rift_check() -> void:
	var fixture := await _create_host_fixture(246)
	var room: Node = fixture["room"]

	var room_player: Node = room.get_node("Player")
	var time_manager: Node = room_player.get_node("TimeManager")
	time_manager.time_rift_cost_multiplier = 0.8
	time_manager.time_rift_duration = 0.08
	time_manager.time_rift_duration_bonus = 0.02
	time_manager.time_rift_radius_bonus = 10.0
	time_manager.time_rift_slow_bonus = 0.1
	var enemy: Node = _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")[0]
	var energy_before: float = time_manager.energy
	var created: bool = time_manager.try_time_rift(enemy.global_position)
	await get_tree().physics_frame
	await get_tree().process_frame

	_assert_true(created, "time rift can be cast")
	_assert_true(time_manager.energy <= energy_before - time_manager.time_rift_cost * time_manager.time_rift_cost_multiplier + 0.1, "time rift spends adjusted energy")
	_assert_true(time_manager.get_cooldown(&"time_rift") > 0.0, "time rift starts cooldown")
	_assert_true(get_tree().get_nodes_in_group("time_rifts").size() > 0, "time rift spawns area")
	var rift: Node = get_tree().get_nodes_in_group("time_rifts")[0]
	_assert_close(rift.radius, time_manager.time_rift_radius + time_manager.time_rift_radius_bonus, "time rift uses adjusted radius")
	_assert_close(enemy._rift_slow_multiplier, time_manager.time_rift_slow_multiplier - time_manager.time_rift_slow_bonus, "time rift slows enemy")

	await get_tree().create_timer(0.12).timeout
	await get_tree().process_frame
	_assert_close(enemy._rift_slow_multiplier, 1.0, "time rift clears slow on expire")

	await _destroy_host_fixture(fixture)


func _run_time_accelerate_check() -> void:
	var fixture := await _create_host_fixture(247)
	var room: Node = fixture["room"]

	var room_player: Node = room.get_node("Player")
	var time_manager: Node = room_player.get_node("TimeManager")
	var sword: Node = room_player.get_node("SwordWeapon")
	time_manager.time_accelerate_cost_multiplier = 0.8
	time_manager.time_accelerate_duration = 0.08
	time_manager.time_accelerate_duration_bonus = 0.02
	time_manager.time_accelerate_multiplier_bonus = 0.2
	var base_attack_speed: float = sword.attack_speed
	var energy_before: float = time_manager.energy
	var accelerated: bool = time_manager.try_time_accelerate()
	await get_tree().process_frame

	_assert_true(accelerated, "time accelerate can be cast")
	_assert_true(time_manager.energy <= energy_before - time_manager.time_accelerate_cost * time_manager.time_accelerate_cost_multiplier + 0.1, "time accelerate spends adjusted energy")
	_assert_true(time_manager.get_cooldown(&"time_accelerate") > 0.0, "time accelerate starts cooldown")
	_assert_true(room_player.is_time_accelerated(), "player enters accelerated state")
	_assert_close(sword.attack_speed, base_attack_speed * (time_manager.time_accelerate_multiplier + time_manager.time_accelerate_multiplier_bonus), "time accelerate boosts attack speed")

	await get_tree().create_timer(0.12).timeout
	await get_tree().process_frame
	_assert_true(not room_player.is_time_accelerated(), "time accelerate expires")
	_assert_close(sword.attack_speed, base_attack_speed, "time accelerate restores attack speed")

	await _destroy_host_fixture(fixture)


func _run_death_check() -> void:
	var fixture := await _create_host_fixture(321)
	var room: Node = fixture["room"]
	var host: Node = fixture["host"]
	var result_counter := RunResultSignalCounter.new()
	EventBus.run_ended.connect(result_counter.record)

	var room_player: Node = room.get_node("Player")
	var fatal_damage := DamageInfoScript.new(9999.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	room_player.get_node("HealthComponent").take_damage(fatal_damage)
	await get_tree().process_frame

	var terminal_snapshot: Dictionary = host.call("runtime_snapshot")
	var terminal_result: Dictionary = terminal_snapshot.get("result", {})
	_assert_true(int(terminal_snapshot.get("phase", -1)) == RunPhaseScript.Value.DEFEAT, "player death enters authoritative defeat")
	_assert_true(str(terminal_result.get("result", "")) == "death", "authoritative death records the result")
	_assert_true(int(terminal_result.get("current_room", -1)) == 1, "authoritative death records the current room")
	_assert_true(result_counter.count == 1, "player death emits one terminal result")
	if not result_counter.payloads.is_empty():
		var emitted_result: Dictionary = result_counter.payloads[0]
		_assert_true(str(emitted_result.get("result", "")) == "death", "death event publishes the result")
		_assert_true(int(emitted_result.get("rooms_cleared", -1)) == 0, "death event records cleared rooms")
		_assert_true(int(emitted_result.get("current_room", -1)) == 1, "death event records current room")
		_assert_true(int(emitted_result.get("kills", -1)) == 0, "death event records kill count")
	var persistent_summary: Dictionary = GameState.persistent.get("last_run_summary", {})
	_assert_true(str(persistent_summary.get("result", "")) == "death", "death persists the terminal summary")
	_assert_true(room.get_node("RewardMarker").visible == false, "death hides reward marker")

	if EventBus.run_ended.is_connected(result_counter.record):
		EventBus.run_ended.disconnect(result_counter.record)
	await _destroy_host_fixture(fixture)


func _run_death_overlay_check() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(main.get_node("StartMenu").visible, "main scene opens on start menu")
	main._start_new_run()
	await get_tree().process_frame
	await get_tree().process_frame

	var room_player: Node = main.get_node("CombatRoom01/Player")
	var fatal_damage := DamageInfoScript.new(9999.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	room_player.get_node("HealthComponent").take_damage(fatal_damage)
	await get_tree().process_frame

	var overlay: CanvasLayer = main.get_node("RunEndOverlay")
	var label: Label = main.get_node("RunEndOverlay/Panel/Margin/VBox/ResultLabel")
	_assert_true(overlay.visible, "death shows run end overlay")
	_assert_true(label.text.contains("旅程失败"), "death overlay shows failed result")
	_assert_true(label.text.contains("用时"), "death overlay shows run time")
	_assert_true(label.text.contains("击杀"), "death overlay shows kill count")
	_assert_true(label.text.contains("道具"), "death overlay shows item list")

	main.queue_free()
	await get_tree().process_frame


func _run_pause_menu_check() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var start_menu: CanvasLayer = main.get_node("StartMenu")
	var pause_menu: CanvasLayer = main.get_node("PauseMenu")
	var resume_button: Button = main.get_node("PauseMenu/Panel/Margin/VBox/ResumeButton")
	var settings_button: Button = main.get_node("PauseMenu/Panel/Margin/VBox/SettingsButton")
	var remap_button: Button = main.get_node("PauseMenu/Panel/Margin/VBox/RemapButton")
	var settings_panel: Control = main.get_node("AccessibilitySettingsLayer/AccessibilitySettingsPanel")
	var restart_button: Button = main.get_node("PauseMenu/Panel/Margin/VBox/RestartButton")
	var quit_button: Button = main.get_node("PauseMenu/Panel/Margin/VBox/QuitButton")
	var host: Node = main.get_node("RunRuntimeHost")
	_assert_true(start_menu.visible, "pause check starts on start menu")
	_assert_true(int((host.call("runtime_snapshot") as Dictionary).get("phase", -1)) == RunPhaseScript.Value.HUB, "main scene starts in authoritative hub phase")
	_assert_true(restart_button.text == "重新开始", "pause menu exposes restart")
	_assert_true(quit_button.text == "退出", "pause menu exposes quit")
	_assert_true(settings_button.text == tr("UI_ACCESSIBILITY_SETTINGS"), "pause menu exposes localized accessibility settings")
	_assert_true(remap_button.text == tr("UI_INPUT_REMAP"), "pause menu exposes localized input remapping")
	_assert_true(settings_panel.call("get_setting_control", "camera_shake_enabled") != null, "settings panel exposes camera shake accessibility")
	_assert_true(settings_panel.call("get_setting_control", "hit_flash_enabled") != null, "settings panel exposes hit flash accessibility")
	_assert_true(settings_panel.call("get_setting_control", "reduced_motion") != null, "settings panel exposes reduced motion accessibility")
	main._pause_run()
	_assert_true(not get_tree().paused, "hub phase cannot open pause")
	main.get_node("CombatRoom01").set("spawn_warning_duration", 0.0)
	main._start_new_run()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(not start_menu.visible, "quick start hides start menu")
	_assert_true(not pause_menu.visible, "pause menu starts hidden")
	main._pause_run()
	_assert_true(get_tree().paused, "pause freezes scene tree")
	_assert_true(bool((host.call("runtime_snapshot") as Dictionary).get("suspended", false)), "pause suspends the authoritative run")
	_assert_true(pause_menu.visible, "pause menu becomes visible")
	settings_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(settings_panel.visible, "pause menu opens the accessibility settings panel")
	var volume_slider := settings_panel.call("get_setting_control", "master_volume") as HSlider
	var mute_toggle := settings_panel.call("get_setting_control", "master_muted") as CheckButton
	var camera_shake_toggle := settings_panel.call("get_setting_control", "camera_shake_enabled") as CheckButton
	var hit_flash_toggle := settings_panel.call("get_setting_control", "hit_flash_enabled") as CheckButton
	var reduced_motion_toggle := settings_panel.call("get_setting_control", "reduced_motion") as CheckButton
	var volume_label := settings_panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows/Row_master_volume/ValueLabel") as Label
	volume_slider.value = 50.0
	_assert_close(GameState.get_setting("master_volume", 0.0), 0.5, "settings panel stores master volume")
	_assert_true(volume_label.text.contains("50%"), "settings panel updates volume label")
	mute_toggle.button_pressed = true
	_assert_true(bool(GameState.get_setting("master_muted", false)), "settings panel stores mute setting")
	_assert_true(camera_shake_toggle.button_pressed, "camera shake defaults on")
	_assert_true(hit_flash_toggle.button_pressed, "hit flash defaults on")
	_assert_true(not reduced_motion_toggle.button_pressed, "reduced motion defaults off")
	camera_shake_toggle.button_pressed = false
	hit_flash_toggle.button_pressed = false
	reduced_motion_toggle.button_pressed = true
	_assert_true(not bool(GameState.get_setting("camera_shake_enabled", true)), "settings panel persists camera shake")
	_assert_true(not bool(GameState.get_setting("hit_flash_enabled", true)), "settings panel persists hit flash")
	_assert_true(bool(GameState.get_setting("reduced_motion", false)), "settings panel persists reduced motion")
	_assert_true(CombatFeedback.has_method("get_feedback_options_for_test"), "feedback exposes runtime option evidence")
	if CombatFeedback.has_method("get_feedback_options_for_test"):
		var feedback_options: Dictionary = CombatFeedback.get_feedback_options_for_test()
		_assert_true(not bool(feedback_options.get("camera_shake_enabled", true)), "camera shake setting applies immediately")
		_assert_true(not bool(feedback_options.get("hit_flash_enabled", true)), "hit flash setting applies immediately")
		_assert_true(bool(feedback_options.get("reduced_motion", false)), "reduced motion setting applies immediately")
	settings_panel.call("close_panel")
	await get_tree().process_frame
	_assert_true(not settings_panel.visible, "settings panel closes back to pause")

	resume_button.pressed.emit()
	_assert_true(not get_tree().paused, "resume unfreezes scene tree")
	_assert_true(not bool((host.call("runtime_snapshot") as Dictionary).get("suspended", true)), "resume restores the authoritative run")
	_assert_true(not pause_menu.visible, "resume hides pause menu")

	var fatal_damage := DamageInfoScript.new(9999.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	main.get_node("CombatRoom01/Player/HealthComponent").take_damage(fatal_damage)
	await get_tree().process_frame
	_assert_true(int((host.call("runtime_snapshot") as Dictionary).get("phase", -1)) == RunPhaseScript.Value.DEFEAT, "player death terminates the authoritative run")
	main._pause_run()
	_assert_true(not get_tree().paused, "terminal run cannot open pause")
	_assert_true(not pause_menu.visible, "pause stays hidden during death")

	main.queue_free()
	await get_tree().process_frame


func _run_persistence_check() -> void:
	GameState.reset_persistent_data(true)
	GameState.persistent = {"settings": {"master_volume": 0.3}}
	_assert_true(GameState.save_persistent(), "legacy settings fixture can be saved")
	GameState.persistent = {}
	_assert_true(GameState.load_persistent(), "legacy settings fixture can be loaded")
	var migrated_settings: Dictionary = GameState.persistent.get("settings", {})
	_assert_true(migrated_settings.has("camera_shake_enabled"), "old save gains camera shake default")
	_assert_true(migrated_settings.has("hit_flash_enabled"), "old save gains hit flash default")
	_assert_true(migrated_settings.has("reduced_motion"), "old save gains reduced motion default")
	_assert_true(bool(migrated_settings.get("camera_shake_enabled", false)), "old save defaults camera shake on")
	_assert_true(bool(migrated_settings.get("hit_flash_enabled", false)), "old save defaults hit flash on")
	_assert_true(not bool(migrated_settings.get("reduced_motion", true)), "old save defaults reduced motion off")

	GameState.reset_persistent_data(true)
	GameState.set_setting("master_volume", 0.4)
	GameState.set_setting("master_muted", true)
	GameState.set_setting("camera_shake_enabled", false)
	GameState.set_setting("hit_flash_enabled", false)
	GameState.set_setting("reduced_motion", true)
	_assert_true(GameState.record_run_summary({
		"result": "floor_cleared",
		"floor": 1,
		"rooms_cleared": 5,
		"run_time": 123.0,
		"kills": 7,
		"rewards": [{"id": "test_reward"}],
		"blessings": [{"id": "test_blessing"}],
		"talent_choices": [{"id": "test_talent"}],
		"curses": [{"id": "test_curse"}],
	}), "run summary can be persisted")

	_assert_true(GameState.persistent.get("runs_completed", 0) == 1, "run persistence increments completion count")
	_assert_true(GameState.persistent.get("victories", 0) == 1, "run persistence increments victory count")
	_assert_true(GameState.persistent.get("best_rooms_cleared", 0) == 5, "run persistence stores best room count")
	_assert_true(GameState.persistent.get("last_run_summary", {}).get("kills", 0) == 7, "run persistence stores kill count")

	GameState.persistent = {}
	_assert_true(GameState.load_persistent(), "persistent save can be loaded")
	_assert_close(float(GameState.get_setting("master_volume", 0.0)), 0.4, "persistent save restores master volume")
	_assert_true(bool(GameState.get_setting("master_muted", false)), "persistent save restores mute setting")
	_assert_true(not bool(GameState.get_setting("camera_shake_enabled", true)), "persistent save restores camera shake")
	_assert_true(not bool(GameState.get_setting("hit_flash_enabled", true)), "persistent save restores hit flash")
	_assert_true(bool(GameState.get_setting("reduced_motion", false)), "persistent save restores reduced motion")
	CombatFeedback.reload_feedback_options_from_game_state()
	var loaded_feedback: Dictionary = CombatFeedback.get_feedback_options_for_test()
	_assert_true(not bool(loaded_feedback.get("camera_shake_enabled", true)), "loaded camera shake reaches feedback runtime")
	_assert_true(not bool(loaded_feedback.get("hit_flash_enabled", true)), "loaded hit flash reaches feedback runtime")
	_assert_true(bool(loaded_feedback.get("reduced_motion", false)), "loaded reduced motion reaches feedback runtime")
	_assert_true(GameState.persistent.get("runs_completed", 0) == 1, "persistent save restores run count")
	_assert_true(GameState.persistent.get("last_run_summary", {}).get("result", "") == "floor_cleared", "persistent save restores last run result")
	_assert_true(GameState.persistent.get("last_run_summary", {}).get("blessings", []).size() == 1, "persistent save stores blessings")
	_assert_true(GameState.persistent.get("last_run_summary", {}).get("talent_choices", []).size() == 1, "persistent save stores talents")


func _run_room_progression_check() -> void:
	var director := RunDirectorScript.new()
	director.configure_fixed_sequence(5, [2], [3], [4])
	_assert_true(director.room_type_for(1) == "combat", "run director starts with combat room")
	_assert_true(director.room_type_for(2) == "event", "run director marks event room")
	_assert_true(director.room_type_for(3) == "elite", "run director marks elite room")
	_assert_true(director.room_type_for(5) == "boss", "run director marks boss room")
	_assert_true(director.should_offer_curse(4), "run director marks curse offer room")
	director.free()

	var fixture := await _create_host_fixture(456)
	var host: Node = fixture["host"]
	var room: Node = fixture["room"]
	var snapshot: Dictionary = host.call("runtime_snapshot")
	_assert_true(int(snapshot.get("current_room", 0)) == 1, "host starts the authoritative first room")
	_assert_true(int(snapshot.get("phase", -1)) == RunPhaseScript.Value.COMBAT_ACTIVE, "host enters combat through RoomRuntime")
	_assert_true(not room.has_method("_clear_room"), "room controller exposes no private clear authority")
	await _resolve_host_room(fixture)
	snapshot = host.call("runtime_snapshot")
	_assert_true(int(snapshot.get("current_room", 0)) == 2, "public host selection advances to room two")
	_assert_true(int(snapshot.get("phase", -1)) == RunPhaseScript.Value.COMBAT_ACTIVE, "room two begins through the public runtime path")
	await _destroy_host_fixture(fixture)


func _run_curse_selection_check() -> void:
	var fixture := await _create_host_fixture(987)
	var host: Node = fixture["host"]
	for _room_number: int in range(1, 4):
		await _resolve_host_room(fixture)
	var snapshot: Dictionary = host.call("runtime_snapshot")
	_assert_true(int(snapshot.get("current_room", 0)) == 4, "host reaches the contract room")
	await _defeat_host_room(fixture)
	snapshot = host.call("runtime_snapshot")
	var offer: Dictionary = snapshot.get("open_offer", {})
	_assert_true(str(offer.get("category", "")) == "contract", "room four opens the V2 risk contract")
	var buttons := _host_option_buttons(host)
	_assert_true(not buttons.is_empty(), "contract renders public V2 options")
	var selected: Button
	for button: Button in buttons:
		if str(button.get_meta("option_id", "")) != "decline_contract":
			selected = button
			break
	_assert_true(selected != null, "contract exposes one accepted-risk option")
	if selected != null:
		selected.pressed.emit()
		await _wait_host_room(host, 5)
	snapshot = host.call("runtime_snapshot")
	_assert_true((snapshot.get("build", {}) as Dictionary).get("curses", []).size() == 1, "accepted V2 contract records one curse")
	await _destroy_host_fixture(fixture)


func _run_event_selection_risk_check() -> void:
	var fixture := await _create_host_fixture(988)
	var host: Node = fixture["host"]
	var room: Node = fixture["room"]
	var plan: Array = host.call("room_plan")
	_assert_true(not plan.is_empty() and str((plan[0] as Dictionary).get("type", "")) == "combat", "host uses the authoritative M1 room plan")
	_assert_true(room.get_node_or_null("EventSelection") == null, "host removes the legacy event authority")
	_assert_true(host.get_node_or_null("ChoiceLayer/ChoicePanelV2") != null, "host provides the unified V2 choice path")
	await _destroy_host_fixture(fixture)


func _run_reward_ui_build_check() -> void:
	var fixture := await _create_host_fixture(789)
	var host: Node = fixture["host"]
	await _defeat_host_room(fixture)
	var snapshot: Dictionary = host.call("runtime_snapshot")
	var offer: Dictionary = snapshot.get("open_offer", {})
	_assert_true(str(offer.get("category", "")) == "item", "first room opens the authoritative item offer")
	var buttons := _host_option_buttons(host)
	_assert_true(not buttons.is_empty(), "V2 choice panel renders reward cards")
	if not buttons.is_empty():
		var card_content := buttons[0].get_node_or_null("CardContent")
		_assert_true(card_content != null, "reward card renders structured content")
		buttons[0].pressed.emit()
		await _wait_host_room(host, 2)
	snapshot = host.call("runtime_snapshot")
	_assert_true((snapshot.get("build", {}) as Dictionary).get("items", []).size() == 1, "V2 reward selection updates the authoritative build")
	await _destroy_host_fixture(fixture)


func _create_host_fixture(seed: int) -> Dictionary:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var room := main.get_node("CombatRoom01")
	var host := main.get_node("RunRuntimeHost")
	room.set("spawn_warning_duration", 0.0)
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT
	var started = host.call("start_run", {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": seed,
	})
	_assert_true(started.ok, "host fixture starts through the public API")
	await _wait_host_phase(host, RunPhaseScript.Value.COMBAT_ACTIVE)
	await _wait_for_enemy_count(room, 1)
	return {"main": main, "room": room, "host": host}


func _destroy_host_fixture(fixture: Dictionary) -> void:
	get_tree().paused = false
	for group_name: StringName in [&"player_arrows", &"time_rifts", &"boss_hazards"]:
		for transient: Node in get_tree().get_nodes_in_group(group_name):
			if not transient.is_queued_for_deletion():
				transient.queue_free()
	var main: Node = fixture.get("main")
	if main != null and is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _resolve_host_room(fixture: Dictionary) -> void:
	var host: Node = fixture["host"]
	var before := int((host.call("runtime_snapshot") as Dictionary).get("current_room", 0))
	await _defeat_host_room(fixture)
	var buttons := _host_option_buttons(host)
	_assert_true(not buttons.is_empty(), "cleared room exposes one V2 choice")
	if buttons.is_empty():
		return
	buttons[0].pressed.emit()
	await _wait_host_room(host, before + 1)


func _defeat_host_room(fixture: Dictionary) -> void:
	var host: Node = fixture["host"]
	var room: Node = fixture["room"]
	for _cycle: int in range(12):
		var phase := int((host.call("runtime_snapshot") as Dictionary).get("phase", -1))
		if phase not in [RunPhaseScript.Value.COMBAT_ACTIVE, RunPhaseScript.Value.BOSS_ACTIVE]:
			return
		var enemies := _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")
		if enemies.is_empty():
			await get_tree().process_frame
			continue
		for enemy: Node in enemies:
			EventBus.entity_died.emit(enemy, null)
			enemy.queue_free()
		await get_tree().process_frame
	_assert_true(false, "host room resolves within the encounter cycle budget")


func _wait_host_room(host: Node, room_number: int) -> void:
	for _frame: int in range(60):
		var snapshot: Dictionary = host.call("runtime_snapshot")
		if int(snapshot.get("current_room", 0)) == room_number and int(snapshot.get("phase", -1)) in [
			RunPhaseScript.Value.COMBAT_ACTIVE,
			RunPhaseScript.Value.BOSS_ACTIVE,
		]:
			return
		await get_tree().process_frame
	_assert_true(false, "host advances to room %d" % room_number)


func _wait_host_phase(host: Node, expected_phase: int) -> void:
	for _frame: int in range(60):
		if int((host.call("runtime_snapshot") as Dictionary).get("phase", -1)) == expected_phase:
			return
		await get_tree().process_frame
	_assert_true(false, "host reaches phase %d" % expected_phase)


func _host_option_buttons(host: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	var panel := host.get_node_or_null("ChoiceLayer/ChoicePanelV2")
	if panel == null:
		return buttons
	var container := panel.get_node("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	for child: Node in container.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons
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


func _wait_for_enemy_count(room: Node, expected_count: int, timeout: float = 1.2) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		var enemies := _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")
		if enemies.size() >= expected_count:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_assert_true(false, "room spawned %d enemies before timeout" % expected_count)


func _wait_for_health_below(health: Node, threshold: float, timeout: float = 1.2) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if health.current_hp < threshold:
			return
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_assert_true(false, "health dropped below %.1f before timeout" % threshold)


func _isolated_storage_root(test_name: String) -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("%s_%d_%d" % [test_name, OS.get_process_id(), Time.get_ticks_usec()])


func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			_remove_tree(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
