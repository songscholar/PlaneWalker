class_name ContentRegistry
extends RefCounted

const ValidationReportScript := preload("res://scripts/content/content_validation_report.gd")
const ContentPackDescriptorScript := preload("res://scripts/content/content_pack_descriptor.gd")
const ContentPackResolverScript := preload("res://scripts/content/content_pack_resolver.gd")
const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")
const CharacterRuntimeProfileScript := preload("res://scripts/player/characters/character_runtime_profile.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")
const ActiveItemDefinitionScript := preload("res://scripts/items/active_item_definition.gd")
const LaunchPoolCatalogScript := preload("res://scripts/content/launch_pool_catalog.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const RoomTemplateDefinitionScript := preload("res://scripts/dungeon/room_template_definition.gd")
const DungeonEventDefinitionScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const P16ContentCatalogScript := preload("res://scripts/content/p16_content_catalog.gd")
const EnemyDefinitionScript := preload("res://scripts/enemies/launch/enemy_definition.gd")
const BossDefinitionScript := preload("res://scripts/enemies/launch/boss_definition.gd")
const SummonDefinitionScript := preload("res://scripts/enemies/launch/summon_definition.gd")
const EliteAffixDefinitionScript := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const LaunchEncounterProfileScript := preload("res://scripts/dungeon/launch_encounter_profile.gd")
const LaunchEncounterExtensionScript := preload("res://scripts/dungeon/launch_encounter_extension.gd")
const CosmeticDefinitionScript := preload("res://scripts/content/cosmetic_definition.gd")

const VALID_AVAILABILITY: Array[String] = ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]
const VALID_CATEGORIES: Array[String] = [
	"character",
	"weapon",
	"time_ability",
	"item",
	"blessing",
	"curse",
	"talent",
	"enemy",
	"encounter",
	"room",
	"event",
	"merchant",
	"boss",
	"narrative",
	"cosmetic",
	"challenge",
	"archetype_profile",
	"weapon_runtime_profile",
	"character_runtime_profile",
]
const EFFECT_BEARING_CATEGORIES: Array[String] = ["blessing", "curse", "item", "talent"]
const LAUNCH_ROUTE_CATEGORIES: Array[String] = ["item", "blessing", "curse"]
const OVERRIDABLE_FIELDS: Array[String] = ["archetype", "role", "rarity", "kind"]
const CONTENT_ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,63}$"
const LOCALIZATION_KEY_PATTERN := "^[A-Z][A-Z0-9_]{1,127}$"
const V2_REQUIRED_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
]
const V2_ALLOWED_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
	"kind",
	"archetype",
	"role",
	"rarity",
	"icon_id",
	"item_mode",
	"active_handler_id",
	"cooldown_frames",
	"active_parameters",
	"references",
	"profile_version",
	"weapon_id",
	"character_id",
	"runtime_kind",
	"capabilities",
	"resources",
	"actions",
	"payloads",
	"cues",
	"time_interactions",
	"boss_interactions",
	"base_stats",
	"mobility",
	"resource",
	"passive",
	"character_skill",
	"weapon_mastery",
	"presentation",
	"talent_ids",
	"archetype_id",
	"mechanic_tags",
	"starter_min",
	"payoff_min",
	"risk_min",
	"boss_conversion_id",
	"boss_response_key",
]
const COMPATIBILITY_FIELDS: Array[String] = [
	"character_ids",
	"weapon_ids",
	"time_ability_ids",
	"archetype_ids",
	"modes",
]
const COMPATIBILITY_CATEGORY_BY_FIELD := {
	"character_ids": "character",
	"weapon_ids": "weapon",
	"time_ability_ids": "time_ability",
}
const WEAPON_TIME_ABILITIES: Array[String] = ["stop", "rewind", "accelerate", "rift"]
const WEAPON_RUNTIME_PROFILE_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
	"references",
	"profile_version",
	"weapon_id",
	"runtime_kind",
	"actions",
	"resources",
	"capabilities",
	"payloads",
	"cues",
	"time_interactions",
	"boss_interactions",
]
const CHARACTER_RUNTIME_PROFILE_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
	"references",
	"profile_version",
	"character_id",
	"runtime_kind",
	"base_stats",
	"mobility",
	"resource",
	"passive",
	"character_skill",
	"weapon_mastery",
	"time_interactions",
	"presentation",
	"capabilities",
	"talent_ids",
]
const CHARACTER_PROFILE_ONLY_FIELDS: Array[String] = [
	"character_id",
	"base_stats",
	"mobility",
	"resource",
	"passive",
	"character_skill",
	"weapon_mastery",
	"presentation",
	"talent_ids",
]
const ARCHETYPE_PROFILE_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
	"references",
	"profile_version",
	"archetype_id",
	"mechanic_tags",
	"starter_min",
	"payoff_min",
	"risk_min",
	"boss_conversion_id",
	"boss_response_key",
]
const ARCHETYPE_PROFILE_ONLY_FIELDS: Array[String] = [
	"archetype_id",
	"mechanic_tags",
	"starter_min",
	"payoff_min",
	"risk_min",
	"boss_conversion_id",
	"boss_response_key",
]
const SPECIALIZED_CATEGORIES: Array[String] = [
	"cosmetic_definition",
	"floor_definition",
	"room_template",
	"dungeon_event",
	"merchant_definition",
	"economy_profile",
	"enemy_definition",
	"boss_definition",
	"summon_definition",
	"elite_affix_definition",
	"launch_encounter_profile",
	"launch_encounter_extension",
	"meta_node",
	"hub_district",
	"forge_definition",
	"narrative_definition",
	"narrative_source_definition",
	"tutorial_definition",
]
const P14_ENVIRONMENT_RULE_IDS: Array[String] = [
	"rule_crumbling_ground",
	"rule_void_spores",
	"rule_temporal_distortion",
	"rule_forge_vents",
	"rule_collapsing_plane",
]
const P14_ENCOUNTER_PROFILE_IDS: Array[String] = [
	"encounter_profile_ruins_adapter_v1",
	"encounter_profile_forest_adapter_v1",
	"encounter_profile_rift_adapter_v1",
	"encounter_profile_forge_adapter_v1",
	"encounter_profile_throne_adapter_v1",
]
const P14_BOSS_ENCOUNTER_IDS: Array[String] = [
	"boss_encounter_ruin_king_adapter_v1",
	"boss_encounter_forest_heart_adapter_v1",
	"boss_encounter_time_sovereign_adapter_v1",
	"boss_encounter_forge_colossus_adapter_v1",
	"boss_encounter_void_throne_adapter_v1",
]
const P15_CATEGORY_COUNTS := {"enemy_definition": 22, "boss_definition": 5, "summon_definition": 9, "elite_affix_definition": 10, "launch_encounter_profile": 5}

var _definitions: Dictionary = {}
var _active_packs: Array[Dictionary] = []
var _effect_catalog_path: String = EffectHandlerCatalogScript.DEFAULT_CATALOG_PATH


func _init(effect_catalog_path: String = EffectHandlerCatalogScript.DEFAULT_CATALOG_PATH) -> void:
	_effect_catalog_path = effect_catalog_path


func load_packs(
	pack_specs: Array,
	game_version: String,
	execution_mode: StringName = &"M1"
):
	_definitions.clear()
	_active_packs.clear()
	var report = ValidationReportScript.new()
	var mode := str(execution_mode)
	if game_version.is_empty() or not VALID_AVAILABILITY.has(mode):
		report.add_error(
			"Content pack activation arguments are invalid",
			{"game_version": game_version, "execution_mode": mode},
			true
		)
		return report
	if pack_specs.is_empty():
		report.add_error("At least one content pack is required", {}, true)
		return report

	var descriptors: Array[Dictionary] = []
	var isolated_ids: Dictionary = {}
	for index: int in range(pack_specs.size()):
		var spec_result := _normalize_pack_spec(pack_specs[index], index)
		if not bool(spec_result.get("ok", false)):
			report.add_error(
				"Content pack specification is invalid",
				spec_result.get("context", {}),
				bool(spec_result.get("required", index == 0))
			)
			continue
		var required_pack := bool(spec_result["required"])
		var descriptor_result: Dictionary = ContentPackDescriptorScript.load_path(
			str(spec_result["path"]),
			required_pack
		)
		if not bool(descriptor_result.get("ok", false)):
			var descriptor_context: Dictionary = descriptor_result.get("context", {}).duplicate(true)
			descriptor_context["code"] = str(descriptor_result.get("code", &"INVALID_PACK"))
			report.add_error("Content pack descriptor failed", descriptor_context, required_pack)
			var failed_pack_id := str(spec_result.get("pack_id", ""))
			if not required_pack and not failed_pack_id.is_empty():
				isolated_ids[failed_pack_id] = true
			continue
		descriptors.append((descriptor_result["descriptor"] as Dictionary).duplicate(true))

	if report.has_blocking_errors():
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report
	var resolution = ContentPackResolverScript.new().resolve(descriptors, game_version)
	report.merge(resolution)
	for pack_id: Variant in resolution.get_meta("isolated_pack_ids", []):
		isolated_ids[str(pack_id)] = true
	if report.has_blocking_errors():
		report.loaded_count = 0
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report

	var effect_catalog = EffectHandlerCatalogScript.new(_effect_catalog_path)
	var effect_report = effect_catalog.load_report()
	report.merge(effect_report)
	if report.has_blocking_errors():
		report.loaded_count = 0
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report

	var localization_keys: Dictionary = {}
	var active_descriptors: Array = resolution.get_meta("active_descriptors", [])
	for descriptor_value: Variant in active_descriptors:
		if not descriptor_value is Dictionary:
			continue
		var descriptor: Dictionary = descriptor_value
		var pack_id := str(descriptor.get("pack_id", ""))
		if isolated_ids.has(pack_id):
			continue
		var blocking := bool(descriptor.get("required_pack", false))
		var unavailable_dependency := _first_isolated_dependency(descriptor, isolated_ids)
		if not unavailable_dependency.is_empty():
			report.add_error(
				"Content pack dependency was isolated during activation",
				{"pack_id": pack_id, "dependency_id": unavailable_dependency},
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		var localization_result := _load_pack_localization_keys(descriptor)
		if not bool(localization_result.get("ok", false)):
			report.add_error(
				"Content pack localization failed",
				localization_result.get("context", {}),
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		var candidate_localization_keys: Dictionary = localization_keys.duplicate(true)
		for key_value: Variant in (localization_result.get("keys", {}) as Dictionary).keys():
			candidate_localization_keys[str(key_value)] = true

		var definitions_result := _load_pack_definitions(
			descriptor,
			effect_catalog,
			candidate_localization_keys
		)
		if not bool(definitions_result.get("ok", false)):
			for error_value: Variant in definitions_result.get("errors", []):
				var error: Dictionary = error_value
				report.add_error(
					str(error.get("message", "Content pack entry failed validation")),
					error.get("context", {}),
					blocking
				)
			isolated_ids[pack_id] = true
			continue
		var pack_definitions: Array[Dictionary] = definitions_result["definitions"]
		var duplicate_id := ""
		for definition: Dictionary in pack_definitions:
			var content_id := str(definition["id"])
			if _definitions.has(content_id):
				duplicate_id = content_id
				break
		if not duplicate_id.is_empty():
			report.add_error(
				"Duplicate content id across packs",
				{"pack_id": pack_id, "content_id": duplicate_id},
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		var available_ids := _known_content_ids(pack_definitions)
		var reference_error := _first_reference_error(pack_definitions, available_ids)
		if not reference_error.is_empty():
			reference_error["pack_id"] = pack_id
			report.add_error("Content reference is unavailable", reference_error, blocking)
			isolated_ids[pack_id] = true
			continue
		var effect_capability_error := _first_effect_capability_error(
			pack_definitions,
			effect_catalog
		)
		if not effect_capability_error.is_empty():
			effect_capability_error["pack_id"] = pack_id
			report.add_error(
				"Effect capability is unsupported by a weapon runtime profile",
				effect_capability_error,
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		for definition: Dictionary in pack_definitions:
			_definitions[str(definition["id"])] = definition.duplicate(true)
		localization_keys = candidate_localization_keys
		_active_packs.append(descriptor.duplicate(true))

	if report.has_blocking_errors():
		_definitions.clear()
		_active_packs.clear()
		report.loaded_count = 0
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report

	report.loaded_count = _definitions.size()
	var category_counts := _category_counts()
	report.set_activation_summary(
		_active_packs.size(),
		_sorted_string_keys(isolated_ids),
		category_counts,
		{
			"activation_order": _active_pack_ids(),
			"execution_mode": mode,
			"game_version": game_version,
		}
	)
	return report


func load_manifest(path: String):
	_definitions.clear()
	_active_packs.clear()
	var report = ValidationReportScript.new()
	var parsed = _parse_json_file(path, report, true)
	if parsed == null:
		return report
	if typeof(parsed) != TYPE_DICTIONARY:
		report.add_error("Content manifest root must be a dictionary", {"path": path}, true)
		return report
	if not _schema_version_is_supported(parsed.get("schema_version")):
		report.add_error("Unsupported content manifest schema", {"path": path}, true)
		return report
	var sources: Variant = parsed.get("sources")
	if typeof(sources) != TYPE_ARRAY:
		report.add_error("Content manifest sources must be an array", {"path": path}, true)
		return report

	for source_value: Variant in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			report.add_error("Content manifest source must be a dictionary", {"path": path}, true)
			continue
		var source: Dictionary = source_value
		if not _manifest_source_is_valid(source, path, report):
			continue
		var source_path: String = source["path"]
		var category := StringName(source["category"])
		var default_availability := StringName(source.get("default_availability", "NEXT"))
		var m1_ids_value: Variant = source.get("m1_ids", [])
		var overrides_value: Variant = source.get("overrides", {})
		load_entries(source_path, category, default_availability, m1_ids_value, report, overrides_value)
	return report


func load_entries(
	path: String,
	category: StringName,
	default_availability: StringName,
	m1_ids: Array = [],
	report = null,
	overrides: Dictionary = {}
):
	var active_report = report if report != null else ValidationReportScript.new()
	var source_is_m1 := str(default_availability) == "M1" or not m1_ids.is_empty()
	if not VALID_CATEGORIES.has(str(category)) or not VALID_AVAILABILITY.has(str(default_availability)):
		active_report.add_error(
			"Content source arguments are invalid",
			{"path": path, "category": str(category), "default_availability": str(default_availability)},
			true
		)
		return active_report
	if not _id_list_is_valid(m1_ids):
		active_report.add_error("Content source M1 ids are invalid", {"path": path, "m1_ids": m1_ids}, true)
		return active_report
	var override_error := _override_error(overrides)
	if not override_error.is_empty():
		override_error["path"] = path
		active_report.add_error("Content source overrides are invalid", override_error, true)
		overrides = {}
	var parsed = _parse_json_file(path, active_report, source_is_m1)
	if parsed == null:
		return active_report
	if typeof(parsed) != TYPE_ARRAY:
		active_report.add_error(
			"Content source root must be an array",
			{"path": path, "category": str(category)},
			source_is_m1
		)
		return active_report

	var source_ids: Dictionary = {}
	for index: int in range(parsed.size()):
		var entry_value: Variant = parsed[index]
		var entry: Dictionary = entry_value if typeof(entry_value) == TYPE_DICTIONARY else {}
		var entry_id := str(entry.get("id", ""))
		if not entry_id.is_empty():
			source_ids[entry_id] = true
		var blocking := source_is_m1 or m1_ids.has(entry_id)
		var invalid_field := _first_invalid_field(entry_value)
		if not invalid_field.is_empty():
			active_report.add_error(
				"Content entry is missing a required field",
				{"path": path, "index": index, "id": entry_id, "field": invalid_field},
				blocking
			)
			continue

		var normalized := _normalize_entry(entry, category, default_availability, m1_ids, overrides)
		if _definitions.has(entry_id):
			var existing: Dictionary = _definitions[entry_id]
			var duplicate_blocks: bool = blocking or existing.get("availability", []).has("M1")
			active_report.add_error(
				"Duplicate content id",
				{"path": path, "index": index, "id": entry_id},
				duplicate_blocks
			)
			continue

		_definitions[entry_id] = normalized
		active_report.loaded_count += 1
		active_report.add_warning(
			"Legacy display fields normalized",
			{"path": path, "id": entry_id, "fields": ["name", "description"]}
		)
		if overrides.has(entry_id):
			active_report.add_warning(
				"Milestone content override applied",
					{"path": path, "id": entry_id, "override": overrides[entry_id]}
				)

	_validate_declared_m1_ids(path, category, m1_ids, source_ids, active_report)
	for override_id: Variant in overrides.keys():
		if not source_ids.has(str(override_id)):
			active_report.add_error(
				"Content override id was not found in source",
				{"path": path, "id": str(override_id)},
				true
			)
	return active_report


func get_content(content_id: StringName) -> Dictionary:
	var definition: Dictionary = _definitions.get(str(content_id), {})
	return definition.duplicate(true)


func get_catalog_entries(category: StringName, availability: StringName = &"") -> Array[Dictionary]:
	var entries := get_by_category(category, availability)
	for entry: Dictionary in entries:
		entry.erase("pack_id")
		entry.erase("pack_version")
	return entries


func get_weapon_runtime_profile(profile_id: StringName) -> Dictionary:
	var definition := get_content(profile_id)
	if str(definition.get("category", "")) != "weapon_runtime_profile":
		return {}
	return _canonical_weapon_runtime_profile(definition)


func resolve_weapon_runtime_profile(weapon_id: StringName, milestone: StringName) -> Dictionary:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in get_by_category(&"weapon_runtime_profile", milestone):
		if str(definition.get("weapon_id", "")) == str(weapon_id):
			matches.append(definition)
	if matches.size() != 1:
		return {}
	return _canonical_weapon_runtime_profile(matches[0])


func get_character_runtime_profile(profile_id: StringName) -> Dictionary:
	var definition := get_content(profile_id)
	if str(definition.get("category", "")) != "character_runtime_profile":
		return {}
	return _canonical_character_runtime_profile(definition)


func resolve_character_runtime_profile(character_id: StringName, milestone: StringName) -> Dictionary:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in get_by_category(&"character_runtime_profile", milestone):
		if str(definition.get("character_id", "")) == str(character_id):
			matches.append(definition)
	if matches.size() != 1:
		return {}
	return _canonical_character_runtime_profile(matches[0])


func get_archetype_profile(archetype_id: StringName) -> Dictionary:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in get_by_category(&"archetype_profile"):
		if str(definition.get("archetype_id", "")) == str(archetype_id):
			matches.append(definition)
	if matches.size() != 1:
		return {}
	return _canonical_archetype_profile(matches[0])


func get_archetype_profiles(milestone: StringName) -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	for archetype_id: String in ArchetypeProfileScript.ARCHETYPE_IDS:
		var profile := get_archetype_profile(StringName(archetype_id))
		if profile.is_empty() or not profile.get("availability", []).has(str(milestone)):
			continue
		profiles.append(profile)
	return profiles


func resolve_floor(floor_id: StringName) -> Dictionary:
	return _resolve_specialized(floor_id, "floor_definition")


func resolve_room_template(room_template_id: StringName) -> Dictionary:
	return _resolve_specialized(room_template_id, "room_template")


func resolve_dungeon_event(event_id: StringName) -> Dictionary:
	return _resolve_specialized(event_id, "dungeon_event")


func resolve_merchant(merchant_id: StringName) -> Dictionary:
	return _resolve_specialized(merchant_id, "merchant_definition")


func resolve_economy_profile(economy_profile_id: StringName) -> Dictionary:
	return _resolve_specialized(economy_profile_id, "economy_profile")


func get_floor_definitions(availability: StringName = &"") -> Array[Dictionary]:
	var floors := get_by_category(&"floor_definition", availability)
	floors.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_order := int(left.get("order", 0))
			var right_order := int(right.get("order", 0))
			if left_order != right_order:
				return left_order < right_order
			return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return floors


func _resolve_specialized(content_id: StringName, expected_category: String) -> Dictionary:
	var definition := get_content(content_id)
	if str(definition.get("category", "")) != expected_category:
		return {}
	return definition.duplicate(true)


func _canonical_weapon_runtime_profile(definition: Dictionary) -> Dictionary:
	var source: Dictionary = {}
	for field: String in WEAPON_RUNTIME_PROFILE_FIELDS:
		if definition.has(field):
			source[field] = definition[field].duplicate(true) if definition[field] is Array or definition[field] is Dictionary else definition[field]
	var result: Dictionary = WeaponRuntimeProfileScript.new().configure(source)
	if not bool(result.get("ok", false)):
		return {}
	return (result.get("profile", {}) as Dictionary).duplicate(true)


func _canonical_character_runtime_profile(definition: Dictionary) -> Dictionary:
	var source: Dictionary = {}
	for field: String in CHARACTER_RUNTIME_PROFILE_FIELDS:
		if definition.has(field):
			source[field] = definition[field].duplicate(true) if definition[field] is Array or definition[field] is Dictionary else definition[field]
	var result: Dictionary = CharacterRuntimeProfileScript.new().configure(source)
	if not bool(result.get("ok", false)):
		return {}
	return (result.get("profile", {}) as Dictionary).duplicate(true)


func _canonical_archetype_profile(definition: Dictionary) -> Dictionary:
	var source: Dictionary = {}
	for field: String in ARCHETYPE_PROFILE_FIELDS:
		if definition.has(field):
			source[field] = definition[field].duplicate(true) if definition[field] is Array or definition[field] is Dictionary else definition[field]
	var result: Dictionary = ArchetypeProfileScript.new().configure(source)
	if not bool(result.get("ok", false)):
		return {}
	return (result.get("profile", {}) as Dictionary).duplicate(true)


func get_by_category(category: StringName, availability: StringName = &"") -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in _sorted_definitions():
		if str(definition.get("category", "")) != str(category):
			continue
		if not str(availability).is_empty() and not definition.get("availability", []).has(str(availability)):
			continue
		matches.append(definition.duplicate(true))
	return matches


func all_content() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for definition: Dictionary in _sorted_definitions():
		values.append(definition.duplicate(true))
	return values


func active_packs() -> Array[Dictionary]:
	return _active_packs.duplicate(true)


func get_by_tag(tag: StringName, availability: StringName = &"") -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in _sorted_definitions():
		if not definition.get("tags", []).has(str(tag)):
			continue
		if not str(availability).is_empty() and not definition.get("availability", []).has(str(availability)):
			continue
		matches.append(definition.duplicate(true))
	return matches


func _parse_json_file(path: String, report, blocking: bool):
	if not FileAccess.file_exists(path):
		report.add_error("Content file does not exist", {"path": path}, blocking)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report.add_error("Content file could not be opened", {"path": path}, blocking)
		return null
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		report.add_error(
			"Content file contains invalid JSON",
			{"path": path, "line": json.get_error_line(), "message": json.get_error_message()},
			blocking
		)
		return null
	return json.data


func _first_invalid_field(entry_value: Variant) -> String:
	if typeof(entry_value) != TYPE_DICTIONARY:
		return "entry"
	var entry: Dictionary = entry_value
	for field: String in ["id", "name", "description"]:
		if typeof(entry.get(field)) != TYPE_STRING or str(entry.get(field)).is_empty():
			return field
	if typeof(entry.get("effects")) != TYPE_DICTIONARY:
		return "effects"
	if (
		entry.has("availability")
		and not _id_array_error(entry["availability"], VALID_AVAILABILITY, false, false).is_empty()
	):
		return "availability"
	return ""


func _normalize_entry(
	entry: Dictionary,
	category: StringName,
	default_availability: StringName,
	m1_ids: Array,
	overrides: Dictionary
) -> Dictionary:
	var entry_id := str(entry["id"])
	var availability: Array = (
		(entry["availability"] as Array).duplicate()
		if entry.has("availability")
		else [str(default_availability)]
	)
	if m1_ids.has(entry_id) and not availability.has("M1"):
		availability.append("M1")
	var normalized := {
		"schema_version": 1,
		"id": entry_id,
		"category": str(category),
		"availability": availability,
		"name_key": str(entry["name"]),
		"description_key": str(entry["description"]),
		"kind": str(entry.get("kind", "")),
		"archetype": str(entry.get("archetype", "")),
		"role": str(entry.get("role", "utility")),
		"rarity": str(entry.get("rarity", "common")),
		"effects": (entry["effects"] as Dictionary).duplicate(true),
	}
	var entry_overrides: Variant = overrides.get(entry_id, {})
	if typeof(entry_overrides) == TYPE_DICTIONARY:
		for field: String in ["archetype", "role", "rarity", "kind"]:
			if entry_overrides.has(field):
				normalized[field] = str(entry_overrides[field])
	return normalized


func _schema_version_is_supported(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric_value := float(value)
	return is_finite(numeric_value) and numeric_value == 1.0


func _manifest_source_is_valid(source: Dictionary, path: String, report) -> bool:
	for field: String in ["path", "category", "default_availability"]:
		if typeof(source.get(field)) != TYPE_STRING or str(source.get(field)).is_empty():
			report.add_error(
				"Content manifest source field is invalid",
				{"path": path, "field": field, "source": source},
				true
			)
			return false
	if not VALID_AVAILABILITY.has(str(source["default_availability"])):
		report.add_error(
			"Content manifest availability is invalid",
			{"path": path, "value": source["default_availability"]},
			true
		)
		return false
	if not VALID_CATEGORIES.has(str(source["category"])):
		report.add_error(
			"Content manifest category is invalid",
			{"path": path, "value": source["category"]},
			true
		)
		return false
	var m1_ids: Variant = source.get("m1_ids", [])
	if typeof(m1_ids) != TYPE_ARRAY or not _id_list_is_valid(m1_ids):
		report.add_error("Content manifest M1 ids are invalid", {"path": path, "source": source}, true)
		return false
	var overrides: Variant = source.get("overrides", {})
	if typeof(overrides) != TYPE_DICTIONARY:
		report.add_error("Content manifest overrides must be a dictionary", {"path": path}, true)
		return false
	var override_error := _override_error(overrides)
	if not override_error.is_empty():
		override_error["path"] = path
		report.add_error("Content manifest override is invalid", override_error, true)
		return false
	return true


func _id_list_is_valid(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if typeof(value) != TYPE_STRING or str(value).is_empty() or seen.has(str(value)):
			return false
		seen[str(value)] = true
	return true


func _override_error(overrides: Dictionary) -> Dictionary:
	for entry_id: Variant in overrides.keys():
		if typeof(entry_id) != TYPE_STRING or str(entry_id).is_empty():
			return {"id": str(entry_id), "field": "id"}
		var entry_override: Variant = overrides[entry_id]
		if typeof(entry_override) != TYPE_DICTIONARY:
			return {"id": str(entry_id), "field": "override"}
		for field_value: Variant in (entry_override as Dictionary).keys():
			var field := str(field_value)
			var value: Variant = (entry_override as Dictionary)[field_value]
			if typeof(field_value) != TYPE_STRING or not OVERRIDABLE_FIELDS.has(field):
				return {"id": str(entry_id), "field": field}
			if typeof(value) != TYPE_STRING or (field != "archetype" and str(value).is_empty()):
				return {"id": str(entry_id), "field": field, "value": value}
	return {}


func _validate_declared_m1_ids(
	path: String,
	category: StringName,
	m1_ids: Array,
	source_ids: Dictionary,
	report
) -> void:
	for content_id_value: Variant in m1_ids:
		var content_id := str(content_id_value)
		if not source_ids.has(content_id):
			report.add_error(
				"Declared M1 content id was not found in source",
				{"path": path, "id": content_id},
				true
			)
			continue
		var definition: Variant = _definitions.get(content_id)
		if (
			typeof(definition) != TYPE_DICTIONARY
			or str((definition as Dictionary).get("category", "")) != str(category)
			or not (definition as Dictionary).get("availability", []).has("M1")
		):
			report.add_error(
				"Declared M1 content id failed to load",
				{"path": path, "id": content_id, "category": str(category)},
				true
			)


func _sorted_definitions() -> Array[Dictionary]:
	var ids: Array = _definitions.keys()
	ids.sort()
	var sorted: Array[Dictionary] = []
	for content_id: Variant in ids:
		sorted.append(_definitions[content_id])
	return sorted


func _normalize_pack_spec(value: Variant, index: int) -> Dictionary:
	if typeof(value) == TYPE_STRING:
		var path := str(value)
		if path.is_empty():
			return {"ok": false, "required": index == 0, "context": {"index": index, "field": "path"}}
		return {"ok": true, "path": path, "required": index == 0}
	if not value is Dictionary:
		return {"ok": false, "required": index == 0, "context": {"index": index, "field": "spec"}}
	var spec: Dictionary = value
	if typeof(spec.get("path")) != TYPE_STRING or str(spec.get("path")).is_empty():
		return {"ok": false, "required": bool(spec.get("required", index == 0)), "context": {"index": index, "field": "path"}}
	if spec.has("required") and typeof(spec["required"]) != TYPE_BOOL:
		return {"ok": false, "required": index == 0, "context": {"index": index, "field": "required"}}
	return {
		"ok": true,
		"path": str(spec["path"]),
		"required": bool(spec.get("required", index == 0)),
		"pack_id": str(spec.get("pack_id", "")),
	}


func _load_pack_localization_keys(descriptor: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	var root_path := str(descriptor.get("root_path", ""))
	var pack_id := str(descriptor.get("pack_id", ""))
	for relative_path_value: Variant in descriptor.get("localization_sources", []):
		var relative_path := str(relative_path_value)
		var source_path := root_path.path_join(relative_path)
		var file := FileAccess.open(source_path, FileAccess.READ)
		if file == null:
			return {
				"ok": false,
				"keys": {},
				"context": {"pack_id": pack_id, "path": source_path, "reason": "open_failed"},
			}
		var lines := file.get_as_text().split("\n", false)
		if lines.is_empty() or str(lines[0]).strip_edges().to_lower() != "keys,en,zh_cn":
			return {
				"ok": false,
				"keys": {},
				"context": {"pack_id": pack_id, "path": source_path, "reason": "header"},
			}
		for line_index: int in range(1, lines.size()):
			var line := str(lines[line_index]).strip_edges()
			if line.is_empty():
				continue
			var key := line.get_slice(",", 0).strip_edges().trim_prefix("\"").trim_suffix("\"")
			if not _matches(LOCALIZATION_KEY_PATTERN, key) or keys.has(key):
				return {
					"ok": false,
					"keys": {},
					"context": {
						"pack_id": pack_id,
						"path": source_path,
						"line": line_index + 1,
						"key": key,
						"reason": "invalid_or_duplicate_key",
					},
				}
			keys[key] = true
	return {"ok": true, "keys": keys, "context": {}}


func _load_pack_definitions(
	descriptor: Dictionary,
	effect_catalog,
	localization_keys: Dictionary
) -> Dictionary:
	var definitions: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var pack_ids: Dictionary = {}
	var root_path := str(descriptor.get("root_path", ""))
	var pack_id := str(descriptor.get("pack_id", ""))
	var pack_version := str(descriptor.get("pack_version", ""))
	for relative_path_value: Variant in descriptor.get("content_manifest", []):
		var relative_path := str(relative_path_value)
		var source_path := root_path.path_join(relative_path)
		var file := FileAccess.open(source_path, FileAccess.READ)
		if file == null:
			errors.append({
				"message": "Content pack source could not be opened",
				"context": {"pack_id": pack_id, "path": source_path},
			})
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		if parse_error != OK or not parser.data is Array:
			errors.append({
				"message": "Content pack source must contain a valid JSON array",
				"context": {
					"pack_id": pack_id,
					"path": source_path,
					"line": parser.get_error_line(),
					"parse_error": parse_error,
				},
			})
			continue
		for index: int in range((parser.data as Array).size()):
			var entry_value: Variant = (parser.data as Array)[index]
			var normalized: Dictionary = {}
			var specialized_result := _specialized_definition_parse_result(
				entry_value,
				localization_keys
			)
			if bool(specialized_result.get("handled", false)):
				if not bool(specialized_result.get("ok", false)):
					var specialized_error: Dictionary = specialized_result.get("context", {}).duplicate(true)
					specialized_error["pack_id"] = pack_id
					specialized_error["path"] = source_path
					specialized_error["index"] = index
					specialized_error["code"] = str(specialized_result.get("code", &"SPECIALIZED_DEFINITION_INVALID"))
					errors.append({
						"message": "Specialized content pack entry failed validation",
						"context": specialized_error,
					})
					continue
				normalized = (specialized_result.get("definition", {}) as Dictionary).duplicate(true)
			else:
				var entry_error := _v2_entry_error(entry_value, effect_catalog, localization_keys)
				if not entry_error.is_empty():
					entry_error["pack_id"] = pack_id
					entry_error["path"] = source_path
					entry_error["index"] = index
					errors.append({"message": "Content pack entry failed validation", "context": entry_error})
					continue
				var entry: Dictionary = entry_value
				normalized = entry.duplicate(true)
				var availability: Array = normalized["availability"]
				if str(normalized.get("category", "")) != "archetype_profile":
					availability.sort()
				normalized["availability"] = availability
				var tags: Array = normalized["tags"]
				tags.sort()
				normalized["tags"] = tags
				var compatibility: Dictionary = normalized["compatibility"]
				for compatibility_field: Variant in compatibility.keys():
					var values: Array = compatibility[compatibility_field]
					values.sort()
					compatibility[compatibility_field] = values
				normalized["compatibility"] = compatibility
				normalized["effects"] = effect_catalog.normalize_effects(normalized["effects"])
				normalized["kind"] = str(normalized.get("kind", ""))
				normalized["archetype"] = str(normalized.get("archetype", ""))
				normalized["role"] = str(normalized.get("role", "utility"))
				normalized["rarity"] = str(normalized.get("rarity", "common"))
				normalized["icon_id"] = str(normalized.get("icon_id", "content_%s" % str(normalized.get("id", ""))))
				if str(normalized.get("category", "")) == "item":
					normalized["item_mode"] = str(normalized.get("item_mode", "passive"))
					if normalized["item_mode"] == "active":
						var active_parse_result := _active_item_parse_result(normalized)
						if bool(active_parse_result.get("ok", false)):
							var active_snapshot: Dictionary = active_parse_result.get("snapshot", {})
							for active_field: String in [
								"active_handler_id", "cooldown_frames", "active_parameters",
							]:
								normalized[active_field] = active_snapshot[active_field]
				var references: Array = normalized.get("references", [])
				references.sort()
				normalized["references"] = references
			var content_id := str(normalized.get("id", ""))
			if pack_ids.has(content_id):
				errors.append({
					"message": "Duplicate content id inside pack",
					"context": {"pack_id": pack_id, "path": source_path, "index": index, "content_id": content_id},
				})
				continue
			pack_ids[content_id] = true
			normalized["pack_id"] = pack_id
			normalized["pack_version"] = pack_version
			definitions.append(normalized)
	if not errors.is_empty():
		return {"ok": false, "definitions": [], "errors": errors}
	var closure := P16ContentCatalogScript.validate_complete(definitions)
	if not closure.ok:
		return {"ok": false, "definitions": [], "errors": [{"message": "P16 catalog closure failed validation", "context": {"pack_id": pack_id, "code": str(closure.code), "detail": closure.context.duplicate(true)}}]}
	var hostile_counts: Dictionary = {}
	for definition: Dictionary in definitions:
		if P15_CATEGORY_COUNTS.has(definition.category):
			hostile_counts[definition.category] = int(hostile_counts.get(definition.category, 0)) + 1
	if not hostile_counts.is_empty():
		for category: String in P15_CATEGORY_COUNTS:
			if hostile_counts.get(category, 0) != P15_CATEGORY_COUNTS[category]:
				return {"ok": false, "definitions": [], "errors": [{"message": "Launch hostile catalog count is incomplete", "context": {"pack_id": pack_id, "category": category}}]}
	definitions.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left["id"]) < str(right["id"])
	)
	return {"ok": true, "definitions": definitions, "errors": []}


func _specialized_definition_parse_result(
	entry_value: Variant,
	localization_keys: Dictionary
) -> Dictionary:
	if not entry_value is Dictionary:
		return {"handled": false, "ok": false, "definition": {}, "context": {}}
	var entry: Dictionary = entry_value
	var category := str(entry.get("category", ""))
	if not SPECIALIZED_CATEGORIES.has(category):
		return {"handled": false, "ok": false, "definition": {}, "context": {}}
	var definition_parser: RefCounted
	if P16ContentCatalogScript.COUNTS.has(category):
		if not _matches(CONTENT_ID_PATTERN, entry.get("id")):
			return {"handled": true, "ok": false, "code": &"P16_CONTENT_ID_INVALID", "definition": {}, "context": {"field": "id"}}
		var p16_result := P16ContentCatalogScript.parse_entry(entry)
		p16_result["handled"] = true
		if p16_result.ok:
			var localization_error := _nested_localization_error(p16_result.definition, localization_keys)
			if not localization_error.is_empty():
				return {"handled": true, "ok": false, "code": &"SPECIALIZED_LOCALIZATION_INVALID", "definition": {}, "context": localization_error}
		return p16_result
	match category:
		"cosmetic_definition":
			definition_parser = CosmeticDefinitionScript.new()
		"floor_definition":
			definition_parser = FloorDefinitionScript.new()
		"room_template":
			definition_parser = RoomTemplateDefinitionScript.new()
		"dungeon_event":
			definition_parser = DungeonEventDefinitionScript.new()
		"merchant_definition":
			definition_parser = MerchantDefinitionScript.new()
		"economy_profile":
			definition_parser = EconomyProfileScript.new()
		"enemy_definition":
			definition_parser = EnemyDefinitionScript.new()
		"boss_definition":
			definition_parser = BossDefinitionScript.new()
		"summon_definition":
			definition_parser = SummonDefinitionScript.new()
		"elite_affix_definition":
			definition_parser = EliteAffixDefinitionScript.new()
		"launch_encounter_profile":
			definition_parser = LaunchEncounterProfileScript.new()
		"launch_encounter_extension":
			definition_parser = LaunchEncounterExtensionScript.new()
		_:
			return {
				"handled": true,
				"ok": false,
				"code": &"SPECIALIZED_CATEGORY_UNREGISTERED",
				"definition": {},
				"context": {"field": "category", "reason": "unregistered"},
			}
	var result: Dictionary = definition_parser.call("configure", entry)
	if not bool(result.get("ok", false)):
		return {
			"handled": true,
			"ok": false,
			"code": result.get("code", &"SPECIALIZED_DEFINITION_INVALID"),
			"definition": {},
			"context": (result.get("context", {}) as Dictionary).duplicate(true),
		}
	var definition: Dictionary = (result.get("definition", {}) as Dictionary).duplicate(true)
	if definition.is_empty():
		definition = (definition_parser.call("snapshot") as Dictionary).duplicate(true)
	var localization_error := _nested_localization_error(definition, localization_keys)
	if not localization_error.is_empty():
		return {
			"handled": true,
			"ok": false,
			"code": &"SPECIALIZED_LOCALIZATION_INVALID",
			"definition": {},
			"context": localization_error,
		}
	return {
		"handled": true,
		"ok": true,
		"code": &"OK",
		"definition": definition.duplicate(true),
		"context": {},
	}


func _nested_localization_error(
	value: Variant,
	localization_keys: Dictionary,
	field_path: String = ""
) -> Dictionary:
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key_value: Variant in dictionary.keys():
			var key := str(key_value)
			var child_path := key if field_path.is_empty() else "%s.%s" % [field_path, key]
			var child_value: Variant = dictionary[key_value]
			if key.ends_with("_key"):
				if not _matches(LOCALIZATION_KEY_PATTERN, child_value):
					return {"field": child_path, "reason": "invalid_localization", "key": child_value}
				if not localization_keys.has(str(child_value)):
					return {"field": child_path, "reason": "missing_localization", "key": child_value}
			var child_error := _nested_localization_error(child_value, localization_keys, child_path)
			if not child_error.is_empty():
				return child_error
	elif value is Array:
		var values: Array = value
		for index: int in range(values.size()):
			var child_path := "[%d]" % index if field_path.is_empty() else "%s[%d]" % [field_path, index]
			var child_error := _nested_localization_error(values[index], localization_keys, child_path)
			if not child_error.is_empty():
				return child_error
	return {}


func _v2_entry_error(
	entry_value: Variant,
	effect_catalog,
	localization_keys: Dictionary
) -> Dictionary:
	if not entry_value is Dictionary:
		return {"field": "entry", "reason": "type"}
	var entry: Dictionary = entry_value
	for field: String in V2_REQUIRED_FIELDS:
		if not entry.has(field):
			return {"field": field, "reason": "missing"}
	for field_value: Variant in entry.keys():
		var field := str(field_value)
		if not V2_ALLOWED_FIELDS.has(field):
			return {"field": field, "reason": "unknown"}
	if not _matches(CONTENT_ID_PATTERN, entry["id"]):
		return {"field": "id", "reason": "value"}
	if typeof(entry["category"]) != TYPE_STRING or not VALID_CATEGORIES.has(str(entry["category"])):
		return {"field": "category", "reason": "value"}
	var category := str(entry["category"])
	for item_field: String in ["item_mode", "active_handler_id", "cooldown_frames", "active_parameters"]:
		if category != "item" and entry.has(item_field):
			return {"field": item_field, "reason": "category_specific_field"}
	if category != "archetype_profile":
		for profile_field: String in ARCHETYPE_PROFILE_ONLY_FIELDS:
			if entry.has(profile_field):
				return {"field": profile_field, "reason": "category_specific_field"}
	var availability_error := _id_array_error(entry["availability"], VALID_AVAILABILITY, false, false)
	if not availability_error.is_empty():
		return {"field": "availability", "reason": availability_error}
	for field: String in ["name_key", "description_key"]:
		if not _matches(LOCALIZATION_KEY_PATTERN, entry[field]):
			return {"field": field, "reason": "value"}
		if not localization_keys.has(str(entry[field])):
			return {"field": field, "reason": "missing_localization", "key": entry[field]}
	var tags_error := _id_array_error(entry["tags"], [], true)
	if not tags_error.is_empty():
		return {"field": "tags", "reason": tags_error}
	if not entry["compatibility"] is Dictionary:
		return {"field": "compatibility", "reason": "type"}
	for field_value: Variant in (entry["compatibility"] as Dictionary).keys():
		var field := str(field_value)
		if not COMPATIBILITY_FIELDS.has(field):
			return {"field": "compatibility.%s" % field, "reason": "unknown"}
		if category == "character_runtime_profile" and field in ["archetype_ids", "modes"]:
			return {"field": "compatibility.%s" % field, "reason": "unsupported_constraint"}
		var compatibility_error := _id_array_error(
			(entry["compatibility"] as Dictionary)[field_value],
			[],
			false if field == "archetype_ids" else category != "character_runtime_profile"
		)
		if not compatibility_error.is_empty():
			return {"field": "compatibility.%s" % field, "reason": compatibility_error}
	if not entry["effects"] is Dictionary:
		return {"field": "effects", "reason": "type"}
	if category != "character_runtime_profile":
		for character_field: String in CHARACTER_PROFILE_ONLY_FIELDS:
			if entry.has(character_field):
				return {"field": character_field, "reason": "category_specific_field"}
	if not EFFECT_BEARING_CATEGORIES.has(category):
		if not (entry["effects"] as Dictionary).is_empty():
			return {"field": "effects", "reason": "unsupported_category"}
	else:
		var effect_report = effect_catalog.validate_effects(
			entry["effects"],
			{"category": category}
		)
		if effect_report.has_blocking_errors():
			return {"field": "effects", "reason": "invalid", "errors": effect_report.blocking_errors.duplicate(true)}
	if category == "weapon_runtime_profile":
		var profile_result: Dictionary = WeaponRuntimeProfileScript.new().configure(entry)
		if not bool(profile_result.get("ok", false)):
			var profile_context: Dictionary = profile_result.get("context", {})
			return {
				"field": str(profile_context.get("field", "weapon_runtime_profile")),
				"reason": str(profile_context.get("reason", "invalid")),
			}
		var integration_error := _weapon_runtime_profile_integration_error(entry)
		if not integration_error.is_empty():
			return integration_error
	if category == "character_runtime_profile":
		var character_profile_result: Dictionary = CharacterRuntimeProfileScript.new().configure(entry)
		if not bool(character_profile_result.get("ok", false)):
			var character_profile_context: Dictionary = character_profile_result.get("context", {})
			return {
				"field": str(character_profile_context.get("field", "character_runtime_profile")),
				"reason": str(character_profile_context.get("reason", "invalid")),
			}
		var character_integration_error := _character_runtime_profile_integration_error(entry)
		if not character_integration_error.is_empty():
			return character_integration_error
	if category == "archetype_profile":
		var archetype_profile_result: Dictionary = ArchetypeProfileScript.new().configure(entry)
		if not bool(archetype_profile_result.get("ok", false)):
			var archetype_profile_context: Dictionary = archetype_profile_result.get("context", {})
			return {
				"field": str(archetype_profile_context.get("field", "archetype_profile")),
				"reason": str(archetype_profile_context.get("reason", "invalid")),
			}
	for field: String in ["kind", "archetype", "role"]:
		if entry.has(field) and not _optional_identifier_is_valid(entry[field]):
			return {"field": field, "reason": "value"}
	if entry.has("rarity") and str(entry["rarity"]) not in ["common", "uncommon", "rare", "legendary", "unique"]:
		return {"field": "rarity", "reason": "value"}
	if entry.has("icon_id") and not _matches(CONTENT_ID_PATTERN, entry["icon_id"]):
		return {"field": "icon_id", "reason": "value"}
	if category == "item":
		var item_mode := str(entry.get("item_mode", "passive"))
		if item_mode not in ["passive", "active"]:
			return {"field": "item_mode", "reason": "value"}
		if item_mode == "active":
			var active_result := _active_item_parse_result(entry)
			if not bool(active_result.get("ok", false)):
				var active_context: Dictionary = active_result.get("context", {})
				return {
					"field": str(active_context.get("field", "active_item")),
					"reason": str(active_context.get("reason", "invalid")),
				}
		else:
			for active_field: String in ["active_handler_id", "cooldown_frames", "active_parameters"]:
				if entry.has(active_field):
					return {"field": active_field, "reason": "active_only"}
	var launch_content_error := _launch_content_error(entry)
	if not launch_content_error.is_empty():
		return launch_content_error
	if entry.has("references"):
		var reference_error := _id_array_error(entry["references"], [], true)
		if not reference_error.is_empty():
			return {"field": "references", "reason": reference_error}
	return {}


func _active_item_parse_result(entry: Dictionary) -> Dictionary:
	var parser = ActiveItemDefinitionScript.new()
	var result: Dictionary = parser.configure(entry)
	if not bool(result.get("ok", false)):
		return result
	return {
		"ok": true,
		"context": {},
		"snapshot": parser.snapshot(),
	}


func _launch_content_error(entry: Dictionary) -> Dictionary:
	var availability: Array = entry.get("availability", [])
	if not availability.has("LAUNCH"):
		return {}
	var category := str(entry.get("category", ""))
	var archetype := str(entry.get("archetype", ""))
	var role := str(entry.get("role", "utility"))
	var tags: Array = entry.get("tags", [])
	var compatibility: Dictionary = entry.get("compatibility", {})
	if LAUNCH_ROUTE_CATEGORIES.has(category):
		var route_ids: Array = compatibility.get("archetype_ids", [])
		if archetype.is_empty():
			if role != "utility":
				return {"field": "role", "reason": "generalist_requires_utility"}
			if not tags.has("generalist") or not tags.has("utility"):
				return {"field": "tags", "reason": "generalist_utility_required"}
			if not route_ids.is_empty():
				return {
					"field": "compatibility.archetype_ids",
					"reason": "generalist_must_not_route",
				}
			return {}
		if not ArchetypeProfileScript.ARCHETYPE_IDS.has(archetype):
			return {"field": "archetype", "reason": "unknown"}
		var allowed_roles: Array = []
		match category:
			"item":
				allowed_roles = ["risk"] if str(entry.get("item_mode", "passive")) == "active" else ["starter", "payoff"]
			"blessing":
				allowed_roles = ["starter", "payoff"]
			"curse":
				allowed_roles = ["risk"]
		if not allowed_roles.has(role):
			return {"field": "role", "reason": "route_role"}
		if not tags.has(archetype) or tags.has("generalist") or tags.has("utility"):
			return {"field": "tags", "reason": "route_tag_contract"}
		if route_ids != [archetype]:
			return {
				"field": "compatibility.archetype_ids",
				"reason": "exact_route_required",
			}
		return {}
	if category == "talent":
		if not archetype.is_empty():
			return {"field": "archetype", "reason": "talent_route_forbidden"}
		var talent_route_ids: Array = compatibility.get("archetype_ids", [])
		if not talent_route_ids.is_empty():
			return {
				"field": "compatibility.archetype_ids",
				"reason": "talent_route_forbidden",
			}
		var character_ids_value: Variant = compatibility.get("character_ids", [])
		if not character_ids_value is Array or (character_ids_value as Array).size() != 1:
			return {
				"field": "compatibility.character_ids",
				"reason": "exact_owner_required",
			}
		var character_id := str((character_ids_value as Array)[0])
		if not CharacterRuntimeProfileScript.CHARACTER_IDS.has(character_id):
			return {"field": "compatibility.character_ids", "reason": "unknown_owner"}
		var canonical_owner := str(
			LaunchPoolCatalogScript.TALENT_CHARACTER_BY_ID.get(str(entry.get("id", "")), "")
		)
		if not canonical_owner.is_empty() and canonical_owner != character_id:
			return {"field": "compatibility.character_ids", "reason": "owner_mismatch"}
	return {}


func _weapon_runtime_profile_integration_error(entry: Dictionary) -> Dictionary:
	if not entry.get("time_interactions") is Dictionary:
		return {"field": "time_interactions", "reason": "missing"}
	var time_interactions: Dictionary = entry["time_interactions"]
	if time_interactions.size() != WEAPON_TIME_ABILITIES.size():
		return {"field": "time_interactions", "reason": "incomplete"}
	for ability_id: String in WEAPON_TIME_ABILITIES:
		if not time_interactions.has(ability_id):
			return {"field": "time_interactions.%s" % ability_id, "reason": "missing"}
	if not entry.get("boss_interactions") is Dictionary:
		return {"field": "boss_interactions", "reason": "missing"}
	if not (entry["boss_interactions"] as Dictionary).has("chrono_warden"):
		return {"field": "boss_interactions.chrono_warden", "reason": "missing"}
	return {}


func _character_runtime_profile_integration_error(entry: Dictionary) -> Dictionary:
	var mastery_value: Variant = entry.get("weapon_mastery")
	if not mastery_value is Dictionary:
		return {"field": "weapon_mastery", "reason": "missing"}
	var weapon_mastery: Dictionary = mastery_value
	var expected_weapons: Array[String] = []
	expected_weapons.append_array(
		["sword", "bow"]
		if str(entry.get("id", "")) == "wanderer_m1_v1"
		else CharacterRuntimeProfileScript.WEAPON_IDS
	)
	if weapon_mastery.size() != expected_weapons.size():
		return {"field": "weapon_mastery", "reason": "incomplete"}
	for weapon_id: String in expected_weapons:
		if not weapon_mastery.has(weapon_id):
			return {"field": "weapon_mastery.%s" % weapon_id, "reason": "missing"}
	var interactions_value: Variant = entry.get("time_interactions")
	if not interactions_value is Dictionary:
		return {"field": "time_interactions", "reason": "missing"}
	var time_interactions: Dictionary = interactions_value
	if time_interactions.size() != CharacterRuntimeProfileScript.TIME_ABILITY_IDS.size():
		return {"field": "time_interactions", "reason": "incomplete"}
	for ability_id: String in CharacterRuntimeProfileScript.TIME_ABILITY_IDS:
		if not time_interactions.has(ability_id):
			return {"field": "time_interactions.%s" % ability_id, "reason": "missing"}
	return {}



func _id_array_error(
	value: Variant,
	allowed_values: Array,
	allow_empty: bool,
	require_identifier: bool = true
) -> String:
	if not value is Array:
		return "type"
	if not allow_empty and (value as Array).is_empty():
		return "empty"
	var seen: Dictionary = {}
	for id_value: Variant in value:
		if typeof(id_value) != TYPE_STRING:
			return "entry_type"
		var content_id := str(id_value)
		if require_identifier and not _matches(CONTENT_ID_PATTERN, content_id):
			return "entry_value"
		if not allowed_values.is_empty() and not allowed_values.has(content_id):
			return "entry_unknown"
		if seen.has(content_id):
			return "duplicate"
		seen[content_id] = true
	return ""


func _optional_identifier_is_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (str(value).is_empty() or _matches(CONTENT_ID_PATTERN, value))


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _known_content_ids(pack_definitions: Array[Dictionary]) -> Dictionary:
	var ids: Dictionary = {}
	for content_id: Variant in _definitions.keys():
		ids[str(content_id)] = true
	for definition: Dictionary in pack_definitions:
		ids[str(definition["id"])] = true
	return ids


func _first_reference_error(
	pack_definitions: Array[Dictionary],
	available_ids: Dictionary
) -> Dictionary:
	var definitions_by_id: Dictionary = {}
	for existing_id: Variant in _definitions.keys():
		definitions_by_id[str(existing_id)] = _definitions[existing_id]
	for definition: Dictionary in pack_definitions:
		definitions_by_id[str(definition["id"])] = definition
	var specialized_reference_error := _first_specialized_reference_error(
		pack_definitions,
		definitions_by_id
	)
	if not specialized_reference_error.is_empty():
		return specialized_reference_error
	var profiles_by_archetype: Dictionary = {}
	for definition_value: Variant in definitions_by_id.values():
		if not definition_value is Dictionary:
			continue
		var profile_definition: Dictionary = definition_value
		if str(profile_definition.get("category", "")) != "archetype_profile":
			continue
		var profile_archetype_id := str(profile_definition.get("archetype_id", ""))
		if profiles_by_archetype.has(profile_archetype_id):
			return {
				"content_id": str(profile_definition.get("id", "")),
				"field": "archetype_id",
				"reference_id": profile_archetype_id,
				"reason": "duplicate_profile",
			}
		profiles_by_archetype[profile_archetype_id] = profile_definition
	for definition: Dictionary in pack_definitions:
		for reference_value: Variant in definition.get("references", []):
			var reference_id := str(reference_value)
			if not available_ids.has(reference_id):
				return {"content_id": str(definition["id"]), "reference_id": reference_id}
		var category := str(definition.get("category", ""))
		if category != "archetype_profile":
			var archetype_reference_error := _archetype_reference_error(
				definition,
				profiles_by_archetype
			)
			if not archetype_reference_error.is_empty():
				return archetype_reference_error
		var compatibility_reference_error := _compatibility_reference_error(
			definition,
			definitions_by_id
		)
		if not compatibility_reference_error.is_empty():
			return compatibility_reference_error
		if category == "weapon_runtime_profile":
			var weapon_id := str(definition.get("weapon_id", ""))
			var weapon_value: Variant = definitions_by_id.get(weapon_id)
			if not weapon_value is Dictionary or str((weapon_value as Dictionary).get("category", "")) != "weapon":
				return {"content_id": str(definition["id"]), "reference_id": weapon_id, "reason": "weapon_category"}
			var weapon_availability: Array = (weapon_value as Dictionary).get("availability", [])
			for milestone_value: Variant in definition.get("availability", []):
				if not weapon_availability.has(str(milestone_value)):
					return {
						"content_id": str(definition["id"]),
						"reference_id": weapon_id,
						"reason": "availability_widening",
						"milestone": str(milestone_value),
					}
			if not (weapon_value as Dictionary).get("references", []).has(str(definition["id"])):
				return {"content_id": str(definition["id"]), "reference_id": weapon_id, "reason": "weapon_back_reference"}
		if category == "character_runtime_profile":
			var character_id := str(definition.get("character_id", ""))
			var character_value: Variant = definitions_by_id.get(character_id)
			if not character_value is Dictionary or str((character_value as Dictionary).get("category", "")) != "character":
				return {"content_id": str(definition["id"]), "reference_id": character_id, "reason": "character_category"}
			var character_availability: Array = (character_value as Dictionary).get("availability", [])
			for milestone_value: Variant in definition.get("availability", []):
				if not character_availability.has(str(milestone_value)):
					return {
						"content_id": str(definition["id"]),
						"reference_id": character_id,
						"reason": "availability_widening",
						"milestone": str(milestone_value),
					}
			if not (character_value as Dictionary).get("references", []).has(str(definition["id"])):
				return {"content_id": str(definition["id"]), "reference_id": character_id, "reason": "character_back_reference"}
			var required_reference_error := _character_profile_required_reference_error(
				definition,
				definitions_by_id
			)
			if not required_reference_error.is_empty():
				return required_reference_error
			for talent_id_value: Variant in definition.get("talent_ids", []):
				var talent_id := str(talent_id_value)
				var talent_value: Variant = definitions_by_id.get(talent_id)
				if not talent_value is Dictionary or str((talent_value as Dictionary).get("category", "")) != "talent":
					return {
						"content_id": str(definition["id"]),
						"reference_id": talent_id,
						"reason": "talent_category",
					}
				for milestone_value: Variant in definition.get("availability", []):
					if not (talent_value as Dictionary).get("availability", []).has(str(milestone_value)):
						return {
							"content_id": str(definition["id"]),
							"reference_id": talent_id,
							"reason": "talent_availability",
							"milestone": str(milestone_value),
						}
				var talent_compatibility: Dictionary = (talent_value as Dictionary).get("compatibility", {})
				if not talent_compatibility.has("character_ids"):
					return {
						"content_id": str(definition["id"]),
						"reference_id": talent_id,
						"reason": "talent_character_scope_missing",
					}
				var talent_character_ids: Array = talent_compatibility["character_ids"]
				if talent_character_ids.size() != 1 or str(talent_character_ids[0]) != character_id:
					return {
						"content_id": str(definition["id"]),
						"reference_id": talent_id,
						"reason": "talent_character_mismatch",
					}
	return {}


func _first_specialized_reference_error(
	pack_definitions: Array[Dictionary],
	definitions_by_id: Dictionary
) -> Dictionary:
	for definition: Dictionary in pack_definitions:
		var category := str(definition.get("category", ""))
		if not SPECIALIZED_CATEGORIES.has(category):
			continue
		var reference_error: Dictionary = {}
		match category:
			"enemy_definition", "boss_definition", "summon_definition", "launch_encounter_profile", "launch_encounter_extension":
				reference_error = _specialized_reference_field_error(definition, "floor_id", "floor_definition", definitions_by_id)
				if reference_error.is_empty() and category == "launch_encounter_profile":
					reference_error = _specialized_reference_field_error(definition, "boss_id", "boss_definition", definitions_by_id)
					for recipe: Dictionary in definition.recipes:
						if not reference_error.is_empty():
							break
							reference_error = _specialized_reference_field_error({"id": definition.id, "availability": definition.availability, "template_ids": recipe.template_ids}, "template_ids", "room_template", definitions_by_id)
				if reference_error.is_empty() and category == "launch_encounter_extension":
					reference_error = _specialized_reference_field_error(definition, "profile_id", "launch_encounter_profile", definitions_by_id)
					for recipe: Dictionary in definition.recipes:
						if not reference_error.is_empty():
							break
						reference_error = _specialized_reference_field_error({"id": definition.id, "availability": definition.availability, "template_ids": recipe.template_ids}, "template_ids", "room_template", definitions_by_id)
			"floor_definition":
				reference_error = _specialized_reference_field_error(
					definition,
					"economy_profile_id",
					"economy_profile",
					definitions_by_id
				)
				if reference_error.is_empty():
					reference_error = _specialized_reference_field_error(
						definition,
						"merchant_ids",
						"merchant_definition",
						definitions_by_id
					)
				if reference_error.is_empty():
					for merchant_id: String in definition["merchant_ids"]:
						var merchant: Dictionary = definitions_by_id[merchant_id]
						var floor_number := int(definition["order"])
						if floor_number < int(merchant["floor_min"]) or floor_number > int(merchant["floor_max"]):
							reference_error = {
								"content_id": str(definition["id"]),
								"reference_id": merchant_id,
								"reason": "merchant_floor_range",
							}
							break
				if reference_error.is_empty():
					reference_error = _specialized_reference_field_error(
						definition,
						"event_ids",
						"dungeon_event",
						definitions_by_id
					)
				if reference_error.is_empty():
					reference_error = _specialized_reference_field_error(
						definition,
						"boss_room_template_id",
						"room_template",
						definitions_by_id
					)
				if reference_error.is_empty():
					reference_error = _closed_specialized_id_error(
						definition,
						"environment_rule_id",
						P14_ENVIRONMENT_RULE_IDS
					)
				if reference_error.is_empty():
					reference_error = _closed_specialized_id_error(
						definition,
						"encounter_profile_id",
						P14_ENCOUNTER_PROFILE_IDS
					)
				if reference_error.is_empty():
					reference_error = _closed_specialized_id_error(
						definition,
						"boss_encounter_id",
						P14_BOSS_ENCOUNTER_IDS
					)
			"room_template":
				for floor_field: String in ["floor_ids", "eligible_floor_ids"]:
					if not reference_error.is_empty() or not definition.has(floor_field):
						continue
					reference_error = _specialized_reference_field_error(
						definition,
						floor_field,
						"floor_definition",
						definitions_by_id
					)
				for rule_field: String in ["environment_rule_ids", "supported_environment_rule_ids"]:
					if not reference_error.is_empty() or not definition.has(rule_field):
						continue
					reference_error = _closed_specialized_id_error(
						definition,
						rule_field,
						P14_ENVIRONMENT_RULE_IDS
					)
			"dungeon_event", "merchant_definition":
				for floor_field: String in ["floor_ids", "eligible_floor_ids"]:
					if not reference_error.is_empty() or not definition.has(floor_field):
						continue
					reference_error = _specialized_reference_field_error(
						definition,
						floor_field,
						"floor_definition",
						definitions_by_id
					)
				if reference_error.is_empty() and definition.has("economy_profile_id"):
					reference_error = _specialized_reference_field_error(
						definition,
						"economy_profile_id",
						"economy_profile",
						definitions_by_id
					)
				if reference_error.is_empty() and definition.has("shop_room_template_ids"):
					reference_error = _specialized_reference_field_error(
						definition,
						"shop_room_template_ids",
						"room_template",
						definitions_by_id
					)
				if reference_error.is_empty() and category == "dungeon_event":
					reference_error = _dungeon_event_reference_error(definition)
		if not reference_error.is_empty():
			return reference_error
	return {}


func _dungeon_event_reference_error(definition: Dictionary) -> Dictionary:
	var allowed_encounters: Array[String] = []
	allowed_encounters.append_array(P14_ENCOUNTER_PROFILE_IDS)
	allowed_encounters.append_array(P14_BOSS_ENCOUNTER_IDS)
	var options: Array = definition.get("options", [])
	for option_index: int in range(options.size()):
		if not options[option_index] is Dictionary:
			continue
		var consequences: Array = (options[option_index] as Dictionary).get("consequences", [])
		for consequence_index: int in range(consequences.size()):
			if not consequences[consequence_index] is Dictionary:
				continue
			var consequence: Dictionary = consequences[consequence_index]
			if str(consequence.get("operation", "")) != "encounter_start":
				continue
			var encounter_id := str(consequence.get("arguments", {}).get("encounter_id", ""))
			if allowed_encounters.has(encounter_id):
				continue
			return {
				"content_id": str(definition.get("id", "")),
				"field": "options[%d].consequences[%d].arguments.encounter_id" % [
					option_index,
					consequence_index,
				],
				"reference_id": encounter_id,
				"reason": "closed_adapter_id",
			}
	return {}


func _specialized_reference_field_error(
	definition: Dictionary,
	field: String,
	expected_category: String,
	definitions_by_id: Dictionary
) -> Dictionary:
	if not definition.has(field):
		return {}
	var reference_values: Array = (
		(definition[field] as Array).duplicate()
		if definition[field] is Array
		else [definition[field]]
	)
	for reference_value: Variant in reference_values:
		var reference_id := str(reference_value)
		var target_value: Variant = definitions_by_id.get(reference_id)
		if (
			not target_value is Dictionary
			or str((target_value as Dictionary).get("category", "")) != expected_category
		):
			return {
				"content_id": str(definition.get("id", "")),
				"field": field,
				"reference_id": reference_id,
				"reason": "specialized_reference_category",
			}
		for milestone_value: Variant in definition.get("availability", []):
			if not (target_value as Dictionary).get("availability", []).has(str(milestone_value)):
				return {
					"content_id": str(definition.get("id", "")),
					"field": field,
					"reference_id": reference_id,
					"reason": "availability_widening",
					"milestone": str(milestone_value),
				}
	return {}


func _closed_specialized_id_error(
	definition: Dictionary,
	field: String,
	allowed_ids: Array[String]
) -> Dictionary:
	if not definition.has(field):
		return {}
	var reference_values: Array = (
		(definition[field] as Array).duplicate()
		if definition[field] is Array
		else [definition[field]]
	)
	for reference_value: Variant in reference_values:
		var reference_id := str(reference_value)
		if allowed_ids.has(reference_id):
			continue
		return {
			"content_id": str(definition.get("id", "")),
			"field": field,
			"reference_id": reference_id,
			"reason": "closed_adapter_id",
		}
	return {}


func _archetype_reference_error(
	definition: Dictionary,
	profiles_by_archetype: Dictionary
) -> Dictionary:
	var archetype_id := str(definition.get("archetype", ""))
	if not archetype_id.is_empty():
		var direct_error := _archetype_profile_reference_error(
			definition,
			archetype_id,
			"archetype",
			profiles_by_archetype
		)
		if not direct_error.is_empty():
			return direct_error
	var compatibility: Dictionary = definition.get("compatibility", {})
	for compatible_id_value: Variant in compatibility.get("archetype_ids", []):
		var compatibility_error := _archetype_profile_reference_error(
			definition,
			str(compatible_id_value),
			"compatibility.archetype_ids",
			profiles_by_archetype
		)
		if not compatibility_error.is_empty():
			return compatibility_error
	for tag_value: Variant in definition.get("tags", []):
		var tag := str(tag_value)
		if not ArchetypeProfileScript.ARCHETYPE_IDS.has(tag):
			continue
		var tag_error := _archetype_profile_reference_error(
			definition,
			tag,
			"tags",
			profiles_by_archetype
		)
		if not tag_error.is_empty():
			return tag_error
	return {}


func _archetype_profile_reference_error(
	definition: Dictionary,
	archetype_id: String,
	field: String,
	profiles_by_archetype: Dictionary
) -> Dictionary:
	var profile_value: Variant = profiles_by_archetype.get(archetype_id)
	if not profile_value is Dictionary:
		return {
			"content_id": str(definition.get("id", "")),
			"field": field,
			"reference_id": archetype_id,
			"reason": "archetype_profile_missing",
		}
	var profile: Dictionary = profile_value
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		if not definition.get("availability", []).has(milestone):
			continue
		if not profile.get("availability", []).has(milestone):
			return {
				"content_id": str(definition.get("id", "")),
				"field": field,
				"reference_id": archetype_id,
				"reason": "availability_widening",
				"milestone": milestone,
			}
	return {}


func _compatibility_reference_error(
	definition: Dictionary,
	definitions_by_id: Dictionary
) -> Dictionary:
	var compatibility_value: Variant = definition.get("compatibility", {})
	if not compatibility_value is Dictionary:
		return {
			"content_id": str(definition.get("id", "")),
			"field": "compatibility",
			"reason": "type",
		}
	var compatibility: Dictionary = compatibility_value
	for field_value: Variant in COMPATIBILITY_CATEGORY_BY_FIELD.keys():
		var field := str(field_value)
		if not compatibility.has(field):
			continue
		for compatible_id_value: Variant in compatibility[field]:
			var compatible_id := str(compatible_id_value)
			var compatible_value: Variant = definitions_by_id.get(compatible_id)
			if (
				not compatible_value is Dictionary
				or str((compatible_value as Dictionary).get("category", ""))
				!= str(COMPATIBILITY_CATEGORY_BY_FIELD[field_value])
			):
				return {
					"content_id": str(definition.get("id", "")),
					"reference_id": compatible_id,
					"field": "compatibility.%s" % field,
					"reason": "compatibility_category",
				}
			for milestone_value: Variant in definition.get("availability", []):
				if not (compatible_value as Dictionary).get("availability", []).has(str(milestone_value)):
					return {
						"content_id": str(definition.get("id", "")),
						"reference_id": compatible_id,
						"field": "compatibility.%s" % field,
						"reason": "availability_widening",
						"milestone": str(milestone_value),
					}
	return {}


func _character_profile_required_reference_error(
	definition: Dictionary,
	definitions_by_id: Dictionary
) -> Dictionary:
	var profile_id := str(definition.get("id", ""))
	var expected_categories: Dictionary = {}
	for weapon_id: String in CharacterRuntimeProfileScript.WEAPON_IDS:
		expected_categories[weapon_id] = "weapon"
	for ability_id: String in CharacterRuntimeProfileScript.TIME_ABILITY_IDS:
		expected_categories[ability_id] = "time_ability"
	for reference_id_value: Variant in expected_categories.keys():
		var reference_id := str(reference_id_value)
		if profile_id == "wanderer_m1_v1" and reference_id in ["gun", "staff", "gauntlets"]:
			continue
		var referenced_value: Variant = definitions_by_id.get(reference_id)
		if (
			not referenced_value is Dictionary
			or str((referenced_value as Dictionary).get("category", ""))
			!= str(expected_categories[reference_id_value])
		):
			return {
				"content_id": profile_id,
				"reference_id": reference_id,
				"reason": "%s_category" % str(expected_categories[reference_id_value]),
			}
		var required_milestones: Array = definition.get("availability", [])
		if profile_id == "wanderer_m1_v1":
			required_milestones = (
				["M1", "CURRENT", "NEXT"]
				if reference_id in ["sword", "stop", "rewind"]
				else ["NEXT"]
			)
		for milestone_value: Variant in required_milestones:
			if not (referenced_value as Dictionary).get("availability", []).has(str(milestone_value)):
				return {
					"content_id": profile_id,
					"reference_id": reference_id,
					"reason": "availability_widening",
					"milestone": str(milestone_value),
				}
	return {}


func _first_effect_capability_error(
	pack_definitions: Array[Dictionary],
	effect_catalog
) -> Dictionary:
	var definitions: Array[Dictionary] = []
	for existing_value: Variant in _definitions.values():
		if existing_value is Dictionary:
			definitions.append(existing_value as Dictionary)
	definitions.append_array(pack_definitions)
	var profiles_by_weapon: Dictionary = {}
	for definition: Dictionary in definitions:
		if str(definition.get("category", "")) != "weapon_runtime_profile":
			continue
		var weapon_id := str(definition.get("weapon_id", ""))
		if not profiles_by_weapon.has(weapon_id):
			profiles_by_weapon[weapon_id] = []
		(profiles_by_weapon[weapon_id] as Array).append(definition)
	for definition: Dictionary in definitions:
		if not EFFECT_BEARING_CATEGORIES.has(str(definition.get("category", ""))):
			continue
		var content_availability: Array = definition.get("availability", [])
		var compatibility_value: Variant = definition.get("compatibility", {})
		var compatible_weapons: Array = []
		if compatibility_value is Dictionary:
			var weapon_ids_value: Variant = (compatibility_value as Dictionary).get("weapon_ids", [])
			if weapon_ids_value is Array:
				compatible_weapons = weapon_ids_value
		var routes: Array[Dictionary] = effect_catalog.weapon_capability_routes(
			definition.get("effects", {})
		)
		var applicable_routes_by_weapon: Dictionary = {}
		for route: Dictionary in routes:
			var weapon_id := str(route.get("weapon_id", ""))
			if not compatible_weapons.is_empty() and not compatible_weapons.has(weapon_id):
				continue
			if not applicable_routes_by_weapon.has(weapon_id):
				applicable_routes_by_weapon[weapon_id] = []
			(applicable_routes_by_weapon[weapon_id] as Array).append(route)
		if not compatible_weapons.is_empty():
			for compatible_weapon_value: Variant in compatible_weapons:
				var compatible_weapon_id := str(compatible_weapon_value)
				var compatible_routes: Array = applicable_routes_by_weapon.get(compatible_weapon_id, [])
				if not routes.is_empty() and compatible_routes.is_empty():
					return {
						"content_id": str(definition.get("id", "")),
						"weapon_id": compatible_weapon_id,
						"reason": "no_executable_route",
					}
				var overlapping_profiles: Array[Dictionary] = []
				for profile_value: Variant in profiles_by_weapon.get(compatible_weapon_id, []):
					if (
						profile_value is Dictionary
						and _arrays_overlap(content_availability, (profile_value as Dictionary).get("availability", []))
					):
						overlapping_profiles.append(profile_value as Dictionary)
				if overlapping_profiles.is_empty():
					return {
						"content_id": str(definition.get("id", "")),
						"weapon_id": compatible_weapon_id,
						"reason": "compatible_profile_missing",
					}
		for weapon_id_value: Variant in applicable_routes_by_weapon.keys():
			var weapon_id := str(weapon_id_value)
			for route_value: Variant in applicable_routes_by_weapon[weapon_id_value]:
				if not route_value is Dictionary:
					continue
				var route: Dictionary = route_value
				var capability := str(route.get("capability", ""))
				for profile_value: Variant in profiles_by_weapon.get(weapon_id, []):
					if not profile_value is Dictionary:
						continue
					var profile: Dictionary = profile_value
					if not _arrays_overlap(content_availability, profile.get("availability", [])):
						continue
					if not (profile.get("capabilities", []) as Array).has(capability):
						return {
							"content_id": str(definition.get("id", "")),
							"effect_id": str(route.get("effect_id", "")),
							"weapon_id": weapon_id,
							"profile_id": str(profile.get("id", "")),
							"capability": capability,
							"reason": "unsupported_capability",
						}
	return {}


func _arrays_overlap(left: Array, right: Array) -> bool:
	for value: Variant in left:
		if right.has(value):
			return true
	return false


func _first_isolated_dependency(descriptor: Dictionary, isolated_ids: Dictionary) -> String:
	for dependency_value: Variant in descriptor.get("dependencies", []):
		if not dependency_value is Dictionary:
			continue
		var dependency: Dictionary = dependency_value
		if bool(dependency.get("required", true)) and isolated_ids.has(str(dependency.get("pack_id", ""))):
			return str(dependency.get("pack_id", ""))
	return ""


func _category_counts() -> Dictionary:
	var counts: Dictionary = {}
	for definition: Dictionary in _definitions.values():
		var category := str(definition.get("category", ""))
		counts[category] = int(counts.get(category, 0)) + 1
	return counts


func _active_pack_ids() -> Array[String]:
	var ids: Array[String] = []
	for descriptor: Dictionary in _active_packs:
		ids.append(str(descriptor.get("pack_id", "")))
	return ids


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values.keys():
		result.append(str(value))
	result.sort()
	return result
