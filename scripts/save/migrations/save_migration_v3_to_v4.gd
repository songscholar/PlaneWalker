class_name SaveMigrationV3ToV4
extends RefCounted

const ResultScript := preload("res://scripts/save/save_result.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Compatibility := preload("res://scripts/progression/meta_profile_compatibility.gd")


func migrate(document: Dictionary, context: Dictionary = {}):
	if document.get("schema_version") != 3 or document.get("document_kind") != "profile" or not context.get("meta_catalog") is RefCounted:
		return ResultScript.failure(&"MIGRATION_FAILED", {"reason": "meta_profile_context_required"})
	var authenticated = Envelope.validate(document, &"profile")
	if not authenticated.ok:
		return ResultScript.failure(&"MIGRATION_FAILED", {"reason": "source_authentication_failed"})
	var imported: Dictionary = Compatibility.from_legacy(authenticated.payload.payload, context.meta_catalog)
	if not imported.ok:
		return ResultScript.failure(&"MIGRATION_FAILED", {"reason": str(imported.code)})
	var migrated: Dictionary = authenticated.payload.duplicate(true)
	migrated.schema_version = 4
	migrated.payload = imported.context.payload
	return ResultScript.success(migrated, {"meta_profile_imported": true})
