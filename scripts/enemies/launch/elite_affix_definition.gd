class_name EliteAffixDefinition
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
const FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references",
	"runtime_kind", "minimum_floor", "maximum_floor", "excluded_affix_ids", "excluded_enemy_ids", "parameters", "cue_id",
]
const PARAMETERS := {
  "frenzy": {
    "damage_multiplier": 1.25,
    "speed_multiplier": 1.15,
    "damage_taken_multiplier": 1.2
  },
  "fortified": {
    "hp_multiplier": 1.5,
    "knockback_resistance_bonus": 0.2,
    "knockback_resistance_cap": 0.9,
    "speed_multiplier": 0.8
  },
  "regenerating": {
    "interval_frames": 120,
    "heal_fraction": 0.03,
    "total_heal_fraction_cap": 0.3,
    "heavy_interrupt_frames": 120
  },
  "teleporting": {
    "interval_frames": 480,
    "distance_min_px": 48,
    "distance_max_px": 80,
    "departure_warning_frames": 30,
    "arrival_recovery_frames": 30
  },
  "splitting": {
    "child_count": 2,
    "child_hp_fraction": 0.33,
    "lifetime_frames": 480,
    "spawn_warning_frames": 30,
    "once_only": true,
    "reward_eligible": false
  },
  "shielded": {
    "shield_fraction": 0.3,
    "regeneration_delay_frames": 1200,
    "regeneration_count_cap": 1,
    "break_exposure_frames": 45
  },
  "nullified": {
    "stop_delay_frames": 30,
    "stop_vulnerability_frames": 30,
    "rift_movement_floor": 0.7,
    "time_damage_retained": true,
    "echo_interactions_retained": true
  },
  "anchored": {
    "displacement_multiplier": 0,
    "control_poise": 20,
    "poise_threshold": 100,
    "recovery_extension_frames": 20,
    "stop_rift_retained": true
  },
  "chaining": {
    "recipient_count_cap": 2,
    "recipient_radius_px": 96,
    "attack_multiplier": 1.15,
    "buff_frames": 90,
    "cooldown_frames": 120,
    "strongest_only": true
  },
  "mirroring": {
    "interval_frames": 900,
    "spawn_warning_frames": 40,
    "definition_id": "elite_mirror",
    "lifetime_frames": 480,
    "alive_count_cap": 1
  }
}

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	if not Action.exact_fields(source, FIELDS):
		return Contract.failure("affix", "exact_fields_required")
	var common := Contract.common(source, "elite_affix_definition", Ids.AFFIX_IDS)
	if not common.ok:
		return common
	var result: Dictionary = common.definition
	var minimum: int = Rules.MIN_FLOORS[result.id]
	if typeof(result.runtime_kind) != TYPE_STRING or result.runtime_kind != result.id:
		return Contract.failure("runtime_kind", "identity_mismatch")
	if not Action.integer_in_range(source.minimum_floor, minimum, minimum) or not Action.integer_in_range(source.maximum_floor, 5, 5):
		return Contract.failure("minimum_floor", "identity_mismatch")
	if not source.compatibility is Dictionary or not Action.exact_fields(source.compatibility, ["floor_ids", "actor_kinds"]):
		return Contract.failure("compatibility", "exact_fields_required")
	if source.compatibility.floor_ids != Ids.FLOOR_IDS.slice(minimum - 1) or source.compatibility.actor_kinds != ["elite"]:
		return Contract.failure("compatibility", "identity_mismatch")
	var excluded := Contract.string_list(source.excluded_affix_ids, Ids.AFFIX_IDS, 1, 2, "excluded_affix_ids")
	if not excluded.ok:
		return excluded
	var expected: Array = Rules.EXCLUSIONS[result.id].duplicate()
	expected.sort()
	if excluded.value != expected:
		return Contract.failure("excluded_affix_ids", "symmetric_exclusions_required")
	var enemy_exclusions := Contract.string_list(source.excluded_enemy_ids, Ids.enemy_ids(), 0, 22, "excluded_enemy_ids")
	if not enemy_exclusions.ok:
		return enemy_exclusions
	var expected_enemies: Array = Rules.CHILD_OWNER_IDS.duplicate() if result.id in ["splitting", "mirroring"] else []
	expected_enemies.sort()
	if enemy_exclusions.value != expected_enemies:
		return Contract.failure("excluded_enemy_ids", "nonrecursive_species_required")
	if typeof(source.cue_id) != TYPE_STRING or source.cue_id != "affix_" + result.id:
		return Contract.failure("cue_id", "identity_mismatch")
	var parameters := _parameters(source.parameters, PARAMETERS[result.id])
	if not parameters.ok:
		return parameters
	var expected_references := ["elite_mirror"] if result.id == "mirroring" else []
	if result.references != expected_references:
		return Contract.failure("references", "identity_mismatch")
	result.minimum_floor = minimum
	result.maximum_floor = 5
	result.excluded_affix_ids = excluded.value
	result.excluded_enemy_ids = enemy_exclusions.value
	result.parameters = parameters.value
	_snapshot = result.duplicate(true)
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _parameters(value: Variant, expected: Dictionary) -> Dictionary:
	if not value is Dictionary or not Action.exact_fields(value, expected.keys()):
		return Contract.failure("parameters", "exact_fields_required")
	var result: Dictionary = {}
	for field: String in expected:
		var authored: Variant = expected[field]
		var actual: Variant = value[field]
		if typeof(authored) in [TYPE_BOOL, TYPE_STRING]:
			if typeof(actual) != typeof(authored) or actual != authored:
				return Contract.failure("parameters." + field, "invalid_value")
			result[field] = actual
		elif typeof(authored) == TYPE_INT:
			if not Action.integer_in_range(actual, authored, authored):
				return Contract.failure("parameters." + field, "invalid_integer")
			result[field] = int(actual)
		else:
			if not Action.number_in_range(actual, authored, authored):
				return Contract.failure("parameters." + field, "invalid_number")
			result[field] = float(actual)
	return {"ok": true, "value": result}
