extends CanvasLayer

const Artwork := preload("res://scripts/dungeon/native_room_artwork.gd")

var _floor_id := ""
var _backdrop: TextureRect
var _extent := Vector2i.ZERO
var _final_transform := Transform2D.IDENTITY


func _ready() -> void:
	layer = -100
	_backdrop = TextureRect.new()
	_backdrop.name = "ModeArenaBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_backdrop.stretch_mode = TextureRect.STRETCH_TILE
	_backdrop.modulate = Color(0.55, 0.55, 0.55, 1.0)
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_queue_fit_viewport)
	_fit_viewport()


func _queue_fit_viewport() -> void:
	call_deferred("_fit_viewport")


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport.size != _extent or viewport.get_final_transform() != _final_transform:
		_fit_viewport()


func _fit_viewport() -> void:
	# Integer canvas stretching can leave side bands outside the design rect.
	var viewport := get_viewport()
	_extent = viewport.size
	_final_transform = viewport.get_final_transform()
	var inverse := _final_transform.affine_inverse()
	var start := inverse * Vector2.ZERO
	var physical_size := Vector2(viewport.size).max(viewport.get_visible_rect().size)
	var end := inverse * physical_size
	_backdrop.position = start
	_backdrop.size = end - start


func configure(floor_id: String) -> bool:
	if not is_inside_tree() or not Artwork.FLOOR_ART.has(floor_id):
		return false
	if floor_id == _floor_id and _backdrop.texture != null:
		return true
	var tiles := load(Artwork.ART_ROOT + str(Artwork.FLOOR_ART[floor_id]) + "_tiles.png") as Texture2D
	if tiles == null:
		return false
	var image := tiles.get_image()
	if image == null or image.is_empty():
		return false
	_backdrop.texture = ImageTexture.create_from_image(image.get_region(Rect2i(0, 0, 32, 32)))
	_floor_id = floor_id
	return true
