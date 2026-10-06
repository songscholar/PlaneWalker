class_name HeldWeaponAtlasProjection
extends Sprite2D

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const IDS := ["sword", "bow", "gun", "gauntlets", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"]
const PHASES := {"READY": 0, "HOLD": 1, "WINDUP": 1, "ACTIVE": 2, "RESOURCE_ACTION": 1, "RECOVERY": 3, "COMPLETE": 0, "INTERRUPTED": 0}
static var _assets: Dictionary = {}
var _identity := ""


func present(identity: String, phase: String, reduced_motion: bool) -> bool:
	if identity not in IDS or not PHASES.has(phase):
		visible = false
		return false
	if not _assets.has(identity):
		var descriptor := Catalog.asset(&"held_weapons", StringName(identity))
		var path := Catalog.ROOT_PATH + str(descriptor.get("path", ""))
		if descriptor.get("filter") != "nearest" or descriptor.get("frame_width") != 32 or descriptor.get("frame_height") != 32 or descriptor.get("frame_count") != 4:
			visible = false
			return false
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(descriptor.get("sha256", "")) or not ResourceLoader.exists(path, "Texture2D"):
			visible = false
			return false
		var candidate := load(path) as Texture2D
		if candidate == null or candidate.get_size() != Vector2(128, 32):
			visible = false
			return false
		_assets[identity] = candidate
	texture = _assets[identity]
	_identity = identity
	hframes = 4
	vframes = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame = 0 if reduced_motion else int(PHASES[phase])
	visible = true
	return true


func snapshot() -> Dictionary:
	return {"identity": _identity, "frame": frame, "visible": visible, "filter": texture_filter}
