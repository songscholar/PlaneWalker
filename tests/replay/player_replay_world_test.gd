extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Session := preload("res://scripts/replay/player_replay_view_session.gd")
const Scope := preload("res://scripts/player/player_scene_scope.gd")
const World := preload("res://scripts/replay/player_replay_world.gd")
const EnemyScene := preload("res://scenes/enemies/enemy_tank.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "isolated world test uses actual Launch content")
	var live := EnemyScene.instantiate()
	add_child(live)
	live.process_mode = Node.PROCESS_MODE_DISABLED
	live.set_physics_process(false)
	var health_before: Dictionary = live.get_node("HealthComponent").runtime_state_snapshot()
	var stop_before: Dictionary = live.get("_time_stop_sources").duplicate(true)
	var observed: Array[String] = []
	var action_observer := func(_weapon: StringName, _action: StringName, _token: int, _context: Dictionary): observed.append("action")
	var damage_observer := func(_info: Variant, _target: Node, _amount: float): observed.append("damage")
	EventBus.weapon_action_committed.connect(action_observer)
	EventBus.damage_applied.connect(damage_observer)
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var run_id := "world-" + weapon
		var replay := await Fixture.record(self, registry, suite, run_id, 904, weapon, true)
		var target := await Fixture.spawn(self, registry, suite, run_id, 904, true, weapon)
		var world: SubViewport = target.get_parent()
		var local_actions: Array = []
		Scope.event_bus(target).weapon_action_committed.connect(func(_weapon: StringName, _action: StringName, _token: int, _context: Dictionary): local_actions.append(_action))
		suite.assert_true(world.world_2d != get_viewport().world_2d, "actual replay physics world differs from production: " + weapon)
		suite.assert_equal(Scope.nodes_in_group(target, &"enemies"), [], "live enemy is excluded from replay target queries: " + weapon)
		suite.assert_true(not target.is_in_group("player"), "live hostile target queries exclude the viewing Player: " + weapon)
		suite.assert_true(not EventBus.room_cleared.is_connected(Callable(target, "_on_character_room_cleared")), "viewing Player subscribes only to local room facts: " + weapon)
		var session := Session.new()
		suite.assert_true(session.configure(replay, target).ok and session.seek(0).ok, "actual five-weapon viewing starts: " + weapon)
		var played := session.play_to_terminal()
		suite.assert_true(played.ok, "actual weapon/time commands execute in isolated world: " + weapon + " " + str(played))
		suite.assert_true(not local_actions.is_empty(), "actual weapon action publishes locally: " + weapon)
		suite.assert_equal(observed, [], "local weapon facts and hits cannot publish globally: " + weapon)
		suite.assert_equal(live.get_node("HealthComponent").runtime_state_snapshot(), health_before, "weapon payloads cannot damage live Health: " + weapon)
		suite.assert_equal(live.get("_time_stop_sources"), stop_before, "replay time commands cannot freeze live actors: " + weapon)
		var player_before: Dictionary = target.full_player_replay_snapshot()
		EventBus.room_cleared.emit(run_id, &"live_room", 1)
		suite.assert_equal(target.full_player_replay_snapshot(), player_before, "incoming live room facts cannot mutate viewing Player: " + weapon)
		world.world_2d = get_viewport().world_2d
		suite.assert_true(not session.seek(0).ok, "tampered world isolation refuses: " + weapon)
		world.queue_free()
		await get_tree().process_frame
	EventBus.weapon_action_committed.disconnect(action_observer)
	EventBus.damage_applied.disconnect(damage_observer)
	live.queue_free()
	await get_tree().process_frame
	var scope := World.new()
	add_child(scope)
	var outside := await Fixture.spawn(self, registry, suite, "foreign-player", 904)
	outside.reparent(scope)
	suite.assert_true(not scope.owns_player(outside), "reparenting a globally initialized Player cannot forge scoped admission")
	scope.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
