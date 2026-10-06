class_name PlayerEffectAtlasProjection
extends Sprite2D

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const EFFECT_IDS := ["weapon_arc", "arrow_trail", "muzzle_flash", "spell_burst", "time_ring", "rift_bloom"]
static var _assets: Dictionary = {}

var _effect_id := ""
var _marker := ""
var _start_clock := 0.0


func present(effect_id: String, marker: String, clock: float, duration: float, reduced_motion: bool) -> bool:
	if effect_id not in EFFECT_IDS or marker.is_empty() or not is_finite(clock) or clock < 0.0 or not is_finite(duration) or duration <= 0.0:
		clear()
		return false
	if not _assets.has(effect_id):
		var descriptor := Catalog.asset(&"player_effects", StringName(effect_id))
		var path := Catalog.ROOT_PATH + str(descriptor.get("path", ""))
		if descriptor.get("filter") != "nearest" or descriptor.get("frame_width") != 32 or descriptor.get("frame_height") != 32 or descriptor.get("frame_count") != 4:
			clear()
			return false
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(descriptor.get("sha256", "")) or not ResourceLoader.exists(path, "Texture2D"):
			clear()
			return false
		var candidate := load(path) as Texture2D
		if candidate == null or candidate.get_size() != Vector2(128, 32):
			clear()
			return false
		_assets[effect_id] = candidate
	if _effect_id != effect_id or _marker != marker:
		_effect_id = effect_id
		_marker = marker
		_start_clock = clock
		texture = _assets[effect_id]
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hframes = 4
		vframes = 1
	var elapsed := maxf(0.0, clock - _start_clock)
	frame = 1 if reduced_motion else clampi(int(elapsed * 4.0 / duration), 0, 3)
	visible = true
	return true


func clear() -> void:
	visible = false
	_effect_id = ""
	_marker = ""
	_start_clock = 0.0


func snapshot() -> Dictionary:
	return {"effect_id": _effect_id, "marker": _marker, "frame": frame, "visible": visible, "filter": texture_filter}
