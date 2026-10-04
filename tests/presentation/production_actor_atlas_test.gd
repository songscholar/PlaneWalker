extends Node2D

const Suite := preload("res://tests/support/test_suite.gd")
const ACTORS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord", "ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
const STATES := ["idle", "move", "attack", "cast", "hurt", "death"]
var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/production/actors/manifest.json"))
	suite.assert_true(parsed is Dictionary and parsed.get("schema_id") == "plane_walker_actor_atlas_v1", "native PNG library has an actual structured manifest")
	if not parsed is Dictionary:
		suite.finish(get_tree())
		return
	var rows: Dictionary = {}
	for row: Dictionary in parsed.assets:
		rows[row.id] = row
	for index: int in range(ACTORS.size()):
		var id: String = ACTORS[index]
		var row: Dictionary = rows[id]
		var path := "res://assets/production/actors/" + str(row.path)
		suite.assert_equal(FileAccess.get_sha256(path), row.sha256, "actual native actor PNG matches the declared asset manifest")
		var texture: Texture2D = load(path)
		suite.assert_true(texture != null and texture.get_size() == Vector2(row.width, row.height), "native Godot imports the expected actor atlas dimensions")
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.hframes = 4
		sprite.vframes = 6
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(64 + index % 5 * 128, 96 + index / 5 * 174)
		sprite.scale = Vector2.ONE * (1.5 if index < 5 else 1.0)
		add_child(sprite)
		_sprites.append(sprite)
		var label := Label.new()
		label.position = Vector2(5 + index % 5 * 128, 148 + index / 5 * 174)
		label.size = Vector2(118, 28)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = id.replace("_", " ")
		label.add_theme_font_size_override("font_size", 12)
		add_child(label)
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		for state: int in range(6):
			for frame: int in range(4):
				var crop := image.get_region(Rect2i(frame * int(row.frame_width), state * int(row.frame_height), int(row.frame_width), int(row.frame_height)))
				suite.assert_true(not crop.is_invisible(), "native atlas cell is nonblank: %s %s %d" % [id, STATES[state], frame])
	for state: int in range(6):
		for frame: int in range(4):
			for sprite: Sprite2D in _sprites:
				sprite.frame = state * 4 + frame
			await get_tree().process_frame
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var directory := "res://build/visual-evidence/p17a-actor-atlases"
			DirAccess.make_dir_recursive_absolute(directory)
			get_viewport().get_texture().get_image().save_png(directory + "/" + STATES[state] + ".png")
	for child: Node in get_children():
		child.queue_free()
	_sprites.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
