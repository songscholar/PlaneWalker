class_name EventModifierLifetime
extends RefCounted

const FloorsScript := preload("res://scripts/dungeon/floor_definition.gd")
const EventsScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const FACT_TYPE := "room_completed_v1"
const FACT_FIELDS := ["type", "sequence", "floor_id", "floor_index", "node_id"]
const BASELINE_TYPE := "modifier_lifetime_baseline_v1"
const BASELINE_FIELDS := ["type", "source_transaction_id", "after_room_sequence"]
const MODIFIER_FIELDS := ["modifier_id", "duration_rooms", "magnitude", "source_transaction_id"]
const COMMITTED_PHASES := ["resolved", "dismissed", "pending_reward", "pending_encounter"]
const MAX_ROOM_FACTS := 256


static func append_completed_room(events: Array, floor_id: String, floor_index: int, node_id: String) -> Dictionary:
	var validation := validate_events(events)
	if not validation["ok"]:
		return validation
	if not _valid_floor(floor_id, floor_index) or not _valid_node(node_id):
		return _failure(&"INVALID_ARGUMENT")
	var facts: Array = validation["context"]["room_facts"]
	for fact: Dictionary in facts:
		if fact["floor_id"] == floor_id and fact["node_id"] == node_id:
			return _failure(&"ALREADY_COMPLETED")
	if facts.size() >= MAX_ROOM_FACTS or (not facts.is_empty() and floor_index < int(facts[-1]["floor_index"])):
		return _failure(&"INVALID_ROOM_SEQUENCE")
	var fact := {"type": FACT_TYPE, "sequence": facts.size() + 1, "floor_id": floor_id, "floor_index": floor_index, "node_id": node_id}
	var updated := events.duplicate(true)
	updated.append(fact)
	return _success({"events": updated, "fact": fact.duplicate(true)})


static func validate_events(events: Array) -> Dictionary:
	var facts: Array[Dictionary] = []
	var room_keys: Dictionary = {}
	var baselines: Dictionary = {}
	var last_floor_index := -1
	for value: Variant in events:
		if _is_baseline_candidate(value):
			if not _exact(value, BASELINE_FIELDS):
				return _failure(&"INVALID_MODIFIER_BASELINE")
			var baseline := value as Dictionary
			if typeof(baseline["type"]) != TYPE_STRING or baseline["type"] != BASELINE_TYPE or typeof(baseline["source_transaction_id"]) != TYPE_STRING or not _valid_source(baseline["source_transaction_id"]):
				return _failure(&"INVALID_MODIFIER_BASELINE")
			if typeof(baseline["after_room_sequence"]) != TYPE_INT or int(baseline["after_room_sequence"]) != facts.size() or baselines.has(baseline["source_transaction_id"]) or baselines.size() >= MAX_ROOM_FACTS:
				return _failure(&"INVALID_MODIFIER_BASELINE")
			baselines[baseline["source_transaction_id"]] = int(baseline["after_room_sequence"])
			continue
		if not _is_room_fact_candidate(value):
			continue
		if not value is Dictionary or not _exact(value, FACT_FIELDS):
			return _failure(&"INVALID_ROOM_FACT")
		var fact := value as Dictionary
		if typeof(fact["type"]) != TYPE_STRING or fact["type"] != FACT_TYPE or typeof(fact["sequence"]) != TYPE_INT or int(fact["sequence"]) != facts.size() + 1:
			return _failure(&"INVALID_ROOM_SEQUENCE")
		if typeof(fact["floor_id"]) != TYPE_STRING or typeof(fact["floor_index"]) != TYPE_INT or not _valid_floor(fact["floor_id"], int(fact["floor_index"])):
			return _failure(&"INVALID_ROOM_FLOOR")
		if typeof(fact["node_id"]) != TYPE_STRING or not _valid_node(fact["node_id"]):
			return _failure(&"INVALID_ROOM_ID")
		var floor_index := int(fact["floor_index"])
		var room_key := "%s:%s" % [fact["floor_id"], fact["node_id"]]
		if facts.size() >= MAX_ROOM_FACTS or floor_index < last_floor_index or room_keys.has(room_key):
			return _failure(&"INVALID_ROOM_SEQUENCE")
		last_floor_index = floor_index
		room_keys[room_key] = true
		facts.append(fact.duplicate(true))
	return _success({"room_facts": facts, "modifier_baselines": baselines})


static func history_matches_plan(events: Array, plan: Dictionary) -> bool:
	var validation := validate_events(events)
	if not bool(validation.get("ok", false)):
		return false
	var facts: Array = validation["context"]["room_facts"]
	if plan.is_empty():
		return facts.is_empty()
	if not plan.get("nodes") is Array or not plan.get("visited_node_ids") is Array:
		return false
	var current_floor_index := int(plan.get("floor_index", -1))
	var last_route_index := -1
	for fact: Dictionary in facts:
		if int(fact["floor_index"]) > current_floor_index:
			return false
		if int(fact["floor_index"]) < current_floor_index:
			continue
		if fact["floor_id"] != plan.get("floor_id", ""):
			return false
		var route_index := (plan["visited_node_ids"] as Array).find(fact["node_id"])
		if route_index <= last_route_index:
			return false
		var matched := false
		for node_value: Variant in plan["nodes"]:
			if node_value is Dictionary and node_value.get("id") == fact["node_id"]:
				matched = bool(node_value.get("visited", false)) and bool(node_value.get("cleared", false))
				break
		if not matched:
			return false
		last_route_index = route_index
	return true


static func normalize_legacy_baselines(events: Array, assignments: Dictionary, modifiers: Array) -> Dictionary:
	var validation := validate_events(events)
	if not validation["ok"]:
		return validation
	var facts: Array = validation["context"]["room_facts"]
	var baselines: Dictionary = validation["context"]["modifier_baselines"]
	var updated := events.duplicate(true)
	for value: Variant in modifiers:
		if not value is Dictionary or typeof(value.get("source_transaction_id")) != TYPE_STRING:
			return _failure(&"INVALID_MODIFIER")
		var source: String = value["source_transaction_id"]
		var assignment := _source_assignment(assignments, source)
		if assignment.is_empty():
			return _failure(&"INVALID_MODIFIER_SOURCE")
		if assignment["phase"] != "dismissed" or baselines.has(source) or _source_room_index(facts, assignment) >= 0:
			continue
		# Older saves cannot reconstruct elapsed rooms; the retained baseline bounds future life.
		updated.append({"type": BASELINE_TYPE, "source_transaction_id": source, "after_room_sequence": facts.size()})
		baselines[source] = facts.size()
	var projected := active_projection(updated, assignments, modifiers)
	if not projected["ok"]:
		return projected
	return _success({"events": updated})


static func active_projection(events: Array, assignments: Dictionary, modifiers: Array) -> Dictionary:
	var validation := validate_events(events)
	if not validation["ok"]:
		return validation
	if modifiers.size() > EventsScript.MODIFIER_IDS.size():
		return _failure(&"INVALID_MODIFIER")
	var facts: Array = validation["context"]["room_facts"]
	var baselines: Dictionary = validation["context"]["modifier_baselines"]
	for source: String in baselines:
		var assignment := _source_assignment(assignments, source)
		if assignment.is_empty() or assignment["phase"] != "dismissed":
			return _failure(&"INVALID_MODIFIER_BASELINE_SOURCE")
	var projected: Array[Dictionary] = []
	var ids: Dictionary = {}
	var sources: Dictionary = {}
	for value: Variant in modifiers:
		if not value is Dictionary or not _exact(value, MODIFIER_FIELDS):
			return _failure(&"INVALID_MODIFIER")
		var modifier := value as Dictionary
		if typeof(modifier["modifier_id"]) != TYPE_STRING or not EventsScript.MODIFIER_IDS.has(modifier["modifier_id"]):
			return _failure(&"INVALID_MODIFIER")
		if typeof(modifier["duration_rooms"]) != TYPE_INT or int(modifier["duration_rooms"]) < 1 or int(modifier["duration_rooms"]) > 5:
			return _failure(&"INVALID_MODIFIER_DURATION")
		if typeof(modifier["magnitude"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(modifier["magnitude"])) or float(modifier["magnitude"]) <= 0.0 or float(modifier["magnitude"]) > 10.0:
			return _failure(&"INVALID_MODIFIER_MAGNITUDE")
		if typeof(modifier["source_transaction_id"]) != TYPE_STRING or not _valid_source(modifier["source_transaction_id"]):
			return _failure(&"INVALID_MODIFIER_SOURCE")
		var source: String = modifier["source_transaction_id"]
		if ids.has(modifier["modifier_id"]) or sources.has(source):
			return _failure(&"DUPLICATE_MODIFIER_SOURCE")
		ids[modifier["modifier_id"]] = true
		sources[source] = true
		var assignment := _source_assignment(assignments, source)
		if assignment.is_empty():
			return _failure(&"INVALID_MODIFIER_SOURCE")
		var source_index := _source_room_index(facts, assignment)
		# The granting room is excluded; only subsequent successful clears consume duration.
		var elapsed := 0
		if source_index >= 0:
			elapsed = facts.size() - source_index - 1
		elif baselines.has(source):
			elapsed = facts.size() - int(baselines[source])
		if elapsed < int(modifier["duration_rooms"]):
			projected.append({"modifier_id": modifier["modifier_id"], "magnitude": float(modifier["magnitude"]), "source_transaction_id": source})
	projected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["modifier_id"] < b["modifier_id"])
	return _success({"modifiers": projected})


static func _source_room_index(facts: Array, assignment: Dictionary) -> int:
	for index: int in range(facts.size()):
		if facts[index]["floor_id"] == assignment["floor_id"] and facts[index]["node_id"] == assignment["node_id"]:
			return index
	return -1


static func _source_assignment(assignments: Dictionary, source: String) -> Dictionary:
	var found: Dictionary = {}
	for key: Variant in assignments:
		var value: Variant = assignments[key]
		if not value is Dictionary or value.get("transaction_id") != source:
			continue
		if not found.is_empty() or typeof(key) != TYPE_STRING:
			return {}
		if typeof(value.get("floor_id")) != TYPE_STRING or typeof(value.get("floor_index")) != TYPE_INT or not _valid_floor(value["floor_id"], int(value["floor_index"])):
			return {}
		if typeof(value.get("node_id")) != TYPE_STRING or not _valid_node(value["node_id"]) or key != "%s:%s" % [value["floor_id"], value["node_id"]] or value.get("phase") not in COMMITTED_PHASES:
			return {}
		found = value.duplicate(true)
	return found


static func _is_room_fact_candidate(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	return str(value.get("type", "")).begins_with("room_completed") or (value.has("sequence") and value.has("floor_index") and value.has("node_id"))


static func _is_baseline_candidate(value: Variant) -> bool:
	return value is Dictionary and (str(value.get("type", "")).begins_with("modifier_lifetime_baseline") or (value.has("source_transaction_id") and value.has("after_room_sequence")))


static func _valid_floor(floor_id: String, floor_index: int) -> bool:
	return floor_index >= 0 and floor_index < FloorsScript.FLOOR_IDS.size() and FloorsScript.FLOOR_IDS[floor_index] == floor_id


static func _valid_node(value: String) -> bool:
	var regex := RegEx.new()
	return value != "entry" and regex.compile("^[a-z0-9][a-z0-9_-]{0,63}$") == OK and regex.search(value) != null


static func _valid_source(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.:-]{0,95}$") == OK and regex.search(value) != null


static func _exact(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
