class_name CosmeticDefinition
extends RefCounted

const Rules := preload("res://scripts/progression/meta_progression_catalog.gd")
const CHARACTERS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
const ROUTES := ["default", "return", "victory"]
const FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "cosmetic_id", "character_id", "unlock_route", "atlas_path", "atlas_sha256"]
var _definition: Dictionary = {}


func configure(value: Dictionary) -> Dictionary:
	if not Rules.exact_fields(value, FIELDS) or value.category != "cosmetic_definition" or not Rules.bounded_int(value.schema_version, 1, 1) or value.character_id not in CHARACTERS or value.unlock_route not in ROUTES:
		return _failure(&"COSMETIC_DEFINITION_INVALID")
	var identity := "%s.%s" % [value.character_id, value.unlock_route]
	var path := "res://data/content_packs/base/assets/cosmetics/%s_%s.png" % [value.character_id, value.unlock_route]
	if value.cosmetic_id != identity or value.id != "cosmetic_" + identity.replace(".", "_") or value.availability != ["LAUNCH", "EXPANSION"] or value.tags != ["free", "appearance"] or not value.effects is Dictionary or not value.effects.is_empty() or not value.compatibility is Dictionary or not value.compatibility.is_empty() or value.atlas_path != path or not value.atlas_sha256 is String or value.atlas_sha256.length() != 64 or not value.atlas_sha256.is_valid_hex_number(false):
		return _failure(&"COSMETIC_DEFINITION_INVALID")
	for field: String in ["name_key", "description_key"]:
		if not value[field] is String or not value[field].begins_with("COSMETIC_") or not value[field].to_upper() == value[field]:
			return _failure(&"COSMETIC_LOCALIZATION_INVALID")
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != value.atlas_sha256:
		return _failure(&"COSMETIC_ASSET_INVALID")
	_definition = value.duplicate(true)
	return {"ok": true, "code": &"OK", "context": {}, "definition": snapshot()}


func snapshot() -> Dictionary:
	return _definition.duplicate(true)


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}, "definition": {}}
