extends RefCounted

const FLOOR_ART := {"floor_ruins_of_remnant": "ruins", "floor_void_forest": "forest", "floor_time_rift": "rift", "floor_plane_forge": "forge", "floor_throne_of_void": "void"}
const LANDMARK_FRAMES := ["combat", "elite", "boss", "treasure", "shop", "rest", "event"]
const ART_ROOT := "res://assets/production/rooms/"
var _presentation: Dictionary = {}
var _root: Node2D


func configure(binding: Dictionary, room: Node2D) -> bool:
	if not FLOOR_ART.has(binding.get("floor_id")) or not LANDMARK_FRAMES.has(binding.get("room_type")):
		return false
	var palette: String = FLOOR_ART[binding.floor_id]
	var tiles := load(ART_ROOT + palette + "_tiles.png") as Texture2D
	var wall := load(ART_ROOT + palette + "_wall.png") as Texture2D
	var door := load(ART_ROOT + palette + "_door.png") as Texture2D
	var landmarks := load(ART_ROOT + "landmarks.png") as Texture2D
	if tiles == null or wall == null or door == null or landmarks == null:
		return false
	if not is_instance_valid(_root):
		_root = Node2D.new()
		_root.name = "RoomArtwork"
		room.add_child(_root)
	for child: Node in _root.get_children():
		_root.remove_child(child)
		child.free()
	_root.z_index = -30
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(binding.content_id) + ":" + str(binding.room_seed)).hash()
	var tile_frames: Array[int] = []
	var floor_tiles := Node2D.new()
	floor_tiles.name = "FloorTiles"
	_root.add_child(floor_tiles)
	for y: int in range(12):
		for x: int in range(20):
			var frame := rng.randi_range(0, 3)
			tile_frames.append(frame)
			var sprite := _sprite(floor_tiles, tiles, Vector2(x * 32, y * 32))
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(frame * 32, 0, 32, mini(32, 360 - y * 32))
	var borders := Node2D.new()
	borders.name = "Masonry"
	_root.add_child(borders)
	for x: int in range(10):
		for y: int in [0, 344]:
			var sprite := _sprite(borders, wall, Vector2(x * 64, y))
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, 64, 16)
	for y: int in range(16, 344, 32):
		if y >= 144 and y < 216:
			continue
		for x: int in [0, 624]:
			var sprite := _sprite(borders, wall, Vector2(x, y))
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, 16, mini(32, 344 - y))
	for x: int in [24, 616]:
		var doorway := _sprite(_root, door, Vector2(x, 180))
		doorway.name = "DoorwayWest" if x == 24 else "DoorwayEast"
	var landmark_position := Vector2(320, 68)
	var anchors := room.get_node_or_null("InteractionAnchors")
	if anchors != null:
		for anchor: Node in anchors.get_children():
			if anchor is Marker2D and str(anchor.get_meta("kind", "")) == str(binding.room_type):
				landmark_position = anchor.position + Vector2(0, -12)
	var landmark := _sprite(_root, landmarks, landmark_position)
	landmark.name = "Landmark"
	landmark.hframes = LANDMARK_FRAMES.size()
	landmark.frame = LANDMARK_FRAMES.find(binding.room_type)
	_presentation = {"floor_id": binding.floor_id, "content_id": binding.content_id, "room_seed": int(binding.room_seed), "palette": palette, "tile_frames": tile_frames, "landmark_position": landmark_position, "landmark_frame": landmark.frame}
	_root.visible = true
	return true


func presentation_snapshot() -> Dictionary:
	return _presentation.duplicate(true)


static func _sprite(parent: Node2D, texture: Texture2D, position: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = position
	parent.add_child(sprite)
	return sprite
