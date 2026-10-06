class_name UiArtwork
extends RefCounted

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const ActorAtlas := preload("res://scripts/presentation/actor_atlas_projection.gd")
const RoomArtwork := preload("res://scripts/dungeon/native_room_artwork.gd")
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


static func content(content_id: String, category: String = "") -> Texture2D:
	if content_id.is_empty():
		return null
	var batches := {"item": "items", "blessing": "blessings", "curse": "curses", "contract": "curses", "talent": "talents"}
	if batches.has(category):
		var category_texture := icon(StringName(batches[category]), StringName(content_id))
		if category_texture != null:
			return category_texture
	for batch: String in ["items", "blessings", "curses", "talents"]:
		var texture := icon(StringName(batch), StringName(content_id))
		if texture != null:
			return texture
	# Data-only Mod content keeps its requested identity while using a neutral,
	# authenticated package glyph instead of an empty or misleading known icon.
	var generic := icon(&"controls", &"content") as AtlasTexture
	if generic == null:
		return null
	var fallback := AtlasTexture.new()
	fallback.atlas = generic.atlas
	fallback.region = generic.region
	fallback.set_meta("requested_content_id", content_id)
	fallback.set_meta("requested_category", category)
	return fallback


static func landmark(room_type: String) -> Texture2D:
	var index := RoomArtwork.LANDMARK_FRAMES.find(room_type)
	if index < 0:
		return icon(&"room_types", StringName(room_type))
	var base := icon(&"rooms", &"landmarks") as AtlasTexture
	if base == null or base.atlas.get_width() < (index + 1) * 64 or base.atlas.get_height() < 64:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = base.atlas
	texture.region = Rect2(index * 64, 0, 64, 64)
	return texture


static func floor_tile(floor_id: String) -> Texture2D:
	var palette := str(RoomArtwork.FLOOR_ART.get(floor_id, ""))
	return icon(&"rooms", StringName(palette + "_tiles")) if not palette.is_empty() else null


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
