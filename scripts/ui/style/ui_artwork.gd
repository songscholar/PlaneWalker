class_name UiArtwork
extends RefCounted

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const ActorAtlas := preload("res://scripts/presentation/actor_atlas_projection.gd")
static var _textures: Dictionary = {}


static func icon(batch_id: StringName, asset_id: StringName) -> Texture2D:
	var key := str(batch_id) + ":" + str(asset_id)
	if _textures.has(key):
		return _textures[key] as Texture2D
	var entry := Catalog.asset(batch_id, asset_id)
	var path := Catalog.texture_path(batch_id, asset_id)
	if entry.is_empty() or path.is_empty() or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != entry.get("sha256", ""):
		return null
	var source := load(path) as Texture2D
	var width := int(entry.get("frame_width", 32))
	var height := int(entry.get("frame_height", 32))
	if source == null or source.get_width() < width or source.get_height() < height:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = source
	texture.region = Rect2(0, 0, width, height)
	_textures[key] = texture
	return texture


static func actor(actor_id: String) -> Texture2D:
	var key := "actor:" + actor_id
	if _textures.has(key):
		return _textures[key] as Texture2D
	var projection := ActorAtlas.new()
	if not projection.configure(actor_id):
		projection.free()
		return null
	var texture := AtlasTexture.new()
	texture.atlas = projection.texture
	texture.region = Rect2(0, 0, projection.texture.get_width() / 4, projection.texture.get_height() / 6)
	projection.free()
	_textures[key] = texture
	return texture


static func image(texture: Texture2D, size: int = 32, node_name: String = "Artwork") -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.texture = texture
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.custom_minimum_size = Vector2(size, size)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_meta("production_ui_art", true)
	return view


static func button_icon(button: Button, texture: Texture2D) -> void:
	button.icon = texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", 24)
	button.add_theme_constant_override("h_separation", 8)
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
