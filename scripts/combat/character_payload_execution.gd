class_name CharacterPayloadExecution
extends RefCounted

const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const MAX_SEGMENT_LENGTH := 64
const EVENT_FIELDS: Array[String] = [
	"kind",
	"event_id",
	"character_id",
	"runtime_frame",
	"token",
	"generation",
	"context",
]
const DECISION_FIELDS: Array[String] = [
	"kind",
	"decision_id",
	"character_id",
	"runtime_frame",
	"token",
	"generation",
	"parameters",
]
const WORLD_PAYLOAD_FIELDS: Array[String] = [
	"payload_id",
	"handler_id",
	"run_id",
	"owner_character_generation",
	"payload_family",
	"source_token",
	"payload_generation",
	"transform",
	"geometry",
	"remaining_frames",
	"claims",
	"tags",
	"parameters",
]


static func decision(
	decision_id: StringName,
	character_id: StringName,
	runtime_frame: int,
	token: int,
	generation: int,
	parameters: Dictionary = {}
) -> Dictionary:
	var value := {
		"kind": &"character_decision",
		"decision_id": decision_id,
		"character_id": character_id,
		"runtime_frame": runtime_frame,
		"token": token,
		"generation": generation,
		"parameters": parameters.duplicate(true),
	}
	return value if is_decision(value) else {}


static func is_decision(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var decision_value := value as Dictionary
	return (
		_has_exact_fields(decision_value, DECISION_FIELDS)
		and decision_value["kind"] == &"character_decision"
		and _valid_segment(decision_value["decision_id"])
		and _valid_segment(decision_value["character_id"])
		and typeof(decision_value["runtime_frame"]) == TYPE_INT
		and int(decision_value["runtime_frame"]) >= 0
		and typeof(decision_value["token"]) == TYPE_INT
		and int(decision_value["token"]) >= 0
		and typeof(decision_value["generation"]) == TYPE_INT
		and int(decision_value["generation"]) > 0
		and decision_value["parameters"] is Dictionary
		and ReplaySafeValueScript.is_supported(decision_value["parameters"])
	)


static func event(
	event_id: StringName,
	character_id: StringName,
	runtime_frame: int,
	token: int,
	generation: int,
	context: Dictionary = {}
) -> Dictionary:
	var value := {
		"kind": &"character_event",
		"event_id": event_id,
		"character_id": character_id,
		"runtime_frame": runtime_frame,
		"token": token,
		"generation": generation,
		"context": context.duplicate(true),
	}
	return value if is_event(value) else {}


static func is_event(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var event_value := value as Dictionary
	return (
		_has_exact_fields(event_value, EVENT_FIELDS)
		and event_value["kind"] == &"character_event"
		and _valid_segment(event_value["event_id"])
		and _valid_segment(event_value["character_id"])
		and typeof(event_value["runtime_frame"]) == TYPE_INT
		and int(event_value["runtime_frame"]) >= 0
		and typeof(event_value["token"]) == TYPE_INT
		and int(event_value["token"]) >= 0
		and typeof(event_value["generation"]) == TYPE_INT
		and int(event_value["generation"]) > 0
		and event_value["context"] is Dictionary
		and _event_context_is_supported(event_value["context"] as Dictionary)
	)


static func world_payload_descriptor(
	run_id: StringName,
	owner_character_generation: int,
	payload_family: StringName,
	source_token: int,
	payload_generation: int,
	handler_id: StringName,
	transform: Transform2D,
	geometry: Dictionary,
	remaining_frames: int,
	claims: Array,
	tags: Array,
	parameters: Dictionary
) -> Dictionary:
	var canonical_claims := _canonical_string_set(claims, true)
	var canonical_tags := _canonical_string_set(tags, false)
	if (
		(canonical_claims.is_empty() and not claims.is_empty())
		or (canonical_tags.is_empty() and not tags.is_empty())
	):
		return {}
	var value := {
		"payload_id": _stable_payload_id(
			run_id,
			owner_character_generation,
			payload_family,
			source_token,
			payload_generation
		),
		"handler_id": handler_id,
		"run_id": run_id,
		"owner_character_generation": owner_character_generation,
		"payload_family": payload_family,
		"source_token": source_token,
		"payload_generation": payload_generation,
		"transform": transform,
		"geometry": geometry.duplicate(true),
		"remaining_frames": remaining_frames,
		"claims": canonical_claims,
		"tags": canonical_tags,
		"parameters": parameters.duplicate(true),
	}
	return value if is_world_payload_descriptor(value) else {}


static func is_world_payload_descriptor(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var descriptor := value as Dictionary
	if not _has_exact_fields(descriptor, WORLD_PAYLOAD_FIELDS):
		return false
	if (
		not _valid_segment(descriptor["handler_id"])
		or not _valid_segment(descriptor["run_id"])
		or not _valid_segment(descriptor["payload_family"])
		or typeof(descriptor["owner_character_generation"]) != TYPE_INT
		or int(descriptor["owner_character_generation"]) <= 0
		or typeof(descriptor["source_token"]) != TYPE_INT
		or int(descriptor["source_token"]) <= 0
		or typeof(descriptor["payload_generation"]) != TYPE_INT
		or int(descriptor["payload_generation"]) <= 0
		or typeof(descriptor["remaining_frames"]) != TYPE_INT
		or int(descriptor["remaining_frames"]) <= 0
		or typeof(descriptor["transform"]) != TYPE_TRANSFORM2D
		or not _finite_transform(descriptor["transform"] as Transform2D)
		or not descriptor["geometry"] is Dictionary
		or (descriptor["geometry"] as Dictionary).is_empty()
		or not descriptor["parameters"] is Dictionary
		or not ReplaySafeValueScript.is_supported(descriptor["geometry"])
		or not ReplaySafeValueScript.is_supported(descriptor["parameters"])
	):
		return false
	var claims := _canonical_string_set(descriptor["claims"], true)
	var tags := _canonical_string_set(descriptor["tags"], false)
	if (
		(claims.is_empty() and (not descriptor["claims"] is Array or not (descriptor["claims"] as Array).is_empty()))
		or (tags.is_empty() and (not descriptor["tags"] is Array or not (descriptor["tags"] as Array).is_empty()))
		or claims != descriptor["claims"]
		or tags != descriptor["tags"]
	):
		return false
	var expected_id := _stable_payload_id(
		StringName(descriptor["run_id"]),
		int(descriptor["owner_character_generation"]),
		StringName(descriptor["payload_family"]),
		int(descriptor["source_token"]),
		int(descriptor["payload_generation"])
	)
	return (
		typeof(descriptor["payload_id"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(descriptor["payload_id"]) == expected_id
	)


static func _canonical_string_set(value: Variant, allow_colon: bool) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for entry: Variant in value as Array:
		if typeof(entry) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return []
		var text := str(entry)
		if (
			text.is_empty()
			or text != text.strip_edges()
			or text.contains("\n")
			or text.contains("\r")
			or text.contains("\t")
			or (not allow_colon and text.contains(":"))
			or result.has(text)
		):
			return []
		result.append(text)
	result.sort()
	return result


static func _event_context_is_supported(value: Dictionary) -> bool:
	if not value.has("descriptor"):
		return ReplaySafeValueScript.is_supported(value)
	if not is_world_payload_descriptor(value["descriptor"]):
		return false
	var remaining := value.duplicate(true)
	remaining.erase("descriptor")
	return ReplaySafeValueScript.is_supported(remaining)


static func _stable_payload_id(
	run_id: StringName,
	owner_character_generation: int,
	payload_family: StringName,
	source_token: int,
	payload_generation: int
) -> String:
	if (
		not _valid_segment(run_id)
		or not _valid_segment(payload_family)
		or owner_character_generation <= 0
		or source_token <= 0
		or payload_generation <= 0
	):
		return ""
	return "%s:%d:%s:%d:%d" % [
		str(run_id),
		owner_character_generation,
		str(payload_family),
		source_token,
		payload_generation,
	]


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	if (
		text.is_empty()
		or text != text.strip_edges()
		or text.length() > MAX_SEGMENT_LENGTH
		or text.contains(":")
	):
		return false
	for character: String in text:
		var code := character.unicode_at(0)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or character in ["_", "-", "."]
		):
			return false
	return true


static func _finite_transform(value: Transform2D) -> bool:
	return (
		is_finite(value.x.x)
		and is_finite(value.x.y)
		and is_finite(value.y.x)
		and is_finite(value.y.y)
		and is_finite(value.origin.x)
		and is_finite(value.origin.y)
	)


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not fields.has(str(key)):
			return false
	return true
