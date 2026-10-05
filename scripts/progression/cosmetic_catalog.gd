class_name CosmeticCatalog
extends RefCounted

const Definition := preload("res://scripts/content/cosmetic_definition.gd")
const Rules := preload("res://scripts/progression/meta_progression_catalog.gd")
const SOURCE := "res://data/content_packs/base/content/cosmetics.json"
const COLLECTION_FIELDS := ["schema_id", "schema_version", "catalog_fingerprint", "claimed_ids", "equipped_by_character"]
var _definitions: Dictionary = {}
var _fingerprint := ""


static func load_base() -> RefCounted:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var catalog: RefCounted = load("res://scripts/progression/cosmetic_catalog.gd").new()
	return catalog if rows is Array and catalog.configure(rows).ok else null


func configure(rows: Array) -> Dictionary:
	var definitions: Dictionary = {}
	for value: Variant in rows:
		if not value is Dictionary:
			return _failure(&"COSMETIC_DEFINITION_INVALID")
		var parser := Definition.new()
		if not parser.configure(value).ok or definitions.has(value.cosmetic_id):
			return _failure(&"COSMETIC_DEFINITION_INVALID")
		definitions[value.cosmetic_id] = parser.snapshot()
	if definitions.size() != 15:
		return _failure(&"COSMETIC_CATALOG_INCOMPLETE")
	for character: String in Definition.CHARACTERS:
		for route: String in Definition.ROUTES:
			if not definitions.has(character + "." + route):
				return _failure(&"COSMETIC_CATALOG_INCOMPLETE")
	_definitions = definitions
	_fingerprint = JSON.stringify(_definitions, "", true, true).sha256_text()
	return _success()


func fingerprint() -> String:
	return _fingerprint


func ids() -> Array:
	var value: Array = _definitions.keys()
	value.sort()
	return value


func definition(id: String) -> Dictionary:
	return _definitions.get(id, {}).duplicate(true)


func for_character(character_id: String) -> Array:
	var rows: Array = []
	for route: String in Definition.ROUTES:
		var row := definition(character_id + "." + route)
		if not row.is_empty():
			rows.append(row)
	return rows


func empty_collection() -> Dictionary:
	return {"schema_id": "cosmetic_collection_v1", "schema_version": 1, "catalog_fingerprint": _fingerprint, "claimed_ids": [], "equipped_by_character": {}}


func unlock_status(id: String, profile: Dictionary) -> Dictionary:
	var row := definition(id)
	if row.is_empty():
		return _failure(&"COSMETIC_UNKNOWN")
	if not profile.get("unlocked_characters", []).has(row.character_id):
		return _failure(&"COSMETIC_CHARACTER_LOCKED")
	if row.unlock_route == "return" and profile.get("statistics", {}).get("finished_runs", 0) < 1:
		return _failure(&"COSMETIC_RETURN_REQUIRED")
	if row.unlock_route == "victory" and profile.get("statistics", {}).get("victories", 0) < 1:
		return _failure(&"COSMETIC_VICTORY_REQUIRED")
	return _success()


func validate_collection(value: Variant, profile: Dictionary) -> bool:
	if _fingerprint.is_empty() or not Rules.exact_fields(value, COLLECTION_FIELDS) or value.schema_id != "cosmetic_collection_v1" or not Rules.bounded_int(value.schema_version, 1, 1) or value.catalog_fingerprint != _fingerprint or not value.claimed_ids is Array or not value.equipped_by_character is Dictionary:
		return false
	var seen: Array = []
	for id: Variant in value.claimed_ids:
		if not id is String or seen.has(id) or not unlock_status(id, profile).ok or definition(id).unlock_route == "default":
			return false
		seen.append(id)
	seen.sort()
	if seen != value.claimed_ids:
		return false
	for character: Variant in value.equipped_by_character:
		var id: Variant = value.equipped_by_character[character]
		if character not in Definition.CHARACTERS or not id is String or not unlock_status(id, profile).ok or definition(id).character_id != character or definition(id).unlock_route != "default" and not value.claimed_ids.has(id):
			return false
	return true


func equipped(value: Dictionary, character_id: String) -> String:
	return str(value.get("equipped_by_character", {}).get(character_id, character_id + ".default")) if character_id in Definition.CHARACTERS else ""


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
