extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const World := preload("res://scripts/replay/run_replay_world.gd")
const Telegraph := preload("res://scripts/fx/combat_telegraph_2d.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var world := World.new()
	add_child(world)
	var origin := {"x": 80.0, "y": 40.0}
	var identity := {"run_id": "projection", "hostile_source_id": "forest_projection", "runtime_frame": 0, "next_generation_floor": 1, "seed": 45}
	var runtime := Runtime.new()
	runtime.configure_arena_origin(origin)
	var parsed := Definition.new()
	parsed.configure(_definition(registry, &"forest_heart"))
	suite.assert_true(runtime.configure(parsed.runtime_projection(), identity).ok, "presentation fixture uses actual Forest domain")
	var action := runtime.request_action("matriarch_root_sweep", {"runtime_frame": 0, "target_id": "player:1", "source_position": {"x": 400.0, "y": 184.0}, "target_position": {"x": 212.0, "y": 144.0}, "facing_direction": {"x": -1.0, "y": 0.0}})
	suite.assert_true(action.ok, "actual translated root produces frozen cone")
	var stage := Node2D.new()
	world.add_child(stage)
	var actor := {"definition_id": "forest_heart", "actor": {"runtime": runtime.snapshot(), "position": {"x": 400.0, "y": 184.0}, "room_motion": {"bounds": origin}}}
	var zone := {"id": "projection_zone", "phase": "WARNING", "damage_type": "physical", "geometry": {"shape": "circle", "origin": {"x": 250.0, "y": 200.0}, "radius": 18.0}}
	var observation := {"player": {"frame": 0}, "scene": {}, "native": {"actors": {"forest_projection": actor}, "threats": action.get("threat_facts", []), "effects": {"semantics": {"zones": [zone]}}}}
	suite.assert_true(world._build_scene(stage, observation, registry), "translated Forest constructs and semantic zone project privately")
	var roots := _sprites(stage, "forest_root.png")
	suite.assert_equal(roots.size(), 6, "all six recorded roots use actual production raster")
	if not roots.is_empty():
		suite.assert_equal(roots[0].position, Vector2(192, 144), "root projection retains actual room origin")
		suite.assert_true(roots[0].hframes == 3 and roots[0].frame == 0, "root projection retains living atlas state")
	suite.assert_equal(_sprites(stage, "physical_pool.png").size(), 1, "recorded semantic warning retains raster zone")
	var telegraphs := _telegraphs(stage)
	suite.assert_equal(telegraphs.size(), 1, "recorded warning uses production geometry renderer")
	if not telegraphs.is_empty():
		var fact: Dictionary = telegraphs[0].get_snapshot()
		suite.assert_true(fact.shape == "cone" and fact.origin == Vector2(192, 144), "replay cone preserves actual selected-root origin")
	stage.free()
	runtime = Runtime.new()
	identity.hostile_source_id = "ruin_projection"
	parsed.configure(_definition(registry, &"ruin_king"))
	suite.assert_true(runtime.configure(parsed.runtime_projection(), identity).ok, "presentation fixture uses actual Ruin arena domain")
	stage = Node2D.new()
	world.add_child(stage)
	actor = {"definition_id": "ruin_king", "actor": {"runtime": runtime.snapshot(), "position": {"x": 400.0, "y": 184.0}, "room_motion": {"bounds": origin}}}
	observation.native = {"actors": {"ruin_projection": actor}}
	suite.assert_true(world._build_scene(stage, observation, registry), "recorded cover arena projects privately")
	var covers := _sprites(stage, "ruins_cover.png")
	suite.assert_equal(covers.size(), 4, "all four recorded covers use production raster")
	if not covers.is_empty():
		var row: Dictionary = runtime.snapshot().arena_state.covers[0]
		suite.assert_equal(covers[0].position, Vector2(80 + row.position.x, 32 + row.position.y), "cover uses room motion origin and authored art offset")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _sprites(node: Node, suffix: String) -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for child: Node in node.get_children():
		if child is Sprite2D and child.texture != null and child.texture.resource_path.ends_with(suffix):
			result.append(child)
		result.append_array(_sprites(child, suffix))
	return result


func _definition(registry: RefCounted, id: StringName) -> Dictionary:
	var result: Dictionary = {}
	var source: Dictionary = registry.get_content(id)
	for field: String in Definition.FIELDS:
		result[field] = source[field]
	return result


func _telegraphs(node: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child: Node in node.get_children():
		if child is Telegraph:
			result.append(child)
		result.append_array(_telegraphs(child))
	return result
