class_name ActorAtlasProjection
extends Sprite2D

const ROOT := "res://assets/production/actors/"
const STATES := ["idle", "move", "attack", "cast", "hurt", "death"]
const CHARACTERS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
const BOSSES := ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
var _actor_id := ""
var _descriptor: Dictionary = {}
var _state := "idle"
var _state_clock := 0.0


func configure(actor_id: String) -> bool:
	if actor_id == _actor_id and texture != null:
		visible = true
		return true
	visible = false
	if actor_id not in CHARACTERS and actor_id not in BOSSES:
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	if not parsed is Dictionary or parsed.get("schema_id") != "plane_walker_actor_atlas_v1" or parsed.get("schema_version") != 1 or parsed.get("states") != STATES or not parsed.get("assets") is Array:
		return false
	var row: Dictionary = {}
	for entry: Variant in parsed.assets:
		if entry is Dictionary and entry.get("id") == actor_id:
			if not row.is_empty():
				return false
			row = entry.duplicate(true)
	var size := 48 if actor_id in CHARACTERS else 80
	if row.get("path") != actor_id + ".png" or row.get("frame_width") != size or row.get("frame_height") != size or row.get("columns") != 4 or row.get("rows") != 6 or row.get("width") != size * 4 or row.get("height") != size * 6 or row.get("filter") != "nearest" or not row.get("fps") is Dictionary or row.fps.size() != STATES.size():
		return false
	for state: String in STATES:
		var fps: Variant = row.fps.get(state)
		if typeof(fps) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(fps)) or float(fps) != floor(float(fps)) or int(fps) < 1 or int(fps) > 30:
			return false
	var path := ROOT + actor_id + ".png"
	if not ResourceLoader.exists(path, "Texture2D"):
		return false
	var candidate := load(path) as Texture2D
	if candidate == null or candidate.get_size() != Vector2(size * 4, size * 6):
		return false
	texture = candidate
	_actor_id = actor_id
	_descriptor = row
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hframes = 4
	vframes = 6
	frame = 0
	_state = "idle"
	_state_clock = 0.0
	visible = true
	return true


func present(state: StringName, facing: Vector2, clock: float, flash: bool, reduced_motion: bool) -> bool:
	if texture == null or _descriptor.is_empty() or not is_finite(clock) or clock < 0.0:
		return false
	var normalized := str(state)
	match normalized:
		"dash": normalized = "move"
		"hit": normalized = "hurt"
		"time_stop", "time_rewind", "windup", "heal": normalized = "cast"
		"recovery": normalized = "idle"
	if normalized not in STATES:
		return false
	if normalized != _state:
		_state = normalized
		_state_clock = clock
	var elapsed := maxf(0.0, clock - _state_clock)
	var index := int(elapsed * int(_descriptor.fps[_state]))
	index = mini(3, index) if _state == "death" else index % 4
	if reduced_motion:
		index = 3 if _state == "death" else 0
	frame = STATES.find(_state) * 4 + index
	if absf(facing.x) > 0.001:
		flip_h = facing.x < 0.0
	modulate = Color(1.6, 1.6, 1.6) if flash else Color.WHITE
	return true


func snapshot() -> Dictionary:
	return {"actor_id": _actor_id, "state": _state, "frame": frame, "flip_h": flip_h, "visible": visible, "texture_size": texture.get_size() if texture != null else Vector2.ZERO, "filter": texture_filter}
