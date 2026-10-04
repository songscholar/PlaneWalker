class_name RewardCompatibility
extends RefCounted

const ARCHETYPES := preload("res://scripts/progression/archetype_profile.gd")
const EffectCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")

static var _effect_descriptors: Dictionary = {}


static func context_for(config: Dictionary) -> Dictionary:
	return {
		"character_ids": [str(config.get("character_id", ""))],
		"weapon_ids": [str(config.get("weapon_id", ""))],
		"time_ability_ids": config.get("enabled_time_skills", []).duplicate(),
		"archetype_ids": ARCHETYPES.ARCHETYPE_IDS.duplicate(),
		"modes": [str(config.get("mode", "normal"))],
	}


static func matches(definition: Dictionary, context: Dictionary) -> bool:
	for key: String in definition.get("compatibility", {}):
		var allowed: Array = definition["compatibility"][key]
		if allowed.is_empty():
			continue
		var found := false
		for selected: Variant in context.get(key, []):
			if allowed.has(str(selected)):
				found = true
				break
		if not found:
			return false
	if _effect_descriptors.is_empty():
		var catalog = EffectCatalogScript.new()
		for row: Dictionary in catalog.snapshot():
			var effect_id := StringName(str(row["effect_id"]))
			_effect_descriptors[str(effect_id)] = catalog.effect_descriptor(effect_id)
	var viable_weapons: Array = context.get("weapon_ids", []).duplicate()
	for effect_id: Variant in definition.get("effects", {}):
		var descriptor: Dictionary = _effect_descriptors.get(str(effect_id), {})
		if descriptor.is_empty():
			return false
		if str(descriptor.get("runtime_domain", "")) != "weapon":
			continue
		var allowed_weapons: Array[String] = []
		for route: Dictionary in descriptor.get("weapon_capabilities", []):
			allowed_weapons.append(str(route["weapon_id"]))
		viable_weapons = viable_weapons.filter(
			func(weapon_id: Variant) -> bool: return allowed_weapons.has(str(weapon_id))
		)
		if viable_weapons.is_empty():
			return false
	return true
