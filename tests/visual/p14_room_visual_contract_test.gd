extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RoomSceneContractScript := preload("res://scripts/dungeon/room_scene_contract.gd")

const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const DESIGN_BOUNDS := Rect2(0.0, 0.0, 640.0, 360.0)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var templates := _load_json_array(TEMPLATE_PATH)
	var floors := _load_json_array(FLOOR_PATH)
	suite.assert_equal(templates.size(), 30, "P14D visual contract owns exactly thirty room templates")
	suite.assert_equal(floors.size(), 5, "P14D visual contract owns exactly five floor palettes")
	if templates.size() == 30 and floors.size() == 5:
		_test_scene_proxy_quality(suite, templates)
		_test_every_floor_binding(suite, templates, floors)
		_test_floor_palettes_and_accessibility(suite, templates[0], floors)
	suite.finish(get_tree())


func _test_scene_proxy_quality(suite, templates: Array) -> void:
	var visual_signatures: Dictionary = {}
	var geometry_signatures: Dictionary = {}
	for template_value: Variant in templates:
		var template := template_value as Dictionary
		var scene := _instantiate_scene(str(template.get("scene_path", "")))
		suite.assert_true(scene != null, "%s scene instantiates" % template.get("id", ""))
		if scene == null:
			continue
		var contract: Dictionary = RoomSceneContractScript.validate(scene, template)
		suite.assert_true(
			bool(contract.get("ok", false)),
			"%s satisfies the native room contract: %s" % [
				template.get("id", ""), str(contract.get("context", {})),
			]
		)
		var visual_signature := str(scene.get_meta("visual_signature", ""))
		suite.assert_true(not visual_signature.is_empty(), "%s has a visual signature" % template.get("id", ""))
		suite.assert_true(not visual_signatures.has(visual_signature), "%s visual signature is unique" % template.get("id", ""))
		visual_signatures[visual_signature] = true

		var pixel_layer := scene.get_node_or_null("PixelProxyLayer")
		suite.assert_true(pixel_layer is Node2D, "%s owns a native PixelProxyLayer" % template.get("id", ""))
		if pixel_layer is Node2D:
			for required_visual: String in [
				"Background", "Ground", "LandmarkPrimary", "DoorVisualWest",
				"DoorVisualEast", "HazardCue",
			]:
				suite.assert_true(
					pixel_layer.get_node_or_null(required_visual) is Polygon2D,
					"%s exposes %s proxy geometry" % [template.get("id", ""), required_visual]
				)
			var geometry_signature := _geometry_signature(pixel_layer as Node2D)
			suite.assert_true(not geometry_signature.is_empty(), "%s proxy geometry is nonempty" % template.get("id", ""))
			suite.assert_true(not geometry_signatures.has(geometry_signature), "%s layout geometry is distinct" % template.get("id", ""))
			geometry_signatures[geometry_signature] = true
			_assert_proxy_inside_canvas(suite, pixel_layer as Node2D, str(template.get("id", "")))

		var floor_rule_anchors := scene.get_node_or_null("FloorRuleAnchors")
		var hazard_count := 0
		if floor_rule_anchors is Node:
			for child: Node in floor_rule_anchors.get_children():
				if child is Area2D:
					hazard_count += 1
		suite.assert_true(hazard_count >= 3, "%s exposes at least three bounded hazard zones" % template.get("id", ""))
		_assert_category_landmark(suite, scene, template)
		scene.free()
	suite.assert_equal(visual_signatures.size(), 30, "all thirty visual signatures are unique")
	suite.assert_equal(geometry_signatures.size(), 30, "all thirty proxy layouts are geometrically distinct")


func _test_every_floor_binding(suite, templates: Array, floors: Array) -> void:
	var floors_by_id: Dictionary = {}
	for floor_value: Variant in floors:
		var floor := floor_value as Dictionary
		floors_by_id[str(floor["id"])] = floor
	for template_value: Variant in templates:
		var template := template_value as Dictionary
		for floor_id_value: Variant in template.get("floor_ids", []):
			var floor_id := str(floor_id_value)
			var floor := floors_by_id.get(floor_id, {}) as Dictionary
			var scene := _instantiate_scene(str(template["scene_path"]))
			suite.assert_true(scene != null, "%s binds on %s" % [template["id"], floor_id])
			if scene == null:
				continue
			var bound: Dictionary = scene.call(
				"bind_room",
				{
					"id": "%s:%s" % [floor_id, template["id"]],
					"template_id": str(template["id"]),
					"room_type": str(template["room_type"]),
				},
				template.duplicate(true),
				{
					"floor_id": floor_id,
					"palette_id": str(floor.get("palette_id", "")),
					"environment_rule_id": str(floor.get("environment_rule_id", "")),
					"room_seed": 20261002,
					"reduced_motion": false,
					"hit_flash_enabled": true,
				}
			)
			suite.assert_true(
				bool(bound.get("ok", false)),
				"%s accepts authoritative %s palette/rule binding" % [template["id"], floor_id]
			)
			scene.free()


func _test_floor_palettes_and_accessibility(suite, template: Dictionary, floors: Array) -> void:
	var palette_ids: Dictionary = {}
	var color_pairs: Dictionary = {}
	for floor_value: Variant in floors:
		var floor := floor_value as Dictionary
		var normal := _bound_scene(template, floor, false)
		var reduced := _bound_scene(template, floor, true)
		suite.assert_true(normal != null and reduced != null, "%s palette fixtures bind" % floor["id"])
		if normal == null or reduced == null:
			if normal != null:
				normal.free()
			if reduced != null:
				reduced.free()
			continue
		var normal_snapshot := normal.call("presentation_snapshot") as Dictionary
		var reduced_snapshot := reduced.call("presentation_snapshot") as Dictionary
		var palette_id := str(normal_snapshot.get("palette_id", ""))
		var base_color := normal_snapshot.get("base_color", Color.TRANSPARENT) as Color
		var accent_color := normal_snapshot.get("accent_color", Color.TRANSPARENT) as Color
		palette_ids[palette_id] = true
		color_pairs["%s:%s" % [base_color.to_html(), accent_color.to_html()]] = true
		suite.assert_equal(reduced_snapshot.get("palette_id"), palette_id, "reduced motion preserves floor identity")
		var background := normal.get_node_or_null("PixelProxyLayer/Background")
		var landmark := normal.get_node_or_null("PixelProxyLayer/LandmarkPrimary")
		var west_door := normal.get_node_or_null("PixelProxyLayer/DoorVisualWest")
		var east_door := normal.get_node_or_null("PixelProxyLayer/DoorVisualEast")
		suite.assert_true(
			background is Polygon2D and (background as Polygon2D).color == base_color,
			"%s applies its base palette to room geometry" % floor["id"]
		)
		for accent_node: Node in [landmark, west_door, east_door]:
			suite.assert_true(
				accent_node is Polygon2D and (accent_node as Polygon2D).color == accent_color,
				"%s applies its accent palette to landmarks and doors" % floor["id"]
			)
		var normal_cue := normal_snapshot.get("hazard_cue", {}) as Dictionary
		var reduced_cue := reduced_snapshot.get("hazard_cue", {}) as Dictionary
		suite.assert_equal(normal_cue.get("motion_enabled"), true, "default presentation enables bounded motion")
		suite.assert_equal(reduced_cue.get("motion_enabled"), false, "reduced motion disables animated hazard cues")
		suite.assert_equal(reduced_cue.get("visual_mode"), "static_outline", "reduced motion keeps a static hazard boundary")
		suite.assert_equal(reduced_cue.get("high_contrast_outline"), true, "reduced motion keeps high-contrast hazard information")
		suite.assert_equal(reduced_cue.get("subtitle_required"), true, "reduced motion keeps subtitle hazard information")
		normal.free()
		reduced.free()
	suite.assert_equal(palette_ids.size(), 5, "five floors expose five distinct palette identities")
	suite.assert_equal(color_pairs.size(), 5, "five floors expose five distinct base/accent color pairs")


func _bound_scene(template: Dictionary, floor: Dictionary, reduced_motion: bool) -> Node2D:
	var scene := _instantiate_scene(str(template["scene_path"]))
	if scene == null:
		return null
	var result: Dictionary = scene.call(
		"bind_room",
		{
			"id": "visual:%s" % floor["id"],
			"template_id": str(template["id"]),
			"room_type": str(template["room_type"]),
		},
		template.duplicate(true),
		{
			"floor_id": str(floor["id"]),
			"palette_id": str(floor["palette_id"]),
			"environment_rule_id": str(floor["environment_rule_id"]),
			"room_seed": 20261002,
			"reduced_motion": reduced_motion,
			"hit_flash_enabled": true,
		}
	)
	if not bool(result.get("ok", false)):
		scene.free()
		return null
	return scene


func _assert_category_landmark(suite, scene: Node2D, template: Dictionary) -> void:
	var room_type := str(template.get("room_type", ""))
	if room_type in ["combat", "elite", "boss"]:
		var encounter_anchors := scene.get_node_or_null("EncounterAnchors")
		suite.assert_true(
			encounter_anchors != null and encounter_anchors.get_child_count() >= 1,
			"%s has a readable encounter landmark" % template.get("id", "")
		)
		return
	var interaction_anchors := scene.get_node_or_null("InteractionAnchors")
	var category_found := false
	if interaction_anchors != null:
		for child: Node in interaction_anchors.get_children():
			if str(child.get_meta("kind", "")) == room_type:
				category_found = true
				break
	suite.assert_true(category_found, "%s has a readable %s landmark" % [template.get("id", ""), room_type])


func _assert_proxy_inside_canvas(suite, pixel_layer: Node2D, content_id: String) -> void:
	for child: Node in pixel_layer.get_children():
		if not child is Polygon2D:
			continue
		for point: Vector2 in (child as Polygon2D).polygon:
			var world_point := point + (child as Polygon2D).position
			suite.assert_true(
				world_point.x >= DESIGN_BOUNDS.position.x
				and world_point.y >= DESIGN_BOUNDS.position.y
				and world_point.x <= DESIGN_BOUNDS.end.x
				and world_point.y <= DESIGN_BOUNDS.end.y,
				"%s proxy geometry stays inside 640x360" % content_id
			)


func _geometry_signature(pixel_layer: Node2D) -> String:
	var fragments: Array[String] = []
	for child: Node in pixel_layer.get_children():
		if not child is Polygon2D:
			continue
		var points: Array[String] = []
		for point: Vector2 in (child as Polygon2D).polygon:
			points.append("%.2f,%.2f" % [point.x, point.y])
		fragments.append("%s:%s" % [child.name, ";".join(points)])
	fragments.sort()
	return "|".join(fragments)


func _instantiate_scene(path: String) -> Node2D:
	var resource := ResourceLoader.load(path, "PackedScene")
	if not resource is PackedScene:
		return null
	var instance := (resource as PackedScene).instantiate()
	return instance as Node2D if instance is Node2D else null


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Array if parsed is Array else []
