extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const CharacterProfile := preload("res://scripts/player/characters/character_runtime_profile.gd")
const SOURCE := "res://assets/production/modes/challenge_rewards.json"
const IDS := ["walker_proof", "speedwalker_boots", "walker_entry", "eternal_walker", "void_walker", "daily_participation_frame", "daily_walker_frame", "eternal_traveler", "daily_weapon_skin", "daily_character_color", "daily_archive_decoration"]
var _rows: Dictionary = {}
var _fingerprint := ""
var _mobility_profiles: Dictionary = {}
static var _canonical_catalog: RefCounted


func configure() -> bool:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not Meta.exact_fields(value, ["schema_version", "collection_id", "rewards"]) or value.schema_version != 1 or value.collection_id != "planewalker.challenge_rewards.v1" or not value.rewards is Array or value.rewards.size() != IDS.size():
		return false
	var rows := {}
	for row: Variant in value.rewards:
		if not Meta.exact_fields(row, ["id", "kind", "name_key", "tint", "effects"]) or row.id not in IDS or rows.has(row.id) or row.kind not in ["item", "cosmetic", "frame", "title", "weapon_cosmetic", "decoration"] or not row.name_key is String or not row.name_key.begins_with("UI_") or not row.tint is Array or not row.effects is Dictionary:
			return false
		if row.kind in ["cosmetic", "weapon_cosmetic"]:
			if row.tint.size() != 4:
				return false
			for channel: Variant in row.tint:
				if not channel is float and not channel is int or not is_finite(float(channel)) or channel < 0 or channel > 1:
					return false
		elif not row.tint.is_empty():
			return false
		if row.id == "walker_proof" and not Rules.same(row.effects, {"boss_damage_multiplier": 1.15}) or row.id == "speedwalker_boots" and not Rules.same(row.effects, {"move_speed_multiplier": 1.15, "dash_speed_multiplier": 1.2}) or row.kind != "item" and not row.effects.is_empty():
			return false
		rows[row.id] = row.duplicate(true)
	var profiles: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/character_runtime_profiles.json"))
	if not profiles is Array:
		return false
	var mobility_profiles := {}
	for profile: Variant in profiles:
		if not profile is Dictionary or not CharacterProfile.new().configure(profile).ok or mobility_profiles.has(profile.id):
			return false
		mobility_profiles[profile.id] = profile.mobility.duplicate(true)
	_rows = rows
	_fingerprint = Rules.canonical(value).sha256_text()
	_mobility_profiles = mobility_profiles
	return true


static func canonical() -> RefCounted:
	if _canonical_catalog == null:
		var candidate: RefCounted = load("res://scripts/progression/challenge_reward_catalog.gd").new()
		if not candidate.configure():
			return null
		_canonical_catalog = candidate
	return _canonical_catalog


func projected_mobility(profile_id: String, projection_value: Dictionary) -> Dictionary:
	if not valid_projection(projection_value) or not _mobility_profiles.has(profile_id) or profile_id == "wanderer_m1_v1":
		return {}
	var result: Dictionary = _mobility_profiles[profile_id].duplicate(true)
	result.dash_speed = float(result.dash_speed) * float(projection_value.modifiers.dash_speed_multiplier)
	return result


func fingerprint() -> String:
	return _fingerprint


func definition(id: String) -> Dictionary:
	return _rows.get(id, {}).duplicate(true)


func empty_collection() -> Dictionary:
	return {"schema_version": 1, "catalog_fingerprint": _fingerprint, "owned_ids": [], "equipped_ids": [], "source_receipts": []}


func valid_collection(value: Variant) -> bool:
	if not Meta.exact_fields(value, empty_collection().keys()) or value.schema_version != 1 or value.catalog_fingerprint != _fingerprint or not _ids(value.owned_ids) or not _ids(value.equipped_ids) or value.equipped_ids.size() > 7 or not value.source_receipts is Array or value.source_receipts.size() > 2:
		return false
	var kinds := {}
	for id: String in value.equipped_ids:
		if not value.owned_ids.has(id):
			return false
		var kind: String = _rows[id].kind
		if kind != "item" and kinds.has(kind):
			return false
		kinds[kind] = true
	var seen := {}
	for row: Variant in value.source_receipts:
		if not Meta.exact_fields(row, ["mode_id", "source_id", "source_digest", "owned_ids"]) or row.mode_id not in ["boss_rush_carried", "daily_boss"] or not row.source_id is String or row.source_id.length() > 256 or not Meta.fingerprint_valid(row.source_digest) or seen.has(row.mode_id) or not _ids(row.owned_ids):
			return false
		seen[row.mode_id] = true
	var union: Array[String] = []
	for row: Dictionary in value.source_receipts:
		for id: String in row.owned_ids:
			if not union.has(id):
				union.append(id)
	union.sort()
	return Rules.same(union, value.owned_ids)


func projection(collection: Dictionary, identity: Dictionary) -> Dictionary:
	if not valid_collection(collection) or not Meta.exact_fields(identity, ["profile_id", "save_domain", "content_snapshot"]) or not Paths.validate_id(identity.profile_id).ok or not Paths.validate_id(identity.save_domain).ok or not identity.content_snapshot is Dictionary or not Envelope._content_snapshot_error(identity.content_snapshot).is_empty():
		return {}
	var modifiers := {"boss_damage_multiplier": 1.0, "move_speed_multiplier": 1.0, "dash_speed_multiplier": 1.0}
	var presentation := {"character_cosmetic_id": "", "tint": [], "weapon_cosmetic_id": "", "weapon_tint": [], "frame_id": "", "title_id": "", "decoration_id": ""}
	for id: String in collection.equipped_ids:
		var row: Dictionary = _rows[id]
		if row.kind == "item":
			modifiers.merge(row.effects, true)
		elif row.kind == "cosmetic":
			presentation.character_cosmetic_id = id
			presentation.tint = row.tint.duplicate()
		elif row.kind == "weapon_cosmetic":
			presentation.weapon_cosmetic_id = id
			presentation.weapon_tint = row.tint.duplicate()
		else:
			presentation[row.kind + "_id"] = id
	var result := {"schema_id": "planewalker.challenge_reward_projection", "schema_version": 1, "catalog_fingerprint": _fingerprint, "profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot.duplicate(true), "collection": collection.duplicate(true), "modifiers": modifiers, "presentation": presentation}
	result["digest"] = Rules.canonical(result).sha256_text()
	return result


func valid_projection(value: Variant) -> bool:
	if not Meta.exact_fields(value, ["schema_id", "schema_version", "catalog_fingerprint", "profile_id", "save_domain", "content_snapshot", "collection", "modifiers", "presentation", "digest"]) or not value.profile_id is String or not value.save_domain is String or not value.content_snapshot is Dictionary or not value.collection is Dictionary:
		return false
	var expected := projection(value.collection, {"profile_id": value.profile_id, "save_domain": value.save_domain, "content_snapshot": value.content_snapshot})
	return not expected.is_empty() and Rules.same(value, expected)


func _ids(value: Variant) -> bool:
	if not value is Array or value.size() > IDS.size():
		return false
	var seen := {}
	for id: Variant in value:
		if not id is String or not _rows.has(id) or seen.has(id):
			return false
		seen[id] = true
	return true
