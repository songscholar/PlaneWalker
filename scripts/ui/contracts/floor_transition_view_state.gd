class_name FloorTransitionViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const Floors := preload("res://scripts/dungeon/floor_definition.gd")
const SCHEMA_VERSION := 1
const FIELDS := ["schema_version", "revision", "run_id", "completed_floor_id", "completed_floor_index", "completed_name_key", "next_floor_id", "next_floor_index", "next_name_key", "gold", "available"]


static func validate(value: Variant):
	if not Rules.header(value, FIELDS):
		return Rules.reject(value, "root")
	var state := value as Dictionary
	if not Rules.integer(state["completed_floor_index"]) or not Rules.integer(state["next_floor_index"]) or not Rules.integer(state["gold"]) or int(state["gold"]) < 0 or typeof(state["available"]) != TYPE_BOOL:
		return Rules.reject(value, "floor")
	var completed_index := int(state["completed_floor_index"])
	var next_index := int(state["next_floor_index"])
	if completed_index < 0 or completed_index >= 4 or next_index != completed_index + 1 or state["completed_floor_id"] != Floors.FLOOR_IDS[completed_index] or state["next_floor_id"] != Floors.FLOOR_IDS[next_index] or not Rules.key(state["completed_name_key"]) or not Rules.key(state["next_name_key"]):
		return Rules.reject(value, "floor.order")
	return Rules.accept(state)


static func copy_of(value: Dictionary) -> Dictionary:
	return value.duplicate(true) if validate(value).ok else {}
