class_name PlayerZoneAtlasProjection
extends Node2D

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const IDS := ["ice_zone", "planar_collapse", "seeded_sequence", "steam_burst", "crystal_thunder", "reverse_steam", "thunder_flare", "thunder_crystal", "blazing_storm", "space_time_shatter", "primordial_collapse", "charged_heavy_shockwave", "rewind_counter_shockwave"]
static var _textures: Dictionary = {}
var _reduced_motion := false
var _sprites: Array[Sprite2D] = []


static func attach(zone: Node2D) -> void:
	if zone.get_node_or_null("ProductionZoneAtlas") == null:
		var projection := PlayerZoneAtlasProjection.new()
		projection.name = "ProductionZoneAtlas"
		projection.z_index = -2
		zone.add_child(projection)


func _ready() -> void:
	_reduced_motion = bool(GameState.get_setting("reduced_motion", false))
	GameState.setting_changed.connect(_on_setting_changed)
	sync_from_owner()


func _process(_delta: float) -> void:
	sync_from_owner()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func sync_from_owner() -> void:
	var zone := get_parent() as Node2D
	visible = false
	if zone == null or not bool(zone.get("_execution_active")) or zone.is_queued_for_deletion():
		return
	var mode := str(zone.get("mode"))
	var parameters: Dictionary = zone.get("parameters")
	var values: Dictionary = parameters.get("combo_parameters", {}) if mode == "combination" else parameters
	var identity := str(parameters.get("combo_id", "")) if mode == "combination" else mode
	if identity not in IDS:
		return
	var frame_index := int(zone.get("_execution_frame"))
	var radius_tiles := float(values.get("radius_tiles", 0.0))
	if identity == "reverse_steam":
		radius_tiles = float(values.get("freeze_radius_tiles", 0.0)) if frame_index < int(values.get("delay_frames", 0)) else float(values.get("explosion_radius_tiles", 0.0))
	if not is_finite(radius_tiles) or radius_tiles <= 0.0:
		return
	var locations: Array = values.get("origins", []) if identity in ["thunder_flare", "thunder_crystal"] else [Vector2.ZERO]
	if locations.is_empty() or locations.size() > 64 or not locations.all(func(value: Variant) -> bool: return value is Vector2 and (value as Vector2).is_finite()):
		return
	var texture := _texture(identity)
	if texture == null:
		return
	while _sprites.size() < locations.size():
		var sprite := Sprite2D.new()
		sprite.name = "Primary" if _sprites.is_empty() else "Origin%d" % _sprites.size()
		sprite.hframes = 4
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		_sprites.append(sprite)
	while _sprites.size() > locations.size():
		var retired: Sprite2D = _sprites.pop_back()
		remove_child(retired)
		retired.queue_free()
	for index: int in range(_sprites.size()):
		var sprite := _sprites[index]
		sprite.texture = texture
		sprite.frame = 0 if _reduced_motion else (frame_index / 6) % 4
		sprite.scale = Vector2.ONE * radius_tiles * 64.0 / 30.0
		if identity in ["thunder_flare", "thunder_crystal"]:
			sprite.global_position = locations[index]
		else:
			sprite.position = Vector2.ZERO
	visible = true


func _texture(identity: String) -> Texture2D:
	if not _textures.has(identity):
		var descriptor := Catalog.asset(&"player_zones", StringName(identity))
		var path := Catalog.ROOT_PATH + str(descriptor.get("path", ""))
		if descriptor.get("filter") != "nearest" or descriptor.get("frame_count") != 4 or descriptor.get("frame_width") != 64 or descriptor.get("frame_height") != 64 or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(descriptor.get("sha256", "")) or not ResourceLoader.exists(path, "Texture2D"):
			return null
		var texture := load(path) as Texture2D
		if texture == null or texture.get_size() != Vector2(256, 64):
			return null
		_textures[identity] = texture
	return _textures[identity]


func _on_setting_changed(setting_id: StringName, value: Variant) -> void:
	if setting_id == &"reduced_motion":
		set_reduced_motion(bool(value))
