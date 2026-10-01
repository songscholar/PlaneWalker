class_name CharacterRuntimeProfile
extends RefCounted

const ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,63}$"
const LOCALIZATION_KEY_PATTERN := "^[A-Z][A-Z0-9_]{1,127}$"
const PARAMETER_KEY_PATTERN := "^[a-z][a-z0-9_.-]{0,95}$"

const REQUIRED_FIELDS: Array[String] = [
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
const MILESTONES: Array[String] = ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]
const CHARACTER_IDS: Array[String] = [
	"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
]
const WEAPON_IDS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_ABILITY_IDS: Array[String] = ["stop", "rewind", "accelerate", "rift"]
const COMPATIBILITY_FIELDS: Array[String] = [
	"character_ids", "weapon_ids", "time_ability_ids", "archetype_ids", "modes",
]
const RUNTIME_KINDS: Array[String] = [
	"wanderer_m1_compat", "wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
]
const RESOURCE_HANDLERS: Array[String] = [
	"none", "path_marks", "ward", "void_debt", "resonance", "codex_pages",
]
const PASSIVE_HANDLERS: Array[String] = [
	"none", "wanderer_path", "chrono_bulwark", "void_debt", "planar_resonance", "chrono_codex",
]
const SKILL_HANDLERS: Array[String] = [
	"none", "waypoint_recall", "chrono_fortress", "void_devour", "realm_cleave", "codex_dominion",
]
const MASTERY_HANDLERS: Array[String] = [
	"none", "wanderer_mastery", "time_guardian_mastery", "void_walker_mastery",
	"primordial_knight_mastery", "time_lord_mastery",
]
const TIME_HANDLERS: Array[String] = [
	"none",
	"wanderer_stop", "wanderer_rewind", "wanderer_accelerate", "wanderer_rift",
	"time_guardian_stop", "time_guardian_rewind", "time_guardian_accelerate", "time_guardian_rift",
	"void_walker_stop", "void_walker_rewind", "void_walker_accelerate", "void_walker_rift",
	"primordial_knight_stop", "primordial_knight_rewind", "primordial_knight_accelerate", "primordial_knight_rift",
	"time_lord_stop", "time_lord_rewind", "time_lord_accelerate", "time_lord_rift",
]
const PALETTE_IDS: Array[String] = CHARACTER_IDS
const METER_IDS: Array[String] = ["none", "path_marks", "ward", "void_debt", "resonance", "codex_pages"]
const CUE_IDS: Array[String] = [
	"none", "waypoint_recall", "chrono_fortress", "void_devour", "realm_cleave", "codex_dominion",
]
const TALENT_IDS: Array[String] = [
	"tal_eternity_reserve", "tal_ruin_execute", "tal_steel_recover",
	"widened_guard", "fortress_core", "temporal_rebuke",
	"deep_debt", "bounded_devour", "risk_step",
	"resonant_plate", "echo_forge", "realm_collapse",
	"codex_margin", "efficient_inscription", "dominion_cadence",
]
const BASE_STAT_FIELDS: Array[String] = [
	"max_hp", "attack", "defense", "move_speed", "attack_speed", "crit_chance",
	"crit_multiplier", "time_energy_max", "time_energy_regen",
]
const MOBILITY_FIELDS: Array[String] = [
	"dash_duration_frames", "dash_cooldown_frames", "dash_speed", "dash_cost_kind",
	"dash_cost", "dash_invulnerable_frames",
]
const RESOURCE_FIELDS: Array[String] = [
	"resource_id", "handler_id", "minimum", "maximum", "initial", "gain_cap_per_action",
]
const PASSIVE_FIELDS: Array[String] = ["handler_id", "parameters"]
const SKILL_FIELDS: Array[String] = [
	"skill_id", "handler_id", "cooldown_frames", "energy_cost", "hold_threshold_frames", "parameters",
]
const MASTERY_FIELDS: Array[String] = ["handler_id", "mastery_family", "parameters"]
const TIME_INTERACTION_FIELDS: Array[String] = ["handler_id", "parameters"]
const PRESENTATION_FIELDS: Array[String] = ["palette_id", "meter_id", "skill_cue_id"]
const EXECUTION_KEY_FRAGMENTS: Array[String] = ["script", "method", "callable"]
const MAX_PARAMETER_DEPTH := 4

const PASSIVE_PARAMETER_CONTRACTS := {
	"none": {},
	"wanderer_path": {
		"progress_threshold": 3, "wayfarer_window_frames": 180, "first_room_immediate": true,
		"wayfarer_energy_restore": 6, "wayfarer_heal_ratio": 0.02,
		"room_clear_heal_per_mark": 2, "forgiveness_expiry_frames": 180,
		"sword_recovery_reduction_frames": 4, "bow_full_charge_frames": 44,
		"gun_reload_perfect_start": 26, "gun_reload_perfect_end": 37,
		"staff_window_extension_frames": 60, "staff_window_cap_frames": 360,
		"gauntlets_combo_extension_frames": 30, "gauntlets_combo_cap_frames": 150,
	},
	"chrono_bulwark": {
		"damage_reduction": 0.35, "rebuke_window_frames": 180,
		"rebuke_echo_multiplier": 0.75, "cooldown_reduction_frames": 30,
	},
	"void_debt": {
		"corruption_threshold": 60, "corruption_tick_damage": 1,
		"corruption_tick_frames": 30, "conversion_cap": 20, "risk_radius": 240,
		"echo_radius": 160, "echo_multiplier": 0.75, "conversion_heal_cap": 6,
	},
	"planar_resonance": {
		"reservation_cost": 3, "armor_reduction": 0.35,
		"echo_multiplier": 0.75, "echo_release_after_recovery": true,
	},
	"chrono_codex": {
		"pair_window_frames": 300, "primer_page_cost": 1, "page_rate_cap_frames": 60,
	},
}
const SKILL_PARAMETER_CONTRACTS := {
	"none": {},
	"waypoint_recall": {
		"windup_frames": 6, "recovery_frames": 12, "anchor_frames": 480,
		"healing_ratio": 0.25,
	},
	"chrono_fortress": {
		"perfect_last_frame": 8, "normal_last_frame": 23, "close_frame": 24,
		"duration_frames": 180, "ward_cost": 3, "fortress_cooldown_frames": 600,
		"movement_multiplier": 0.7, "frontal_reduction": 0.5,
		"frontal_cone_degrees": 120, "shockwave_radius": 192,
		"shockwave_multiplier": 1.0,
	},
	"void_devour": {
		"windup_frames": 24, "active_frames": 1, "recovery_frames": 30,
		"health_cost_ratio": 0.2, "minimum_health_cost": 10,
		"damage_multiplier": 4.0, "cone_tiles": 8, "cone_degrees": 60,
		"heal_ratio": 0.15, "heal_cap_ratio": 0.12,
	},
	"realm_cleave": {
		"windup_frames": 36, "active_frames": 1, "recovery_frames": 30,
		"armor_reduction": 0.4, "base_multiplier": 1.5, "stack_multiplier": 0.35,
		"radius_tiles": 5, "instability_frames": 480, "instability_bonus": 0.2,
	},
	"codex_dominion": {
		"infusion_duration_frames": 300, "infusion_echo_multiplier": 2.0,
		"dominion_energy_cost": 60, "dominion_page_cost": 2,
		"dominion_cooldown_frames": 480, "dominion_charge_frames": 300,
	},
}
const EMPTY_MASTERY_PARAMETER_HANDLERS: Array[String] = [
	"none", "wanderer_mastery", "time_guardian_mastery", "void_walker_mastery", "time_lord_mastery",
]
const PRIMORDIAL_MASTERY_PARAMETER_CONTRACTS := {
	"sword": {"commitment_action": "charged_slash", "minimum_hold_frames": 30},
	"bow": {"commitment_action": "precision_draw", "requires_full_charge": true},
	"gun": {"commitment_action": "aimed_fire", "minimum_hold_frames": 18},
	"staff": {"commitment_action": "charged_element", "minimum_hold_frames": 30},
	"gauntlets": {"commitment_action": "charged_heavy", "minimum_hold_frames": 30},
}
const TIME_PARAMETER_CONTRACTS := {
	"none": {},
	"wanderer_stop": {"window_bonus_frames": 60},
	"wanderer_rewind": {"preserve_anchor": true},
	"wanderer_accelerate": {"progress_threshold": 2},
	"wanderer_rift": {"progress_bonus": 1},
	"time_guardian_stop": {"boss_exposure_only": true},
	"time_guardian_rewind": {"preserve_guard_claims": true},
	"time_guardian_accelerate": {"fixed_guard_frames": true},
	"time_guardian_rift": {"requires_full_ward": true},
	"void_walker_stop": {"pause_corruption": true},
	"void_walker_rewind": {"preserve_self_cost": true},
	"void_walker_accelerate": {"preserve_corruption_budget": true},
	"void_walker_rift": {"additional_debt_cost": 10},
	"primordial_knight_stop": {"release_echo_on_end": true},
	"primordial_knight_rewind": {"preserve_world_echo": true},
	"primordial_knight_accelerate": {"shorten_echo_delay": true},
	"primordial_knight_rift": {"anchor_once_per_generation": true},
	"time_lord_stop": {
		"rewind_zone_radius": 96, "rewind_zone_frames": 90, "rewind_zone_speed_scalar": 0.5,
		"rewind_dominion_zone_radius": 128, "rewind_dominion_zone_frames": 150,
		"rewind_dominion_speed_scalar": 0.35, "rift_projectile_speed_scalar": 0.5,
		"rift_overlap_cap_frames": 180, "rift_dominion_projectile_speed_scalar": 0.35,
		"rift_dominion_overlap_cap_frames": 240, "accelerate_recovery_multiplier": 0.8,
		"accelerate_recovery_frames": 90, "accelerate_dominion_recovery_multiplier": 0.65,
		"accelerate_dominion_recovery_frames": 150,
	},
	"time_lord_rewind": {
		"freeze_pre_return_position": true, "rift_pulse_multiplier": 1.25,
		"rift_dominion_pulse_multiplier": 1.75, "accelerate_echo_frames": 180,
		"accelerate_echo_multiplier": 0.75, "accelerate_dominion_echo_frames": 300,
		"accelerate_dominion_echo_multiplier": 1.1,
	},
	"time_lord_accelerate": {
		"rift_tick_interval_multiplier": 0.75, "rift_tick_cap_frames": 180,
		"rift_dominion_tick_interval_multiplier": 0.5, "rift_dominion_tick_cap_frames": 240,
	},
	"time_lord_rift": {
		"preserve_committed_tick_count": true, "preserve_total_damage": true,
	},
}

var profile_id: StringName = &""
var profile_version: int = 0
var character_id: StringName = &""
var availability: PackedStringArray = PackedStringArray()
var runtime_kind: StringName = &""
var base_stats: Dictionary = {}
var mobility: Dictionary = {}
var resource: Dictionary = {}
var passive: Dictionary = {}
var character_skill: Dictionary = {}
var weapon_mastery: Dictionary = {}
var time_interactions: Dictionary = {}
var presentation: Dictionary = {}
var capabilities: PackedStringArray = PackedStringArray()
var talent_ids: PackedStringArray = PackedStringArray()

var _snapshot: Dictionary = {}


static func from_definition(definition: Dictionary):
	var profile = new()
	var result := profile.configure(definition)
	return profile if bool(result.get("ok", false)) else null


func configure(source: Dictionary) -> Dictionary:
	var validation := _validate_and_normalize(source)
	if not bool(validation.get("ok", false)):
		return validation
	_snapshot = (validation["profile"] as Dictionary).duplicate(true)
	_project_fields()
	return {"ok": true, "profile": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _project_fields() -> void:
	profile_id = StringName(str(_snapshot["id"]))
	profile_version = int(_snapshot["profile_version"])
	character_id = StringName(str(_snapshot["character_id"]))
	availability = PackedStringArray(_snapshot["availability"])
	runtime_kind = StringName(str(_snapshot["runtime_kind"]))
	base_stats = (_snapshot["base_stats"] as Dictionary).duplicate(true)
	mobility = (_snapshot["mobility"] as Dictionary).duplicate(true)
	resource = (_snapshot["resource"] as Dictionary).duplicate(true)
	passive = (_snapshot["passive"] as Dictionary).duplicate(true)
	character_skill = (_snapshot["character_skill"] as Dictionary).duplicate(true)
	weapon_mastery = (_snapshot["weapon_mastery"] as Dictionary).duplicate(true)
	time_interactions = (_snapshot["time_interactions"] as Dictionary).duplicate(true)
	presentation = (_snapshot["presentation"] as Dictionary).duplicate(true)
	capabilities = PackedStringArray(_snapshot["capabilities"])
	talent_ids = PackedStringArray(_snapshot["talent_ids"])


func _validate_and_normalize(source: Dictionary) -> Dictionary:
	var root_error := _exact_fields_error(source, REQUIRED_FIELDS, "profile")
	if not root_error.is_empty():
		return root_error
	if not _matches(ID_PATTERN, source["id"]):
		return _failure("id", "invalid")
	if source["category"] != "character_runtime_profile":
		return _failure("category", "unsupported")
	var availability_error := _string_list_error(source["availability"], MILESTONES, false, "availability")
	if not availability_error.is_empty():
		return availability_error
	if not _matches(LOCALIZATION_KEY_PATTERN, source["name_key"]):
		return _failure("name_key", "invalid")
	if not _matches(LOCALIZATION_KEY_PATTERN, source["description_key"]):
		return _failure("description_key", "invalid")
	var tags_error := _string_list_error(source["tags"], [], true, "tags")
	if not tags_error.is_empty():
		return tags_error
	var compatibility_error := _compatibility_error(source["compatibility"])
	if not compatibility_error.is_empty():
		return compatibility_error
	if not source["effects"] is Dictionary or not (source["effects"] as Dictionary).is_empty():
		return _failure("effects", "must_be_empty")
	var references_error := _string_list_error(source["references"], [], false, "references")
	if not references_error.is_empty():
		return references_error
	if not _is_positive_integer(source["profile_version"]) or int(source["profile_version"]) != 1:
		return _failure("profile_version", "unsupported_version")
	if typeof(source["character_id"]) != TYPE_STRING or not CHARACTER_IDS.has(str(source["character_id"])):
		return _failure("character_id", "unsupported")
	if typeof(source["runtime_kind"]) != TYPE_STRING or not RUNTIME_KINDS.has(str(source["runtime_kind"])):
		return _failure("runtime_kind", "unsupported")

	var identity_error := _identity_error(source)
	if not identity_error.is_empty():
		return identity_error
	var stats_error := _base_stats_error(source["base_stats"])
	if not stats_error.is_empty():
		return stats_error
	var mobility_error := _mobility_error(source["mobility"])
	if not mobility_error.is_empty():
		return mobility_error
	var resource_error := _resource_error(source["resource"])
	if not resource_error.is_empty():
		return resource_error
	var passive_error := _handler_descriptor_error(
		source["passive"], PASSIVE_FIELDS, PASSIVE_HANDLERS, "passive"
	)
	if not passive_error.is_empty():
		return passive_error
	var passive_parameters_error := _closed_parameters_error(
		source["passive"]["parameters"],
		PASSIVE_PARAMETER_CONTRACTS[str(source["passive"]["handler_id"])],
		"passive.parameters"
	)
	if not passive_parameters_error.is_empty():
		return passive_parameters_error
	var skill_error := _skill_error(source["character_skill"])
	if not skill_error.is_empty():
		return skill_error
	var mastery_error := _mastery_error(source["weapon_mastery"], str(source["id"]))
	if not mastery_error.is_empty():
		return mastery_error
	var time_error := _time_interactions_error(source["time_interactions"])
	if not time_error.is_empty():
		return time_error
	var presentation_error := _presentation_error(source["presentation"])
	if not presentation_error.is_empty():
		return presentation_error
	var capabilities_error := _string_list_error(source["capabilities"], [], false, "capabilities")
	if not capabilities_error.is_empty():
		return capabilities_error
	var talent_error := _string_list_error(source["talent_ids"], TALENT_IDS, true, "talent_ids")
	if not talent_error.is_empty():
		return talent_error
	var handler_identity_error := _handler_identity_error(source)
	if not handler_identity_error.is_empty():
		return handler_identity_error

	var normalized := source.duplicate(true)
	for field: String in ["availability", "tags", "references", "capabilities"]:
		var values: Array = normalized[field]
		values.sort()
		normalized[field] = values
	var compatibility: Dictionary = normalized["compatibility"]
	for field_value: Variant in compatibility.keys():
		var values: Array = compatibility[field_value]
		values.sort()
		compatibility[field_value] = values
	normalized["compatibility"] = compatibility
	return {"ok": true, "profile": normalized, "context": {}}


func _identity_error(source: Dictionary) -> Dictionary:
	var profile_id := str(source["id"])
	var character_id := str(source["character_id"])
	if not profile_id.begins_with("%s_" % character_id):
		return _failure("character_id", "profile_identity_mismatch")
	var expected_runtime := "wanderer_m1_compat" if profile_id == "wanderer_m1_v1" else character_id
	if str(source["runtime_kind"]) != expected_runtime:
		return _failure("runtime_kind", "character_mismatch")
	var availability: Array = source["availability"]
	var expected_availability := (
		["M1", "CURRENT", "NEXT"]
		if profile_id == "wanderer_m1_v1"
		else ["LAUNCH", "EXPANSION"]
	)
	if _sorted_strings(availability) != _sorted_strings(expected_availability):
		return _failure("availability", "profile_milestone_boundary")
	var references: Array = source["references"]
	var allowed_weapons: Array[String] = []
	allowed_weapons.append_array(["sword", "bow"] if profile_id == "wanderer_m1_v1" else WEAPON_IDS)
	for required_id: String in [character_id] + allowed_weapons + TIME_ABILITY_IDS:
		if not references.has(required_id):
			return _failure("references", "coverage_missing", {"reference_id": required_id})
	for talent_id_value: Variant in source["talent_ids"]:
		var talent_id := str(talent_id_value)
		if not references.has(talent_id):
			return _failure("references", "talent_reference_missing", {"reference_id": talent_id})
	if profile_id == "wanderer_m1_v1":
		for launch_only_weapon: String in ["gun", "staff", "gauntlets"]:
			if references.has(launch_only_weapon):
				return _failure("references", "m1_surface_widening", {"reference_id": launch_only_weapon})
	var compatibility: Dictionary = source["compatibility"]
	if compatibility.has("character_ids") and not (compatibility["character_ids"] as Array).has(character_id):
		return _failure("compatibility.character_ids", "character_missing")
	return {}


func _handler_identity_error(source: Dictionary) -> Dictionary:
	var profile_id := str(source["id"])
	var character_id := str(source["character_id"])
	if profile_id == "wanderer_m1_v1":
		var m1_resource: Dictionary = source["resource"]
		if str(m1_resource.get("resource_id", "")) != "none" or str(m1_resource.get("handler_id", "")) != "none":
			return _failure("resource", "m1_surface_widening")
		for field: String in ["minimum", "maximum", "initial", "gain_cap_per_action"]:
			if not _is_finite_number(m1_resource.get(field)) or float(m1_resource[field]) != 0.0:
				return _failure("resource.%s" % field, "m1_surface_widening")
		if str(source["passive"].get("handler_id", "")) != "none":
			return _failure("passive.handler_id", "m1_surface_widening")
		var m1_skill: Dictionary = source["character_skill"]
		if str(m1_skill.get("skill_id", "")) != "none" or str(m1_skill.get("handler_id", "")) != "none":
			return _failure("character_skill.handler_id", "m1_surface_widening")
		for field: String in ["cooldown_frames", "energy_cost", "hold_threshold_frames"]:
			if not _is_finite_number(m1_skill.get(field)) or float(m1_skill[field]) != 0.0:
				return _failure("character_skill.%s" % field, "m1_surface_widening")
		for mastery_value: Variant in (source["weapon_mastery"] as Dictionary).values():
			if not mastery_value is Dictionary or str((mastery_value as Dictionary).get("handler_id", "")) != "none":
				return _failure("weapon_mastery", "m1_surface_widening")
		for interaction_value: Variant in (source["time_interactions"] as Dictionary).values():
			if not interaction_value is Dictionary or str((interaction_value as Dictionary).get("handler_id", "")) != "none":
				return _failure("time_interactions", "m1_surface_widening")
		if source["presentation"] != {"palette_id": "wanderer", "meter_id": "none", "skill_cue_id": "none"}:
			return _failure("presentation", "m1_surface_widening")
		if _sorted_strings(source["capabilities"]) != ["character.m1_parity"]:
			return _failure("capabilities", "m1_surface_widening")
		return _exact_talents_error(
			source["talent_ids"],
			["tal_eternity_reserve", "tal_ruin_execute", "tal_steel_recover"]
		)

	var expected_resource := ""
	var expected_passive := ""
	var expected_skill := ""
	var expected_mastery := "%s_mastery" % character_id
	var expected_talents: Array[String] = []
	match character_id:
		"wanderer":
			expected_resource = "path_marks"
			expected_passive = "wanderer_path"
			expected_skill = "waypoint_recall"
			expected_talents.append_array(["tal_eternity_reserve", "tal_ruin_execute", "tal_steel_recover"])
		"time_guardian":
			expected_resource = "ward"
			expected_passive = "chrono_bulwark"
			expected_skill = "chrono_fortress"
			expected_talents.append_array(["widened_guard", "fortress_core", "temporal_rebuke"])
		"void_walker":
			expected_resource = "void_debt"
			expected_passive = "void_debt"
			expected_skill = "void_devour"
			expected_talents.append_array(["deep_debt", "bounded_devour", "risk_step"])
		"primordial_knight":
			expected_resource = "resonance"
			expected_passive = "planar_resonance"
			expected_skill = "realm_cleave"
			expected_talents.append_array(["resonant_plate", "echo_forge", "realm_collapse"])
		"time_lord":
			expected_resource = "codex_pages"
			expected_passive = "chrono_codex"
			expected_skill = "codex_dominion"
			expected_talents.append_array(["codex_margin", "efficient_inscription", "dominion_cadence"])
		_:
			return _failure("character_id", "unsupported")
	var resource: Dictionary = source["resource"]
	if str(resource.get("resource_id", "")) != expected_resource or str(resource.get("handler_id", "")) != expected_resource:
		return _failure("resource", "character_handler_mismatch")
	if str(source["passive"].get("handler_id", "")) != expected_passive:
		return _failure("passive.handler_id", "character_handler_mismatch")
	if str(source["character_skill"].get("skill_id", "")) != expected_skill or str(source["character_skill"].get("handler_id", "")) != expected_skill:
		return _failure("character_skill", "character_handler_mismatch")
	for mastery_value: Variant in (source["weapon_mastery"] as Dictionary).values():
		if not mastery_value is Dictionary or str((mastery_value as Dictionary).get("handler_id", "")) != expected_mastery:
			return _failure("weapon_mastery", "character_handler_mismatch")
	for ability_id: String in TIME_ABILITY_IDS:
		var expected_time_handler := "%s_%s" % [character_id, ability_id]
		if str(source["time_interactions"][ability_id].get("handler_id", "")) != expected_time_handler:
			return _failure("time_interactions.%s.handler_id" % ability_id, "character_handler_mismatch")
	var presentation: Dictionary = source["presentation"]
	if (
		str(presentation.get("palette_id", "")) != character_id
		or str(presentation.get("meter_id", "")) != expected_resource
		or str(presentation.get("skill_cue_id", "")) != expected_skill
	):
		return _failure("presentation", "character_handler_mismatch")
	return _exact_talents_error(source["talent_ids"], expected_talents)


func _exact_talents_error(value: Array, expected: Array[String]) -> Dictionary:
	var actual: Array[String] = []
	for talent_id: Variant in value:
		actual.append(str(talent_id))
	if actual != expected:
		return _failure("talent_ids", "character_talent_mismatch")
	return {}


func _base_stats_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("base_stats", "type")
	var stats: Dictionary = value
	var fields_error := _exact_fields_error(stats, BASE_STAT_FIELDS, "base_stats")
	if not fields_error.is_empty():
		return fields_error
	for field: String in BASE_STAT_FIELDS:
		if not _is_finite_number(stats[field]):
			return _failure("base_stats.%s" % field, "expected_finite_number")
	for field: String in [
		"max_hp", "attack", "move_speed", "attack_speed", "crit_multiplier", "time_energy_max",
	]:
		if float(stats[field]) <= 0.0:
			return _failure("base_stats.%s" % field, "expected_positive")
	for field: String in ["defense", "time_energy_regen"]:
		if float(stats[field]) < 0.0:
			return _failure("base_stats.%s" % field, "expected_non_negative")
	var critical_chance := float(stats["crit_chance"])
	if critical_chance < 0.0 or critical_chance > 1.0:
		return _failure("base_stats.crit_chance", "out_of_range")
	return {}


func _mobility_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("mobility", "type")
	var mobility: Dictionary = value
	var fields_error := _exact_fields_error(mobility, MOBILITY_FIELDS, "mobility")
	if not fields_error.is_empty():
		return fields_error
	for field: String in ["dash_duration_frames", "dash_cooldown_frames", "dash_invulnerable_frames"]:
		if not _is_positive_integer(mobility[field]):
			return _failure("mobility.%s" % field, "expected_positive_integer")
	if int(mobility["dash_invulnerable_frames"]) > int(mobility["dash_duration_frames"]):
		return _failure("mobility.dash_invulnerable_frames", "exceeds_duration")
	if not _is_finite_number(mobility["dash_speed"]) or float(mobility["dash_speed"]) <= 0.0:
		return _failure("mobility.dash_speed", "expected_positive")
	if mobility["dash_cost_kind"] != "none":
		return _failure("mobility.dash_cost_kind", "unsupported")
	if not _is_finite_number(mobility["dash_cost"]) or float(mobility["dash_cost"]) != 0.0:
		return _failure("mobility.dash_cost", "must_be_zero")
	return {}


func _resource_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("resource", "type")
	var resource: Dictionary = value
	var fields_error := _exact_fields_error(resource, RESOURCE_FIELDS, "resource")
	if not fields_error.is_empty():
		return fields_error
	if not _matches(ID_PATTERN, resource["resource_id"]):
		return _failure("resource.resource_id", "invalid")
	if typeof(resource["handler_id"]) != TYPE_STRING or not RESOURCE_HANDLERS.has(str(resource["handler_id"])):
		return _failure("resource.handler_id", "unknown_handler")
	for field: String in ["minimum", "maximum", "initial", "gain_cap_per_action"]:
		if not _is_finite_number(resource[field]):
			return _failure("resource.%s" % field, "expected_finite_number")
	var minimum := float(resource["minimum"])
	var maximum := float(resource["maximum"])
	var initial := float(resource["initial"])
	if minimum < 0.0 or maximum < minimum or initial < minimum or initial > maximum:
		return _failure("resource", "invalid_bounds")
	if float(resource["gain_cap_per_action"]) < 0.0:
		return _failure("resource.gain_cap_per_action", "expected_non_negative")
	return {}


func _skill_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("character_skill", "type")
	var skill: Dictionary = value
	var fields_error := _exact_fields_error(skill, SKILL_FIELDS, "character_skill")
	if not fields_error.is_empty():
		return fields_error
	if not _matches(ID_PATTERN, skill["skill_id"]):
		return _failure("character_skill.skill_id", "invalid")
	if typeof(skill["handler_id"]) != TYPE_STRING or not SKILL_HANDLERS.has(str(skill["handler_id"])):
		return _failure("character_skill.handler_id", "unknown_handler")
	for field: String in ["cooldown_frames", "hold_threshold_frames"]:
		if not _is_non_negative_integer(skill[field]):
			return _failure("character_skill.%s" % field, "expected_non_negative_integer")
	if not _is_finite_number(skill["energy_cost"]) or float(skill["energy_cost"]) < 0.0:
		return _failure("character_skill.energy_cost", "expected_non_negative")
	var parameters_error := _parameters_error(skill["parameters"], "character_skill.parameters")
	if not parameters_error.is_empty():
		return parameters_error
	var contract_error := _closed_parameters_error(
		skill["parameters"],
		SKILL_PARAMETER_CONTRACTS[str(skill["handler_id"])],
		"character_skill.parameters"
	)
	if not contract_error.is_empty():
		return contract_error
	if str(skill["handler_id"]) == "none" and str(skill["skill_id"]) != "none":
		return _failure("character_skill.skill_id", "none_handler_requires_none_skill")
	return {}


func _mastery_error(value: Variant, profile_id: String) -> Dictionary:
	if not value is Dictionary:
		return _failure("weapon_mastery", "type")
	var mastery: Dictionary = value
	var expected_weapons: Array[String] = []
	expected_weapons.append_array(["sword", "bow"] if profile_id == "wanderer_m1_v1" else WEAPON_IDS)
	var fields_error := _exact_fields_error(mastery, expected_weapons, "weapon_mastery")
	if not fields_error.is_empty():
		return fields_error
	for weapon_id: String in expected_weapons:
		var descriptor_value: Variant = mastery[weapon_id]
		if not descriptor_value is Dictionary:
			return _failure("weapon_mastery.%s" % weapon_id, "type")
		var descriptor: Dictionary = descriptor_value
		var descriptor_error := _exact_fields_error(
			descriptor, MASTERY_FIELDS, "weapon_mastery.%s" % weapon_id
		)
		if not descriptor_error.is_empty():
			return descriptor_error
		if typeof(descriptor["handler_id"]) != TYPE_STRING or not MASTERY_HANDLERS.has(str(descriptor["handler_id"])):
			return _failure("weapon_mastery.%s.handler_id" % weapon_id, "unknown_handler")
		if descriptor["mastery_family"] != weapon_id:
			return _failure("weapon_mastery.%s.mastery_family" % weapon_id, "weapon_mismatch")
		var parameters_error := _parameters_error(
			descriptor["parameters"], "weapon_mastery.%s.parameters" % weapon_id
		)
		if not parameters_error.is_empty():
			return parameters_error
		var expected_parameters: Dictionary = {}
		var handler_id := str(descriptor["handler_id"])
		if handler_id == "primordial_knight_mastery":
			expected_parameters = PRIMORDIAL_MASTERY_PARAMETER_CONTRACTS[weapon_id]
		elif EMPTY_MASTERY_PARAMETER_HANDLERS.has(handler_id):
			expected_parameters = {}
		else:
			return _failure("weapon_mastery.%s.handler_id" % weapon_id, "unknown_handler")
		var contract_error := _closed_parameters_error(
			descriptor["parameters"],
			expected_parameters,
			"weapon_mastery.%s.parameters" % weapon_id
		)
		if not contract_error.is_empty():
			return contract_error
	return {}


func _time_interactions_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("time_interactions", "type")
	var interactions: Dictionary = value
	var fields_error := _exact_fields_error(interactions, TIME_ABILITY_IDS, "time_interactions")
	if not fields_error.is_empty():
		return fields_error
	for ability_id: String in TIME_ABILITY_IDS:
		var descriptor_error := _handler_descriptor_error(
			interactions[ability_id], TIME_INTERACTION_FIELDS, TIME_HANDLERS,
			"time_interactions.%s" % ability_id
		)
		if not descriptor_error.is_empty():
			return descriptor_error
		var descriptor: Dictionary = interactions[ability_id]
		var contract_error := _closed_parameters_error(
			descriptor["parameters"],
			TIME_PARAMETER_CONTRACTS[str(descriptor["handler_id"])],
			"time_interactions.%s.parameters" % ability_id
		)
		if not contract_error.is_empty():
			return contract_error
	return {}


func _presentation_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("presentation", "type")
	var presentation: Dictionary = value
	var fields_error := _exact_fields_error(presentation, PRESENTATION_FIELDS, "presentation")
	if not fields_error.is_empty():
		return fields_error
	for field_and_allowed: Array in [
		["palette_id", PALETTE_IDS], ["meter_id", METER_IDS], ["skill_cue_id", CUE_IDS],
	]:
		var field := str(field_and_allowed[0])
		var allowed: Array = field_and_allowed[1]
		if typeof(presentation[field]) != TYPE_STRING or not allowed.has(str(presentation[field])):
			return _failure("presentation.%s" % field, "unknown_handler")
	return {}


func _handler_descriptor_error(
	value: Variant,
	fields: Array[String],
	allowed_handlers: Array[String],
	path: String
) -> Dictionary:
	if not value is Dictionary:
		return _failure(path, "type")
	var descriptor: Dictionary = value
	var fields_error := _exact_fields_error(descriptor, fields, path)
	if not fields_error.is_empty():
		return fields_error
	if typeof(descriptor["handler_id"]) != TYPE_STRING or not allowed_handlers.has(str(descriptor["handler_id"])):
		return _failure("%s.handler_id" % path, "unknown_handler")
	return _parameters_error(descriptor["parameters"], "%s.parameters" % path)


func _compatibility_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("compatibility", "type")
	var compatibility: Dictionary = value
	for field_value: Variant in compatibility.keys():
		var field := str(field_value)
		if not COMPATIBILITY_FIELDS.has(field):
			return _failure("compatibility.%s" % field, "unknown")
		if field in ["archetype_ids", "modes"]:
			return _failure("compatibility.%s" % field, "unsupported_constraint")
		var allowed_values: Array[String] = []
		match field:
			"character_ids":
				allowed_values.append_array(CHARACTER_IDS)
			"weapon_ids":
				allowed_values.append_array(WEAPON_IDS)
			"time_ability_ids":
				allowed_values.append_array(TIME_ABILITY_IDS)
		var list_error := _string_list_error(
			compatibility[field_value], allowed_values, false, "compatibility.%s" % field
		)
		if not list_error.is_empty():
			return list_error
	return {}


func _closed_parameters_error(value: Variant, expected: Dictionary, path: String) -> Dictionary:
	var safety_error := _parameters_error(value, path, 0)
	if not safety_error.is_empty():
		return safety_error
	var actual: Dictionary = value
	var fields_error := _exact_fields_error(actual, _string_keys(expected), path)
	if not fields_error.is_empty():
		return fields_error
	for field_value: Variant in expected.keys():
		var field := str(field_value)
		var value_error := _exact_parameter_value_error(actual[field], expected[field_value], "%s.%s" % [path, field])
		if not value_error.is_empty():
			return value_error
	return {}


func _exact_parameter_value_error(actual: Variant, expected: Variant, path: String) -> Dictionary:
	match typeof(expected):
		TYPE_BOOL:
			if typeof(actual) != TYPE_BOOL or bool(actual) != bool(expected):
				return _failure(path, "expected_exact_boolean")
		TYPE_INT:
			if not _is_non_negative_integer(actual) or int(actual) != int(expected):
				return _failure(path, "expected_exact_integer")
		TYPE_FLOAT:
			if not _is_finite_number(actual) or float(actual) != float(expected):
				return _failure(path, "expected_exact_number")
		TYPE_STRING:
			if typeof(actual) != TYPE_STRING or str(actual) != str(expected):
				return _failure(path, "expected_exact_string")
		_:
			return _failure(path, "unsupported_contract_type")
	return {}


func _string_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	return keys


func _parameters_error(value: Variant, path: String, depth: int = 0) -> Dictionary:
	if depth > MAX_PARAMETER_DEPTH:
		return _failure(path, "maximum_depth_exceeded")
	if not value is Dictionary:
		return _failure(path, "type")
	for key_value: Variant in (value as Dictionary).keys():
		if typeof(key_value) != TYPE_STRING or not _matches(PARAMETER_KEY_PATTERN, key_value):
			return _failure(path, "invalid_key")
		var key := str(key_value).to_lower()
		for fragment: String in EXECUTION_KEY_FRAGMENTS:
			if key.contains(fragment):
				return _failure("%s.%s" % [path, str(key_value)], "executable_key")
		if not _parameter_value_is_valid((value as Dictionary)[key_value], depth + 1):
			return _failure("%s.%s" % [path, str(key_value)], "invalid_value")
	return {}


func _parameter_value_is_valid(value: Variant, depth: int) -> bool:
	if depth > MAX_PARAMETER_DEPTH:
		return false
	if typeof(value) in [TYPE_BOOL, TYPE_STRING]:
		return true
	if _is_finite_number(value):
		return true
	if value is Array:
		for nested: Variant in value:
			if not _parameter_value_is_valid(nested, depth + 1):
				return false
		return true
	if value is Dictionary:
		var nested_error := _parameters_error(value, "parameters", depth)
		return nested_error.is_empty()
	return false


func _exact_fields_error(value: Dictionary, fields: Array[String], path: String) -> Dictionary:
	for field: String in fields:
		if not value.has(field):
			return _failure("%s.%s" % [path, field], "missing")
	for field_value: Variant in value.keys():
		var field := str(field_value)
		if not fields.has(field):
			return _failure("%s.%s" % [path, field], "unknown")
	return {}


func _string_list_error(
	value: Variant,
	allowed: Array[String],
	allow_empty: bool,
	path: String
) -> Dictionary:
	if not value is Array:
		return _failure(path, "type")
	if not allow_empty and (value as Array).is_empty():
		return _failure(path, "empty")
	var seen: Dictionary = {}
	for item: Variant in value:
		if typeof(item) != TYPE_STRING:
			return _failure(path, "invalid_entry")
		var item_id := str(item)
		if allowed.is_empty() and not _matches(ID_PATTERN, item_id):
			return _failure(path, "invalid_entry")
		if not allowed.is_empty() and not allowed.has(item_id):
			return _failure(path, "unknown_entry", {"value": item_id})
		if seen.has(item_id):
			return _failure(path, "duplicate")
		seen[item_id] = true
	return {}


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _is_positive_integer(value: Variant) -> bool:
	return _is_non_negative_integer(value) and int(value) > 0


func _is_non_negative_integer(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == floorf(float(value)) and int(value) >= 0


func _failure(field: String, reason: String, extra: Dictionary = {}) -> Dictionary:
	var context := {"field": field, "reason": reason}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	return {"ok": false, "profile": {}, "context": context}
