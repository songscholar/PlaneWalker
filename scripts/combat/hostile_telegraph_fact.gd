class_name HostileTelegraphFact
extends RefCounted

const FIELDS: Array[String] = [
	"hostile_source_id",
	"attack_generation",
	"shape",
	"origin",
	"aim_direction",
	"target_point",
	"summon_slots",
	"radius",
	"length",
	"active_from_frame",
	"active_through_frame",
]
const SHAPES := {
	"circle": true,
	"cone": true,
	"line": true,
	"rift": true,
	"ring": true,
	"summon_slots": true,
	"target_circle": true,
}
const MAX_SOURCE_ID_LENGTH := 64


static func create(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source := value as Dictionary
	if source.size() != FIELDS.size():
		return {}
	for field: String in FIELDS:
		if not source.has(field):
			return {}
	for key: Variant in source.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not FIELDS.has(str(key)):
			return {}

	var source_id_value: Variant = source["hostile_source_id"]
	if typeof(source_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {}
	var source_id := StringName(str(source_id_value).strip_edges())
	if source_id == &"" or str(source_id).length() > MAX_SOURCE_ID_LENGTH:
		return {}
	if typeof(source["attack_generation"]) != TYPE_INT:
		return {}
	var generation := int(source["attack_generation"])
	if generation <= 0:
		return {}
	if typeof(source["shape"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {}
	var shape := str(source["shape"]).strip_edges()
	if not SHAPES.has(shape):
		return {}
	if (
		typeof(source["origin"]) != TYPE_VECTOR2
		or typeof(source["aim_direction"]) != TYPE_VECTOR2
		or typeof(source["target_point"]) != TYPE_VECTOR2
	):
		return {}
	var origin := source["origin"] as Vector2
	var aim_direction := source["aim_direction"] as Vector2
	var target_point := source["target_point"] as Vector2
	if not _finite_vector(origin) or not _finite_vector(aim_direction) or not _finite_vector(target_point):
		return {}
	if aim_direction.is_zero_approx():
		return {}
	if not source["summon_slots"] is Array:
		return {}
	var summon_slots: Array[Vector2] = []
	for slot_value: Variant in source["summon_slots"] as Array:
		if typeof(slot_value) != TYPE_VECTOR2 or not _finite_vector(slot_value as Vector2):
			return {}
		summon_slots.append(slot_value as Vector2)
	if typeof(source["radius"]) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	if typeof(source["length"]) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	var radius := float(source["radius"])
	var length := float(source["length"])
	if not is_finite(radius) or radius < 0.0 or not is_finite(length) or length < 0.0:
		return {}
	if typeof(source["active_from_frame"]) != TYPE_INT:
		return {}
	if typeof(source["active_through_frame"]) != TYPE_INT:
		return {}
	var active_from := int(source["active_from_frame"])
	var active_through := int(source["active_through_frame"])
	if active_from < 0 or active_through < active_from:
		return {}
	if not _shape_geometry_is_valid(shape, radius, length, summon_slots):
		return {}

	return {
		"hostile_source_id": source_id,
		"attack_generation": generation,
		"shape": shape,
		"origin": origin,
		"aim_direction": aim_direction.normalized(),
		"target_point": target_point,
		"summon_slots": summon_slots.duplicate(),
		"radius": radius,
		"length": length,
		"active_from_frame": active_from,
		"active_through_frame": active_through,
	}


static func identity_key(value: Dictionary) -> String:
	var fact := create(value)
	if fact.is_empty():
		return ""
	return "%s#%d" % [str(fact["hostile_source_id"]), int(fact["attack_generation"])]


static func _shape_geometry_is_valid(
	shape: String,
	radius: float,
	length: float,
	summon_slots: Array[Vector2]
) -> bool:
	match shape:
		"circle", "ring", "target_circle":
			return radius > 0.0
		"cone", "line", "rift":
			return radius > 0.0 and length > 0.0
		"summon_slots":
			return radius > 0.0 and not summon_slots.is_empty()
	return false


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
