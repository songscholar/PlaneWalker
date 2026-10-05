extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Player := preload("res://scenes/player/player.tscn")
const Native := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Legacy := preload("res://scenes/enemies/enemy_tank.tscn")
const Main := preload("res://scenes/main.tscn")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Identity := preload("res://tests/support/p15_action_fixtures.gd")
var _suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = Suite.new()
	for native: bool in [true, false]:
		for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
			await _test_real_hit(weapon, native)
	await _test_nearest_swept_target()
	await _test_production_dungeon()
	_suite.finish(get_tree())


func _test_real_hit(weapon: String, native: bool) -> void:
	var label := "%s %s" % ["native layer3" if native else "legacy layer1", weapon]
	var player: Node2D = Player.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	_suite.assert_true(player.configure_run(&"run-p15"), "authentic Player run binds " + label)
	_suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual Launch weapon configures " + label)
	player.global_position = Vector2(200, 200)
	var actor: Node2D = Native.instantiate() if native else Legacy.instantiate()
	actor.set_meta("run_id", &"run-p15")
	actor.set_meta("room_id", &"weapon-collision-room")
	actor.set_meta("encounter_id", &"weapon-collision")
	actor.set_meta("encounter_spawn_id", &"weapon-collision-target")
	add_child(actor)
	actor.set_physics_process(false)
	if native:
		var parser := Definition.new()
		_suite.assert_true(parser.configure(Content.enemy()).ok, "canonical native target definition accepts")
		var identity := Identity.identity()
		identity.hostile_source_id = "weapon-collision-target"
		identity.seed = 42
		_suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("enemy"), identity).ok, "actual native target configures " + label)
	actor.global_position = player.global_position + Vector2(42, 0)
	var health: Node = actor.get_node("HealthComponent")
	var observations: Array[float] = []
	health.damaged.connect(func(amount: float, _hp: float): observations.append(amount))
	var hp_before: float = health.current_hp
	await get_tree().physics_frame
	await get_tree().physics_frame
	_suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "real selected aim establishes " + label)
	_suite.assert_true(player.try_action(&"weapon_primary"), "real input accepts primary attack " + label)
	for frame: int in range(120):
		if frame == 40:
			player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		_suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "real action commits frame %d %s" % [frame, label])
		await get_tree().physics_frame
	_suite.assert_true(not observations.is_empty() and (not is_instance_valid(health) or health.current_hp < hp_before), "actual physics collision damages authentic target " + label)
	player.cancel_transient_actions()
	player.queue_free()
	if is_instance_valid(actor):
		actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_nearest_swept_target() -> void:
	var player: Node2D = Player.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	_suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "gun", "weapon_profile": player._weapon_profile_catalog_definition(&"gun_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual Gun configures a non-piercing swept shot")
	player.global_position = Vector2(200, 200)
	var targets: Array[Node2D] = []
	for index: int in range(3):
		var actor: Node2D = Native.instantiate()
		actor.set_meta("encounter_spawn_id", StringName("swept-target-%d" % index))
		add_child(actor)
		var parser := Definition.new()
		parser.configure(Content.enemy())
		var identity := Identity.identity()
		identity.hostile_source_id = "swept-target-%d" % index
		identity.seed = 42
		_suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("enemy"), identity).ok, "authentic swept trajectory target configures")
		actor.global_position = player.global_position + [Vector2(42, 0), Vector2(110, 0), Vector2(42, 40)][index]
		targets.append(actor)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}) and player.try_action(&"weapon_primary"), "actual Gun accepts a close-range normal fire command")
	_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "actual Gun releases normal fire without piercing")
	for _frame: int in range(30):
		_suite.assert_true(player.advance_action_frame({"aim": Vector2.RIGHT}), "normal fire accepts the real swept trajectory frame")
		await get_tree().physics_frame
	var first: Node = targets[0].get_node("HealthComponent")
	_suite.assert_true(first.current_hp < first.max_hp, "high-speed normal fire damages the nearest native Hurtbox once")
	for index: int in [1, 2]:
		var health: Node = targets[index].get_node("HealthComponent")
		_suite.assert_close(health.current_hp, health.max_hp, "normal fire cannot pierce the nearest target or damage an off-path target")
	player.cancel_transient_actions()
	player.queue_free()
	for actor: Node2D in targets:
		actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_production_dungeon() -> void:
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	_suite.assert_true(main._launch_run(config, false, true), "actual Main launches production Dungeon for natural weapon hits")
	var host: Node = main.get_node("RunRuntimeHost")
	var controller: Node = main.get_node("CombatRoom01")
	var player: Node2D = controller.get_node("Player")
	host.set_process(false)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
	main.get_node("DungeonFlow").set_process(false)
	var selected := false
	for route: Dictionary in host.route_choices():
		if route.room_type in ["combat", "elite"]:
			selected = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok
			break
	_suite.assert_true(selected, "actual Dungeon route enters an authored native combat room")
	host.set_dungeon_selection_safety(false)
	var enemies: Node = controller.get_node("Enemies")
	for _frame: int in range(100):
		_suite.assert_true(player.advance_action_frame(), "actual Dungeon accepts spawn warning frame")
		await get_tree().physics_frame
		if enemies.get_child_count() > 0:
			break
	_suite.assert_true(enemies.get_child_count() > 0, "actual Dungeon publishes a native collision target")
	if enemies.get_child_count() > 0:
		var actor: Node2D = enemies.get_child(0)
		var health: Node = actor.get_node("HealthComponent")
		var hp_before: float = health.current_hp
		var hp_observations: Array[float] = []
		health.damaged.connect(func(_amount: float, hp: float): hp_observations.append(hp))
		player.health.acquire_invulnerability_source(&"native_collision_fixture")
		player.global_position = actor.global_position + Vector2(42, 0)
		await get_tree().physics_frame
		_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}) and player.try_action(&"weapon_primary"), "authentic Dungeon Player submits selected sword input")
		_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "authentic Dungeon Player releases the Launch sword charge")
		for _frame: int in range(90):
			_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}), "actual Dungeon and weapon accept combat frame")
			await get_tree().physics_frame
		_suite.assert_true(not hp_observations.is_empty() and hp_observations.back() < hp_before, "actual Dungeon sword collision reduces live native enemy HP")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
