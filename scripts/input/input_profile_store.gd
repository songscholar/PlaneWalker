class_name InputProfileStore
extends RefCounted

const InputActionContractScript := preload("res://scripts/input/input_action_contract.gd")
const InputBindingCodecScript := preload("res://scripts/input/input_binding_codec.gd")
const RuntimeUserDataPathScript := preload("res://scripts/save/runtime_user_data_path.gd")

const SCHEMA_VERSION := 4
const SCHEMA_THREE_VERSION := 3
const SCHEMA_TWO_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1
const PRIMARY_FILE := "input_profile_v4.json"
const PENDING_FILE := "pending.tmp"
const BACKUP_FILE := "backup_4.json"
const SCHEMA_THREE_PRIMARY_FILE := "input_profile_v3.json"
const SCHEMA_THREE_BACKUP_FILE := "backup_3.json"
const SCHEMA_TWO_PRIMARY_FILE := "input_profile_v2.json"
const SCHEMA_TWO_BACKUP_FILE := "backup_2.json"
const LEGACY_PRIMARY_FILE := "input_profile_v1.json"
const LEGACY_BACKUP_FILE := "backup_1.json"
const BINDING_FAMILIES: Array[String] = ["keyboard_mouse", "controller"]
const PROFILE_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"weapon_primary",
	&"weapon_secondary",
	&"weapon_utility",
	&"weapon_skill",
	&"weapon_ultimate",
	&"time_slot_1",
	&"time_slot_2",
	&"character_skill",
	&"active_item",
	&"dash",
	&"interact",
	&"pause",
]
const SCHEMA_THREE_PROFILE_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"weapon_primary",
	&"weapon_secondary",
	&"weapon_utility",
	&"weapon_skill",
	&"weapon_ultimate",
	&"time_slot_1",
	&"time_slot_2",
	&"character_skill",
	&"dash",
	&"interact",
	&"pause",
]
const SCHEMA_TWO_PROFILE_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
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

var _root_path: String = ""


func configure(root_path: String = "user://plane_walker/input") -> void:
	var selected := root_path
	if selected == "user://plane_walker/input":
		selected = RuntimeUserDataPathScript.resolve_default(selected, "plane_walker/input")
	_root_path = ProjectSettings.globalize_path(selected) if not selected.is_empty() else ""


func primary_path() -> String:
	return _path(PRIMARY_FILE)


func pending_path() -> String:
	return _path(PENDING_FILE)


func backup_path() -> String:
	return _path(BACKUP_FILE)


func schema_three_primary_path() -> String:
	return _path(SCHEMA_THREE_PRIMARY_FILE)


func schema_three_backup_path() -> String:
	return _path(SCHEMA_THREE_BACKUP_FILE)


func schema_two_primary_path() -> String:
	return _path(SCHEMA_TWO_PRIMARY_FILE)


func schema_two_backup_path() -> String:
	return _path(SCHEMA_TWO_BACKUP_FILE)


func legacy_primary_path() -> String:
	return _path(LEGACY_PRIMARY_FILE)


func legacy_backup_path() -> String:
	return _path(LEGACY_BACKUP_FILE)


static func profile_actions() -> Array[StringName]:
	return PROFILE_ACTIONS.duplicate()


static func schema_three_profile_actions() -> Array[StringName]:
	return SCHEMA_THREE_PROFILE_ACTIONS.duplicate()


static func schema_two_profile_actions() -> Array[StringName]:
	return SCHEMA_TWO_PROFILE_ACTIONS.duplicate()


func save(profile: Dictionary) -> Dictionary:
	var readiness := _require_configured()
	if not bool(readiness["ok"]):
		return readiness
	var validation := validate_profile(profile)
	if not bool(validation["ok"]):
		_remove_if_present(pending_path())
		return validation
	var directory_error := DirAccess.make_dir_recursive_absolute(_root_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure("IO_ERROR", {"operation": "make_directory", "error": directory_error})

	_remove_if_present(pending_path())
	var write_result := _write_text(pending_path(), JSON.stringify(profile, "", true, true))
	if not bool(write_result["ok"]):
		_remove_if_present(pending_path())
		return write_result
	var pending_result := _load_candidate(pending_path(), "pending", SCHEMA_VERSION)
	if not bool(pending_result["ok"]):
		_remove_if_present(pending_path())
		return _failure("VERIFY_FAILED", {"candidate": "pending", "cause": pending_result})
	if pending_result["profile"] != profile:
		_remove_if_present(pending_path())
		return _failure("VERIFY_FAILED", {"candidate": "pending", "reason": "round_trip_mismatch"})

	var had_verified_primary := false
	if FileAccess.file_exists(primary_path()):
		var primary_result := _load_candidate(primary_path(), "primary", SCHEMA_VERSION)
		if bool(primary_result["ok"]):
			_remove_if_present(backup_path())
			var backup_error := DirAccess.copy_absolute(primary_path(), backup_path())
			if backup_error != OK:
				_remove_if_present(pending_path())
				return _failure("IO_ERROR", {"operation": "backup", "error": backup_error})
			had_verified_primary = true

	var remove_error := _remove_if_present(primary_path())
	if remove_error != OK:
		_remove_if_present(pending_path())
		return _failure("IO_ERROR", {"operation": "remove_primary", "error": remove_error})
	var promote_error := DirAccess.rename_absolute(pending_path(), primary_path())
	if promote_error != OK:
		_restore_backup_if_needed(had_verified_primary)
		_remove_if_present(pending_path())
		return _failure("IO_ERROR", {"operation": "promote", "error": promote_error})

	var promoted_result := _load_candidate(primary_path(), "primary", SCHEMA_VERSION)
	if not bool(promoted_result["ok"]) or promoted_result["profile"] != profile:
		_remove_if_present(primary_path())
		_restore_backup_if_needed(had_verified_primary)
		return _failure("VERIFY_FAILED", {"candidate": "primary", "cause": promoted_result})
	return _success(profile, "primary", "OK")


func load() -> Dictionary:
	var readiness := _require_configured()
	if not bool(readiness["ok"]):
		return readiness
	var primary_result := _load_candidate(primary_path(), "primary", SCHEMA_VERSION)
	if bool(primary_result["ok"]):
		return primary_result
	var backup_result := _load_candidate(backup_path(), "backup_4", SCHEMA_VERSION)
	if bool(backup_result["ok"]):
		backup_result["code"] = "RECOVERED"
		backup_result["diagnostics"] = [{
			"candidate": "primary",
			"code": primary_result.get("code", "CORRUPT"),
		}]
		return backup_result

	var schema_three_primary_result := _load_candidate(
		schema_three_primary_path(),
		"schema_three_primary",
		SCHEMA_THREE_VERSION
	)
	if bool(schema_three_primary_result["ok"]):
		schema_three_primary_result["code"] = "MIGRATION_REQUIRED"
		return schema_three_primary_result
	var schema_three_backup_result := _load_candidate(
		schema_three_backup_path(),
		"schema_three_backup",
		SCHEMA_THREE_VERSION
	)
	if bool(schema_three_backup_result["ok"]):
		schema_three_backup_result["code"] = "RECOVERED_MIGRATION_REQUIRED"
		schema_three_backup_result["diagnostics"] = [{
			"candidate": "schema_three_primary",
			"code": schema_three_primary_result.get("code", "CORRUPT"),
		}]
		return schema_three_backup_result

	var schema_two_primary_result := _load_candidate(
		schema_two_primary_path(),
		"schema_two_primary",
		SCHEMA_TWO_VERSION
	)
	if bool(schema_two_primary_result["ok"]):
		schema_two_primary_result["code"] = "MIGRATION_REQUIRED"
		return schema_two_primary_result
	var schema_two_backup_result := _load_candidate(
		schema_two_backup_path(),
		"schema_two_backup",
		SCHEMA_TWO_VERSION
	)
	if bool(schema_two_backup_result["ok"]):
		schema_two_backup_result["code"] = "RECOVERED_MIGRATION_REQUIRED"
		schema_two_backup_result["diagnostics"] = [{
			"candidate": "schema_two_primary",
			"code": schema_two_primary_result.get("code", "CORRUPT"),
		}]
		return schema_two_backup_result

	var legacy_primary_result := _load_candidate(
		legacy_primary_path(),
		"legacy_primary",
		LEGACY_SCHEMA_VERSION
	)
	if bool(legacy_primary_result["ok"]):
		legacy_primary_result["code"] = "MIGRATION_REQUIRED"
		return legacy_primary_result
	var legacy_backup_result := _load_candidate(
		legacy_backup_path(),
		"legacy_backup",
		LEGACY_SCHEMA_VERSION
	)
	if bool(legacy_backup_result["ok"]):
		legacy_backup_result["code"] = "RECOVERED_MIGRATION_REQUIRED"
		legacy_backup_result["diagnostics"] = [{
			"candidate": "legacy_primary",
			"code": legacy_primary_result.get("code", "CORRUPT"),
		}]
		return legacy_backup_result

	if (
		primary_result.get("code") == "NOT_FOUND"
		and backup_result.get("code") == "NOT_FOUND"
		and schema_three_primary_result.get("code") == "NOT_FOUND"
		and schema_three_backup_result.get("code") == "NOT_FOUND"
		and schema_two_primary_result.get("code") == "NOT_FOUND"
		and schema_two_backup_result.get("code") == "NOT_FOUND"
		and legacy_primary_result.get("code") == "NOT_FOUND"
		and legacy_backup_result.get("code") == "NOT_FOUND"
	):
		return _failure("NOT_FOUND")
	return _failure("CORRUPT", {
		"primary": primary_result,
		"backup_4": backup_result,
		"schema_three_primary": schema_three_primary_result,
		"schema_three_backup": schema_three_backup_result,
		"schema_two_primary": schema_two_primary_result,
		"schema_two_backup": schema_two_backup_result,
		"legacy_primary": legacy_primary_result,
		"legacy_backup": legacy_backup_result,
	})


func validate_profile(profile: Dictionary) -> Dictionary:
	return _validate_profile_for_actions(profile, SCHEMA_VERSION, PROFILE_ACTIONS)


func validate_schema_three_profile(profile: Dictionary) -> Dictionary:
	return _validate_profile_for_actions(
		profile,
		SCHEMA_THREE_VERSION,
		SCHEMA_THREE_PROFILE_ACTIONS
	)


func validate_schema_two_profile(profile: Dictionary) -> Dictionary:
	return _validate_profile_for_actions(
		profile,
		SCHEMA_TWO_VERSION,
		SCHEMA_TWO_PROFILE_ACTIONS
	)


func _validate_legacy_profile(profile: Dictionary) -> Dictionary:
	return _validate_profile_for_actions(
		profile,
		LEGACY_SCHEMA_VERSION,
		InputActionContractScript.legacy_profile_actions()
	)


func _validate_profile_for_actions(
	profile: Dictionary,
	expected_schema_version: int,
	required_actions: Array[StringName]
) -> Dictionary:
	if not _has_exact_fields(profile, ["schema_version", "bindings"]):
		return _failure("INVALID_PROFILE", {"field": "profile", "reason": "fields"})
	if (
		typeof(profile.get("schema_version")) != TYPE_INT
		or int(profile["schema_version"]) != expected_schema_version
	):
		return _failure("INVALID_PROFILE", {"field": "schema_version", "reason": "version"})
	if typeof(profile.get("bindings")) != TYPE_DICTIONARY:
		return _failure("INVALID_PROFILE", {"field": "bindings", "reason": "type"})

	var bindings: Dictionary = profile["bindings"]
	if bindings.size() != required_actions.size():
		return _failure("INVALID_PROFILE", {"field": "bindings", "reason": "action_count"})
	for action_value: Variant in bindings.keys():
		if not required_actions.has(StringName(str(action_value))):
			return _failure("INVALID_PROFILE", {
				"field": "bindings.%s" % action_value,
				"reason": "unknown_action",
			})

	var canonical_owners := {
		"keyboard_mouse": {},
		"controller": {},
	}
	for action: StringName in required_actions:
		var action_id := str(action)
		if typeof(bindings.get(action_id)) != TYPE_DICTIONARY:
			return _failure("INVALID_PROFILE", {"field": "bindings.%s" % action_id, "reason": "type"})
		var action_bindings: Dictionary = bindings[action_id]
		if not _has_exact_fields(action_bindings, BINDING_FAMILIES):
			return _failure("INVALID_PROFILE", {"field": "bindings.%s" % action_id, "reason": "families"})
		for family: String in BINDING_FAMILIES:
			if typeof(action_bindings.get(family)) != TYPE_ARRAY or (action_bindings[family] as Array).is_empty():
				return _failure("INVALID_PROFILE", {
					"field": "bindings.%s.%s" % [action_id, family],
					"reason": "non_empty_array_required",
				})
			for record_value: Variant in action_bindings[family]:
				if typeof(record_value) != TYPE_DICTIONARY:
					return _failure("INVALID_PROFILE", {
						"field": "bindings.%s.%s" % [action_id, family],
						"reason": "record_type",
					})
				var record := record_value as Dictionary
				var canonical_id := InputBindingCodecScript.canonical_id(record)
				if canonical_id.is_empty():
					return _failure("INVALID_PROFILE", {
						"field": "bindings.%s.%s" % [action_id, family],
						"reason": "record",
					})
				if InputBindingCodecScript.binding_family(record) != family:
					return _failure("INVALID_PROFILE", {
						"field": "bindings.%s.%s" % [action_id, family],
						"reason": "family_mismatch",
					})
				var owners: Dictionary = canonical_owners[family]
				if owners.has(canonical_id):
					return _failure("INVALID_PROFILE", {
						"field": "bindings.%s.%s" % [action_id, family],
						"reason": "duplicate_binding",
						"binding": canonical_id,
						"owner": owners[canonical_id],
					})
				owners[canonical_id] = action_id
	return {"ok": true, "code": "OK"}


func _load_candidate(path: String, source: String, expected_schema_version: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("NOT_FOUND", {"path": path, "source": source})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("IO_ERROR", {"path": path, "source": source, "error": FileAccess.get_open_error()})
	var contents := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _failure("IO_ERROR", {"path": path, "source": source, "error": read_error})
	var parsed: Variant = JSON.parse_string(contents)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("CORRUPT", {"path": path, "source": source, "reason": "json"})
	var profile := _normalize_json_profile(parsed as Dictionary)
	var validation: Dictionary
	match expected_schema_version:
		LEGACY_SCHEMA_VERSION:
			validation = _validate_legacy_profile(profile)
		SCHEMA_TWO_VERSION:
			validation = validate_schema_two_profile(profile)
		SCHEMA_THREE_VERSION:
			validation = validate_schema_three_profile(profile)
		_:
			validation = validate_profile(profile)
	if not bool(validation["ok"]):
		return _failure("CORRUPT", {"path": path, "source": source, "reason": validation})
	return _success(profile, source, "OK")


func _write_text(path: String, contents: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("IO_ERROR", {"path": path, "operation": "open_write", "error": FileAccess.get_open_error()})
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("IO_ERROR", {"path": path, "operation": "write", "error": write_error})
	return {"ok": true, "code": "OK"}


func _restore_backup_if_needed(had_verified_primary: bool) -> void:
	if had_verified_primary and FileAccess.file_exists(backup_path()):
		DirAccess.copy_absolute(backup_path(), primary_path())


func _remove_if_present(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)


func _require_configured() -> Dictionary:
	if _root_path.strip_edges().is_empty():
		return _failure("NOT_CONFIGURED")
	return {"ok": true, "code": "OK"}


func _path(file_name: String) -> String:
	return _root_path.path_join(file_name) if not _root_path.is_empty() else file_name


static func _has_exact_fields(value: Dictionary, expected_fields: Array[String]) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field: String in expected_fields:
		if not value.has(field):
			return false
	return true


static func _normalize_json_profile(profile: Dictionary) -> Dictionary:
	var normalized := profile.duplicate(true)
	if _is_integral_number(normalized.get("schema_version")):
		normalized["schema_version"] = int(normalized["schema_version"])
	if typeof(normalized.get("bindings")) != TYPE_DICTIONARY:
		return normalized
	var bindings: Dictionary = normalized["bindings"]
	for action_value: Variant in bindings.keys():
		if typeof(bindings[action_value]) != TYPE_DICTIONARY:
			continue
		var action_bindings: Dictionary = bindings[action_value]
		for family: String in BINDING_FAMILIES:
			if typeof(action_bindings.get(family)) != TYPE_ARRAY:
				continue
			var records: Array = action_bindings[family]
			for index: int in range(records.size()):
				if typeof(records[index]) != TYPE_DICTIONARY:
					continue
				var record: Dictionary = (records[index] as Dictionary).duplicate(true)
				for field: String in ["physical_keycode", "button_index", "axis", "direction"]:
					if _is_integral_number(record.get(field)):
						record[field] = int(record[field])
				records[index] = record
	return normalized


static func _is_integral_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and is_equal_approx(float(value), floorf(float(value)))


static func _success(profile: Dictionary, source: String, code: String) -> Dictionary:
	return {
		"ok": true,
		"code": code,
		"profile": profile.duplicate(true),
		"source": source,
	}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"details": details.duplicate(true),
	}
