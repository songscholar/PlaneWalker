extends RefCounted

const Replay := preload("res://scripts/replay/replay_recorder.gd")

var _events: Array[Dictionary] = []
var _digests: Array[String] = []
var _prefix: Dictionary = {}
var _eligible := false
var _certifications := 0
var _root_builds := 0


func refresh(events: Array[Dictionary]) -> Dictionary:
	if _same_refs(events):
		_eligible = true
		return _prefix.duplicate()
	_eligible = false
	if events.is_read_only():
		return {}
	var candidate_events: Array[Dictionary] = []
	var candidate_digests: Array[String] = []
	var certifications := 0
	for index: int in range(events.size()):
		var event := events[index]
		if index < _events.size() and is_same(event, _events[index]):
			candidate_events.append(event)
			candidate_digests.append(_digests[index])
			continue
		var owned := event.duplicate(true)
		if not Replay.replay_value_is_safe(owned) or _has_packed_descendant(owned):
			return {}
		var digest := Replay.capture_event_digest(owned)
		if digest.is_empty():
			return {}
		_freeze(owned)
		candidate_events.append(owned)
		candidate_digests.append(digest)
		certifications += 1
	var indices: Array[int] = []
	var capture_sequences: Dictionary = {}
	for index: int in range(candidate_events.size()):
		indices.append(index)
		var capture_sequence := int(candidate_events[index].capture_sequence)
		if capture_sequences.has(capture_sequence):
			return {}
		capture_sequences[capture_sequence] = true
	indices.sort_custom(func(left: int, right: int) -> bool:
		return int(candidate_events[left].capture_sequence) < int(candidate_events[right].capture_sequence)
	)
	var count := 0
	while capture_sequences.has(count + 1):
		count += 1
	var prefix_digests: Array[String] = []
	for index: int in range(count):
		if int(candidate_events[indices[index]].capture_sequence) != index + 1:
			return {}
		prefix_digests.append(candidate_digests[indices[index]])
	var root := Replay.value_digest({"schema_id": Replay.EVENT_PREFIX_SCHEMA_ID, "schema_version": Replay.EVENT_PREFIX_SCHEMA_VERSION, "event_count": count, "capture_event_digests": prefix_digests})
	if root.is_empty():
		return {}
	# Publish only after all slots and the complete prefix have authenticated.
	for index: int in range(events.size()):
		events[index] = candidate_events[index]
	_events = candidate_events
	_digests = candidate_digests
	_prefix = {"event_prefix_count": count, "event_prefix_root": root}
	_eligible = true
	_certifications += certifications
	_root_builds += 1
	return _prefix.duplicate()


func certifies(events: Array[Dictionary]) -> bool:
	return _eligible and _same_refs(events)


func snapshot() -> Dictionary:
	return {"retained_events": _events.size(), "certifications": _certifications, "root_builds": _root_builds, "eligible": _eligible}


func _same_refs(events: Array[Dictionary]) -> bool:
	if _prefix.is_empty() or events.size() != _events.size():
		return false
	for index: int in range(events.size()):
		if not is_same(events[index], _events[index]):
			return false
	return true


static func _has_packed_descendant(value: Variant) -> bool:
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return true
	if value is Dictionary:
		for child: Variant in value.values():
			if _has_packed_descendant(child):
				return true
	elif value is Array:
		for child: Variant in value:
			if _has_packed_descendant(child):
				return true
	return false


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value:
			_freeze(child)
		value.make_read_only()
