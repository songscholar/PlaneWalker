extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const COMBAT_ROOM_SCENE := preload("res://scenes/rooms/combat_room_01.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")
const CursePoolScript := preload("res://scripts/curses/curse_pool.gd")

var _failed := false
var _original_save_path := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_save_path = GameState.save_path
	GameState.save_path = "user://plane_walker_smoke_test_save.json"
	GameState.reset_persistent_data(true)

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
			"rewind_heal": 28.0,
			"combo_finisher_multiplier_bonus": 0.35,
			"heavy_damage_multiplier_bonus": 0.4,
			"low_hp_damage_multiplier_bonus": 0.45,
			"dash_invulnerable_bonus": 0.08,
			"time_rift_cost_multiplier": 0.85,
			"time_rift_duration_bonus": 1.0,
			"time_rift_radius_bonus": 22.0,
			"time_rift_slow_bonus": 0.12,
			"time_accelerate_cost_multiplier": 0.85,
			"time_accelerate_duration_bonus": 0.8,
			"time_accelerate_multiplier_bonus": 0.2,
			"bow_charge_rate_bonus": 0.25,
			"bow_full_charge_damage_multiplier_bonus": 0.35,
			"bow_pierce_bonus": 1,
		},
	})
	_assert_close(time_manager.time_stop_duration_bonus, 0.75, "time stop duration starter")
	_assert_close(time_manager.time_stop_cost_multiplier, 0.9, "time stop cost starter")
	_assert_close(time_manager.rewind_heal, 28.0, "rewind heal starter")
	_assert_close(sword.combo_finisher_multiplier_bonus, 0.35, "combo finisher starter")
	_assert_close(sword.heavy_damage_multiplier_bonus, 0.4, "heavy damage starter")
	_assert_close(sword.low_hp_damage_multiplier_bonus, 0.45, "low hp damage starter")
	_assert_close(player._dash_invulnerable_bonus, 0.08, "dash invulnerability starter")
	_assert_close(time_manager.time_rift_cost_multiplier, 0.85, "rift cost payoff")
	_assert_close(time_manager.time_rift_duration_bonus, 1.0, "rift duration payoff")
	_assert_close(time_manager.time_rift_radius_bonus, 22.0, "rift radius payoff")
	_assert_close(time_manager.time_rift_slow_bonus, 0.12, "rift slow payoff")
	_assert_close(time_manager.time_accelerate_cost_multiplier, 0.85, "accelerate cost payoff")
	_assert_close(time_manager.time_accelerate_duration_bonus, 0.8, "accelerate duration payoff")
	_assert_close(time_manager.time_accelerate_multiplier_bonus, 0.2, "accelerate multiplier payoff")
	_assert_close(bow.charge_rate_bonus, 0.25, "bow charge rate starter")
	_assert_close(bow.full_charge_damage_multiplier_bonus, 0.35, "bow full charge damage payoff")
	_assert_true(bow.pierce_bonus == 1, "bow pierce starter")

	GameState.start_run({"seed": 123})
	GameState.add_run_reward({"id": "test_power", "effects": {}})
	GameState.add_run_reward({
		"id": "test_archetype",
		"archetype": "accelerated_combo",
		"role": "starter",
		"effects": {},
	})
	_assert_true(GameState.current_run.get("inventory", []).has("test_power"), "run inventory records reward")
	_assert_true(GameState.current_run.get("archetypes", {}).get("accelerated_combo", 0) == 1, "run records reward archetype")
	_assert_true(GameState.get_dominant_archetype() == "accelerated_combo", "run tracks dominant archetype")
	_assert_true(GameState.current_room == 0, "run starts before first room")

	var first_roll := RewardPoolScript.roll_options(3, 123, 1, [])
	var second_roll := RewardPoolScript.roll_options(3, 123, 1, [])
	_assert_true(_reward_ids(first_roll) == _reward_ids(second_roll), "reward roll is deterministic")
	_assert_true(RewardPoolScript.REWARDS.size() >= 14, "reward pool includes build starters")
	_assert_true(_reward_ids(RewardPoolScript.REWARDS).has("frozen_burst"), "reward pool includes frozen burst starter")
	_assert_true(_reward_ids(RewardPoolScript.REWARDS).has("accelerated_combo"), "reward pool includes combo starter")
	_assert_true(_reward_ids(RewardPoolScript.REWARDS).has("tempo_barrage"), "reward pool includes barrage starter")
	_assert_true(_reward_ids(RewardPoolScript.REWARDS).has("piercing_draw"), "reward pool includes bow starter")
	_assert_true(_reward_ids(RewardPoolScript.REWARDS).has("focused_draw"), "reward pool includes bow payoff")
	_assert_true(_reward_ids(RewardPoolScript.REWARDS).has("rift_snare"), "reward pool includes rift payoff")
	_assert_true(RewardPoolScript.get_reward_route_label({
		"archetype": "rift_control",
		"role": "payoff",
	}).contains("Payoff - Rift Control"), "reward route labels payoff")
	_assert_true(RewardPoolScript.get_reward_route_label({
		"archetype": "piercing_draw",
		"role": "starter",
	}).contains("Starter - Piercing Draw"), "reward route labels bow starter")

	var first_curse_roll := CursePoolScript.roll_options(2, 123, 2, [])
	var second_curse_roll := CursePoolScript.roll_options(2, 123, 2, [])
	_assert_true(_reward_ids(first_curse_roll) == _reward_ids(second_curse_roll), "curse roll is deterministic")
	_assert_true(CursePoolScript.CURSES.size() >= 6, "curse pool includes first risk set")

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
	_assert_true(GameState.current_run.get("active_curses", []).has("test_curse"), "run records active curse")
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
	get_tree().quit(1 if _failed else 0)


func _run_hit_feedback_check() -> void:
	GameState.start_run({"seed": 654})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_enemy_count(room, 1)

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
	await get_tree().create_timer(0.08, true, false, true).timeout
	_assert_close(Engine.time_scale, 1.0, "hit pause restores time scale")

	room.queue_free()
	await get_tree().process_frame


func _run_bow_weapon_check() -> void:
	GameState.start_run({"seed": 655})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_enemy_count(room, 1)

	var room_player: Node = room.get_node("Player")
	var bow: Node = room_player.get_node("BowWeapon")
	var time_manager: Node = room_player.get_node("TimeManager")
	var enemy: Node = _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")[0]
	var enemy_health: Node = enemy.get_node("HealthComponent")
	var floating_layer: CanvasLayer = room.get_node("FloatingTextLayer")
	var weapon_label: Label = room.get_node("CombatHUD/WeaponPanel/VBox/WeaponLabel")
	var bow_charge_bar: ProgressBar = room.get_node("CombatHUD/WeaponPanel/VBox/BowChargeBar")

	var short_started: bool = bow.start_charge()
	bow._charge_time = bow.min_charge_time * 0.5
	await get_tree().process_frame
	_assert_true(weapon_label.text.contains("Charging"), "combat hud shows bow charging")
	_assert_true(bow_charge_bar.value > 0.0, "combat hud shows bow charge progress")
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
	await get_tree().process_frame
	_assert_true(weapon_label.text.contains("Cooldown"), "combat hud shows bow cooldown")

	room.queue_free()
	await get_tree().process_frame


func _run_time_rift_check() -> void:
	GameState.start_run({"seed": 246})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_enemy_count(room, 1)

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
	var hud_label: Label = room.get_node("CombatHUD/StatusLabel")
	_assert_true(hud_label.text.contains("Rift"), "combat hud shows rift cooldown")

	await get_tree().create_timer(0.12).timeout
	await get_tree().process_frame
	_assert_close(enemy._rift_slow_multiplier, 1.0, "time rift clears slow on expire")

	room.queue_free()
	await get_tree().process_frame


func _run_time_accelerate_check() -> void:
	GameState.start_run({"seed": 247})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame

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
	var hud_label: Label = room.get_node("CombatHUD/StatusLabel")
	_assert_true(hud_label.text.contains("Accel"), "combat hud shows accelerate cooldown")

	await get_tree().create_timer(0.12).timeout
	await get_tree().process_frame
	_assert_true(not room_player.is_time_accelerated(), "time accelerate expires")
	_assert_close(sword.attack_speed, base_attack_speed, "time accelerate restores attack speed")

	room.queue_free()
	await get_tree().process_frame


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
	_assert_true(label.text.contains("Run Failed"), "death overlay shows failed result")

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
	var volume_label: Label = main.get_node("PauseMenu/Panel/Margin/VBox/VolumeLabel")
	var volume_slider: HSlider = main.get_node("PauseMenu/Panel/Margin/VBox/VolumeSlider")
	var mute_toggle: CheckButton = main.get_node("PauseMenu/Panel/Margin/VBox/MuteToggle")
	_assert_true(start_menu.visible, "pause check starts on start menu")
	_assert_true(GameState.phase == GameState.GamePhase.HUB, "main scene starts in hub phase")
	main._pause_run()
	_assert_true(not get_tree().paused, "hub phase cannot open pause")
	main._start_new_run()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(not start_menu.visible, "quick start hides start menu")
	_assert_true(not pause_menu.visible, "pause menu starts hidden")
	main._pause_run()
	_assert_true(get_tree().paused, "pause freezes scene tree")
	_assert_true(GameState.phase == GameState.GamePhase.PAUSED, "pause sets paused phase")
	_assert_true(pause_menu.visible, "pause menu becomes visible")
	volume_slider.value = 0.5
	_assert_close(GameState.get_setting("master_volume", 0.0), 0.5, "pause menu stores master volume")
	_assert_true(volume_label.text.contains("50%"), "pause menu updates volume label")
	mute_toggle.button_pressed = true
	_assert_true(bool(GameState.get_setting("master_muted", false)), "pause menu stores mute setting")

	resume_button.pressed.emit()
	_assert_true(not get_tree().paused, "resume unfreezes scene tree")
	_assert_true(GameState.phase == GameState.GamePhase.DUNGEON, "resume restores previous phase")
	_assert_true(not pause_menu.visible, "resume hides pause menu")

	GameState.set_phase(GameState.GamePhase.DEATH)
	main._pause_run()
	_assert_true(not get_tree().paused, "death phase cannot open pause")
	_assert_true(not pause_menu.visible, "pause stays hidden during death")

	main.queue_free()
	await get_tree().process_frame


func _run_persistence_check() -> void:
	GameState.reset_persistent_data(true)
	GameState.set_setting("master_volume", 0.4)
	GameState.set_setting("master_muted", true)
	GameState.start_run({"seed": 991})
	GameState.current_room = 5
	GameState.end_run({
		"result": "floor_cleared",
		"floor": 1,
		"rooms_cleared": 5,
		"run_time": 123.0,
		"rewards": [{"id": "test_reward"}],
		"curses": [{"id": "test_curse"}],
	})

	_assert_true(GameState.persistent.get("runs_completed", 0) == 1, "run persistence increments completion count")
	_assert_true(GameState.persistent.get("victories", 0) == 1, "run persistence increments victory count")
	_assert_true(GameState.persistent.get("best_rooms_cleared", 0) == 5, "run persistence stores best room count")

	GameState.persistent = {}
	_assert_true(GameState.load_persistent(), "persistent save can be loaded")
	_assert_close(float(GameState.get_setting("master_volume", 0.0)), 0.4, "persistent save restores master volume")
	_assert_true(bool(GameState.get_setting("master_muted", false)), "persistent save restores mute setting")
	_assert_true(GameState.persistent.get("runs_completed", 0) == 1, "persistent save restores run count")
	_assert_true(GameState.persistent.get("last_run_summary", {}).get("result", "") == "floor_cleared", "persistent save restores last run result")


func _run_room_progression_check() -> void:
	GameState.start_run({"seed": 456})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_enemy_count(room, 1)
	_assert_true(GameState.current_room == 1, "first combat room starts at one")
	_assert_true(GameState.get_current_room_type() == "combat", "first room is combat type")

	room._clear_room()
	var reward_title: Label = room.get_node("RewardSelection/Panel/Margin/VBox/Title")
	_assert_true(reward_title.text.contains("Room 1"), "reward title includes first cleared room")
	room.get_node("RewardSelection")._select_reward(0)
	await get_tree().process_frame
	await get_tree().process_frame

	var event_selection: CanvasLayer = room.get_node("EventSelection")
	var event_title: Label = room.get_node("EventSelection/Panel/Margin/VBox/Title")
	var event_options: VBoxContainer = room.get_node("EventSelection/Panel/Margin/VBox/Options")
	var event_health: Node = room.get_node("Player/HealthComponent")
	event_health.current_hp = 100.0
	_assert_true(GameState.current_room == 2, "reward advances to event room")
	_assert_true(GameState.get_current_room_type() == "event", "second room is event type")
	_assert_true(event_selection.visible, "event room opens event selection")
	_assert_true(event_title.text.contains("Room 2"), "event title includes room index")
	_assert_true(event_options.get_child_count() == 3, "event room offers three choices")
	event_selection._select_option(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_true(GameState.current_run.get("events", []).size() == 1, "event choice is recorded")
	_assert_true(event_health.current_hp > 100.0, "event choice applies healing")

	await _wait_for_enemy_count(room, 3)
	_assert_true(GameState.current_room == 3, "event advances to elite room")
	var elite_enemies := _nodes_in_group(room.get_node("Enemies").get_children(), "elite_enemies")
	var hud_label: Label = room.get_node("CombatHUD/StatusLabel")
	_assert_true(GameState.get_current_room_type() == "elite", "third room is elite type")
	_assert_true(elite_enemies.size() == 1, "elite room upgrades one enemy")
	_assert_true(elite_enemies[0].health.max_hp > elite_enemies[0].max_hp / 1.8, "elite enemy has upgraded health")
	_assert_true(hud_label.text.contains("Elite"), "combat hud shows elite room type")

	room._clear_room()
	reward_title = room.get_node("RewardSelection/Panel/Margin/VBox/Title")
	var reward_options: VBoxContainer = room.get_node("RewardSelection/Panel/Margin/VBox/Options")
	_assert_true(reward_title.text.contains("elite reward"), "elite room shows elite reward title")
	_assert_true(reward_options.get_child_count() == 4, "elite room offers an extra reward option")
	room.get_node("RewardSelection")._select_reward(0)
	await get_tree().process_frame
	await get_tree().process_frame

	await _wait_for_enemy_count(room, 3)
	_assert_true(GameState.current_room == 4, "elite reward advances to fourth room")
	_assert_true(GameState.get_current_room_type() == "combat", "fourth room is combat type")

	room._clear_room()
	_resolve_curse_offer_if_visible(room, false)
	reward_title = room.get_node("RewardSelection/Panel/Margin/VBox/Title")
	_assert_true(reward_title.text.contains("Room 4"), "fourth room reward title includes room index")
	room.get_node("RewardSelection")._select_reward(0)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_enemy_count(room, 1)
	_assert_true(GameState.current_room == 5, "fourth reward advances to boss room")

	var enemies := _nodes_in_group(room.get_node("Enemies").get_children(), "enemies")
	var boss_panel: PanelContainer = room.get_node("CombatHUD/BossPanel")
	var boss_hp_bar: ProgressBar = room.get_node("CombatHUD/BossPanel/VBox/BossHPBar")
	_assert_true(GameState.phase == GameState.GamePhase.BOSS_FIGHT, "fifth room enters boss phase")
	_assert_true(enemies.size() == 1, "boss room spawns one enemy")
	_assert_true(enemies[0].is_in_group("bosses"), "fifth room enemy is boss")
	var boss_health: Node = enemies[0].get_node("HealthComponent")
	var phase_damage := DamageInfoScript.new(boss_health.max_hp * 0.5, DamageInfoScript.DamageType.PHYSICAL, self, self)
	boss_health.take_damage(phase_damage)
	await get_tree().process_frame
	_assert_true(enemies[0]._phase >= 2, "boss enters later phase after health threshold")
	await get_tree().process_frame
	_assert_true(boss_panel.visible, "boss room shows boss panel")
	_assert_close(boss_hp_bar.max_value, enemies[0].health.max_hp, "boss hp max binds to health")
	enemies[0].apply_time_stop(0.1)
	await get_tree().process_frame
	_assert_close(enemies[0].health.defense, 0.0, "time stop exposes boss")
	await get_tree().create_timer(0.12).timeout
	await get_tree().process_frame
	_assert_close(enemies[0].health.defense, enemies[0]._base_defense, "boss recovers after time stop exposure")
	enemies[0].apply_time_rift(0.4)
	await get_tree().process_frame
	_assert_close(enemies[0].health.defense, 0.0, "time rift exposes boss")
	_assert_true(enemies[0]._pattern_timer >= 1.2, "time rift delays boss pattern")
	enemies[0].clear_time_rift()
	await get_tree().process_frame
	_assert_close(enemies[0].health.defense, enemies[0]._base_defense, "boss recovers after rift exposure")

	room._clear_room()
	_resolve_curse_offer_if_visible(room, false)
	room.get_node("RewardSelection")._select_reward(0)
	await get_tree().process_frame
	_assert_true(GameState.phase == GameState.GamePhase.RUN_END, "final room ends run")
	room.queue_free()
	await get_tree().process_frame


func _run_curse_selection_check() -> void:
	GameState.start_run({"seed": 987})
	var room := COMBAT_ROOM_SCENE.instantiate()
	var forced_curse_rooms: Array[int] = [1]
	room.curse_offer_rooms = forced_curse_rooms
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_enemy_count(room, 1)

	room._clear_room()
	await get_tree().process_frame
	var curse_selection: CanvasLayer = room.get_node("CurseSelection")
	var reward_selection: CanvasLayer = room.get_node("RewardSelection")
	_assert_true(curse_selection.visible, "curse offer appears before reward")
	_assert_true(not reward_selection.visible, "reward waits for curse offer resolution")
	var curse_button: Button = room.get_node("CurseSelection/Panel/Margin/VBox/Options").get_child(0)
	_assert_true(curse_button.text.contains("Risk:"), "curse option shows risk label")

	curse_selection._select_curse(0)
	await get_tree().process_frame
	_assert_true(not curse_selection.visible, "curse offer closes after selection")
	_assert_true(reward_selection.visible, "reward opens after curse selection")
	_assert_true(GameState.current_run.get("active_curses", []).size() == 1, "curse selection records active curse")

	room.queue_free()
	await get_tree().process_frame


func _run_event_selection_risk_check() -> void:
	GameState.start_run({"seed": 988})
	var room := COMBAT_ROOM_SCENE.instantiate()
	var forced_event_rooms: Array[int] = [1]
	room.event_rooms = forced_event_rooms
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame

	var event_selection: CanvasLayer = room.get_node("EventSelection")
	var health: Node = room.get_node("Player/HealthComponent")
	health.current_hp = 120.0
	_assert_true(event_selection.visible, "forced event room opens event selection")
	_assert_true(GameState.get_current_room_type() == "event", "forced first room is event type")

	event_selection._select_option(2)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_close(GameState.current_run.get("events", [])[0].get("hp_paid", 0.0), 25.0, "fractured cache pays hp cost")
	_assert_true(GameState.current_run.get("inventory", []).size() == 1, "fractured cache grants a reward")
	_assert_true(GameState.current_run.get("events", [])[0].get("granted_reward_id", "") != "", "event records granted reward")
	_assert_true(GameState.current_room == 2, "event selection advances run")

	room.queue_free()
	await get_tree().process_frame


func _run_reward_ui_build_check() -> void:
	GameState.start_run({"seed": 789})
	var room := COMBAT_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame

	var reward_selection := room.get_node("RewardSelection")
	var forced_options: Array[Dictionary] = [{
		"id": "accelerated_combo",
		"name": "Accelerated Combo",
		"kind": "weapon",
		"archetype": "accelerated_combo",
		"role": "starter",
		"description": "Sword attacks are faster and combo finishers hit harder.",
		"effects": {"combo_finisher_multiplier_bonus": 0.35},
	}]
	reward_selection._current_options = forced_options
	reward_selection._render_options()
	var reward_button: Button = room.get_node("RewardSelection/Panel/Margin/VBox/Options").get_child(0)
	_assert_true(reward_button.text.contains("Starter - Accelerated Combo"), "reward option shows build route")

	reward_selection._select_reward(0)
	await get_tree().process_frame
	var build_label: Label = room.get_node("CombatHUD/BuildLabel")
	_assert_true(build_label.text.contains("Accelerated Combo"), "combat hud shows dominant build")
	_assert_true(GameState.current_run.get("archetypes", {}).get("accelerated_combo", 0) == 1, "selected reward records archetype")

	room.queue_free()
	await get_tree().process_frame


func _resolve_curse_offer_if_visible(room: Node, accept: bool) -> void:
	var curse_selection: CanvasLayer = room.get_node("CurseSelection")
	if not curse_selection.visible:
		return
	if accept:
		curse_selection._select_curse(0)
	else:
		curse_selection._skip_curse()


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
