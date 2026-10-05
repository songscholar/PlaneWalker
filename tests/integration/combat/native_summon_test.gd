extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Caller := preload("res://data/content_packs/base/assets/enemies/launch/enemy_forest_caller.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_forest_heart.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := Caller.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var parser := Definition.new()
	parser.configure(Content.enemy("forest_caller"))
	actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-summons", "hostile_source_id": "summon-caller", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42})
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			actor.configure_launch_room_motion(room, template)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-summons")
	player.global_position = Vector2(400, 180)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-summons", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "real caller binds native summon frame authority")
	var runtime: RefCounted = actor.get("_launch_runtime")
	var action: Dictionary = runtime.request_action("forest_caller.void_call", {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 400.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
	for fact: Dictionary in action.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	await get_tree().physics_frame
	var accepted := true
	for frame: int in range(1, 46):
		var ticket: Dictionary = bridge.begin_frame(frame)
		if ticket.is_empty() or not bridge.prepare_frame(ticket) or not _publish(bridge, ticket):
			if not ticket.is_empty():
				bridge.rollback_frame(ticket)
			accepted = false
			break
	suite.assert_true(accepted, "authored void_call completes full45frame warning and materializes two native children")
	if accepted:
		suite.assert_true(effects.has_method("native_summon_actors") and effects.native_summon_actors().size() == 2, "two real support bodies exist after accepted summon action")
		if effects.has_method("native_summon_actors"):
			suite.assert_true(runtime.add_control_source("parent-test-stop", "stop", 240, 1.0), "parent Stop isolates actual child attack authority")
			var before_hp := float(player.health.current_hp)
			for frame: int in range(46, 141):
				var ticket: Dictionary = bridge.begin_frame(frame)
				if ticket.is_empty() or not bridge.prepare_frame(ticket) or not _publish(bridge, ticket):
					suite.assert_true(false, "actual child authoritatively continues frame%d" % frame)
					if not ticket.is_empty():
						bridge.rollback_frame(ticket)
					break
				suite.assert_true(effects.native_summon_actors().values().all(func(child: Node2D): return child.get("_launch_runtime").snapshot().runtime_frame == frame), "actual child accepted clock follows shared bridge")
			suite.assert_true(float(player.health.current_hp) < before_hp, "real firefly projectile hurts Player after child full warning")
			suite.assert_true(effects.native_summon_actors().values().all(func(child: Node2D): return child.get_meta("summoned") and not child.get_meta("reward_eligible") and child.launch_runtime_snapshot().runtime.action.decision_index > 0), "unrewarded children execute their own actual authored attacks")
	effects.dispose_native_effects()
	for node: Node in [actor, player, root, room]:
		node.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
