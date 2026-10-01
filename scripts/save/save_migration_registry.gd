class_name SaveMigrationRegistry
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SaveMigrationV0ToV1Script := preload("res://scripts/save/migrations/save_migration_v0_to_v1.gd")
const SaveMigrationV1ToV2Script := preload("res://scripts/save/migrations/save_migration_v1_to_v2.gd")

var _migrations: Dictionary = {}
var _default_migrators: Array[RefCounted] = []


func _init(register_defaults: bool = true) -> void:
	if register_defaults:
		var v0_to_v1: RefCounted = SaveMigrationV0ToV1Script.new()
		var v1_to_v2: RefCounted = SaveMigrationV1ToV2Script.new()
		_default_migrators.assign([v0_to_v1, v1_to_v2])
		register_migration(0, 1, Callable(v0_to_v1, "migrate"))
		register_migration(1, 2, Callable(v1_to_v2, "migrate"))


func register_migration(from_version: int, to_version: int, migration: Callable):
	if from_version < 0 or to_version != from_version + 1 or not migration.is_valid():
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {
			"from_version": from_version,
			"to_version": to_version,
		})
	if _migrations.has(from_version):
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {
			"from_version": from_version,
			"to_version": to_version,
			"reason": "duplicate_source_version",
		})
	_migrations[from_version] = {
		"to_version": to_version,
		"migration": migration,
	}
	return SaveResultScript.success({}, {
		"from_version": from_version,
		"to_version": to_version,
	})


func migrate(document: Dictionary, target_version: int, context: Dictionary = {}):
	var version_info := _source_version(document)
	if not bool(version_info.get("valid", false)) or target_version < 0:
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {
			"target_version": target_version,
			"reason": str(version_info.get("reason", "invalid_target_version")),
		})

	var source_version := int(version_info["version"])
	var source_kind := StringName(str(version_info["source_kind"]))
	if source_version > target_version:
		return SaveResultScript.failure(&"FORWARD_VERSION", {
			"source_kind": source_kind,
			"migrated_from": source_version,
			"migrated_to": source_version,
			"source_version": source_version,
			"target_version": target_version,
		})

	var current := document.duplicate(true)
	var current_version := source_version
	var merged_metadata: Dictionary = {}
	var merged_diagnostics: Array[Dictionary] = []
	while current_version < target_version:
		if not _migrations.has(current_version):
			return _migration_failure(
				&"MIGRATION_UNAVAILABLE",
				source_kind,
				source_version,
				current_version,
				current_version + 1,
				merged_diagnostics,
				{"target_version": target_version}
			)

		var registration: Dictionary = _migrations[current_version]
		var next_version := int(registration["to_version"])
		if next_version != current_version + 1:
			return _migration_failure(
				&"MIGRATION_FAILED",
				source_kind,
				source_version,
				current_version,
				next_version,
				merged_diagnostics,
				{"reason": "non_adjacent_registered_step"}
			)

		var migration: Callable = registration["migration"]
		var first: Variant = migration.call(current.duplicate(true), context.duplicate(true))
		var second: Variant = migration.call(current.duplicate(true), context.duplicate(true))
		var validation: Variant = _validate_step_results(first, second, current_version, next_version)
		if not validation.ok:
			var failed_metadata: Dictionary = validation.metadata.duplicate(true)
			return _migration_failure(
				&"MIGRATION_FAILED",
				source_kind,
				source_version,
				current_version,
				next_version,
				merged_diagnostics,
				failed_metadata
			)

		var step_result: Variant = first
		current = (step_result.payload as Dictionary).duplicate(true)
		_merge_metadata(merged_metadata, step_result.metadata)
		for diagnostic: Dictionary in step_result.diagnostics:
			merged_diagnostics.append(diagnostic.duplicate(true))
		current_version = next_version

	merged_metadata["source_kind"] = source_kind
	merged_metadata["migrated_from"] = source_version
	merged_metadata["migrated_to"] = current_version
	merged_metadata["player_notice_required"] = false
	return SaveResultScript.success(current, merged_metadata, merged_diagnostics)


func _validate_step_results(first: Variant, second: Variant, from_version: int, to_version: int):
	var step_metadata := {
		"from_version": from_version,
		"to_version": to_version,
	}
	if not _is_save_result(first) or not _is_save_result(second):
		step_metadata["reason"] = "migration_did_not_return_save_result"
		return SaveResultScript.failure(&"MIGRATION_FAILED", step_metadata)
	var first_result: Variant = first
	var second_result: Variant = second
	if not first_result.ok or not second_result.ok:
		step_metadata["reason"] = "migration_step_rejected_input"
		step_metadata["first_code"] = str(first_result.code)
		step_metadata["second_code"] = str(second_result.code)
		return SaveResultScript.failure(&"MIGRATION_FAILED", step_metadata)
	if not first_result.payload is Dictionary or not second_result.payload is Dictionary:
		step_metadata["reason"] = "migration_output_must_be_dictionary"
		return SaveResultScript.failure(&"MIGRATION_FAILED", step_metadata)
	if not _has_exact_schema_version(first_result.payload, to_version):
		step_metadata["reason"] = "migration_output_has_wrong_schema_version"
		return SaveResultScript.failure(&"MIGRATION_FAILED", step_metadata)
	if first_result.to_dictionary() != second_result.to_dictionary():
		step_metadata["reason"] = "migration_is_not_deterministic"
		return SaveResultScript.failure(&"MIGRATION_FAILED", step_metadata)
	return SaveResultScript.success({}, step_metadata)


func _is_save_result(value: Variant) -> bool:
	return (
		value is RefCounted
		and (value as RefCounted).has_method("to_dictionary")
		and "ok" in value
		and "code" in value
		and "payload" in value
		and "metadata" in value
		and "diagnostics" in value
	)


func _source_version(document: Dictionary) -> Dictionary:
	if document.has("schema_version"):
		if not _is_nonnegative_integer(document["schema_version"]):
			return {"valid": false, "reason": "invalid_schema_version"}
		var version := int(document["schema_version"])
		return {
			"valid": true,
			"version": version,
			"source_kind": "schema_v%d" % version,
		}
	if _is_legacy_v0(document):
		return {
			"valid": true,
			"version": 0,
			"source_kind": "legacy_v0",
		}
	return {"valid": false, "reason": "unrecognized_save_format"}


func _is_legacy_v0(document: Dictionary) -> bool:
	return (
		not document.has("magic")
		and _is_nonnegative_integer(document.get("version"))
		and int(document.get("version", 0)) == 1
		and document.get("persistent") is Dictionary
	)


func _has_exact_schema_version(document: Dictionary, expected: int) -> bool:
	return (
		document.has("schema_version")
		and _is_nonnegative_integer(document["schema_version"])
		and int(document["schema_version"]) == expected
	)


func _is_nonnegative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return is_finite(number) and number >= 0.0 and number == floorf(number)
	return false


func _migration_failure(
	code: StringName,
	source_kind: StringName,
	migrated_from: int,
	from_version: int,
	to_version: int,
	diagnostics: Array[Dictionary],
	extra_metadata: Dictionary = {}
):
	var metadata := extra_metadata.duplicate(true)
	metadata["source_kind"] = source_kind
	metadata["migrated_from"] = migrated_from
	metadata["migrated_to"] = from_version
	metadata["from_version"] = from_version
	metadata["to_version"] = to_version
	metadata["player_notice_required"] = false
	return SaveResultScript.failure(code, metadata, diagnostics)


func _merge_metadata(destination: Dictionary, source: Dictionary) -> void:
	for key: Variant in source.keys():
		destination[key] = _deep_copy(source[key])


func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
