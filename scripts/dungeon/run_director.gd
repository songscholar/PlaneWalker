class_name RunDirector
extends Node

const ROOM_TYPE_COMBAT := "combat"
const ROOM_TYPE_EVENT := "event"
const ROOM_TYPE_ELITE := "elite"
const ROOM_TYPE_BOSS := "boss"

var room_sequence: Array[Dictionary] = [
	{"scene": "res://scenes/rooms/combat_room_01.tscn", "type": ROOM_TYPE_COMBAT},
]
var current_room_index: int = 0


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
	return room_sequence[index]
