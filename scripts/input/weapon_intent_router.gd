class_name WeaponIntentRouter
extends RefCounted

const LEGACY_SCHEMA_VERSION := 1
const CURRENT_SCHEMA_VERSION := 2
const LEGACY_WEAPON_ACTIONS := {
	&"attack": &"weapon_primary",
	&"ranged_attack": &"weapon_primary",
	&"heavy_attack": &"weapon_secondary",
}
const LEGACY_MIGRATION_ORDER: Array[StringName] = [
	&"attack",
	&"ranged_attack",
	&"heavy_attack",
]
const SEMANTIC_ACTIONS: Array[StringName] = [
	&"weapon_primary",
	&"weapon_secondary",
	&"weapon_utility",
	&"weapon_skill",
	&"weapon_ultimate",
	&"time_slot_1",
	&"time_slot_2",
	&"dash",
	&"interact",
	&"pause",
]
const VALID_EDGES: Array[StringName] = [&"pressed", &"held", &"released"]
const VALID_MODES: Array[StringName] = [&"press", &"hold", &"toggle"]

var _active_actions: Dictionary = {}
var _held_frames: Dictionary = {}


func migrate_profile(profile: Dictionary) -> Dictionary:
	if not _has_exact_fields(profile, ["schema_version", "bindings"]):
		return {}
	if typeof(profile.get("schema_version")) != TYPE_INT:
		return {}
	if not profile.get("bindings") is Dictionary:
		return {}

	var schema_version := int(profile["schema_version"])
	var source_bindings: Dictionary = profile["bindings"]
	if schema_version == CURRENT_SCHEMA_VERSION:
		if not _bindings_are_valid(source_bindings, true):
			return {}
		return profile.duplicate(true)
	if schema_version != LEGACY_SCHEMA_VERSION or not _bindings_are_valid(source_bindings, false):
		return {}

	for semantic_action: StringName in LEGACY_WEAPON_ACTIONS.values():
		if source_bindings.has(str(semantic_action)) or source_bindings.has(semantic_action):
			return {}

	var migrated_bindings: Dictionary = {}
	for action_value: Variant in source_bindings.keys():
		var action_id := StringName(str(action_value))
		if LEGACY_WEAPON_ACTIONS.has(action_id):
			continue
		migrated_bindings[str(action_id)] = source_bindings[action_value].duplicate(true)

	for legacy_action: StringName in LEGACY_MIGRATION_ORDER:
		var source_key: Variant = _existing_key(source_bindings, legacy_action)
		if source_key == null:
			continue
		var semantic_action: StringName = LEGACY_WEAPON_ACTIONS[legacy_action]
		var target_key := str(semantic_action)
		if not migrated_bindings.has(target_key):
			migrated_bindings[target_key] = source_bindings[source_key].duplicate(true)
			continue
		var merged: Variant = _merge_binding_sets(
			migrated_bindings[target_key],
			source_bindings[source_key]
		)
		if merged == null:
			return {}
		migrated_bindings[target_key] = merged

	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"bindings": migrated_bindings,
	}


func normalize_edge(
	action_id: StringName,
	raw_edge: StringName,
	held_frames: int,
	activation_mode: StringName
) -> Dictionary:
	var semantic_action: StringName = LEGACY_WEAPON_ACTIONS.get(action_id, action_id)
	if (
		not SEMANTIC_ACTIONS.has(semantic_action)
		or not VALID_EDGES.has(raw_edge)
		or not VALID_MODES.has(activation_mode)
		or held_frames < 0
	):
		return {}

	if activation_mode == &"press":
		return _normalize_press_edge(semantic_action, raw_edge)
	if activation_mode == &"toggle":
		return _normalize_toggle_edge(semantic_action, raw_edge, held_frames)
	return _normalize_hold_edge(semantic_action, raw_edge, held_frames)


func reset() -> void:
	reset_all()


func reset_action(action_id: StringName) -> bool:
	var semantic_action: StringName = LEGACY_WEAPON_ACTIONS.get(action_id, action_id)
	if not SEMANTIC_ACTIONS.has(semantic_action):
		return false
	_active_actions.erase(semantic_action)
	_held_frames.erase(semantic_action)
	return true


func reset_all() -> void:
	_active_actions.clear()
	_held_frames.clear()


func _normalize_press_edge(action_id: StringName, raw_edge: StringName) -> Dictionary:
	if raw_edge != &"pressed":
		return {}
	return _intent(action_id, &"pressed", 0)


func _normalize_hold_edge(action_id: StringName, raw_edge: StringName, frames: int) -> Dictionary:
	if raw_edge == &"pressed":
		if bool(_active_actions.get(action_id, false)):
			return {}
		_active_actions[action_id] = true
		_held_frames[action_id] = 0
		return _intent(action_id, &"pressed", 0)
	if not bool(_active_actions.get(action_id, false)):
		return {}

	var normalized_frames := maxi(int(_held_frames.get(action_id, 0)), frames)
	_held_frames[action_id] = normalized_frames
	if raw_edge == &"held":
		return _intent(action_id, &"held", normalized_frames)

	_active_actions.erase(action_id)
	_held_frames.erase(action_id)
	return _intent(action_id, &"released", normalized_frames)


func _normalize_toggle_edge(action_id: StringName, raw_edge: StringName, frames: int) -> Dictionary:
	var is_active := bool(_active_actions.get(action_id, false))
	if raw_edge == &"released":
		if is_active:
			_held_frames[action_id] = maxi(int(_held_frames.get(action_id, 0)), frames)
		return {}
	if raw_edge == &"held":
		if not is_active:
			return {}
		var normalized_frames := maxi(int(_held_frames.get(action_id, 0)), frames)
		_held_frames[action_id] = normalized_frames
		return _intent(action_id, &"held", normalized_frames)

	if not is_active:
		_active_actions[action_id] = true
		_held_frames[action_id] = 0
		return _intent(action_id, &"pressed", 0)

	var release_frames := maxi(int(_held_frames.get(action_id, 0)), frames)
	_active_actions.erase(action_id)
	_held_frames.erase(action_id)
	return _intent(action_id, &"released", release_frames)


func _bindings_are_valid(bindings: Dictionary, reject_legacy_weapon_actions: bool) -> bool:
	for key_value: Variant in bindings.keys():
		if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var action_id := StringName(str(key_value))
		if action_id == &"":
			return false
		if reject_legacy_weapon_actions and LEGACY_WEAPON_ACTIONS.has(action_id):
			return false
		if not _binding_set_is_valid(bindings[key_value]):
			return false
	return true


func _binding_set_is_valid(value: Variant) -> bool:
	if value is Array:
		return true
	if not value is Dictionary or (value as Dictionary).is_empty():
		return false
	for family_value: Variant in (value as Dictionary).values():
		if not family_value is Array:
			return false
	return true


func _merge_binding_sets(existing: Variant, incoming: Variant) -> Variant:
	if existing is Array and incoming is Array:
		return _merge_arrays(existing as Array, incoming as Array)
	if not existing is Dictionary or not incoming is Dictionary:
		return null
	var existing_families: Dictionary = existing
	var incoming_families: Dictionary = incoming
	if existing_families.size() != incoming_families.size():
		return null
	var merged := {}
	for family_value: Variant in existing_families.keys():
		if not incoming_families.has(family_value):
			return null
		if not existing_families[family_value] is Array or not incoming_families[family_value] is Array:
			return null
		merged[family_value] = _merge_arrays(
			existing_families[family_value] as Array,
			incoming_families[family_value] as Array
		)
	return merged


func _merge_arrays(existing: Array, incoming: Array) -> Array:
	var merged := existing.duplicate(true)
	for binding_value: Variant in incoming:
		if not merged.has(binding_value):
			merged.append(binding_value.duplicate(true) if binding_value is Array or binding_value is Dictionary else binding_value)
	return merged


func _existing_key(bindings: Dictionary, action_id: StringName) -> Variant:
	if bindings.has(action_id):
		return action_id
	var string_id := str(action_id)
	return string_id if bindings.has(string_id) else null


func _intent(action_id: StringName, edge: StringName, held_frames: int) -> Dictionary:
	return {
		"id": action_id,
		"edge": edge,
		"held_frames": held_frames,
	}


func _has_exact_fields(value: Dictionary, expected_fields: Array[String]) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field: String in expected_fields:
		if not value.has(field):
			return false
	return true
