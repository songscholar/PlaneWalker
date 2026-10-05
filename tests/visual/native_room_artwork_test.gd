extends "res://tests/visual/p14_room_visual_contract_test.gd"

const Registry := preload("res://scripts/content/content_registry.gd")
const ReplayWorld := preload("res://scripts/replay/run_replay_world.gd")


func _run() -> void:
	var suite := TestSuiteScript.new()
	var templates := _load_json_array(TEMPLATE_PATH)
	var floors := _load_json_array(FLOOR_PATH)
	var floor_lookup := {}
	for floor: Dictionary in floors:
		floor_lookup[floor.id] = floor
	var visited := 0
	for template: Dictionary in templates:
		for floor_id: String in template.floor_ids:
			var scene := _bound_scene(template, floor_lookup[floor_id], false)
			suite.assert_true(scene != null, "native artwork fixture binds %s/%s" % [floor_id, template.id])
			if scene == null:
				continue
			var artwork := scene.get_node_or_null("RoomArtwork")
			suite.assert_true(artwork is Node2D, "bound %s owns native raster artwork" % template.id)
			if artwork != null:
				var tiles := artwork.get_node_or_null("FloorTiles")
				var landmark := artwork.get_node_or_null("Landmark") as Sprite2D
				suite.assert_true(tiles != null and tiles.get_child_count() == 240, "floor covers exact640x360 with240 original32px raster tiles")
				suite.assert_true(landmark != null and landmark.texture != null, "room category uses actual original landmark raster")
				suite.assert_true(not scene.get_node("PixelProxyLayer").visible, "bound production room retires placeholder geometry")
				var first: Dictionary = scene.room_artwork_snapshot()
				suite.assert_equal(first.floor_id, floor_id, "art palette follows authoritative floor")
				suite.assert_equal(first.content_id, template.id, "art layout follows authoritative template")
				var prior_rules: Dictionary = scene.floor_rule_configuration()
				var second := _bound_scene(template, floor_lookup[floor_id], true)
				suite.assert_equal(second.room_artwork_snapshot(), first, "same room identity and reduced motion reproduce exact raster layout")
				suite.assert_true(RoomSceneContractScript.validate(scene, template).ok, "bound raster room retains its single scripted owner contract")
				var reduced_rules := prior_rules.duplicate(true)
				reduced_rules.reduced_motion = true
				suite.assert_equal(second.floor_rule_configuration(), reduced_rules, "reduced motion retains physical floor zones and publishes its accessibility flag")
				second.free()
				var binding: Dictionary = scene.binding_snapshot().binding
				scene.reset_room_binding()
				suite.assert_true(not artwork.visible, "reset retires presentation of previous room identity")
				suite.assert_equal(scene.room_artwork_snapshot(), {}, "reset exposes no old room artwork identity")
				var rebound: Dictionary = scene.bind_room({"id": binding.node_id, "template_id": template.id, "room_type": template.room_type}, template, binding)
				suite.assert_true(rebound.ok and artwork.visible, "same native owner rebinds and republishes room artwork")
				suite.assert_equal(scene.room_artwork_snapshot(), first, "reset and rebind preserve exact raster layout")
				suite.assert_equal(artwork.get_node("FloorTiles").get_child_count(), 240, "rebind replaces previous sprites without accumulation")
			visited += 1
			scene.free()
	suite.assert_true(visited >= 30, "all thirty authored templates receive raster bindings")
	_test_replay_binding(suite, templates[0], floor_lookup[templates[0].floor_ids[0]])
	suite.finish(get_tree())


func _test_replay_binding(suite, template: Dictionary, floor: Dictionary) -> void:
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var native := _bound_scene(template, floor, true)
	var stage := Node2D.new()
	var world := ReplayWorld.new()
	var observation := {"player": {"frame": 0}, "scene": {"binding": native.binding_snapshot().binding}, "native": {}}
	suite.assert_true(world._build_scene(stage, observation, registry), "actual replay renderer reconstructs recorded room binding")
	var replay_room := stage.get_child(0)
	suite.assert_equal(replay_room.room_artwork_snapshot(), native.room_artwork_snapshot(), "private replay room uses the exact authoritative native raster layout")
	suite.assert_equal(replay_room.process_mode, Node.PROCESS_MODE_DISABLED, "replay artwork reconstruction leaves gameplay processing disabled")
	stage.free()
	world.free()
	native.free()
