class_name RoomInteractionViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const SCHEMA_VERSION := 1
const FIELDS := ["schema_version", "revision", "run_id", "room_type", "node_id", "name_key", "description_key", "choices"]
const CHOICE_FIELDS := ["id", "label_key", "description_key", "available", "disabled_reason_key"]
const CHOICES := {"treasure": ["claim", "leave"], "rest": ["heal", "upgrade", "leave"]}


static func validate(value: Variant):
	if not Rules.header(value, FIELDS):
		return Rules.reject(value, "root")
	var state := value as Dictionary
	if not CHOICES.has(state["room_type"]) or not Rules.identifier(state["node_id"]) or not Rules.key(state["name_key"]) or not Rules.key(state["description_key"]) or not state["choices"] is Array or state["choices"].is_empty():
		return Rules.reject(value, "room")
	var ids: Dictionary = {}
	for choice_value: Variant in state["choices"]:
		if not Rules.exact(choice_value, CHOICE_FIELDS):
			return Rules.reject(value, "choices")
		var choice := choice_value as Dictionary
		if not CHOICES[state["room_type"]].has(choice["id"]) or ids.has(choice["id"]) or not Rules.key(choice["label_key"]) or not Rules.key(choice["description_key"]) or not Rules.availability(choice):
			return Rules.reject(value, "choices.identity")
		ids[choice["id"]] = true
	return Rules.accept(state)


static func copy_of(value: Dictionary) -> Dictionary:
	return value.duplicate(true) if validate(value).ok else {}
