class_name InputRemapService
extends RefCounted

signal bindings_changed(action: StringName)

const InputBindingCodecScript := preload("res://scripts/input/input_binding_codec.gd")
const InputProfileStoreScript := preload("res://scripts/input/input_profile_store.gd")
const WeaponIntentRouterScript := preload("res://scripts/input/weapon_intent_router.gd")

const BINDING_FAMILIES: Array[String] = ["keyboard_mouse", "controller"]
const RETIRED_ACTIONS: Array[StringName] = [
	&"attack",
	&"heavy_attack",
	&"ranged_attack",
	&"time_stop",
	&"time_rewind",
	&"time_rift",
	&"time_accelerate",
]
const AXIS_CAPTURE_THRESHOLD := 0.75
const JOYPAD_BUTTON_LABELS: Array[String] = [
	"A", "B", "X", "Y", "Back", "Guide", "Start", "Left Stick", "Right Stick",
	"Left Shoulder", "Right Shoulder", "D-pad Up", "D-pad Down", "D-pad Left",
	"D-pad Right", "Misc", "Paddle 1", "Paddle 2", "Paddle 3", "Paddle 4",
	"Touchpad", "Button 21", "Button 22", "Button 23",
]
const JOYPAD_AXIS_LABELS: Array[String] = [
	"Left Stick X", "Left Stick Y", "Right Stick X", "Right Stick Y",
	"Left Trigger", "Right Trigger", "Axis 6", "Axis 7",
]

var _store: Variant
var _default_profile: Dictionary = {}


func configure(root_path: String = "user://plane_walker/input", store_override: Variant = null) -> void:
	_default_profile = _profile_from_project_settings()
	if store_override != null:
		_store = store_override
		return
	_store = InputProfileStoreScript.new()
	_store.configure(root_path)


func remappable_actions() -> Array[StringName]:
	return InputProfileStoreScript.profile_actions()


func load_or_defaults() -> Dictionary:
	var readiness := _require_configured()
	if not bool(readiness["ok"]):
		return readiness
	var loaded: Dictionary = _store.load()
	if bool(loaded.get("ok", false)):
		var profile: Dictionary = loaded.get("profile", {})
		if int(profile.get("schema_version", 0)) != InputProfileStoreScript.SCHEMA_VERSION:
			return _migrate_loaded_profile(loaded, profile)
		if not _apply_profile(profile):
			return _failure("APPLY_FAILED")
		return {
			"ok": true,
			"code": loaded.get("code", "OK"),
			"profile": profile.duplicate(true),
			"source": loaded.get("source", "primary"),
		}

	var runtime_before := _snapshot_runtime_events()
	if not _apply_profile(_default_profile):
		return _failure("APPLY_FAILED")
	var saved: Dictionary = _store.save(_default_profile)
	if not bool(saved.get("ok", false)):
		_restore_runtime_events(runtime_before)
		return saved
	return {
		"ok": true,
		"code": "DEFAULTS_CREATED" if loaded.get("code") == "NOT_FOUND" else "DEFAULTS_RECOVERED",
		"profile": _default_profile.duplicate(true),
		"source": "defaults",
	}


func remap(action: StringName, family: StringName, event: InputEvent) -> Dictionary:
	var readiness := _require_configured()
	if not bool(readiness["ok"]):
		return readiness
	if not remappable_actions().has(action):
		return _failure("UNKNOWN_ACTION", {"action": str(action)})
	if str(family) not in BINDING_FAMILIES:
		return _failure("UNKNOWN_BINDING_FAMILY", {"family": str(family)})
	if event == null:
		return _failure("UNSUPPORTED_INPUT")
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < AXIS_CAPTURE_THRESHOLD:
		return _failure("AXIS_BELOW_CAPTURE_THRESHOLD")

	var portable_event := event.duplicate(true) as InputEvent
	portable_event.device = -1
	var requested_record: Dictionary = InputBindingCodecScript.encode(portable_event)
	if requested_record.is_empty():
		return _failure("UNSUPPORTED_INPUT")
	if InputBindingCodecScript.binding_family(requested_record) != str(family):
		return _failure("BINDING_FAMILY_MISMATCH")

	var before := snapshot_profile()
	var candidate := before.duplicate(true)
	var action_id := str(action)
	var family_id := str(family)
	var target_records: Array = candidate["bindings"][action_id][family_id]
	var requested_id := InputBindingCodecScript.canonical_id(requested_record)
	var existing_index := _record_index(target_records, requested_id)
	if existing_index >= 0:
		return {"ok": true, "code": "UNCHANGED", "profile": before}

	var owner := _find_owner(candidate, family_id, requested_id)
	if _would_remove_last_pause_binding(action_id, target_records, owner, candidate, family_id):
		return _failure("PROTECTED_PAUSE_BINDING")
	var displaced_record: Dictionary = (target_records[0] as Dictionary).duplicate(true)
	var changed_actions: Array[StringName] = [action]
	target_records[0] = requested_record.duplicate(true)
	if not owner.is_empty() and owner != action_id:
		var owner_records: Array = candidate["bindings"][owner][family_id]
		var owner_index := _record_index(owner_records, requested_id)
		if owner_index < 0:
			return _failure("CONFLICT_OWNER_MISSING")
		owner_records[owner_index] = displaced_record
		changed_actions.append(StringName(owner))

	var validation: Dictionary = _store.validate_profile(candidate)
	if not bool(validation.get("ok", false)):
		return validation
	if not _apply_profile(candidate):
		_apply_profile(before)
		return _failure("APPLY_FAILED")
	var saved: Dictionary = _store.save(candidate)
	if not bool(saved.get("ok", false)):
		_apply_profile(before)
		return saved
	for changed_action: StringName in changed_actions:
		bindings_changed.emit(changed_action)
	return {
		"ok": true,
		"code": "SWAPPED" if changed_actions.size() > 1 else "OK",
		"profile": candidate.duplicate(true),
		"changed_actions": changed_actions.duplicate(),
	}


func reset_action(action: StringName) -> Dictionary:
	var readiness := _require_configured()
	if not bool(readiness["ok"]):
		return readiness
	if not remappable_actions().has(action):
		return _failure("UNKNOWN_ACTION", {"action": str(action)})
	var before := snapshot_profile()
	var candidate := before.duplicate(true)
	var action_id := str(action)
	var changed_actions: Array[StringName] = [action]
	for family: String in BINDING_FAMILIES:
		var target_records: Array = candidate["bindings"][action_id][family]
		var desired_records: Array = _default_profile["bindings"][action_id][family]
		for index: int in range(desired_records.size()):
			var desired_record := desired_records[index] as Dictionary
			var desired_id := InputBindingCodecScript.canonical_id(desired_record)
			var owner := _find_owner(candidate, family, desired_id)
			if owner.is_empty() or owner == action_id:
				continue
			var owner_records: Array = candidate["bindings"][owner][family]
			var owner_index := _record_index(owner_records, desired_id)
			if owner_index < 0 or index >= target_records.size():
				return _failure("RESET_CONFLICT")
			owner_records[owner_index] = (target_records[index] as Dictionary).duplicate(true)
			var owner_name := StringName(owner)
			if not changed_actions.has(owner_name):
				changed_actions.append(owner_name)
		candidate["bindings"][action_id][family] = desired_records.duplicate(true)
	return _persist_candidate(before, candidate, changed_actions, "RESET_ACTION")


func reset_all() -> Dictionary:
	var readiness := _require_configured()
	if not bool(readiness["ok"]):
		return readiness
	var before := snapshot_profile()
	var candidate := _default_profile.duplicate(true)
	return _persist_candidate(before, candidate, remappable_actions(), "RESET_ALL")


func binding_labels(action: StringName) -> Dictionary:
	var labels := {
		"keyboard_mouse": [],
		"controller": [],
	}
	if not remappable_actions().has(action):
		return labels
	var profile := snapshot_profile()
	for family: String in BINDING_FAMILIES:
		for record_value: Variant in profile["bindings"][str(action)][family]:
			(labels[family] as Array).append(_binding_label(record_value as Dictionary))
	return labels


func snapshot_profile() -> Dictionary:
	return _profile_from_runtime()


func _migrate_loaded_profile(loaded: Dictionary, source_profile: Dictionary) -> Dictionary:
	var router = WeaponIntentRouterScript.new()
	var semantic_profile := source_profile.duplicate(true)
	var source_schema := int(source_profile.get("schema_version", 0))
	if source_schema == WeaponIntentRouterScript.LEGACY_SCHEMA_VERSION:
		semantic_profile = router.migrate_legacy_profile_to_schema_two(source_profile)
		if semantic_profile.is_empty():
			return _failure("MIGRATION_FAILED", {"source": loaded.get("source", "unknown")})
		var semantic_bindings: Dictionary = semantic_profile.get("bindings", {})
		for action: StringName in InputProfileStoreScript.schema_two_profile_actions():
			var action_id := str(action)
			if semantic_bindings.has(action_id):
				continue
			semantic_bindings[action_id] = _default_profile["bindings"][action_id].duplicate(true)
		semantic_profile["bindings"] = semantic_bindings
		var semantic_validation: Dictionary = _store.validate_schema_two_profile(semantic_profile)
		if not bool(semantic_validation.get("ok", false)):
			return _failure("MIGRATION_FAILED", {
				"source": loaded.get("source", "unknown"),
				"cause": semantic_validation,
			})
	elif source_schema != InputProfileStoreScript.SCHEMA_TWO_VERSION:
		return _failure("MIGRATION_FAILED", {"source": loaded.get("source", "unknown")})

	var migrated: Dictionary = router.migrate_profile(semantic_profile)
	if migrated.get("code", "") == "NO_REACHABLE_CHARACTER_SKILL":
		return migrated.duplicate(true)
	if migrated.is_empty() or migrated.has("ok"):
		return _failure("MIGRATION_FAILED", {"source": loaded.get("source", "unknown")})

	var validation: Dictionary = _store.validate_profile(migrated)
	if not bool(validation.get("ok", false)):
		return _failure("MIGRATION_FAILED", {
			"source": loaded.get("source", "unknown"),
			"cause": validation,
		})
	var runtime_before := _snapshot_runtime_events()
	if not _apply_profile(migrated):
		_restore_runtime_events(runtime_before)
		return _failure("APPLY_FAILED")
	var saved: Dictionary = _store.save(migrated)
	if not bool(saved.get("ok", false)):
		_restore_runtime_events(runtime_before)
		return saved
	return {
		"ok": true,
		"code": (
			"RECOVERED_MIGRATED"
			if str(loaded.get("code", "")).begins_with("RECOVERED_")
			else "MIGRATED"
		),
		"profile": migrated.duplicate(true),
		"source": loaded.get("source", "legacy_primary"),
	}


func _snapshot_runtime_events() -> Dictionary:
	var snapshot := {}
	var actions := remappable_actions()
	for retired_action: StringName in RETIRED_ACTIONS:
		if not actions.has(retired_action):
			actions.append(retired_action)
	for action: StringName in actions:
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate(true) as InputEvent)
		snapshot[action] = events
	return snapshot


func _restore_runtime_events(snapshot: Dictionary) -> void:
	for action_value: Variant in snapshot.keys():
		var action := StringName(str(action_value))
		InputMap.action_erase_events(action)
		for event: InputEvent in snapshot[action_value]:
			InputMap.action_add_event(action, event)


func _persist_candidate(
	before: Dictionary,
	candidate: Dictionary,
	changed_actions: Array[StringName],
	code: String
) -> Dictionary:
	var validation: Dictionary = _store.validate_profile(candidate)
	if not bool(validation.get("ok", false)):
		return validation
	if not _apply_profile(candidate):
		_apply_profile(before)
		return _failure("APPLY_FAILED")
	var saved: Dictionary = _store.save(candidate)
	if not bool(saved.get("ok", false)):
		_apply_profile(before)
		return saved
	for action: StringName in changed_actions:
		bindings_changed.emit(action)
	return {"ok": true, "code": code, "profile": candidate.duplicate(true)}


func _profile_from_project_settings() -> Dictionary:
	var bindings := {}
	for action: StringName in remappable_actions():
		var action_setting: Dictionary = ProjectSettings.get_setting("input/%s" % action, {})
		bindings[str(action)] = _records_by_family(action_setting.get("events", []))
	return {"schema_version": InputProfileStoreScript.SCHEMA_VERSION, "bindings": bindings}


func _profile_from_runtime() -> Dictionary:
	var bindings := {}
	for action: StringName in remappable_actions():
		bindings[str(action)] = _records_by_family(InputMap.action_get_events(action))
	return {"schema_version": InputProfileStoreScript.SCHEMA_VERSION, "bindings": bindings}


func _records_by_family(events: Array) -> Dictionary:
	var families := {
		"keyboard_mouse": [],
		"controller": [],
	}
	for event_value: Variant in events:
		if not event_value is InputEvent:
			continue
		var event := (event_value as InputEvent).duplicate(true) as InputEvent
		event.device = -1
		var record: Dictionary = InputBindingCodecScript.encode(event)
		if record.is_empty():
			continue
		var family := InputBindingCodecScript.binding_family(record)
		(families[family] as Array).append(record)
	return families


func _apply_profile(profile: Dictionary) -> bool:
	var decoded_by_action := {}
	for action: StringName in remappable_actions():
		var action_id := str(action)
		if not profile.get("bindings", {}).has(action_id):
			return false
		var decoded_events: Array[InputEvent] = []
		for family: String in BINDING_FAMILIES:
			for record_value: Variant in profile["bindings"][action_id][family]:
				var decoded := InputBindingCodecScript.decode(record_value as Dictionary)
				if decoded == null:
					return false
				decoded_events.append(decoded)
		decoded_by_action[action] = decoded_events
	for action: StringName in remappable_actions():
		InputMap.action_erase_events(action)
		for event: InputEvent in decoded_by_action[action]:
			InputMap.action_add_event(action, event)
	for retired_action: StringName in RETIRED_ACTIONS:
		InputMap.action_erase_events(retired_action)
	return true


func _would_remove_last_pause_binding(
	target_action: String,
	target_records: Array,
	owner: String,
	profile: Dictionary,
	family: String
) -> bool:
	if target_action == "pause" and target_records.size() == 1:
		return true
	if owner == "pause":
		var pause_records: Array = profile["bindings"]["pause"][family]
		return pause_records.size() == 1
	return false


func _find_owner(profile: Dictionary, family: String, canonical_id: String) -> String:
	for action: StringName in remappable_actions():
		var records: Array = profile["bindings"][str(action)][family]
		if _record_index(records, canonical_id) >= 0:
			return str(action)
	return ""


func _record_index(records: Array, canonical_id: String) -> int:
	for index: int in range(records.size()):
		if InputBindingCodecScript.canonical_id(records[index] as Dictionary) == canonical_id:
			return index
	return -1


func _binding_label(record: Dictionary) -> String:
	match str(record.get("type", "")):
		"key":
			return OS.get_keycode_string(int(record["physical_keycode"]))
		"mouse_button":
			return "Mouse %d" % int(record["button_index"])
		"joypad_button":
			var button_index := int(record["button_index"])
			return JOYPAD_BUTTON_LABELS[button_index] if button_index < JOYPAD_BUTTON_LABELS.size() else "Button %d" % button_index
		"joypad_axis":
			var axis := int(record["axis"])
			var base := JOYPAD_AXIS_LABELS[axis] if axis < JOYPAD_AXIS_LABELS.size() else "Axis %d" % axis
			if axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
				return base
			var direction := int(record["direction"])
			if axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]:
				return "%s %s" % [base.trim_suffix(" X"), "Left" if direction < 0 else "Right"]
			if axis in [JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_Y]:
				return "%s %s" % [base.trim_suffix(" Y"), "Up" if direction < 0 else "Down"]
			return "%s %s" % [base, "-" if direction < 0 else "+"]
	return "Unknown"


func _require_configured() -> Dictionary:
	if _store == null or _default_profile.is_empty():
		return _failure("NOT_CONFIGURED")
	return {"ok": true, "code": "OK"}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "details": details.duplicate(true)}
