class_name CharacterTalentState
extends RefCounted

const EffectHandlerCatalogScript := preload(
	"res://scripts/content/effects/effect_handler_catalog.gd"
)

const SNAPSHOT_SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"configured",
	"character_id",
	"selected_talent_ids",
	"modifiers",
	"revision",
]
const CHARACTER_ORDER: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]
const TALENT_CATALOG := {
	&"wanderer": [&"tal_eternity_reserve", &"tal_ruin_execute", &"tal_steel_recover"],
	&"time_guardian": [&"widened_guard", &"fortress_core", &"temporal_rebuke"],
	&"void_walker": [&"deep_debt", &"bounded_devour", &"risk_step"],
	&"primordial_knight": [&"resonant_plate", &"echo_forge", &"realm_collapse"],
	&"time_lord": [&"codex_margin", &"efficient_inscription", &"dominion_cadence"],
}
const BASE_MODIFIERS := {
	&"wanderer": {
		"low_energy_threshold": 30,
		"low_energy_regen_multiplier": 1.0,
		"wayfarer_energy_restore": 6,
		"heavy_execute_hp_ratio": 0.30,
		"heavy_execute_multiplier_bonus": 0.0,
		"wayfarer_bonus_progress": 0,
		"max_hp_bonus": 0,
		"acquisition_heal": 0,
		"room_clear_hp_per_mark": 2,
	},
	&"time_guardian": {
		"perfect_last_frame": 8,
		"normal_last_frame": 23,
		"close_frame": 24,
		"fortress_ward_cost": 3,
		"rebuke_echo_multiplier": 0.75,
		"cooldown_reduction_frames": 30,
	},
	&"void_walker": {
		"debt_cap": 100,
		"corruption_threshold": 60,
		"devour_heal_ratio": 0.15,
		"devour_heal_cap_ratio": 0.12,
		"risk_radius": 240,
		"mastery_conversion_cap": 20,
	},
	&"primordial_knight": {
		"armor_recovery_extension_frames": 0,
		"echo_multiplier": 0.75,
		"instability_frames": 480,
	},
	&"time_lord": {
		"pair_window_frames": 300,
		"infusion_energy_cost": 10,
		"dominion_energy_cost": 60,
		"dominion_cooldown_frames": 480,
	},
}
const TALENT_EFFECTS := {
	&"tal_eternity_reserve": [
		"low_energy_regen_multiplier", "low_energy_threshold",
		"talent_wayfarer_energy_restore",
	],
	&"tal_ruin_execute": [
		"heavy_execute_multiplier_bonus", "heavy_execute_threshold",
		"talent_wayfarer_bonus_progress",
	],
	&"tal_steel_recover": [
		"max_hp_bonus", "heal", "talent_room_clear_heal_per_mark",
	],
	&"widened_guard": [
		"talent_guard_perfect_last_frame", "talent_guard_normal_last_frame",
		"talent_guard_close_frame",
	],
	&"fortress_core": ["talent_fortress_ward_cost"],
	&"temporal_rebuke": [
		"talent_rebuke_echo_multiplier", "talent_cooldown_reduction_frames",
	],
	&"deep_debt": ["talent_debt_cap", "talent_corruption_threshold"],
	&"bounded_devour": [
		"talent_devour_heal_ratio", "talent_devour_heal_cap_ratio",
	],
	&"risk_step": ["talent_risk_radius", "talent_mastery_conversion_cap"],
	&"resonant_plate": ["talent_armor_recovery_extension_frames"],
	&"echo_forge": ["talent_echo_multiplier"],
	&"realm_collapse": ["talent_instability_frames"],
	&"codex_margin": ["talent_pair_window_frames"],
	&"efficient_inscription": ["talent_infusion_energy_cost"],
	&"dominion_cadence": [
		"talent_dominion_energy_cost", "talent_dominion_cooldown_frames",
	],
}
const MODIFIER_BY_EFFECT := {
	"low_energy_regen_multiplier": "low_energy_regen_multiplier",
	"low_energy_threshold": "low_energy_threshold",
	"talent_wayfarer_energy_restore": "wayfarer_energy_restore",
	"heavy_execute_multiplier_bonus": "heavy_execute_multiplier_bonus",
	"heavy_execute_threshold": "heavy_execute_hp_ratio",
	"talent_wayfarer_bonus_progress": "wayfarer_bonus_progress",
	"max_hp_bonus": "max_hp_bonus",
	"heal": "acquisition_heal",
	"talent_room_clear_heal_per_mark": "room_clear_hp_per_mark",
	"talent_guard_perfect_last_frame": "perfect_last_frame",
	"talent_guard_normal_last_frame": "normal_last_frame",
	"talent_guard_close_frame": "close_frame",
	"talent_fortress_ward_cost": "fortress_ward_cost",
	"talent_rebuke_echo_multiplier": "rebuke_echo_multiplier",
	"talent_cooldown_reduction_frames": "cooldown_reduction_frames",
	"talent_debt_cap": "debt_cap",
	"talent_corruption_threshold": "corruption_threshold",
	"talent_devour_heal_ratio": "devour_heal_ratio",
	"talent_devour_heal_cap_ratio": "devour_heal_cap_ratio",
	"talent_risk_radius": "risk_radius",
	"talent_mastery_conversion_cap": "mastery_conversion_cap",
	"talent_armor_recovery_extension_frames": "armor_recovery_extension_frames",
	"talent_echo_multiplier": "echo_multiplier",
	"talent_instability_frames": "instability_frames",
	"talent_pair_window_frames": "pair_window_frames",
	"talent_infusion_energy_cost": "infusion_energy_cost",
	"talent_dominion_energy_cost": "dominion_energy_cost",
	"talent_dominion_cooldown_frames": "dominion_cooldown_frames",
}

var _configured: bool = false
var _character_id: StringName = &""
var _selected_talent_ids: Array[String] = []
var _definitions: Array[Dictionary] = []
var _modifiers: Dictionary = {}
var _revision: int = 0


static func canonical_catalog() -> Dictionary:
	var result: Dictionary = {}
	for character_id: StringName in CHARACTER_ORDER:
		result[character_id] = (TALENT_CATALOG[character_id] as Array).duplicate()
	return result


func configure(
	character_id_value: Variant,
	talents: Variant,
	definitions: Variant = []
) -> bool:
	if typeof(character_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var character_id := StringName(str(character_id_value).strip_edges())
	if not TALENT_CATALOG.has(character_id):
		return false
	var canonical := _canonical_subset(character_id, talents)
	if not bool(canonical.get("ok", false)):
		return false
	var selected: Array[String] = canonical.get("talents", [])
	var normalized_definitions := _normalized_definitions(character_id, selected, definitions)
	if not bool(normalized_definitions.get("ok", false)):
		return false
	var selected_definitions: Array[Dictionary] = normalized_definitions.get("definitions", [])
	var modifiers := _modifiers_for(character_id, selected, selected_definitions)
	if modifiers.is_empty():
		return false

	_character_id = character_id
	_selected_talent_ids = selected.duplicate()
	_definitions = selected_definitions.duplicate(true)
	_modifiers = modifiers.duplicate(true)
	_configured = true
	_revision += 1
	return true


func character_id() -> StringName:
	return _character_id


func selected_talent_ids() -> Array[String]:
	return _selected_talent_ids.duplicate()


func modifier_snapshot() -> Dictionary:
	return _modifiers.duplicate(true)


func definition_snapshots() -> Array[Dictionary]:
	return _definitions.duplicate(true)


func freeze_for_commit(source_kind_value: Variant, token: int, generation: int) -> Dictionary:
	if (
		not _configured
		or typeof(source_kind_value) not in [TYPE_STRING, TYPE_STRING_NAME]
		or not _valid_segment(source_kind_value)
		or token <= 0
		or generation <= 0
	):
		return {}
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"character_id": str(_character_id),
		"selected_talent_ids": _selected_talent_ids.duplicate(),
		"modifiers": _modifiers.duplicate(true),
		"state_revision": _revision,
		"source_kind": str(source_kind_value),
		"token": token,
		"generation": generation,
	}


func reset_runtime_state(_reason: StringName) -> void:
	if _configured:
		_revision += 1


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _configured,
		"character_id": str(_character_id),
		"selected_talent_ids": _selected_talent_ids.duplicate(),
		"modifiers": _modifiers.duplicate(true),
		"revision": _revision,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value["configured"]) != TYPE_BOOL
		or bool(value["configured"]) != _configured
		or typeof(value["character_id"]) != TYPE_STRING
		or not value["selected_talent_ids"] is Array
		or not value["modifiers"] is Dictionary
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return false
	if not _configured:
		return (
			str(value["character_id"]).is_empty()
			and (value["selected_talent_ids"] as Array).is_empty()
			and (value["modifiers"] as Dictionary).is_empty()
		)
	return (
		StringName(value["character_id"]) == _character_id
		and value["selected_talent_ids"] == _selected_talent_ids
		and value["modifiers"] == _modifiers
	)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_revision = int(value["revision"])
	return snapshot() == value


static func _canonical_subset(character_id: StringName, talents: Variant) -> Dictionary:
	if not talents is Array and not talents is PackedStringArray:
		return {"ok": false}
	var requested: Array[String] = []
	for talent_value: Variant in talents:
		if typeof(talent_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {"ok": false}
		var talent_id := str(talent_value).strip_edges()
		if talent_id.is_empty() or requested.has(talent_id):
			return {"ok": false}
		requested.append(talent_id)
	var allowed: Array = TALENT_CATALOG[character_id]
	for talent_id: String in requested:
		if not allowed.has(StringName(talent_id)):
			return {"ok": false}
	var canonical: Array[String] = []
	for talent_id_value: Variant in allowed:
		var talent_id := str(talent_id_value)
		if requested.has(talent_id):
			canonical.append(talent_id)
	return {"ok": true, "talents": canonical}


static func _normalized_definitions(
	character_id: StringName,
	selected: Array[String],
	definitions: Variant
) -> Dictionary:
	if not definitions is Array or (definitions as Array).size() != selected.size():
		return {"ok": false}
	var by_id: Dictionary = {}
	for definition_value: Variant in definitions:
		if not definition_value is Dictionary:
			return {"ok": false}
		var definition := (definition_value as Dictionary).duplicate(true)
		var talent_id := str(definition.get("id", ""))
		var compatibility: Variant = definition.get("compatibility", {})
		if (
			talent_id.is_empty()
			or by_id.has(talent_id)
			or not selected.has(talent_id)
			or str(definition.get("category", "")) != "talent"
			or not compatibility is Dictionary
			or (compatibility as Dictionary).get("character_ids", []) != [str(character_id)]
			or not definition.get("effects") is Dictionary
			or (definition.get("effects") as Dictionary).is_empty()
		):
			return {"ok": false}
		var allowed_effects: Array = TALENT_EFFECTS.get(StringName(talent_id), [])
		var effect_keys: Array = (definition["effects"] as Dictionary).keys()
		effect_keys.sort()
		var expected_effects := allowed_effects.duplicate()
		expected_effects.sort()
		if effect_keys != expected_effects:
			return {"ok": false}
		var catalog = EffectHandlerCatalogScript.new()
		var report = catalog.validate_effects(definition["effects"], {"category": "talent"})
		if report.has_blocking_errors():
			return {"ok": false}
		definition["effects"] = catalog.normalize_effects(definition["effects"])
		by_id[talent_id] = definition

	var canonical: Array[Dictionary] = []
	for talent_id: String in selected:
		if not by_id.has(talent_id):
			return {"ok": false}
		canonical.append((by_id[talent_id] as Dictionary).duplicate(true))
	return {"ok": true, "definitions": canonical}


static func _modifiers_for(
	character_id: StringName,
	selected: Array[String],
	definitions: Array[Dictionary]
) -> Dictionary:
	if not BASE_MODIFIERS.has(character_id) or definitions.size() != selected.size():
		return {}
	var modifiers: Dictionary = (BASE_MODIFIERS[character_id] as Dictionary).duplicate(true)
	for index: int in range(selected.size()):
		if str(definitions[index].get("id", "")) != selected[index]:
			return {}
		var effects: Dictionary = definitions[index].get("effects", {})
		for effect_value: Variant in effects.keys():
			var effect_id := str(effect_value)
			if not MODIFIER_BY_EFFECT.has(effect_id):
				return {}
			var modifier_id := str(MODIFIER_BY_EFFECT[effect_id])
			if not modifiers.has(modifier_id):
				return {}
			var baseline_value: Variant = modifiers[modifier_id]
			var selected_value: Variant = effects[effect_value]
			if typeof(baseline_value) == TYPE_INT:
				if typeof(selected_value) not in [TYPE_INT, TYPE_FLOAT] or float(selected_value) != floorf(float(selected_value)):
					return {}
				modifiers[modifier_id] = int(selected_value)
			elif typeof(baseline_value) == TYPE_FLOAT:
				if typeof(selected_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(selected_value)):
					return {}
				modifiers[modifier_id] = float(selected_value)
			else:
				return {}
	return modifiers


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	return (
		not text.is_empty()
		and text == text.strip_edges()
		and not text.contains("\n")
		and not text.contains("\r")
		and not text.contains("\t")
		and text.length() <= 64
	)


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not fields.has(str(key)):
			return false
	return true
