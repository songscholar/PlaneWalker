extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const CONTENT := "res://data/content_packs/base/content/enemies.json"
const LEGACY_SCENE_RADII := {"shattered_sentinel": 12.0, "stone_shell_strider": 12.0, "ruins_wraith": 9.0}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string(CONTENT))
	suite.assert_equal(definitions.size(), 22, "all launch enemies are exercised")
	for definition: Dictionary in definitions:
		var identity: String = definition.id
		var scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % identity) as PackedScene
		suite.assert_true(scene != null, identity + " scene loads")
		if scene == null:
			continue
		var actor := scene.instantiate() as CharacterBody2D
		add_child(actor)
		var sprite := actor.get_node("Sprite2D") as Sprite2D
		suite.assert_equal(sprite.texture.resource_path, "res://assets/production/enemies/%s.png" % identity, identity + " consumes the production atlas")
		suite.assert_equal(sprite.texture.get_size(), Vector2(192, 48), identity + " uses 48px phase cells")
		suite.assert_equal(sprite.hframes, 4, identity + " has four runtime phases")
		suite.assert_equal(sprite.vframes, 1, identity + " has one phase row")
		suite.assert_equal(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, identity + " preserves pixel edges")
		var shape := actor.get_node("CollisionShape2D") as CollisionShape2D
		suite.assert_equal((shape.shape as CircleShape2D).radius, float(LEGACY_SCENE_RADII.get(identity, definition.collision_radius_px)), identity + " retains authored collision radius")
		actor.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
