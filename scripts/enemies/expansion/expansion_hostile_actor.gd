class_name ExpansionHostileActor
extends "res://scripts/enemies/launch/launch_hostile_actor.gd"

const ExpansionRuntime := preload("res://scripts/enemies/expansion/expansion_enemy_runtime.gd")


func _create_launch_runtime() -> RefCounted:
	return ExpansionRuntime.new()


func configure_expansion_visual(path: String) -> bool:
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty() or image.get_size() != Vector2i(128, 32):
		return false
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return false
	sprite.texture = ImageTexture.create_from_image(image)
	return true
