extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const PayloadProjection := preload("res://scripts/enemies/launch/launch_hostile_payload_projection.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
var suite: RefCounted
var _effect_owner: RefCounted = RefCounted.new()
var _projections: Array[Node2D] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for index: int in range(Contract.DAMAGE_TYPES.size()):
		var kind: String = Contract.DAMAGE_TYPES[index]
		for shape: String in ["projectile", "pool"]:
			var position := {"x": 56.0 + index * 96.0, "y": 110.0 if shape == "projectile" else 240.0}
			var definition := {"kind": "projectile" if shape == "projectile" else "impact_pool", "visual_kind": kind, "direction": {"x": 1.0, "y": 0.0}, "radius": 12.0, "position": position}
			var projection := PayloadProjection.new()
			suite.assert_true(projection.configure_payload(_effect_owner, "%s-%s" % [kind, shape], definition), "native %s %s loads original raster" % [kind, shape])
			add_child(projection)
			var row := {"definition": definition, "position": position, "phase": "ACTIVE"}
			suite.assert_true(projection.project_record(row, 1) and projection.native_definition_matches(definition), "native effect has closed physical and visual projection")
			suite.assert_equal(projection.get_node("Sprite2D").texture.resource_path, "res://assets/production/hostile_effects/%s_%s.png" % [kind, shape], "native projection uses its manifested element atlas")
			_projections.append(projection)
	if DisplayServer.get_name() != "headless":
		await _capture()
	for projection: Node2D in _projections:
		projection.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _capture() -> void:
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var background := pixels.get_pixel(0, 0).to_rgba32()
		for projection: Node2D in _projections:
			var colors: Dictionary = {}
			var foreground := 0
			for y: int in range(-16, 17):
				for x: int in range(-16, 17):
					var point := Vector2i((projection.global_position + Vector2(x, y)) * Vector2(pixels.get_size()) / Vector2(640, 360))
					var color := pixels.get_pixelv(point).to_rgba32()
					colors[color] = true
					if color != background:
						foreground += 1
			suite.assert_true(colors.size() >= 4 and foreground > 40, "actual GPU raster is nonblank and correctly framed: " + str(projection.name))
		var path := "res://build/visual-evidence/p15b-hostile-element-effects/effects-%dx%d.png" % [resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "actual native elemental projection screenshot is retained")
