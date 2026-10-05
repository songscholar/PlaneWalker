class_name CosmeticCollectionRuntime
extends RefCounted

const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
var _cosmetics: RefCounted
var _meta: RefCounted


func configure(cosmetics: RefCounted, meta: RefCounted) -> bool:
	if cosmetics == null or cosmetics.fingerprint().is_empty() or meta == null:
		return false
	_cosmetics = cosmetics
	_meta = meta
	return true


func prepare(profile: Dictionary, collection: Dictionary, command: Dictionary, expected_revision: int) -> Dictionary:
	var valid := Candidate.validate(profile, _meta, command, ["command_id", "kind", "cosmetic_id"], expected_revision)
	if not valid.ok:
		return valid
	if not _cosmetics.validate_collection(collection, profile):
		return Candidate.failure(&"COSMETIC_COLLECTION_INVALID")
	if not profile.active_launch_receipt.is_empty():
		return Candidate.failure(&"LAUNCH_ACTIVE")
	if command.kind not in ["cosmetic_claim", "cosmetic_equip"] or not command.cosmetic_id is String:
		return Candidate.failure(&"COMMAND_INVALID")
	var unlocked: Dictionary = _cosmetics.unlock_status(command.cosmetic_id, profile)
	if not unlocked.ok:
		return unlocked
	var row: Dictionary = _cosmetics.definition(command.cosmetic_id)
	var owned: bool = row.unlock_route == "default" or collection.claimed_ids.has(command.cosmetic_id)
	var next := collection.duplicate(true)
	if command.kind == "cosmetic_claim":
		if owned:
			return Candidate.failure(&"COSMETIC_ALREADY_OWNED")
		next.claimed_ids.append(command.cosmetic_id)
		next.claimed_ids.sort()
	else:
		if not owned:
			return Candidate.failure(&"COSMETIC_NOT_OWNED")
		if _cosmetics.equipped(collection, row.character_id) == command.cosmetic_id:
			return Candidate.failure(&"NO_CHANGE")
		next.equipped_by_character[row.character_id] = command.cosmetic_id
	return Candidate.finish(profile.duplicate(true), _meta, command.command_id, {"collection": next, "cosmetic_id": command.cosmetic_id})
