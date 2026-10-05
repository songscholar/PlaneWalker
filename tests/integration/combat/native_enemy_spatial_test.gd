extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for entry: Array in [["bramble_mage", "bramble_mage.bramble_cage"], ["void_web_weaver", "void_web_weaver.void_web"], ["void_web_weaver", "void_web_weaver.web_cage"], ["plane_ripper", "plane_ripper.plane_rip"], ["plane_ripper", "plane_ripper.one_way_plane"]]:
		await _test_real_cast(str(entry[0]), str(entry[1]))
	suite.finish(get_tree())


func _actor(id: String, source: String, position: Vector2, elite: bool = false) -> Node2D:
	var actor := ActorScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = position
	var parser := Definition.new()
	var parsed := parser.configure(Content.enemy(id))
	suite.assert_true(parsed.ok, "actual spatial species parses: " + id)
	var identity := {"run_id": "run-p15", "hostile_source_id": source, "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite" if elite else "enemy"), identity).ok, "actual spatial species configures: " + id)
	return actor


func _test_real_cast(id: String, action_id: String) -> void:
	var actor := _actor(id, "hostile:spatial", Vector2(320, 180), action_id.ends_with(".bramble_cage") or action_id.ends_with(".web_cage") or action_id.ends_with(".one_way_plane"))
	var ally_a := _actor("shattered_sentinel", "hostile:ally-a", Vector2(240, 130))
	var ally_b := _actor("shattered_sentinel", "hostile:ally-b", Vector2(400, 130))
	var actors := {"hostile:ally-a": ally_a, "hostile:ally-b": ally_b, "hostile:spatial": actor}
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(430, 180)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15", 0) and effects.configure_native_payloads(root), "actual spatial effects authority configures")
	var registry := Registry.new()
	var context := {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 430.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
	var started: Dictionary = actor.get("_launch_runtime").request_action(action_id, context)
	suite.assert_true(started.ok, "actual authored spatial warning starts: " + action_id)
	for fact: Dictionary in started.get("threat_facts", []):
		suite.assert_true(registry.register_fact(Actions.native_threat_fact(fact)), "actual spatial cast registers frozen warning")
	var action := Content.action(action_id)
	var admitted := false
	await get_tree().physics_frame
	for frame: int in range(1, int(action.warning_frames) + 1):
		var wrappers: Array = []
		var prepared: Array = []
		for source: String in actors:
			var owner: Node2D = actors[source]
			var observation := context.duplicate(true)
			observation.runtime_frame = frame
			observation.source_position = {"x": owner.global_position.x, "y": owner.global_position.y}
			var candidate: Dictionary = owner.prepare_launch_frame(frame, observation)
			suite.assert_true(candidate.ok, "actual spatial native actor prepares frame %d" % frame)
			if not candidate.ok:
				break
			prepared.append({"owner": owner, "ticket": candidate.ticket})
			wrappers.append({"hostile_source_id": source, "batch": candidate.batch})
		var routed: Dictionary = effects.prepare_effects(wrappers, {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {"player:1": player}})
		suite.assert_true(routed.ok, "%s native active frame is admitted (%d): %s" % [action_id, frame, str(routed.get("context", {}))])
		if not routed.ok:
			for row: Dictionary in prepared:
				row.owner.rollback_launch_frame(row.ticket)
			break
		for row: Dictionary in prepared:
			suite.assert_true(row.owner.commit_launch_frame(row.ticket), "native spatial owner commits")
		suite.assert_true(effects.commit(routed.ticket).ok, "native spatial effects commit")
		for row: Dictionary in prepared:
			suite.assert_true(row.owner.publish_launch_frame(row.ticket), "native spatial owner publishes")
		suite.assert_true(effects.publish_effect_observations(routed.ticket), "native spatial effects publish")
		admitted = frame == int(action.warning_frames)
		await get_tree().physics_frame
	suite.assert_true(admitted, "complete actual warning reaches admitted native impact: " + action_id)
	effects.dispose_native_effects()
	for owner: Node2D in actors.values():
		owner.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame
