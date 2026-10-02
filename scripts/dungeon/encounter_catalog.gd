class_name EncounterCatalog
extends RefCounted

const ValidationReportScript := preload("res://scripts/content/content_validation_report.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")

const DEFAULT_PATH := "res://data/encounters/m1_encounters.json"
const AUTHORITATIVE_ROOM_SCENE := "res://scenes/rooms/combat_room_01.tscn"
const EXPECTED_ROOM_TYPES: Array[String] = ["combat", "combat", "combat", "elite", "boss"]

var _plan_id: String = ""
var _mechanism_ids: Dictionary = {}
var _enemy_definitions: Dictionary = {}
var _spawn_slots: Dictionary = {}
var _rooms: Array[Dictionary] = []
var _encounters: Dictionary = {}


func load_path(path: String = DEFAULT_PATH):
	var report = ValidationReportScript.new()
	if not FileAccess.file_exists(path):
		report.add_error("Encounter catalog file does not exist", {"path": path}, true)
		_clear()
		return report
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report.add_error("Encounter catalog could not be opened", {"path": path}, true)
		_clear()
		return report
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		report.add_error(
			"Encounter catalog contains invalid JSON",
			{"path": path, "line": json.get_error_line(), "message": json.get_error_message()},
			true
		)
		_clear()
		return report
	return load_data(json.data, path)


func load_data(value: Variant, source: String = "<memory>"):
	_clear()
	var report = ValidationReportScript.new()
	if typeof(value) != TYPE_DICTIONARY:
		report.add_error("Encounter catalog root must be a dictionary", {"source": source}, true)
		return report
	var data: Dictionary = value
	if not _is_schema_version_one(data.get("schema_version")):
		report.add_error("Unsupported encounter catalog schema", {"source": source}, true)
	if not _is_non_empty_string(data.get("plan_id")):
		report.add_error("Encounter plan id is invalid", {"source": source}, true)

	var mechanism_values: Variant = data.get("mechanism_ids")
	if typeof(mechanism_values) != TYPE_ARRAY:
		report.add_error("Encounter mechanism ids must be an array", {"source": source}, true)
	else:
		_collect_unique_strings(mechanism_values, _mechanism_ids, "mechanism", source, report)

	_validate_enemy_definitions(data.get("enemy_definitions"), source, report)
	_validate_spawn_slots(data.get("spawn_slots"), source, report)
	_validate_encounters(data.get("encounters"), source, report)
	_validate_rooms(data.get("rooms"), source, report)
	_validate_m1_shape(source, report)

	if report.has_blocking_errors():
		_clear()
		return report
	_plan_id = str(data["plan_id"])
	report.loaded_count = _rooms.size()
	return report


func plan_id() -> String:
	return _plan_id


func room_definitions(run_seed: int = 0) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for room: Dictionary in _rooms:
		var copy := room.duplicate(true)
		var encounter_id := str(copy.get("encounter_id", ""))
		var encounter: Dictionary = encounter_definition(encounter_id, run_seed, int(copy.get("room_number", 0)))
		copy["plan_id"] = _plan_id
		copy["target_seconds_min"] = int(encounter.get("target_seconds_min", 0))
		copy["target_seconds_max"] = int(encounter.get("target_seconds_max", 0))
		definitions.append(copy)
	return definitions


func encounter_definition(
	encounter_id: String,
	run_seed: int = 0,
	room_number: int = 0,
	room_type: String = ""
) -> Dictionary:
	var source_id := encounter_id
	if not _encounters.has(source_id):
		source_id = _launch_adapter_source(encounter_id, room_number, room_type)
	var source: Dictionary = _encounters.get(source_id, {})
	if source.is_empty():
		return {}
	var resolved := source.duplicate(true)
	resolved["id"] = encounter_id
	_resolve_choices(resolved, run_seed, room_number)
	return resolved


func _launch_adapter_source(encounter_id: String, room_number: int, room_type: String) -> String:
	# P14 keeps the authored M1 behaviors behind the closed Launch references
	# until P15 supplies their enemy and Boss implementations.
	var source_type := ""
	if encounter_id in FloorDefinitionScript.ENCOUNTER_PROFILE_IDS:
		source_type = "combat" if room_type.is_empty() else room_type
		if source_type not in ["combat", "elite"]:
			return ""
	elif encounter_id in FloorDefinitionScript.BOSS_ENCOUNTER_IDS:
		if room_type not in ["", "boss"]:
			return ""
		source_type = "boss"
	else:
		return ""
	var candidates: Array[String] = []
	for room: Dictionary in _rooms:
		if str(room.get("type", "")) == source_type:
			candidates.append(str(room.get("encounter_id", "")))
	if candidates.is_empty():
		return ""
	return candidates[posmod(maxi(1, room_number) - 1, candidates.size())]


func enemy_definition(enemy_id: String) -> Dictionary:
	var definition: Dictionary = _enemy_definitions.get(enemy_id, {})
	return definition.duplicate(true)


func spawn_slot(spawn_slot_id: String) -> Dictionary:
	var definition: Dictionary = _spawn_slots.get(spawn_slot_id, {})
	return definition.duplicate(true)


func _validate_enemy_definitions(value: Variant, source: String, report) -> void:
	if typeof(value) != TYPE_ARRAY:
		report.add_error("Enemy definitions must be an array", {"source": source}, true)
		return
	for index: int in range(value.size()):
		var entry_value: Variant = value[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			report.add_error("Enemy definition must be a dictionary", {"source": source, "index": index}, true)
			continue
		var entry: Dictionary = entry_value
		var enemy_id := str(entry.get("id", ""))
		var scene_path := str(entry.get("scene", ""))
		if enemy_id.is_empty() or _enemy_definitions.has(enemy_id):
			report.add_error("Enemy definition id is invalid or duplicated", {"source": source, "id": enemy_id}, true)
			continue
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			report.add_error("Enemy scene reference is invalid", {"source": source, "id": enemy_id, "scene": scene_path}, true)
			continue
		var scene_resource := ResourceLoader.load(scene_path)
		if not scene_resource is PackedScene:
			report.add_error("Enemy scene reference must be a PackedScene", {"source": source, "id": enemy_id, "scene": scene_path}, true)
			continue
		var scene_root := (scene_resource as PackedScene).instantiate()
		if not scene_root is Node2D:
			report.add_error("Enemy scene root must be a Node2D", {"source": source, "id": enemy_id, "scene": scene_path}, true)
			scene_root.free()
			continue
		scene_root.free()
		var allowed: Variant = entry.get("allowed_mechanism_ids", [])
		if typeof(allowed) != TYPE_ARRAY or not _string_array_is_valid(allowed):
			report.add_error("Enemy mechanism allowlist is invalid", {"source": source, "id": enemy_id}, true)
			continue
		for mechanism_value: Variant in allowed:
			if not _mechanism_ids.has(str(mechanism_value)):
				report.add_error("Enemy references an unknown mechanism", {"source": source, "id": enemy_id, "mechanism_id": mechanism_value}, true)
		_enemy_definitions[enemy_id] = entry.duplicate(true)


func _validate_spawn_slots(value: Variant, source: String, report) -> void:
	if typeof(value) != TYPE_ARRAY:
		report.add_error("Spawn slots must be an array", {"source": source}, true)
		return
	var room_scene_resource := ResourceLoader.load(AUTHORITATIVE_ROOM_SCENE)
	var room_root: Node
	if room_scene_resource is PackedScene:
		room_root = (room_scene_resource as PackedScene).instantiate()
	if not room_root is Node2D:
		report.add_error("Authoritative room scene must instantiate a Node2D", {"source": source, "scene": AUTHORITATIVE_ROOM_SCENE}, true)
		if room_root != null:
			room_root.free()
		room_root = null
	for index: int in range(value.size()):
		var entry_value: Variant = value[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			report.add_error("Spawn slot must be a dictionary", {"source": source, "index": index}, true)
			continue
		var entry: Dictionary = entry_value
		var slot_id := str(entry.get("id", ""))
		var node_path_value: Variant = entry.get("node_path")
		var node_path := str(node_path_value)
		if slot_id.is_empty() or _spawn_slots.has(slot_id) or typeof(node_path_value) != TYPE_STRING or node_path.is_empty():
			report.add_error("Spawn slot is invalid or duplicated", {"source": source, "id": slot_id}, true)
			continue
		if room_root == null or not room_root.get_node_or_null(NodePath(node_path)) is Node2D:
			report.add_error("Spawn slot does not exist in the authoritative room", {"source": source, "id": slot_id, "node_path": node_path}, true)
		_spawn_slots[slot_id] = entry.duplicate(true)
	if room_root != null:
		room_root.free()


func _validate_encounters(value: Variant, source: String, report) -> void:
	if typeof(value) != TYPE_ARRAY:
		report.add_error("Encounters must be an array", {"source": source}, true)
		return
	var spawn_ids: Dictionary = {}
	for index: int in range(value.size()):
		var entry_value: Variant = value[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			report.add_error("Encounter must be a dictionary", {"source": source, "index": index}, true)
			continue
		var encounter: Dictionary = entry_value
		var encounter_id := str(encounter.get("id", ""))
		if encounter_id.is_empty() or _encounters.has(encounter_id):
			report.add_error("Encounter id is invalid or duplicated", {"source": source, "id": encounter_id}, true)
			continue
		var target_min := float(encounter.get("target_seconds_min", -1.0))
		var target_max := float(encounter.get("target_seconds_max", -1.0))
		if not is_finite(target_min) or not is_finite(target_max) or target_min <= 0.0 or target_max < target_min:
			report.add_error("Encounter target duration is invalid", {"source": source, "id": encounter_id}, true)
		var waves: Variant = encounter.get("waves")
		if typeof(waves) != TYPE_ARRAY or waves.is_empty():
			report.add_error("Encounter waves must be a non-empty array", {"source": source, "id": encounter_id}, true)
			_encounters[encounter_id] = encounter.duplicate(true)
			continue
		var wave_ids: Dictionary = {}
		for wave_index: int in range(waves.size()):
			_validate_wave(waves[wave_index], encounter_id, wave_index, wave_ids, spawn_ids, source, report)
		_encounters[encounter_id] = encounter.duplicate(true)


func _validate_wave(
	value: Variant,
	encounter_id: String,
	wave_index: int,
	wave_ids: Dictionary,
	spawn_ids: Dictionary,
	source: String,
	report
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		report.add_error("Encounter wave must be a dictionary", {"source": source, "encounter_id": encounter_id, "wave_index": wave_index}, true)
		return
	var wave: Dictionary = value
	var wave_id := str(wave.get("id", ""))
	if wave_id.is_empty() or wave_ids.has(wave_id):
		report.add_error("Wave id is invalid or duplicated", {"source": source, "encounter_id": encounter_id, "id": wave_id}, true)
	else:
		wave_ids[wave_id] = true
	for duration_field: String in ["delay_seconds", "telegraph_seconds"]:
		var duration := float(wave.get(duration_field, -1.0))
		if not is_finite(duration) or duration < 0.0:
			report.add_error("Wave timing is invalid", {"source": source, "encounter_id": encounter_id, "field": duration_field}, true)
	var spawns: Variant = wave.get("spawns")
	if typeof(spawns) != TYPE_ARRAY or spawns.is_empty():
		report.add_error("Wave spawns must be a non-empty array", {"source": source, "encounter_id": encounter_id, "wave_id": wave_id}, true)
		return
	for spawn_index: int in range(spawns.size()):
		_validate_spawn(spawns[spawn_index], encounter_id, wave_id, spawn_index, spawn_ids, source, report)


func _validate_spawn(
	value: Variant,
	encounter_id: String,
	wave_id: String,
	spawn_index: int,
	spawn_ids: Dictionary,
	source: String,
	report
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		report.add_error("Wave spawn must be a dictionary", {"source": source, "encounter_id": encounter_id, "wave_id": wave_id, "spawn_index": spawn_index}, true)
		return
	var spawn: Dictionary = value
	var spawn_id := str(spawn.get("id", ""))
	var enemy_id := str(spawn.get("enemy_id", ""))
	var slot_id := str(spawn.get("spawn_slot_id", ""))
	if spawn_id.is_empty() or spawn_ids.has(spawn_id):
		report.add_error("Spawn id is invalid or duplicated", {"source": source, "id": spawn_id}, true)
	else:
		spawn_ids[spawn_id] = true
	if not _enemy_definitions.has(enemy_id):
		report.add_error("Spawn references an unknown enemy", {"source": source, "spawn_id": spawn_id, "enemy_id": enemy_id}, true)
	if not _spawn_slots.has(slot_id):
		report.add_error("Spawn references an unknown slot", {"source": source, "spawn_id": spawn_id, "spawn_slot_id": slot_id}, true)
	var enemy_choices := _validate_reference_choices(
		spawn,
		"enemy_choices",
		_enemy_definitions,
		"enemy",
		spawn_id,
		source,
		report
	)
	_validate_reference_choices(
		spawn,
		"spawn_slot_choices",
		_spawn_slots,
		"spawn slot",
		spawn_id,
		source,
		report
	)
	var mechanisms: Variant = spawn.get("mechanism_ids", [])
	if typeof(mechanisms) != TYPE_ARRAY or not _string_array_is_valid(mechanisms):
		report.add_error("Spawn mechanism ids are invalid", {"source": source, "spawn_id": spawn_id}, true)
		return
	var candidate_enemy_ids: Array = [enemy_id]
	for choice: Variant in enemy_choices:
		if not candidate_enemy_ids.has(str(choice)):
			candidate_enemy_ids.append(str(choice))
	for candidate_enemy_id: String in candidate_enemy_ids:
		_validate_enemy_mechanisms(candidate_enemy_id, mechanisms, spawn_id, source, report)


func _validate_reference_choices(
	spawn: Dictionary,
	field: String,
	references: Dictionary,
	label: String,
	spawn_id: String,
	source: String,
	report
) -> Array:
	if not spawn.has(field):
		return []
	var value: Variant = spawn[field]
	if typeof(value) != TYPE_ARRAY:
		report.add_error("Spawn %s choices must be an array" % label, {"source": source, "spawn_id": spawn_id, "field": field}, true)
		return []
	var choices: Array = value
	if choices.is_empty():
		report.add_error("Spawn %s choices must not be empty" % label, {"source": source, "spawn_id": spawn_id, "field": field}, true)
		return []
	if not _string_array_is_valid(choices):
		report.add_error("Spawn %s choices are invalid or duplicated" % label, {"source": source, "spawn_id": spawn_id, "field": field}, true)
	for choice: Variant in choices:
		if typeof(choice) == TYPE_STRING and not str(choice).is_empty() and not references.has(str(choice)):
			report.add_error("Spawn %s choice references an unknown id" % label, {"source": source, "spawn_id": spawn_id, "field": field, "id": choice}, true)
	return choices.duplicate()


func _validate_enemy_mechanisms(enemy_id: String, mechanisms: Array, spawn_id: String, source: String, report) -> void:
	var enemy_definition_value: Variant = _enemy_definitions.get(enemy_id, {})
	var allowed: Array = enemy_definition_value.get("allowed_mechanism_ids", []) if enemy_definition_value is Dictionary else []
	for mechanism_value: Variant in mechanisms:
		var mechanism_id := str(mechanism_value)
		if not _mechanism_ids.has(mechanism_id):
			report.add_error("Spawn references an unknown mechanism", {"source": source, "spawn_id": spawn_id, "mechanism_id": mechanism_id}, true)
		elif not allowed.has(mechanism_id):
			report.add_error("Enemy does not allow the spawn mechanism", {"source": source, "spawn_id": spawn_id, "enemy_id": enemy_id, "mechanism_id": mechanism_id}, true)


func _validate_rooms(value: Variant, source: String, report) -> void:
	if typeof(value) != TYPE_ARRAY:
		report.add_error("Room definitions must be an array", {"source": source}, true)
		return
	var room_numbers: Dictionary = {}
	var room_encounter_ids: Dictionary = {}
	for index: int in range(value.size()):
		var entry_value: Variant = value[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			report.add_error("Room definition must be a dictionary", {"source": source, "index": index}, true)
			continue
		var room: Dictionary = entry_value
		var room_number := int(room.get("room_number", 0))
		var room_type := str(room.get("type", ""))
		var reward_kind := str(room.get("reward_kind", ""))
		var encounter_id := str(room.get("encounter_id", ""))
		if room_number <= 0 or room_numbers.has(room_number):
			report.add_error("Room number is invalid or duplicated", {"source": source, "room_number": room_number}, true)
		else:
			room_numbers[room_number] = true
		if room_type not in ["combat", "elite", "boss"] or reward_kind.is_empty():
			report.add_error("Room type or reward is invalid", {"source": source, "room_number": room_number}, true)
		if encounter_id.is_empty() or room_encounter_ids.has(encounter_id):
			report.add_error("Room encounter id is invalid or duplicated", {"source": source, "room_number": room_number, "encounter_id": encounter_id}, true)
		else:
			room_encounter_ids[encounter_id] = true
		if not _encounters.has(encounter_id):
			report.add_error("Room references a missing encounter", {"source": source, "room_number": room_number, "encounter_id": encounter_id}, true)
		var normalized_room := room.duplicate(true)
		normalized_room["room_number"] = room_number
		_rooms.append(normalized_room)
	_rooms.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("room_number", 0)) < int(b.get("room_number", 0)))


func _validate_m1_shape(source: String, report) -> void:
	if _rooms.size() != 5 or _encounters.size() != 5:
		report.add_error("M1 catalog must contain exactly five rooms and encounters", {"source": source}, true)
		return
	for index: int in range(5):
		var room: Dictionary = _rooms[index]
		if int(room.get("room_number", 0)) != index + 1 or str(room.get("type", "")) != EXPECTED_ROOM_TYPES[index]:
			report.add_error("M1 room order or type is invalid", {"source": source, "room_number": index + 1}, true)
	var elite_room: Dictionary = _rooms[3]
	var elite_spawns := _spawns_for(str(elite_room.get("encounter_id", "")))
	if elite_spawns.size() != 1 or str(elite_spawns[0].get("enemy_id", "")) != "tank" or elite_spawns[0].get("mechanism_ids", []) != ["overload_pulse"]:
		report.add_error("M1 room four must contain one overload-pulse Tank", {"source": source}, true)
	var boss_room: Dictionary = _rooms[4]
	var boss_spawns := _spawns_for(str(boss_room.get("encounter_id", "")))
	if boss_spawns.size() != 1 or str(boss_spawns[0].get("enemy_id", "")) != "chrono_warden":
		report.add_error("M1 room five must contain Chrono Warden", {"source": source}, true)


func _spawns_for(encounter_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var encounter: Dictionary = _encounters.get(encounter_id, {})
	for wave: Dictionary in encounter.get("waves", []):
		for spawn: Dictionary in wave.get("spawns", []):
			result.append(spawn)
	return result


func _resolve_choices(encounter: Dictionary, run_seed: int, room_number: int) -> void:
	var roll_index := 0
	for wave: Dictionary in encounter.get("waves", []):
		for spawn: Dictionary in wave.get("spawns", []):
			for fields_value: Variant in [["enemy_choices", "enemy_id"], ["spawn_slot_choices", "spawn_slot_id"]]:
				var fields: Array = fields_value
				var choices: Variant = spawn.get(fields[0])
				if typeof(choices) == TYPE_ARRAY and not choices.is_empty():
					var rng: RandomNumberGenerator = SeedServiceScript.make_rng(run_seed, StringName("encounter:%s" % _plan_id), 1, room_number, roll_index)
					spawn[fields[1]] = choices[rng.randi_range(0, choices.size() - 1)]
					spawn.erase(fields[0])
				roll_index += 1


func _collect_unique_strings(values: Array, target: Dictionary, label: String, source: String, report) -> void:
	for value: Variant in values:
		var text := str(value)
		if typeof(value) != TYPE_STRING or text.is_empty() or target.has(text):
			report.add_error("%s id is invalid or duplicated" % label.capitalize(), {"source": source, "id": text}, true)
			continue
		target[text] = true


func _string_array_is_valid(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if typeof(value) != TYPE_STRING or str(value).is_empty() or seen.has(str(value)):
			return false
		seen[str(value)] = true
	return true


func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).is_empty()


func _is_schema_version_one(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == 1.0


func _clear() -> void:
	_plan_id = ""
	_mechanism_ids.clear()
	_enemy_definitions.clear()
	_spawn_slots.clear()
	_rooms.clear()
	_encounters.clear()
