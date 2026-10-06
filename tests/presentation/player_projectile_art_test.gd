extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Arrow := preload("res://scenes/combat/player_arrow.tscn")
const Bullet := preload("res://scenes/combat/gun_projectile.tscn")
const Spell := preload("res://scenes/combat/staff_projectile.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(stage)
	for fixture: Array in [[Arrow, "arrow", 5.0], [Bullet, "bullet", 4.0], [Spell, "staff_arcane", 9.6]]:
		var projectile: Area2D = fixture[0].instantiate()
		if fixture[1] == "staff_arcane":
			projectile.element_id = "arcane"
		stage.add_child(projectile)
		var visual := projectile.get_node("Visual") as Sprite2D
		suite.assert_true(visual != null, fixture[1] + " replaces the polygon with a raster projection")
		if visual != null:
			suite.assert_true(visual.texture != null and visual.visible, fixture[1] + " loads actual production pixels")
			suite.assert_equal(visual.texture.resource_path, "res://assets/production/ui/player_projectiles/%s.png" % fixture[1], "correct projectile identity is selected")
			var before: Dictionary = projectile.execution_snapshot()
			visual.advance_visual(0.09)
			suite.assert_true(visual.frame > 0, "projectile bitmap animation advances")
			visual.set_reduced_motion(true)
			visual.advance_visual(0.09)
			suite.assert_equal(visual.frame, 0, "reduced motion freezes projectile raster")
			suite.assert_equal(projectile.execution_snapshot(), before, "art preserves native projectile execution and replay")
			if fixture[1] == "staff_arcane":
				for element: String in ["fire", "ice", "lightning"]:
					projectile.element_id = element
					visual.advance_visual(0.0)
					suite.assert_true(visual.texture.resource_path.ends_with("staff_%s.png" % element), "staff element selects authored artwork: " + element)
				projectile.element_id = "unknown"
				visual.advance_visual(0.0)
				suite.assert_true(not visual.visible, "unknown element cannot borrow a projectile image")
			else:
				visual.visible = false
				visual.advance_visual(0.09)
				suite.assert_true(not visual.visible, "completed native projectile stays hidden")
		suite.assert_close(projectile.get_node("CollisionShape2D").shape.radius, fixture[2], "original hit radius is preserved")
		suite.assert_equal(projectile.collision_mask, 5, "original target collision mask is preserved")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
