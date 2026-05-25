class_name RunDirector
extends Node

var room_sequence: Array[String] = [
	"res://scenes/rooms/combat_room_01.tscn",
]
var current_room_index: int = 0


func current_room_path() -> String:
	if room_sequence.is_empty():
		return ""
	return room_sequence[current_room_index]
