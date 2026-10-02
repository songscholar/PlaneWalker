class_name RunDirector
extends Node

const RoomTemplateDefinitionScript := preload(
	"res://scripts/dungeon/room_template_definition.gd"
)

const ROOM_TYPE_COMBAT := "combat"
const ROOM_TYPE_EVENT := "event"
const ROOM_TYPE_ELITE := "elite"
const ROOM_TYPE_BOSS := "boss"
const ROOM_TYPE_TREASURE := "treasure"
const ROOM_TYPE_SHOP := "shop"
const ROOM_TYPE_REST := "rest"

var room_sequence: Array[Dictionary] = [
	{"scene": "res://scenes/rooms/combat_room_01.tscn", "type": ROOM_TYPE_COMBAT},
]
var current_room_index: int = 0
var _launch_nodes_by_id: Dictionary = {}


func configure_from_definitions(definitions: Array[Dictionary]) -> void:
	room_sequence = definitions.duplicate(true)
	current_room_index = 0
	_launch_nodes_by_id.clear()


func configure_launch_plan(plan: Dictionary, registry: RefCounted) -> bool:
	room_sequence.clear()
	_launch_nodes_by_id.clear()
	current_room_index = 0
	if registry == null or not registry.has_method("resolve_room_template"):
		return false
	var floor_id := str(plan.get("floor_id", ""))
	var floor_index := int(plan.get("floor_index", -1))
	if floor_id.is_empty() or floor_index < 0 or not plan.get("nodes", []) is Array:
		return false
	for node_value: Variant in plan.get("nodes", []):
		if not node_value is Dictionary:
			return false
		var node: Dictionary = node_value
		var node_id := str(node.get("id", ""))
		if node_id == str(plan.get("entry_node_id", "entry")):
			continue
		var template_id := str(node.get("template_id", ""))
		var template_value: Variant = registry.call(
			"resolve_room_template", StringName(template_id)
		)
		if not template_value is Dictionary or (template_value as Dictionary).is_empty():
			room_sequence.clear()
			_launch_nodes_by_id.clear()
			return false
		var parser_source: Dictionary = {}
		for field: String in RoomTemplateDefinitionScript.ROOT_FIELDS:
			if not (template_value as Dictionary).has(field):
				continue
			var value: Variant = (template_value as Dictionary)[field]
			parser_source[field] = (
				value.duplicate(true) if value is Array or value is Dictionary else value
			)
		var template_result: Dictionary = RoomTemplateDefinitionScript.new().configure(
			parser_source
		)
		if not bool(template_result.get("ok", false)):
			room_sequence.clear()
			_launch_nodes_by_id.clear()
			return false
		var template: Dictionary = (
			template_result.get("definition", {}) as Dictionary
		).duplicate(true)
		var definition := {
			"id": node_id,
			"node_id": node_id,
			"floor_id": floor_id,
			"floor_index": floor_index,
			"room_number": int(node.get("layer", 0)),
			"type": str(node.get("room_type", "")),
			"room_type": str(node.get("room_type", "")),
			"template_id": template_id,
			"scene": str(template.get("scene_path", "")),
			"scene_path": str(template.get("scene_path", "")),
			"encounter_id": str(node.get("encounter_id", "")),
			"event_id": str(node.get("event_id", "")),
			"merchant_id": str(node.get("merchant_id", "")),
			"reward_policy_id": str(node.get("reward_policy_id", "")),
			"runtime_mode": "launch",
			"template": template.duplicate(true),
		}
		_launch_nodes_by_id[node_id] = definition.duplicate(true)
		room_sequence.append(definition)
	room_sequence.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left["room_number"]) != int(right["room_number"]):
				return int(left["room_number"]) < int(right["room_number"])
			return str(left["node_id"]) < str(right["node_id"])
	)
	return not room_sequence.is_empty()


func room_definition_for_node(node_id: StringName) -> Dictionary:
	return (_launch_nodes_by_id.get(str(node_id), {}) as Dictionary).duplicate(true)


func overlay_event_assignment(node_id: StringName, event_id: StringName) -> bool:
	var node_key := str(node_id)
	var selected_event_id := str(event_id)
	if node_key.is_empty() or selected_event_id.is_empty():
		return false
	var existing_value: Variant = _launch_nodes_by_id.get(node_key, {})
	if not existing_value is Dictionary or (existing_value as Dictionary).is_empty():
		return false
	var existing := existing_value as Dictionary
	if str(existing.get("room_type", existing.get("type", ""))) != ROOM_TYPE_EVENT:
		return false
	var sequence_index := -1
	for index: int in range(room_sequence.size()):
		if str(room_sequence[index].get("node_id", "")) != node_key:
			continue
		if sequence_index >= 0:
			return false
		sequence_index = index
	if sequence_index < 0:
		return false
	var overlaid := existing.duplicate(true)
	overlaid["event_id"] = selected_event_id
	_launch_nodes_by_id[node_key] = overlaid.duplicate(true)
	room_sequence[sequence_index] = overlaid.duplicate(true)
	return true


func configure_fixed_sequence(
	room_count: int,
	event_rooms: Array[int] = [],
	elite_rooms: Array[int] = [],
	curse_rooms: Array[int] = []
) -> void:
	room_sequence.clear()
	var total_rooms := maxi(1, room_count)
	for room_number: int in range(1, total_rooms + 1):
		var room_type := ROOM_TYPE_COMBAT
		if room_number == total_rooms:
			room_type = ROOM_TYPE_BOSS
		elif event_rooms.has(room_number):
			room_type = ROOM_TYPE_EVENT
		elif elite_rooms.has(room_number):
			room_type = ROOM_TYPE_ELITE
		room_sequence.append({
			"scene": "res://scenes/rooms/combat_room_01.tscn",
			"type": room_type,
			"room_number": room_number,
			"offer_curse": curse_rooms.has(room_number),
		})
	current_room_index = 0


func current_room_path() -> String:
	if room_sequence.is_empty():
		return ""
	return str(room_sequence[current_room_index].get("scene", ""))


func room_type_for(room_number: int) -> String:
	var definition := room_definition_for(room_number)
	return str(definition.get("type", ROOM_TYPE_COMBAT))


func should_offer_curse(room_number: int) -> bool:
	return bool(room_definition_for(room_number).get("offer_curse", false))


func encounter_id_for(room_number: int) -> String:
	return str(room_definition_for(room_number).get("encounter_id", ""))


func room_count() -> int:
	return room_sequence.size()


func spawn_count_for(room_number: int, spawn_point_count: int, enemy_scene_count: int) -> int:
	if room_type_for(room_number) == ROOM_TYPE_EVENT:
		return 0
	if room_type_for(room_number) == ROOM_TYPE_BOSS:
		return 1
	return mini(mini(spawn_point_count, enemy_scene_count), maxi(1, room_number))


func room_definition_for(room_number: int) -> Dictionary:
	if room_sequence.is_empty():
		configure_fixed_sequence(maxi(1, room_number))
	var index := clampi(room_number - 1, 0, room_sequence.size() - 1)
	current_room_index = index
	return room_sequence[index].duplicate(true)
