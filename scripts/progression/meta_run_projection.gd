class_name MetaRunProjection
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const FIELDS := ["schema_id", "schema_version", "catalog_fingerprint", "profile_revision", "unlocked_nodes", "stat_bonuses", "direct_combat_budget", "forge_attack_bonuses", "options", "soul_retention", "hub_discount", "projection_digest"]


static func from_profile(profile: Dictionary, catalog: RefCounted) -> Dictionary:
	var validator = Profile.new()
	if not validator.configure(catalog, profile):
		return {"ok": false, "code": &"PROFILE_INVALID", "context": {}}
	return {"ok": true, "code": &"OK", "context": {"projection": _derive(validator.snapshot(), catalog)}}


static func validate(value: Dictionary, catalog: RefCounted = null) -> bool:
	if catalog == null:
		return false
	if not Catalog.exact_fields(value, FIELDS) or value.schema_id != "planewalker.meta_run_projection" or not Catalog.bounded_int(value.schema_version, 1, 1) or not Catalog.bounded_int(value.profile_revision, 0, Catalog.MAX_VALUE) or not Catalog.fingerprint_valid(value.catalog_fingerprint) or not Catalog.fingerprint_valid(value.projection_digest) or not Catalog.valid_stat_budget(value.stat_bonuses) or not Catalog.finite_number(value.direct_combat_budget, 0.0, 0.15) or not Catalog.finite_number(value.soul_retention, 0.3, 0.7) or not Catalog.finite_number(value.hub_discount, 0.0, 0.1):
		return false
	if not _sorted_ids(value.unlocked_nodes) or not _sorted_ids(value.options) or not Catalog.exact_fields(value.forge_attack_bonuses, Catalog.WEAPON_IDS):
		return false
	var total := 0.0
	for stat: String in Catalog.STAT_IDS:
		if not _percent_exact(value.stat_bonuses[stat]):
			return false
		total += float(value.stat_bonuses[stat])
	if not _percent_exact(value.direct_combat_budget) or not _percent_exact(value.soul_retention) or not _percent_exact(value.hub_discount) or absf(total - float(value.direct_combat_budget)) > 0.000000000001 or value.projection_digest != digest(value):
		return false
	for weapon: String in Catalog.WEAPON_IDS:
		if not Catalog.finite_number(value.forge_attack_bonuses[weapon], 0.0, 0.05) or not _percent_exact(value.forge_attack_bonuses[weapon]):
			return false
	if catalog != null:
		var state = Profile.new()
		if not state.configure(catalog) or catalog.call("fingerprint") != value.catalog_fingerprint:
			return false
		var profile: Dictionary = state.snapshot()
		profile.revision = int(value.profile_revision)
		profile.unlocked_nodes = value.unlocked_nodes.duplicate()
		for weapon: String in Catalog.WEAPON_IDS:
			profile.forge_state[weapon].level = int(roundf(float(value.forge_attack_bonuses[weapon]) * 100.0))
		if not state.restore_snapshot(profile) or _derive(state.snapshot(), catalog).projection_digest != value.projection_digest:
			return false
	return true


static func validate_combined(value: Dictionary, character_bonuses: Dictionary, weapon_id: String, catalog: RefCounted = null) -> bool:
	if not validate(value, catalog) or weapon_id not in Catalog.WEAPON_IDS:
		return false
	var caps := {"max_hp": 0.20, "attack": 0.15, "defense": 0.15, "speed": 0.08, "attack_speed": 0.0}
	for stat: Variant in character_bonuses:
		if not caps.has(stat) or not Catalog.finite_number(character_bonuses[stat], 0.0, caps[stat]):
			return false
	for stat: String in caps:
		var multiplier := (1.0 + float(character_bonuses.get(stat, 0.0))) * (1.0 + float(value.stat_bonuses[stat]))
		if stat == "attack":
			multiplier *= 1.0 + float(value.forge_attack_bonuses[weapon_id])
		var combined := multiplier - 1.0 + float(value.stat_bonuses.entrance_healing) + float(value.stat_bonuses.void_reduction)
		if combined > 0.30 + 0.000000001:
			return false
	return true


static func digest(value: Dictionary) -> String:
	var unsigned := value.duplicate(true)
	unsigned.erase("projection_digest")
	# Hash authored whole percentages and integer counters independently of JSON float spelling.
	for field: String in ["schema_version", "profile_revision"]:
		if unsigned.has(field):
			unsigned[field] = int(unsigned[field])
	for field: String in ["stat_bonuses", "forge_attack_bonuses"]:
		if unsigned.get(field) is Dictionary:
			for key: Variant in unsigned[field]:
				unsigned[field][key] = int(roundf(float(unsigned[field][key]) * 100.0))
	for field: String in ["direct_combat_budget", "soul_retention", "hub_discount"]:
		if unsigned.has(field):
			unsigned[field] = int(roundf(float(unsigned[field]) * 100.0))
	return JSON.stringify(unsigned, "", true, true).sha256_text()


static func _percent_exact(value: Variant) -> bool:
	return absf(float(value) * 100.0 - roundf(float(value) * 100.0)) <= 0.000000000001


static func _derive(profile: Dictionary, catalog: RefCounted) -> Dictionary:
	var value := {"schema_id": "planewalker.meta_run_projection", "schema_version": 1, "catalog_fingerprint": catalog.call("fingerprint"), "profile_revision": profile.revision, "unlocked_nodes": profile.unlocked_nodes.duplicate(), "stat_bonuses": Catalog.empty_stat_bonuses(), "direct_combat_budget": 0.0, "forge_attack_bonuses": {}, "options": [], "soul_retention": 0.3, "hub_discount": 0.0}
	for id: String in profile.unlocked_nodes:
		var definition: Dictionary = catalog.call("definition", StringName(id))
		for effect: Dictionary in definition.effects:
			match effect.kind:
				"stat_bonus": value.stat_bonuses[effect.stat] += float(effect.magnitude)
				"option":
					if not value.options.has(effect.option_id):
						value.options.append(effect.option_id)
				"soul_retention": value.soul_retention = maxf(value.soul_retention, float(effect.value))
				"hub_discount": value.hub_discount = maxf(value.hub_discount, float(effect.value))
	for stat: String in Catalog.STAT_IDS:
		value.direct_combat_budget += float(value.stat_bonuses[stat])
	for weapon: String in Catalog.WEAPON_IDS:
		value.forge_attack_bonuses[weapon] = int(profile.forge_state[weapon].level) * 0.01
	value.options.sort()
	value.projection_digest = digest(value)
	return value


static func _sorted_ids(value: Variant) -> bool:
	if not value is Array or value.size() > 4096:
		return false
	var previous := ""
	for id: Variant in value:
		if not Catalog.stable_id(id) or not previous.is_empty() and previous >= str(id):
			return false
		previous = id
	return true
