class_name ForgeRuntime
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const COMMON_FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "definition_kind"]
const WEAPON_FIELDS := ["weapon_id", "levels", "proficiency_thresholds", "enchantment_ids", "void_temper_costs", "maximum_enchantments", "required_node_id"]
const ENCHANT_FIELDS := ["enchantment_id", "preference_tags", "exclusive_group", "unlock_cost", "required_node_id", "training_action_id", "effect_policy"]
const UNLOCK_PREFIX := "forge-enchant-unlock:"

var _catalog: RefCounted
var _weapons: Dictionary = {}
var _enchantments: Dictionary = {}


func configure(entries: Array, catalog: RefCounted) -> Dictionary:
	_catalog = null
	_weapons.clear()
	_enchantments.clear()
	var validator := Profile.new()
	if not validator.configure(catalog) or entries.size() != 20:
		return Candidate.failure(&"CONTENT_INVALID")
	var weapons: Dictionary = {}
	var enchantments: Dictionary = {}
	for row: Variant in entries:
		if not row is Dictionary or not _common_valid(row):
			return Candidate.failure(&"CONTENT_INVALID")
		if row.definition_kind == "weapon":
			if not Catalog.exact_fields(row, COMMON_FIELDS + WEAPON_FIELDS) or not _weapon_valid(row) or weapons.has(row.weapon_id):
				return Candidate.failure(&"WEAPON_DEFINITION_INVALID", {"id": row.get("id")})
			weapons[row.weapon_id] = row.duplicate(true)
		elif row.definition_kind == "enchantment":
			if not Catalog.exact_fields(row, COMMON_FIELDS + ENCHANT_FIELDS) or not _enchantment_valid(row, catalog) or enchantments.has(row.enchantment_id):
				return Candidate.failure(&"ENCHANTMENT_DEFINITION_INVALID", {"id": row.get("id")})
			enchantments[row.enchantment_id] = row.duplicate(true)
		else:
			return Candidate.failure(&"CONTENT_INVALID")
	if weapons.size() != 5 or enchantments.size() != 15:
		return Candidate.failure(&"CONTENT_COUNT_INVALID")
	for row: Dictionary in weapons.values():
		if row.enchantment_ids.size() != enchantments.size():
			return Candidate.failure(&"ENCHANTMENT_REFERENCE_INVALID")
		for id: Variant in row.enchantment_ids:
			if not enchantments.has(id):
				return Candidate.failure(&"ENCHANTMENT_REFERENCE_INVALID")
	_catalog = catalog
	_weapons = weapons
	_enchantments = enchantments
	return Candidate.success()


func prepare_command(profile: Dictionary, command: Dictionary, expected_revision: int) -> Dictionary:
	if _catalog == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var fields: Array = {
		"forge_upgrade": ["command_id", "kind", "weapon_id"],
		"enchant_preference": ["command_id", "kind", "weapon_id", "enchantment_ids"],
		"void_temper": ["command_id", "kind", "weapon_id", "payment_currency"],
	}.get(command.get("kind"), [])
	if fields.is_empty():
		return Candidate.failure(&"COMMAND_INVALID")
	var valid := Candidate.validate(profile, _catalog, command, fields, expected_revision)
	if not valid.ok:
		return valid
	if not command.weapon_id is String or not _weapons.has(command.weapon_id) or not profile.unlocked_weapons.has(command.weapon_id):
		return Candidate.failure(&"WEAPON_LOCKED")
	var definition: Dictionary = _weapons[command.weapon_id]
	var candidate := profile.duplicate(true)
	var cost := {"chronos_shards": 0, "existential_imprints": 0}
	var forge: Dictionary = candidate.forge_state[command.weapon_id]
	match command.kind:
		"forge_upgrade":
			if not profile.unlocked_nodes.has(definition.required_node_id):
				return Candidate.failure(&"PREREQUISITE_MISSING")
			if forge.level >= definition.levels.size():
				return Candidate.failure(&"FORGE_MAX_LEVEL")
			cost = definition.levels[int(forge.level)].cost.duplicate(true)
			forge.level += 1
		"enchant_preference":
			var preferences: Variant = command.enchantment_ids
			var capacity := 2 if profile.unlocked_nodes.has("F-03") else (1 if profile.unlocked_nodes.has("F-02") else 0)
			if not preferences is Array or preferences.size() > capacity:
				return Candidate.failure(&"ENCHANTMENT_CAPACITY")
			var selected: Array = []
			var groups: Array = []
			for id: Variant in preferences:
				if not id is String or not _enchantments.has(id) or selected.has(id):
					return Candidate.failure(&"ENCHANTMENT_INVALID")
				var enchantment: Dictionary = _enchantments[id]
				if not profile.unlocked_nodes.has(enchantment.required_node_id):
					return Candidate.failure(&"PREREQUISITE_MISSING")
				if enchantment.exclusive_group != "none":
					if groups.has(enchantment.exclusive_group):
						return Candidate.failure(&"ENCHANTMENT_EXCLUSIVE")
					groups.append(enchantment.exclusive_group)
				selected.append(id)
				var unlock_source: String = UNLOCK_PREFIX + id
				if not profile.completed_command_ids.has(unlock_source):
					for currency: String in cost:
						cost[currency] += enchantment.unlock_cost[currency]
					candidate.completed_command_ids.append(unlock_source)
			selected.sort()
			if selected == forge.enchant_preferences:
				return Candidate.failure(&"NO_CHANGE")
			forge.enchant_preferences = selected
		"void_temper":
			if not profile.unlocked_nodes.has("F-04"):
				return Candidate.failure(&"PREREQUISITE_MISSING")
			if forge.void_tempered:
				return Candidate.failure(&"ALREADY_TEMPERED")
			if command.payment_currency not in ["chronos_shards", "existential_imprints"]:
				return Candidate.failure(&"PAYMENT_INVALID")
			cost = definition.void_temper_costs[0 if command.payment_currency == "chronos_shards" else 1].duplicate(true)
			forge.void_tempered = true
	for currency: String in cost:
		if profile[currency] < cost[currency]:
			return Candidate.failure(&"INSUFFICIENT_CURRENCY", {"currency": currency})
		candidate[currency] -= cost[currency]
	return Candidate.finish(candidate, _catalog, command.command_id, {"cost": cost, "weapon_id": command.weapon_id})


func weapon_projection(profile: Dictionary, weapon_id: String) -> Dictionary:
	var validator := Profile.new()
	if profile.is_empty() or _catalog == null or not _weapons.has(weapon_id) or not validator.configure(_catalog, profile):
		return {}
	var state: Dictionary = profile.forge_state[weapon_id]
	var bonus := 0.0
	for index: int in range(int(state.level)):
		bonus += float(_weapons[weapon_id].levels[index].attack_bonus)
	var tags: Array = []
	var groups: Array = []
	for id: String in state.enchant_preferences:
		var definition: Dictionary = _enchantments[id]
		if not profile.unlocked_nodes.has(definition.required_node_id) or definition.exclusive_group != "none" and groups.has(definition.exclusive_group):
			return {}
		groups.append(definition.exclusive_group)
		for tag: String in definition.preference_tags:
			if not tags.has(tag):
				tags.append(tag)
	tags.sort()
	return {"weapon_id": weapon_id, "forge_level": int(state.level), "attack_bonus": bonus, "enchant_preferences": state.enchant_preferences.duplicate(), "preference_tags": tags, "void_tempered": state.void_tempered}


func weapon_definition(weapon_id: String) -> Dictionary:
	return (_weapons.get(weapon_id, {}) as Dictionary).duplicate(true)


func _common_valid(row: Dictionary) -> bool:
	for field: String in COMMON_FIELDS:
		if not row.has(field):
			return false
	return row.category == "forge_definition" and Catalog.bounded_int(row.schema_version, 1, 1) and Catalog.stable_id(row.id) and row.name_key is String and not row.name_key.is_empty() and row.description_key is String and not row.description_key.is_empty() and row.availability == ["LAUNCH", "EXPANSION"] and row.tags == ["launch", "hub"] and row.compatibility is Dictionary and row.compatibility.is_empty() and row.effects is Dictionary and row.effects.is_empty()


func _weapon_valid(row: Dictionary) -> bool:
	if row.weapon_id not in Catalog.WEAPON_IDS or row.id != "forge_" + str(row.weapon_id) or row.required_node_id != "F-01" or not Catalog.bounded_int(row.maximum_enchantments, 2, 2) or not row.levels is Array or row.levels.size() != 5 or not row.proficiency_thresholds is Array or row.proficiency_thresholds.size() != 5:
		return false
	for index: int in range(5):
		var threshold: int = [0, 100, 300, 700, 1500][index]
		if not Catalog.bounded_int(row.proficiency_thresholds[index], threshold, threshold):
			return false
	for index: int in range(5):
		var level: Variant = row.levels[index]
		if not Catalog.exact_fields(level, ["level", "cost", "attack_bonus"]) or not Catalog.bounded_int(level.level, index + 1, index + 1) or not _cost_valid(level.cost) or not Catalog.finite_number(level.attack_bonus, 0.01, 0.01):
			return false
	if not row.enchantment_ids is Array or row.enchantment_ids.size() != 15:
		return false
	var seen: Array = []
	for id: Variant in row.enchantment_ids:
		if not Catalog.stable_id(id) or seen.has(id):
			return false
		seen.append(id)
	if not row.void_temper_costs is Array or row.void_temper_costs.size() != 2:
		return false
	for cost: Variant in row.void_temper_costs:
		if not _cost_valid(cost):
			return false
	return row.void_temper_costs[0].chronos_shards == 30 and row.void_temper_costs[0].existential_imprints == 0 and row.void_temper_costs[1].chronos_shards == 0 and row.void_temper_costs[1].existential_imprints == 3


func _enchantment_valid(row: Dictionary, catalog: RefCounted) -> bool:
	var ids: Array = []
	for number: int in range(1, 16):
		ids.append("EN-%02d" % number)
	if row.enchantment_id not in ids or row.id != "enchantment_" + str(row.enchantment_id).to_lower().replace("-", "_") or not catalog.call("has_reference", "enchantment", row.enchantment_id) or row.required_node_id not in ["F-02", "F-03"] or row.exclusive_group not in ["none", "element", "time_void"] or row.effect_policy != "reward_preference_and_training" or not _cost_valid(row.unlock_cost) or row.training_action_id not in ["weapon_primary", "weapon_secondary", "weapon_skill"]:
		return false
	var expected_group := "element" if row.enchantment_id in ["EN-01", "EN-02", "EN-03"] else ("time_void" if row.enchantment_id in ["EN-04", "EN-05"] else "none")
	if row.exclusive_group != expected_group or not row.preference_tags is Array or row.preference_tags.is_empty() or row.preference_tags.size() > 8:
		return false
	var seen: Array = []
	for tag: Variant in row.preference_tags:
		if not Catalog.stable_id(tag) or seen.has(tag):
			return false
		seen.append(tag)
	return true


func _cost_valid(value: Variant) -> bool:
	return Catalog.exact_fields(value, ["chronos_shards", "existential_imprints"]) and Catalog.bounded_int(value.chronos_shards, 0, Catalog.MAX_VALUE) and Catalog.bounded_int(value.existential_imprints, 0, Catalog.MAX_VALUE)
