class_name HostileActionContract
extends RefCounted

const FIELDS: Array[String] = [
	"id", "handler_id", "warning_frames", "active_frames", "recovery_frames",
	"idle_frames", "cooldown_frames", "weight", "max_consecutive",
	"distance_min_px", "distance_max_px", "geometry", "hit_schedule", "parameters", "cue_id",
]
const GEOMETRY_FIELDS: Array[String] = ["shape", "origin_offset", "aim_offset_degrees", "radius", "length"]
const HIT_FIELDS: Array[String] = ["offset_frame", "hit_index", "damage", "damage_type"]
const ACTOR_KINDS: Array[String] = ["enemy", "elite", "summon", "boss"]
const SHAPES: Array[String] = ["circle", "cone", "line", "rift", "ring", "summon_slots", "target_circle"]
const DAMAGE_TYPES: Array[String] = ["physical", "time", "void", "fire", "ice", "lightning"]
const MAX_FRAME := 36000
const MAX_PRIMITIVES := 16
const MAX_HITS := 64
const PARAMETER_RULES := {
	"melee": {"knockback_px": [0, 64, false]},
	"charge": {"travel_px": [0, 640, false], "speed_px_per_second": [1, 480, false], "knockback_px": [0, 64, false]},
	"projectile_volley": {"speed_px_per_second": [1, 480, false], "lifetime_frames": [1, 600, true], "pierce_count": [0, 8, true]},
	"zone": {"lifetime_frames": [1, 1200, true], "tick_interval_frames": [1, 600, true], "slow_multiplier": [0.4, 1.0, false], "slow_duration_frames": [0, 600, true]},
	"heal": {"heal_amount": [0, 300, false], "recipient_radius_px": [0, 320, false]},
	"shield": {"shield_fraction": [0, 0.3, false], "lifetime_frames": [1, 600, true]},
	"summon": {"definition_id": "id", "count": [1, 8, true], "lifetime_frames": [1, 1200, true]},
	"blink": {"travel_px": [0, 160, false], "transit_frames": [1, 30, true], "landing_warning_frames": [23, 120, true]},
	"wall": {"hit_points": [1, 100, false], "lifetime_frames": [1, 1200, true], "gap_px": [32, 320, false]},
	"link": {"hit_points": [1, 100, false], "lifetime_frames": [1, 1200, true], "attack_multiplier": [1, 1.25, false], "speed_multiplier": [1, 1.25, false]},
	"portal": {"lifetime_frames": [1, 1200, true], "min_distance_px": [96, 640, false], "arrival_clearance_px": [48, 320, false], "transit_cooldown_frames": [12, 600, true], "team_rule": "team_rule"},
	"self_rewind": {"max_cast_heal": [0, 150, false], "max_total_heal": [0, 300, false], "history_frames": [1, 180, true]},
	"phase_transition": {"phase_id": "id", "cue_frames": [60, 180, true]},
	"pull_zone": {"lifetime_frames": [1, 1200, true], "tick_interval_frames": [1, 600, true], "pull_px_per_second": [0, 32, false], "slow_multiplier": [0.4, 1.0, false]},
	"arena_core": {"hit_points": [1, 100, false], "body_damage": [0, 100, false], "exposure_frames": [20, 60, true], "max_rounds": [1, 2, true]},
}


static func handler_ids() -> Array[String]:
	var result: Array[String] = []
	for key: String in PARAMETER_RULES:
		result.append(key)
	result.sort()
	return result


static func create(source: Dictionary, actor_kind: String) -> Dictionary:
	if not ACTOR_KINDS.has(actor_kind):
		return failure("actor_kind", "unsupported")
	if not exact_fields(source, FIELDS):
		return failure("action", "exact_fields_required")
	if not valid_id(source.id) or not valid_id(source.cue_id):
		return failure("id", "invalid")
	if typeof(source.handler_id) != TYPE_STRING or not PARAMETER_RULES.has(source.handler_id):
		return failure("handler_id", "unsupported")
	var result := source.duplicate(true)
	for field: String in ["warning_frames", "active_frames", "recovery_frames", "idle_frames", "cooldown_frames"]:
		var minimum := 1 if field == "active_frames" else 0
		if not integer_in_range(source[field], minimum, MAX_FRAME):
			return failure(field, "invalid_frames")
		result[field] = int(source[field])
	if result.warning_frames + result.active_frames + result.recovery_frames + result.idle_frames > MAX_FRAME:
		return failure("action", "duration_exceeds_bound")
	var warning_minimum := 25 if actor_kind == "boss" else 23
	if result.warning_frames < warning_minimum:
		return failure("warning_frames", "below_warning_floor")
	if not integer_in_range(source.weight, 1, 100) or not integer_in_range(source.max_consecutive, 1, 3):
		return failure("weight", "invalid_selection")
	result.weight = int(source.weight)
	result.max_consecutive = int(source.max_consecutive)
	for field: String in ["distance_min_px", "distance_max_px"]:
		if not number_in_range(source[field], 0, 640):
			return failure(field, "invalid_distance")
		result[field] = float(source[field])
	if result.distance_min_px > result.distance_max_px:
		return failure("distance_min_px", "greater_than_max")
	var geometry_result := _geometry(source.geometry)
	if not geometry_result.ok:
		return geometry_result
	result.geometry = geometry_result.value
	var hit_result := _hits(source.hit_schedule, result.active_frames)
	if not hit_result.ok:
		return hit_result
	result.hit_schedule = hit_result.value
	var damaging := false
	for hit: Dictionary in result.hit_schedule:
		damaging = damaging or hit.damage > 0
	if damaging:
		if result.geometry.is_empty():
			return failure("geometry", "damage_requires_geometry")
		if result.recovery_frames < (20 if actor_kind == "boss" else 15):
			return failure("recovery_frames", "below_recovery_floor")
	var parameters_result := _parameters(source.handler_id, source.parameters)
	if not parameters_result.ok:
		return parameters_result
	result.parameters = parameters_result.value
	return {"ok": true, "definition": result, "context": {}}


static func _geometry(value: Variant) -> Dictionary:
	if not value is Array or value.size() > MAX_PRIMITIVES:
		return failure("geometry", "invalid_array")
	var rows: Array[Dictionary] = []
	for candidate: Variant in value:
		if not candidate is Dictionary or not exact_fields(candidate, GEOMETRY_FIELDS):
			return failure("geometry", "exact_fields_required")
		if typeof(candidate.shape) != TYPE_STRING or not SHAPES.has(candidate.shape):
			return failure("geometry.shape", "unsupported")
		if not valid_point(candidate.origin_offset, 640):
			return failure("geometry.origin_offset", "invalid_point")
		if not number_in_range(candidate.aim_offset_degrees, -180, 180):
			return failure("geometry.aim_offset_degrees", "invalid_angle")
		if not number_in_range(candidate.radius, 0, 320) or not number_in_range(candidate.length, 0, 640):
			return failure("geometry", "invalid_extent")
		if candidate.shape in ["cone", "line", "rift"] and (candidate.length <= 0 or candidate.radius <= 0):
			return failure("geometry", "empty_directed_shape")
		if candidate.shape in ["circle", "ring", "target_circle"] and candidate.radius <= 0:
			return failure("geometry", "empty_circle")
		rows.append({
			"shape": candidate.shape, "origin_offset": point(candidate.origin_offset),
			"aim_offset_degrees": float(candidate.aim_offset_degrees),
			"radius": float(candidate.radius), "length": float(candidate.length),
		})
	return {"ok": true, "value": rows}


static func _hits(value: Variant, active_frames: int) -> Dictionary:
	if not value is Array or value.size() > MAX_HITS:
		return failure("hit_schedule", "invalid_array")
	var rows: Array[Dictionary] = []
	var indices: Array[int] = []
	var previous_offset := -1
	for candidate: Variant in value:
		if not candidate is Dictionary or not exact_fields(candidate, HIT_FIELDS):
			return failure("hit_schedule", "exact_fields_required")
		if not integer_in_range(candidate.offset_frame, 0, active_frames - 1):
			return failure("hit_schedule.offset_frame", "outside_active_interval")
		if not integer_in_range(candidate.hit_index, 0, MAX_HITS - 1):
			return failure("hit_schedule.hit_index", "invalid")
		var hit_index := int(candidate.hit_index)
		var offset := int(candidate.offset_frame)
		if indices.has(hit_index) or offset < previous_offset:
			return failure("hit_schedule", "duplicate_or_unsorted")
		if not number_in_range(candidate.damage, 0, 600):
			return failure("hit_schedule.damage", "invalid")
		if typeof(candidate.damage_type) != TYPE_STRING or not DAMAGE_TYPES.has(candidate.damage_type):
			return failure("hit_schedule.damage_type", "unsupported")
		indices.append(hit_index)
		previous_offset = offset
		rows.append({"offset_frame": offset, "hit_index": hit_index, "damage": float(candidate.damage), "damage_type": candidate.damage_type})
	return {"ok": true, "value": rows}


static func _parameters(handler_id: String, value: Variant) -> Dictionary:
	var rules: Dictionary = PARAMETER_RULES[handler_id]
	if not value is Dictionary or not exact_fields(value, rules.keys()):
		return failure("parameters", "exact_handler_fields_required")
	var result: Dictionary = {}
	for field: String in rules:
		var rule: Variant = rules[field]
		var candidate: Variant = value[field]
		if rule is String:
			if rule == "id" and not valid_id(candidate):
				return failure("parameters." + field, "invalid_id")
			if rule == "team_rule" and (typeof(candidate) != TYPE_STRING or candidate not in ["both", "enemy_only"]):
				return failure("parameters." + field, "unsupported_team")
			result[field] = candidate
		elif rule[2]:
			if not integer_in_range(candidate, rule[0], rule[1]):
				return failure("parameters." + field, "invalid_integer")
			result[field] = int(candidate)
		else:
			if not number_in_range(candidate, rule[0], rule[1]):
				return failure("parameters." + field, "invalid_number")
			result[field] = float(candidate)
	if handler_id == "self_rewind" and result.max_cast_heal > result.max_total_heal:
		return failure("parameters.max_cast_heal", "exceeds_encounter_cap")
	return {"ok": true, "value": result}


static func exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: Variant in fields:
		if not value.has(field):
			return false
	return true


static func integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return number_in_range(value, minimum, maximum) and float(value) == floorf(float(value))


static func number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 96:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code not in [46, 95]:
			return false
	return true


static func valid_point(value: Variant, bound: float = 1000000.0) -> bool:
	return value is Dictionary and exact_fields(value, ["x", "y"]) and number_in_range(value.x, -bound, bound) and number_in_range(value.y, -bound, bound)


static func point(value: Dictionary) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}


static func failure(field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_ACTION_INVALID", "context": {"field": field, "reason": reason}}
