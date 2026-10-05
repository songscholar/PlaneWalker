class_name HubViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const Config := preload("res://scripts/application/run_config.gd")
const Cosmetic := preload("res://scripts/content/cosmetic_definition.gd")
const FIELDS := ["schema_version", "revision", "epoch", "run_id", "district_id", "panel_id", "function_id", "currencies", "repair_stage", "districts", "functions", "nodes", "forge", "builds", "loadout", "dialogue", "collections", "cosmetics", "providers", "launch_available", "launch_reason_key", "resume_available", "resume_reason_key"]


static func validate(value: Variant):
	if not Rules.exact(value, FIELDS) or value.schema_version != 1 or not Rules.integer(value.schema_version) or not _number(value.revision) or not _number(value.epoch) or not _optional_id(value.run_id) or not Rules.identifier(value.district_id) or not _optional_id(value.panel_id) or not _optional_id(value.function_id) or not _cost(value.currencies) or not _number(value.repair_stage) or value.repair_stage > 3:
		return Rules.reject(value, "header")
	if not _rows(value.districts, ["id", "name_key", "current", "scene_path", "available", "reason_key", "cost"], "district") or value.districts.size() != 3 or not _rows(value.functions, ["id", "name_key", "district_id", "npc_id", "panel_id", "available", "reason_key", "cost"], "function") or value.functions.size() != 3:
		return Rules.reject(value, "destinations")
	if not _rows(value.nodes, ["id", "name_key", "description_key", "branch", "owned", "prerequisites", "available", "reason_key", "cost"], "node") or not _forge(value.forge) or not _rows(value.builds, ["id", "name", "character_id", "weapon_id", "time_abilities", "available", "reason_key", "cost", "remove"], "build") or not _loadout(value.loadout):
		return Rules.reject(value, "progression")
	if not _dialogue(value.dialogue) or not Rules.exact(value.collections, ["archive", "gallery", "mirror"]):
		return Rules.reject(value, "narrative")
	for collection: String in ["archive", "gallery", "mirror"]:
		if not _rows(value.collections[collection], ["id", "name_key", "owned", "available", "reason_key", "cost"], "collection"):
			return Rules.reject(value, "collections")
	if not _cosmetics(value.cosmetics):
		return Rules.reject(value, "cosmetics")
	if not _rows(value.providers, ["id", "status", "entries", "available", "reason_key", "cost"], "provider") or value.providers.size() != 3 or not _availability({"available": value.launch_available, "reason_key": value.launch_reason_key, "cost": {"chronos_shards": 0, "existential_imprints": 0}}):
		return Rules.reject(value, "providers")
	if not _availability({"available": value.resume_available, "reason_key": value.resume_reason_key, "cost": {"chronos_shards": 0, "existential_imprints": 0}}) or value.resume_available and (value.run_id.is_empty() or value.launch_available):
		return Rules.reject(value, "continuation")
	return Rules.accept(value)


static func _cosmetics(value: Variant) -> bool:
	if not value is Array or value.size() != 15:
		return false
	var ids: Array = []
	for row: Variant in value:
		if not Rules.exact(row, ["id", "character_id", "name_key", "description_key", "atlas_path", "owned", "equipped", "operation", "available", "reason_key", "cost"]) or row.character_id not in Cosmetic.CHARACTERS or not Rules.key(row.name_key) or not Rules.key(row.description_key) or typeof(row.owned) != TYPE_BOOL or typeof(row.equipped) != TYPE_BOOL or not _availability(row) or row.cost.chronos_shards != 0 or row.cost.existential_imprints != 0:
			return false
		var route := ""
		for candidate: String in Cosmetic.ROUTES:
			if row.id == row.character_id + "." + candidate:
				route = candidate
		if route.is_empty() or ids.has(row.id) or row.atlas_path != "res://data/content_packs/base/assets/cosmetics/%s_%s.png" % [row.character_id, route] or row.operation != ("cosmetic_equip" if row.owned else "cosmetic_claim") or row.equipped and (not row.owned or row.available):
			return false
		ids.append(row.id)
	return true


static func _rows(value: Variant, fields: Array, kind: String) -> bool:
	if not value is Array:
		return false
	var ids: Array = []
	for row: Variant in value:
		if not Rules.exact(row, fields) or not Rules.identifier(row.id) or ids.has(row.id) or not _availability(row):
			return false
		ids.append(row.id)
		if row.has("name_key") and not Rules.key(row.name_key) or row.has("description_key") and not Rules.key(row.description_key):
			return false
		match kind:
			"district":
				if typeof(row.current) != TYPE_BOOL or row.scene_path != "res://scenes/hub/%s.tscn" % row.id:
					return false
			"function":
				if not Rules.identifier(row.npc_id) or not Rules.identifier(row.panel_id) or not Rules.identifier(row.district_id):
					return false
			"node":
				if typeof(row.owned) != TYPE_BOOL or not Rules.identifier(row.branch) or not _ids(row.prerequisites):
					return false
			"build":
				if not _text(row.name, 64) or not Rules.identifier(row.character_id) or not Rules.identifier(row.weapon_id) or not _ids(row.time_abilities) or row.time_abilities.size() != 2 or not Rules.exact(row.remove, ["available", "reason_key", "cost"]) or not _availability(row.remove):
					return false
			"collection":
				if typeof(row.owned) != TYPE_BOOL:
					return false
			"provider":
				if row.id not in ["daily", "leaderboard", "social"] or row.status not in ["AVAILABLE", "UNAVAILABLE"] or row.available != (row.status == "AVAILABLE") or not row.entries is Array:
					return false
				var seen: Array = []
				for entry: Variant in row.entries:
					if not Rules.exact(entry, ["id", "name", "score"]) or not Rules.identifier(entry.id) or seen.has(entry.id) or not _text(entry.name, 96) or not _number(entry.score):
						return false
					seen.append(entry.id)
				if not row.available and not row.entries.is_empty():
					return false
	return true


static func _forge(value: Variant) -> bool:
	if not Rules.exact(value, ["weapons"]) or not value.weapons is Array:
		return false
	var ids: Array = []
	for row: Variant in value.weapons:
		if not Rules.exact(row, ["id", "name_key", "level", "attack_bonus", "enchant_preferences", "void_tempered", "upgrade", "enchantments", "temper_options"]) or not Rules.identifier(row.id) or ids.has(row.id) or not Rules.key(row.name_key) or not _number(row.level) or row.level > 5 or typeof(row.attack_bonus) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(row.attack_bonus)) or row.attack_bonus < 0 or not _ids(row.enchant_preferences) or typeof(row.void_tempered) != TYPE_BOOL or not Rules.exact(row.upgrade, ["available", "reason_key", "cost"]) or not _availability(row.upgrade):
			return false
		ids.append(row.id)
		if not _rows(row.enchantments, ["id", "name_key", "selected", "available", "reason_key", "cost"], "enchantment") or not _enchantments(row.enchantments) or not row.temper_options is Array or row.temper_options.size() != 2:
			return false
		var currencies: Array = []
		for temper: Variant in row.temper_options:
			if not Rules.exact(temper, ["currency", "available", "reason_key", "cost"]) or temper.currency not in ["chronos_shards", "existential_imprints"] or currencies.has(temper.currency) or not _availability(temper):
				return false
			currencies.append(temper.currency)
	return true


static func _enchantments(value: Array) -> bool:
	for row: Dictionary in value:
		if typeof(row.selected) != TYPE_BOOL:
			return false
	return true


static func _loadout(value: Variant) -> bool:
	if not Rules.exact(value, ["selected", "characters", "weapons", "time_pairs", "build_save"]) or not Rules.exact(value.selected, Config.DEFAULTS.keys()) or value.selected.milestone != "LAUNCH" or not Config.validate(value.selected).ok or not Rules.exact(value.build_save, ["available", "reason_key", "cost"]) or not _availability(value.build_save):
		return false
	if not _rows(value.characters, ["id", "name_key", "available", "reason_key", "cost"], "loadout") or not _rows(value.weapons, ["id", "name_key", "available", "reason_key", "cost"], "loadout") or not value.time_pairs is Array:
		return false
	var ids: Array = []
	for row: Variant in value.time_pairs:
		if not Rules.exact(row, ["id", "ability_ids", "name_keys", "available", "reason_key", "cost"]) or not row.id is String or row.id.is_empty() or ids.has(row.id) or not _ids(row.ability_ids) or row.ability_ids.size() != 2 or not row.name_keys is Array or row.name_keys.size() != 2 or not _availability(row):
			return false
		ids.append(row.id)
		for key: Variant in row.name_keys:
			if not Rules.key(key):
				return false
	return true


static func _dialogue(value: Variant) -> bool:
	if not Rules.exact(value, ["npc_id", "affinity", "nodes"]) or not _optional_id(value.npc_id) or not _number(value.affinity) or not value.nodes is Array:
		return false
	var ids: Array = []
	for row: Variant in value.nodes:
		if not Rules.exact(row, ["id", "text_key", "consumed", "choices", "available", "reason_key", "cost"]) or not Rules.identifier(row.id) or ids.has(row.id) or not Rules.key(row.text_key) or typeof(row.consumed) != TYPE_BOOL or not _availability(row) or not row.choices is Array:
			return false
		ids.append(row.id)
		var choices: Array = []
		for choice: Variant in row.choices:
			if not Rules.exact(choice, ["id", "text_key", "available", "reason_key", "cost"]) or not Rules.identifier(choice.id) or choices.has(choice.id) or not Rules.key(choice.text_key) or not _availability(choice):
				return false
			choices.append(choice.id)
	return true


static func _availability(row: Dictionary) -> bool:
	return typeof(row.get("available")) == TYPE_BOOL and Rules.key(row.get("reason_key"), row.get("available", false)) and (not row.available or row.reason_key.is_empty()) and _cost(row.get("cost"))


static func _cost(value: Variant) -> bool:
	return Rules.exact(value, ["chronos_shards", "existential_imprints"]) and _number(value.chronos_shards) and _number(value.existential_imprints)


static func _number(value: Variant) -> bool:
	return Rules.integer(value) and value >= 0 and value <= 2147483647


static func _ids(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Array = []
	for id: Variant in value:
		if not Rules.identifier(id) or seen.has(id):
			return false
		seen.append(id)
	return true


static func _optional_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (value.is_empty() or Rules.identifier(value))


static func _text(value: Variant, limit: int) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty() and value.length() <= limit and not value.to_utf8_buffer().has(0)
