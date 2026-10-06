class_name PlayerProjectileAtlasProjection
extends Sprite2D

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const IDS := ["arrow", "bullet", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"]
static var _textures: Dictionary = {}

@export var projectile_id := "arrow"
@export var bind_staff_element := false

var _asset_id := ""
var _clock := 0.0
var _reduced_motion := false


func _ready() -> void:
	_reduced_motion = bool(GameState.get_setting("reduced_motion", false))
	GameState.setting_changed.connect(_on_setting_changed)
	advance_visual(0.0)


func _process(delta: float) -> void:
	advance_visual(delta)


func advance_visual(delta: float) -> void:
	var next_id := projectile_id
	if bind_staff_element:
		next_id = "staff_" + str(get_parent().get("element_id"))
	if next_id != _asset_id and not _configure(next_id):
		return
	if not _reduced_motion:
		_clock += maxf(0.0, delta)
	frame = 0 if _reduced_motion else int(_clock * 12.0) % 4


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		frame = 0


func _configure(identity: String) -> bool:
	if identity not in IDS:
		visible = false
		_asset_id = ""
		return false
	if not _textures.has(identity):
		var descriptor := Catalog.asset(&"player_projectiles", StringName(identity))
		var path := Catalog.ROOT_PATH + str(descriptor.get("path", ""))
		if descriptor.get("frame_count") != 4 or descriptor.get("frame_width") != 32 or descriptor.get("frame_height") != 32 or descriptor.get("filter") != "nearest" or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != descriptor.get("sha256"):
			visible = false
			return false
		var candidate := load(path) as Texture2D
		if candidate == null or candidate.get_size() != Vector2(128, 32):
			visible = false
			return false
		_textures[identity] = candidate
	texture = _textures[identity]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hframes = 4
	vframes = 1
	_asset_id = identity
	_clock = 0.0
	visible = true
	return true


func _on_setting_changed(setting_id: StringName, value: Variant) -> void:
	if setting_id == &"reduced_motion":
		set_reduced_motion(bool(value))
