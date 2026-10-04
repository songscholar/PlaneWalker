class_name LaunchElementalStatusRuntime
extends "res://scripts/combat/elemental_status_runtime.gd"

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const FIELDS: Array[String] = ["schema_version", "seed", "slow_floor", "attack_slow_floor", "entries"]
const ENTRY_FIELDS: Array[String] = ["key", "effect_id", "source_id", "generation", "remaining_frames", "elapsed_frames", "magnitude", "attack_speed_multiplier", "tick_interval_frames", "damage_source", "damage_attacker"]


func transaction_snapshot() -> Dictionary:
	return {"schema_version": 1, "seed": _deterministic_seed, "slow_floor": _slow_floor_multiplier, "attack_slow_floor": _attack_slow_floor_multiplier, "entries": _entries.duplicate(true)}


func can_restore_transaction_snapshot(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or typeof(value.seed) != TYPE_INT:
		return false
	if not Contract.number_in_range(value.slow_floor, 0.1, 1.0) or not Contract.number_in_range(value.attack_slow_floor, 0.1, 1.0) or not value.entries is Dictionary:
		return false
	for key: Variant in value.entries:
		var candidate: Variant = value.entries[key]
		if typeof(key) != TYPE_STRING or not candidate is Dictionary or not Contract.exact_fields(candidate, ENTRY_FIELDS):
			return false
		var row := candidate as Dictionary
		if typeof(row.effect_id) not in [TYPE_STRING, TYPE_STRING_NAME] or typeof(row.source_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		for field: String in ["generation", "remaining_frames", "elapsed_frames", "tick_interval_frames"]:
			if typeof(row[field]) != TYPE_INT:
				return false
		if row.elapsed_frames < 0 or not _is_valid_application(StringName(row.effect_id), StringName(row.source_id), row.generation, row.remaining_frames, row.magnitude, maxi(1, int(row.tick_interval_frames)), row.attack_speed_multiplier):
			return false
		if row.key != key or key != _status_key(StringName(row.effect_id), StringName(row.source_id), row.generation):
			return false
		if str(row.effect_id) == "burn":
			if row.tick_interval_frames <= 0 or not _valid_node(row.damage_source) or not _valid_node(row.damage_attacker):
				return false
		elif row.tick_interval_frames != 0 or row.damage_source != null or row.damage_attacker != null:
			return false
	return true


func restore_transaction_snapshot(value: Dictionary) -> bool:
	if not can_restore_transaction_snapshot(value):
		return false
	_deterministic_seed = value.seed
	_slow_floor_multiplier = float(value.slow_floor)
	_attack_slow_floor_multiplier = float(value.attack_slow_floor)
	_entries = value.entries.duplicate(true)
	return true


static func _valid_node(value: Variant) -> bool:
	return value == null or (value is Node and is_instance_valid(value))
