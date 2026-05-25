class_name RunBuildState
extends RefCounted

var items: Array[String] = []
var blessings: Array[String] = []
var curses: Array[String] = []
var talents: Array[String] = []
var reward_history: Array[Dictionary] = []
var archetypes: Dictionary = {}
var dominant_archetype: String = ""


func reset() -> void:
	items.clear()
	blessings.clear()
	curses.clear()
	talents.clear()
	reward_history.clear()
	archetypes.clear()
	dominant_archetype = ""


func record_item(reward_data: Dictionary) -> void:
	_record_reward_id(items, reward_data)
	_record_reward(reward_data)


func record_blessing(blessing_data: Dictionary) -> void:
	_record_reward_id(blessings, blessing_data)
	_record_reward(blessing_data)


func record_curse(curse_data: Dictionary) -> void:
	_record_reward_id(curses, curse_data)
	_record_reward(curse_data, false)


func record_talent(talent_data: Dictionary) -> void:
	_record_reward_id(talents, talent_data)
	_record_reward(talent_data)


func selected_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.append_array(items)
	ids.append_array(blessings)
	ids.append_array(curses)
	ids.append_array(talents)
	return ids


func to_dictionary() -> Dictionary:
	return {
		"items": items.duplicate(),
		"blessings": blessings.duplicate(),
		"curses": curses.duplicate(),
		"talents": talents.duplicate(),
		"reward_history": reward_history.duplicate(true),
		"archetypes": archetypes.duplicate(true),
		"dominant_archetype": dominant_archetype,
	}


static func from_run(run_data: Dictionary) -> RefCounted:
	var state = load("res://scripts/progression/run_build_state.gd").new()
	for reward: Dictionary in run_data.get("rewards", []):
		state.record_item(reward)
	for blessing: Dictionary in run_data.get("blessings", []):
		state.record_blessing(blessing)
	for curse: Dictionary in run_data.get("curses", []):
		state.record_curse(curse)
	for talent: Dictionary in run_data.get("talent_choices", []):
		state.record_talent(talent)
	return state


func _record_reward_id(target: Array[String], reward_data: Dictionary) -> void:
	var reward_id := str(reward_data.get("id", ""))
	if reward_id.is_empty() or target.has(reward_id):
		return
	target.append(reward_id)


func _record_reward(reward_data: Dictionary, count_archetype: bool = true) -> void:
	reward_history.append(reward_data.duplicate(true))
	if count_archetype:
		_record_archetype(reward_data)


func _record_archetype(reward_data: Dictionary) -> void:
	var archetype := str(reward_data.get("archetype", ""))
	if archetype.is_empty():
		return
	archetypes[archetype] = int(archetypes.get(archetype, 0)) + 1
	dominant_archetype = _find_dominant_archetype()


func _find_dominant_archetype() -> String:
	var best_id := ""
	var best_count := -1
	for archetype: String in archetypes.keys():
		var count := int(archetypes[archetype])
		if count > best_count:
			best_id = archetype
			best_count = count
	return best_id
