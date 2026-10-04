class_name BuildLibrary
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const BUILD_FIELDS := ["id", "name", "character_id", "weapon_id", "time_abilities"]
const CAPACITY := 32

var _catalog: RefCounted


func configure(catalog: RefCounted) -> bool:
	_catalog = null
	var validator := Profile.new()
	if not validator.configure(catalog):
		return false
	_catalog = catalog
	return true


func prepare_command(profile: Dictionary, command: Dictionary, expected_revision: int) -> Dictionary:
	if _catalog == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var fields: Array = {
		"build_save": ["command_id", "kind", "build"],
		"build_remove": ["command_id", "kind", "build_id"],
	}.get(command.get("kind"), [])
	if fields.is_empty():
		return Candidate.failure(&"COMMAND_INVALID")
	var validation := Candidate.validate(profile, _catalog, command, fields, expected_revision)
	if not validation.ok:
		return validation
	var candidate := profile.duplicate(true)
	var selected_id: String
	if command.kind == "build_save":
		if not _build_valid(command.build, profile):
			return Candidate.failure(&"LOADOUT_INVALID")
		var build: Dictionary = command.build.duplicate(true)
		build.time_abilities.sort()
		selected_id = build.id
		var index := _index(candidate.build_library, selected_id)
		if index >= 0:
			if candidate.build_library[index] == build:
				return Candidate.failure(&"NO_CHANGE")
			candidate.build_library[index] = build
		elif candidate.build_library.size() < CAPACITY:
			candidate.build_library.append(build)
		else:
			return Candidate.failure(&"BUILD_CAPACITY")
		candidate.build_library.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	else:
		if not command.build_id is String:
			return Candidate.failure(&"BUILD_ID_INVALID")
		selected_id = command.build_id
		var index := _index(candidate.build_library, selected_id)
		if index < 0:
			return Candidate.failure(&"BUILD_NOT_FOUND")
		candidate.build_library.remove_at(index)
	return Candidate.finish(candidate, _catalog, command.command_id, {"build_id": selected_id})


func resolve(profile: Dictionary, build_id: String) -> Dictionary:
	var validator := Profile.new()
	if profile.is_empty() or _catalog == null or not validator.configure(_catalog, profile):
		return Candidate.failure(&"PROFILE_INVALID")
	var index := _index(profile.build_library, build_id)
	if index < 0:
		return Candidate.failure(&"BUILD_NOT_FOUND")
	var build: Dictionary = profile.build_library[index]
	if not _build_valid(build, profile):
		return Candidate.failure(&"LOADOUT_LOCKED")
	return Candidate.success({"build": build.duplicate(true)})


func _build_valid(value: Variant, profile: Dictionary) -> bool:
	if not Catalog.exact_fields(value, BUILD_FIELDS) or not Catalog.stable_id(value.id) or not value.name is String or value.name.strip_edges().is_empty() or value.name.length() > 64 or value.name.to_utf8_buffer().has(0):
		return false
	return profile.unlocked_characters.has(value.character_id) and profile.unlocked_weapons.has(value.weapon_id) and value.time_abilities is Array and value.time_abilities.size() == 2 and value.time_abilities[0] is String and value.time_abilities[1] is String and value.time_abilities[0] != value.time_abilities[1] and Catalog.TIME_IDS.has(value.time_abilities[0]) and Catalog.TIME_IDS.has(value.time_abilities[1])


func _index(entries: Array, id: String) -> int:
	for index: int in range(entries.size()):
		if entries[index].id == id:
			return index
	return -1
