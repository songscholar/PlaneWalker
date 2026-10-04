extends Node2D

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const LEGACY_SCENES := ["shattered_sentinel", "corrosive_moth", "stone_shell_strider", "ruins_wraith"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "enemy presentation fixture activates the authenticated Base")
	var index := 0
	for definition: Dictionary in registry.get_catalog_entries(&"enemy_definition", &"LAUNCH"):
		var path := "res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % definition.id
		var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
		suite.assert_true(scene != null, "canonical native scene exists: " + definition.id)
		if scene == null:
			continue
		var actor := scene.instantiate() as CharacterBody2D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(actor)
		actor.position = Vector2(50 + (index % 8) * 76, 63 + (index / 8) * 100)
		index += 1
		suite.assert_true(actor.has_method("configure_launch_definition") and actor.has_signal("hostile_final_death"), "native actor exposes the authoritative hostile API")
		var health: Node = actor.get_node("HealthComponent")
		suite.assert_equal(health.max_hp, float(definition.max_hp), "native Health matches the authoritative enemy: " + definition.id)
		var body := actor.get_node("CollisionShape2D") as CollisionShape2D
		suite.assert_true(body.shape is CircleShape2D, "native enemy body uses stable circular room geometry")
		if definition.id not in LEGACY_SCENES:
			suite.assert_equal(body.shape.radius, float(definition.collision_radius_px), "new native enemy preserves its exact authored collision radius")
		var sprite := actor.get_node("Sprite2D") as Sprite2D
		suite.assert_true(sprite.texture != null and sprite.hframes == 4 and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "actual imported enemy phase raster is nonblank and pixel filtered")
		var label := Label.new()
		label.text = tr(definition.name_key)
		label.position = Vector2(-35, 30)
		label.size = Vector2(70, 40)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		actor.add_child(label)
	suite.assert_equal(index, 22, "all twenty-two authored species have actual native scene resources")
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var root := "res://build/visual-evidence/p17c-enemy-art"
		DirAccess.make_dir_recursive_absolute(root)
		get_viewport().get_texture().get_image().save_png(root.path_join("native-enemies.png"))
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
