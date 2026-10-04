class_name ProfileCommandCandidate
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")


static func validate(profile: Dictionary, catalog: RefCounted, command: Dictionary, fields: Array, expected_revision: int) -> Dictionary:
	var validator := Profile.new()
	if profile.is_empty() or catalog == null or not validator.configure(catalog, profile):
		return failure(&"PROFILE_INVALID")
	if expected_revision != profile.revision:
		return failure(&"STALE_REVISION")
	if not Catalog.exact_fields(command, fields) or not Catalog.stable_id(command.command_id):
		return failure(&"COMMAND_INVALID")
	for prefix: String in Profile.RESERVED_COMMAND_PREFIXES:
		if str(command.command_id).begins_with(prefix):
			return failure(&"RESERVED_COMMAND_ID")
	if profile.completed_command_ids.has(command.command_id):
		return failure(&"DUPLICATE_COMMAND")
	if profile.completed_command_ids.size() >= Profile.MAX_HISTORY or profile.revision == Catalog.MAX_VALUE:
		return failure(&"TRANSACTION_LIMIT")
	return success()


static func finish(candidate: Dictionary, catalog: RefCounted, command_id: String, context: Dictionary = {}) -> Dictionary:
	candidate.completed_command_ids.append(command_id)
	candidate.completed_command_ids.sort()
	candidate.revision += 1
	var validator := Profile.new()
	if not validator.configure(catalog, candidate):
		return failure(&"CANDIDATE_INVALID")
	var result := context.duplicate(true)
	result.candidate = validator.snapshot()
	return success(result)


static func success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context}
