extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Identity := preload("res://tests/support/p15_action_fixtures.gd")
const BossDefinition := preload("res://scripts/enemies/launch/boss_definition.gd")
const EnemyDefinition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for id: String in ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne", "shattered_sentinel", "corrosive_moth", "bramble_mage"]:
		var boss := id in ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
		var parser: RefCounted = BossDefinition.new() if boss else EnemyDefinition.new()
		parser.configure(Content.boss(id) if boss else Content.enemy(id))
		var definition: Dictionary = parser.runtime_projection()
		var path := "res://data/content_packs/base/assets/%s/launch/%s_%s.tscn" % ["bosses" if boss else "enemies", "boss" if boss else "enemy", id]
		var actor := load(path).instantiate() as Node2D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(actor)
		actor.global_position = Vector2(320, 144)
		var identity := Identity.identity()
		identity.seed = 42
		identity.hostile_source_id = "warning-" + id
		suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actualwarningactorconfigures" + id)
		var action_id: String = "matriarch_spore_release" if id == "forest_heart" else str(definition.actions[0].id)
		var result: Dictionary = actor._launch_runtime.request_action(action_id, {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 144.0}, "target_position": {"x": 340.0, "y": 144.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"})
		suite.assert_true(result.ok, "actualnativeactionwarns" + id)
		actor._refresh_control_visual()
		var holder: Node = actor.get_node_or_null("LaunchTelegraphs")
		suite.assert_true(holder != null and holder.get_child_count() == result.get("threat_facts", []).size(), "actualactorprojectsallcommittedprimitives" + id)
		if holder != null:
			for index: int in range(holder.get_child_count()):
				var node := holder.get_child(index)
				var fact: Dictionary = Actions.native_threat_fact(result.threat_facts[index])
				var shown: Dictionary = node.get_snapshot()
				suite.assert_true(shown.visible and not node.is_processing(), "nativewarningusesacceptedclockratherthanwallclock" + id)
				for field: String in ["shape", "origin", "aim_direction", "target_point", "hostile_source_id", "attack_generation", "active_from_frame", "active_through_frame"]:
					suite.assert_equal(shown[field], fact[field], "visiblewarningretainsactualfact" + id + ":" + field)
		var cold: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
		var encoded := Replay.encode_replay_json(cold)
		suite.assert_true(encoded.ok and actor.restore_native_cold_snapshot(Replay.decode_replay_json(encoded.json).replay, func(_binding: Dictionary): return null), "visiblewarningretainsstrictnativecoldcontract" + id)
		actor._launch_runtime.cancel_action(&"fixture_retirement")
		actor._refresh_control_visual()
		suite.assert_true(holder == null or holder.get_child_count() == 0, "cancelledwarningremovesallpresentationprimitives" + id)
		actor.queue_free()
		await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
