class_name CharacterTalentState
extends RefCounted

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

var _configured: bool = false
var _character_id: StringName = &""
var _selected_talent_ids: Array[String] = []
var _modifiers: Dictionary = {}
var _revision: int = 0


static func canonical_catalog() -> Dictionary:
	var result: Dictionary = {}
	for character_id: StringName in CHARACTER_ORDER:
		result[character_id] = (TALENT_CATALOG[character_id] as Array).duplicate()
	return result


func configure(character_id_value: Variant, talents: Variant) -> bool:
	if typeof(character_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var character_id := StringName(str(character_id_value).strip_edges())
	if not TALENT_CATALOG.has(character_id):
		return false
	var canonical := _canonical_subset(character_id, talents)
	if not bool(canonical.get("ok", false)):
		return false
	var selected: Array[String] = canonical.get("talents", [])
	var modifiers := _modifiers_for(character_id, selected)
	if modifiers.is_empty():
		return false

	_character_id = character_id
	_selected_talent_ids = selected.duplicate()
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


static func _modifiers_for(character_id: StringName, selected: Array[String]) -> Dictionary:
	match character_id:
		&"wanderer":
			return {
				"low_energy_threshold": 30,
				"low_energy_regen_multiplier": 2.0 if selected.has("tal_eternity_reserve") else 1.0,
				"wayfarer_energy_restore": 8 if selected.has("tal_eternity_reserve") else 6,
				"heavy_execute_hp_ratio": 0.30,
				"heavy_execute_multiplier_bonus": 0.5 if selected.has("tal_ruin_execute") else 0.0,
				"wayfarer_bonus_progress": 1 if selected.has("tal_ruin_execute") else 0,
				"max_hp_bonus": 20 if selected.has("tal_steel_recover") else 0,
				"acquisition_heal": 20 if selected.has("tal_steel_recover") else 0,
				"room_clear_hp_per_mark": 3 if selected.has("tal_steel_recover") else 2,
			}
		&"time_guardian":
			return {
				"perfect_last_frame": 11 if selected.has("widened_guard") else 8,
				"normal_last_frame": 26 if selected.has("widened_guard") else 23,
				"close_frame": 27 if selected.has("widened_guard") else 24,
				"fortress_ward_cost": 2 if selected.has("fortress_core") else 3,
				"rebuke_echo_multiplier": 1.0 if selected.has("temporal_rebuke") else 0.75,
				"cooldown_reduction_frames": 45 if selected.has("temporal_rebuke") else 30,
			}
		&"void_walker":
			return {
				"debt_cap": 120 if selected.has("deep_debt") else 100,
				"corruption_threshold": 75 if selected.has("deep_debt") else 60,
				"devour_heal_ratio": 0.18 if selected.has("bounded_devour") else 0.15,
				"devour_heal_cap_ratio": 0.16 if selected.has("bounded_devour") else 0.12,
				"risk_radius": 288 if selected.has("risk_step") else 240,
				"mastery_conversion_cap": 25 if selected.has("risk_step") else 20,
			}
		&"primordial_knight":
			return {
				"armor_recovery_extension_frames": 12 if selected.has("resonant_plate") else 0,
				"echo_multiplier": 1.0 if selected.has("echo_forge") else 0.75,
				"instability_frames": 600 if selected.has("realm_collapse") else 480,
			}
		&"time_lord":
			return {
				"pair_window_frames": 420 if selected.has("codex_margin") else 300,
				"infusion_energy_cost": 5 if selected.has("efficient_inscription") else 10,
				"dominion_energy_cost": 45 if selected.has("dominion_cadence") else 60,
				"dominion_cooldown_frames": 360 if selected.has("dominion_cadence") else 480,
			}
	return {}


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
